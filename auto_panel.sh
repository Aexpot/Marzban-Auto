#!/bin/bash

set -Eeuo pipefail

if [[ -t 1 ]] && [[ -n "${TERM:-}" ]]; then
clear
fi

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"
MARZBAN_DIR="/opt/Marzban"
BACKUP_DIR="/root/marzban-backups"

echo -e "${CYAN}"
echo "================================"
echo "        MARZBAN MANAGER"
echo "================================"
echo "        By Aexpot"
echo "  https://github.com/Aexpot"
echo "================================"
echo -e "${RESET}"

echo "1) Установить панель Marzban"
echo "2) Удалить панель Marzban"
echo "3) Обновить Xray core на ноде"
echo "4) Установить Marzban Node"
echo "5) Удалить Marzban Node"
echo "6) Статус панели"
echo "7) Обновить панель Marzban"
echo "0) Выход"
echo ""

read -r -p "Выберите действие: " option

if command -v docker-compose &> /dev/null
then
	DC=(docker-compose)
else
	DC=(docker compose)
fi

require_root(){

if [[ $EUID -ne 0 ]]; then
echo -e "${RED}Запустите скрипт от root или через sudo${RESET}"
exit 1
fi

}

require_marzban_dir(){

if [[ ! -d "$MARZBAN_DIR" ]]; then
echo -e "${RED}Директория $MARZBAN_DIR не найдена${RESET}"
exit 1
fi

}

create_panel_backup(){

require_root

mkdir -p "$BACKUP_DIR"

local timestamp
timestamp=$(date +%Y%m%d-%H%M%S)

local backup_file="$BACKUP_DIR/marzban-$timestamp.tar.gz"
local paths=()

[[ -d "$MARZBAN_DIR" ]] && paths+=("$MARZBAN_DIR")
[[ -d /var/lib/marzban ]] && paths+=("/var/lib/marzban")
[[ -f /etc/nginx/sites-available/marzban ]] && paths+=("/etc/nginx/sites-available/marzban")

if [[ ${#paths[@]} -eq 0 ]]; then
echo "Нет файлов для backup"
return 0
fi

tar -czf "$backup_file" "${paths[@]}"
echo -e "${GREEN}Backup создан: $backup_file${RESET}"

}

create_admin(){

require_root
require_marzban_dir

read -r -p "Создать sudo admin-пользователя? [y/N]: " CREATE_ADMIN

case "$CREATE_ADMIN" in
y|Y|yes|YES|д|Д|да|ДА)
read -r -p "Логин admin: " ADMIN_USER
read -r -s -p "Пароль admin: " ADMIN_PASS
echo ""

cd "$MARZBAN_DIR" || exit 1

if ! "${DC[@]}" exec -T -e "MARZBAN_ADMIN_PASSWORD=$ADMIN_PASS" marzban marzban cli admin create -u "$ADMIN_USER" --sudo; then
"${DC[@]}" exec -T -e "MARZBAN_ADMIN_PASSWORD=$ADMIN_PASS" marzban marzban-cli admin create -u "$ADMIN_USER" --sudo
fi

echo -e "${GREEN}Admin создан${RESET}"
;;
*)
echo "Создание admin пропущено"
;;
esac

}

install_panel(){

require_root

echo -e "${YELLOW}Установка панели...${RESET}"

read -r -p "Домен панели: " DOMAIN
read -r -p "Email SSL: " EMAIL

apt update -y
apt install -y curl git docker.io nginx certbot python3-certbot-nginx

systemctl enable docker
systemctl start docker

cd /opt || exit 1

if [[ -d "$MARZBAN_DIR" ]]; then
echo -e "${RED}$MARZBAN_DIR уже существует${RESET}"
exit 1
fi

git clone https://github.com/Gozargah/Marzban

cd "$MARZBAN_DIR" || exit 1
cp .env.example .env

"${DC[@]}" up -d

sleep 10

cat > /etc/nginx/sites-available/marzban <<EOF
server {

server_name $DOMAIN;

location / {

proxy_pass http://127.0.0.1:8000;

proxy_http_version 1.1;

proxy_set_header Upgrade \$http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host \$host;

}

}
EOF

ln -sf /etc/nginx/sites-available/marzban /etc/nginx/sites-enabled/

systemctl restart nginx

certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect

create_admin

echo -e "${GREEN}Панель установлена${RESET}"
echo "https://$DOMAIN/dashboard"

}

remove_panel(){

require_root

echo -e "${RED}Удаление панели...${RESET}"

if [[ -d "$MARZBAN_DIR" ]]; then
cd "$MARZBAN_DIR" || exit 1
"${DC[@]}" down
else
echo "Директория $MARZBAN_DIR не найдена, пропускаю docker compose down"
fi

rm -rf "$MARZBAN_DIR"

rm -f /etc/nginx/sites-enabled/marzban
rm -f /etc/nginx/sites-available/marzban

systemctl restart nginx

echo "Панель удалена"

}

update_xray(){

echo "Обновление Xray"

read -r -p "Имя контейнера ноды: " CONTAINER
read -r -p "Версия Xray (latest или например 26.2.6) [latest]: " VERSION

VERSION=${VERSION:-latest}

local arch
case "$(uname -m)" in
x86_64|amd64) arch="64" ;;
aarch64|arm64) arch="arm64-v8a" ;;
armv7l|armv7) arch="arm32-v7a" ;;
*)
echo -e "${RED}Неподдерживаемая архитектура: $(uname -m)${RESET}"
exit 1
;;
esac

