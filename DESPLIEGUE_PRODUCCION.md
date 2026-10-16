# Despliegue del tablero CVP en producción (cvprogreso.cvp.gov.co)

> **Estado: preparado, NO ejecutado.** Nada de esto se corre hasta que QA apruebe y quien administra producción dé el visto bueno a los pasos con root (marcados 🔒). Se basa en una revisión de solo lectura hecha el 2026-10-09 y en el despliegue ya validado en desarrollo (`DESPLIEGUE_DESARROLLO.md`, `deploy/README.md`). Misma estructura que desarrollo: usuario de servicio `tableros`, `/srv/tableros-bi/cvp/`, cron del sistema y despliegue del HTML por GitHub Actions (un `yml` y un environment por ambiente, convención de Felix).

## Lo que se encontró en producción (solo lectura)
| Dato | Valor |
|---|---|
| Servidor | `ssh Interkont-Produccion` (`ip-172-31-19-222`, Ubuntu 20.04) |
| Python | 3.8.10 (el actualizador corre **sin** el parche de 3.5; falta `psycopg2`) |
| Disco | 17 GB libres (45 %) |
| Tomcat | `catalina.base=/srv/tomcat8`, puerto 8095, filtro `httpHeaderSecurity` declarado (`X-Frame-Options: DENY` por defecto) |
| `webapps` | `/srv/tomcat8/webapps` es `drwxr-xr-x tomcat8:tomcat8` → crear carpetas requiere root |
| nginx | `/etc/nginx/sites-enabled/sgi.conf`, `server_name cvprogreso.cvp.gov.co`; **un `location` explícito por contexto** (`/sgi`, `/cobracvp-webcomponents`, `/birt`, …) con `proxy_pass http://localhost:8095/<contexto>` |
| Base de datos | `viviendacvp` en `localhost:5432` (perfil `produccion` del pom). Último log: 2026-10-08 20:26; 1.151 obras |
| **Pagos** | `public.desembolso` tiene **0 filas** → *Ejecución Presupuestal* mostrará pagos en $0 y la advertencia amarilla del HTML |
| Usuario de despliegue | no existe `cicd-deploy` ni scripts `deploy-*` (Actions requeriría montarlo) |

## Plan vigente para producción: tablero protegido con la sesión del aplicativo (opción E, decidida con Daniel el 2026-10-10)
Desarrollo NO cambia (Tomcat atiende el puerto 80 directo, sin nginx delante: sigue con la carpeta de Tomcat y `web.xml`). Solo producción.

**Cómo funciona**
- El tablero (HTML, `config.js`, `data.js`) vive **fuera de Tomcat**, en `/srv/tableros-bi/cvp/web/`. Tomcat no lo publica por ningún puerto.
- nginx lo entrega desde disco bajo **`/sgi/tablero-cvp/`** y exige sesión para TODO (`auth_request` → servlet `/sgi/tablero-auth` del JSF, que responde 204 si hay sesión con el permiso `btnreportes`, 401 sin sesión, 403 sin permiso). La cookie de sesión del aplicativo lleva `Path=/sgi`, por eso el tablero va bajo `/sgi/` (con otra ruta el navegador no la enviaría).
- El menú del JSF apunta a la ruta relativa `../tablero-cvp/Tablero_CVP.html` (sirve igual en `/sgi` y `/cobracvp-wv`).
- Cambios del HTML → GitHub Actions (`deploy-prod.yml` de la rama `main`, manual) sin tocar el aplicativo. Datos → cron. El WAR solo se redespliega si cambia la regla de acceso o la ruta.

**Estado de partida (2026-10-12)**: usuario `tableros`, `/srv/tableros-bi/cvp`, `cicd-tableros`, script de despliegue, `cvp-prod` en GitHub: hechos. `data.js` borrado y cron desactivado (había quedado accesible por el 8095, que ya está cerrado). Daniel dejó un `location /tablero-cvp` (proxy al Tomcat) para el HTML, sin datos.

