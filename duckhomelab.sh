#!/bin/bash

set -e

echo "========================================"
echo "     DuckHomeLab V5 - SIMPLE MODE"
echo "========================================"

### -----------------------------
### CHECK ROOT
### -----------------------------
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Ejecuta como root (sudo)."
  exit 1
fi

### -----------------------------
### CHECK DOCKER
### -----------------------------
if ! command -v docker &> /dev/null; then
  echo "[INFO] Docker no encontrado. Instalando..."
  curl -fsSL https://get.docker.com | bash
else
  echo "[OK] Docker ya instalado."
fi

systemctl enable docker >/dev/null 2>&1 || true
systemctl start docker

### -----------------------------
### INPUTS
### -----------------------------
read -p "DuckDNS domain (ej: midominio.duckdns.org): " DUCKDNS_DOMAIN
read -p "Email Let's Encrypt: " EMAIL

### -----------------------------
### DETECT PUBLIC IP
### -----------------------------
PUBLIC_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip)

echo "[INFO] Public IP: $PUBLIC_IP"

### -----------------------------
### VALIDATE DNS
### -----------------------------
DNS_IP=$(getent hosts "$DUCKDNS_DOMAIN" | awk '{ print $1 }' || true)

echo "[INFO] DNS IP: $DNS_IP"

if [ "$PUBLIC_IP" != "$DNS_IP" ]; then
  echo "[WARN] DNS no coincide con IP pública"
  echo "       Puede tardar en propagarse DuckDNS"
else
  echo "[OK] DNS validado"
fi

### -----------------------------
### CREATE NETWORK
### -----------------------------
docker network create duck_proxy >/dev/null 2>&1 || true
echo "[OK] Red duck_proxy lista"

### -----------------------------
### CORE STACK INSTALL
### -----------------------------

echo "[INFO] Instalando CORE STACK..."

### ---------------- Dockge ----------------
docker run -d \
  --name dockge \
  --restart=always \
  -p 5001:5001 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v dockge_data:/app/data \
  louislam/dockge:latest || true

### ---------------- Nginx Proxy Manager ----------------
docker run -d \
  --name npm \
  --restart=always \
  --network duck_proxy \
  -p 81:81 \
  -p 80:80 \
  -p 443:443 \
  -v npm_data:/data \
  -v npm_letsencrypt:/etc/letsencrypt \
  jc21/nginx-proxy-manager:latest || true

### ---------------- Portainer (CORE FIXED) ----------------
docker run -d \
  --name portainer \
  --restart=always \
  -p 9000:9000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest || true

echo "[OK] CORE STACK desplegado"

### -----------------------------
### OPTIONAL STACKS
### -----------------------------

echo ""
read -p "Install Nextcloud? [y/N]: " NEXTCLOUD

if [[ "$NEXTCLOUD" =~ ^[yY]$ ]]; then
  echo "[INFO] Deploy Nextcloud..."
  docker run -d \
    --name nextcloud \
    --restart=always \
    --network duck_proxy \
    -p 8080:80 \
    nextcloud:latest
fi

read -p "Install WireGuard Easy? [y/N]: " WG

if [[ "$WG" =~ ^[yY]$ ]]; then
  echo "[INFO] Deploy WireGuard..."
  docker run -d \
    --name wireguard \
    --restart=always \
    -p 51821:51821 \
    -p 51820:51820/udp \
    weejewel/wg-easy:latest
fi

### -----------------------------
### FINAL REPORT
### -----------------------------

echo ""
echo "========================================"
echo "        DUCKHOMELAB V5 COMPLETE"
echo "========================================"

echo "Domain: $DUCKDNS_DOMAIN"
echo "Public IP: $PUBLIC_IP"
echo ""
echo "ACCESS:"
echo "- NPM: http://$PUBLIC_IP:81"
echo "- Dockge: http://$PUBLIC_IP:5001"
echo "- Portainer: http://$PUBLIC_IP:9000"

if [[ "$NEXTCLOUD" =~ ^[yY]$ ]]; then
  echo "- Nextcloud: http://$PUBLIC_IP:8080"
fi

if [[ "$WG" =~ ^[yY]$ ]]; then
  echo "- WireGuard: http://$PUBLIC_IP:51821"
fi

echo ""
echo "IMPORTANT:"
echo "- Configura SSL manualmente en NPM"
echo "- Crea Proxy Hosts desde UI"
echo "========================================"