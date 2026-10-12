#!/usr/bin/env bash
# Migra el actualizador del tablero CVP de la carpeta personal de wvargas a /srv/tableros-bi/cvp, con un usuario de servicio.
# Se ejecuta UNA vez en el servidor de desarrollo:   sudo bash migrar-a-srv.sh
# Es idempotente y NO borra nada: /home/wvargas/tableros-bi queda como respaldo. Si la prueba de la base falla, aborta antes de tocar el cron.
set -Eeuo pipefail

# Valores por defecto = servidor de desarrollo. En producción:
#   sudo bash migrar-a-srv.sh --origen /home/<usuario>/tableros-bi --web-dir /srv/tomcat8/webapps/tablero-cvp --url-prueba http://localhost:8095/tablero-cvp/Tablero_CVP.html
ORIGEN="/home/wvargas/tableros-bi"
WEB_DIR="/srv/tomcat/webapps/tablero-cvp"
URL_PRUEBA="http://localhost/tablero-cvp/Tablero_CVP.html"
OMITIR_PRUEBA="no"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --origen) ORIGEN="${2:?falta el valor de --origen}"; shift 2 ;;
    --web-dir) WEB_DIR="${2:?falta el valor de --web-dir}"; shift 2 ;;
    --url-prueba) URL_PRUEBA="${2:?falta el valor de --url-prueba}"; shift 2 ;;
    --sin-url-prueba) URL_PRUEBA=""; shift ;;   # producción con nginx sirviendo desde disco: el despliegue verifica el archivo, no una URL
    --omitir-prueba) OMITIR_PRUEBA="si"; shift ;;   # solo para pruebas sin base de datos
    *) echo "Argumento desconocido: $1" >&2; exit 1 ;;
  esac
done
readonly ORIGEN WEB_DIR URL_PRUEBA OMITIR_PRUEBA
readonly DESTINO="/srv/tableros-bi/cvp"
readonly USUARIO="tableros"
readonly CRON_FILE="/etc/cron.d/tableros-bi-cvp"
readonly CONF_DIR="/etc/tableros-bi"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Este script debe ejecutarse con sudo." >&2
  exit 1
fi
[[ -d /etc/cron.d ]] || { echo "No existe /etc/cron.d: cron no está instalado. No se puede programar la actualización diaria." >&2; exit 1; }
[[ "$WEB_DIR" =~ ^/[A-Za-z0-9._/-]+$ ]] || { echo "--web-dir inválido" >&2; exit 1; }
[[ -z "$URL_PRUEBA" || "$URL_PRUEBA" =~ ^http://localhost(:[0-9]+)?/[A-Za-z0-9._/-]+$ ]] || { echo "--url-prueba inválida (debe ser http://localhost[:puerto]/ruta)" >&2; exit 1; }
for f in "$ORIGEN/app/actualizar_datos.py" "$ORIGEN/app/cvp_config.py" "$ORIGEN/cvp.env"; do
  [[ -f "$f" ]] || { echo "Falta $f" >&2; exit 1; }
done
[[ -d "$ORIGEN/lib/psycopg2" ]] || { echo "Falta $ORIGEN/lib/psycopg2" >&2; exit 1; }
if [[ ! -d "$WEB_DIR" ]]; then
  # Se crea si su carpeta padre ya existe o está dentro de /srv/tableros-bi (que este script crea en el paso 2).
  [[ -d "$(dirname "$WEB_DIR")" || "$WEB_DIR" == /srv/tableros-bi/* ]] || { echo "No existe $(dirname "$WEB_DIR"): revisar --web-dir" >&2; exit 1; }
fi

echo "1/6 Usuario de servicio '$USUARIO'"
if ! id "$USUARIO" >/dev/null 2>&1; then
  useradd --system --home-dir /srv/tableros-bi --shell /usr/sbin/nologin "$USUARIO"
fi

echo "2/6 Copiando a $DESTINO"
mkdir -p "$DESTINO/app" "$DESTINO/lib" "$DESTINO/log" "$DESTINO/backup"
cp -a "$ORIGEN/app/." "$DESTINO/app/"
cp -a "$ORIGEN/lib/." "$DESTINO/lib/"
install -m 0600 "$ORIGEN/cvp.env" "$DESTINO/cvp.env"
chown -R "$USUARIO:$USUARIO" /srv/tableros-bi
chmod 755 /srv/tableros-bi "$DESTINO" "$DESTINO/app" "$DESTINO/lib" "$DESTINO/log" "$DESTINO/backup"   # legibles (logs); el secreto es solo cvp.env
chmod 600 "$DESTINO/cvp.env"

echo "3/6 Dueño de $WEB_DIR -> $USUARIO (lectura abierta para el servidor web)"
mkdir -p "$WEB_DIR"
chown -R "$USUARIO:$USUARIO" "$WEB_DIR"
chmod 755 "$WEB_DIR"
find "$WEB_DIR" -type f -exec chmod 644 {} +
find "$WEB_DIR" -type d -exec chmod 755 {} +

echo "4/6 Prueba del actualizador como '$USUARIO' (escribe en una carpeta temporal, no toca el tablero)"
if [[ "$OMITIR_PRUEBA" == "si" ]]; then
  echo "    (omitida por --omitir-prueba)"
else
  PRUEBA_DIR="$(mktemp -d)"
  chown "$USUARIO:$USUARIO" "$PRUEBA_DIR"
  trap 'rm -rf "$PRUEBA_DIR"' EXIT
  sudo -u "$USUARIO" env PYTHONIOENCODING=utf-8 CVP_WEB_DIR="$PRUEBA_DIR" PYTHONPATH="$DESTINO/lib" \
    python3 "$DESTINO/app/actualizar_datos.py" --env-file "$DESTINO/cvp.env"
  [[ -s "$PRUEBA_DIR/data.js" ]] || { echo "La prueba no generó data.js. No se toca el cron." >&2; exit 1; }
fi

echo "5/6 Cron del sistema: $CRON_FILE (todos los días 6:00, como '$USUARIO')"
cat > "$CRON_FILE.new" <<CRON
# Actualizador del tablero CVP (repo gitinterkont/tableros-bi, rama cvp). Hora del servidor (Bogota).
SHELL=/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin
0 6 * * * $USUARIO cd $DESTINO/app && PYTHONIOENCODING=utf-8 CVP_WEB_DIR=$WEB_DIR PYTHONPATH=../lib python3 actualizar_datos.py --env-file ../cvp.env >> $DESTINO/log/actualizador.log 2>&1
CRON
chmod 0644 "$CRON_FILE.new"
mv -f "$CRON_FILE.new" "$CRON_FILE"

echo "    Configuración del script de despliegue: $CONF_DIR/deploy.conf"
mkdir -p "$CONF_DIR"
cat > "$CONF_DIR/deploy.conf.new" <<CONF
WEB_DIR=$WEB_DIR
URL_PRUEBA=$URL_PRUEBA
CONF
chown root:root "$CONF_DIR/deploy.conf.new"
chmod 0644 "$CONF_DIR/deploy.conf.new"
mv -f "$CONF_DIR/deploy.conf.new" "$CONF_DIR/deploy.conf"

echo "6/6 Listo."
echo
echo "Pendiente (a mano):"
echo "  - Si había un cron del usuario que instaló antes, quitarlo para que no corra dos veces (sudo crontab -u <usuario> -r)"
echo "  - Mañana después de las 6:00:   tail -8 $DESTINO/log/actualizador.log ; ls -l $WEB_DIR/data.js"
echo "  - Cuando todo esté confirmado se puede borrar el respaldo:   rm -rf $ORIGEN"
