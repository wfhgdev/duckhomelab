#!/bin/bash
###############################################################################
# DuckHomeLab - Entorno Docker automatizado + Seguridad Fail2Ban
###############################################################################

# -e: Detiene el script si un comando falla.
# -u: Detiene el script si se usa una variable no definida.
# -o pipefail: Valida fallos en tuberías/pipes intermedios.
set -euo pipefail

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
  _____             _    _    _                      _           _     
 |  __ \           | |  | |  | |                    | |         | |    
 | |  | |_   _  ___| | _| |__| | ___  _ __ ___   ___| |     __ _| |__  
 | |  | | | | |/ __| |/ /  __  |/ _ \| '_ ` _ \ / _ \ |    / _` | '_ \ 
 | |__| | |_| | (__|   <| |  | | (_) | | | | | |  __/ |___| (_| | |_) |
 |_____/ \__,_|\___|_|\_\_|  |_|\___/|_| |_| |_|\___|______\__,_|_.__/ 
  by William Hernandez 2026                                                                     
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
read -rp "Subdominio DuckDNS (digite solo el subdomnio ej: mi-dominio): " SUBDOMAIN
read -rp "Token de DuckDNS: " TOKEN
info "Zona horaria del servidor (Ej: America/Bogota)."
read -rp "Zona horaria (presiona Enter para elegir Europe/Madrid): " TZ
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
# GENERACIÓN DE DOCKER COMPOSE CON RESPALDO VERSIONADO (IDEMPOTENTE)
# ----------------------------
# Si ya existe un compose previo se guarda una copia con marca de tiempo
# antes de sobreescribirlo, evitando pérdida de configuración anterior.
if [[ -f "$COMPOSE_FILE" ]]; then
    FECHA_RESPALDO=$(date +%Y%m%d_%H%M%S)
    FICHERO_BAK="${COMPOSE_FILE}.bak_${FECHA_RESPALDO}"
    warn "Detectado un docker-compose.yml existente. Copia guardada en: $FICHERO_BAK"
    cp "$COMPOSE_FILE" "$FICHERO_BAK"
fi

info "Escribiendo especificación de Docker Compose..."
cat > "$COMPOSE_FILE" <<EOF
services:

  # -----------------------------------------------------------------------
  # DuckDNS: actualiza la IP pública del subdominio cada 5 minutos.
  # No es un servicio web — no necesita Proxy Host en NPM.
  # -----------------------------------------------------------------------
  duckdns:
    image: lscr.io/linuxserver/duckdns:latest
    container_name: duckdns
    environment:
      - SUBDOMAINS=$SUBDOMAIN
      - TOKEN=$TOKEN
      - TZ=$TZ
      - LOG_FILE=false
    restart: unless-stopped
    networks:
      - $NETWORK

  # -----------------------------------------------------------------------
  # Nginx Proxy Manager: proxy inverso con gestión visual de SSL.
  # Puerto 81: panel de administración — accesible en red local.
  # ⚠️  Una vez configurado, elimina el mapeo del puerto 81 de este compose
  # para que no sea accesible desde la red local (ver instrucciones al final).
  # El tráfico real (80/443) sí debe permanecer abierto siempre.
  # -----------------------------------------------------------------------
  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: npm
    ports:
      - "80:80"    # Tráfico HTTP — mantener siempre abierto
      - "443:443"  # Tráfico HTTPS — mantener siempre abierto
      - "81:81"    # Panel admin — cerrar tras la configuración inicial
    volumes:
      - $DIR_BASE/npm/data:/data
      - $DIR_BASE/npm/letsencrypt:/etc/letsencrypt
    restart: unless-stopped
    networks:
      - $NETWORK

  # -----------------------------------------------------------------------
  # Portainer: panel de administración visual de Docker.
  # No expone puertos al host — accede vía NPM (proxy-network).
  # Comunicación interna HTTP: más rápido que HTTPS dentro de Docker.
  # Proxy Host en NPM: portainer → http → portainer:9000
  # -----------------------------------------------------------------------
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
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

  # -----------------------------------------------------------------------
  # Dockge: gestor visual de stacks de Docker Compose.
  # No expone puertos al host — accede vía NPM (proxy-network).
  # Comunicación interna HTTP: más rápido que HTTPS dentro de Docker.
  # Proxy Host en NPM: dockge → http → dockge:5001
  # -----------------------------------------------------------------------
  dockge:
    image: louislam/dockge:latest
    container_name: dockge
    environment:
      - DOCKGE_STACKS_DIR=$DIR_STACKS
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
# AUTOCREACIÓN DE PROXY HOSTS EN NPM VÍA API REST
# ----------------------------
# Crea los Proxy Hosts de Portainer y Dockge automáticamente usando la
# API de NPM con las credenciales por defecto. Los hosts se crean sin SSL
# porque el certificado wildcard se genera en el primer acceso manual.
# Después solo hay que asignar el certificado a cada host desde la interfaz.
#
# Lógica de reintentos: NPM necesita unos segundos para inicializar su
# base de datos interna. El bucle reintenta hasta 12 veces (60 segundos)
# antes de continuar sin crear los hosts y dejar un aviso al usuario.
crear_proxy_hosts_npm() {
    local npm_url="http://127.0.0.1:81"
    local npm_user="admin@example.com"
    local npm_pass="changeme"
    local npm_token=""
    local intentos=0
    local max_intentos=12

    info "Esperando a que NPM inicialice su API interna..."

    while [[ $intentos -lt $max_intentos ]]; do
        intentos=$((intentos + 1))

        npm_token=$(curl -s --max-time 5 -X POST "${npm_url}/api/tokens" \
            -H "Content-Type: application/json" \
            -d "{\"identity\":\"${npm_user}\",\"secret\":\"${npm_pass}\"}" \
            2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('token',''))
except:
    print('')
" 2>/dev/null || true)

        if [[ -n "$npm_token" ]]; then
            ok "API de NPM lista (intento ${intentos}/${max_intentos})."
            break
        fi

        warn "NPM aún no está listo (intento ${intentos}/${max_intentos}). Reintentando en 5s..."
        sleep 5
    done

    if [[ -z "$npm_token" ]]; then
        warn "No se pudo conectar con la API de NPM tras ${max_intentos} intentos."
        warn "Crea los Proxy Hosts manualmente en la interfaz web de NPM."
        return 0
    fi

    # Función interna para crear un host individual.
    # Schema validado contra NPM v2.15 — incluye todos los campos
    # obligatorios para evitar el error "additional properties".
    _crear_host() {
        local descripcion="$1"
        local dominio="$2"
        local contenedor="$3"
        local puerto="$4"

        local resultado
        resultado=$(curl -s --max-time 10 -X POST "${npm_url}/api/nginx/proxy-hosts" \
            -H "Authorization: Bearer ${npm_token}" \
            -H "Content-Type: application/json" \
            -d "{
                \"domain_names\": [\"${dominio}\"],
                \"forward_scheme\": \"http\",
                \"forward_host\": \"${contenedor}\",
                \"forward_port\": ${puerto},
                \"access_list_id\": 0,
                \"certificate_id\": 0,
                \"ssl_forced\": false,
                \"caching_enabled\": false,
                \"block_exploits\": true,
                \"allow_websocket_upgrade\": false,
                \"http2_support\": false,
                \"hsts_enabled\": false,
                \"hsts_subdomains\": false,
                \"advanced_config\": \"\",
                \"locations\": [],
                \"meta\": {\"letsencrypt_agree\": false, \"dns_challenge\": false},
                \"enabled\": true
            }" 2>/dev/null || true)

        local host_id
        host_id=$(echo "$resultado" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('id', ''))
except:
    print('')
" 2>/dev/null || true)

        if [[ -n "$host_id" ]]; then
            ok "Proxy Host creado: ${descripcion} → ${dominio} (ID: ${host_id})"
        else
            warn "No se pudo crear el Proxy Host de ${descripcion}. Créalo manualmente en NPM."
        fi
    }

    info "Creando Proxy Hosts en NPM..."
    _crear_host "NPM Admin"  "npm.${SUBDOMAIN}.duckdns.org"       "npm"       81
    _crear_host "Portainer"  "portainer.${SUBDOMAIN}.duckdns.org" "portainer" 9000
    _crear_host "Dockge"     "dockge.${SUBDOMAIN}.duckdns.org"    "dockge"    5001
}

crear_proxy_hosts_npm

# Detectar la IP local del servidor para mostrarla en el resumen
IP_LOCAL=$(hostname -I 2>/dev/null | awk '{print $1}')
IP_LOCAL="${IP_LOCAL:-TU_IP_LOCAL}"

# ----------------------------
# RESUMEN COMPLETO DE POST-INSTALACIÓN
# ----------------------------
echo ""
ok "=================================================================="
ok "         ¡PROCESO DE INSTALACIÓN COMPLETADO EXITOSAMENTE!         "
ok "=================================================================="
echo ""
echo -e "${COLOR_AZUL}▶ Acceso al panel de Nginx Proxy Manager:${COLOR_RESET}"
echo -e "     http://${IP_LOCAL}:81"
echo "     Usuario inicial : admin@example.com"
echo "     Contraseña      : changeme  ← CÁMBIALA EN EL PRIMER ACCESO"
echo ""
echo -e "${COLOR_AZUL}▶ Proxy Hosts creados automáticamente (sin SSL todavía):${COLOR_RESET}"
echo -e "     npm.${SUBDOMAIN}.duckdns.org       → ${COLOR_VERDE}npm:81 (http)${COLOR_RESET}"
echo -e "     portainer.${SUBDOMAIN}.duckdns.org → ${COLOR_VERDE}portainer:9000 (http)${COLOR_RESET}"
echo -e "     dockge.${SUBDOMAIN}.duckdns.org    → ${COLOR_VERDE}dockge:5001 (http)${COLOR_RESET}"
echo ""
echo -e "${COLOR_AZUL}▶ Protección Fail2Ban activa:${COLOR_RESET}"
echo "     npm-auth    : bloquea IPs tras 4 fallos de login (24h de baneo)"
echo "     npm-badbots : bloquea IPs con escaneos masivos de errores 4xx"
echo -e "     Estado      : ${COLOR_VERDE}sudo fail2ban-client status${COLOR_RESET}"
echo ""
echo -e "${COLOR_AMARILLO}▶ PASOS SIGUIENTES EN NPM (http://${IP_LOCAL}:81):${COLOR_RESET}"
echo ""
echo "  1. Cambia las credenciales por defecto al entrar por primera vez."
echo ""
echo "  2. Genera el certificado Wildcard SSL:"
echo "     Certificates → Add Certificate → Let's Encrypt via DNS"
echo -e "     - Domain Names : ${COLOR_VERDE}*.${SUBDOMAIN}.duckdns.org${COLOR_RESET}"
echo -e "                      ${COLOR_VERDE}${SUBDOMAIN}.duckdns.org${COLOR_RESET}"
echo "     - DNS Provider  : duckdns"
echo -e "     - Credentials  : ${COLOR_VERDE}dns_duckdns_token=${TOKEN}${COLOR_RESET}"
echo "     - Propagation   : 120 segundos"
echo ""
echo "  3. Asigna el certificado a cada Proxy Host:"
echo "     Edita cada host → pestaña SSL → selecciona *.${SUBDOMAIN}.duckdns.org"
echo "     Activa: Force SSL + HTTP/2 Support"
echo ""
echo -e "${COLOR_AMARILLO}▶ SEGURIDAD — Cierra el puerto 81 cuando termines de configurar NPM:${COLOR_RESET}"
echo ""
echo "     El puerto 81 está abierto en tu red local para que puedas"
echo "     configurar NPM cómodamente. Una vez tengas el SSL configurado"
echo "     y compruebes que entras a NPM vía:"
echo -e "       ${COLOR_VERDE}https://npm.${SUBDOMAIN}.duckdns.org${COLOR_RESET}"
echo "     cierra el puerto 81 directo editando el compose:"
echo ""
echo -e "     ${COLOR_VERDE}sudo nano /opt/docker-services/docker-compose.yml${COLOR_RESET}"
echo "     Elimina o comenta esta línea dentro del servicio 'npm':"
echo -e "       ${COLOR_ROJO}- \"81:81\"${COLOR_RESET}"
echo ""
echo -e "     Luego aplica el cambio:"
echo -e "     ${COLOR_VERDE}cd /opt/docker-services && sudo docker compose up -d npm${COLOR_RESET}"
echo ""
echo "     Desde ese momento NPM solo es accesible vía HTTPS por el proxy."
echo "     Si necesitas volver al puerto 81, vuelve a añadir la línea"
echo "     y recrea el contenedor con el mismo comando."
echo ""
echo "=================================================================="