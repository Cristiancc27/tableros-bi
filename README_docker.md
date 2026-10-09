# Tablero CVProgreso · Prueba en local con Docker

Este paquete levanta el tablero completo en su máquina: un contenedor **actualizador** (Python) que lee la base y genera `data.js`, y un contenedor **web** (nginx) que sirve `Tablero_CVP.html` junto con ese `data.js`. Opcionalmente trae una **base de mentira** para probar sin tocar la base real.

```
bd-prueba (opcional)  o  su BD ──(solo lectura)──> actualizador ──> volumen "web" (data.js) ──> web (nginx) ──> http://localhost:8080
                                                                   Tablero_CVP.html (de esta carpeta) ──────^
```

## Requisitos
- Docker Desktop (Windows o Mac) o Docker Engine (Linux), con **Docker Compose v2** (el comando es `docker compose`, sin guion).
- Puerto **8080** libre en su máquina.
- Conexión a internet la primera vez (descarga las imágenes `python:3.12-slim`, `nginx:alpine` y `postgres:16-alpine`, y el paquete `psycopg2-binary`).

Todos los comandos se ejecutan dentro de esta carpeta.

## Pasos

### 1) Crear su archivo `.env`
```
cp .env.docker.example .env          # Linux / Mac
copy .env.docker.example .env        # Windows (cmd)
```
Ya viene listo para el modo A (base de prueba). No hay que editar nada. El `.env` real nunca se sube a un repositorio (ya está excluido en `.gitignore`).

### 2) Levantar todo con datos de mentira
```
docker compose --profile bd-prueba up --build
```
La primera vez tarda unos minutos (construye la imagen). Espere a ver en el log de `actualizador` algo como:
```
hogares        20 filas
historial     125 filas
lotes           4 filas
pagos           7 filas
Listo: /web/data.js
```
La base de prueba tiene 20 hogares inventados repartidos en los lotes 2844, 2846, 2847 y 2848 (5 por lote), con historial de estados y algunos pagos. Ningún dato es real.

### 3) Abrir el tablero
http://localhost:8080

Si abre la página antes de que termine la primera actualización, el propio tablero muestra datos de ejemplo con un aviso naranja; recargue cuando el log diga "Listo". Con la base de prueba, arriba debe decir "Última actualización" con la fecha de hoy y la portada debe mostrar cifras pequeñas (20 hogares en total, no los 880 de la meta).

### 4) Apuntar a una base real
1. Pare todo: `docker compose --profile bd-prueba down`.
2. Edite `.env`: comente las 5 líneas del modo A y active **una sola** de estas opciones:
   - **Modo B**, base PostgreSQL en su misma máquina: `CVP_DB_HOST=host.docker.internal` (más puerto, base, usuario y clave). Esa base debe aceptar conexiones que vengan de Docker (`listen_addresses` y `pg_hba.conf`); si solo escucha en `localhost`, no se podrá conectar.
   - **Modo C**, base remota con VPN: `CVP_DB_URL=postgresql://usuario:clave@host:5432/viviendacvp?sslmode=require`. Conecte la VPN en su máquina antes de levantar. Con Docker Desktop suele funcionar; si el contenedor no resuelve el nombre de la base, use la IP.
3. Use siempre un usuario de **solo lectura** (ver la sección de servidor más abajo).
4. Levante sin el perfil de prueba: `docker compose up --build`.

En `.env` de Docker no se usan comillas ni comentarios en la misma línea del valor: `CLAVE=valor` y nada más. Los comentarios van en líneas aparte.

### 5) Forzar una actualización
El actualizador corre al arrancar y luego cada `CVP_ACTUALIZAR_CADA_HORAS` horas (24 por defecto). Para actualizar ahora:
```
docker compose restart actualizador
```
o una corrida única que no deja nada corriendo:
```
docker compose run --rm -e CVP_ACTUALIZAR_CADA_HORAS=0 actualizador
```
Con `CVP_ACTUALIZAR_CADA_HORAS=0` (por ejemplo en `.env`) el contenedor hace una corrida y termina con el código de esa corrida (0 = bien).

Si una corrida falla (base caída, clave mala, VPN desconectada), el contenedor **no se detiene** y el `data.js` anterior se conserva intacto; el error queda en el log y el siguiente intento es en el próximo ciclo. Para reintentar de inmediato, use `docker compose restart actualizador`.

### 6) Ver los logs
```
docker compose logs -f actualizador
docker compose logs -f web
docker compose ps
```
El log del actualizador nunca imprime la contraseña. `docker compose ps` debe mostrar `web` como `healthy`.

### 7) Bajar todo y borrar datos
```
docker compose --profile bd-prueba down        # para y elimina los contenedores
docker compose --profile bd-prueba down -v     # además borra el volumen con data.js y la base de prueba
```
Si cambia `prueba/seed.sql`, use `down -v` para que la base de prueba se vuelva a crear (el seed solo corre cuando la base se crea desde cero).

