-- =====================================================================
-- Tablero CVProgreso · BASE DE PRUEBA (solo para correr en local con Docker)
-- Todos los datos son INVENTADOS: no hay CHIPs, valores, contratistas ni
-- contratos reales. Solo se crean las tablas y columnas que leen las 4
-- consultas de actualizar_datos.py (ver consultas_tablero.sql).
-- Se ejecuta una sola vez, al crearse el volumen de datos de bd-prueba.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS autenticacion;

CREATE TABLE public.tipoestadobra (
  intestadoobra     integer PRIMARY KEY,
  strdesctipoestado varchar(200) NOT NULL
);

CREATE TABLE public.obra (
  intcodigoobra     integer PRIMARY KEY,
  chip              varchar(30),
  intestadoobra     integer REFERENCES public.tipoestadobra (intestadoobra),
  boolobraterminada boolean NOT NULL DEFAULT false,
  numvaltotobra     numeric(18,2),
  numvalejecobra    numeric(18,2),
  strbarrio         varchar(100),
  datefeciniobra    timestamp,
  datefecfinobra    timestamp
);

CREATE TABLE public.contrato (
  intidcontrato      integer PRIMARY KEY,
  strnumcontrato     varchar(30),
  numvlrcontrato     numeric(18,2)
);

CREATE TABLE public.relacioncontratoobra (
  intcodigoobra   integer NOT NULL REFERENCES public.obra (intcodigoobra),
  intidcontrato   integer NOT NULL REFERENCES public.contrato (intidcontrato),
  numvalorrelacion numeric(18,2)
);

CREATE TABLE public.logestadoobra (
  intidlogestadoobra integer PRIMARY KEY,
  intcodigoobra      integer NOT NULL REFERENCES public.obra (intcodigoobra),
  intestadoobra      integer NOT NULL REFERENCES public.tipoestadobra (intestadoobra),
  datefecha          timestamp NOT NULL
);

CREATE TABLE autenticacion.contratista (
  intcodigo integer PRIMARY KEY
);

CREATE TABLE autenticacion.tercero (
  intcodigo         integer PRIMARY KEY,
  strnombrecompleto varchar(200)
);

CREATE TABLE public.contratocontratista (
  intidcontrato integer NOT NULL REFERENCES public.contrato (intidcontrato),
  intcodigo     integer NOT NULL REFERENCES autenticacion.contratista (intcodigo)
);

CREATE TABLE public.desembolso (
  id       integer PRIMARY KEY,
  fecha    timestamp NOT NULL,
  valor    numeric(18,2) NOT NULL,
  contrato integer NOT NULL REFERENCES public.contrato (intidcontrato)
);

-- ---------- Datos de mentira ----------
INSERT INTO public.tipoestadobra (intestadoobra, strdesctipoestado) VALUES
  (8, 'Diagnóstico en proceso'),
  (9, 'Diagnóstico revisión interventoría'),
  (13, 'Diagnóstico viable'),
  (12, 'Estructuración en proceso'),
  (14, 'Estructuración aprobada'),
  (15, 'Asignado'),
  (1, 'En ejecución'),
  (2, 'Ejecutado Entregado'),
  (19, 'Ejecutado con certificado de existencia');

INSERT INTO public.contrato (intidcontrato, strnumcontrato, numvlrcontrato) VALUES
  (2844, 'PRUEBA-1', 900000000),
  (2846, 'PRUEBA-2', 900000000),
  (2847, 'PRUEBA-3', 900000000),
  (2848, 'PRUEBA-4', 900000000),
  (2849, 'PRUEBA-INTERVENTORIA', 100000000);  -- no es un lote: el actualizador lo ignora

INSERT INTO autenticacion.contratista (intcodigo) VALUES (1), (2), (3);
INSERT INTO autenticacion.tercero (intcodigo, strnombrecompleto) VALUES
  (1, 'CONTRATISTA DE PRUEBA UNO'),
  (2, 'CONTRATISTA DE PRUEBA DOS'),
  (3, 'CONTRATISTA DE PRUEBA TRES');
INSERT INTO public.contratocontratista (intidcontrato, intcodigo) VALUES
  (2844, 1), (2846, 1), (2847, 2), (2848, 3);

