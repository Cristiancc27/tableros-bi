# Despliegue del tablero CVP en el servidor de desarrollo (manual, sin sudo)

Servidor: `Interkont-Desarrollo` (Ubuntu 16.04, Python 3.5.2, sin Docker). Todo vive en la carpeta del usuario y en `/srv/tomcat/webapps/cobracvp-webcomponents/tablero-cvp/` (ruta que ya sirve el Tomcat/nginx para los Web Components). No se reinicia ningún servicio ni se instala nada en el sistema.

URL final del iframe: `/cobracvp-webcomponents/tablero-cvp/Tablero_CVP.html`

## 0. Revisión previa (solo lectura)
    ssh Interkont-Desarrollo 'df -h / | tail -1; ls -ld /srv/tomcat/webapps/cobracvp-webcomponents; curl -s -o /dev/null -w "wc http %{http_code}\n" http://localhost/cobracvp-webcomponents/'

## 1. Copiar los archivos (desde la Mac, en la carpeta de este repo)
    ssh Interkont-Desarrollo 'mkdir -p ~/tableros-bi/app ~/tableros-bi/lib'
    scp actualizar_datos.py cvp_config.py Interkont-Desarrollo:tableros-bi/app/
    scp /tmp/psycopg2_cp35.whl Interkont-Desarrollo:tableros-bi/

## 2. Instalar psycopg2 en una carpeta propia (sin pip, sin venv)
    ssh Interkont-Desarrollo 'cd ~/tableros-bi && python3 -m zipfile -e psycopg2_cp35.whl lib && PYTHONPATH=lib python3 -c "import psycopg2; print(psycopg2.__version__)"'

## 3. Usuario de solo lectura en la base de desarrollo (una vez)
Conéctate como `cobra` y pon una clave nueva (no la compartas en chats):
    ssh -t Interkont-Desarrollo 'psql -h localhost -p 5433 -U cobra -d viviendacvp -W'
    CREATE ROLE tablero_ro LOGIN PASSWORD '<clave-nueva>' NOSUPERUSER NOCREATEDB NOCREATEROLE;
    GRANT CONNECT ON DATABASE viviendacvp TO tablero_ro;
    GRANT USAGE ON SCHEMA public, autenticacion TO tablero_ro;
    GRANT SELECT ON public.obra, public.tipoestadobra, public.relacioncontratoobra, public.logestadoobra, public.contrato, public.contratocontratista, public.desembolso, autenticacion.contratista, autenticacion.tercero TO tablero_ro;
    ALTER ROLE tablero_ro SET default_transaction_read_only = on;

## 4. Configuración (la clave solo vive en este archivo, permisos 600)
    ssh Interkont-Desarrollo
    umask 077
    cat > ~/tableros-bi/cvp.env <<'EOF'
    CVP_AMBIENTE=desarrollo
    CVP_DB_HOST=localhost
    CVP_DB_PORT=5433
    CVP_DB_NAME=viviendacvp
    CVP_DB_USER=tablero_ro
    CVP_DB_PASSWORD=<la-clave-nueva>
    CVP_CONTRATOS=2844,2846,2847,2848
    CVP_LOTES_NOMBRES=2844=Bosa Lote 1;2846=Bosa Lote 2;2847=Suba Lote 1;2848=Suba Lote 2
    CVP_META_LOTE=220
    CVP_FECHA_INICIO=2026-06-01
    CVP_FECHA_FIN=2026-12-31
    EOF

## 5. Primera corrida en una carpeta temporal (no toca webapps)
    mkdir -p /tmp/tablero-prueba
    cd ~/tableros-bi/app && CVP_WEB_DIR=/tmp/tablero-prueba PYTHONPATH=../lib python3 actualizar_datos.py --env-file ../cvp.env
Debe imprimir 1038 hogares, 4 lotes y `Listo: /tmp/tablero-prueba/data.js`.

## 6. Publicar
    DEST=/srv/tomcat/webapps/cobracvp-webcomponents/tablero-cvp
    mkdir -p $DEST
    cp /tmp/tablero-prueba/data.js $DEST/data.js
    printf 'window.CVP_CONFIG = {allowSample: false};\n' > $DEST/config.js
(El HTML se copia desde la Mac:)
    scp Tablero_CVP.html Interkont-Desarrollo:/srv/tomcat/webapps/cobracvp-webcomponents/tablero-cvp/
Comprobar: `http://13.59.62.87/cobracvp-webcomponents/tablero-cvp/Tablero_CVP.html`

## 7. Actualizar los datos (cuando haga falta)
    cd ~/tableros-bi/app && CVP_WEB_DIR=/srv/tomcat/webapps/cobracvp-webcomponents/tablero-cvp PYTHONPATH=../lib python3 actualizar_datos.py --env-file ../cvp.env
El script reemplaza `data.js` de forma atómica y no lo toca si la consulta de hogares viene vacía.

## Rollback (todo es reversible)
    ssh Interkont-Desarrollo 'rm -rf ~/tableros-bi /tmp/tablero-prueba /srv/tomcat/webapps/cobracvp-webcomponents/tablero-cvp'
    -- en la base: DROP OWNED BY tablero_ro; DROP ROLE tablero_ro;
