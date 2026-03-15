#!/bin/bash

clear

echo "================================"
echo "        MARZBAN MANAGER"
echo "================================"
echo "        By Aexpot"
echo "  https://github.com/Aexpot"
echo "================================"

echo ""
echo "1) Установить панель Marzban"
echo "2) Удалить панель Marzban"
echo "3) Обновить Xray core на ноде"
echo "4) Установить Marzban Node"
echo "5) Удалить Marzban Node"
echo "0) Выход"
echo ""

read -p "Выберите действие: " option

if command -v docker-compose &> /dev/null
then
DC="docker-compose"
else
DC="docker compose"
fi


install_panel(){

echo "=== Установка панели ==="

read -p "Домен панели: " DOMAIN
read -p "Email SSL: " EMAIL

apt update -y
apt install -y curl git docker.io nginx certbot python3-certbot-nginx

systemctl enable docker
systemctl start docker

cd /opt

git clone https://github.com/Gozargah/Marzban 2>/dev/null

cd Marzban

cp .env.example .env

$DC up -d

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

certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL --redirect

echo ""
echo "Панель доступна:"
echo "https://$DOMAIN/dashboard"

}



remove_panel(){

echo "Удаление панели..."

cd /opt/Marzban 2>/dev/null

$DC down

rm -rf /opt/Marzban

rm -f /etc/nginx/sites-enabled/marzban
rm -f /etc/nginx/sites-available/marzban

systemctl restart nginx

echo "Панель удалена"

}



update_xray(){

echo "=== Обновление Xray ==="

read -p "Имя контейнера ноды: " CONTAINER

VERSION="26.2.6"

docker exec $CONTAINER bash -c "
cd /tmp &&
apt update -y >/dev/null &&
apt install -y wget unzip >/dev/null &&
wget -q https://github.com/XTLS/Xray-core/releases/download/v$VERSION/Xray-linux-64.zip &&
unzip -o Xray-linux-64.zip &&
mv xray /usr/local/bin/xray &&
chmod +x /usr/local/bin/xray
"

docker restart $CONTAINER

docker exec $CONTAINER xray version

}



install_node(){

echo "=== Установка ноды ==="

apt update -y
apt install -y curl jq socat git

if ! command -v docker &> /dev/null
then
curl -fsSL https://get.docker.com | sh
fi

read -p "URL панели: " PANEL
PANEL=$(echo "$PANEL" | xargs)
PANEL=${PANEL%/}

read -p "Логин администратора: " USER
read -s -p "Пароль: " PASS
echo ""

echo "Получение API токена..."

TOKEN=$(curl -s -X POST "$PANEL/api/admin/token" \
-H "Content-Type: application/x-www-form-urlencoded" \
-d "username=$USER&password=$PASS" | jq -r '.access_token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]
then
echo "Ошибка получения токена"
exit 1
fi

echo "Токен получен"


read -p "Имя ноды: " NODE_NAME
read -p "IP ноды: " NODE_IP

echo "Создание ноды..."

NODE_DATA=$(curl -s -X POST "$PANEL/api/node" \
-H "Authorization: Bearer $TOKEN" \
-H "Content-Type: application/json" \
-d "{\"name\":\"$NODE_NAME\",\"address\":\"$NODE_IP\"}")

CERT=$(echo "$NODE_DATA" | jq -r '.certificate')

mkdir -p /var/lib/marzban-node

echo "$CERT" > /var/lib/marzban-node/ssl_client_cert.pem


git clone https://github.com/Gozargah/Marzban-node ~/Marzban-node 2>/dev/null

cd ~/Marzban-node

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


$DC up -d

echo ""
echo "Нода установлена"
echo "Имя: $NODE_NAME"
echo "IP: $NODE_IP"

}



remove_node(){

echo "Удаление ноды..."

cd ~/Marzban-node 2>/dev/null

$DC down

rm -rf ~/Marzban-node
rm -rf /var/lib/marzban-node

echo "Нода удалена"

}



case $option in

1)
install_panel
;;

2)
remove_panel
;;

3)
update_xray
;;

4)
install_node
;;

5)
remove_node
;;

0)
exit
;;

*)
echo "Неверный выбор"
;;

esac
