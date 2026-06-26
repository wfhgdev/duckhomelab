#!/bin/bash

# Configuración de variables
CONTAINER="nextcloud-app"
DESTINO="/home/willi"
NOMBRE_ARCHIVO="nextcloud_data_backup.tar"
RUTA_VOLUMEN="/var/lib/docker/volumes/nextcloud_nextcloud_data/_data"
USUARIO="willi" #Digite nombre de usuario Ubuntu

echo "========================================================="
echo "  INICIANDO RESPALDO DE NEXTCLOUD (SOLO EMPAQUETADO)     "
echo "========================================================="

# 1. Congelar Nextcloud para evitar corrupción de datos
echo "--> 1/4 Activando modo mantenimiento..."
docker exec --user www-data $CONTAINER php occ maintenance:mode --on

echo "---------------------------------------------------------"
# 2. Crear el paquete .tar sin comprimir
echo "--> 2/4 Empaquetando archivos en $DESTINO/$NOMBRE_ARCHIVO..."
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
echo "  Archivo disponible en: $DESTINO/$NOMBRE_ARCHIVO       "
echo "========================================================="