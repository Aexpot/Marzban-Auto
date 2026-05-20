#!/bin/bash

set -e

clear

echo "========================================="
echo "      Marzban Node Auto Installer"
echo "========================================="
echo ""

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo "Запусти скрипт через sudo:"
    echo "sudo bash install-node.sh"
    exit 1
fi

# Обновление системы
echo "[1/8] Обновление системы..."
apt-get update -y
apt-get upgrade -y

# Установка зависимостей
echo "[2/8] Установка зависимостей..."
apt-get install -y curl socat git docker-compose-plugin

# Установка Docker
echo "[3/8] Установка Docker..."
curl -fsSL https://get.docker.com | sh

# Создание папки
echo "[4/8] Создание директорий..."
mkdir -p /var/lib/marzban-node/

# Ввод сертификата
echo "[5/8] Вставь SSL сертификат панели."
echo "После вставки нажми CTRL+D"
echo ""

cat > /var/lib/marzban-node/ssl_client_cert.pem

chmod 600 /var/lib/marzban-node/ssl_client_cert.pem

# Клонирование
echo "[6/8] Загрузка Marzban-node..."

cd /root

if [ -d "Marzban-node" ]; then
    rm -rf Marzban-node
fi

git clone https://github.com/Gozargah/Marzban-node

cd Marzban-node

# Создание docker-compose.yml
echo "[7/8] Создание docker-compose.yml..."

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

# Запуск
echo "[8/8] Запуск Marzban-node..."

docker compose down --remove-orphans || true
docker compose up -d

echo ""
echo "========================================="
echo "      Установка завершена!"
echo "========================================="
echo ""
echo "Проверка контейнеров:"
docker ps

echo ""
echo "Логи:"
echo "cd /root/Marzban-node && docker compose logs -f"
echo ""
echo "Теперь добавь IP сервера в панели Marzban."
echo ""
echo "Порт узла: 62050"
echo "Протокол: REST"
echo ""
