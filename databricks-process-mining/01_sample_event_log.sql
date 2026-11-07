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
    -- Start gleichmäßig über 26 Wochen ab Mo 05.01.2026 verteilt. Zwei simulierte Effekte:
    --  * Varianten ohne Kreditprüfung (2, 5, 6) erst ab Mo 02.03.2026, als hätte ein
    --    Release die Freigabe ohne Kreditprüfung ermöglicht.
    --  * Sofort-Storno ohne Kreditprüfung (8) nur bis Anfang April, als wäre es behoben worden.
    CASE
      WHEN variant_id IN (2, 5, 6) THEN timestampadd(HOUR, CAST(pmod(abs(hash(variant_id, case_no)), 18 * 7 * 24) AS INT), TIMESTAMP'2026-03-02 00:00:00')
      WHEN variant_id = 8          THEN timestampadd(HOUR, CAST(pmod(abs(hash(variant_id, case_no)), 13 * 7 * 24) AS INT), TIMESTAMP'2026-01-05 00:00:00')
      ELSE                              timestampadd(HOUR, CAST(pmod(abs(hash(variant_id, case_no)), 26 * 7 * 24) AS INT), TIMESTAMP'2026-01-05 00:00:00')
    END AS case_start
  FROM variants
  LATERAL VIEW explode(sequence(1, n_cases)) AS case_no
)
SELECT
  c.case_id,
  c.region,
  c.variant_id,
  a.pos            AS step_no,
  a.activity,
  -- Wartezeit bis zur Aktivität = typische Dauer je Aktivität × Faktor 0,5–1,5
  -- (deterministisch pseudo-zufällig, damit Engpässe sichtbar werden)
  timestampadd(
    HOUR,
    CAST(aggregate(sequence(0, a.pos), 0D, (acc, i) -> acc + IF(i = 0, 0D,
      element_at(map(
        'Kreditprüfung', 6D, 'Auftrag freigegeben', 10D, 'Preisänderung', 36D,
        'Lieferung', 52D, 'Rechnung gestellt', 8D, 'Zahlung erhalten', 260D,
        'Mahnung', 340D, 'Gutschrift', 96D, 'Storniert', 30D
      ), element_at(c.activities, i + 1))
      * (0.5 + pmod(abs(hash(c.case_id, i)), 100) / 100.0))) AS INT),
    c.case_start
  ) AS event_ts
FROM cases c
LATERAL VIEW posexplode(c.activities) a AS pos, activity;
