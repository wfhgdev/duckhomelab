#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# DUCKHOMELAB V4.7
# PRODUCTION HARDENING
# =========================

BASE_DIR="/opt/duckhomelab"
DOMAIN=""
EMAIL=""
PUBLIC_IP=""
STACKS_DEPLOYED=()

# -------------------------
# LOGGING
# -------------------------
log() { echo -e "[DuckHomeLab] $1"; }

# -------------------------
# DNS VALIDATION REAL
# -------------------------
validate_dns() {
    DOMAIN="$1"

    log "Validando DNS..."

    PUBLIC_IP=$(curl -s https://api.ipify.org)
    DNS_IP=$(getent ahosts "$DOMAIN" | awk '{print $1; exit}')

    log "DNS -> $DNS_IP"
    log "WAN -> $PUBLIC_IP"

    if [[ "$DNS_IP" != "$PUBLIC_IP" ]]; then
        log "ERROR: DNS no apunta a este servidor"
        exit 1
    fi

    log "DNS correcto"
}

# -------------------------
# NETWORK SETUP
# -------------------------
init_networks() {
    log "Creando redes Docker..."

    docker network create proxy >/dev/null 2>&1 || true
    docker network create internal >/dev/null 2>&1 || true

    log "Redes OK"
}

# -------------------------
# NPM CORE
# -------------------------
deploy_npm() {
    log "Deploy Nginx Proxy Manager..."

    docker volume create npm_data >/dev/null 2>&1 || true

    docker run -d \
        --name npm \
        --restart=always \
        --network proxy \
        -p 80:80 \
        -p 443:443 \
        -p 81:81 \
        -v npm_data:/data \
        jc21/nginx-proxy-manager:latest

    STACKS_DEPLOYED+=("npm")
}

# -------------------------
# PORTAINER CORE
# -------------------------
deploy_portainer() {
    log "Deploy Portainer (CORE)..."

    docker volume create portainer_data >/dev/null 2>&1 || true

    docker run -d \
        --name portainer \
        --restart=always \
        --network proxy \
        -p 9000:9000 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest

    STACKS_DEPLOYED+=("portainer")
}

# -------------------------
# NEXTCLOUD
# -------------------------
deploy_nextcloud() {
    log "Deploy Nextcloud + Redis..."

    docker volume create nc_db >/dev/null 2>&1 || true
    docker volume create nc_data >/dev/null 2>&1 || true

    docker run -d --name nextcloud-db \
        --network internal \
        -e MYSQL_ROOT_PASSWORD=secret \
        -e MYSQL_DATABASE=nextcloud \
        mariadb:11 || return 1

    docker run -d --name nextcloud-redis \
        --network internal \
        redis:alpine || return 1

    docker run -d --name nextcloud \
        --network proxy \
        -e MYSQL_HOST=nextcloud-db \
        -e REDIS_HOST=nextcloud-redis \
        nextcloud:latest || return 1

    STACKS_DEPLOYED+=("nextcloud")
}

# -------------------------
# WIREGUARD EASY (UDP)
# -------------------------
deploy_wireguard() {
    log "Deploy WireGuard Easy..."

    docker run -d \
        --name wireguard \
        --cap-add=NET_ADMIN \
        --cap-add=SYS_MODULE \
        -e WG_HOST="$DOMAIN" \
        -p 51820:51820/udp \
        -p 51821:51821 \
        weejewel/wg-easy || return 1

    STACKS_DEPLOYED+=("wireguard")
}

# -------------------------
# OPTIONAL STACK FLAGS
# -------------------------
select_stacks() {
    read -p "Nextcloud? [y/N]: " r && [[ "$r" == "y" ]] && NEXTCLOUD=1
    read -p "WireGuard? [y/N]: " r && [[ "$r" == "y" ]] && WG=1
}

NEXTCLOUD=0
WG=0

# -------------------------
# ROLLBACK ENGINE
# -------------------------
rollback() {
    log "ROLLBACK ACTIVADO"

    for s in "${STACKS_DEPLOYED[@]}"; do
        docker rm -f "$s" >/dev/null 2>&1 || true
    done

    log "Sistema restaurado"
}

trap rollback ERR

# -------------------------
# HEALTH CHECK
# -------------------------
health_check() {
    log "Health check..."

    docker ps --format "table {{.Names}}\t{{.Status}}"
}

# -------------------------
# FINAL REPORT
# -------------------------
report() {
    echo ""
    echo "=================================="
    echo "   DUCKHOMELAB V4.7 COMPLETE"
    echo "=================================="
    echo ""
    echo "Domain: $DOMAIN"
    echo "Public IP: $PUBLIC_IP"
    echo ""
    echo "STACKS:"
    for s in "${STACKS_DEPLOYED[@]}"; do
        echo "- $s"
    done
    echo ""
    echo "ACCESS:"
    echo "- NPM: http://$DOMAIN:81"
    echo "- Portainer: http://$DOMAIN:9000"
    echo ""
    echo "=================================="
}

# -------------------------
# MAIN
# -------------------------
main() {

    echo "=== DUCKHOMELAB V4.7 ==="

    read -p "DuckDNS domain: " DOMAIN
    read -p "Email Let's Encrypt: " EMAIL

    validate_dns "$DOMAIN"

    init_networks

    deploy_npm
    deploy_portainer

    select_stacks

    [[ "$NEXTCLOUD" == "1" ]] && deploy_nextcloud
    [[ "$WG" == "1" ]] && deploy_wireguard

    health_check
    report
}

main