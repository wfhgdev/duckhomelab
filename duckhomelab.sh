#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# DUCKHOMELAB V4.1 - ROBUST INSTALLER CORE
# ==============================================================================

CONFIG_FILE="./duckhomelab.env"

# ------------------------------------------------------------------------------
# 1. DEFAULTS
# ------------------------------------------------------------------------------
DOMAIN=""
DUCKDNS_TOKEN=""
NPM_EMAIL="admin@local"

# ------------------------------------------------------------------------------
# 2. LOGGER
# ------------------------------------------------------------------------------
log() { echo -e "[DuckHomeLab] $1"; }
error() { echo -e "[ERROR] $1"; exit 1; }

# ------------------------------------------------------------------------------
# 3. INTERACTIVE WIZARD
# ------------------------------------------------------------------------------
prompt() {
  local var_name="$1"
  local message="$2"
  local default="$3"

  if [[ -z "${!var_name:-}" ]]; then
    read -rp "$message [$default]: " input
    export "$var_name"="${input:-$default}"
  fi
}

run_wizard() {
  log "🧠 Configuración inicial requerida"

  prompt DUCKDNS_TOKEN "DuckDNS Token" ""
  prompt DOMAIN "DuckDNS Domain (ej: midominio.duckdns.org)" ""
  prompt NPM_EMAIL "Email para NPM SSL" "admin@local"

  if [[ -z "$DUCKDNS_TOKEN" || -z "$DOMAIN" ]]; then
    error "DuckDNS_TOKEN y DOMAIN son obligatorios"
  fi

  cat > "$CONFIG_FILE" <<EOF
DUCKDNS_TOKEN=$DUCKDNS_TOKEN
DOMAIN=$DOMAIN
NPM_EMAIL=$NPM_EMAIL
EOF

  log "✔ Config guardada en $CONFIG_FILE"
}

# ------------------------------------------------------------------------------
# 4. LOAD CONFIG IF EXISTS
# ------------------------------------------------------------------------------
load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    log "📦 Cargando configuración existente..."
    source "$CONFIG_FILE"
  else
    run_wizard
  fi
}

# ------------------------------------------------------------------------------
# 5. VALIDATION LAYER (CRITICAL FIX)
# ------------------------------------------------------------------------------
validate_env() {
  log "🔍 Validando configuración..."

  [[ -z "$DUCKDNS_TOKEN" ]] && error "Falta DUCKDNS_TOKEN"
  [[ -z "$DOMAIN" ]] && error "Falta DOMAIN"

  [[ -z "$NPM_EMAIL" ]] && {
    log "⚠ NPM_EMAIL vacío → usando default"
    NPM_EMAIL="admin@local"
  }
}

# ------------------------------------------------------------------------------
# 6. BOOTSTRAP FLOW
# ------------------------------------------------------------------------------
main() {
  log "🚀 DuckHomeLab V4.1 starting..."

  load_config
  validate_env

  log "✔ Config OK"
  log "🌍 Domain: $DOMAIN"
  log "📧 NPM Email: $NPM_EMAIL"

  # aquí continúa instalación real...
  log "➡ Continuing Docker + stacks installation..."
}

main "$@"