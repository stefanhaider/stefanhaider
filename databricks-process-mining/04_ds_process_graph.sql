-- =====================================================================
-- Dataset "process_graph" – Soll-Ist-Prozessgraph eines Prozesses (Custom Viz)
--
-- Parameter: :process (z. B. 'Access Request'), :domain ('Alle' = kein Filter)
--
-- Vega-Lite kann Graphen nicht anordnen, daher berechnet diese Abfrage das Layout.
-- Zeilentypen (row_type):
--   node  : Aktivität (Mittelpunkt x/y, Breite w, Höhe h, is_control)
--   edge  : Stützpunkte einer Kante (Reihenfolge seq)
--   arrow : Pfeilspitze (shape = Richtung)
--   label : Position der Zahl auf der Kante
--   frame : zwei unsichtbare Eckpunkte (0,0) und (800, Höhe) – legen den Zeichenbereich fest
-- conformance: 'soll' | 'abweichung' | 'kontrolle_umgangen' | 'latent'
--   latent = vom System (aktuelles Release) erlaubt, nicht im Soll-Prozess, aber noch nie genutzt
-- system_status: 'vom System erlaubt' | 'außerhalb des Workflows' | 'erlaubt, ungenutzt'
-- Positionen kommen aus process_graph_layout (02_process_model.sql).
-- =====================================================================
WITH t AS (
  SELECT * FROM main.data_manager_pm.v_transitions
  WHERE process = :process AND (:domain = 'Alle' OR domain = :domain)
),
observed AS (
  SELECT src, tgt, COUNT(*) AS cases, MEDIAN(wait_h) AS median_wait_h,
         MAX(finding_type) AS finding_type,
         CASE WHEN BOOL_OR(is_allowed) THEN 'soll'
              WHEN MAX(finding_type) = 'Kontrolle umgangen' THEN 'kontrolle_umgangen'
              ELSE 'abweichung' END AS conformance,
         IF(BOOL_AND(is_system_allowed), 'vom System erlaubt', 'außerhalb des Workflows') AS system_status
  FROM t GROUP BY src, tgt
),
latent AS (   -- vom System erlaubt, nicht im Soll, noch nie genutzt
  SELECT sa.src, sa.tgt, CAST(0 AS BIGINT) AS cases, CAST(NULL AS DOUBLE) AS median_wait_h,
         c.finding_type, 'latent' AS conformance, 'erlaubt, ungenutzt' AS system_status
  FROM main.data_manager_pm.system_allowed_transitions sa
  JOIN main.data_manager_pm.v_transition_classes c
    ON c.process = sa.process AND c.src = sa.src AND c.tgt = sa.tgt AND NOT c.is_allowed
  LEFT ANTI JOIN observed o ON o.src = sa.src AND o.tgt = sa.tgt
  WHERE sa.process = :process AND sa.valid_to IS NULL
),
trans AS (
  SELECT * FROM observed UNION ALL SELECT * FROM latent
),
node_counts AS (
  SELECT tgt AS activity, COUNT(*) AS cases FROM t WHERE tgt <> '■ Ende' GROUP BY tgt
  UNION ALL SELECT '▶ Start', COUNT(DISTINCT case_id) FROM t
  UNION ALL SELECT '■ Ende',  COUNT(DISTINCT case_id) FROM t
),
nodes AS (
  SELECT
    n.activity, n.cases,
    COALESCE(l.x, 740D) AS x,
    COALESCE(l.y, 60D + 80D * (ROW_NUMBER() OVER (PARTITION BY l.activity IS NULL ORDER BY n.activity) - 1)) AS y,
    IF(n.activity IN ('▶ Start', '■ Ende'), 28D, 180D) AS w,
    IF(n.activity IN ('▶ Start', '■ Ende'), 28D,  44D) AS h,
    CASE n.activity WHEN '▶ Start' THEN 'start' WHEN '■ Ende' THEN 'end' ELSE 'activity' END AS node_kind,
    IF(ma.activity IS NULL, 'abweichung', 'soll') AS conformance,
    CAST(COALESCE(ma.is_control, false) AS INT) AS is_control
  FROM node_counts n
  LEFT JOIN main.data_manager_pm.process_graph_layout l ON l.process = :process AND l.activity = n.activity
  LEFT JOIN main.data_manager_pm.process_model_activities ma ON ma.process = :process AND ma.activity = n.activity
),
-- senkrechte Kanten, die durch einen anderen Kasten laufen würden (übersprungene Schritte)
blocked AS (
  SELECT DISTINCT tr.src, tr.tgt
  FROM trans tr
  JOIN nodes s ON s.activity = tr.src
  JOIN nodes g ON g.activity = tr.tgt
  JOIN nodes b ON abs(b.x - s.x) < s.w / 2 AND b.y > s.y AND b.y < g.y
  WHERE g.y > s.y AND abs(g.x - s.x) < s.w / 2
),
e AS (
  SELECT tr.*,
         s.x AS x0, s.y AS y0, s.w AS w0, s.h AS h0,
         g.x AS x1, g.y AS y1, g.w AS w1, g.h AS h1,
         CASE
           WHEN tr.src = tr.tgt                          THEN 'self'
           WHEN tr.tgt = '■ Ende' AND g.x <> s.x         THEN 'down_across'
           WHEN bl.src IS NOT NULL                       THEN 'skip'
           WHEN g.y > s.y AND abs(g.x - s.x) < s.w / 2   THEN 'straight'
           WHEN g.y > s.y                                THEN 'side_down'
           WHEN g.y = s.y                                THEN 'same_row'
           ELSE 'back'
         END AS etype
  FROM trans tr
  JOIN nodes s ON s.activity = tr.src
  JOIN nodes g ON g.activity = tr.tgt
  LEFT JOIN blocked bl ON bl.src = tr.src AND bl.tgt = tr.tgt
),
-- Eingänge oben am Ziel verteilen: Skip-Spuren ganz links (äußere zuerst), dann von links,
-- senkrecht, von rechts – so kreuzen sich die Linien nicht.
top_in AS (
  SELECT src, tgt,
         ROW_NUMBER() OVER (PARTITION BY tgt ORDER BY grp, IF(grp = 0, -y0, y0), x0) - 1 AS r,
         COUNT(*)     OVER (PARTITION BY tgt) AS n
  FROM (SELECT *, CASE WHEN etype = 'skip' THEN -1 WHEN etype = 'straight' THEN 1 WHEN x0 < x1 THEN 0 ELSE 2 END AS grp
        FROM e WHERE etype IN ('straight', 'side_down', 'skip'))
),
side_out AS (
  SELECT src, tgt,
         ROW_NUMBER() OVER (PARTITION BY src, sign(x1 - x0) ORDER BY abs(x1 - x0) DESC) - 1 AS r,
         COUNT(*)     OVER (PARTITION BY src, sign(x1 - x0)) AS n
  FROM e WHERE etype = 'side_down'
),
end_in AS (
  SELECT src, tgt,
         ROW_NUMBER() OVER (PARTITION BY tgt ORDER BY abs(x1 - x0) DESC) - 1 AS r,
         COUNT(*)     OVER (PARTITION BY tgt) AS n
  FROM e WHERE etype = 'down_across'
),
back_lane AS (
  SELECT src, tgt, ROW_NUMBER() OVER (ORDER BY y0 - y1, src) - 1 AS r FROM e WHERE etype = 'back'
),
skip_lane AS (   -- r: globale Spur (kürzere Sprünge innen); rt: je Ziel (äußere Spur biegt tiefer ein)
  SELECT src, tgt,
         ROW_NUMBER() OVER (ORDER BY y1 - y0, src) - 1 AS r,
         ROW_NUMBER() OVER (PARTITION BY tgt ORDER BY y1 - y0 DESC, src) - 1 AS rt
  FROM e WHERE etype = 'skip'
),
routed AS (
  SELECT e.*,
    x1 + IF(ti.n > 1, -least(w1 / 2 - 20, 25 * (ti.n - 1)) + 2 * least(w1 / 2 - 20, 25 * (ti.n - 1)) * ti.r / (ti.n - 1), 0) AS entry_x,
    y0 + IF(so.n > 1, -least(h0 / 2 - 8, 8 * (so.n - 1)) + 2 * least(h0 / 2 - 8, 8 * (so.n - 1)) * so.r / (so.n - 1), 0) AS exit_y,
    y1 + IF(ei.n > 1, 5 - 10 * ei.r / (ei.n - 1), 0) AS end_y,
    greatest(x0 + w0 / 2, x1 + w1 / 2) + 25 + 14 * COALESCE(bl.r, 0) AS lane_x,
    least(x0 - w0 / 2, x1 - w1 / 2) - 25 - 14 * COALESCE(sl.r, 0)    AS skip_x,
    y1 - h1 / 2 - 10 - 8 * COALESCE(sl.rt, 0)                         AS skip_y
  FROM e
  LEFT JOIN top_in    ti USING (src, tgt)
  LEFT JOIN side_out  so USING (src, tgt)
  LEFT JOIN end_in    ei USING (src, tgt)
  LEFT JOIN back_lane bl USING (src, tgt)
  LEFT JOIN skip_lane sl USING (src, tgt)
),
geom AS (
  SELECT src, tgt, cases, median_wait_h, conformance, finding_type, system_status,
    CASE etype
      WHEN 'straight' THEN array(named_struct('x', entry_x, 'y', y0 + h0 / 2), named_struct('x', entry_x, 'y', y1 - h1 / 2))
      WHEN 'side_down' THEN array(
        named_struct('x', x0 + sign(x1 - x0) * w0 / 2, 'y', exit_y),
        named_struct('x', entry_x, 'y', exit_y),
        named_struct('x', entry_x, 'y', y1 - h1 / 2))
      WHEN 'skip' THEN array(       -- links an den übersprungenen Kästen vorbei, oben ins Ziel
        named_struct('x', x0 - w0 / 2, 'y', y0),
        named_struct('x', skip_x, 'y', y0),
        named_struct('x', skip_x, 'y', skip_y),
        named_struct('x', entry_x, 'y', skip_y),
        named_struct('x', entry_x, 'y', y1 - h1 / 2))
      WHEN 'down_across' THEN array( -- am äußeren Rand der Quelle nach unten, dann seitlich ins Ende
        named_struct('x', x0 + sign(x0 - x1) * (w0 / 2 - 8), 'y', y0 + h0 / 2),
        named_struct('x', x0 + sign(x0 - x1) * (w0 / 2 - 8), 'y', end_y),
        named_struct('x', x1 - sign(x1 - x0) * w1 / 2, 'y', end_y))
      WHEN 'same_row' THEN array(
        named_struct('x', x0 + sign(x1 - x0) * w0 / 2, 'y', y0 + IF(x1 > x0, -11D, 11D)),
        named_struct('x', x1 - sign(x1 - x0) * w1 / 2, 'y', y0 + IF(x1 > x0, -11D, 11D)))
      WHEN 'back' THEN array(        -- rechts hoch; Aus- und Eingang leicht versetzt
        named_struct('x', x0 + w0 / 2, 'y', y0 - 8),
        named_struct('x', lane_x, 'y', y0 - 8),
        named_struct('x', lane_x, 'y', y1 + 8),
        named_struct('x', x1 + w1 / 2, 'y', y1 + 8))
      ELSE array(                    -- Selbstschleife oben rechts
        named_struct('x', x0 + w0 / 2 - 24, 'y', y0 - h0 / 2),
        named_struct('x', x0 + w0 / 2 - 24, 'y', y0 - h0 / 2 - 12),
        named_struct('x', x0 + w0 / 2 + 14, 'y', y0 - h0 / 2 - 12),
        named_struct('x', x0 + w0 / 2 + 14, 'y', y0 - h0 / 4),
        named_struct('x', x0 + w0 / 2,      'y', y0 - h0 / 4))
    END AS pts,
    CASE etype
      WHEN 'straight'    THEN named_struct('x', entry_x, 'y', (y0 + h0 / 2 + y1 - h1 / 2) / 2)
      WHEN 'side_down'   THEN named_struct('x', entry_x, 'y', (exit_y + y1 - h1 / 2) / 2)
      WHEN 'skip'        THEN named_struct('x', skip_x, 'y', (y0 + skip_y) / 2)
      WHEN 'down_across' THEN named_struct('x', x0 + sign(x0 - x1) * (w0 / 2 - 8), 'y', (y0 + h0 / 2 + end_y) / 2)
      WHEN 'same_row'    THEN named_struct('x', (x0 + x1) / 2, 'y', y0 + IF(x1 > x0, -11D, 11D))
      WHEN 'back'        THEN named_struct('x', lane_x, 'y', (y0 + y1) / 2)
      ELSE named_struct('x', x0 + w0 / 2 + 14, 'y', y0 - h0 / 2 - 12)
    END AS lbl,
    CASE
      WHEN etype IN ('straight', 'side_down', 'skip') THEN 'triangle-down'
      WHEN etype IN ('back', 'self')                  THEN 'triangle-left'
      WHEN x1 > x0                                    THEN 'triangle-right'
      ELSE 'triangle-left'
    END AS arrow_shape
  FROM routed
)
SELECT 'node' AS row_type, activity AS id, CAST(NULL AS STRING) AS src, CAST(NULL AS STRING) AS tgt,
       cases, CAST(NULL AS DOUBLE) AS median_wait_h, x, y, w, h, CAST(NULL AS INT) AS seq,
       CAST(NULL AS STRING) AS shape, node_kind, conformance, is_control, CAST(NULL AS STRING) AS finding_type,
       CAST(NULL AS STRING) AS system_status