**Orden (nunca hay un momento con datos sin protección)**
1. **WAR con el servlet** (Jenkins `produccion`, rama `feature/tablero-cvp-iframe`). Sin cambiar aún `url.tablerocvp`: no hay efecto visible. Comprobar: `curl -s -o /dev/null -w "%{http_code}\n" https://cvprogreso.cvp.gov.co/sgi/tablero-auth` → **401** (no 302 ni 404).
2. **Copiar los scripts actualizados y mover la carpeta de datos** (re-ejecuta la migración con la carpeta nueva; reactiva el cron apuntando ahí y escribe `deploy.conf` sin URL de prueba):
       scp deploy/servidor/{migrar-a-srv.sh,deploy-tableros-bi,nginx-agregar-tablero.sh} Interkont-Produccion:/tmp/
       sudo install -o root -g root -m 0755 /tmp/deploy-tableros-bi /usr/local/sbin/deploy-tableros-bi
       sudo bash /tmp/migrar-a-srv.sh --origen /home/wvargas/tableros-bi --web-dir /srv/tableros-bi/cvp/web --sin-url-prueba
3. **Primera carga de datos y config** (quedan detrás de nginx; aún sin ruta pública):
       cd /srv/tableros-bi/cvp/app && sudo -u tableros env PYTHONIOENCODING=utf-8 CVP_WEB_DIR=/srv/tableros-bi/cvp/web PYTHONPATH=../lib python3 actualizar_datos.py --env-file ../cvp.env
       printf 'window.CVP_CONFIG = {allowSample: false};\n' | sudo -u tableros tee /srv/tableros-bi/cvp/web/config.js
   El HTML lo despliega el workflow de producción (`confirmar = DESPLEGAR-PRODUCCION`): ahora solo empaqueta `Tablero_CVP.html`.
4. **nginx** (el servlet ya responde, y la carpeta existe): `sudo bash /tmp/nginx-agregar-tablero.sh --retirar-ruta-vieja`. Respalda, valida con `nginx -t`, verifica 401 sin sesión y que `/sgi/` no cambie; revierte solo si algo falla (probado con nginx 1.18 sobre la copia del `sgi.conf` actual, incluidos intentos de esquivar la protección).
5. **Limpiar lo viejo**: `sudo rm -rf /srv/tomcat8/webapps/tablero-cvp`.
6. **Menú**: `url.tablerocvp` del perfil `produccion` = `../tablero-cvp/Tablero_CVP.html` y redesplegar el WAR.
7. **Verificar**: con sesión (Reportes → Tablero CVProgreso) carga con datos; sin sesión, `curl -s -o /dev/null -w "%{http_code}\n" https://cvprogreso.cvp.gov.co/sgi/tablero-cvp/data.js` → 401; `http://3.21.77.133:8095/...` sin respuesta.
Rollback de nginx: `sudo cp -a /etc/nginx/sites-available/sgi.conf.bak-<fecha> /etc/nginx/sites-available/sgi.conf && sudo nginx -t && sudo systemctl reload nginx`.

> Los pasos numerados 8 y 10 más abajo (ruta `/tablero-cvp` hacia Tomcat y `url.tablerocvp=/tablero-cvp/...`) son del diseño anterior y quedan **reemplazados** por este plan.

## Decisiones previas (pedir confirmación)
1. **Pagos en $0:** ¿se sale así (con la advertencia) o se espera al módulo financiero? (Cristian / Guillermo)
2. **Sin login:** `/tablero-cvp/data.js` es público para quien tenga la URL (CHIP, barrio, estados). ¿Se acepta en producción o se protege primero? (Daniel / Victor)
3. **Quién ejecuta los pasos 🔒:** administrador de producción con sudo.
4. **QA de CVP:** el perfil `preproduccion` del pom apunta al servidor de desarrollo; confirmar si QA es ese mismo servidor (entonces no hay `cvp-qa`).

## Aprobaciones necesarias
| Paso | Qué cambia | Requiere |
|---|---|---|
| 3 | Crear `tablero_ro` en la BD de producción (solo `SELECT`) | 🔒 admin de BD |
| 5 | Usuario `tableros`, `/srv/tableros-bi`, cron del sistema, `/etc/tableros-bi/deploy.conf` | 🔒 sudo |
| 6 | Usuario `cicd-tableros`, script `deploy-tableros-bi`, sudoers | 🔒 sudo |
| 8 | Nuevo `location` en nginx + recarga | 🔒 sudo, **toca el nginx compartido** |
| 9 | Environment `cvp-prod`, llave y variables en GitHub | admin del repo |
| 10 | Cambio del pom `produccion` + WAR | Jenkins producción |

