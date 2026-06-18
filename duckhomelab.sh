#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompts.sh"
source "${SCRIPT_DIR}/lib/network.sh"

main() {

    print_banner

    require_root

    validate_os

    validate_docker

    collect_user_configuration

    validate_dns_resolution

    validate_ports

    create_proxy_network

    save_configuration

    show_phase1_report
}

main "$@"