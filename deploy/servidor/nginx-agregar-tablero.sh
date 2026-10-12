#!/usr/bin/env bash
# Publica el Tablero CVProgreso en nginx protegido con la sesión del aplicativo (auth_request).
#   sudo bash nginx-agregar-tablero.sh [--conf /etc/nginx/sites-available/sgi.conf] [--contexto sgi] [--puerto 8095]
#                                      [--dir /srv/tableros-bi/cvp/web] [--host cvprogreso.cvp.gov.co] [--retirar-ruta-vieja]
#
# Agrega, junto al bloque de /cobracvp-webcomponents:
#   - location = /_tablero_auth        (interna) pregunta al servlet /<contexto>/tablero-auth del JSF si hay sesión con permiso
#   - location ^~ /<contexto>/tablero-cvp/   sirve los archivos DESDE DISCO (--dir) y exige esa validación para TODO (HTML, config.js, data.js)
# La cookie de sesión del aplicativo lleva Path=/<contexto>, por eso el tablero se publica bajo /<contexto>/tablero-cvp/ (con otra ruta
# el navegador no enviaría la cookie y siempre diría "sin sesión").
#
# Requisito: el WAR con el servlet /tablero-auth ya desplegado (si no, nginx daría 500: el script lo detecta y revierte).
# Seguro: respaldo con fecha, `nginx -t` antes/después, verificación y reversión automática. Idempotente.
set -Eeuo pipefail

CONF="/etc/nginx/sites-available/sgi.conf"
CONTEXTO="sgi"
PUERTO="8095"
DIR="/srv/tableros-bi/cvp/web"
HOST="cvprogreso.cvp.gov.co"
RETIRAR_VIEJA="no"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --conf) CONF="${2:?falta el valor de --conf}"; shift 2 ;;
    --contexto) CONTEXTO="${2:?falta el valor de --contexto}"; shift 2 ;;
    --puerto) PUERTO="${2:?falta el valor de --puerto}"; shift 2 ;;
    --dir) DIR="${2:?falta el valor de --dir}"; shift 2 ;;
    --host) HOST="${2:?falta el valor de --host}"; shift 2 ;;
    --retirar-ruta-vieja) RETIRAR_VIEJA="si"; shift ;;
    *) echo "Argumento desconocido: $1" >&2; exit 1 ;;
  esac
done
readonly CONF CONTEXTO PUERTO DIR HOST RETIRAR_VIEJA

if [[ "${EUID}" -ne 0 ]]; then
  echo "Este script debe ejecutarse con sudo." >&2
  exit 1
