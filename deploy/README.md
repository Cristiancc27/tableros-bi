# Despliegue automático del tablero CVP (desarrollo)

Al cambiar `Tablero_CVP.html` (o `deploy/WEB-INF/web.xml`) en la rama `cvp`, el workflow `.github/workflows/deploy-develop.yml` copia el HTML al servidor de desarrollo. Los **datos** (`data.js`) los sigue refrescando el cron del servidor (todos los días 6:00); el workflow no los toca.

```
push a cvp ──> runner de la organización ──ssh (cicd-deploy)──> sudo deploy-tableros-bi <paquete.tar.gz>
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

## Instalación (una vez, con sudo; probada en un contenedor Ubuntu 16.04)
Desde la Mac, en la carpeta de este repo:

    scp deploy/servidor/migrar-a-srv.sh deploy/servidor/deploy-tableros-bi deploy/servidor/sudoers-cicd-deploy-tableros-bi Interkont-Desarrollo:/tmp/

1. Migrar el actualizador a la carpeta general (crea el usuario `tableros`, copia, prueba contra la base y deja el cron del sistema; no borra nada):

       ssh -t Interkont-Desarrollo 'sudo bash /tmp/migrar-a-srv.sh'
       ssh -t Interkont-Desarrollo 'sudo crontab -u wvargas -r'     # quita el cron viejo (solo tenía esa línea)

2. Instalar el script de despliegue y su permiso:

       ssh -t Interkont-Desarrollo 'sudo install -o root -g root -m 0755 /tmp/deploy-tableros-bi /usr/local/sbin/deploy-tableros-bi'
       ssh -t Interkont-Desarrollo 'sudo visudo -cf /tmp/sudoers-cicd-deploy-tableros-bi && sudo install -o root -g root -m 0440 /tmp/sudoers-cicd-deploy-tableros-bi /etc/sudoers.d/cicd-deploy-tableros-bi && sudo visudo -c'

3. En GitHub (`tableros-bi` → Settings → Environments → `interkont-develop`): secretos `DEPLOY_HOST`, `DEPLOY_USER` (= `cicd-deploy`), `DEPLOY_SSH_PRIVATE_KEY`, `DEPLOY_KNOWN_HOSTS`; opcionales (variables): `DEPLOY_PORT`, `DEPLOY_SCRIPT`, `DEPLOY_KEY_FINGERPRINT`. Son los mismos valores que usa `solicitudes-ikont` para el mismo servidor (los administra Felix).
4. Probar a mano: Actions → *Desplegar tablero CVP en desarrollo* → *Run workflow* (rama `cvp`).
5. Cuando funcione, activar el despliegue automático por push: variable de repositorio `DEPLOY_CVP_AUTO` = `true`.

## Seguridad
- `cicd-deploy` solo puede ejecutar ese script con sudo; el script solo acepta `/tmp/tableros-bi-cvp-<run>-<intento>.tar.gz` con exactamente `Tablero_CVP.html` y `WEB-INF/web.xml`, rechaza cualquier otra entrada y no toca `data.js`, `config.js` ni la base.
- La clave de `tablero_ro` solo vive en `cvp.env` (600, `tableros`); no pasa por GitHub.
- Sigue pendiente (aparte): el tablero y `data.js` no tienen login.

## Reversión
- HTML: respaldos en `/srv/tableros-bi/cvp/backup/` (10 más recientes); el script restaura solo si el tablero no responde bien tras el cambio.
- Quitar el despliegue automático: poner `DEPLOY_CVP_AUTO` en `false` o borrar la variable.
- Quitar el permiso: `sudo rm /etc/sudoers.d/cicd-deploy-tableros-bi /usr/local/sbin/deploy-tableros-bi`.
