#!/bin/bash
###############################################################################
# DuckHomeLab - Entorno Docker automatizado
###############################################################################

set -euo pipefail

# ----------------------------
# MODO DE EJECUCIÓN
# ----------------------------
# PROD = sin puertos en apps internas (solo NPM)
# DEV  = expone puertos para debug
DOCKER_MODE="${DOCKER_MODE:-prod}"

# ----------------------------
# COLORES
# ----------------------------
COLOR_VERDE='\033[0;32m'
COLOR_AMARILLO='\033[1;33m'
COLOR_ROJO='\033[0;31m'
COLOR_AZUL='\033[0;34m'
COLOR_RESET='\033[0m'

info(){ echo -e "${COLOR_AZUL}[INFO]${COLOR_RESET} $1"; }
ok(){ echo -e "${COLOR_VERDE}[OK]${COLOR_RESET} $1"; }
warn(){ echo -e "${COLOR_AMARILLO}[WARN]${COLOR_RESET} $1"; }
error(){ echo -e "${COLOR_ROJO}[ERROR]${COLOR_RESET} $1" >&2; }

# ----------------------------
# VARIABLES
# ----------------------------
DIR_BASE="/opt/docker-services"
DIR_STACKS="/opt/stacks"
NETWORK="proxy-network"
COMPOSE_FILE="${DIR_BASE}/docker-compose.yml"

# ----------------------------
# ROOT CHECK
# ----------------------------
[[ $EUID -ne 0 ]] && { error "Ejecuta como root"; exit 1; }

# ----------------------------
# INPUTS
# ----------------------------
read -rp "Subdominio DuckDNS: " SUBDOMAIN
read -rp "Token DuckDNS: " TOKEN
read -rp "Zona horaria (Europe/Madrid): " TZ
TZ="${TZ:-Europe/Madrid}"

# ----------------------------
# UPDATE + DEPENDENCIAS
# ----------------------------
info "Actualizando sistema..."
apt-get update -y
apt-get install -y curl git ca-certificates gnupg

# ----------------------------
# DOCKER INSTALL
# ----------------------------
if ! command -v docker &>/dev/null; then
    info "Instalando Docker..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
    > /etc/apt/sources.list.d/docker.list

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable --now docker
fi

# ----------------------------
# ENTORNO
# ----------------------------
info "Preparando entorno..."
mkdir -p "$DIR_BASE" "$DIR_STACKS"

docker network inspect "$NETWORK" >/dev/null 2>&1 || \
docker network create "$NETWORK"

# ----------------------------
# COMPOSE
# ----------------------------
info "Generando docker-compose..."

DOCKGE_PORT_BLOCK=""
if [[ "$DOCKER_MODE" == "dev" ]]; then
    DOCKGE_PORT_BLOCK='ports:
      - "5001:5001"'
    warn "Modo DEV: Dockge expuesto en puerto 5001"
else
    DOCKGE_PORT_BLOCK="# sin puerto (modo proxy NPM)"
fi

cat > "$COMPOSE_FILE" <<EOF
services:

  duckdns:
    image: lscr.io/linuxserver/duckdns:latest
    container_name: duckdns
    environment:
      - SUBDOMAINS=$SUBDOMAIN
      - TOKEN=$TOKEN
      - TZ=$TZ
    restart: unless-stopped
    networks: [$NETWORK]

  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: npm
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    volumes:
      - $DIR_BASE/npm/data:/data
      - $DIR_BASE/npm/letsencrypt:/etc/letsencrypt
    restart: unless-stopped
    networks: [$NETWORK]

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - $DIR_BASE/portainer:/data
    restart: unless-stopped
    networks: [$NETWORK]
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  dockge:
    image: louislam/dockge:latest
    container_name: dockge
    environment:
      - DOCKGE_STACKS_DIR=$DIR_STACKS
$DOCKGE_PORT_BLOCK
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - $DIR_BASE/dockge:/app/data
      - $DIR_STACKS:$DIR_STACKS
    restart: unless-stopped
    networks: [$NETWORK]
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

networks:
  $NETWORK:
    external: true
EOF

# ----------------------------
# DEPLOY
# ----------------------------
info "Desplegando servicios..."
cd "$DIR_BASE"
docker compose up -d --pull always

# ----------------------------
# HEALTH CHECK
# ----------------------------
info "Verificando servicios..."

sleep 5

curl -fs http://localhost:81 >/dev/null && ok "NPM OK" || warn "NPM FAIL"
curl -fs http://localhost:9000 >/dev/null && warn "Portainer directo no expuesto (OK si usas NPM)"
curl -fs http://localhost:5001 >/dev/null && ok "Dockge OK (DEV mode activo)" || warn "Dockge solo vía proxy (PROD mode)"

# ----------------------------
# RESUMEN
# ----------------------------
echo ""
ok "INSTALACIÓN COMPLETADA"
echo "Modo: $DOCKER_MODE"
echo "NPM: http://localhost:81"
echo "DuckDNS: https://${SUBDOMAIN}.duckdns.org"
echo ""
echo "IMPORTANTE:"
echo "- Configura Proxy Hosts en NPM"
echo "- Portainer -> http://portainer:9000"
echo "- Dockge -> http://dockge:5001"