## 0. Revisión previa (solo lectura)
    ssh Interkont-Produccion 'df -h / | tail -1; date; python3 --version; ls -ld /srv/tomcat8/webapps; grep -n "autoDeploy" /srv/tomcat8/conf/server.xml; systemctl is-active cron; ls -d /etc/cron.d'
Si `autoDeploy` no es `true`, Tomcat no desplegará la carpeta sola: avisar antes de seguir.

## 1. Archivos y psycopg2 (desde la Mac, en la carpeta de este repo)
El wheel de Python 3.8 (`psycopg2-binary 2.9.9`, sha256 `ead20f79…c972`):
    docker run --rm --platform linux/amd64 -v /tmp/wheel38:/w python:3.8 pip download -q --no-deps --only-binary=:all: --dest /w "psycopg2-binary==2.9.9"
Copiar a la carpeta del operador (`~/tableros-bi`; el actualizador es compatible con Python 3.5 y 3.8):
    ssh Interkont-Produccion 'mkdir -p ~/tableros-bi/app ~/tableros-bi/lib'
    scp /Users/wuilly/Work/Interkont/CVP/tableros-bi/actualizar_datos.py /Users/wuilly/Work/Interkont/CVP/tableros-bi/cvp_config.py Interkont-Produccion:tableros-bi/app/
    scp /tmp/psycopg2_cp38.whl Interkont-Produccion:tableros-bi/
    ssh Interkont-Produccion 'cd ~/tableros-bi && python3 -m zipfile -e psycopg2_cp38.whl lib && PYTHONPATH=lib python3 -c "import psycopg2; print(psycopg2.__version__)"'

## 2. (reservado)

## 3. 🔒 Usuario de solo lectura en la BD de producción (una vez, administrador de la BD)
    ssh -t Interkont-Produccion 'psql -h localhost -p 5432 -U cobra -d viviendacvp -W'
    CREATE ROLE tablero_ro LOGIN PASSWORD '<clave-nueva>' NOSUPERUSER NOCREATEDB NOCREATEROLE;
    GRANT CONNECT ON DATABASE viviendacvp TO tablero_ro;
    GRANT USAGE ON SCHEMA public, autenticacion TO tablero_ro;
    GRANT SELECT ON public.obra, public.tipoestadobra, public.relacioncontratoobra, public.logestadoobra, public.contrato, public.contratocontratista, public.desembolso, autenticacion.contratista, autenticacion.tercero TO tablero_ro;
    ALTER ROLE tablero_ro SET default_transaction_read_only = on;
Comprobar que no escribe: `psql -h localhost -p 5432 -U tablero_ro -d viviendacvp -W -c "create table public.zz(x int)"` debe fallar con *read-only transaction*. La clave no se comparte por chat ni se guarda en el repo.

## 4. Configuración con la clave (permisos 600, en `~/tableros-bi/cvp.env`)
    ssh Interkont-Produccion
    umask 077
    cat > ~/tableros-bi/cvp.env <<'EOF2'
    CVP_AMBIENTE=produccion
    CVP_DB_HOST=localhost
    CVP_DB_PORT=5432
    CVP_DB_NAME=viviendacvp
    CVP_DB_USER=tablero_ro
    CVP_DB_PASSWORD=<la-clave-nueva>
    CVP_CONTRATOS=2844,2846,2847,2848
    CVP_LOTES_NOMBRES=2844=Bosa Lote 1;2846=Bosa Lote 2;2847=Suba Lote 1;2848=Suba Lote 2
    CVP_META_LOTE=220
    CVP_FECHA_INICIO=2026-06-01
    CVP_FECHA_FIN=2026-12-31
    EOF2

## 5. 🔒 Carpeta general, usuario de servicio y cron (`migrar-a-srv.sh`)
Copiar el script y ejecutarlo con los valores de producción. Crea el usuario `tableros`, copia el actualizador a `/srv/tableros-bi/cvp`, **prueba el actualizador contra la base en una carpeta temporal** (si falla, no toca el cron), crea la carpeta del tablero, `/etc/cron.d/tableros-bi-cvp` (6:00) y `/etc/tableros-bi/deploy.conf` (rutas de producción para el script de despliegue):
    scp /Users/wuilly/Work/Interkont/CVP/tableros-bi/deploy/servidor/migrar-a-srv.sh /Users/wuilly/Work/Interkont/CVP/tableros-bi/deploy/servidor/deploy-tableros-bi /Users/wuilly/Work/Interkont/CVP/tableros-bi/deploy/servidor/sudoers-cicd-deploy-tableros-bi Interkont-Produccion:/tmp/
    ssh -t Interkont-Produccion 'sudo bash /tmp/migrar-a-srv.sh --origen /home/wvargas/tableros-bi --web-dir /srv/tomcat8/webapps/tablero-cvp --url-prueba http://localhost:8095/tablero-cvp/Tablero_CVP.html'
