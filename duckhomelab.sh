#!/bin/bash
###############################################################################
# DuckHomeLab - Entorno Docker automatizado + Seguridad Fail2Ban
###############################################################################

# -e: Detiene el script si un comando falla.
# -u: Detiene el script si se usa una variable no definida.
# -o pipefail: Valida fallos en tuberías/pipes intermedios.
set -euo pipefail

# ----------------------------
# MODO DE EJECUCIÓN
# ----------------------------
# PROD = Aislamiento estricto. Puertos internos ocultos; puerto 81 mapeado a localhost.
# DEV  = Expone puertos de debug (81, 9000, 5001) públicamente en el host.
DOCKER_MODE="${DOCKER_MODE:-prod}"

# ----------------------------
# COLORES PARA OUTPUT
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
# BANNER ASCII
# ----------------------------
mostrar_banner() {
    cat << "EOF"
 ______                    __        ____  ____                            __          __        
|_   _ `.                  [  |  _  |_   ||   _|                          [  |        [  |       
  | | `. \ __   _   .---.  | | / ]    | |__| |    .--.   _ .--..--.  .---.   | |  ,--.   | |.--.   
  | |  | |[  | | | / /'`\] | '' <     |  __  |  / .'`\ \[ `.-. .-. |/ /__\\  | | `'_\ :  | '/'`\ \ 
 _| |_.' / | \_/ |,| \__.  | |`\ \   _| |  | |_ | \__. | | | | | | || \__.,  | | // | |, | \__/ | 
|______.'  '.__.'_/'.___.'[__|  \_]|____||____| '.__.' [___||__||__]'.__.'[___]\'-;__/[__;.__.'  
                                                                                                 
EOF
}

# ----------------------------
# VARIABLES DE ENTORNO
# ----------------------------
DIR_BASE="/opt/docker-services"
DIR_STACKS="/opt/stacks"
NETWORK="proxy-network"
COMPOSE_FILE="${DIR_BASE}/docker-compose.yml"

# ----------------------------
# CONTROL DE PRIVILEGIOS
# ----------------------------
[[ $EUID -ne 0 ]] && { error "Este script requiere privilegios de root (sudo)."; exit 1; }

# Mostrar Banner de inicio
mostrar_banner

# ----------------------------
# PARÁMETROS DE ENTRADA
# ----------------------------
info "Configuración inicial del entorno:"
read -rp "Subdominio DuckDNS (ej: mi-homelab): " SUBDOMAIN
read -rp "Token de DuckDNS: " TOKEN
read -rp "Zona horaria (presiona Enter para Europe/Madrid): " TZ
TZ="${TZ:-Europe/Madrid}"
echo ""

# ----------------------------
# ACTUALIZACIÓN E INSTALACIÓN DE DEPENDENCIAS
# ----------------------------
info "Actualizando repositorios e instalando herramientas básicas del sistema..."
apt-get update -y
apt-get install -y curl git ca-certificates gnupg fail2ban iproute2

# ----------------------------
# INSTALACIÓN TOTAL DE DOCKER (SI CORRESPONDE)
# ----------------------------
if ! command -v docker &>/dev/null; then
    info "Docker no detectado. Procediendo con la instalación oficial..."
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
    ok "Docker instalado y activado correctamente."
fi

# ----------------------------
# PREPARACIÓN DE DIRECTORIOS Y LOGS (PRE-REQUISITO FAIL2BAN)
# ----------------------------
info "Estructurando directorios persistentes y archivos de registro..."
mkdir -p "$DIR_BASE" "$DIR_STACKS"
mkdir -p "$DIR_BASE/npm/data/logs"
mkdir -p "$DIR_BASE/npm/letsencrypt"
mkdir -p "$DIR_BASE/portainer"
mkdir -p "$DIR_BASE/dockge"

# Nota crítica: Fail2Ban fallará al arrancar si los archivos .log declarados no existen en el host.
touch "$DIR_BASE/npm/data/logs/manager.log"
touch "$DIR_BASE/npm/data/logs/default-host_access.log"
touch "$DIR_BASE/npm/data/logs/fallback_access.log"

# Asegurar permisos correctos para despliegues no privilegiados futuros
chown -R 1000:1000 "$DIR_BASE/portainer" "$DIR_BASE/dockge" "$DIR_STACKS"

# Crear la red externa del proxy si no existe
docker network inspect "$NETWORK" >/dev/null 2>&1 || {
    info "Creando red externa puente: $NETWORK..."
    docker network create "$NETWORK"
}

