#!/usr/bin/env bash

collect_user_configuration() {

    echo

    read -rp "Dominio DuckDNS (ej: midominio.duckdns.org): " DUCKDNS_DOMAIN

    while [[ -z "${DUCKDNS_DOMAIN}" ]]; do
        echo "Dominio obligatorio."
        read -rp "Dominio DuckDNS: " DUCKDNS_DOMAIN
    done

    echo

    read -rp "Email Let's Encrypt: " LETSENCRYPT_EMAIL

    while [[ -z "${LETSENCRYPT_EMAIL}" ]]; do
        echo "Email obligatorio."
        read -rp "Email Let's Encrypt: " LETSENCRYPT_EMAIL
    done

    export DUCKDNS_DOMAIN
    export LETSENCRYPT_EMAIL
}

save_configuration() {

    mkdir -p "${CONFIG_DIR}"

    cat > "${CONFIG_FILE}" <<EOF
DUCKDNS_DOMAIN=${DUCKDNS_DOMAIN}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
EOF

    chmod 600 "${CONFIG_FILE}"

    log_success "Configuración guardada."
}

show_phase1_report() {

cat <<EOF

========================================
      PHASE 1 COMPLETED
========================================

DuckDNS:
${DUCKDNS_DOMAIN}

Let's Encrypt:
${LETSENCRYPT_EMAIL}

Docker Network:
duck_proxy

Config:
${CONFIG_FILE}

========================================

EOF

}