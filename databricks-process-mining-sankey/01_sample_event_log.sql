-- =====================================================================
-- Process Mining Mockup – Beispiel-Eventlog (Order-to-Cash)
-- Erzeugt eine deterministische Tabelle mit 1.000 Fällen / 8 Varianten.
-- Katalog/Schema bei Bedarf anpassen.
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS main.process_mining;

CREATE OR REPLACE TABLE main.process_mining.event_log AS
WITH variants AS (
  SELECT * FROM VALUES
    (1, 420, array('Auftrag angelegt','Kreditprüfung','Auftrag freigegeben','Lieferung','Rechnung gestellt','Zahlung erhalten')),
    (2, 210, array('Auftrag angelegt','Auftrag freigegeben','Lieferung','Rechnung gestellt','Zahlung erhalten')),
    (3, 130, array('Auftrag angelegt','Kreditprüfung','Auftrag freigegeben','Lieferung','Rechnung gestellt','Mahnung','Zahlung erhalten')),
    (4,  70, array('Auftrag angelegt','Kreditprüfung','Storniert')),
    (5,  60, array('Auftrag angelegt','Auftrag freigegeben','Preisänderung','Auftrag freigegeben','Lieferung','Rechnung gestellt','Zahlung erhalten')),
    (6,  50, array('Auftrag angelegt','Auftrag freigegeben','Lieferung','Rechnung gestellt','Gutschrift')),
    (7,  35, array('Auftrag angelegt','Kreditprüfung','Auftrag freigegeben','Lieferung','Storniert')),
    (8,  25, array('Auftrag angelegt','Storniert'))
  AS t(variant_id, n_cases, activities)
),
cases AS (
  SELECT
    variant_id,
    activities,
    concat('ORD-', lpad(CAST(variant_id * 10000 + case_no AS STRING), 6, '0')) AS case_id,
    element_at(array('DACH','Nordics','Benelux','Südeuropa'), CAST(pmod(case_no, 4) + 1 AS INT)) AS region,
    timestampadd(HOUR, CAST(pmod(case_no * 37, 24 * 180) AS INT), TIMESTAMP'2026-01-01 08:00:00') AS case_start
  FROM variants
  LATERAL VIEW explode(sequence(1, n_cases)) AS case_no
)
SELECT
  c.case_id,
  c.region,
  c.variant_id,
  a.pos            AS step_no,
  a.activity,
  -- jede Aktivität 2–50 h nach der vorherigen (deterministisch pseudo-zufällig)
  timestampadd(
    HOUR,
    CAST(aggregate(sequence(0, a.pos), 0, (acc, i) -> acc + IF(i = 0, 0, 2 + pmod(abs(hash(c.case_id, i)), 48))) AS INT),
    c.case_start
  ) AS event_ts
FROM cases c
LATERAL VIEW posexplode(c.activities) a AS pos, activity;
