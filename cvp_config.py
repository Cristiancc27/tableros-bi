# -*- coding: utf-8 -*-
"""
Configuración externalizada del Tablero CVProgreso
(equivalente a un application.properties: nada de esto va dentro del código).

Orden de prioridad (gana el primero):
  1. Variables de entorno CVP_*            (Docker, servidor, CI)
  2. Archivo de propiedades .env           (por ambiente: .env.dev, .env.prod ...)
  3. config.ini (formato antiguo, solo conexión a la base)
  4. Valores por defecto

El archivo .env se busca en este orden:
  --env-file RUTA  >  variable CVP_ENV_FILE  >  .env junto a los scripts.
Formato: una línea CLAVE=valor, líneas con # son comentarios.
"""
import configparser
import os
import re
import sys
from urllib.parse import parse_qs, unquote, urlparse

BASE = os.path.dirname(os.path.abspath(__file__))

DEFECTOS = {
    "CVP_AMBIENTE": "local",
    # --- Base de datos (use CVP_DB_URL, o CVP_DB_DSN, o los campos sueltos) ---
    "CVP_DB_URL": "",
    "CVP_DB_DSN": "",
    "CVP_DB_HOST": "",
    "CVP_DB_PORT": "5432",
    "CVP_DB_NAME": "viviendacvp",
    "CVP_DB_USER": "",
    "CVP_DB_PASSWORD": "",
    "CVP_DB_SSLMODE": "",
    "CVP_DB_TIMEOUT_SEG": "15",
    "CVP_DB_STATEMENT_TIMEOUT_SEG": "120",
    # --- Aplicación web ---
    "CVP_WEB_DIR": "",  # carpeta donde viven Tablero_CVP.html y donde se escribe data.js
    # --- Reglas del programa ---
    "CVP_CONTRATOS": "2844,2846,2847,2848",
    "CVP_LOTES_NOMBRES": "2844=Bosa Lote 1;2846=Bosa Lote 2;2847=Suba Lote 1;2848=Suba Lote 2",
    "CVP_META_LOTE": "220",
    "CVP_FECHA_INICIO": "2026-06-01",
    "CVP_FECHA_FIN": "2026-12-31",
}


class ConfigError(Exception):
    pass


def _leer_env(ruta):
    vals = {}
    with open(ruta, encoding="utf-8-sig") as f:
        for n, linea in enumerate(f, 1):
            linea = linea.strip()
            if not linea or linea.startswith("#") or linea.startswith(";"):
                continue
            if "=" not in linea:
                raise ConfigError("%s línea %d: se esperaba CLAVE=valor" % (ruta, n))
            k, v = linea.split("=", 1)
            k, v = k.strip(), v.strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                v = v[1:-1]
            vals[k] = v
    return vals


def _leer_config_ini(ruta):
    cp = configparser.ConfigParser()
    cp.read(ruta, encoding="utf-8")
    if "bd" not in cp:
        return {}
    bd, out = cp["bd"], {}
    for ini, clave in (("dsn", "CVP_DB_DSN"), ("host", "CVP_DB_HOST"), ("port", "CVP_DB_PORT"),
                       ("dbname", "CVP_DB_NAME"), ("user", "CVP_DB_USER"), ("password", "CVP_DB_PASSWORD")):
        if bd.get(ini, "").strip():
            out[clave] = bd[ini].strip()
    return out


