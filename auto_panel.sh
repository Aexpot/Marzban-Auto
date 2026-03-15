#!/bin/bash

clear

echo "================================"
echo "        MARZBAN MANAGER"
echo "================================"
echo "1) Установить панель Marzban"
echo "2) Удалить панель Marzban"
echo "3) Обновить Xray core на ноде"
echo "4) Установить Marzban Node"
echo "0) Выход"
echo "================================"

read -p "Выберите действие: " option


install_marzban() {

echo "=== Установка Marzban ==="

read -p "Введите домен панели: " DOMAIN
read -p "Введите email для SSL: " EMAIL
read -p "Введите логин администратора: " ADMIN_USER
read -s -p "Введите пароль администратора: " ADMIN_PASS
echo ""

apt update -y
apt upgrade -y

apt install -y curl git docker.io docker-compose nginx certbot python3-certbot-nginx jq socat

systemctl enable docker
systemctl start docker

cd /opt

if [ ! -d "Marzban" ]; then
git clone https://github.com/Gozargah/Marzban.git
fi

cd Marzban

cp .env.example .env

echo "🚀 Запуск контейнера..."

docker-compose up -d

sleep 10

CONTAINER=$(docker ps --filter "ancestor=gozargah/marzban" --format "{{.Names}}")

if [ -z "$CONTAINER" ]; then
echo "❌ Контейнер не найден"
exit 1
fi

echo "Контейнер найден: $CONTAINER"

echo "👤 Создание администратора..."

docker exec -i $CONTAINER marzban-cli admin create <<EOF
$ADMIN_USER
$ADMIN_PASS
$ADMIN_PASS
EOF

echo "⚙ Настройка Nginx..."

cat > /etc/nginx/sites-available/marzban <<EOL
server {
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8000;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOL

ln -sf /etc/nginx/sites-available/marzban /etc/nginx/sites-enabled/

nginx -t
systemctl restart nginx

echo "🔐 Получение SSL..."

certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL --redirect

echo ""
echo "================================"
echo "✅ Установка завершена"
echo "🌐 Панель: https://$DOMAIN/dashboard"
echo "👤 Логин: $ADMIN_USER"
echo "================================"

}


remove_marzban() {

echo "🗑 Удаление Marzban..."

docker-compose -f /opt/Marzban/docker-compose.yml down 2>/dev/null

rm -rf /opt/Marzban

rm -f /etc/nginx/sites-enabled/marzban
rm -f /etc/nginx/sites-available/marzban

systemctl restart nginx

echo "✅ Marzban удален"

}


update_xray() {

echo "⬆ Обновление Xray Core"

CONTAINER="marzban-node-marzban-node-1"
VERSION="26.2.6"
FILE="Xray-linux-64.zip"

docker exec $CONTAINER bash -c "
cd /tmp &&
apt update -y >/dev/null 2>&1 &&
apt install -y wget unzip >/dev/null 2>&1 &&
wget -q https://github.com/XTLS/Xray-core/releases/download/v$VERSION/$FILE &&
unzip -o $FILE &&
mv xray /usr/local/bin/xray &&
chmod +x /usr/local/bin/xray &&
rm -f $FILE
"

docker restart $CONTAINER

echo "Проверка версии:"
docker exec $CONTAINER xray version

}


install_node() {

echo "🚀 Установка Marzban Node"

apt-get update -y
apt-get upgrade -y

apt install -y curl socat git jq

if ! command -v docker &> /dev/null; then
  echo "📦 Установка Docker..."
  curl -fsSL https://get.docker.com | sh
fi

if [ ! -d "$HOME/Marzban-node" ]; then
git clone https://github.com/Gozargah/Marzban-node $HOME/Marzban-node
fi

cd $HOME/Marzban-node

mkdir -p /var/lib/marzban-node

read -rp "URL панели (пример https://panel.com): " PANEL_URL
read -rp "Логин администратора: " USERNAME
read -rsp "Пароль: " PASSWORD
echo ""

TOKEN=$(curl -s -X POST "$PANEL_URL/api/admin/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=$USERNAME&password=$PASSWORD" | jq -r '.access_token')

if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
  echo "❌ Ошибка получения токена"
  exit 1
fi

curl -s -X POST "$PANEL_URL/api/node" \
  -H "Authorization: Bearer $TOKEN" \
  | tee /var/lib/marzban-node/ssl_client_cert.pem > /dev/null

cat > docker-compose.yml <<EOF
services:
  marzban-node:
    image: gozargah/marzban-node:latest
    restart: always
    network_mode: host

    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node

    environment:
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/ssl_client_cert.pem"
      SERVICE_PROTOCOL: rest
EOF

docker-compose up -d

echo "✅ Нода установлена"

}


case $option in

1)
install_marzban
;;

2)
remove_marzban
;;

3)
update_xray
;;

4)
install_node
;;

0)
exit
;;

*)
echo "Неверный выбор"
;;

esac
