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

if [[ -d /opt/Marzban ]]; then
echo -e "${RED}/opt/Marzban уже существует${RESET}"
exit 1
fi

git clone https://github.com/Gozargah/Marzban

cd Marzban || exit 1

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

echo -e "${GREEN}Панель установлена${RESET}"
echo "https://$DOMAIN/dashboard"

}

remove_panel(){

require_root

echo -e "${RED}Удаление панели...${RESET}"

if [[ -d /opt/Marzban ]]; then
cd /opt/Marzban || exit 1
"${DC[@]}" down
else
echo "Директория /opt/Marzban не найдена, пропускаю docker compose down"
fi

rm -rf /opt/Marzban

rm -f /etc/nginx/sites-enabled/marzban
rm -f /etc/nginx/sites-available/marzban

systemctl restart nginx

echo "Панель удалена"

}

update_xray(){

echo "Обновление Xray"

read -r -p "Имя контейнера ноды: " CONTAINER

VERSION="26.2.6"

docker exec "$CONTAINER" bash -c "
cd /tmp &&
apt update -y >/dev/null &&
apt install -y wget unzip >/dev/null &&
wget -q https://github.com/XTLS/Xray-core/releases/download/v$VERSION/Xray-linux-64.zip &&
unzip -o Xray-linux-64.zip &&
mv xray /usr/local/bin/xray &&
chmod +x /usr/local/bin/xray
"

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
echo "docker run -d \\"
echo "--name marzban-node \\"
echo "--restart always \\"
echo "--network host \\"
echo "-v /var/lib/marzban-node:/var/lib/marzban-node \\"
echo "-e SERVICE_PROTOCOL=rest \\"
echo "-e SSL_CLIENT_CERT_FILE=/var/lib/marzban-node/client.pem \\"
echo "gozargah/marzban-node:latest"

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

case $option in

1) install_panel ;;
2) remove_panel ;;
3) update_xray ;;
4) install_node ;;
5) remove_node ;;
0) exit ;;

*) echo "Неверный выбор" ;;

esac
