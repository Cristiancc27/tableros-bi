-- =====================================================================
-- Tablero de Seguimiento CVProgreso · Mejora tu Casa  (versión HTML)
-- Consultas de origen. Son las MISMAS del tablero de Power BI (modelo
-- semántico TABLERO CVP), para que las cifras coincidan.
-- Base: viviendacvp (Postgres). Contratos de los 4 lotes:
--   2844 = 1-2026 Bosa Lote 1 | 2846 = 2-2026 Bosa Lote 2
--   2847 = 3-2026 Suba Lote 1 | 2848 = 4-2026 Suba Lote 2
-- (el 2849 / 5-2026 es de interventoría y NO es un lote del tablero)
-- Cada consulta alimenta un endpoint JSON; los alias en comillas dobles
-- son los nombres de campo que lee el HTML.
-- =====================================================================

-- ---------- GET /hogares ----------
SELECT
  o.intcodigoobra AS "HogarID",
  o.chip          AS "CHIP",
  rc.intidcontrato AS "LoteID",
  o.intestadoobra AS "EstadoActualID",
  te.strdesctipoestado AS "EstadoActual",
  CASE WHEN o.boolobraterminada THEN 1 ELSE 0 END AS "Terminado",
  o.numvaltotobra AS "ValorViviendaContrato",
  o.numvalejecobra AS "ValorEjecutadoObra",
  o.strbarrio     AS "Barrio",
  o.datefeciniobra AS "FechaInicioObra",
  o.datefecfinobra AS "FechaFinObra"
FROM public.obra o
LEFT JOIN public.tipoestadobra te ON te.intestadoobra = o.intestadoobra
LEFT JOIN LATERAL (
  SELECT r.intidcontrato
  FROM public.relacioncontratoobra r
  WHERE r.intcodigoobra = o.intcodigoobra
    AND r.intidcontrato IN (2844,2846,2847,2848)
  ORDER BY r.numvalorrelacion DESC NULLS LAST
  LIMIT 1
) rc ON true
WHERE rc.intidcontrato IS NOT NULL;

-- ---------- GET /historial ----------
SELECT
  l.intidlogestadoobra AS "HistorialID",
  l.intcodigoobra      AS "HogarID",
  l.intestadoobra      AS "EstadoID",
  te.strdesctipoestado AS "EstadoNombre",
  l.datefecha          AS "FechaCambio"
FROM public.logestadoobra l
LEFT JOIN public.tipoestadobra te ON te.intestadoobra = l.intestadoobra;

-- ---------- GET /lotes ----------
SELECT
  c.intidcontrato AS "LoteID",
  CASE c.intidcontrato
    WHEN 2844 THEN 'Bosa Lote 1' WHEN 2846 THEN 'Bosa Lote 2'
    WHEN 2847 THEN 'Suba Lote 1' WHEN 2848 THEN 'Suba Lote 2'
  END AS "NombreLote",
  c.strnumcontrato AS "NumContrato",
  c.numvlrcontrato AS "ValorTotalContrato",
  220              AS "MetaHogares",
  t.strnombrecompleto AS "Contratista"
FROM public.contrato c
LEFT JOIN public.contratocontratista cc ON cc.intidcontrato = c.intidcontrato
LEFT JOIN autenticacion.contratista ac ON ac.intcodigo = cc.intcodigo
LEFT JOIN autenticacion.tercero t ON t.intcodigo = ac.intcodigo
WHERE c.intidcontrato IN (2844,2846,2847,2848);

-- ---------- GET /pagos ----------
SELECT
  d.id       AS "PagoID",
  d.fecha    AS "Fecha",
  d.valor    AS "Valor",
  d.contrato AS "LoteID"
FROM public.desembolso d
WHERE d.contrato IN (2844,2846,2847,2848);

-- ---------- GET /parametros  (una sola fila) ----------
SELECT
  DATE '2026-06-01' AS "FechaInicioProyecto",
  DATE '2026-12-31' AS "FechaFinProyecto",
  (now() AT TIME ZONE 'America/Bogota') AS "FechaActualizacion";

-- =====================================================================
-- OPCIONAL · Actualización diaria desde la propia base
-- Si prefieres no consultar las tablas operativas en cada visita:
-- crear una vista materializada por consulta (esquema "tablero") y
-- apuntar los endpoints a ellas. Ejemplo para /hogares:
--
--   CREATE SCHEMA IF NOT EXISTS tablero;
--   CREATE MATERIALIZED VIEW tablero.hogares AS <consulta de /hogares>;
--
-- Refresco diario (requiere la extensión pg_cron; si no, usar cron del
-- servidor con psql):
--   SELECT cron.schedule('tablero-cvp', '0 5 * * *',
--     $$REFRESH MATERIALIZED VIEW tablero.hogares$$);
--
-- Usuario de solo lectura para el servicio del tablero:
--   CREATE ROLE tablero_ro LOGIN PASSWORD '<definir>';
--   GRANT USAGE ON SCHEMA tablero TO tablero_ro;
--   GRANT SELECT ON ALL TABLES IN SCHEMA tablero TO tablero_ro;
-- =====================================================================