# ----------------------------
# AUTOCONFIGURACIÓN DE FAIL2BAN NATIVO
# ----------------------------
info "Configurando el blindaje perimetral con Fail2Ban..."

# Detección dinámica automatizada de los segmentos de red locales activos (Lista blanca / ignoreip)
LOCAL_NETWORKS=$(ip -o addr show | awk '/inet / && !/127.0.0.1/ {print $4}' | tr '\n' ' ')
IGNORE_LIST="127.0.0.1/8 ::1 ${LOCAL_NETWORKS}"
info "Redes añadidas a la lista blanca de exclusión (ignoreip): $IGNORE_LIST"

# 1. Crear Filtro contra Fuerza Bruta en el panel de Administración de NPM
cat << 'EOF' > /etc/fail2ban/filter.d/npm-auth.conf
[Definition]
failregex = ^.*\[.*\]\s+.*\s+›\s+.*\s+Authentication Failed for.*IP:\s+<HOST>
            ^<HOST> \- \- \[.*\] "POST /api/tokens HTTP\/.*" 401 .*
ignoreregex =
EOF

# 2. Crear Filtro contra Escaneo de vulnerabilidades y Web-bots (Exceso de errores HTTP 4XX)
cat << 'EOF' > /etc/fail2ban/filter.d/npm-badbots.conf
[Definition]
failregex = ^<HOST> \- \- \[.*\] ".*" (400|401|403|404|444) .*
ignoreregex =
EOF

# 3. Desplegar configuración de las cárceles (Jails) personalizadas con tus parámetros exactos
cat << EOF > /etc/fail2ban/jail.d/npm.local
[DEFAULT]
ignoreip = $IGNORE_LIST

[npm-auth]
enabled = true
port = 80,443,81
filter = npm-auth
logpath = $DIR_BASE/npm/data/logs/manager.log
          $DIR_BASE/npm/data/logs/default-host_access.log
          $DIR_BASE/npm/data/logs/proxy-host-*_access.log
bantime = 24h
findtime = 10m
maxretry = 4
action = iptables-multiport[name=npm-auth, port="80,443,81", protocol=tcp]

[npm-badbots]
enabled = true
port = 80,443
filter = npm-badbots
logpath = $DIR_BASE/npm/data/logs/default-host_access.log
          $DIR_BASE/npm/data/logs/proxy-host-*_access.log
          $DIR_BASE/npm/data/logs/fallback_access.log
bantime = 24h
findtime = 10m
maxretry = 4
action = iptables-multiport[name=npm-badbots, port="80,443", protocol=tcp]
EOF

systemctl restart fail2ban
ok "Fail2Ban configurado y reiniciado con éxito."

# ----------------------------
# GESTIÓN Y AJUSTES DE PUERTOS (PROD vs DEV)
# ----------------------------
if [[ "$DOCKER_MODE" == "dev" ]]; then
    NPM_PORT_81='- "81:81"'
    PORTAINER_PORT_BLOCK='ports:
      - "9000:9000"'
    DOCKGE_PORT_BLOCK='ports:
      - "5001:5001"'
    warn "Modo DESARROLLO (DEV) activo: Todos los puertos administrativos se exponen al host."
else
    NPM_PORT_81='- "127.0.0.1:81:81"'
    PORTAINER_PORT_BLOCK="# Sin puerto mapeado (Tráfico optimizado HTTP interno por proxy-network)"
    DOCKGE_PORT_BLOCK="# Sin puerto mapeado (Acceso exclusivo a través del proxy inverso)"
fi

# ----------------------------
# GENERACIÓN DE DOCKER COMPOSE CON RESPALDO VERSIONADO (IDEMPOTENTE)
# ----------------------------
# Mejora: Se incluye marca de tiempo para evitar sobreescribir respaldos anteriores
if [[ -f "$COMPOSE_FILE" ]]; then
    FECHA_RESPALDO=$(date +%Y%m%d_%H%M%S)
    FICHERO_BAK="${COMPOSE_FILE}.bak_${FECHA_RESPALDO}"
    warn "Detectado un docker-compose.yml existente. Guardando copia histórica en: $FICHERO_BAK"
    cp "$COMPOSE_FILE" "$FICHERO_BAK"
fi

info "Escribiendo especificación limpia de Docker Compose..."
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
    networks:
      - $NETWORK

  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: npm
    ports:
      - "80:80"
      - "443:443"
      $NPM_PORT_81
    volumes:
      - $DIR_BASE/npm/data:/data
      - $DIR_BASE/npm/letsencrypt:/etc/letsencrypt
    restart: unless-stopped
    networks:
      - $NETWORK

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    $PORTAINER_PORT_BLOCK
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - $DIR_BASE/portainer:/data
    restart: unless-stopped
    networks:
      - $NETWORK
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
    networks:
      - $NETWORK
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
# DESPLIEGUE OPERATIVO
# ----------------------------
info "Lanzando contenedores mediante Docker Compose..."
cd "$DIR_BASE"
docker compose up -d --pull always

