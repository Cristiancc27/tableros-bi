#!/usr/bin/env bash
# Agrega a nginx la ruta /tablero-cvp (proxy al Tomcat) duplicando el bloque "location /cobracvp-webcomponents" del sitio.
#   sudo bash nginx-agregar-tablero.sh [--conf /etc/nginx/sites-available/sgi.conf] [--puerto 8095] [--host cvprogreso.cvp.gov.co]
# Seguro por diseño: respaldo con fecha, `nginx -t` antes de recargar, y si algo falla se restaura el archivo original. Después de recargar
# comprueba que /tablero-cvp responda 200 y que las rutas que ya existían respondan igual que antes; si no, revierte.
# Es idempotente: si ya existe el bloque, no hace nada.
set -Eeuo pipefail

CONF="/etc/nginx/sites-available/sgi.conf"
PUERTO="8095"
HOST="cvprogreso.cvp.gov.co"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --conf) CONF="${2:?falta el valor de --conf}"; shift 2 ;;
    --puerto) PUERTO="${2:?falta el valor de --puerto}"; shift 2 ;;
    --host) HOST="${2:?falta el valor de --host}"; shift 2 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 1 ;;
  esac
done
readonly CONF PUERTO HOST

if [[ "${EUID}" -ne 0 ]]; then
  echo "Este script debe ejecutarse con sudo." >&2
  exit 1
fi
[[ "$PUERTO" =~ ^[0-9]+$ ]] || { echo "--puerto inválido" >&2; exit 1; }
[[ "$HOST" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "--host inválido" >&2; exit 1; }
for cmd in nginx python3 curl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Falta el comando $cmd" >&2; exit 1; }
done
[[ -f "$CONF" ]] || { echo "No existe $CONF" >&2; exit 1; }
CONF_REAL="$(readlink -f "$CONF")"

if grep -Eq '^\s*location\s+/tablero-cvp\b' "$CONF_REAL"; then
  echo "Ya existe 'location /tablero-cvp' en $CONF_REAL: no se hace nada."
  exit 0
fi

recargar() {
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nginx 2>/dev/null; then
    systemctl reload nginx
  else
    nginx -s reload
  fi
}

# Código HTTP de una ruta a través de nginx (TLS local, con el Host del sitio).
codigo() {
  curl -sk -o /dev/null -w '%{http_code}' --max-time 8 -H "Host: $HOST" "https://127.0.0.1$1" || true
}

echo "1/5 Comprobando que nginx está sano antes de tocar nada"
nginx -t

echo "2/5 Estado previo de las rutas existentes"
ANTES_SGI="$(codigo /sgi/)"
ANTES_WC="$(codigo /cobracvp-webcomponents/tablero-cvp.js)"
echo "    /sgi/ -> $ANTES_SGI | /cobracvp-webcomponents/tablero-cvp.js -> $ANTES_WC"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$CONF_REAL.bak-$STAMP"

restaurar() {
  echo "Restaurando $CONF_REAL desde $BACKUP ..." >&2
  cp -a "$BACKUP" "$CONF_REAL"
  nginx -t >&2 && recargar || true
}

NUEVO="$(mktemp)"
trap 'rm -f "$NUEVO"' EXIT
python3 - "$CONF_REAL" "$NUEVO" "$PUERTO" <<'PY'
import re, sys
origen, destino, puerto = sys.argv[1], sys.argv[2], sys.argv[3]
texto = open(origen, encoding="utf-8").read()
m = list(re.finditer(r'^[ \t]*location[ \t]+/cobracvp-webcomponents[ \t]*\{', texto, re.M))
if len(m) != 1:
    sys.exit("ERROR: se esperaba exactamente un bloque 'location /cobracvp-webcomponents' y hay %d. No se modifica nada." % len(m))
i = m[0].end()
profundidad = 1
while i < len(texto) and profundidad:
    if texto[i] == '{':
        profundidad += 1
    elif texto[i] == '}':
        profundidad -= 1
    i += 1
if profundidad:
    sys.exit("ERROR: llaves sin cerrar en el bloque de /cobracvp-webcomponents.")
bloque = """

    # Tablero CVProgreso (HTML estatico + data.js). Repo gitinterkont/tableros-bi, rama cvp.
    location  /tablero-cvp {
        proxy_pass         http://localhost:%s/tablero-cvp;
        proxy_redirect     off;
        proxy_set_header   Host $host;
        # data.js pesa ~1,5 MB: se comprime (el Tomcat no lo hace).
        gzip               on;
        gzip_types         application/javascript text/html;
        add_header Cache-Control 'no-store, no-cache';
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload";
    }""" % puerto
open(destino, "w", encoding="utf-8").write(texto[:i] + bloque + texto[i:])
PY

cp -a "$CONF_REAL" "$BACKUP"
echo "3/5 Respaldo: $BACKUP"
install -m "$(stat -c %a "$CONF_REAL")" -o "$(stat -c %u "$CONF_REAL")" -g "$(stat -c %g "$CONF_REAL")" "$NUEVO" "$CONF_REAL"

echo "4/5 Probando la configuración nueva (nginx -t)"
if ! nginx -t; then
  restaurar
  echo "nginx -t falló: se restauró el archivo original. No se recargó nada." >&2
  exit 1
fi
recargar

echo "5/5 Verificando"
OK="no"
for _ in 1 2 3 4 5; do
  if [[ "$(codigo /tablero-cvp/data.js)" == "200" ]]; then OK="si"; break; fi
  sleep 2
done
DESPUES_SGI="$(codigo /sgi/)"
DESPUES_WC="$(codigo /cobracvp-webcomponents/tablero-cvp.js)"
echo "    /tablero-cvp/data.js -> $(codigo /tablero-cvp/data.js)"
echo "    /sgi/ -> $DESPUES_SGI (antes $ANTES_SGI) | /cobracvp-webcomponents/tablero-cvp.js -> $DESPUES_WC (antes $ANTES_WC)"
if [[ "$OK" != "si" || "$DESPUES_SGI" != "$ANTES_SGI" || "$DESPUES_WC" != "$ANTES_WC" ]]; then
  echo "La verificación falló: se revierte el cambio." >&2
  restaurar
  exit 1
fi

echo
echo "Listo. /tablero-cvp quedó enrutado. Respaldo: $BACKUP"
echo "Revertir a mano: sudo cp -a $BACKUP $CONF_REAL && sudo nginx -t && sudo systemctl reload nginx"
