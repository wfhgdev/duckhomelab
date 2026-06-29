#!/bin/bash

# ==============================================================================
# CONFIGURACIÓN DE RED WINDOWS (SAMBA/CIFS)
# Rellena estos datos una sola vez para activar la Opción 3
# ==============================================================================
SMB_SERVER="192.168.1.X"       # La IP de tu ordenador Windows
SMB_SHARE="NombreCompartido"   # El nombre del recurso compartido en Windows
SMB_USER="UsuarioWindows"      # Tu usuario de Windows
SMB_PASS="ContraseñaWindows"   # Tu contraseña de Windows
# ==============================================================================

# 1. Identificar automáticamente al usuario real de Ubuntu
USUARIO_REAL=${SUDO_USER:-$USER}
HOME_USUARIO="/home/$USUARIO_REAL"

# 2. Parámetros internos de Nextcloud y nombres de archivos
CONTAINER_APP="nextcloud-app"
CONTAINER_DB="nextcloud-db"
FECHA=$(date +%Y%m%d_%H%M%S)
RESPALDO_DATA="nextcloud_datos_$FECHA.tar"
RESPALDO_SQL="nextcloud_base_datos_$FECHA.sql"
RUTA_VOLUMEN_DATA="/var/lib/docker/volumes/nextcloud_nextcloud_data/_data"

# Variables de control para el montaje dinámico
PUNTO_MONTAJE="/mnt/nextcloud_backup_smb"
NECESITA_DESMONTAR=false
APLICAR_CHOWN=true

echo "========================================================="
echo "    GESTOR DE RESPALDOS AUTOMÁTICO DE NEXTCLOUD          "
echo "========================================================="
echo "👤 Usuario Ubuntu detectado: $USUARIO_REAL"
echo "🏠 Ruta Home asignada:       $HOME_USUARIO"
echo "---------------------------------------------------------"
echo "Selecciona el destino del respaldo:"
echo "1) En tu carpeta Home ($HOME_USUARIO)"
echo "2) En otra ruta local personalizada (Ej: /media/mi_disco)"
echo "3) Enviar directo a carpeta compartida de Windows (LAN)"
echo "---------------------------------------------------------"
read -p "Selecciona una opción [1-3]: " OPCION

case $OPCION in
    1)
        DESTINO="$HOME_USUARIO"
        ;;
    2)
        read -p "Introduce la ruta absoluta del directorio destino: " RUTA_PERSONALIZADA
        if [ ! -d "$RUTA_PERSONALIZADA" ]; then
            echo "❌ Error: La ruta introducida no existe."
            exit 1
        fi
        DESTINO="$RUTA_PERSONALIZADA"
        ;;
    3)
        echo "--> Preparando conexión con el entorno Windows ($SMB_SERVER)..."
        
        # Verificar que el paquete de red cifs-utils esté en el servidor
        if ! command -v mount.cifs &> /dev/null; then
            echo "❌ Error: 'cifs-utils' no está instalado en tu Ubuntu Server."
            echo "👉 Por favor ejecuta primero: sudo apt install cifs-utils"
            exit 1
        fi

        # Crear el directorio temporal de montaje si no existe
        if [ ! -d "$PUNTO_MONTAJE" ]; then
            sudo mkdir -p "$PUNTO_MONTAJE"
        fi

        # Montar en caliente aplicando tus IDs de Linux para evitar bloqueos de permisos
        sudo mount -t cifs -o username="$SMB_USER",password="$SMB_PASS",uid=$(id -u $USUARIO_REAL),gid=$(id -g $USUARIO_REAL),iocharset=utf8 "//$SMB_SERVER/$SMB_SHARE" "$PUNTO_MONTAJE"
        
        if [ $? -ne 0 ]; then
            echo "❌ Error crítico: No se pudo montar la carpeta de Windows."
            echo "Verifica que la IP, el nombre del recurso compartido y tus credenciales sean correctos."
            exit 1
        fi

        DESTINO="$PUNTO_MONTAJE"
        NECESITA_DESMONTAR=true
        APLICAR_CHOWN=false # En redes Windows Samba, los permisos se gestionan en el montaje.
        echo "✅ Red Windows conectada y mapeada con éxito."
        ;;
    *)
        echo "❌ Opción inválida. Proceso cancelado."
        exit 1
        ;;
esac

echo "========================================================="
echo "   INICIANDO RESPALDO SELECTIVO (DATOS DE USUARIO + BD)   "
echo "========================================================="

# 1. Modo mantenimiento para blindar los archivos durante la copia
echo "--> 1/4 Activando modo mantenimiento en Nextcloud..."
docker exec --user www-data $CONTAINER_APP php occ maintenance:mode --on

echo "---------------------------------------------------------"
# 2. Volcado de Base de Datos directo al destino elegido
echo "--> 2/4 Exportando estructura de Base de Datos MariaDB..."
docker exec -i $CONTAINER_DB mysqldump -unextcloud -p'1JsjXBq?1IK' nextcloud > "$DESTINO/$RESPALDO_SQL"
if [ $? -eq 0 ]; then
    echo "   ✅ Base de datos volcada correctamente."
else
    echo "   ❌ Falló la exportación de la Base de Datos."
fi

echo "---------------------------------------------------------"
# 3. Empaquetar únicamente los datos reales del usuario y la config base
echo "--> 3/4 Empaquetando exclusivamente directorios 'data' y 'config'..."
sudo tar -cvf "$DESTINO/$RESPALDO_DATA" -C "$RUTA_VOLUMEN_DATA" data config
if [ $? -eq 0 ]; then
    echo "   ✅ Archivos de usuario empaquetados correctamente."
else
    echo "   ❌ Falló el empaquetado de archivos."
fi
echo "---------------------------------------------------------"

# 4. Devolver Nextcloud a producción
echo "--> 4/4 Desactivando modo mantenimiento..."
docker exec --user www-data $CONTAINER_APP php occ maintenance:mode --off

# 5. Modificar permisos de descarga si el archivo se quedó en local
if [ "$APLICAR_CHOWN" = true ]; then
    echo "--> Otorgando propiedad de los archivos a '$USUARIO_REAL' para WinSCP..."
    sudo chown $USUARIO_REAL:$USUARIO_REAL "$DESTINO/$RESPALDO_SQL"
    sudo chown $USUARIO_REAL:$USUARIO_REAL "$DESTINO/$RESPALDO_DATA"
fi

# 6. Desmontaje y limpieza limpia si se usó Windows
if [ "$NECESITA_DESMONTAR" = true ]; then
    echo "---------------------------------------------------------"
    echo "--> Limpiando entorno: Desmontando almacenamiento de Windows..."
    sudo umount "$PUNTO_MONTAJE"
    sudo rmdir "$PUNTO_MONTAJE"
    echo "   ✅ Conexión de red cerrada de forma segura."
fi

echo "========================================================="
echo "  ¡RESPALDO FINALIZADO CON ÉXITO!                        "
if [ "$NECESITA_DESMONTAR" = true ]; then
    echo "  Los archivos fueron enviados directo a tu PC Windows:  "
    echo "  📂 Recurso: //$SMB_SERVER/$SMB_SHARE/"
    echo "  📄 -> $RESPALDO_SQL"
    echo "  📄 -> $RESPALDO_DATA"
else
    echo "  Ubicación de los archivos locales:                     "
    echo "  📄 BD: $DESTINO/$RESPALDO_SQL                          "
    echo "  📄 Archivos: $DESTINO/$RESPALDO_DATA                   "
fi
echo "========================================================="