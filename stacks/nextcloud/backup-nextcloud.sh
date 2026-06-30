#!/bin/bash

# 1. Identificar automáticamente al usuario real de Ubuntu
USUARIO_REAL=${SUDO_USER:-$USER}
HOME_USUARIO="/home/$USUARIO_REAL"

# 2. Nombres de los contenedores
CONTAINER_APP="nextcloud-app"
CONTAINER_DB="nextcloud-db"

# 3. Parámetros de tiempo y archivos
FECHA=$(date +%Y%m%d_%H%M%S)
RESPALDO_DATA="nextcloud_datos_$FECHA.tar"
RESPALDO_SQL="nextcloud_base_datos_$FECHA.sql"
RUTA_VOLUMEN_DATA="/var/lib/docker/volumes/nextcloud_nextcloud_data/_data"

# Variables de control para el montaje dinámico
PUNTO_MONTAJE="/mnt/nextcloud_backup_smb"
NECESITA_DESMONTAR=false
APLICAR_CHOWN=true

echo "========================================================="
echo "   GESTOR DE RESPALDOS AUTOMÁTICO DE NEXTCLOUD DOCKER          "
echo "========================================================="
echo "👤 Usuario Ubuntu detectado: $USUARIO_REAL"
echo "🏠 Ruta Home asignada:       $HOME_USUARIO"

# 🛠️ EXTRACCIÓN AUTOMÁTICA DE CREDENCIALES DE LA BD
# Usamos 'tr -d \r' porque la salida de Docker a veces incluye retornos de carro invisibles
echo "--> Detectando credenciales de la Base de Datos..."
DB_USER=$(docker exec $CONTAINER_APP printenv MYSQL_USER | tr -d '\r')
DB_PASS=$(docker exec $CONTAINER_APP printenv MYSQL_PASSWORD | tr -d '\r')
DB_NAME=$(docker exec $CONTAINER_APP printenv MYSQL_DATABASE | tr -d '\r')

# Validar si el contenedor está apagado o no se pudieron leer las variables
if [ -z "$DB_USER" ] || [ -z "$DB_PASS" ] || [ -z "$DB_NAME" ]; then
    echo "❌ Error crítico: No se pudieron leer las credenciales desde $CONTAINER_APP."
    echo "👉 Asegúrate de que los contenedores de Nextcloud estén encendidos ('up')."
    exit 1
fi
echo "    ✅ Base de Datos:  $DB_NAME"
echo "    ✅ Usuario DB:     $DB_USER"
echo "    ✅ Contraseña DB:  🔐 [Detectada con éxito]"

echo "---------------------------------------------------------"
echo "Selecciona el destino del respaldo:"
echo "1) En tu carpeta Home ($HOME_USUARIO)"
echo "2) En otra ruta local personalizada (Ej: /media/mi_disco)"
echo "3) Enviar directo a carpeta compartida de Windows (SBM/CIFS)"
echo "---------------------------------------------------------"
read -p "Selecciona una opción [1-3]: " OPCION

case $OPCION in
    1)
        DESTINO="$HOME_USUARIO"
        ;;
    2)
        #Comando para listar todas las particiones de los discos: sudo fdisk -l
        read -p "Introduce la ruta absoluta del directorio destino: " RUTA_PERSONALIZADA
        if [ ! -d "$RUTA_PERSONALIZADA" ]; then
            echo "❌ Error: La ruta introducida no existe."
            exit 1
        fi
        DESTINO="$RUTA_PERSONALIZADA"
        ;;
    3)
        echo "========================================================="
        echo "🔑 CONFIGURACIÓN DE RED WINDOWS (SAMBA/CIFS)"
        echo "========================================================="
        read -p "  -> IP del PC Windows (Ej: 192.168.1.50): " SMB_SERVER
        read -p "  -> Nombre del recurso compartido (Folder): " SMB_SHARE
        read -p "  -> Usuario de Windows: " SMB_USER
        read -s -p "  -> Contraseña de Windows (no se mostrará al escribir): " SMB_PASS
        echo "" 
        echo "========================================================="

        if [ -z "$SMB_SERVER" ] || [ -z "$SMB_SHARE" ] || [ -z "$SMB_USER" ] || [ -z "$SMB_PASS" ]; then
            echo "❌ Error: Todos los datos de la red Windows son obligatorios."
            exit 1
        fi

        # Verificación e instalación de cifs-utils
        if ! command -v mount.cifs &> /dev/null; then
            echo "--> 🛠️ 'cifs-utils' no está instalado. Instalándolo automáticamente..."
            apt update && apt install -y cifs-utils
            if [ $? -ne 0 ]; then
                echo "❌ Error crítico: No se pudo instalar 'cifs-utils'."
                exit 1
            fi
            echo "✅ 'cifs-utils' se instaló correctamente."
        fi

        echo "--> Intentando conectar con //$SMB_SERVER/$SMB_SHARE..."

        if [ ! -d "$PUNTO_MONTAJE" ]; then
            sudo mkdir -p "$PUNTO_MONTAJE"
        fi

        sudo mount -t cifs -o username="$SMB_USER",password="$SMB_PASS",uid=$(id -u $USUARIO_REAL),gid=$(id -g $USUARIO_REAL),iocharset=utf8 "//$SMB_SERVER/$SMB_SHARE" "$PUNTO_MONTAJE"
        
        if [ $? -ne 0 ]; then
            echo "❌ Error crítico: No se pudo montar la carpeta de Windows."
            sudo rmdir "$PUNTO_MONTAJE" 2>/dev/null
            exit 1
        fi

        DESTINO="$PUNTO_MONTAJE"
        NECESITA_DESMONTAR=true
        APLICAR_CHOWN=false
        echo "✅ Red Windows conectada correctamente."
        ;;
    *)
        echo "❌ Opción inválida. Proceso cancelado."
        exit 1
        ;;
