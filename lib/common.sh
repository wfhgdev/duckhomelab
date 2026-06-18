#!/usr/bin/env bash

CONFIG_DIR="/opt/duckhomelab"
CONFIG_FILE="${CONFIG_DIR}/duckhomelab.conf"

log_info() {
    echo "[INFO] $*"
}

log_success() {
    echo "[OK] $*"
}

log_warn() {
    echo "[WARN] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

print_banner() {

cat <<'EOF'

========================================
         DUCKHOMELAB V4.5
      STABLE HOMELAB ENGINE
========================================

EOF

}

require_root() {

    if [[ "${EUID}" -ne 0 ]]; then
        log_error "Ejecute este script con sudo."
        exit 1
    fi
}

validate_os() {

    if [[ ! -f /etc/os-release ]]; then
        log_error "No se pudo detectar el sistema operativo."
        exit 1
    fi

    . /etc/os-release

    if [[ "${ID}" != "ubuntu" ]]; then
        log_error "Solo Ubuntu es soportado."
        exit 1
    fi

    log_success "Ubuntu detectado."
}

validate_docker() {

    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker no está instalado."
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        log_error "Docker no responde."
        exit 1
    fi

    log_success "Docker operativo."
}