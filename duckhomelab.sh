#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================
# DuckHomeLab V4.3 CORE INSTALLER
# ==============================

LOG_FILE="/var/log/duckhomelab.log"

log() {
  echo -e "[DuckHomeLab] $1"
}

error() {
  echo -e "[ERROR] $1" >&2
}

rollback() {
  log "Rollback iniciado..."

  docker compose -f npm/docker-compose.yml down -v 2>/dev/null || true
  docker compose -f nextcloud/docker-compose.yml down -v 2>/dev/null || true
  docker compose -f portainer/docker-compose.yml down -v 2>/dev/null || true

  docker network rm proxy-network 2>/dev/null || true

  log "Rollback completado."
}

trap 'error "Fallo crítico. Ejecutando rollback..."; rollback' ERR

# ==============================
# 1. INPUTS OBLIGATORIOS
# ==============================

echo ""
echo "=== DuckHomeLab Setup ==="

read -rp "👉 Introduce tu dominio DuckDNS (ej: midominio.duckdns.org): " DOMAIN
read -rp "👉 Email admin (Let's Encrypt / NPM): " NPM_EMAIL

if [[ -z "$DOMAIN" || -z "$NPM_EMAIL" ]]; then
  error "Dominio o email vacío"
  exit 1
fi

# ==============================
# 2. VALIDACIÓN DNS
# ==============================

log "Validando DNS..."

if ! getent hosts "$DOMAIN" >/dev/null 2>&1; then
  error "El dominio no resuelve DNS: $DOMAIN"
  exit 1
fi

# ==============================
# 3. CHECK PUERTOS
# ==============================

log "Validando puertos 80 y 443..."

if ss -tuln | grep -q ":80 "; then
  error "Puerto 80 ocupado"
  exit 1
fi

if ss -tuln | grep -q ":443 "; then
  error "Puerto 443 ocupado"
  exit 1
fi

# ==============================
# 4. RED DOCKER PROXY
# ==============================

log "Creando red proxy..."

docker network create proxy-network 2>/dev/null || true

# ==============================
# 5. STACK: NPM
# ==============================

log "Instalando Nginx Proxy Manager..."

mkdir -p npm
cat > npm/docker-compose.yml <<EOF
version: "3"

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
      DISABLE_IPV6: "true"
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

# ==============================
# 6. STACK: PORTAINER
# ==============================

log "Instalando Portainer..."

docker volume create portainer_data 2>/dev/null || true

docker run -d \
  --name portainer \
  --restart=always \
  -p 9000:9000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest

# ==============================
# 7. NEXTCLOUD (SIN EXPOSICIÓN DIRECTA)
# ==============================

log "Instalando Nextcloud..."

mkdir -p nextcloud

cat > nextcloud/docker-compose.yml <<EOF
version: "3"

services:
  db:
    image: mariadb:latest
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: nextcloudroot
      MYSQL_PASSWORD: nextcloud
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
    volumes:
      - db:/var/lib/mysql
    networks:
      - internal

  nextcloud:
    image: nextcloud:latest
    restart: always
    depends_on:
      - db
    environment:
      MYSQL_HOST: db
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: nextcloud
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

# ==============================
# 8. FINAL REPORT
# ==============================

log "Generando reporte final..."

cat <<EOF

========================================
        DUCKHOMELAB INSTALADO
========================================

🌐 Dominio: https://$DOMAIN

📦 Servicios:

- Nginx Proxy Manager:
  http://$DOMAIN:81

- Portainer:
  http://$DOMAIN:9000

- Nextcloud:
  https://cloud.$DOMAIN (configurar en NPM)

========================================

⚠️ SIGUIENTE PASO MANUAL EN NPM:
1. Crear Proxy Host:
   cloud.$DOMAIN -> nextcloud:80

2. Activar SSL Let's Encrypt

========================================

EOF

log "Instalación completada."