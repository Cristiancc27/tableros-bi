# Tablero CVProgreso (HTML) · Guía de conexión y configuración

## Qué es
`Tablero_CVP.html` reemplaza al tablero de Power BI con el mismo contenido (Portada, Tablero General, Ejecución Presupuestal, Detalle) más una página **Datos completos** con búsqueda. Cada gráfica tiene un botón **CSV** y el encabezado un botón **Descargar PDF** (imprime la página con los filtros aplicados). Es **un solo archivo**: estilos, logos y gráficas incluidos, sin librerías externas. El tablero original de Power BI no se modifica.

Sin datos conectados muestra **datos de ejemplo** (aviso naranja arriba).

## Cómo funciona
```
Base viviendacvp ──(solo lectura)──> actualizar_datos.py ──> data.js ──> Tablero_CVP.html (navegador)
```
`actualizar_datos.py` corre una vez al día (tarea programada, cron o contenedor), ejecuta las mismas consultas del modelo de Power BI y escribe `data.js` en la carpeta de la aplicación web. El HTML lee `data.js` al abrirse.

| Archivo | Para qué sirve |
|---|---|
| `Tablero_CVP.html` | La aplicación (estática). |
| `actualizar_datos.py` | Lee la base y genera `data.js`. Usa `cvp_config.py`. |
| `cvp_config.py` | Lee las propiedades del ambiente (variables de entorno / `.env`). |
| `.env.example` | Plantilla de propiedades (equivalente a `application.properties`). |
| `crear_html_compartir.py` | Opcional: une HTML + `data.js` en un solo archivo para enviarlo por correo/Slack. No se usa en el servidor. |
| `actualizar_datos.bat` | Atajo de Windows que ejecuta los dos scripts anteriores. No se usa en el servidor. |
| `consultas_tablero.sql` | Las consultas, documentadas. |

## Configuración por ambiente (externalizada)
Nada de la configuración está dentro del código. Prioridad (gana el primero):

1. **Variables de entorno `CVP_*`** (Docker: `-e` o `--env-file`).
2. **Archivo `.env`** junto a los scripts, o el que indique `CVP_ENV_FILE` / `--env-file` (p. ej. `.env.dev`, `.env.prod`).
3. `config.ini` (formato antiguo, solo conexión).
4. Valores por defecto.

| Variable | Descripción | Defecto |
|---|---|---|
| `CVP_AMBIENTE` | Nombre del ambiente (solo informativo en el log) | `local` |
| `CVP_DB_URL` | Cadena de conexión `postgresql://usuario:clave@host:5432/viviendacvp?sslmode=require` (clave con caracteres especiales codificada) | — |
| `CVP_DB_HOST` `CVP_DB_PORT` `CVP_DB_NAME` `CVP_DB_USER` `CVP_DB_PASSWORD` `CVP_DB_SSLMODE` | Alternativa a la URL, por campos | puerto 5432, base `viviendacvp` |
| `CVP_DB_DSN` | Alternativa: DSN ODBC existente (requiere `pyodbc`) | — |
| `CVP_DB_TIMEOUT_SEG` `CVP_DB_STATEMENT_TIMEOUT_SEG` | Tiempos máximos | 15 / 120 |
| `CVP_WEB_DIR` | **Carpeta de la aplicación web**: donde está `Tablero_CVP.html` y donde se escribe `data.js` | carpeta de los scripts |
| `CVP_CONTRATOS` | IDs de contrato que son lotes (el 2849 es interventoría y **no** va) | `2844,2846,2847,2848` |
| `CVP_LOTES_NOMBRES` | `id=nombre;id=nombre...` | Bosa Lote 1/2, Suba Lote 1/2 |
| `CVP_META_LOTE` | Meta de hogares por lote | `220` |
| `CVP_FECHA_INICIO` `CVP_FECHA_FIN` | Vigencia del programa (AAAA-MM-DD) | 2026-06-01 / 2026-12-31 |

Uso típico:
```
cp .env.example .env.prod        # completar valores (no subir a ningún repositorio)
python actualizar_datos.py --env-file .env.prod
```
En Docker, sin archivo: `docker run -e CVP_DB_URL=... -e CVP_WEB_DIR=/usr/share/nginx/html ...`.

El script nunca imprime la contraseña, abre la sesión en modo `read_only` y, si la consulta de hogares viene vacía, **no** reemplaza el `data.js` anterior.

### Propiedades del lado del navegador (opcional)
Si se prefiere API en vivo en lugar de `data.js`, cada ambiente puede crear un `config.js` junto al HTML (sin editar el HTML):
```js
window.CVP_CONFIG = { apiBase: '/api/tablero' };
```
El HTML pide entonces `GET {apiBase}/hogares`, `/historial`, `/lotes`, `/pagos`, `/parametros` (arreglos JSON con los alias de `consultas_tablero.sql`). Con `apiBase` definido se ignora `data.js`.

## Despliegue sugerido (Docker)
- Contenedor Python (`psycopg2-binary`) que ejecuta `actualizar_datos.py` una vez al día (cron o programador), con `CVP_WEB_DIR` apuntando a un volumen compartido.
- Servidor web estático (p. ej. nginx) que sirve ese volumen: `Tablero_CVP.html` y `data.js`.
- Cambiar el `src` del iframe de Power BI por la dirección del nuevo HTML.

## Seguridad
- Sin usuario ni contraseña de la base en el HTML ni en el repositorio: solo en variables de entorno o `.env` (fuera del control de versiones). Usar un usuario de **solo lectura**.
- `data.js` contiene datos operativos (CHIP, barrio, estados): servirlo solo detrás del login del aplicativo.

## Diferencias frente a Power BI
- Los acumulados mensuales cuentan hasta el **final del día** del último día del mes (Power BI los cortaba a las 00:00).
- La Portada también acepta el filtro de lote.
- "Datos completos" es visible (en Power BI esa página estaba oculta).
- Los semáforos (En tiempo / En riesgo / Atrasado) usan la misma regla de fechas respecto a `CVP_FECHA_FIN`.

## Reglas que conviene no cambiar
- "Mejoramientos terminados" = estado actual **«Ejecutado Entregado»** (id 2). Si renombran ese estado en `tipoestadobra`, hay que cambiar el texto en el HTML (buscar `Ejecutado Entregado`).
- Los pagos salen de `public.desembolso`; si esa tabla no tiene registros de los contratos, Ejecución Presupuestal muestra pagos en $0.

## Docker
Hay un paquete para probar todo en local con Docker (actualizador Python + nginx, y una base de prueba con datos inventados opcional): ver **`README_docker.md`**. Incluye `Dockerfile`, `docker-compose.yml`, `.env.docker.example` y los pasos exactos. Es solo para pruebas: el contenedor web no tiene login, y en servidor `data.js` debe servirse detrás de la autenticación del aplicativo.
