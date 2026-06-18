#!/usr/bin/env bash
set -euo pipefail

BASE="/opt/homelab"
LOG="/var/log/homelab-v4.log"
SERVER_IP=$(hostname -I | awk '{print $1}')

echo "[INIT] Homelab V4 starting..." | tee -a "$LOG"

# =========================
# NPM AUTH
# =========================
npm_token() {
  curl -s -X POST "http://$SERVER_IP:81/api/tokens" \
    -H "Content-Type: application/json" \
    -d "{\"identity\":\"$NPM_EMAIL\",\"secret\":\"$NPM_PASS\"}" \
    | jq -r '.token'
}

# =========================
# DOCKER DISCOVERY ENGINE
# =========================
discover_containers() {
  docker ps --format '{{.Names}}' | while read -r container; do

    enable=$(docker inspect "$container" \
      --format '{{ index .Config.Labels "com.homelab.proxy.enable" }}' 2>/dev/null || true)

    [[ "$enable" != "true" ]] && continue

    domain=$(docker inspect "$container" \
      --format '{{ index .Config.Labels "com.homelab.proxy.domain" }}')

    port=$(docker inspect "$container" \
      --format '{{ index .Config.Labels "com.homelab.proxy.port" }}')

    echo "$container|$domain|$port"
  done
}

# =========================
# CREATE PROXY HOST
# =========================
create_proxy() {
  local token="$1"
  local domain="$2"
  local host="$3"
  local port="$4"

  echo "[PROXY] $domain -> $host:$port" | tee -a "$LOG"

  curl -s -X POST "http://$SERVER_IP:81/api/nginx/proxy-hosts" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{
      \"domain_names\": [\"$domain\"],
      \"forward_scheme\": \"http\",
      \"forward_host\": \"$host\",
      \"forward_port\": $port,
      \"ssl_forced\": false,
      \"block_exploits\": true,
      \"allow_websocket_upgrade\": true,
      \"http2_support\": true
    }" >/dev/null || true
}

# =========================
# GET HOST ID
# =========================
get_host_id() {
  local token="$1"
  local domain="$2"

  curl -s "http://$SERVER_IP:81/api/nginx/proxy-hosts" \
    -H "Authorization: Bearer $token" \
    | jq -r ".[] | select(.domain_names[] == \"$domain\") | .id"
}

# =========================
# SSL ENABLE FLOW (REALISTIC)
# =========================
enable_ssl() {
  local token="$1"
  local host_id="$2"
  local email="$3"

  curl -s -X PUT "http://$SERVER_IP:81/api/nginx/proxy-hosts/$host_id" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{
      \"ssl_forced\": true,
      \"letsencrypt_agree\": true,
      \"email\": \"$email\",
      \"http2_support\": true
    }" >/dev/null || true
}

# =========================
# SSL ORCHESTRATOR (IMPORTANT PART)
# =========================
ssl_orchestrator() {
  local token="$1"
  local domain="$2"

  echo "[SSL] Processing $domain"

  host_id=$(get_host_id "$token" "$domain")

  [[ -z "$host_id" ]] && return

  # Retry loop (DNS propagation safe)
  for i in {1..10}; do
    if curl -Is "http://$domain" >/dev/null 2>&1; then
      enable_ssl "$token" "$host_id" "$EMAIL"
      echo "[SSL] enabled for $domain"
      return
    fi
    sleep 5
  done

  echo "[SSL] skipped (DNS not ready): $domain"
}

# =========================
# RECONCILIATION LOOP
# =========================
reconcile() {
  TOKEN=$(npm_token)

  discover_containers | while IFS='|' read -r name domain port; do

    [[ -z "$domain" || -z "$port" ]] && continue

    create_proxy "$TOKEN" "$domain" "$name" "$port"
    ssl_orchestrator "$TOKEN" "$domain"

  done
}

# =========================
# WATCHER LOOP (AUTODISCOVERY REAL TIME)
# =========================
watch_loop() {
  while true; do
    echo "[WATCHER] scanning containers..." | tee -a "$LOG"
    reconcile
    sleep 60
  done
}

# =========================
# START
# =========================
watch_loop