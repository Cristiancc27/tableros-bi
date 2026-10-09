# tableros-bi · rama `cvp`

Tablero **CVProgreso / Mejora tu Casa** (reemplazo del Power BI), entregado por Cristian Correa: HTML estático + actualizador Python que lee `viviendacvp` (solo lectura) y genera `data.js`. Se embebe por **iframe** en `cobra-housing` (`reportes/biFrameCVProgreso.xhtml`, variable de perfil `url.tablerocvp`).

Una rama por cliente (`cvp`, `gespro`…), cada una autónoma: el tablero cambia seguido y se ajusta aquí sin tocar el backend ni desplegar el aplicativo.

- Prueba local con datos ficticios: ver `README_docker.md` (`cp .env.docker.example .env && docker compose --profile bd-prueba up --build`, luego http://localhost:8080).
- Configuración por ambiente, consultas y reglas de cálculo: `README_conexion.md`.
- Seguridad: el nginx del compose **no tiene login** y solo escucha en `127.0.0.1`. `data.js` trae datos operativos (CHIP, barrio, estados): en un servidor debe quedar detrás del login del aplicativo y la BD se lee con un usuario de **solo lectura**. El `.env` real no se versiona.