-- Hogares: 5 por lote (900001 a 900020) + 2 casos de borde que el tablero NO debe contar:
--   900021 pertenece solo al contrato 2849 (interventoría) y 900022 no tiene contrato.
INSERT INTO public.obra (intcodigoobra, chip, intestadoobra, boolobraterminada, numvaltotobra, numvalejecobra, strbarrio, datefeciniobra, datefecfinobra) VALUES
  (900001, 'PRUEBA-0001', 19, true, 40000000, 40000000, 'BARRIO PRUEBA A', '2026-07-04', '2026-09-17'),
  (900002, 'PRUEBA-0002', 2, true, 42000000, 42000000, 'BARRIO PRUEBA B', '2026-07-08', '2026-09-21'),
  (900003, 'PRUEBA-0003', 1, false, 44000000, 22000000, 'BARRIO PRUEBA C', '2026-07-12', '2026-09-25'),
  (900004, 'PRUEBA-0004', 1, false, 46000000, 27600000, 'BARRIO PRUEBA D', '2026-07-16', '2026-09-29'),
  (900005, 'PRUEBA-0005', 15, false, 38000000, 0, 'BARRIO PRUEBA A', '2026-07-20', '2026-10-03'),
  (900006, 'PRUEBA-0006', 2, true, 40000000, 40000000, 'BARRIO PRUEBA A', '2026-07-24', '2026-10-07'),
  (900007, 'PRUEBA-0007', 1, false, 42000000, 16800000, 'BARRIO PRUEBA B', '2026-07-28', '2026-10-11'),
  (900008, 'PRUEBA-0008', 1, false, 44000000, 22000000, 'BARRIO PRUEBA C', '2026-08-01', '2026-10-15'),
  (900009, 'PRUEBA-0009', 14, false, 46000000, 0, 'BARRIO PRUEBA D', NULL, NULL),
  (900010, 'PRUEBA-0010', 13, false, 38000000, 0, 'BARRIO PRUEBA A', NULL, NULL),
  (900011, 'PRUEBA-0011', 19, true, 40000000, 40000000, 'BARRIO PRUEBA A', '2026-08-13', '2026-10-27'),
  (900012, 'PRUEBA-0012', 1, false, 42000000, 16800000, 'BARRIO PRUEBA B', '2026-08-17', '2026-10-31'),
  (900013, 'PRUEBA-0013', 15, false, 44000000, 0, 'BARRIO PRUEBA C', '2026-08-21', '2026-11-04'),
  (900014, 'PRUEBA-0014', 15, false, 46000000, 0, 'BARRIO PRUEBA D', '2026-08-25', '2026-11-08'),
  (900015, 'PRUEBA-0015', 12, false, 38000000, 0, 'BARRIO PRUEBA A', NULL, NULL),
  (900016, 'PRUEBA-0016', 2, true, 40000000, 40000000, 'BARRIO PRUEBA A', '2026-09-02', '2026-11-16'),
  (900017, 'PRUEBA-0017', 1, false, 42000000, 16800000, 'BARRIO PRUEBA B', '2026-09-06', '2026-11-20'),
  (900018, 'PRUEBA-0018', 9, false, 44000000, 0, 'BARRIO PRUEBA C', NULL, NULL),
  (900019, 'PRUEBA-0019', 8, false, 46000000, 0, 'BARRIO PRUEBA D', NULL, NULL),
  (900020, 'PRUEBA-0020', 1, false, 38000000, 7600000, 'BARRIO PRUEBA A', '2026-09-18', '2026-12-02'),
  (900021, 'PRUEBA-X001', 8, false, 40000000, 0, 'BARRIO PRUEBA X', NULL, NULL),
  (900022, 'PRUEBA-X002', 8, false, 40000000, 0, 'BARRIO PRUEBA X', NULL, NULL);

-- Relación hogar-lote. El hogar 900003 aparece también en el lote 2846 con un valor menor:
-- la consulta se queda con la relación de mayor valor (2844).
INSERT INTO public.relacioncontratoobra (intcodigoobra, intidcontrato, numvalorrelacion) VALUES
  (900001, 2844, 40000000),
  (900002, 2844, 42000000),
  (900003, 2844, 44000000),
  (900004, 2844, 46000000),
  (900005, 2844, 38000000),
  (900006, 2846, 40000000),
  (900007, 2846, 42000000),
  (900008, 2846, 44000000),
  (900009, 2846, 46000000),
  (900010, 2846, 38000000),
  (900011, 2847, 40000000),
  (900012, 2847, 42000000),
  (900013, 2847, 44000000),
  (900014, 2847, 46000000),
  (900015, 2847, 38000000),
  (900016, 2848, 40000000),
  (900017, 2848, 42000000),
  (900018, 2848, 44000000),
  (900019, 2848, 46000000),
  (900020, 2848, 38000000),
  (900021, 2849, 40000000),
  (900003, 2846, 1000000);

