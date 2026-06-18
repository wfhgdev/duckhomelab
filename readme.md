# 🦆 DuckHomeLab V4 por William H.

**DuckHomeLab** es un instalador en Bash listo para producción que automatiza el despliegue de un home-lab completo basado en Docker, con proxy inverso centralizado, SSL automático y servicios self-hosted modernos.

Está diseñado para ser:

* Simple de instalar (1 comando)
* Seguro por defecto
* Automático (zero manual config tras setup)
* Extensible (stacks opcionales)

---

# 🚀 ¿Qué instala DuckHomeLab?

## 🧱 Infraestructura base

* Docker Engine
* Docker Networks separadas (proxy / internal / vpn)
* Nginx Proxy Manager (NPM) como único reverse proxy
* Dockge (gestión de stacks Docker)
* Portainer (gestión avanzada Docker)

---

## 🌐 Reverse Proxy + SSL (CORE V4)

* NPM como único punto de entrada
* API automation completa
* Auto creación de hosts
* SSL automático con Let's Encrypt
* Redirecciones HTTP → HTTPS
* Autodiscovery de containers Docker

---

## 🧠 Aplicaciones principales

* Nextcloud (con Redis + MariaDB optimizado)
* Nginx Proxy Manager (central)
* Dockge
* Portainer

---

## 📦 Stacks opcionales

Seleccionables durante instalación:

* Immich (Photos self-hosted)
* Jellyfin (media server)
* WireGuard Easy (VPN simple)
* AdGuard Home (DNS adblocker)
* Fail2Ban (seguridad SSH/NPM)

---

## 💾 Backups (OPCIONAL)

DuckHomeLab NO obliga backups.

El usuario decide:

* Activar o no
* Motor:

  * `restic` (recomendado)
  * `rsync` (simple)
* Frecuencia:

  * diario
  * semanal
  * personalizado
* Hora configurable
* Destino:

  * local
  * disco externo
  * SSH remoto

Incluye modo restore interactivo.

---

# ⚙️ Arquitectura de red

```plaintext
Docker Networks:

proxy-net
 ├── nginx-proxy-manager
 ├── nextcloud
 ├── immich
 ├── jellyfin
 └── adguard

internal-net
 ├── mariadb
 ├── redis
 └── app-backends

vpn-net
 └── wireguard-easy (UDP 51820)
```

---

# 🚀 Instalación (1 solo comando)

```bash
curl -fsSL https://get.docker.com | sudo bash && \
git clone <YOUR_REPO_URL> DuckHomeLab && \
cd DuckHomeLab && \
chmod +x install.sh && \
sudo ./install.sh
```

---

# 🌍 Dominio (DuckDNS)

DuckHomeLab usa DuckDNS como proveedor por defecto:

Ejemplo:

```
https://cloud.tudominio.duckdns.org
```

Incluye:

* Auto actualización IP
* Integración automática con NPM
* Certificados SSL automáticos

---

# 🤖 AUTODISCOVERY (Docker → NPM)

Los servicios se publican automáticamente si incluyen labels:

```yaml
labels:
  - proxy.enable=true
  - proxy.host=cloud
  - proxy.port=8080
```

Resultado:

```
cloud.tudominio.duckdns.org → container:8080
```

---

# 🔐 SEGURIDAD

Incluye por defecto:

* Fail2Ban (SSH + NPM protection)
* UFW firewall (si habilitado)
* Docker network isolation
* Passwords aleatorios seguros:

  * MariaDB
  * Redis
  * WireGuard peers

---

# 📊 REPORTE FINAL (POST-INSTALL)

Al terminar la instalación se muestra:

```plaintext
================== DUCKHOMELAB REPORT ==================

CORE SERVICES
- NPM: http://SERVER_IP:81
- Portainer: http://SERVER_IP:9000
- Dockge: http://SERVER_IP:5001

APPLICATIONS
- Nextcloud: https://cloud.xxx.duckdns.org
- Jellyfin: https://media.xxx.duckdns.org
- Immich: https://photos.xxx.duckdns.org

SECURITY
- Fail2Ban: ENABLED
- UFW: ACTIVE

BACKUP
- Status: OPTIONAL
- Engine: restic
- Schedule: daily 03:00
- Path: /mnt/backups/duckhomelab

========================================================
```

---

# 🧩 STACKS OPCIONALES

Durante instalación:

```plaintext
[ ] Immich Photos
[ ] Jellyfin
[ ] WireGuard Easy
[ ] AdGuard Home
[ ] Fail2Ban (recommended)
[ ] Backups (optional)
```

---

# 🧠 DECISIONES DE DISEÑO (V4)

* NPM = único reverse proxy (no alternativas)
* Todo servicio interno bloqueado por defecto
* Redis obligatorio para Nextcloud performance
* No exposición directa de apps (solo proxy)
* WireGuard aislado en UDP 51820
* DNS siempre via DuckDNS

---

# ⚠️ PRINCIPIOS DEL PROYECTO

DuckHomeLab sigue 3 reglas:

1. Automatización primero
2. Seguridad por defecto
3. Cero configuración manual post-install

---

# 🏁 ESTADO

✔ V4 definida
✔ Arquitectura estable
✔ Stacks opcionales definidos
✔ Backups desacoplados y opcionales
✔ Proxy centralizado en NPM