(Cambiar `/home/wvargas` por el usuario del operador.) Debe imprimir 1.151 hogares aprox. y `Listo`. Primera carga de `data.js` y `config.js` (el HTML y el `web.xml` los despliega el workflow, paso 9):
    ssh -t Interkont-Produccion 'cd /srv/tableros-bi/cvp/app && sudo -u tableros env PYTHONIOENCODING=utf-8 CVP_WEB_DIR=/srv/tomcat8/webapps/tablero-cvp PYTHONPATH=../lib python3 actualizar_datos.py --env-file ../cvp.env && printf "window.CVP_CONFIG = {allowSample: false};\n" | sudo -u tableros tee /srv/tomcat8/webapps/tablero-cvp/config.js'
Comparar los conteos con una consulta SQL independiente antes de publicar.

## 6. 🔒 Usuario de despliegue propio y script (producción no tiene `cicd-deploy`)
    ssh -t Interkont-Produccion 'sudo useradd -m -s /bin/bash cicd-tableros && sudo passwd -l cicd-tableros'
    ssh -t Interkont-Produccion 'sudo install -o root -g root -m 0755 /tmp/deploy-tableros-bi /usr/local/sbin/deploy-tableros-bi'
    ssh Interkont-Produccion 'sed "s/^cicd-deploy /cicd-tableros /" /tmp/sudoers-cicd-deploy-tableros-bi > /tmp/sudoers-cicd-tableros-bi'
    ssh -t Interkont-Produccion 'sudo visudo -cf /tmp/sudoers-cicd-tableros-bi && sudo install -o root -g root -m 0440 /tmp/sudoers-cicd-tableros-bi /etc/sudoers.d/cicd-tableros-bi && sudo visudo -c'
Llave solo para este repo (en la Mac; la privada nunca se guarda fuera de GitHub):
    ssh-keygen -t ed25519 -N "" -C "gh-actions tableros-bi cvp-prod" -f /tmp/cvp_prod_key
    ssh -t Interkont-Produccion 'sudo install -d -m 700 -o cicd-tableros -g cicd-tableros /home/cicd-tableros/.ssh'
    ssh Interkont-Produccion 'cat > /tmp/cvp_prod_key.pub' < /tmp/cvp_prod_key.pub
    ssh -t Interkont-Produccion 'sudo install -m 600 -o cicd-tableros -g cicd-tableros /tmp/cvp_prod_key.pub /home/cicd-tableros/.ssh/authorized_keys'

## 7. (reservado)

## 8. (reemplazado por el plan E de arriba) nginx: ruta `/tablero-cvp`
Tomcat sirve el contexto en `localhost:8095/tablero-cvp`, pero nginx solo enruta los contextos que tienen `location`. El script **duplica el bloque `location /cobracvp-webcomponents`** de `sgi.conf` como `/tablero-cvp` (con compresión gzip, porque `data.js` pesa ~1,5 MB), con estas garantías (probadas con nginx 1.18 en Ubuntu 20.04 sobre una copia del archivo real): `nginx -t` antes y después, respaldo con fecha, comprobación de que `/tablero-cvp/data.js` responda 200 y de que `/sgi/` y `/cobracvp-webcomponents/` respondan igual que antes; si algo falla restaura el original. Es idempotente.
    scp /Users/wuilly/Work/Interkont/CVP/tableros-bi/deploy/servidor/nginx-agregar-tablero.sh Interkont-Produccion:/tmp/
    ssh -t Interkont-Produccion 'sudo bash /tmp/nginx-agregar-tablero.sh'
**Este paso hace público el tablero** (`https://cvprogreso.cvp.gov.co/tablero-cvp/…`); `data.js` no tiene login. Revertir: `sudo cp -a /etc/nginx/sites-available/sgi.conf.bak-<fecha> /etc/nginx/sites-available/sgi.conf && sudo nginx -t && sudo systemctl reload nginx`.

