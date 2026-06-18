#!/usr/bin/env bash

set -euo pipefail

echo "========================================"
echo "      DuckHomeLab V5 STABLE BASE"
echo "========================================"

# -----------------------------
# INPUTS
# -----------------------------
read -rp "DuckDNS domain (ej: midominio.duckdns.org): " DOMAIN
read -rp "Email Let's Encrypt: " EMAIL

echo ""
echo "[INFO] Validando entorno..."

# -----------------------------
# VALIDAR IP PUBLICA
# -----------------------------
PUBLIC_IP=$(curl -s ifconfig.me || true)
DNS_IP=$(getent ahosts "$DOMAIN" | awk '{print $1; exit}' || true)

echo "[INFO] Public IP: $PUBLIC_IP"
echo "[INFO] DNS IP: $DNS_IP"

if [[ -n "$DNS_IP" && "$DNS_IP" != "$PUBLIC_IP" ]]; then
  echo "[WARN] DNS no apunta a esta máquina (continuando igual)"
else
  echo "[OK] DNS validado"
fi

# -----------------------------
# INSTALL DOCKER CHECK
# -----------------------------
if ! command -v docker &>/dev/null; then
  echo "[INFO] Instalando Docker..."
  curl -fsSL https://get.docker.com | bash
fi

systemctl enable --now docker

# -----------------------------
# DOCKER COMPOSE PLUGIN CHECK
# -----------------------------
docker compose version >/dev/null 2>&1 || {
  echo "[INFO] Instalando docker compose plugin..."
  apt-get update && apt-get install -y docker-compose-plugin
}

# -----------------------------
# NETWORK
# -----------------------------
docker network create duck_proxy 2>/dev/null || true

# -----------------------------
# DOCKGE
# -----------------------------
echo "[INFO] Deploy Dockge..."
docker run -d \
  --name dockge \
  -p 5001:5001 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /opt/dockge:/opt/dockge \
  --restart unless-stopped \
  louislam/dockge:latest

# -----------------------------
# NGINX PROXY MANAGER
# -----------------------------
echo "[INFO] Deploy Nginx Proxy Manager..."

docker run -d \
  --name npm \
  --network duck_proxy \
  -p 80:80 \
  -p 81:81 \
  -p 443:443 \
  -e DB_SQLITE_FILE="/data/database.sqlite" \
  -v /opt/npm/data:/data \
  -v /opt/npm/letsencrypt:/etc/letsencrypt \
  --restart unless-stopped \
  jc21/nginx-proxy-manager:latest

# -----------------------------
# OPTIONALS
# -----------------------------

read -rp "Install Nextcloud? [y/N]: " NC
if [[ "$NC" == "y" || "$NC" == "Y" ]]; then
  echo "[INFO] Deploy Nextcloud..."
  docker run -d \
    --name nextcloud \
    --network duck_proxy \
    nextcloud:latest
fi

read -rp "Install WireGuard Easy? [y/N]: " WG
if [[ "$WG" == "y" || "$WG" == "Y" ]]; then
  echo "[INFO] Deploy WireGuard..."
  docker run -d \
    --name wireguard \
    --cap-add=NET_ADMIN \
    --cap-add=SYS_MODULE \
    -p 51820:51820/udp \
    -p 51821:51821 \
    -e PASSWORD="admin" \
    -v /opt/wireguard:/etc/wireguard \
    --restart unless-stopped \
    weejewel/wg-easy
fi

# -----------------------------
# REPORT
# -----------------------------

echo ""
echo "========================================"
echo "         DUCKHOMELAB V5 DONE"
echo "========================================"
echo ""
echo "Access:"
echo "- NPM: http://$DOMAIN:81"
echo "- Dockge: http://$PUBLIC_IP:5001"
echo ""
echo "IMPORTANT:"
echo "- Configure SSL manually in NPM"
echo "- Add Proxy Hosts manually"
echo ""
echo "========================================"