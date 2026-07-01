#!/bin/bash
###############################################################################
# Nextcloud Backup Hybrid - Copia Local (con Rotación) o Nube (Rclone)
###############################################################################

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

mostrar_banner() {
    cat << "EOF"
  _   _           _       _                 _                       
 | \ | |         | |     | |               | |                      
 |  \| | _____  _| |_ ___| | ___  _   _  __| |                      
 | . ` |/ _ \ \/ / __/ __| |/ _ \| | | |/ _` |                      
 | |\  |  __/>  <| || (__| | (_) | |_| | (_| |                      
 |_| \_|\___/_/\_\\__\___|_|\___/ \__,_|\__,_|                      
  ____             _                  _____      _                  
 |  _ \           | |                |  __ \    | |                 
 | |_) | __ _  ___| | ___   _ _ __   | |__) |___| | ___  _ __   ___ 
 |  _ < / _` |/ __| |/ / | | | '_ \  |  _  // __| |/ _ \| '_ \ / _ \
 | |_) | (_| | (__|   <| |_| | |_) | | | \ \ (__| | (_) | | | |  __/
 |____/ \__,_|\___|_|\_\\__,_| .__/  |_|  \_\___|_|\___/|_| |_|\___|
                             | |                                    
 by William Hernandez        |_|                                    
EOF
}

CONF_FILE="/etc/nextcloud-backup.conf"
DB_TMP_FILE="/tmp/nextcloud-db.sql"

[[ $EUID -ne 0 ]] && { error "Este script requiere privilegios de root (sudo)."; exit 1; }

mostrar_banner

desactivar_mantenimiento_emergencia() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "El script falló inesperadamente. Forzando desactivación del modo mantenimiento..."
        if [[ -n "${NC_ROOT:-}" && -f "$NC_ROOT/occ" ]]; then
            sudo -u www-data php "$NC_ROOT/occ" maintenance:mode --off || true
        fi
    fi
}
trap desactivar_mantenimiento_emergencia EXIT

# ----------------------------
# FASE 1: CARGA O DETECCIÓN DE PARÁMETROS
# ----------------------------
if [[ -f "$CONF_FILE" ]]; then
    info "Cargando configuración guardada desde $CONF_FILE..."
    source "$CONF_FILE"
else
    info "Primera ejecución detectada. Iniciando fase de autodetectores..."
    
    NC_ROOT="/var/www/nextcloud"
    CONFIG_FILE="$NC_ROOT/config/config.php"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        warn "No se encontró el archivo config.php en la ruta predeterminada."
        read -rp "Introduce la ruta absoluta del DocumentRoot de Nextcloud: " NC_ROOT
        CONFIG_FILE="$NC_ROOT/config/config.php"
    fi

    if [[ -f "$CONFIG_FILE" ]]; then
        info "Configuración encontrada. Extrayendo credenciales mediante PHP nativo..."
        DB_NAME=$(php -r "include '$CONFIG_FILE'; echo \$CONFIG['dbname'] ?? '';")
        DB_USER=$(php -r "include '$CONFIG_FILE'; echo \$CONFIG['dbuser'] ?? '';")
        DB_PASS=$(php -r "include '$CONFIG_FILE'; echo \$CONFIG['dbpassword'] ?? '';")
        DB_HOST=$(php -r "include '$CONFIG_FILE'; echo \$CONFIG['dbhost'] ?? '';")
        DATA_DIR=$(php -r "include '$CONFIG_FILE'; echo \$CONFIG['datadirectory'] ?? '';")
    fi

    if [[ -z "${DB_NAME:-}" || -z "${DB_USER:-}" || -z "${DATA_DIR:-}" ]]; then
        warn "La detección automática fue incompleta. Por favor introduce los datos manualmente:"
        read -rp "Nombre de la Base de Datos MariaDB: " DB_NAME
        read -rp "Usuario de la Base de Datos: " DB_USER
        read -s -rp "Contraseña de la Base de Datos: " DB_PASS
        echo ""
        read -rp "Host de la Base de Datos [localhost]: " DB_HOST
        DB_HOST="${DB_HOST:-localhost}"
        read -rp "Ruta absoluta del directorio de datos [/ncdata]: " DATA_DIR
        DATA_DIR="${DATA_DIR:-/ncdata}"
    else
        ok "¡Datos de Nextcloud detectados con éxito!"
    fi

    # Configuración de compresión
    echo ""
    info "Configuración de compresión para volumen de datos (>50GB):"
    echo "1) PIGZ : Compresión multinúcleo (Ultra rápida, recomendada)"
    echo "2) NONE : Sin compresión (Solo empaqueta tar rápido. Ideal para fotos/videos)"
    echo "3) GZIP : Compresión estándar (Lenta, usa un solo núcleo)"
    read -rp "Selecciona una opción (1-3) [1]: " OPT_COMPRESSION
    OPT_COMPRESSION="${OPT_COMPRESSION:-1}"

    case "$OPT_COMPRESSION" in
        2) COMPRESSION_MODE="none" ;;
        3) COMPRESSION_MODE="gzip" ;;
        *) COMPRESSION_MODE="pigz" ;;
    esac

    # Instalar dependencias base
    apt-get update -y
    apt-get install -y curl pigz

    # -------------------------------------------------------------------------
    # NUEVO: PREGUNTA CLAVE — ¿NUBE O SOLO LOCAL?
    # -------------------------------------------------------------------------
    echo ""
    read -rp "¿Deseas activar la subida automática a una nube comercial (Google Drive/OneDrive)? (s/n) [s]: " ENABLE_CLOUD_INPUT
    ENABLE_CLOUD_INPUT="${ENABLE_CLOUD_INPUT:-s}"

    # Inicializar variables vacías para evitar errores de 'set -u'
    RCLONE_REMOTE=""
    RCLONE_FOLDER=""
    LOCAL_BACKUP_DIR=""
    LOCAL_RETENTION_DAYS=""

    if [[ "$ENABLE_CLOUD_INPUT" =~ ^[Ss]$ ]]; then
        USE_CLOUD="yes"
        LOCAL_BACKUP_DIR="/opt/nextcloud_backup_staging"
        LOCAL_RETENTION_DAYS="0" # No aplica, se borra al subir

        if ! command -v rclone &>/dev/null; then
            info "Rclone no está instalado. Instalando..."
            curl -fsSL https://rclone.org/install.sh | bash
        fi

        info "Iniciando asistente de Rclone. Nombra al remote como: 'nextcloud-cloud'"
        echo ""
        rclone config

        read -rp "Confirma el remote de Rclone [nextcloud-cloud]: " RCLONE_REMOTE
        RCLONE_REMOTE="${RCLONE_REMOTE:-nextcloud-cloud}"
        read -rp "Nombre de la carpeta en la nube [Nextcloud_Backups]: " RCLONE_FOLDER
        RCLONE_FOLDER="${RCLONE_FOLDER:-Nextcloud_Backups}"
    else
        USE_CLOUD="no"
        echo ""
        info "Configuración para MODO SOLO LOCAL activo:"
        read -rp "Introduce la ruta destino donde guardar los backups permanentemente [/var/backups/nextcloud]: " LOCAL_BACKUP_DIR
        LOCAL_BACKUP_DIR="${LOCAL_BACKUP_DIR:-/var/backups/nextcloud}"
        read -rp "Aplica buenas prácticas. ¿Cuántos días de retención local deseas mantener? [7]: " LOCAL_RETENTION_DAYS
        LOCAL_RETENTION_DAYS="${LOCAL_RETENTION_DAYS:-7}"
    fi

    # Guardar archivo de configuración unificado
    cat << EOF > "$CONF_FILE"
NC_ROOT="$NC_ROOT"
DATA_DIR="$DATA_DIR"
DB_NAME="$DB_NAME"
DB_USER="$DB_USER"
DB_PASS="$DB_PASS"
DB_HOST="$DB_HOST"
COMPRESSION_MODE="$COMPRESSION_MODE"
USE_CLOUD="$USE_CLOUD"
RCLONE_REMOTE="$RCLONE_REMOTE"
RCLONE_FOLDER="$RCLONE_FOLDER"
LOCAL_BACKUP_DIR="$LOCAL_BACKUP_DIR"
LOCAL_RETENTION_DAYS="$LOCAL_RETENTION_DAYS"
EOF
    chmod 600 "$CONF_FILE"
    ok "Configuración guardada en $CONF_FILE"

    # Auto-instalación en Cron
    echo ""
    read -rp "¿Deseas auto-instalar este script en el Cron del sistema? (s/n): " INSTALAR_CRON
    if [[ "$INSTALAR_CRON" =~ ^[Ss]$ ]]; then
        SCRIPT_PATH="/usr/local/bin/nextcloud_backup_rclone.sh"
        cp "$0" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        echo "0 2 * * * root $SCRIPT_PATH > /var/log/nextcloud_backup_system.log 2>&1" > /etc/cron.d/nextcloud-backup
        ok "Script programado en Cron con éxito."
    fi
fi

# ----------------------------
# FASE 4: EJECUCIÓN DEL RESPALDO
# ----------------------------
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [[ "$COMPRESSION_MODE" == "none" ]]; then
    FINAL_BACKUP_NAME="nextcloud_backup_${TIMESTAMP}.tar"
    TAR_CMD="tar -cf"
elif [[ "$COMPRESSION_MODE" == "pigz" ]]; then
    FINAL_BACKUP_NAME="nextcloud_backup_${TIMESTAMP}.tar.gz"
    TAR_CMD="tar -I pigz -cf"
else
    FINAL_BACKUP_NAME="nextcloud_backup_${TIMESTAMP}.tar.gz"
    TAR_CMD="tar -czf"
fi

FINAL_BACKUP_PATH="${LOCAL_BACKUP_DIR}/${FINAL_BACKUP_NAME}"
mkdir -p "$LOCAL_BACKUP_DIR"

# 1. Congelar la instancia
info "Activando Modo Mantenimiento en Nextcloud..."
sudo -u www-data php "$NC_ROOT/occ" maintenance:mode --on

# 2. Respaldar base de datos
info "Exportando base de datos MariaDB ($DB_NAME)..."
mysqldump --single-transaction -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$DB_TMP_FILE"

# 3. Empaquetado al vuelo
info "Empaquetando archivos usando método [${COMPRESSION_MODE^^}]..."
$TAR_CMD "$FINAL_BACKUP_PATH" \
    -C "$(dirname "$DB_TMP_FILE")" "$(basename "$DB_TMP_FILE")" \
    -C "$NC_ROOT" "config" \
    -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")"

# 4. Devolver servicio a la vida (Downtime minimizado)
info "Desactivando Modo Mantenimiento..."
sudo -u www-data php "$NC_ROOT/occ" maintenance:mode --off
rm -f "$DB_TMP_FILE"

# 5. Gestión del destino: ¿Subida offsite o permanencia local?
if [[ "$USE_CLOUD" == "yes" ]]; then
    info "Subiendo backup a la nube ($RCLONE_REMOTE) mediante Rclone..."
    rclone copy "$FINAL_BACKUP_PATH" "${RCLONE_REMOTE}:${RCLONE_FOLDER}/"
    ok "¡Subida a la nube finalizada con éxito!"
    
    info "Aplicando política de retención en la nube: Eliminando residuo del host local..."
    rm -f "$FINAL_BACKUP_PATH"
else
    ok "¡Respaldo local guardado correctamente en: $FINAL_BACKUP_PATH!"
    
    # Aplicar rotación local usando 'find' seguro para no saturar el almacenamiento
    info "Aplicando política de rotación local (Conservar últimos $LOCAL_RETENTION_DAYS días)..."
    find "$LOCAL_BACKUP_DIR" -type f -name "nextcloud_backup_*" -mtime +"$LOCAL_RETENTION_DAYS" -exec rm -f {} \;
    ok "Rotación completada."
fi

echo ""
ok "=================================================================="
ok "   ¡RESPALDO DE NEXTCLOUD FINALIZADO CORRECTAMENTE!               "
ok "=================================================================="
if [[ "$USE_CLOUD" == "yes" ]]; then
    echo " Ubicación:  Nube -> ${RCLONE_FOLDER}/${FINAL_BACKUP_NAME}"
else
    echo " Ubicación:  Local -> $FINAL_BACKUP_PATH"
    echo " Rotación:   Manteniendo solo copias de los últimos $LOCAL_RETENTION_DAYS días."
fi
echo "=================================================================="