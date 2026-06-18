#!/usr/bin/env bash

validate_dns_resolution() {

    log_info "Validando DNS..."

    local resolved_ip
    local public_ip

    resolved_ip="$(getent ahostsv4 "${DUCKDNS_DOMAIN}" | awk '{print $1}' | head -n1)"

    public_ip="$(curl -4 -s https://api.ipify.org || true)"

    if [[ -z "${resolved_ip}" ]]; then
        log_error "No se pudo resolver ${DUCKDNS_DOMAIN}"
        exit 1
    fi

    echo "DNS -> ${resolved_ip}"
    echo "WAN -> ${public_ip}"

    if [[ -n "${public_ip}" ]] && [[ "${resolved_ip}" != "${public_ip}" ]]; then
        log_warn "El dominio no apunta a la IP pública actual."
    else
        log_success "Resolución DNS correcta."
    fi
}

validate_ports() {

    log_info "Comprobando puertos 80 y 443..."

    local failed=0

    if ss -ltn '( sport = :80 )' | grep -q LISTEN; then
        log_error "Puerto 80 ocupado."
        failed=1
    fi

    if ss -ltn '( sport = :443 )' | grep -q LISTEN; then
        log_error "Puerto 443 ocupado."
        failed=1
    fi

    if [[ "${failed}" -eq 1 ]]; then
        exit 1
    fi

    log_success "Puertos disponibles."
}

create_proxy_network() {

    if docker network inspect duck_proxy >/dev/null 2>&1; then
        log_info "La red duck_proxy ya existe."
        return
    fi

    docker network create duck_proxy >/dev/null

    log_success "Red duck_proxy creada."
}