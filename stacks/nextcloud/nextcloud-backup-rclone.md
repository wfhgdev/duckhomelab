# Nextcloud Backup rclone 🚀

`Nextcloud Backup rclone` es un script en Bash altamente robusto, idempotente y automatizado diseñado para realizar copias de seguridad completas de instancias convencionales (*bare-metal*) de Nextcloud. 

El script congela la aplicación de forma segura, extrae la base de datos MariaDB/MySQL, empaqueta el código y los datos de usuario al vuelo, y sincroniza el resultado con nubes comerciales como **Google Drive** o **OneDrive** utilizando **Rclone**. Una vez completada la subida, libera el 100% del espacio local ocupado por el respaldo.

---

## ✨ Características Principales

* **Autodetección Inteligente:** Utiliza el propio intérprete de PHP nativo para parsear de forma limpia el archivo `config.php`. Extrae automáticamente las credenciales de la base de datos y la ruta de datos sin intervención humana.
* **Seguridad Perimetral (Fail-Safe):** Implementa un manejador de señales estricto (`trap`). Si el script llega a fallar a mitad del proceso (por ejemplo, por falta de espacio intermedio), Nextcloud es retirado del modo mantenimiento automáticamente para evitar caídas persistentes del servicio.
* **Compresión Eficiente al Vuelo:** Empaqueta los directorios directamente hacia el archivo final de destino usando redirección de rutas dinámicas de `tar`, evitando duplicar innecesariamente el uso de almacenamiento temporal en el host.
* **Retención Local Estricta (Cero Residuo):** Diseñado específicamente para servidores con almacenamiento limitado. El archivo comprimido se elimina del servidor local en cuanto Rclone confirma la subida correcta a la nube.
* **Idempotencia y Persistencia:** En su primera ejecución genera un archivo de configuración en `/etc/nextcloud-backup.conf`. Las ejecuciones posteriores leen este archivo de forma silenciosa, permitiendo su automatización total.
* **Auto-instalación en Cron:** Ofrece la posibilidad de programarse por sí mismo en el demonio Cron del sistema para ejecutarse todas las noches de forma invisible.

---

## 🛠️ Requisitos del Sistema

El script ha sido validado y optimizado para el siguiente entorno, aunque es retrocompatible con versiones superiores e inferiores:
* **Sistemas Operativos:** Ubuntu Server 20.04 LTS (o superior) / Debian.
* **Nextcloud:** v24.0.12 (Compatible con ramas desde la v15 hasta la v30+).
* **PHP:** v7.4 o superior (Compatible con PHP 8.x).
* **Base de Datos:** MariaDB 10.6+ o MySQL 5.7 / 8.0.
* **Servidor Web:** Apache 2.4 o Nginx.
* **Privilegios:** Acceso de superusuario (`root` o `sudo`).

---

## 🚀 Modo de Uso y Despliegue

### 1. Descarga y asignación de permisos
Descarga el script en tu servidor y dale permisos de ejecución:
```bash
chmod +x nextcloud_backup_rclone.sh