local url
if [[ "$VERSION" = "latest" ]]; then
url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$arch.zip"
else
VERSION=${VERSION#v}
url="https://github.com/XTLS/Xray-core/releases/download/v$VERSION/Xray-linux-$arch.zip"
fi

docker exec "$CONTAINER" bash -c '
set -e
cd /tmp
apt update -y >/dev/null
apt install -y wget unzip >/dev/null
wget -qO Xray-linux.zip "$1"
unzip -o Xray-linux.zip
mv xray /usr/local/bin/xray
chmod +x /usr/local/bin/xray
' _ "$url"

docker restart "$CONTAINER"

docker exec "$CONTAINER" xray version

echo "Xray обновлен"

}

install_node(){

require_root

echo "=== Установка ноды ==="

apt update -y
apt install -y curl jq

read -r -p "URL панели: " PANEL
PANEL=${PANEL%/}

read -r -p "Логин администратора: " USER
read -r -s -p "Пароль: " PASS
echo ""

echo "Получение API токена..."

TOKEN_RESPONSE=$(curl -sS -X POST "$PANEL/api/admin/token" \
	-H "Content-Type: application/x-www-form-urlencoded" \
	--data-urlencode "username=$USER" \
	--data-urlencode "password=$PASS")

TOKEN=$(echo "$TOKEN_RESPONSE" | jq -er '.access_token' 2>/dev/null || true)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
echo "Ошибка получения токена"
exit 1
fi

echo "Токен получен"

read -r -p "Имя ноды: " NODE_NAME
read -r -p "IP ноды: " NODE_IP

echo "Создание ноды..."

NODE_PAYLOAD=$(jq -n \
	--arg name "$NODE_NAME" \
	--arg address "$NODE_IP" \
	'{name:$name,address:$address,port:62050,api_port:62051,usage_coefficient:1}')

NODE=$(curl -sS -X POST "$PANEL/api/node" \
	-H "Authorization: Bearer $TOKEN" \
	-H "Content-Type: application/json" \
	-d "$NODE_PAYLOAD")

NODE_ID=$(echo "$NODE" | jq -er '.id' 2>/dev/null || true)

if [ -z "$NODE_ID" ] || [ "$NODE_ID" = "null" ]; then
echo "Ошибка создания ноды"
exit 1
fi

echo ""
echo "Нода создана!"
echo ""
echo "Теперь выполните эту команду на сервере ноды:"
echo ""

echo "mkdir -p /var/lib/marzban-node"
echo ""
cat <<'NODECMD'
docker run -d \
--name marzban-node \
--restart always \
--network host \
-v /var/lib/marzban-node:/var/lib/marzban-node \
-e SERVICE_PROTOCOL=rest \
-e SSL_CLIENT_CERT_FILE=/var/lib/marzban-node/client.pem \
gozargah/marzban-node:latest
NODECMD

echo ""
echo "После этого скачайте certificate в панели:"
echo ""
echo "Nodes → Download certificate"
echo ""
echo "И сохраните его в:"
echo ""
echo "/var/lib/marzban-node/client.pem"

}

remove_node(){

require_root

echo "Удаление ноды..."

if docker ps -a --format '{{.Names}}' | grep -Fxq marzban-node; then
docker rm -f marzban-node
else
echo "Контейнер marzban-node не найден"
fi

rm -rf /var/lib/marzban-node

echo "Нода удалена"

}

panel_status(){

echo "=== Статус Marzban ==="

echo ""
echo "Docker:"
if [[ -d /run/systemd/system ]]; then
systemctl is-active docker || true
else
echo "systemd недоступен"
fi

echo ""
echo "Nginx:"
if [[ -d /run/systemd/system ]]; then
systemctl is-active nginx || true
else
echo "systemd недоступен"
fi

echo ""
echo "Контейнеры:"
if docker info >/dev/null 2>&1; then
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' | grep -E 'NAMES|marzban|xray' || true
else
echo "Docker daemon недоступен"
fi

echo ""
echo "URL панели:"
if [[ -f /etc/nginx/sites-available/marzban ]]; then
local domain
domain=$(awk '/server_name/ {gsub(";", "", $2); print $2; exit}' /etc/nginx/sites-available/marzban)
if [[ -n "$domain" ]]; then
echo "https://$domain/dashboard"
else
echo "Домен не найден в nginx-конфиге"
fi
else
echo "nginx-конфиг Marzban не найден"
fi

echo ""
echo "Xray:"
local xray_container
if docker info >/dev/null 2>&1; then
xray_container=$(docker ps --format '{{.Names}}' | grep -E 'marzban-node|xray' | head -n1 || true)
else
xray_container=""
fi

if [[ -n "$xray_container" ]]; then
docker exec "$xray_container" xray version 2>/dev/null | head -n1 || echo "Xray не найден в контейнере $xray_container"
else
echo "Подходящий контейнер не найден"
fi

}

update_panel(){

require_root
require_marzban_dir

echo -e "${YELLOW}Обновление панели Marzban...${RESET}"

create_panel_backup

cd "$MARZBAN_DIR" || exit 1

git pull --ff-only
"${DC[@]}" pull
"${DC[@]}" up -d

if command -v nginx >/dev/null 2>&1; then
nginx -t
if [[ -d /run/systemd/system ]]; then
systemctl reload nginx
else
nginx -s reload
fi
fi

echo -e "${GREEN}Панель обновлена${RESET}"

}

case $option in

1) install_panel ;;
2) remove_panel ;;
3) update_xray ;;
4) install_node ;;
5) remove_node ;;
6) panel_status ;;
7) update_panel ;;
0) exit ;;

*) echo "Неверный выбор" ;;

esac
