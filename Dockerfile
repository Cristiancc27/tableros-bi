# Actualizador del Tablero CVProgreso: corre actualizar_datos.py al arrancar y luego
# cada CVP_ACTUALIZAR_CADA_HORAS horas, y escribe data.js en /web.
# Python 3.12: psycopg2-binary 2.9.13 pide >= 3.10 (el codigo en si corre desde 3.6).
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    CVP_WEB_DIR=/web

# Usuario sin privilegios. /web es donde se escribe data.js (volumen compartido con nginx);
# crearlo aqui con su dueño hace que el volumen nombrado herede ese dueño.
RUN groupadd --system --gid 10001 cvp \
 && useradd --system --uid 10001 --gid cvp --no-create-home --shell /usr/sbin/nologin cvp \
 && mkdir /app /web \
 && chown cvp:cvp /web

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

# Solo estos tres archivos. El .env, el .html y data.js NO van en la imagen
# (la configuracion llega como variables de entorno desde docker compose).
COPY actualizar_datos.py cvp_config.py entrypoint.sh ./
# sed: por si el archivo se descargo en Windows con finales de linea CRLF.
RUN sed -i 's/\r$//' entrypoint.sh && chmod 0755 entrypoint.sh

VOLUME ["/web"]
USER cvp

ENTRYPOINT ["/app/entrypoint.sh"]