-- Historial de estados (cada hogar recorre el camino hasta su estado actual)
INSERT INTO public.logestadoobra (intidlogestadoobra, intcodigoobra, intestadoobra, datefecha) VALUES
  (1, 900001, 8, '2026-06-14 08:30:00'),
  (2, 900001, 9, '2026-06-18 09:30:00'),
  (3, 900001, 13, '2026-06-22 010:30:00'),
  (4, 900001, 12, '2026-06-26 011:30:00'),
  (5, 900001, 14, '2026-06-30 012:30:00'),
  (6, 900001, 15, '2026-07-04 013:30:00'),
  (7, 900001, 1, '2026-07-08 014:30:00'),
  (8, 900001, 2, '2026-07-12 015:30:00'),
  (9, 900001, 19, '2026-07-16 08:30:00'),
  (10, 900002, 8, '2026-06-18 08:30:00'),
  (11, 900002, 9, '2026-06-22 09:30:00'),
  (12, 900002, 13, '2026-06-26 010:30:00'),
  (13, 900002, 12, '2026-06-30 011:30:00'),
  (14, 900002, 14, '2026-07-04 012:30:00'),
  (15, 900002, 15, '2026-07-08 013:30:00'),
  (16, 900002, 1, '2026-07-12 014:30:00'),
  (17, 900002, 2, '2026-07-16 015:30:00'),
  (18, 900003, 8, '2026-06-22 08:30:00'),
  (19, 900003, 9, '2026-06-26 09:30:00'),
  (20, 900003, 13, '2026-06-30 010:30:00'),
  (21, 900003, 12, '2026-07-04 011:30:00'),
  (22, 900003, 14, '2026-07-08 012:30:00'),
  (23, 900003, 15, '2026-07-12 013:30:00'),
  (24, 900003, 1, '2026-07-16 014:30:00'),
  (25, 900004, 8, '2026-06-26 08:30:00'),
  (26, 900004, 9, '2026-06-30 09:30:00'),
  (27, 900004, 13, '2026-07-04 010:30:00'),
  (28, 900004, 12, '2026-07-08 011:30:00'),
  (29, 900004, 14, '2026-07-12 012:30:00'),
  (30, 900004, 15, '2026-07-16 013:30:00'),
  (31, 900004, 1, '2026-07-20 014:30:00'),
  (32, 900005, 8, '2026-06-30 08:30:00'),
  (33, 900005, 9, '2026-07-04 09:30:00'),
  (34, 900005, 13, '2026-07-08 010:30:00'),
  (35, 900005, 12, '2026-07-12 011:30:00'),
  (36, 900005, 14, '2026-07-16 012:30:00'),
  (37, 900005, 15, '2026-07-20 013:30:00'),
  (38, 900006, 8, '2026-07-04 08:30:00'),
  (39, 900006, 9, '2026-07-08 09:30:00'),
  (40, 900006, 13, '2026-07-12 010:30:00'),
  (41, 900006, 12, '2026-07-16 011:30:00'),
  (42, 900006, 14, '2026-07-20 012:30:00'),
  (43, 900006, 15, '2026-07-24 013:30:00'),
  (44, 900006, 1, '2026-07-28 014:30:00'),
  (45, 900006, 2, '2026-08-01 015:30:00'),
  (46, 900007, 8, '2026-07-08 08:30:00'),
  (47, 900007, 9, '2026-07-12 09:30:00'),
  (48, 900007, 13, '2026-07-16 010:30:00'),
  (49, 900007, 12, '2026-07-20 011:30:00'),
  (50, 900007, 14, '2026-07-24 012:30:00'),
  (51, 900007, 15, '2026-07-28 013:30:00'),
  (52, 900007, 1, '2026-08-01 014:30:00'),
  (53, 900008, 8, '2026-07-12 08:30:00'),
  (54, 900008, 9, '2026-07-16 09:30:00'),
  (55, 900008, 13, '2026-07-20 010:30:00'),
  (56, 900008, 12, '2026-07-24 011:30:00'),
  (57, 900008, 14, '2026-07-28 012:30:00'),
  (58, 900008, 15, '2026-08-01 013:30:00'),
  (59, 900008, 1, '2026-08-05 014:30:00'),
  (60, 900009, 8, '2026-07-16 08:30:00'),
  (61, 900009, 9, '2026-07-20 09:30:00'),
  (62, 900009, 13, '2026-07-24 010:30:00'),
  (63, 900009, 12, '2026-07-28 011:30:00'),
  (64, 900009, 14, '2026-08-01 012:30:00'),
  (65, 900010, 8, '2026-07-20 08:30:00'),
  (66, 900010, 9, '2026-07-24 09:30:00'),
  (67, 900010, 13, '2026-07-28 010:30:00'),
  (68, 900011, 8, '2026-07-24 08:30:00'),
  (69, 900011, 9, '2026-07-28 09:30:00'),
  (70, 900011, 13, '2026-08-01 010:30:00'),
  (71, 900011, 12, '2026-08-05 011:30:00'),
  (72, 900011, 14, '2026-08-09 012:30:00'),
  (73, 900011, 15, '2026-08-13 013:30:00'),
  (74, 900011, 1, '2026-08-17 014:30:00'),
  (75, 900011, 2, '2026-08-21 015:30:00'),
  (76, 900011, 19, '2026-08-25 08:30:00'),
  (77, 900012, 8, '2026-07-28 08:30:00'),
  (78, 900012, 9, '2026-08-01 09:30:00'),
  (79, 900012, 13, '2026-08-05 010:30:00'),
  (80, 900012, 12, '2026-08-09 011:30:00'),
  (81, 900012, 14, '2026-08-13 012:30:00'),
  (82, 900012, 15, '2026-08-17 013:30:00'),
  (83, 900012, 1, '2026-08-21 014:30:00'),
  (84, 900013, 8, '2026-08-01 08:30:00'),
  (85, 900013, 9, '2026-08-05 09:30:00'),
  (86, 900013, 13, '2026-08-09 010:30:00'),
  (87, 900013, 12, '2026-08-13 011:30:00'),
  (88, 900013, 14, '2026-08-17 012:30:00'),
  (89, 900013, 15, '2026-08-21 013:30:00'),
  (90, 900014, 8, '2026-08-05 08:30:00'),
  (91, 900014, 9, '2026-08-09 09:30:00'),
  (92, 900014, 13, '2026-08-13 010:30:00'),
  (93, 900014, 12, '2026-08-17 011:30:00'),
  (94, 900014, 14, '2026-08-21 012:30:00'),
  (95, 900014, 15, '2026-08-25 013:30:00'),
  (96, 900015, 8, '2026-08-09 08:30:00'),
  (97, 900015, 9, '2026-08-13 09:30:00'),
  (98, 900015, 13, '2026-08-17 010:30:00'),
  (99, 900015, 12, '2026-08-21 011:30:00'),
  (100, 900016, 8, '2026-08-13 08:30:00'),
  (101, 900016, 9, '2026-08-17 09:30:00'),
  (102, 900016, 13, '2026-08-21 010:30:00'),
  (103, 900016, 12, '2026-08-25 011:30:00'),
  (104, 900016, 14, '2026-08-29 012:30:00'),
  (105, 900016, 15, '2026-09-02 013:30:00'),
  (106, 900016, 1, '2026-09-06 014:30:00'),
  (107, 900016, 2, '2026-09-10 015:30:00'),
  (108, 900017, 8, '2026-08-17 08:30:00'),
  (109, 900017, 9, '2026-08-21 09:30:00'),
  (110, 900017, 13, '2026-08-25 010:30:00'),
  (111, 900017, 12, '2026-08-29 011:30:00'),
  (112, 900017, 14, '2026-09-02 012:30:00'),
  (113, 900017, 15, '2026-09-06 013:30:00'),
  (114, 900017, 1, '2026-09-10 014:30:00'),
  (115, 900018, 8, '2026-08-21 08:30:00'),
  (116, 900018, 9, '2026-08-25 09:30:00'),
  (117, 900019, 8, '2026-08-25 08:30:00'),
  (118, 900020, 8, '2026-08-29 08:30:00'),
  (119, 900020, 9, '2026-09-02 09:30:00'),
  (120, 900020, 13, '2026-09-06 010:30:00'),
  (121, 900020, 12, '2026-09-10 011:30:00'),
  (122, 900020, 14, '2026-09-14 012:30:00'),
  (123, 900020, 15, '2026-09-18 013:30:00'),
  (124, 900020, 1, '2026-09-22 014:30:00'),
  (125, 900021, 8, '2026-07-01 09:00:00');

