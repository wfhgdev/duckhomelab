#!/bin/bash

# 1. Preguntar dinámicamente el usuario de Ubuntu
echo -n "Introduce tu nombre de usuario de Ubuntu: "
read USUARIO

# Validar que el usuario no esté vacío y exista su carpeta en /home
if [ -z "$USUARIO" ] || [ ! -d "/home/$USUARIO" ]; then
    echo "❌ Error: El usuario proporcionado no es válido o no tiene una carpeta en /home."
    exit 1
fi

# 2. Configuración de variables (Rutas bien estructuradas)
CONTAINER="nextcloud-app"
DESTINO="/home/$USUARIO"
NOMBRE_ARCHIVO="nextcloud_data_backup.tar"
RUTA_VOLUMEN="/var/lib/docker/volumes/nextcloud_nextcloud_data/_data"

echo "========================================================="
echo "   INICIANDO RESPALDO DE NEXTCLOUD (SOLO EMPAQUETADO)     "
echo "========================================================="

# 1. Congelar Nextcloud para evitar corrupción de datos
echo "--> 1/4 Activando modo mantenimiento..."
docker exec --user www-data $CONTAINER php occ maintenance:mode --on

echo "---------------------------------------------------------"
# 2. Crear el paquete .tar sin comprimir
echo "--> 2/4 Empaquetando archivos en $DESTINO/$NOMBRE_ARCHIVO..."
# Usamos sudo para leer el volumen de Docker que suele ser de root
sudo tar -cvf "$DESTINO/$NOMBRE_ARCHIVO" -C "$RUTA_VOLUMEN" .
echo "---------------------------------------------------------"

# 3. Devolver la nube a la vida
echo "--> 3/4 Desactivando modo mantenimiento..."
docker exec --user www-data $CONTAINER php occ maintenance:mode --off

# 4. Corregir permisos para poder descargarlo por WinSCP
echo "--> 4/4 Asignando propiedad del archivo al usuario '$USUARIO'..."
sudo chown $USUARIO:$USUARIO "$DESTINO/$NOMBRE_ARCHIVO"

echo "========================================================="
echo "  ¡PROCESO FINALIZADO CON ÉXITO!                         "
echo "  Archivo disponible en: $DESTINO/$NOMBRE_ARCHIVO        "
echo "========================================================="