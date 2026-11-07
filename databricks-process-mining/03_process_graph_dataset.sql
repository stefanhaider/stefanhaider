-- =====================================================================
-- Dataset für den Prozessgraphen (Custom Visualization / Vega-Lite)
--
-- Vega-Lite kann Graphen nicht automatisch anordnen. Deshalb berechnet
-- diese Abfrage das komplette Layout:
--   row_type = 'node'  : Aktivität (Mittelpunkt x/y, Breite w, Höhe h)
--   row_type = 'edge'  : Stützpunkte einer Kante (Reihenfolge = seq)
--   row_type = 'arrow' : Pfeilspitze am Kantenende (shape = Richtung)
--   row_type = 'label' : Position der Zahl auf der Kante
-- conformance = 'soll' (laut Soll-Prozess erlaubt) oder 'abweichung'
-- (Übergang bzw. Aktivität nicht im Soll-Prozess, siehe 02_process_model.sql)
--
-- Anpassen: nur die CTE `layout` (feste Position je Aktivität). Tipp: den
-- Standardprozess senkrecht in die Mitte legen, Abweichungen seitlich daneben.
-- Unbekannte Aktivitäten landen automatisch in einer Spalte rechts.
-- Optionaler Dashboard-Parameter :region ('Alle' = kein Filter).
-- =====================================================================
WITH ev AS (
  SELECT case_id, activity, event_ts, step_no
  FROM main.process_mining.event_log
  WHERE :region = 'Alle' OR region = :region
),
seq AS (
  SELECT
    case_id, activity, event_ts,
    LAG(activity)  OVER w AS prev_activity,
    LEAD(activity) OVER w AS next_activity,
    LEAD(event_ts) OVER w AS next_ts
  FROM ev
  WINDOW w AS (PARTITION BY case_id ORDER BY event_ts, step_no)
),
trans AS (
  SELECT activity AS src, COALESCE(next_activity, '■ Ende') AS tgt, COUNT(*) AS cases,
         MEDIAN(timestampdiff(MINUTE, event_ts, next_ts) / 60.0) AS median_wait_h
  FROM seq GROUP BY ALL
  UNION ALL
  SELECT '▶ Start', activity, COUNT(*), CAST(NULL AS DOUBLE)
  FROM seq WHERE prev_activity IS NULL GROUP BY activity
),
node_counts AS (
  SELECT activity, COUNT(*) AS cases FROM ev GROUP BY activity
  UNION ALL SELECT '▶ Start', COUNT(DISTINCT case_id) FROM ev
  UNION ALL SELECT '■ Ende',  COUNT(DISTINCT case_id) FROM ev
),
-- ---- Layout: Mittelpunkt je Aktivität (Koordinatensystem 800 × 700) ----
layout AS (
  SELECT * FROM VALUES
    ('▶ Start',             400D,  24D),
    ('Auftrag angelegt',    400D, 100D),
    ('Kreditprüfung',       400D, 180D),
    ('Auftrag freigegeben', 400D, 260D),
    ('Preisänderung',       150D, 260D),
    ('Lieferung',           400D, 340D),
    ('Storniert',           660D, 340D),
    ('Rechnung gestellt',   400D, 420D),
    ('Gutschrift',          170D, 500D),
    ('Mahnung',             630D, 500D),
    ('Zahlung erhalten',    400D, 580D),
    ('■ Ende',              400D, 660D)
  AS t(activity, x, y)
),
nodes AS (
  SELECT
    n.activity, n.cases,
    COALESCE(l.x, 740D) AS x,
    COALESCE(l.y, 60D + 70D * (ROW_NUMBER() OVER (PARTITION BY l.activity IS NULL ORDER BY n.activity) - 1)) AS y,
    IF(n.activity IN ('▶ Start', '■ Ende'), 28D, 180D) AS w,
    IF(n.activity IN ('▶ Start', '■ Ende'), 28D,  44D) AS h,
    CASE n.activity WHEN '▶ Start' THEN 'start' WHEN '■ Ende' THEN 'end' ELSE 'activity' END AS node_kind,
    IF(ma.activity IS NULL, 'abweichung', 'soll') AS conformance
  FROM node_counts n
  LEFT JOIN layout l USING (activity)
  LEFT JOIN main.process_mining.process_model_activities ma ON ma.activity = n.activity
),
-- Senkrechte Kanten, die durch einen anderen Kasten laufen würden (z. B. übersprungener Schritt)
blocked AS (
  SELECT DISTINCT t.src, t.tgt
  FROM trans t
  JOIN nodes s ON s.activity = t.src
  JOIN nodes g ON g.activity = t.tgt
  JOIN nodes b ON abs(b.x - s.x) < s.w / 2 AND b.y > s.y AND b.y < g.y
  WHERE g.y > s.y AND abs(g.x - s.x) < s.w / 2
),
e AS (
  SELECT t.*,
         IF(m.src IS NULL, 'abweichung', 'soll') AS conformance,
         s.x AS x0, s.y AS y0, s.w AS w0, s.h AS h0,
         g.x AS x1, g.y AS y1, g.w AS w1, g.h AS h1,
         CASE
           WHEN t.src = t.tgt                          THEN 'self'
           WHEN t.tgt = '■ Ende' AND g.x <> s.x        THEN 'down_across'
           WHEN bl.src IS NOT NULL                     THEN 'skip'
           WHEN g.y > s.y AND abs(g.x - s.x) < s.w / 2 THEN 'straight'
           WHEN g.y > s.y                              THEN 'side_down'
           WHEN g.y = s.y                              THEN 'same_row'
           ELSE 'back'
         END AS etype
  FROM trans t
  JOIN nodes s ON s.activity = t.src
  JOIN nodes g ON g.activity = t.tgt
  LEFT JOIN blocked bl ON bl.src = t.src AND bl.tgt = t.tgt
  LEFT JOIN main.process_mining.process_model_transitions m ON m.src = t.src AND m.tgt = t.tgt
),
-- Eingänge oben am Ziel verteilen (Linien von links/mittig/rechts sortiert, damit sie sich nicht kreuzen)
top_in AS (
  SELECT src, tgt,
         ROW_NUMBER() OVER (PARTITION BY tgt ORDER BY grp, IF(grp = 0, -y0, y0), x0) - 1 AS r,
         COUNT(*)     OVER (PARTITION BY tgt) AS n
  FROM (SELECT *, CASE WHEN etype = 'straight' THEN 1 WHEN etype = 'skip' OR x0 < x1 THEN 0 ELSE 2 END AS grp
        FROM e WHERE etype IN ('straight', 'side_down', 'skip'))
),
-- Seitliche Ausgänge an der Quelle verteilen (weitere Ziele steigen weiter oben aus)
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
skip_lane AS (
  SELECT src, tgt, ROW_NUMBER() OVER (ORDER BY y1 - y0, src) - 1 AS r FROM e WHERE etype = 'skip'
),
routed AS (
  SELECT e.*,
    x1 + IF(ti.n > 1, -least(w1 / 2 - 20, 25 * (ti.n - 1)) + 2 * least(w1 / 2 - 20, 25 * (ti.n - 1)) * ti.r / (ti.n - 1), 0) AS entry_x,
    y0 + IF(so.n > 1, -least(h0 / 2 - 8, 8 * (so.n - 1)) + 2 * least(h0 / 2 - 8, 8 * (so.n - 1)) * so.r / (so.n - 1), 0) AS exit_y,
    y1 + IF(ei.n > 1, 5 - 10 * ei.r / (ei.n - 1), 0) AS end_y,
    greatest(x0 + w0 / 2, x1 + w1 / 2) + 25 + 14 * COALESCE(bl.r, 0) AS lane_x,
    least(x0 - w0 / 2, x1 - w1 / 2) - 25 - 14 * COALESCE(sl.r, 0)    AS skip_x
  FROM e
  LEFT JOIN top_in    ti USING (src, tgt)
  LEFT JOIN side_out  so USING (src, tgt)
  LEFT JOIN end_in    ei USING (src, tgt)
  LEFT JOIN back_lane bl USING (src, tgt)
  LEFT JOIN skip_lane sl USING (src, tgt)
),
geom AS (
  SELECT src, tgt, cases, median_wait_h, conformance,
    CASE etype
      WHEN 'straight' THEN array(named_struct('x', entry_x, 'y', y0 + h0 / 2), named_struct('x', entry_x, 'y', y1 - h1 / 2))
      WHEN 'side_down' THEN array(
        named_struct('x', x0 + sign(x1 - x0) * w0 / 2, 'y', exit_y),
        named_struct('x', entry_x, 'y', exit_y),
        named_struct('x', entry_x, 'y', y1 - h1 / 2))
      WHEN 'skip' THEN array(  -- links an den übersprungenen Kästen vorbei, oben ins Ziel
        named_struct('x', x0 - w0 / 2, 'y', y0),
        named_struct('x', skip_x, 'y', y0),
        named_struct('x', skip_x, 'y', y1 - h1 / 2 - 12),
        named_struct('x', entry_x, 'y', y1 - h1 / 2 - 12),
        named_struct('x', entry_x, 'y', y1 - h1 / 2))
      WHEN 'down_across' THEN array(  -- am äußeren Rand des Kastens nach unten, dann seitlich ins Ende
        named_struct('x', x0 + sign(x0 - x1) * (w0 / 2 - 8), 'y', y0 + h0 / 2),
        named_struct('x', x0 + sign(x0 - x1) * (w0 / 2 - 8), 'y', end_y),
        named_struct('x', x1 - sign(x1 - x0) * w1 / 2, 'y', end_y))
      WHEN 'same_row' THEN array(
        named_struct('x', x0 + sign(x1 - x0) * w0 / 2, 'y', y0 + IF(x1 > x0, -11D, 11D)),
        named_struct('x', x1 - sign(x1 - x0) * w1 / 2, 'y', y0 + IF(x1 > x0, -11D, 11D)))
      WHEN 'back' THEN array(
        named_struct('x', x0 + w0 / 2, 'y', y0),
        named_struct('x', lane_x, 'y', y0),
        named_struct('x', lane_x, 'y', y1),
        named_struct('x', x1 + w1 / 2, 'y', y1))
      ELSE array(  -- self loop oben rechts
        named_struct('x', x0 + w0 / 2 - 24, 'y', y0 - h0 / 2),
        named_struct('x', x0 + w0 / 2 - 24, 'y', y0 - h0 / 2 - 12),
        named_struct('x', x0 + w0 / 2 + 14, 'y', y0 - h0 / 2 - 12),
        named_struct('x', x0 + w0 / 2 + 14, 'y', y0 - h0 / 4),
        named_struct('x', x0 + w0 / 2,      'y', y0 - h0 / 4))
    END AS pts,
    -- Position der Zahl: Mitte des längsten (meist senkrechten) Segments
    CASE etype
      WHEN 'straight'    THEN named_struct('x', entry_x, 'y', (y0 + h0 / 2 + y1 - h1 / 2) / 2)
      WHEN 'side_down'   THEN named_struct('x', entry_x, 'y', (exit_y + y1 - h1 / 2) / 2)
      WHEN 'skip'        THEN named_struct('x', skip_x, 'y', (y0 + y1 - h1 / 2 - 12) / 2)
      WHEN 'down_across' THEN named_struct('x', x0 + sign(x0 - x1) * (w0 / 2 - 8), 'y', (y0 + h0 / 2 + end_y) / 2)
      WHEN 'same_row'    THEN named_struct('x', (x0 + x1) / 2, 'y', y0 + IF(x1 > x0, -11D, 11D))
      WHEN 'back'        THEN named_struct('x', lane_x, 'y', (y0 + y1) / 2)
      ELSE named_struct('x', x0 + w0 / 2 + 14, 'y', y0 - h0 / 2 - 12)
    END AS lbl,
    CASE
      WHEN etype IN ('straight', 'side_down', 'skip') THEN 'triangle-down'
      WHEN etype IN ('back', 'self')          THEN 'triangle-left'
      WHEN x1 > x0                            THEN 'triangle-right'
      ELSE 'triangle-left'
    END AS arrow_shape
  FROM routed
)
SELECT 'node' AS row_type, activity AS id, CAST(NULL AS STRING) AS src, CAST(NULL AS STRING) AS tgt,
       cases, CAST(NULL AS DOUBLE) AS median_wait_h, x, y, w, h, CAST(NULL AS INT) AS seq,
       CAST(NULL AS STRING) AS shape, node_kind, conformance
FROM nodes
UNION ALL
SELECT 'edge', concat(src, ' → ', tgt), src, tgt, cases, median_wait_h, p.x, p.y, NULL, NULL, i, NULL, NULL, conformance
FROM geom LATERAL VIEW posexplode(pts) AS i, p
UNION ALL  -- Pfeilspitze 5 Einheiten vor dem Endpunkt, damit die Spitze die Box berührt
SELECT 'arrow', concat(src, ' → ', tgt), src, tgt, cases, median_wait_h,
       element_at(pts, -1).x + CASE arrow_shape WHEN 'triangle-right' THEN -5 WHEN 'triangle-left' THEN 5 ELSE 0 END,
       element_at(pts, -1).y + IF(arrow_shape = 'triangle-down', -5, 0),
       NULL, NULL, NULL, arrow_shape, NULL, conformance
FROM geom
UNION ALL
SELECT 'label', concat(src, ' → ', tgt), src, tgt, cases, median_wait_h, lbl.x, lbl.y, NULL, NULL, NULL, NULL, NULL, conformance
FROM geom;
