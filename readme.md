# 🦆 DuckHomeLab

Entorno de homelab self-hosted automatizado sobre Ubuntu Server LTS, construido con Docker y gestionado desde el navegador. Un único script despliega la infraestructura base completa; los servicios adicionales se añaden como stacks independientes desde Dockge.

---

## 📋 Tabla de contenidos

- [Arquitectura general](#arquitectura-general)
- [Requisitos previos](#requisitos-previos)
- [Instalación base](#instalación-base)
- [Estructura de directorios](#estructura-de-directorios)
- [Servicios incluidos](#servicios-incluidos)
  - [Infraestructura base](#infraestructura-base)
  - [Stacks opcionales](#stacks-opcionales)
- [Certificado SSL Wildcard](#certificado-ssl-wildcard)
- [Proxy Hosts en NPM](#proxy-hosts-en-npm)
- [Seguridad](#seguridad)
- [Backups](#backups)
- [Estructura del repositorio](#estructura-del-repositorio)

---

## Arquitectura general

```
Internet
    │
    ▼
Router doméstico (puertos 80 y 443 abiertos)
    │
    ▼
Nginx Proxy Manager ──── Certificado wildcard *.tudominio.duckdns.org
    │
    ├── portainer.tudominio.duckdns.org  →  Portainer   (9443 https)
    ├── dockge.tudominio.duckdns.org     →  Dockge      (5001 http)
    ├── wg.tudominio.duckdns.org         →  WG-Easy     (51821 http)
    ├── fotos.tudominio.duckdns.org      →  Immich      (2283 http)
    └── nextcloud.tudominio.duckdns.org  →  Nextcloud   (80 http)

Red Docker interna: proxy-network (bridge, IPv4 only)
    ├── npm
    ├── portainer
    ├── dockge
    ├── duckdns
    ├── wg-easy          (también en red 'wg' para túnel VPN)
    ├── immich-server    (también en red 'immich-net' para servicios internos)
    └── nextcloud-app    (también en red 'nextcloud-net' para servicios internos)
```

Todos los servicios están conectados a la red Docker `proxy-network`. Los servicios con dependencias internas (bases de datos, caché, ML) usan redes adicionales aisladas e inaccesibles desde el exterior.

---

## Requisitos previos

### Hardware mínimo (con todos los servicios activos)

| Recurso | Mínimo | Recomendado |
|---|---|---|
| CPU | 4 núcleos | 6+ núcleos |
| RAM | 8 GB | 16 GB |
| Disco SO | 40 GB SSD | 60 GB SSD |
| Disco datos | Según biblioteca de fotos | SSD local |
| SO | Ubuntu Server 22.04 LTS | Ubuntu Server 24.04 LTS |

> Si ejecutas solo la infraestructura base (NPM + Portainer + Dockge + DuckDNS) los requisitos se reducen a 2 núcleos y 2 GB RAM.

### Requisitos de red

- Router con soporte de **port forwarding** (reenvío de puertos).
- Puertos abiertos en el router: **80/TCP**, **443/TCP**, **51820/UDP** (solo si usas WG-Easy).
- Cuenta gratuita en [DuckDNS](https://www.duckdns.org) con un subdominio creado.
- IP pública real (no CGNAT). Verifica con:

```bash
# Compara la salida de este comando con la IP WAN de tu router.
# Si son iguales, tienes IP pública real. Si son diferentes, tienes CGNAT.
curl -4 ifconfig.me
```

> Si tienes CGNAT, considera usar **Cloudflare Tunnel** como alternativa al port forwarding.

---

## Instalación base

El script `duckhomelab.sh` despliega automáticamente la infraestructura completa en un servidor Ubuntu limpio.

```bash
# Descarga y ejecuta el script como root
git clone https://github.com/wfhgdev/duckhomelab.git && cd duckhomelab && chmod +x duckhomelab.sh && sudo ./duckhomelab.sh
```

El script solicitará tres datos al inicio:

| Dato | Ejemplo |
|---|---|
| Subdominio DuckDNS | `mihomelab` (sin `.duckdns.org`) |
| Token DuckDNS | UUID de tu cuenta en duckdns.org |
| Zona horaria | `Europe/Madrid` |

### Modo de ejecución

El script soporta dos modos configurables mediante la variable `DOCKER_MODE`:

```bash
# Modo producción (por defecto): los servicios internos no exponen puertos al host
sudo bash duckhomelab.sh

# Modo desarrollo: expone el puerto 5001 de Dockge para debug directo
DOCKER_MODE=dev sudo bash duckhomelab.sh
```

### Qué hace el script

1. Actualiza el sistema e instala dependencias base (`curl`, `git`, `ca-certificates`, `gnupg`).
2. Instala **Docker Engine** y **Docker Compose v2** desde el repositorio oficial de Docker (no los paquetes de Ubuntu).
3. Añade el usuario actual al grupo `docker` para evitar usar `sudo` en cada comando.
4. Crea la red Docker `proxy-network` (bridge, IPv4).
5. Genera la estructura de directorios en `/opt/docker-services` y `/opt/stacks`.
6. Genera y despliega el `docker-compose.yml` con los 4 servicios base.
7. Verifica que los contenedores están en ejecución.
8. Muestra un resumen con los accesos y los próximos pasos.

> Tras la instalación, cierra sesión y vuelve a entrar para que el grupo `docker` tenga efecto.

---

## Estructura de directorios

```
/opt/
├── docker-services/          # Infraestructura base (gestionada por el script)
│   ├── docker-compose.yml
│   ├── npm/
│   │   ├── data/             # Configuración y logs de NPM
│   │   └── letsencrypt/      # Certificados SSL
│   ├── portainer/
│   │   └── data/
│   └── dockge/
│       └── data/
│
└── stacks/                   # Stacks adicionales (gestionados desde Dockge)
    ├── wg-easy/
    │   └── docker-compose.yml
    ├── immich/
    │   ├── docker-compose.yml
    │   ├── .env
    │   ├── library/          # Fotos y vídeos (crear antes de desplegar)
    │   └── postgres/         # Base de datos (crear antes de desplegar)
    └── nextcloud/
        └── docker-compose.yml
```

---

## Servicios incluidos

### Infraestructura base

Desplegados automáticamente por `duckhomelab.sh`.

#### DuckDNS

Actualiza automáticamente la IP pública de tu subdominio cada 5 minutos. No es un servicio web y **no necesita Proxy Host en NPM**. Trabaja completamente en segundo plano.

```bash
# Verificar que funciona correctamente
docker logs duckdns --tail 20
# Debes ver líneas con "OK" cada 5 minutos
```

#### Nginx Proxy Manager (NPM)

Proxy inverso con interfaz web para gestionar certificados SSL y redireccionar dominios a contenedores internos. Accesible en el puerto 81 de la red local.

```
URL local:            http://IP_SERVIDOR:81
Credenciales iniciales: admin@example.com / changeme
```

> Cambia la contraseña en el primer acceso. Cierra el puerto 81 en el router tras completar la configuración.

#### Portainer

Panel de administración visual de Docker. Accesible únicamente a través de NPM (no expone puertos al exterior).

```
Proxy Host: portainer.tudominio.duckdns.org → portainer:9443 (https)
```

> Tiene un temporizador de seguridad de **5 minutos** en el primer arranque. Si aparece el mensaje de timeout, ejecuta `docker restart portainer` y accede inmediatamente.

#### Dockge

Gestor visual de stacks de Docker Compose. Desde aquí se despliegan y gestionan todos los stacks opcionales. Accesible únicamente a través de NPM.

```
Proxy Host: dockge.tudominio.duckdns.org → dockge:5001 (http)
```

---

### Stacks opcionales

Desplegados manualmente desde Dockge en `/opt/stacks/`.

---

#### WG-Easy — VPN WireGuard

VPN personal con panel de administración web. Permite acceder de forma segura al homelab desde cualquier lugar.

**Archivo:** `stacks/wg-easy/docker-compose.yml`

**Requisitos adicionales:**
- Puerto **51820/UDP** abierto en el router.

**Características configuradas:**
- Imagen oficial `ghcr.io/wg-easy/wg-easy:15` (GitHub Container Registry).
- Solo IPv4 (`DISABLE_IPV6=true` + sysctl `net.ipv6.conf.all.disable_ipv6=1`).
- Panel web accesible vía NPM (`INSECURE=true` para comunicación HTTP interna).
- Red interna `wg` (10.42.42.0/24) para el túnel VPN, separada de `proxy-network`.
- IP fija `10.42.42.42` para el servidor dentro del túnel.

```
Proxy Host: wg.tudominio.duckdns.org → wg-easy:51821 (http)
VPN:        tudominio.duckdns.org:51820/UDP
```

> En v15 la configuración inicial (dominio, usuario, contraseña) se hace a través del **asistente web** en el primer acceso, no mediante variables de entorno.

**Evitar IPv6 leak en clientes:**

En el panel de WG-Easy → Settings → **Default Client Allowed IPs**:
```
0.0.0.0/0, ::/0
```

---

#### Immich — Gestión de fotos y vídeos

Alternativa self-hosted a Google Photos con reconocimiento facial, búsqueda inteligente y app móvil nativa.

**Archivos:** `stacks/immich/docker-compose.yml` y `stacks/immich/.env`

**Requisitos de hardware:**

| Recurso | Mínimo | Recomendado |
|---|---|---|
| CPU | 2 núcleos (x86-64-v2+) | 4 núcleos |
| RAM | 6 GB | 8 GB |
| Disco (sin fotos) | ~7 GB | SSD local |

**Crear directorios antes de desplegar:**
```bash
sudo mkdir -p /opt/stacks/immich/library
sudo mkdir -p /opt/stacks/immich/postgres
```

**Editar el `.env` antes de desplegar:**
```bash
DB_PASSWORD=cambiame_por_una_password_segura   # ← cambiar obligatoriamente
IMMICH_VERSION=v2
TZ=Europe/Madrid
UPLOAD_LOCATION=/opt/stacks/immich/library
DB_DATA_LOCATION=/opt/stacks/immich/postgres
IMMICH_MACHINE_LEARNING_ENABLED=false          # ML desactivado por defecto
```

**Características configuradas:**
- Valkey 9 (fork open-source de Redis) en lugar de Redis.
- PostgreSQL 14 con extensión VectorChord (imagen oficial de Immich, obligatoria).
- Machine Learning **desactivado por defecto** para reducir consumo de RAM y disco. Ver sección de reactivación en el propio `docker-compose.yml`.
- Red interna `immich-net` aísla postgres, redis y ML del resto del homelab.
- Solo `immich-server` conectado a `proxy-network`.

```
Proxy Host: fotos.tudominio.duckdns.org → immich-server:2283 (http)
            Websockets Support: ACTIVADO (obligatorio)
            HTTP/2 Support:     ACTIVADO
            HSTS Enabled:       ACTIVADO
```

> El primer usuario en registrarse se convierte en administrador.

---

#### Nextcloud — Plataforma de colaboración en la nube

Alternativa self-hosted a Google Drive / OneDrive con gestión de archivos, calendarios, contactos y colaboración en documentos.

**Archivo:** `stacks/nextcloud/docker-compose.yml`

**Características configuradas:**
- Imagen oficial `nextcloud:latest` con Apache 2.4 y PHP 8.5.
- MariaDB 11.8 como base de datos.
- Redis (Alpine) para caché de sesiones y bloqueo de archivos.
- Variables de proxy inverso preconfiguradas para NPM (`TRUSTED_PROXIES`, `OVERWRITEPROTOCOL`, `OVERWRITEHOST`).
- Script de optimización automática en el primer arranque (zona horaria, idioma, región, app de 2FA).
- SMTP comentado y listo para activar con credenciales de Gmail.
- Límites de PHP y upload comentados y listos para ajustar.

**Editar antes de desplegar:**
```yaml
MARIADB_ROOT_PASSWORD: 'contraseña-root-segura'
MARIADB_PASSWORD: 'contraseña-usuario-segura'
MYSQL_PASSWORD: 'contraseña-usuario-segura'   # debe coincidir con MARIADB_PASSWORD
NEXTCLOUD_TRUSTED_DOMAINS: nextcloud.tudominio.duckdns.org
OVERWRITEHOST: nextcloud.tudominio.duckdns.org
TZ: Europe/Madrid
```

```
Proxy Host: nextcloud.tudominio.duckdns.org → nextcloud-app:80 (http)
            Websockets Support: ACTIVADO (obligatorio)
            HTTP/2 Support:     ACTIVADO
            HSTS Enabled:       ACTIVADO
```

---

## Certificado SSL Wildcard

Un único certificado `*.tudominio.duckdns.org` cubre todos los subdominios del homelab. Se gestiona desde NPM y se renueva automáticamente cada 90 días mediante el plugin `certbot-dns-duckdns`.

**Obtener el certificado:**

En NPM → **Certificates → Add Certificate → Let's Encrypt via DNS**

| Campo | Valor |
|---|---|
| Domain Names | `*.tudominio.duckdns.org` y `tudominio.duckdns.org` |
| DNS Provider | `duckdns` |
| Credentials | `dns_duckdns_token=TU_TOKEN_DUCKDNS` |
| Propagation Seconds | `120` |

> El "Internal Error" que puede aparecer al guardar es un bug visual de NPM. Comprueba en `docker logs npm --tail 50` si el certificado se generó correctamente.

---

## Proxy Hosts en NPM

Resumen de todos los Proxy Hosts del homelab:

| Dominio | Contenedor | Puerto | Scheme | Websockets | HTTP/2 | HSTS |
|---|---|---|---|---|---|---|
| `portainer.tudominio.duckdns.org` | `portainer` | `9443` | `https` | — | ✅ | — |
| `dockge.tudominio.duckdns.org` | `dockge` | `5001` | `http` | — | ✅ | — |
| `wg.tudominio.duckdns.org` | `wg-easy` | `51821` | `http` | — | ✅ | — |
| `fotos.tudominio.duckdns.org` | `immich-server` | `2283` | `http` | ✅ | ✅ | ✅ |
| `nextcloud.tudominio.duckdns.org` | `nextcloud-app` | `80` | `http` | ✅ | ✅ | ✅ |

Todos usan el mismo certificado wildcard `*.tudominio.duckdns.org` con **Force SSL** activado.

---

## Seguridad

### Access Lists en NPM (recomendado)

Restringe el acceso a los paneles de administración (Portainer, Dockge) a tu IP o al rango de tu VPN WireGuard.

En NPM → **Access Lists → Add Access List:**

| Campo | Valor |
|---|---|
| Name | `solo-admin` |
| Allow | Tu IP pública |
| Allow | `10.42.42.0/24` (rango VPN WireGuard) |
| Deny | `all` |

Asigna esta lista en la pestaña **Access** de los Proxy Hosts de Portainer y Dockge.

### Fail2ban en el host

Banea automáticamente IPs con demasiados errores en los logs de NPM.

```bash
sudo apt install fail2ban -y
```

Configuración mínima en `/etc/fail2ban/jail.local`:

```ini
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5

[sshd]
enabled  = true
maxretry = 3
bantime  = 86400

[npm-proxy]
enabled  = true
port     = http,https
filter   = npm-proxy
logpath  = /opt/docker-services/npm/data/logs/proxy-host-*_access.log
maxretry = 10
findtime = 60
bantime  = 3600
```

Comandos útiles:

```bash
# Ver estado de los jails activos
sudo fail2ban-client status

# Ver IPs baneadas en NPM
sudo fail2ban-client status npm-proxy

# Desbanear una IP manualmente
sudo fail2ban-client set npm-proxy unbanip TU_IP

# Ver log de actividad
sudo tail -f /var/log/fail2ban.log
```

### Checklist de seguridad

- [ ] Contraseña de NPM cambiada en el primer acceso.
- [ ] Puerto 81 cerrado en el router tras la configuración inicial.
- [ ] Contraseña de Portainer configurada en los primeros 5 minutos.
- [ ] Contraseña de Dockge configurada en el primer acceso.
- [ ] `DB_PASSWORD` de Immich cambiada antes de desplegar.
- [ ] Contraseñas de MariaDB de Nextcloud cambiadas antes de desplegar.
- [ ] Access Lists en NPM para Portainer y Dockge.
- [ ] Fail2ban instalado y activo.
- [ ] Puertos abiertos en el router: solo 80/TCP, 443/TCP y 51820/UDP.
- [ ] Clientes WireGuard con `Allowed IPs: 0.0.0.0/0, ::/0` para evitar IPv6 leak.

---

## Backups

### Script de backup de Nextcloud

El script `backup-nextcloud.sh` realiza una copia de seguridad de los datos de Nextcloud de forma segura:

1. Activa el **modo mantenimiento** en Nextcloud para evitar corrupción de datos durante el backup.
2. Empaqueta todos los archivos del volumen en un `.tar` sin comprimir.
3. Desactiva el modo mantenimiento para devolver el servicio a los usuarios.
4. Corrige los permisos del archivo para descargarlo via SFTP/WinSCP.

```bash
# Uso
sudo bash backup-nextcloud.sh
# Genera: /home/willi/nextcloud_data_backup.tar
```

Editar las variables al inicio del script según tu entorno:

```bash
CONTAINER="nextcloud-app"       # nombre del contenedor de Nextcloud
DESTINO="/home/willi"           # directorio donde se guarda el backup
NOMBRE_ARCHIVO="nextcloud_data_backup.tar"
RUTA_VOLUMEN="/var/lib/docker/volumes/nextcloud_nextcloud_data/_data"
USUARIO="willi"                 # usuario Ubuntu para corregir permisos
```

### Backup general de todos los servicios

Para hacer backup de toda la configuración del homelab (sin los datos de usuario de Nextcloud/Immich):

```bash
# Infraestructura base
sudo tar -czf backup-docker-services.tar.gz /opt/docker-services

# Todos los stacks
sudo tar -czf backup-stacks.tar.gz /opt/stacks
```

---

## Estructura del repositorio

```
duckhomelab/
│
├── README.md
│
├── duckhomelab.sh              # Script principal de instalación de la infraestructura base
│
└── stacks/
    ├── wg-easy/
    │   └── docker-compose.yml  # WireGuard VPN + panel web (WG-Easy v15)
    │
    ├── immich/
    │   ├── docker-compose.yml  # Gestión de fotos self-hosted (Immich v2)
    │   └── .env                # Variables de entorno (DB, rutas, versión)
    │
    ├── nextcloud/
    │   ├── docker-compose.yml  # Plataforma colaborativa en la nube (Nextcloud v34)
    │   └── backup-nextcloud.sh # Script de backup seguro con modo mantenimiento
    │
    └── ...                     # Futuros stacks
```

---

## Tecnologías utilizadas

![Ubuntu](https://img.shields.io/badge/Ubuntu-Server_LTS-E95420?style=flat&logo=ubuntu&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose_v2-2496ED?style=flat&logo=docker&logoColor=white)
![Nginx](https://img.shields.io/badge/Nginx_Proxy_Manager-v2.15-009639?style=flat&logo=nginx&logoColor=white)
![WireGuard](https://img.shields.io/badge/WireGuard-VPN-88171A?style=flat&logo=wireguard&logoColor=white)
![Immich](https://img.shields.io/badge/Immich-v2-4250AF?style=flat)
![Nextcloud](https://img.shields.io/badge/Nextcloud-v34-0082C9?style=flat&logo=nextcloud&logoColor=white)
![DuckDNS](https://img.shields.io/badge/DuckDNS-DDNS-yellow?style=flat)
![Let's Encrypt](https://img.shields.io/badge/Let's_Encrypt-Wildcard_SSL-003A70?style=flat&logo=letsencrypt&logoColor=white)

---

> **Nota:** Este proyecto está diseñado para uso doméstico y educativo. Revisa y adapta las contraseñas, dominios y rutas a tu entorno antes de desplegar en producción.