-- Pagos (el del contrato 2849 no debe aparecer en el tablero)
INSERT INTO public.desembolso (id, fecha, valor, contrato) VALUES
  (1, '2026-07-15 10:00:00', 120000000, 2844),
  (2, '2026-08-20 10:00:00', 95000000, 2844),
  (3, '2026-07-30 10:00:00', 110000000, 2846),
  (4, '2026-09-10 10:00:00', 60000000, 2846),
  (5, '2026-08-05 10:00:00', 130000000, 2847),
  (6, '2026-09-25 10:00:00', 70000000, 2847),
  (7, '2026-08-28 10:00:00', 90000000, 2848),
  (8, '2026-08-28 10:00:00', 15000000, 2849);

-- ---------- Usuario de solo lectura ----------
-- Misma idea que el bloque "Usuario de solo lectura" de consultas_tablero.sql,
-- pero sobre las tablas que lee el actualizador. La clave es de PRUEBA, no es real.
CREATE ROLE tablero_ro LOGIN PASSWORD 'clave_de_prueba_no_real';
GRANT CONNECT ON DATABASE viviendacvp TO tablero_ro;
GRANT USAGE ON SCHEMA public, autenticacion TO tablero_ro;
GRANT SELECT ON public.obra, public.tipoestadobra, public.relacioncontratoobra,
                public.logestadoobra, public.contrato, public.contratocontratista,
                public.desembolso, autenticacion.contratista, autenticacion.tercero
  TO tablero_ro;