fi
[[ "$PUERTO" =~ ^[0-9]+$ ]] || { echo "--puerto inválido" >&2; exit 1; }
[[ "$HOST" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "--host inválido" >&2; exit 1; }
[[ "$CONTEXTO" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "--contexto inválido" >&2; exit 1; }
[[ "$DIR" =~ ^/[A-Za-z0-9._/-]+$ ]] || { echo "--dir inválido" >&2; exit 1; }
for cmd in nginx python3 curl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Falta el comando $cmd" >&2; exit 1; }
done
[[ -f "$CONF" ]] || { echo "No existe $CONF" >&2; exit 1; }
[[ -d "$DIR" ]] || { echo "No existe $DIR (carpeta de datos del tablero). Ejecuta antes migrar-a-srv.sh con --web-dir $DIR" >&2; exit 1; }
CONF_REAL="$(readlink -f "$CONF")"

YA_E="no"
if grep -Eq "^\s*location\s+\^~\s+/${CONTEXTO}/tablero-cvp/" "$CONF_REAL" && grep -Eq '^\s*location\s+=\s+/_tablero_auth' "$CONF_REAL"; then
  YA_E="si"
fi
VIEJA_ACTIVA="no"
grep -Eq '^\s*location\s+/tablero-cvp\b' "$CONF_REAL" && VIEJA_ACTIVA="si"
if [[ "$YA_E" == "si" && ( "$RETIRAR_VIEJA" == "no" || "$VIEJA_ACTIVA" == "no" ) ]]; then
  echo "Ya está la protección de /${CONTEXTO}/tablero-cvp/ en $CONF_REAL: no se hace nada."
  [[ "$VIEJA_ACTIVA" == "si" ]] && echo "Nota: sigue activa la ruta vieja 'location /tablero-cvp' (proxy al Tomcat). Para retirarla: --retirar-ruta-vieja"
  exit 0
fi

recargar() {
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nginx 2>/dev/null; then
    systemctl reload nginx
  else
    nginx -s reload
  fi
}
codigo() {
  curl -sk -o /dev/null -w '%{http_code}' --max-time 8 -H "Host: $HOST" "https://127.0.0.1$1" || true
}

echo "1/6 Comprobando que nginx está sano antes de tocar nada"
nginx -t

echo "2/6 Estado previo de las rutas existentes"
ANTES_APP="$(codigo "/${CONTEXTO}/")"
ANTES_WC="$(codigo /cobracvp-webcomponents/tablero-cvp.js)"
echo "    /${CONTEXTO}/ -> $ANTES_APP | /cobracvp-webcomponents/tablero-cvp.js -> $ANTES_WC"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$CONF_REAL.bak-$STAMP"
restaurar() {
  echo "Restaurando $CONF_REAL desde $BACKUP ..." >&2
  cp -a "$BACKUP" "$CONF_REAL"
  nginx -t >&2 && recargar || true
}

NUEVO="$(mktemp)"
trap 'rm -f "$NUEVO"' EXIT
python3 - "$CONF_REAL" "$NUEVO" "$CONTEXTO" "$PUERTO" "$DIR" "$YA_E" "$RETIRAR_VIEJA" <<'PY'
import re, sys
origen, destino, contexto, puerto, directorio, ya_e, retirar = sys.argv[1:8]
texto = open(origen, encoding="utf-8").read()

def fin_bloque(t, inicio):
    """Índice justo después de la llave que cierra el bloque cuyo '{' está antes de `inicio`."""
    i, prof = inicio, 1
    while i < len(t) and prof:
        prof += 1 if t[i] == '{' else -1 if t[i] == '}' else 0
        i += 1
    if prof:
        sys.exit("ERROR: llaves sin cerrar en el archivo de nginx.")
    return i

if ya_e != "si":
    m = list(re.finditer(r'^[ \t]*location[ \t]+/cobracvp-webcomponents[ \t]*\{', texto, re.M))
    if len(m) != 1:
        sys.exit("ERROR: se esperaba exactamente un bloque 'location /cobracvp-webcomponents' y hay %d. No se modifica nada." % len(m))
    i = fin_bloque(texto, m[0].end())
    bloque = """

    # --- Tablero CVProgreso (repo gitinterkont/tableros-bi, rama cvp) -----------------------------------------------------------
    # Subpeticion interna: pregunta al JSF si hay sesion con permiso de reportes (204 = si, 401/403 = no). Nunca se expone afuera.
    location = /_tablero_auth {
        internal;
        proxy_pass              http://localhost:%(puerto)s/%(contexto)s/tablero-auth;
        proxy_pass_request_body off;
        proxy_set_header        Content-Length "";
        proxy_set_header        Host $http_host;
        proxy_set_header        X-Original-URI $request_uri;
    }
    # Todo el tablero (HTML, config.js y data.js) se entrega desde disco y exige sesion. Sin excepciones por archivo.
    location ^~ /%(contexto)s/tablero-cvp/ {
        auth_request  /_tablero_auth;
        alias         %(dir)s/;
        gzip          on;
        gzip_types    application/javascript text/html;
        add_header    Cache-Control 'no-store, no-cache, private' always;
        add_header    Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    }
    # --- fin Tablero CVProgreso -----------------------------------------------------------------------------------------------""" % {
        "puerto": puerto, "contexto": contexto, "dir": directorio.rstrip("/")}
    texto = texto[:i] + bloque + texto[i:]

if retirar == "si":
    v = list(re.finditer(r'^[ \t]*location[ \t]+/tablero-cvp\b[^{]*\{', texto, re.M))
    if len(v) == 1:
        fin = fin_bloque(texto, v[0].end())
        comentado = "\n".join(("    # [retirado: ahora el tablero va protegido bajo /%s/tablero-cvp/] " % contexto) + l.lstrip()
                              if l.strip() else l for l in texto[v[0].start():fin].split("\n"))
        texto = texto[:v[0].start()] + comentado + texto[fin:]
open(destino, "w", encoding="utf-8").write(texto)
PY

cp -a "$CONF_REAL" "$BACKUP"
echo "3/6 Respaldo: $BACKUP"
install -m "$(stat -c %a "$CONF_REAL")" -o "$(stat -c %u "$CONF_REAL")" -g "$(stat -c %g "$CONF_REAL")" "$NUEVO" "$CONF_REAL"

echo "4/6 Probando la configuración nueva (nginx -t)"
if ! nginx -t; then
  restaurar
  echo "nginx -t falló: se restauró el archivo original. No se recargó nada." >&2
  exit 1
fi
recargar

echo "5/6 Verificando (sin sesión, el tablero debe responder 401: nginx -> servlet del JSF -> 401)"
# nginx recarga de forma asíncrona: los procesos viejos pueden seguir atendiendo unos instantes con la configuración anterior.
PROTEGIDO=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  PROTEGIDO="$(codigo "/${CONTEXTO}/tablero-cvp/data.js")"
  [[ "$PROTEGIDO" == "401" ]] && break
  sleep 1
done
DESPUES_APP="$(codigo "/${CONTEXTO}/")"
DESPUES_WC="$(codigo /cobracvp-webcomponents/tablero-cvp.js)"
echo "    /${CONTEXTO}/tablero-cvp/data.js (sin sesión) -> $PROTEGIDO"
echo "    /${CONTEXTO}/ -> $DESPUES_APP (antes $ANTES_APP) | /cobracvp-webcomponents/tablero-cvp.js -> $DESPUES_WC (antes $ANTES_WC)"
if [[ "$PROTEGIDO" == "500" ]]; then
  echo "500: el servlet /${CONTEXTO}/tablero-auth no responde (¿el WAR con el servlet ya está desplegado?). Se revierte el cambio." >&2
elif [[ "$PROTEGIDO" != "401" ]]; then
  echo "Se esperaba 401 sin sesión y llegó $PROTEGIDO. Se revierte el cambio." >&2
fi
if [[ "$PROTEGIDO" != "401" || "$DESPUES_APP" != "$ANTES_APP" || "$DESPUES_WC" != "$ANTES_WC" ]]; then
  restaurar
  exit 1
fi

echo "6/6 Listo. /${CONTEXTO}/tablero-cvp/ quedó protegido con la sesión del aplicativo. Respaldo: $BACKUP"
[[ "$RETIRAR_VIEJA" == "no" && "$VIEJA_ACTIVA" == "si" ]] && echo "Nota: sigue activa la ruta vieja 'location /tablero-cvp' (proxy al Tomcat). Para retirarla: vuelve a ejecutar con --retirar-ruta-vieja"
echo "Revertir a mano: sudo cp -a $BACKUP $CONF_REAL && sudo nginx -t && sudo systemctl reload nginx"
