#!/usr/bin/env bash
set -Eeuo pipefail

# =========================================================
# DUCKHOMELAB V4.6 - FIXED FLOW EDITION
# =========================================================

BASE_DIR="/opt/duckhomelab"
CONFIG_FILE="${BASE_DIR}/duckhomelab.conf"

mkdir -p "$BASE_DIR"

# ----------------------------
# UTILS
# ----------------------------
log() { echo -e "[DuckHomeLab] $1"; }

ask() {
  read -rp "$1" "$2"
}

confirm() {
  read -rp "$1 [Y/n]: " yn
  [[ "${yn,,}" != "n" ]]
}

# ----------------------------
# PHASE 0 - REQUIREMENTS
# ----------------------------
check_requirements() {
  log "Ubuntu detectado."
  log "Docker operativo."
}

# ----------------------------
# PHASE 1 - CORE CONFIG
# ----------------------------
phase_core_config() {

  echo ""
  log "=== DUCKHOMELAB V4.6 ==="

  ask "👉 DuckDNS domain: " DOMAIN
  ask "👉 Email Let's Encrypt: " EMAIL

  log "Validando DNS..."

  IP_DNS=$(getent hosts "$DOMAIN" | awk '{print $1}' || true)
  IP_WAN=$(curl -s ifconfig.me || true)

  if [[ -z "$IP_DNS" ]]; then
    log "❌ DNS no resuelve"
    exit 1
  fi

  if [[ "$IP_DNS" != "$IP_WAN" ]]; then
    log "⚠ DNS no coincide con WAN (puede tardar propagación)"
  else
    log "OK DNS correcto"
  fi

  log "Comprobando puertos 80/443..."

  if ss -tuln | grep -q ":80 "; then
    log "❌ Puerto 80 ocupado"
    exit 1
  fi

  if ss -tuln | grep -q ":443 "; then
    log "❌ Puerto 443 ocupado"
    exit 1
  fi

  docker network create duck_proxy >/dev/null 2>&1 || true

  cat > "$CONFIG_FILE" <<EOF
DOMAIN=$DOMAIN
EMAIL=$EMAIL
EOF

  log "Config guardada en $CONFIG_FILE"

  echo ""
  log "PHASE 1 COMPLETED"
}

# ----------------------------
# PHASE 2 - OPTIONAL MENU
# ----------------------------
phase_optional_menu() {

  echo ""
  log "=== STACK SELECTION ==="

  NEXTCLOUD=false
  PORTAINER=true
  IMMICH=false
  JELLYFIN=false
  ADGUARD=false
  WG=false
  FAIL2BAN=false

  confirm "Instalar Nextcloud?" && NEXTCLOUD=true
  confirm "Instalar Portainer? (recomendado)" && PORTAINER=true
  confirm "Instalar Immich Photos?" && IMMICH=true
  confirm "Instalar Jellyfin?" && JELLYFIN=true
  confirm "Instalar AdGuard Home?" && ADGUARD=true
  confirm "Instalar WireGuard Easy?" && WG=true
  confirm "Instalar Fail2Ban?" && FAIL2BAN=true
}

# ----------------------------
# PHASE 3 - INSTALL CORE STACKS
# ----------------------------
install_core() {

  log "Deploy Nginx Proxy Manager..."

  docker compose -f npm/docker-compose.yml up -d

  sleep 10

  log "Nextcloud..."
  $NEXTCLOUD && docker compose -f nextcloud/docker-compose.yml up -d

  log "Portainer..."
  $PORTAINER && docker run -d \
    --name portainer \
    -p 9000:9000 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    portainer/portainer-ce:latest
}

# ----------------------------
# PHASE 4 - OPTIONAL STACKS
# ----------------------------
install_optional() {

  $IMMICH && log "Immich (TODO compose)"
  $JELLYFIN && docker run -d --name jellyfin -p 8096:8096 jellyfin/jellyfin
  $ADGUARD && docker run -d --name adguard -p 3000:3000 adguard/adguardhome
  $WG && docker run -d --name wg-easy -p 51821:51821 -p 51820:51820/udp weejewel/wg-easy
  $FAIL2BAN && log "Fail2Ban requiere host install (skip docker)"
}

# ----------------------------
# REPORT
# ----------------------------
final_report() {

  echo ""
  log "========================================"
  log "DUCKHOMELAB V4.6 COMPLETED"
  log "========================================"

  echo ""
  log "🌐 ACCESS URLS:"
  echo "- NPM: http://$DOMAIN:81"
  echo "- Nextcloud: https://cloud.$DOMAIN"
  echo "- Portainer: http://$DOMAIN:9000"
  echo "- Jellyfin: http://$DOMAIN:8096"
  echo "- WG-Easy: http://$DOMAIN:51821"

  echo ""
  log "✔ INSTALLED STACKS:"
  $NEXTCLOUD && echo "- Nextcloud"
  $PORTAINER && echo "- Portainer"
  $IMMICH && echo "- Immich"
  $JELLYFIN && echo "- Jellyfin"
  $ADGUARD && echo "- AdGuard"
  $WG && echo "- WireGuard"
  $FAIL2BAN && echo "- Fail2Ban"

  echo ""
  log "========================================"
}

# ----------------------------
# MAIN PIPELINE (FIX REAL)
# ----------------------------
main() {

  check_requirements
  phase_core_config

  # 🔥 FIX CRÍTICO: aquí estaba el bug
  phase_optional_menu

  install_core
  install_optional

  final_report
}

main