#!/bin/sh
# Ejecuta actualizar_datos.py al arrancar y luego lo repite cada CVP_ACTUALIZAR_CADA_HORAS horas.
#   CVP_ACTUALIZAR_CADA_HORAS=24   (por defecto) una corrida al arrancar y una cada 24 h
#   CVP_ACTUALIZAR_CADA_HORAS=0    una sola corrida y el contenedor termina
#                                  (con el codigo de salida de esa corrida)
#   CVP_ACTUALIZAR_CADA_SEGUNDOS   opcional, solo para pruebas: si esta definido, manda sobre las horas
#
# Si una corrida falla, se registra el error y se reintenta en el proximo ciclo. El data.js anterior
# no se toca: actualizar_datos.py lo reemplaza de forma atomica solo cuando todo salio bien.
# Con SIGTERM/SIGINT (docker compose down / stop) termina de inmediato.

log() { printf '%s [actualizador] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

HORAS="${CVP_ACTUALIZAR_CADA_HORAS:-24}"
case "$HORAS" in
  ''|*[!0-9]*) log "ERROR: CVP_ACTUALIZAR_CADA_HORAS debe ser un entero >= 0 (valor: '$HORAS')"; exit 2 ;;
esac
if [ -n "${CVP_ACTUALIZAR_CADA_SEGUNDOS:-}" ]; then
  case "$CVP_ACTUALIZAR_CADA_SEGUNDOS" in
    *[!0-9]*) log "ERROR: CVP_ACTUALIZAR_CADA_SEGUNDOS debe ser un entero"; exit 2 ;;
  esac
  ESPERA="$CVP_ACTUALIZAR_CADA_SEGUNDOS"
else
  ESPERA=$((HORAS * 3600))
fi

HIJO=""
terminar() {
  log "Senal de parada recibida, saliendo."
  if [ -n "$HIJO" ]; then kill "$HIJO" 2>/dev/null; fi
  exit 0
}
trap terminar TERM INT

# Los procesos largos (python, sleep) corren en segundo plano y se espera con `wait`,
# porque el shell solo atiende la senal cuando no esta ejecutando un comando en primer plano.
esperar_hijo() {
  wait "$HIJO"
  RC=$?
  HIJO=""
  return $RC
}

while :; do
  log "Iniciando actualizacion."
  python /app/actualizar_datos.py &
  HIJO=$!
  esperar_hijo
  RC=$?
  if [ "$RC" -eq 0 ]; then
    log "Actualizacion terminada correctamente."
  else
    log "ERROR: la actualizacion fallo (codigo $RC). Se conserva el data.js anterior."
  fi

  if [ "$ESPERA" -eq 0 ]; then
    log "Modo de una sola corrida: saliendo con codigo $RC."
    exit "$RC"
  fi

  log "Proxima actualizacion en $ESPERA segundos."
  sleep "$ESPERA" &
  HIJO=$!
  esperar_hijo
done
