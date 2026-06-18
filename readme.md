Aquí tienes el **README.md actualizado listo para copiar**, con el repo real y el instalador correcto (`duckhomelab.sh`).

---

# 🦆 DuckHomeLab V4

**DuckHomeLab** es un instalador en Bash orientado a producción para desplegar un home-lab completo basado en Docker con proxy inverso centralizado, SSL automático y stacks self-hosted.

Diseñado para ser:

* 🚀 Instalación en 1 solo comando
* 🔐 Seguro por defecto
* 🤖 Automatizado (cero configuración manual tras instalación)
* 🧩 Extensible con stacks opcionales

---

# 🚀 ¿Qué instala DuckHomeLab?

## 🧱 Infraestructura base

* Docker Engine
* Docker Networks (proxy / internal / vpn)
* Nginx Proxy Manager (NPM) como reverse proxy central
* Dockge
* Portainer

---

## 🌐 Reverse Proxy + SSL (CORE V4)

* NPM como único punto de entrada
* API automation completa
* Auto creación de hosts
* SSL automático (Let's Encrypt)
* HTTP → HTTPS redirect
* Autodiscovery de contenedores Docker

---

## 🧠 Aplicaciones principales

* Nextcloud (con Redis + MariaDB optimizado)
* Dockge
* Portainer

---

## 📦 Stacks opcionales

Seleccionables durante instalación:

* Immich (Photos self-hosted)
* Jellyfin (Media server)
* WireGuard Easy (VPN simple)
* AdGuard Home (DNS adblocker)
* Fail2Ban (seguridad SSH/NPM)

---

## 💾 Backups (OPCIONAL)

DuckHomeLab no obliga backups.

Configuración flexible:

* Motor:

  * `restic` (recomendado)
  * `rsync` (simple)

* Frecuencia:

  * diario
  * semanal
  * personalizada

* Hora configurable

* Destino:

  * local
  * disco externo
  * SSH remoto

Incluye restore interactivo.

---

# ⚙️ Arquitectura de red

```plaintext
Docker Networks:

proxy-net
 ├── nginx-proxy-manager
 ├── nextcloud
 ├── immich (opcional)
 ├── jellyfin (opcional)
 └── adguard (opcional)

internal-net
 ├── mariadb
 ├── redis
 └── backend-services

vpn-net
 └── wireguard-easy (UDP 51820)
```

---

# 🚀 Instalación (1 solo comando)

```bash
curl -fsSL https://get.docker.com | sudo bash && \
git clone https://github.com/wfhgdev/duckhomelab.git && \
cd duckhomelab && \
chmod +x duckhomelab.sh && \
sudo ./duckhomelab.sh
```

---

# 🌍 Dominio (DuckDNS)

DuckHomeLab usa DuckDNS como proveedor por defecto:

Ejemplo:

```plaintext
https://cloud.tudominio.duckdns.org
```

Incluye:

* Auto actualización de IP
* Integración con NPM
* Certificados SSL automáticos

---

# 🤖 AUTODISCOVERY (Docker → Nginx Proxy Manager)

Servicios publicados automáticamente mediante labels:

```yaml
labels:
  - proxy.enable=true
  - proxy.host=cloud
  - proxy.port=8080
```

Resultado:

```plaintext
cloud.tudominio.duckdns.org → container:8080
```

---

# 🔐 SEGURIDAD

Incluye:

* Fail2Ban (SSH + NPM protection)
* UFW firewall (opcional)
* Docker network isolation
* Passwords aleatorios seguros:

  * MariaDB
  * Redis
  * WireGuard peers

---

# 📊 REPORTE FINAL (POST-INSTALL)

Al finalizar:

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
[ ] Fail2Ban
[ ] Backups (optional)
```

---

# 🧠 PRINCIPIOS DEL PROYECTO

* Automatización primero
* Seguridad por defecto
* Zero-config post install
* NPM como único reverse proxy

---

# 🏁 ESTADO

✔ V4 definida
✔ Repo conectado
✔ Instalador unificado
✔ Stacks opcionales definidos
✔ Backups desacoplados

---