## 9. GitHub: environment `cvp-prod` y primer despliegue (admin del repo)
Convención del equipo: **workflows unificados en `main`** (`deploy-develop.yml` y `deploy-prod.yml`, uno para todos los clientes) y un environment por cliente y ambiente. Producción de CVP usa el `deploy-prod.yml` de `main` (solo manual, cliente `cvp`) y el environment `cvp-prod`.
Environment limitado a la rama `main`, donde viven los workflows. **El plan Team de la organización NO admite revisores obligatorios en environments de repos privados** (GitHub responde 422): la salvaguarda es la confirmación escrita del workflow (`confirmar = DESPLEGAR-PRODUCCION`) y la protección de las ramas `main` y `cvp`.
    gh api -X PUT repos/gitinterkont/tableros-bi/environments/cvp-prod -F 'deployment_branch_policy[protected_branches]=false' -F 'deployment_branch_policy[custom_branch_policies]=true'
    gh api -X POST repos/gitinterkont/tableros-bi/environments/cvp-prod/deployment-branch-policies -f name=cvp
Variables y secreto (la llave privada se borra de la Mac al terminar):
    gh variable set DEPLOY_HOST --env cvp-prod --repo gitinterkont/tableros-bi --body 3.21.77.133
    gh variable set DEPLOY_USER --env cvp-prod --repo gitinterkont/tableros-bi --body cicd-tableros
    ssh-keyscan -t ed25519 3.21.77.133 2>/dev/null | gh variable set DEPLOY_KNOWN_HOSTS --env cvp-prod --repo gitinterkont/tableros-bi
    ssh-keygen -lf /tmp/cvp_prod_key.pub | awk '{print $2}' | gh variable set DEPLOY_KEY_FINGERPRINT --env cvp-prod --repo gitinterkont/tableros-bi
    gh secret set DEPLOY_SSH_PRIVATE_KEY --env cvp-prod --repo gitinterkont/tableros-bi < /tmp/cvp_prod_key
    rm -P /tmp/cvp_prod_key /tmp/cvp_prod_key.pub
Primer despliegue: Actions → *Desplegar tablero en producción* → *Run workflow* (rama **`main`**, cliente `cvp`; escribir `DESPLEGAR-PRODUCCION` en la confirmación). Si la conexión no responde, revisar el *security group* de AWS de producción: debe permitir SSH desde la IP del runner (`ip-172-31-38-67`).

## 10. (reemplazado por el plan E de arriba) Menú del JSF (cobra-housing)
En `pom.xml`, perfil `produccion`: `<url.tablerocvp>/tablero-cvp/Tablero_CVP.html</url.tablerocvp>` (hoy `${url.bicvprogreso}` = Power BI). Desplegar el WAR de producción con Jenkins **después** de los pasos anteriores. Preproducción queda para el final y necesita su propia carpeta y actualizador. Reversión del menú: volver `url.tablerocvp` a `${url.bicvprogreso}` y redesplegar.

## Verificación final
1. `https://cvprogreso.cvp.gov.co/tablero-cvp/Tablero_CVP.html` carga con datos y `X-Frame-Options: SAMEORIGIN` (`curl -sI`).
2. En el JSF: Reportes → Tablero CVProgreso muestra el tablero en el iframe.
3. Las 5 pestañas, los CSV y el PDF.
4. Las cifras de la Portada coinciden con un conteo SQL directo a la base.
5. El día siguiente, `tail /srv/tableros-bi/cvp/log/actualizador.log` termina con `Actualizacion terminada` y `data.js` tiene la hora de la corrida.

## Rollback completo
    ssh -t Interkont-Produccion 'sudo rm -rf /srv/tomcat8/webapps/tablero-cvp /srv/tableros-bi /etc/cron.d/tableros-bi-cvp /etc/tableros-bi /usr/local/sbin/deploy-tableros-bi /etc/sudoers.d/cicd-tableros-bi; sudo userdel -r cicd-tableros; sudo userdel tableros; rm -rf ~/tableros-bi'
Más: restaurar el `.bak` de nginx y recargar; en la BD `DROP OWNED BY tablero_ro; DROP ROLE tablero_ro;`; en el pom, volver a `${url.bicvprogreso}`; en GitHub borrar el environment `cvp-prod`.