class Config:
    def __init__(self, valores, origen):
        self.v = dict(DEFECTOS)
        self.v.update({k: str(x) for k, x in valores.items() if k in DEFECTOS})
        self.origen = origen

    # ---- utilidades ----
    def _int(self, clave):
        try:
            return int(self.v[clave])
        except ValueError:
            raise ConfigError("%s debe ser un número entero (valor: %r)" % (clave, self.v[clave]))

    def _fecha(self, clave):
        import datetime as dt
        try:
            return dt.datetime.strptime(self.v[clave].strip(), "%Y-%m-%d")
        except ValueError:
            raise ConfigError("%s debe tener formato AAAA-MM-DD (valor: %r)" % (clave, self.v[clave]))

    # ---- propiedades ----
    @property
    def ambiente(self):
        return self.v["CVP_AMBIENTE"]

    @property
    def web_dir(self):
        d = self.v["CVP_WEB_DIR"].strip() or BASE
        return os.path.abspath(os.path.expanduser(d))

    @property
    def contratos(self):
        try:
            ids = [int(x) for x in re.split(r"[,\s;]+", self.v["CVP_CONTRATOS"].strip()) if x]
        except ValueError:
            raise ConfigError("CVP_CONTRATOS debe ser una lista de números separados por coma")
        if not ids:
            raise ConfigError("CVP_CONTRATOS no puede estar vacío")
        return ids

    @property
    def nombres_lotes(self):
        out = {}
        for par in re.split(r"[;\n]+", self.v["CVP_LOTES_NOMBRES"]):
            if "=" in par:
                k, n = par.split("=", 1)
                try:
                    out[int(k.strip())] = n.strip()
                except ValueError:
                    raise ConfigError("CVP_LOTES_NOMBRES: id inválido %r" % k)
        return out

    @property
    def meta_lote(self):
        return self._int("CVP_META_LOTE")

    @property
    def fecha_inicio(self):
        return self._fecha("CVP_FECHA_INICIO")

    @property
    def fecha_fin(self):
        return self._fecha("CVP_FECHA_FIN")

    @property
    def db_timeout(self):
        return self._int("CVP_DB_TIMEOUT_SEG")

    @property
    def db_statement_timeout(self):
        return self._int("CVP_DB_STATEMENT_TIMEOUT_SEG")

    def conexion(self):
        """Devuelve ('odbc', {'dsn':...}) o ('pg', {host, port, dbname, user, password, sslmode})."""
        v = self.v
        if v["CVP_DB_DSN"].strip():
            return "odbc", {"dsn": v["CVP_DB_DSN"].strip()}
        if v["CVP_DB_URL"].strip():
            u = urlparse(v["CVP_DB_URL"].strip())
            if u.scheme not in ("postgres", "postgresql"):
                raise ConfigError("CVP_DB_URL debe empezar por postgresql://")
            q = parse_qs(u.query)
            p = {"host": u.hostname or "", "port": str(u.port or 5432), "dbname": (u.path or "/").lstrip("/"),
                 "user": unquote(u.username or ""), "password": unquote(u.password or ""),
                 "sslmode": (q.get("sslmode") or [""])[0]}
        else:
            p = {"host": v["CVP_DB_HOST"], "port": v["CVP_DB_PORT"], "dbname": v["CVP_DB_NAME"],
                 "user": v["CVP_DB_USER"], "password": v["CVP_DB_PASSWORD"], "sslmode": v["CVP_DB_SSLMODE"]}
        if v["CVP_DB_SSLMODE"] and not p["sslmode"]:
            p["sslmode"] = v["CVP_DB_SSLMODE"]
        faltan = [k for k in ("host", "dbname", "user", "password") if not p[k]]
        if faltan:
            raise ConfigError("Falta configurar la base de datos: %s. Defina CVP_DB_URL, CVP_DB_DSN o CVP_DB_HOST/"
                              "CVP_DB_USER/CVP_DB_PASSWORD (variables de entorno o archivo .env)." % ", ".join(faltan))
        return "pg", p

    def resumen(self):
        """Texto seguro para el log (nunca incluye la contraseña)."""
        tipo, p = self.conexion()
        bd = ("ODBC DSN=%s" % p["dsn"]) if tipo == "odbc" else \
             ("%s@%s:%s/%s" % (p["user"], p["host"], p["port"], p["dbname"]))
        return "ambiente=%s | bd=%s | web_dir=%s | contratos=%s | origen=%s" % (
            self.ambiente, bd, self.web_dir, ",".join(map(str, self.contratos)), self.origen)


def cargar(env_file=None):
    archivo = env_file or os.environ.get("CVP_ENV_FILE") or os.path.join(BASE, ".env")
    valores, origen = {}, []
    if os.path.exists(archivo):
        valores.update(_leer_env(archivo))
        origen.append(os.path.basename(archivo))
    elif env_file or os.environ.get("CVP_ENV_FILE"):
        raise ConfigError("No existe el archivo de propiedades: %s" % archivo)
    else:
        ini = os.path.join(BASE, "config.ini")
        if os.path.exists(ini):
            valores.update(_leer_config_ini(ini))
            origen.append("config.ini")
    entorno = {k: x for k, x in os.environ.items() if k.startswith("CVP_") and k != "CVP_ENV_FILE"}
    if entorno:
        valores.update(entorno)
        origen.append("variables de entorno")
    return Config(valores, " + ".join(origen) or "valores por defecto")