esac

echo "========================================================="
echo "   INICIANDO RESPALDO SELECTIVO (DATOS DE USUARIO + BD)   "
echo "========================================================="

# 1. Modo mantenimiento
echo "--> 1/4 Activando modo mantenimiento en Nextcloud..."
docker exec --user www-data $CONTAINER_APP php occ maintenance:mode --on

echo "---------------------------------------------------------"
# 2. Exportar Base de Datos usando las variables auto-detectadas
echo "--> 2/4 Exportando estructura de Base de Datos MariaDB..."
docker exec -i $CONTAINER_DB mysqldump -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$DESTINO/$RESPALDO_SQL"
if [ $? -eq 0 ]; then
    echo "   ✅ Base de datos volcada correctamente."
else
    echo "   ❌ Falló la exportación de la Base de Datos."
fi

echo "---------------------------------------------------------"
# 3. Empaquetar datos de usuario
echo "--> 3/4 Empaquetando exclusivamente directorios 'data' y 'config'..."
sudo tar -cvf "$DESTINO/$RESPALDO_DATA" -C "$RUTA_VOLUMEN_DATA" data config
if [ $? -eq 0 ]; then
    echo "   ✅ Archivos de usuario empaquetados correctamente."
else
    echo "   ❌ Falló el empaquetado de archivos."
fi
echo "---------------------------------------------------------"

# 4. Desactivar modo mantenimiento
echo "--> 4/4 Desactivando modo mantenimiento..."
docker exec --user www-data $CONTAINER_APP php occ maintenance:mode --off

# 5. Aplicar permisos locales (Solo si no es Windows)
if [ "$APLICAR_CHOWN" = true ]; then
    echo "--> Otorgando propiedad de los archivos a '$USUARIO_REAL' para WinSCP..."
    sudo chown $USUARIO_REAL:$USUARIO_REAL "$DESTINO/$RESPALDO_SQL"
    sudo chown $USUARIO_REAL:$USUARIO_REAL "$DESTINO/$RESPALDO_DATA"
fi

# Calcular el peso de los archivos generados antes de desmontar
PESO_SQL=$(du -sh "$DESTINO/$RESPALDO_SQL" 2>/dev/null | awk '{print $1}')
PESO_DATA=$(du -sh "$DESTINO/$RESPALDO_DATA" 2>/dev/null | awk '{print $1}')

# 6. Desmontar carpeta de Windows si fue utilizada
if [ "$NECESITA_DESMONTAR" = true ]; then
    echo "--> Limpiando entorno: Desmontando almacenamiento de Windows..."
    sudo umount "$PUNTO_MONTAJE"
    sudo rmdir "$PUNTO_MONTAJE"
    echo "   ✅ Conexión de red cerrada de forma segura."
fi

echo "========================================================="
echo "  ¡RESPALDO FINALIZADO CON ÉXITO!                        "
echo "========================================================="
if [ "$NECESITA_DESMONTAR" = true ]; then
    echo "  Los archivos fueron enviados directo a tu PC Windows:  "
    echo "  📂 Recurso LAN: //$SMB_SERVER/$SMB_SHARE/"
else
    echo "  Ubicación de los archivos locales del servidor:        "
    echo "  📂 Carpeta:     $DESTINO"
fi
echo "---------------------------------------------------------"
echo "  📦 DETALLE DE ARCHIVOS Y PESO:"
echo "  📄 Base de Datos:  $RESPALDO_SQL ($PESO_SQL)"
echo "  📄 Datos y Config: $RESPALDO_DATA ($PESO_DATA)"
echo "========================================================="