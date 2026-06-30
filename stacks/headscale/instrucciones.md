Mantener Headscale solo por el puerto `8080` simplifica la infraestructura un 200 %, blinda el servidor y te deja toda la gestión centralizada por SSH mediante `docker exec`.

Headscale necesita que creemos sus carpetas y su archivo de configuración **antes** de levantar el contenedor, de lo contrario fallará de inmediato.

Aquí tienes el despliegue completo paso a paso estructurado perfectamente para **Dockge** y **Nginx Proxy Manager**.

---

## 🛠️ Paso 1: Preparar el entorno en tu servidor

Entra por terminal a tu servidor y posiciónate en la carpeta donde Dockge guarda tus stacks (usualmente `/opt/stacks` o `~/docker`). Vamos a crear el directorio del proyecto y el esqueleto necesario:

```bash
# 1. Crear la carpeta del stack y sus subcarpetas locales
mkdir -p ~/docker/headscale/config
mkdir -p ~/docker/headscale/data

# 2. Entrar a la carpeta del proyecto
cd ~/docker/headscale

```

---

## 📄 Paso 2: Crear el archivo de configuración (`config.yaml`)

Headscale requiere este archivo obligatoriamente. Vamos a crear una versión limpia, optimizada para SQLite y con tu dominio listo.

Ejecuta el editor:

```bash
nano config/config.yaml

```

Pega el siguiente contenido exacto dentro del archivo:

```yaml
# URL pública de tu servidor de Headscale (gestionada por NPM con SSL)
server_url: https://headscale.tu-dominio.duckdns.org

# Dirección interna donde escucha Headscale dentro de la red de Docker
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 127.0.0.1:9090

# gRPC se queda en local (seguro, no expuesto al exterior)
grpc_listen_addr: 127.0.0.1:50443
grpc_allow_insecure: true

# Rutas internas del contenedor para las llaves de cifrado
private_key_path: /var/lib/headscale/private.key
noise:
  private_key_path: /var/lib/headscale/noise_private.key

# Configuración de la Base de Datos SQLite
database:
  type: sqlite
  sqlite:
    path: /var/lib/headscale/db.sqlite
    write_ahead_log: true

# Rangos de IPs privadas que asignará tu VPN Mesh a tus dispositivos
ip_prefixes:
  - 100.64.0.0/10

# Servidores de mapas de retransmisión oficiales de Tailscale (para saltar CGNAT)
derp:
  urls:
    - https://controlplane.tailscale.com/derpmap/default

# Desactivar actualizaciones aleatorias automáticas en el arranque
check_updates: false

```

*(Guarda los cambios con `Ctrl+O` y sal con `Ctrl+X`)*

---

## 🐳 Paso 3: El archivo `docker-compose.yml` para Dockge

Ahora creamos el archivo del stack que gestionarás desde la interfaz de Dockge. Como ves, **no lleva la línea `version**` para cumplir con los estándares actuales de las últimas versiones de Docker.

Crea el archivo:

```bash
nano docker-compose.yml

```

Pega este bloque de código:

```yaml
services:
  headscale:
    image: ghcr.io/juanfont/headscale:stable
    container_name: headscale
    restart: always
    command: headscale serve
    volumes:
      - ./config:/etc/headscale
      - ./data:/var/lib/headscale
    networks:
      - proxy-network

networks:
  proxy-network:
    external: true

```

*(Guarda los cambios con `Ctrl+O` y sal con `Ctrl+X`)*

Ya puedes levantar el contenedor ejecutando `sudo docker compose up -d` en tu terminal o dándole al botón **"Deploy"** desde la interfaz web de Dockge.

---

## 🌐 Paso 4: Configuración en Nginx Proxy Manager (NPM)

Ve a la interfaz web de tu NPM y añade un nuevo **Proxy Host** con los siguientes datos:

* **Domain Names:** `headscale.tu-dominio.duckdns.org`
* **Scheme:** `http`
* **Forward Hostname / IP:** `headscale` *(el nombre del servicio en el YAML)*
* **Forward Port:** `8080`
* **Opciones recomendadas en "Details":**
* **Block Common Exploits:** Activado (ON)
* **Websockets Support:** Desactivado (Headscale no lo requiere obligatoriamente para tráfico estándar, pero puedes activarlo si experimentas microcortes en clientes muy modernos).


* **SSL:** Genera tu certificado Let's Encrypt, activa **Force SSL** y **HSTS**.

---

## 🚀 Cheat Sheet: ¿Cómo empezar a usar tu nuevo Headscale?

Una vez que el contenedor esté corriendo y el proxy configurado, todo el control lo harás ejecutando comandos directamente dentro del contenedor mediante SSH. Aquí tienes los comandos esenciales para arrancar:

### 1. Crear tu primer usuario (antiguamente llamados namespaces)

```bash
sudo docker exec -it headscale headscale users create miusuario

```

### 2. Conectar tu primer dispositivo (Ejemplo: Linux/Windows/Móvil)

Cuando instales el cliente oficial de Tailscale en cualquier dispositivo, debes indicarle que use tu servidor propio en lugar de la nube pública.

* **En Linux se conecta ejecutando:**
```bash
tailscale up --login-server https://headscale.tu-dominio.duckdns.org

```


* **En Windows/Mac/Móvil:** Al abrir la app, mantienes pulsado el logo de Tailscale o entras a los ajustes avanzados para cambiar el "Login Server" por tu URL: `https://headscale.tu-dominio.duckdns.org`.

### 3. Registrar la máquina en el servidor

Al intentar conectarse, el dispositivo te mostrará en pantalla un comando con una clave larga (un token). Copia esa clave y regístrala en tu servidor corriendo:

```bash
sudo docker exec -it headscale headscale nodes register --user miusuario --key TU_CLAVE_DE_PANTALLA

```

¡Listo! Ya tienes una red mesh 100 % tuya, ultra segura y perfectamente integrada en tu ecosistema Docker.