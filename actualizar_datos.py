#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Tablero CVProgreso (HTML) - Actualizador de datos
-------------------------------------------------
Lee la base viviendacvp (Postgres) con las MISMAS consultas del tablero de
Power BI y genera `data.js` en la carpeta de la aplicación web.
Es de SOLO LECTURA: no escribe nada en la base.

Toda la configuración (conexión a la base, carpeta web, contratos, fechas...)
se externaliza en variables de entorno CVP_* o en un archivo .env por ambiente.
Ver .env.example y cvp_config.py.

Uso:
    pip install psycopg2-binary          (o pyodbc si usa CVP_DB_DSN)
    python actualizar_datos.py [--env-file .env.prod]
"""
import argparse
import datetime as dt
import decimal
import json
import os
import sys

import cvp_config

BOGOTA = dt.timezone(dt.timedelta(hours=-5))


def consultas(ids):
    """Mismas consultas del modelo de Power BI. `ids` son enteros validados (sin riesgo de inyección)."""
    lista = ",".join(str(int(i)) for i in ids)
    return {
        "hogares": """
            SELECT
              o.intcodigoobra AS "HogarID",
              o.chip AS "CHIP",
              rc.intidcontrato AS "LoteID",
              o.intestadoobra AS "EstadoActualID",
              te.strdesctipoestado AS "EstadoActual",
              CASE WHEN o.boolobraterminada THEN 1 ELSE 0 END AS "Terminado",
              o.numvaltotobra AS "ValorViviendaContrato",
              o.numvalejecobra AS "ValorEjecutadoObra",
              o.strbarrio AS "Barrio",
              o.datefeciniobra AS "FechaInicioObra",
              o.datefecfinobra AS "FechaFinObra"
            FROM public.obra o
            LEFT JOIN public.tipoestadobra te ON te.intestadoobra = o.intestadoobra
            LEFT JOIN LATERAL (
              SELECT r.intidcontrato
              FROM public.relacioncontratoobra r
              WHERE r.intcodigoobra = o.intcodigoobra
                AND r.intidcontrato IN (%s)
              ORDER BY r.numvalorrelacion DESC NULLS LAST
              LIMIT 1
            ) rc ON true
            WHERE rc.intidcontrato IS NOT NULL
        """ % lista,
        "historial": """
            SELECT
              l.intidlogestadoobra AS "HistorialID",
              l.intcodigoobra AS "HogarID",
              l.intestadoobra AS "EstadoID",
              te.strdesctipoestado AS "EstadoNombre",
              l.datefecha AS "FechaCambio"
            FROM public.logestadoobra l
            LEFT JOIN public.tipoestadobra te ON te.intestadoobra = l.intestadoobra
        """,
        "lotes": """
            SELECT
              c.intidcontrato AS "LoteID",
              c.strnumcontrato AS "NumContrato",
              c.numvlrcontrato AS "ValorTotalContrato",
              t.strnombrecompleto AS "Contratista"
            FROM public.contrato c
            LEFT JOIN public.contratocontratista cc ON cc.intidcontrato = c.intidcontrato
            LEFT JOIN autenticacion.contratista ac ON ac.intcodigo = cc.intcodigo
            LEFT JOIN autenticacion.tercero t ON t.intcodigo = ac.intcodigo
            WHERE c.intidcontrato IN (%s)
        """ % lista,
        "pagos": """
            SELECT
              d.id AS "PagoID",
              d.fecha AS "Fecha",
              d.valor AS "Valor",
              d.contrato AS "LoteID"
            FROM public.desembolso d
            WHERE d.contrato IN (%s)
        """ % lista,
    }


def conectar(cfg):
    """Abre conexión de solo lectura (psycopg2, o pyodbc si se define CVP_DB_DSN)."""
    tipo, p = cfg.conexion()
    if tipo == "odbc":
        import pyodbc  # pip install pyodbc
        return pyodbc.connect("DSN=" + p["dsn"], autocommit=True)
    import psycopg2  # pip install psycopg2-binary
    kw = dict(host=p["host"], port=p["port"], dbname=p["dbname"], user=p["user"], password=p["password"],
              connect_timeout=cfg.db_timeout,
              options="-c default_transaction_read_only=on -c statement_timeout=%d" % (cfg.db_statement_timeout * 1000))
    if p.get("sslmode"):
        kw["sslmode"] = p["sslmode"]
    cx = psycopg2.connect(**kw)
    cx.autocommit = True
    return cx


def consultar(cx, sql):
    cur = cx.cursor()
    cur.execute(sql)
    cols = [d[0] for d in cur.description]
    filas = [dict(zip(cols, r)) for r in cur.fetchall()]
    cur.close()
    return filas


def a_json(o):
    """Fechas -> texto ISO SIN zona (el HTML las lee como hora local)."""
    if isinstance(o, dt.datetime):
        if o.tzinfo is not None:
            o = o.astimezone(BOGOTA).replace(tzinfo=None)
        return o.replace(microsecond=0).isoformat()  # sin timespec: compatible con Python 3.5
    if isinstance(o, dt.date):
        return o.isoformat() + "T00:00:00"
    if isinstance(o, decimal.Decimal):
        return float(o)
    if isinstance(o, (bytes, bytearray, memoryview)):
        return bytes(o).decode("utf-8", "replace")
    raise TypeError("No serializable: %r" % type(o))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--env-file", help="archivo de propiedades del ambiente (por defecto .env)")
    a = ap.parse_args()

    try:
        cfg = cvp_config.cargar(a.env_file)
        print("Configuración:", cfg.resumen())
        sqls = consultas(cfg.contratos)
        nombres, meta = cfg.nombres_lotes, cfg.meta_lote
        f_ini, f_fin = cfg.fecha_inicio, cfg.fecha_fin
        salida = os.path.join(cfg.web_dir, "data.js")
        os.makedirs(cfg.web_dir, exist_ok=True)
    except cvp_config.ConfigError as e:
        sys.exit("ERROR de configuración: %s" % e)

    print("Conectando a la base...")
    cx = conectar(cfg)
    datos = {}
    try:
        for nombre, sql in sqls.items():
            datos[nombre] = consultar(cx, sql)
            print("  %-10s %6d filas" % (nombre, len(datos[nombre])))
    finally:
        cx.close()

    # Nombre del lote y meta vienen de la configuración (no de la base)
    for r in datos["lotes"]:
        r["NombreLote"] = nombres.get(r["LoteID"], "Lote %s" % r["LoteID"])
        r["MetaHogares"] = meta

    if not datos["hogares"]:
        sys.exit("ERROR: la consulta de hogares no devolvió filas. No se actualiza data.js.")
    por_lote = {}
    for h in datos["hogares"]:
        por_lote[h["LoteID"]] = por_lote.get(h["LoteID"], 0) + 1
    print("  hogares por lote:", dict(sorted(por_lote.items())))

    datos["parametros"] = {
        "FechaInicioProyecto": f_ini,
        "FechaFinProyecto": f_fin,
        "FechaActualizacion": dt.datetime.now(BOGOTA).replace(tzinfo=None, microsecond=0),
    }

    contenido = "window.CVP_DATA = " + json.dumps(datos, default=a_json, ensure_ascii=False) + ";\n"
    tmp = salida + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(contenido)
    os.replace(tmp, salida)  # reemplazo atómico: nunca queda un data.js a medias
    print("Listo: %s (%d KB)" % (salida, len(contenido) // 1024))


if __name__ == "__main__":
    main()