# ----------------------------
# HEALTH CHECK AVANZADO Y SEGURO (NATIVO DOCKER)
# ----------------------------
info "Ejecutando diagnóstico de salud del stack..."
sleep 6

if curl -fs http://localhost:80 >/dev/null 2>&1 || [ $? -eq 404 ]; then
    ok "NPM Core: Operativo y respondiendo."
else
    warn "NPM Core: No responde en el puerto 80. Revisa logs ('docker logs npm')."
fi

check_container_status() {
    local container_name=$1
    if [[ "$(docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null)" == "true" ]]; then
        ok "Contenedor [$container_name]: CORRIENDO perfectamente de forma interna."
    else
        error "Contenedor [$container_name]: NO SE DETECTA EN EJECUCIÓN."
    fi
}

check_container_status "portainer"
check_container_status "dockge"
check_container_status "duckdns"

# ----------------------------
# RESUMEN COMPLETO DE POST-INSTALACIÓN
# ----------------------------
echo ""
ok "=================================================================="
ok "         ¡PROCESO DE INSTALACIÓN COMPLETADO EXITOSAMENTE!         "
ok "=================================================================="
echo -e "Modo de entorno actual: ${COLOR_VERDE}${DOCKER_MODE^^}${COLOR_RESET}"
echo ""
if [[ "$DOCKER_MODE" == "prod" ]]; then
    echo "Seguridad del Panel NPM (Puerto 81):"
    echo "  - El puerto administrativo 81 está securizado y mapeado a LOCALHOST (127.0.0.1)."
    echo "  - Para acceder de forma segura desde tu máquina local, abre una terminal y lanza:"
    echo -e "      ${COLOR_AMARILLO}ssh -L 8181:127.0.0.1:81 usuario@IP_DE_TU_SERVIDOR${COLOR_RESET}"
    echo "    Luego ve en tu navegador web a: http://localhost:8181"
else
    echo "Acceso directo Web (Modo DEV):"
    echo "  - NPM Admin Panel:  http://localhost:81"
    echo "  - Portainer HTTP:   http://localhost:9000"
    echo "  - Dockge UI:        http://localhost:5001"
fi
echo ""
echo "Protección del Perímetro (Fail2Ban Nativo):"
echo "  - Cárcel 'npm-auth': Baneos automáticos tras 4 fallos de inicio de sesión (Admin o API)."
echo "  - Cárcel 'npm-badbots': Mitigación inmediata ante escaneos masivos de vulnerabilidades (errores 4XX)."
echo "  - Parámetros: Baneo permanente durante 24 horas dentro de ventanas de 10 minutos."
echo -e "  - Consulta el estado usando: ${COLOR_VERDE}fail2ban-client status npm-auth${COLOR_RESET}"
echo ""
echo "PASOS MANUALES FINALES EN LA INTERFAZ WEB DE NPM:"
echo "1. Accede a NPM (admin@example.com / changeme) y actualiza tus credenciales de inmediato."
echo "2. Ve a 'SSL Certificates' -> 'Add SSL Certificate' -> 'Let's Encrypt'."
echo "3. Configura un Certificado Wildcard tal como planificaste:"
echo "     - Domain Names: *.tu-dominio.duckdns.org y tu-dominio.duckdns.org"
echo "     - Activa 'Use a DNS Provider' -> Elige DuckDNS."
echo "     - Provider Credentials: dns_duckdns_token=TU_TOKEN_AQUÍ"
echo "     - Propagation Seconds: 120"
echo "4. Da de alta tus Proxy Hosts usando los nombres DNS internos y HTTP plano (¡Rendimiento Óptimo!):"
echo -e "     - Portainer -> Forward Hostname: ${COLOR_VERDE}portainer${COLOR_RESET} | Puerto: ${COLOR_VERDE}9000${COLOR_RESET} | Protocolo: ${COLOR_VERDE}http${COLOR_RESET}"
echo -e "     - Dockge    -> Forward Hostname: ${COLOR_VERDE}dockge${COLOR_RESET}    | Puerto: ${COLOR_VERDE}5001${COLOR_RESET} | Protocolo: ${COLOR_VERDE}http${COLOR_RESET}"
echo "=================================================================="