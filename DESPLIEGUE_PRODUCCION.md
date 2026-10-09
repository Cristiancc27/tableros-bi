# Despliegue del tablero CVP en producción (cvprogreso.cvp.gov.co)

> **Estado: preparado, NO ejecutado.** Nada de esto se corre hasta que QA apruebe y quien administra producción dé el visto bueno a los pasos con root (marcados 🔒). Se basa en una revisión de solo lectura hecha el 2026-10-09 y en el despliegue ya validado en desarrollo (`DESPLIEGUE_DESARROLLO.md`).

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

## Decisiones previas (pedir confirmación)
1. **Pagos en $0:** ¿se sale así (con la advertencia) o se espera al módulo financiero? (Cristian / Guillermo)
2. **Sin login:** `/tablero-cvp/data.js` es público para quien tenga la URL (CHIP, barrio, estados). ¿Se acepta en producción o se protege primero? (Daniel / Victor)
3. **Quién ejecuta los pasos 🔒:** administrador de producción con sudo.

## Aprobaciones necesarias
| Paso | Qué cambia | Requiere |
|---|---|---|
| 1 | Crear carpeta en `webapps` | 🔒 sudo |
| 3 | Crear `tablero_ro` en la BD de producción (solo `SELECT`) | 🔒 admin de BD |
| 7 | Nuevo `location` en nginx + recarga | 🔒 sudo, **toca el nginx compartido** |
| 9 | Cambio del pom `produccion` + WAR | Jenkins producción |

## 0. Revisión previa (solo lectura)
    ssh Interkont-Produccion 'df -h / | tail -1; date; python3 --version; ls -ld /srv/tomcat8/webapps; grep -n "autoDeploy" /srv/tomcat8/conf/server.xml; systemctl is-active cron; sudo -n true 2>&1 | head -1'

## 1. 🔒 Carpeta del tablero
    ssh -t Interkont-Produccion 'sudo mkdir /srv/tomcat8/webapps/tablero-cvp && sudo chown wvargas:wvargas /srv/tomcat8/webapps/tablero-cvp && sudo mkdir /srv/tomcat8/webapps/tablero-cvp/WEB-INF && sudo chown wvargas:wvargas /srv/tomcat8/webapps/tablero-cvp/WEB-INF'
Si `autoDeploy` no es `true` en `server.xml`, Tomcat no desplegará la carpeta sola: avisar antes de seguir (habría que reiniciar o usar el manager).

## 2. Archivos y psycopg2 (desde la Mac, en la carpeta de este repo)
El wheel para Python 3.8 (`psycopg2-binary 2.9.9`) se descarga así (sha256 `ead20f79…c972`):
    docker run --rm --platform linux/amd64 -v /tmp/wheel38:/w python:3.8 pip download -q --no-deps --only-binary=:all: --dest /w "psycopg2-binary==2.9.9"
Copiar (el actualizador **no** necesita el parche de Python 3.5, pero es compatible):
    ssh Interkont-Produccion 'mkdir -p ~/tableros-bi/app ~/tableros-bi/lib'
    scp actualizar_datos.py cvp_config.py Interkont-Produccion:tableros-bi/app/
    scp /tmp/psycopg2_cp38.whl Interkont-Produccion:tableros-bi/
    ssh Interkont-Produccion 'cd ~/tableros-bi && python3 -m zipfile -e psycopg2_cp38.whl lib && PYTHONPATH=lib python3 -c "import psycopg2; print(psycopg2.__version__)"'

## 3. 🔒 Usuario de solo lectura (una vez, como administrador de la BD)
    ssh -t Interkont-Produccion 'psql -h localhost -p 5432 -U cobra -d viviendacvp -W'
    CREATE ROLE tablero_ro LOGIN PASSWORD '<clave-nueva>' NOSUPERUSER NOCREATEDB NOCREATEROLE;
    GRANT CONNECT ON DATABASE viviendacvp TO tablero_ro;
    GRANT USAGE ON SCHEMA public, autenticacion TO tablero_ro;
    GRANT SELECT ON public.obra, public.tipoestadobra, public.relacioncontratoobra, public.logestadoobra, public.contrato, public.contratocontratista, public.desembolso, autenticacion.contratista, autenticacion.tercero TO tablero_ro;
    ALTER ROLE tablero_ro SET default_transaction_read_only = on;
Comprobar que no escribe: `psql -h localhost -p 5432 -U tablero_ro -d viviendacvp -W -c "create table public.zz(x int)"` debe fallar con *read-only transaction*.
La clave no se comparte por chat ni se guarda en el repo.

## 4. Configuración (la clave solo vive en este archivo, permisos 600)
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