FROM nodes
UNION ALL
SELECT 'edge', concat(src, ' → ', tgt), src, tgt, cases, median_wait_h, p.x, p.y, NULL, NULL, i, NULL, NULL, conformance, NULL, finding_type, system_status
FROM geom LATERAL VIEW posexplode(pts) AS i, p
UNION ALL   -- Pfeilspitze 5 Einheiten vor dem Endpunkt
SELECT 'arrow', concat(src, ' → ', tgt), src, tgt, cases, median_wait_h,
       element_at(pts, -1).x + CASE arrow_shape WHEN 'triangle-right' THEN -5 WHEN 'triangle-left' THEN 5 ELSE 0 END,
       element_at(pts, -1).y + IF(arrow_shape = 'triangle-down', -5, 0),
       NULL, NULL, NULL, arrow_shape, NULL, conformance, NULL, finding_type, system_status
FROM geom
UNION ALL
SELECT 'label', concat(src, ' → ', tgt), src, tgt, cases, median_wait_h, lbl.x, lbl.y, NULL, NULL, NULL, NULL, NULL, conformance, NULL, finding_type, system_status
FROM geom
UNION ALL   -- Zeichenbereich: 800 breit, Höhe = tiefster Knoten + 40
SELECT 'frame', 'frame', NULL, NULL, NULL, NULL, fx, fy, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM (SELECT MAX(y + h / 2) + 22 AS max_y FROM nodes)
LATERAL VIEW inline(array(named_struct('fx', 0D, 'fy', 0D), named_struct('fx', 800D, 'fy', max_y))) f AS fx, fy;
