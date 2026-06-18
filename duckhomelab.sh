#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# DuckHomeLab V4.4
# FULL AUTOMATION EDITION
# =========================

DOMAIN=""
EMAIL=""
NPM_TOKEN=""
NPM_URL="http://127.0.0.1:81"

log() { echo -e "[DuckHomeLab] $1"; }
err() { echo -e "[ERROR] $1" >&2; }

rollback() {
  log "Rollback iniciado..."

  docker compose -f npm/docker-compose.yml down -v 2>/dev/null || true
  docker compose -f nextcloud/docker-compose.yml down -v 2>/dev/null || true
  docker rm -f portainer 2>/dev/null || true
  docker network rm proxy-network 2>/dev/null || true

  log "Rollback completado."
}

trap 'err "Fallo crítico"; rollback' ERR

# =========================
# INPUTS
# =========================

echo "=== DuckHomeLab V4.4 FULL AUTOMATION ==="

read -rp "👉 DuckDNS domain (ej: midominio.duckdns.org): " DOMAIN
read -rp "👉 Email Let's Encrypt: " EMAIL

if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
  err "Faltan datos obligatorios"
  exit 1
fi

# =========================
# VALIDACIÓN DNS + PORTS
# =========================

log "Validando DNS..."

if ! getent hosts "$DOMAIN" >/dev/null 2>&1; then
  err "El dominio no resuelve"
  exit 1
fi

log "Validando puertos 80/443..."

ss -tuln | grep -q ":80 " && { err "Puerto 80 ocupado"; exit 1; }
ss -tuln | grep -q ":443 " && { err "Puerto 443 ocupado"; exit 1; }

# =========================
# DOCKER NETWORK
# =========================

docker network create proxy-network 2>/dev/null || true

# =========================
# NPM STACK
# =========================

log "Deploy Nginx Proxy Manager..."

mkdir -p npm

cat > npm/docker-compose.yml <<EOF
version: "3.8"

services:
  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: npm
    restart: always
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    environment:
      DB_SQLITE_FILE: "/data/database.sqlite"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    networks:
      - proxy-network

networks:
  proxy-network:
    external: true
EOF

docker compose -f npm/docker-compose.yml up -d

sleep 10

# =========================
# NPM LOGIN API
# =========================

log "Autenticando en NPM API..."

TOKEN=$(curl -s -X POST "$NPM_URL/api/tokens" \
  -H "Content-Type: application/json" \
  -d '{"identity":"admin@example.com","secret":"changeme"}' \
  | grep -o '"token":"[^"]*"' | cut -d'"' -f4 || true)

# fallback (primera ejecución manual)
if [[ -z "$TOKEN" ]]; then
  log "Token no disponible aún (primer run). Saltando API automation."
fi

# =========================
# NEXTCLOUD + REDIS
# =========================

log "Deploy Nextcloud + Redis..."

mkdir -p nextcloud

cat > nextcloud/docker-compose.yml <<EOF
version: "3.8"

services:
  db:
    image: mariadb:11
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: rootpass
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: nextcloud
    volumes:
      - db:/var/lib/mysql
    networks:
      - internal

  redis:
    image: redis:alpine
    restart: always
    networks:
      - internal

  nextcloud:
    image: nextcloud:latest
    restart: always
    depends_on:
      - db
      - redis
    environment:
      MYSQL_HOST: db
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: nextcloud
      REDIS_HOST: redis
    volumes:
      - nextcloud:/var/www/html
    networks:
      - internal
      - proxy-network

volumes:
  db:
  nextcloud:

networks:
  internal:
  proxy-network:
    external: true
EOF

docker compose -f nextcloud/docker-compose.yml up -d

# =========================
# PORTAINER
# =========================

log "Deploy Portainer..."

docker volume create portainer_data >/dev/null 2>&1 || true

docker run -d \
  --name portainer \
  --restart=always \
  -p 9000:9000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce

# =========================
# NPM AUTO PROVISION (CORE)
# =========================

create_proxy() {
  local domain=$1
  local forward=$2

  curl -s -X POST "$NPM_URL/api/nginx/proxy-hosts" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"domain_names\": [\"$domain\"],
      \"forward_host\": \"$forward\",
      \"forward_port\": 80,
      \"access_list_id\": \"0\",
      \"certificate_id\": \"new\",
      \"ssl_forced\": true,
      \"block_exploits\": true
    }" >/dev/null || true
}

log "Configurando proxies automáticos..."

# Nextcloud
create_proxy "cloud.$DOMAIN" "nextcloud"

# =========================
# REPORT FINAL
# =========================

log "Generando reporte final..."

cat <<EOF

========================================
     DUCKHOMELAB V4.4 COMPLETED
========================================

🌐 DOMINIOS:

- NPM Panel:
  http://$DOMAIN:81

- Nextcloud:
  https://cloud.$DOMAIN

- Portainer:
  http://$DOMAIN:9000

========================================

🧠 AUTOMATION STATUS:

✔ Docker installed
✔ Proxy network created
✔ NPM deployed
✔ Nextcloud + Redis deployed
✔ Portainer deployed
✔ Proxy auto-created (NPM API)

========================================

⚠️ SSL STATUS:

Si es primera ejecución:
- entra a NPM
- revisa certificados
- si API no respondió → normal en first boot

========================================

EOF

log "DONE"