## 5. Primera corrida en carpeta temporal (no toca webapps)
    mkdir -p /tmp/tablero-prueba && cd ~/tableros-bi/app && PYTHONIOENCODING=utf-8 CVP_WEB_DIR=/tmp/tablero-prueba PYTHONPATH=../lib python3 actualizar_datos.py --env-file ../cvp.env
Debe imprimir ~1.151 hogares… (los lotes suman los hogares de los contratos configurados) y `Listo: /tmp/tablero-prueba/data.js`. Comparar con un conteo SQL independiente antes de publicar.

## 6. Publicar archivos
    DEST=/srv/tomcat8/webapps/tablero-cvp
    cp /tmp/tablero-prueba/data.js $DEST/data.js && printf 'window.CVP_CONFIG = {allowSample: false};\n' > $DEST/config.js
Desde la Mac:
    scp Tablero_CVP.html Interkont-Produccion:/srv/tomcat8/webapps/tablero-cvp/
    scp deploy/WEB-INF/web.xml Interkont-Produccion:/srv/tomcat8/webapps/tablero-cvp/WEB-INF/
El `web.xml` cambia `X-Frame-Options` a `SAMEORIGIN` solo para este contexto (necesario para el iframe del JSF).

## 7. 🔒 nginx: ruta `/tablero-cvp`
Tomcat sirve el contexto en `localhost:8095/tablero-cvp`, pero nginx solo enruta los contextos que tienen `location`. Hay que **duplicar el bloque `location /cobracvp-webcomponents`** de `/etc/nginx/sites-enabled/sgi.conf` cambiando el nombre:
    ssh -t Interkont-Produccion 'sudo cp /etc/nginx/sites-available/sgi.conf /etc/nginx/sites-available/sgi.conf.bak-$(date +%Y%m%d-%H%M)'
    # editar sgi.conf: copiar el bloque de /cobracvp-webcomponents y dejarlo como /tablero-cvp (proxy_pass http://localhost:8095/tablero-cvp)
    ssh -t Interkont-Produccion 'sudo nginx -t'
    ssh -t Interkont-Produccion 'sudo systemctl reload nginx'
No recargar si `nginx -t` falla. Revertir: restaurar el `.bak` y `systemctl reload nginx`.
Comprobar: `curl -sI https://cvprogreso.cvp.gov.co/tablero-cvp/data.js | grep -i -E "^HTTP|frame"` → `200` y `X-Frame-Options: SAMEORIGIN`.

## 8. Cron diario (hora del servidor; confirmar con `date`)
    ssh Interkont-Produccion '(crontab -l 2>/dev/null; echo "0 6 * * * cd /home/wvargas/tableros-bi/app && PYTHONIOENCODING=utf-8 CVP_WEB_DIR=/srv/tomcat8/webapps/tablero-cvp PYTHONPATH=../lib python3 actualizar_datos.py --env-file ../cvp.env >> /home/wvargas/tableros-bi/actualizador.log 2>&1") | crontab -'
Revisar antes con `crontab -l` para no pisar uno existente. En producción lo recomendable es un usuario de servicio en vez de `wvargas`.

## 9. Menú del JSF (cobra-housing)
En `pom.xml`, perfil `produccion`: `<url.tablerocvp>/tablero-cvp/Tablero_CVP.html</url.tablerocvp>` (hoy `${url.bicvprogreso}` = Power BI). Desplegar el WAR de producción con Jenkins **después** de los pasos 1–7. Preproducción queda para el final y necesita su propia carpeta y actualizador.
Reversión del menú: volver `url.tablerocvp` a `${url.bicvprogreso}` y redesplegar.

## Verificación final
1. `https://cvprogreso.cvp.gov.co/tablero-cvp/Tablero_CVP.html` carga con datos.
2. En el JSF: Reportes → Tablero CVProgreso muestra el tablero en el iframe.
3. Las 5 pestañas, los CSV y el PDF.
4. Las cifras de la Portada coinciden con un conteo SQL directo a la base.
5. El día siguiente, `tail ~/tableros-bi/actualizador.log` termina con `Actualizacion terminada` y `data.js` tiene la hora de la corrida.

## Rollback completo
    ssh -t Interkont-Produccion 'rm -rf ~/tableros-bi /tmp/tablero-prueba; sudo rm -rf /srv/tomcat8/webapps/tablero-cvp; crontab -r'
Más: restaurar el `.bak` de nginx y recargar; en la BD `DROP OWNED BY tablero_ro; DROP ROLE tablero_ro;`; en el pom, volver a `${url.bicvprogreso}`.
(`crontab -r` borra TODO el cron del usuario: solo si no había otras tareas.)
