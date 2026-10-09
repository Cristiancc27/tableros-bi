#!/usr/bin/env bash
# Migra el actualizador del tablero CVP de la carpeta personal de wvargas a /srv/tableros-bi/cvp, con un usuario de servicio.
# Se ejecuta UNA vez en el servidor de desarrollo:   sudo bash migrar-a-srv.sh
# Es idempotente y NO borra nada: /home/wvargas/tableros-bi queda como respaldo. Si la prueba de la base falla, aborta antes de tocar el cron.
set -Eeuo pipefail

readonly ORIGEN="/home/wvargas/tableros-bi"
readonly DESTINO="/srv/tableros-bi/cvp"
readonly USUARIO="tableros"
readonly WEB_DIR="/srv/tomcat/webapps/tablero-cvp"
readonly CRON_FILE="/etc/cron.d/tableros-bi-cvp"
OMITIR_PRUEBA="no"
[[ "${1:-}" == "--omitir-prueba" ]] && OMITIR_PRUEBA="si"   # solo para pruebas sin base de datos

if [[ "${EUID}" -ne 0 ]]; then
  echo "Este script debe ejecutarse con sudo." >&2
  exit 1
fi
for f in "$ORIGEN/app/actualizar_datos.py" "$ORIGEN/app/cvp_config.py" "$ORIGEN/cvp.env"; do
  [[ -f "$f" ]] || { echo "Falta $f" >&2; exit 1; }
done
[[ -d "$ORIGEN/lib/psycopg2" ]] || { echo "Falta $ORIGEN/lib/psycopg2" >&2; exit 1; }
[[ -d "$WEB_DIR" ]] || { echo "Falta $WEB_DIR (carpeta del tablero)" >&2; exit 1; }

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

echo "3/6 Dueño de $WEB_DIR -> $USUARIO (lectura abierta para Tomcat)"
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

echo "6/6 Listo."
echo
echo "Pendiente (a mano):"
echo "  - Quitar el cron viejo de wvargas para que no corra dos veces:   sudo crontab -u wvargas -r"
echo "  - Mañana después de las 6:00:   tail -8 $DESTINO/log/actualizador.log ; ls -l $WEB_DIR/data.js"
echo "  - Cuando todo esté confirmado se puede borrar el respaldo:   rm -rf $ORIGEN"