## Qué contiene el paquete

| Archivo | Para qué sirve |
|---|---|
| `docker-compose.yml` | Define `actualizador`, `web` y la `bd-prueba` opcional. |
| `Dockerfile`, `requirements.txt`, `entrypoint.sh` | Imagen del actualizador (Python 3.12, usuario no root, repite la corrida cada N horas). |
| `nginx/default.conf` | Configuración del servidor web (solo GET/HEAD, sin listado de carpetas, `Cache-Control: no-store`). |
| `prueba/seed.sql` | Base de mentira y rol `tablero_ro` de solo lectura. |
| `.env.docker.example` | Plantilla del `.env` para Docker (modos A, B y C). |
| `Tablero_CVP.html`, `actualizar_datos.py`, `cvp_config.py`, `consultas_tablero.sql`, `.env.example`, `README_conexion.md` | Archivos originales del tablero, sin cambios (salvo la sección "Docker" añadida al final de `README_conexion.md`). |

## Detalles que conviene saber
- **Solo PostgreSQL.** La imagen incluye `psycopg2-binary`, pero **no** `pyodbc`, porque este necesita drivers ODBC del sistema que la imagen no trae. Por eso `CVP_DB_DSN` (el DSN ODBC de Power BI) no funciona dentro del contenedor: use `CVP_DB_HOST/USER/PASSWORD` o `CVP_DB_URL`. Soportar ODBC implicaría añadir `unixodbc`, el driver y `pyodbc` a la imagen; no está hecho.
- **Python 3.12.** La imagen usa Python 3.12 porque `psycopg2-binary` 2.9.13 (la versión fijada en `requirements.txt`) pide Python 3.10 o superior (dato de PyPI). Versiones anteriores de la serie 2.9 aceptan Pythons más viejos (2.9.10 pide 3.8 o superior, 2.9.11 y 2.9.12 piden 3.9 o superior). Los scripts del tablero están escritos para Python 3.6 o superior, pero en este paquete solo se probaron con 3.12.
- **El `.html` no va dentro de ninguna imagen**: se monta desde esta carpeta, así que si lo reemplaza basta con recargar el navegador. `data.js` vive en el volumen `web`.
- **El HTML pide `config.js`**; nginx responde un archivo vacío para ese nombre. Si algún día se usa una API en vez de `data.js` (ver `README_conexion.md`), habría que ajustar `nginx/default.conf`.
- **El puerto solo se publica en `127.0.0.1:8080`**: nadie más en su red puede abrirlo.
- **Credenciales de la base de prueba**: `tablero_ro` / `clave_de_prueba_no_real` (y `prueba_admin` / `admin_de_prueba_no_real` como administrador de esa base). Son falsas y solo existen dentro del contenedor `bd-prueba`, que no publica ningún puerto.

## Qué cambia para llevarlo a un servidor
Este compose es **solo para pruebas en local**. Antes de un servidor hay que resolver:

1. **Autenticación (tema abierto).** El contenedor `web` de este compose **no tiene login**: cualquiera que llegue al puerto ve el tablero y descarga `data.js`, que contiene datos operativos (CHIP, barrio, estados). En un servidor debe ir **detrás de la autenticación del aplicativo**; cómo se hace eso lo deciden Victor y Dennis. Mientras no se defina, no lo exponga a la red.
2. **Usuario de BD de solo lectura.** `CVP_DB_USER` debe ser un rol que tenga **únicamente SELECT** sobre las tablas que leen las consultas (`obra`, `tipoestadobra`, `relacioncontratoobra`, `logestadoobra`, `contrato`, `contratocontratista`, `desembolso`, `autenticacion.contratista`, `autenticacion.tercero`). El script ya abre la sesión en modo solo lectura, pero eso no reemplaza los permisos del rol. `prueba/seed.sql` trae un ejemplo (`tablero_ro`) para tomar como referencia.
3. **Sin `bd-prueba` ni claves de prueba.** En servidor no se usa el perfil `bd-prueba`; la conexión real va por `CVP_DB_URL` o por campos, con la clave guardada donde indique el equipo de infraestructura (no en un `.env` dentro del repositorio).
4. **Puerto y TLS.** Hoy se publica `127.0.0.1:8080` por HTTP. Qué puerto, qué proxy y qué certificado se usan en servidor depende de cómo se integre con el aplicativo.
5. **Versiones de las imágenes.** `nginx:alpine`, `postgres:16-alpine` y `python:3.12-slim` son etiquetas que se mueven con el tiempo; para un servidor conviene fijarlas a una versión concreta.
6. **Programación.** El contenedor actualizador ya repite la corrida cada `CVP_ACTUALIZAR_CADA_HORAS`; si en servidor se prefiere un cron o un programador externo, se usa `CVP_ACTUALIZAR_CADA_HORAS=0` y se lanza la corrida única desde allí.
