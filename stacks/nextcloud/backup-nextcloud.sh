#!/bin/bash

# 1. Preguntar dinámicamente el usuario de Ubuntu
echo -n "Introduce tu nombre de usuario de Ubuntu: "
read USUARIO

if [ -z "$USUARIO" ] || [ ! -d "/home/$USUARIO" ]; then
    echo "❌ Error: El usuario proporcionado no es válido."
    exit 1
fi

# 2. Configuración de variables
CONTAINER_APP="nextcloud-app"
CONTAINER_DB="nextcloud-db"
DESTINO="/home/$USUARIO"
FECHA=$(date +%Y%m%d_%H%M%S)

# Nombres de los archivos de salida
RESPALDO_DATA="nextcloud_datos_$FECHA.tar"
RESPALDO_SQL="nextcloud_base_datos_$FECHA.sql"

# Rutas internas de Docker
RUTA_VOLUMEN_DATA="/var/lib/docker/volumes/nextcloud_nextcloud_data/_data"

echo "========================================================="
echo "   INICIANDO RESPALDO SELECTIVO (DATOS DE USUARIO + BD)   "
echo "========================================================="

# 1. Congelar Nextcloud para evitar escrituras durante el proceso
echo "--> 1/4 Activando modo mantenimiento..."
docker exec --user www-data $CONTAINER_APP php occ maintenance:mode --on

echo "---------------------------------------------------------"
# 2. Respaldar la Base de Datos (Extrae un archivo .sql limpio)
echo "--> 2/4 Exportando Base de Datos MariaDB..."
# Extrae las credenciales directamente de las variables del contenedor para que no tengas que escribirlas aquí
docker exec -i $CONTAINER_DB mysqldump -unextcloud -p'1JsjXBq?1IK' nextcloud > "$DESTINO/$RESPALDO_SQL"
echo "   ✅ Base de datos exportada en: $DESTINO/$RESPALDO_SQL"

echo "---------------------------------------------------------"
# 3. Empaquetar SOLO los datos de usuario y las configuraciones básicas
echo "--> 3/4 Empaquetando carpetas 'data' y 'config'..."
sudo tar -cvf "$DESTINO/$RESPALDO_DATA" -C "$RUTA_VOLUMEN_DATA" data config
echo "   ✅ Archivos empaquetados en: $DESTINO/$RESPALDO_DATA"
echo "---------------------------------------------------------"

# 4. Devolver la nube a la vida
echo "--> 4/4 Desactivando modo mantenimiento..."
docker exec --user www-data $CONTAINER_APP php occ maintenance:mode --off

# 5. Corregir permisos para WinSCP
echo "--> 5/4 Asignando propiedad de los archivos a '$USUARIO'..."
sudo chown $USUARIO:$USUARIO "$DESTINO/$RESPALDO_SQL"
sudo chown $USUARIO:$USUARIO "$DESTINO/$RESPALDO_DATA"

echo "========================================================="
echo "  ¡RESPALDO COMPLETADO CON ÉXITO!                        "
echo "  1. BD: $DESTINO/$RESPALDO_SQL                          "
echo "  2. Archivos: $DESTINO/$RESPALDO_DATA                   "
echo "========================================================="