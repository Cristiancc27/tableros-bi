# Despliegue del tablero CVP (desarrollo)

> **Los workflows de despliegue ya no viven en esta rama.** Son unificados y están en la rama `main` (`deploy-develop.yml` y `deploy-prod.yml`): se lanzan desde `main` eligiendo el cliente `cvp`, y descargan el código de esta rama. Ver `docs/CONVENCIONES.md` en `main`. El despliegue automático por push ya no existe.

Al lanzar el workflow de desarrollo con el cliente `cvp`, se copia el HTML (`Tablero_CVP.html`) y `deploy/WEB-INF/web.xml` al servidor de desarrollo. Los **datos** (`data.js`) los sigue refrescando el cron del servidor (todos los días 6:00); el workflow no los toca.

```
lanzamiento manual desde main (cliente cvp) ──> runner de la organización ──ssh (cicd-deploy)──> sudo deploy-tableros-bi <paquete.tar.gz>
                                                                   └─ valida, respalda, instala y verifica (200 + SAMEORIGIN); si falla, restaura
```

## Estructura en el servidor de desarrollo
| Qué | Dónde | Dueño |
|---|---|---|
| HTML, `data.js`, `config.js`, `WEB-INF/web.xml` | `/srv/tomcat/webapps/tablero-cvp/` | `tableros` |
| Actualizador, `psycopg2`, `cvp.env` (clave de `tablero_ro`, 600), log, respaldos del HTML | `/srv/tableros-bi/cvp/{app,lib,cvp.env,log,backup}` | `tableros` |
| Cron | `/etc/cron.d/tableros-bi-cvp` (6:00, como `tableros`) | root |
| Script de despliegue | `/usr/local/sbin/deploy-tableros-bi` | root |
| Permiso sudo | `/etc/sudoers.d/cicd-deploy-tableros-bi` | root |
| Rutas propias del servidor (`WEB_DIR`, `URL_PRUEBA`) | `/etc/tableros-bi/deploy.conf` (lo escribe `migrar-a-srv.sh`; si no existe, valores de desarrollo) | root |

## Instalación (una vez, con sudo; probada en un contenedor Ubuntu 16.04)
Desde la Mac, en la carpeta de este repo:

    scp deploy/servidor/migrar-a-srv.sh deploy/servidor/deploy-tableros-bi deploy/servidor/sudoers-cicd-deploy-tableros-bi Interkont-Desarrollo:/tmp/

1. Migrar el actualizador a la carpeta general (crea el usuario `tableros`, copia, prueba contra la base y deja el cron del sistema; no borra nada):

       ssh -t Interkont-Desarrollo 'sudo bash /tmp/migrar-a-srv.sh'
       ssh -t Interkont-Desarrollo 'sudo crontab -u wvargas -r'     # quita el cron viejo (solo tenía esa línea)

2. Instalar el script de despliegue y su permiso:

       ssh -t Interkont-Desarrollo 'sudo install -o root -g root -m 0755 /tmp/deploy-tableros-bi /usr/local/sbin/deploy-tableros-bi'
       ssh -t Interkont-Desarrollo 'sudo visudo -cf /tmp/sudoers-cicd-deploy-tableros-bi && sudo install -o root -g root -m 0440 /tmp/sudoers-cicd-deploy-tableros-bi /etc/sudoers.d/cicd-deploy-tableros-bi && sudo visudo -c'

3. En GitHub (`tableros-bi` → Settings → Environments → `interkont-develop`): **secreto**: `DEPLOY_SSH_PRIVATE_KEY`; **variables**: `DEPLOY_HOST`, `DEPLOY_USER` (= `cicd-deploy`), `DEPLOY_KNOWN_HOSTS`; opcionales (variables): `DEPLOY_PORT`, `DEPLOY_SCRIPT`, `DEPLOY_KEY_FINGERPRINT`. Son los mismos valores que usa `solicitudes-ikont` para el mismo servidor (los administra Felix).
4. Probar a mano: Actions → *Desplegar tablero en desarrollo* → *Run workflow* desde la rama **`main`**, cliente `cvp`.

## Seguridad
- `cicd-deploy` solo puede ejecutar ese script con sudo; el script solo acepta `/tmp/tableros-bi-cvp-<run>-<intento>.tar.gz` con exactamente `Tablero_CVP.html` y `WEB-INF/web.xml`, rechaza cualquier otra entrada y no toca `data.js`, `config.js` ni la base.
- La clave de `tablero_ro` solo vive en `cvp.env` (600, `tableros`); no pasa por GitHub.
- Sigue pendiente (aparte): el tablero y `data.js` no tienen login.

## Reversión
- HTML: respaldos en `/srv/tableros-bi/cvp/backup/` (10 más recientes); el script restaura solo si el tablero no responde bien tras el cambio.
- Quitar el permiso: `sudo rm /etc/sudoers.d/cicd-deploy-tableros-bi /usr/local/sbin/deploy-tableros-bi`.

## Workflows y environments (convención del equipo)
| Ambiente | Workflow (en `main`) | Environment | Disparo |
|---|---|---|---|
| Desarrollo | `deploy-develop.yml` | `interkont-develop` (solo `main`) | manual, cliente `cvp` |
| Producción | `deploy-prod.yml` | `cvp-prod` (solo `main`) | manual, cliente `cvp`, confirmando `DESPLEGAR-PRODUCCION` |

Cada environment lleva el secreto `DEPLOY_SSH_PRIVATE_KEY` y las variables `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_KNOWN_HOSTS` (y opcionales). Producción: ver `DESPLIEGUE_PRODUCCION.md` (usuario `cicd-tableros`, par de llaves propio, `migrar-a-srv.sh` con `--web-dir` y `--url-prueba` de producción).

## Protecciones del repo
- Rama `cvp`: pull request con 1 aprobación; sin force-push ni borrado. Los admins pueden saltarla (no se activó *Do not allow bypassing*).
- `interkont-develop` y `cvp-prod` solo admiten la rama `main`, donde viven los workflows.
