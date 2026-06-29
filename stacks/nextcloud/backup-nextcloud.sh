#!/bin/bash

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
echo "--------------------------------------------------------..."
echo "Selecciona el destino del respaldo:"
echo "1) En tu carpeta Home ($HOME_USUARIO)"
echo "2) En otra ruta local personalizada (Ej: /media/mi_disco)"
echo "3) Enviar directo a carpeta compartida de Windows (LAN)"
echo "--------------------------------------------------------..."
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
        echo "========================================================="
        echo "🔑 CONFIGURACIÓN DE RED WINDOWS (SAMBA/CIFS)"
        echo "========================================================="
        read -p "  -> IP del PC Windows (Ej: 192.168.1.50): " SMB_SERVER
        read -p "  -> Nombre del recurso compartido (Folder): " SMB_SHARE
        read -p "  -> Usuario de Windows: " SMB_USER
        read -s -p "  -> Contraseña de Windows (no se mostrará al escribir): " SMB_PASS
        echo "" # Salto de línea necesario después del password oculto
        echo "========================================================="

        # Validar que no se dejen campos vacíos
        if [ -z "$SMB_SERVER" ] || [ -z "$SMB_SHARE" ] || [ -z "$SMB_USER" ] || [ -z "$SMB_PASS" ]; then
            echo "❌ Error: Todos los datos de la red Windows son obligatorios."
            exit 1
        fi

        echo "--> Intentando conectar con //$SMB_SERVER/$SMB_SHARE..."
        
        # Verificar que cifs-utils esté instalado
        if ! command -v mount.cifs &> /dev/null; then
            echo "❌ Error: 'cifs-utils' no está instalado."
            echo "👉 Ejecuta primero en tu terminal: sudo apt install cifs-utils"
            exit 1
        fi

        # Crear el punto de montaje temporal
        if [ ! -d "$PUNTO_MONTAJE" ]; then
            sudo mkdir -p "$PUNTO_MONTAJE"
        fi

        # Montar en caliente mapeando los permisos con tus IDs locales
        sudo mount -t cifs -o username="$SMB_USER",password="$SMB_PASS",uid=$(id -u $USUARIO_REAL),gid=$(id -g $USUARIO_REAL),iocharset=utf8 "//$SMB_SERVER/$SMB_SHARE" "$PUNTO_MONTAJE"
        
        if [ $? -ne 0 ]; then
            echo "❌ Error crítico: No se pudo montar la carpeta de Windows."
            echo "Asegúrate de que la carpeta esté bien compartida en Windows y que las credenciales sean correctas."
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
# 2. Exportar Base de Datos
echo "--> 2/4 Exportando estructura de Base de Datos MariaDB..."
docker exec -i $CONTAINER_DB mysqldump -unextcloud -p'1JsjXBq?1IK' nextcloud > "$DESTINO/$RESPALDO_SQL"
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

# 6. Desmontar carpeta de Windows si fue utilizada
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