-- =====================================================================
-- Data Manager – synthetisches Eventlog (nur für Demo und Tests)
--
-- Drei Prozesse des Data Managers mit typischen Governance-Lücken:
--   Access Request (500 Vorgänge), Data Contract (300), Data Product (200)
--
-- Eingebaute Effekte (zum Prüfen der Datasets und des Dashboards):
--   AR: ab KW 14 (30.03.2026) Berechtigungen OHNE Security-Prüfung   -> Kontrolle umgangen, aktiv
--   AR: Berechtigungen direkt ohne Antrag (Admin-Backend)            -> Kontrolle umgangen, aktiv
--   AR: Antrag geht zur Überarbeitung zurück (nicht modelliert)      -> Rücksprung
--   DC: Freigabe ohne Schema-Validierung, nur bis Anfang April       -> Kontrolle umgangen, behoben
--   DC: neue Contract-Version ohne Review der Änderung               -> Kontrolle umgangen, aktiv
--   DP: veröffentlicht ohne Qualitätsprüfung bzw. ohne Data Contract -> Kontrolle umgangen, aktiv
--   DP: ab 18.05. direkt veröffentlicht (Angelegt -> Veröffentlicht) -> Kontrolle umgangen, NEU
--   alle: ca. 4 % der Data-Owner-Freigaben durch den Antragsteller   -> Funktionstrennung verletzt
--   alle: lange Freigabezeiten (Heavy Tail)                          -> Frist überschritten
--
-- System-Ebene (Kanal, Release, abgewiesene Versuche):
--   AR-Vergabe ohne Antrag läuft über die Admin-API      (channel 'admin_api') -> außerhalb des Workflows
--   DP-Direktveröffentlichung läuft über den Batch-Import (channel 'batch')     -> außerhalb des Workflows
--   DC-Änderung ohne Review läuft über die REST-API       (channel 'api')       -> vom System erlaubt
--   DC: nach Release 2.4 (06.04.) abgewiesene Versuche, die Schema-Validierung zu überspringen
--   DP: ab 18.05. abgewiesene Versuche, in der UI direkt zu veröffentlichen
--
-- Spalten gemäß EVENT_STANDARD.md: process, case_id, domain, step_no, event_type
-- ('transition' | 'rejected'), from_activity, activity, actor, channel, app_version, event_ts
--
-- Für echte Daten: diese Tabelle durch eine View auf das Audit-/Workflow-Log
-- des Data Managers ersetzen (gleiche Spaltennamen, siehe IMPLEMENTATION_SPEC.md).
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS main.data_manager_pm;

CREATE OR REPLACE TABLE main.data_manager_pm.event_log AS
WITH variants AS (
  SELECT * FROM VALUES
    -- Access Request
    ('Access Request', 1, 300, array('Beantragt','Prüfung Data Owner','Prüfung Security','Berechtigung erteilt'), DATE'2026-01-05', 26),
    ('Access Request', 2,  40, array('Beantragt','Prüfung Data Owner','Abgelehnt'), DATE'2026-01-05', 26),
    ('Access Request', 3,  20, array('Beantragt','Prüfung Data Owner','Prüfung Security','Abgelehnt'), DATE'2026-01-05', 26),
    ('Access Request', 4,  90, array('Beantragt','Prüfung Data Owner','Berechtigung erteilt'), DATE'2026-03-30', 14),
    ('Access Request', 5,  15, array('Berechtigung erteilt'), DATE'2026-01-05', 26),
    ('Access Request', 6,  35, array('Beantragt','Prüfung Data Owner','Beantragt','Prüfung Data Owner','Prüfung Security','Berechtigung erteilt'), DATE'2026-01-05', 26),
    -- Data Contract
    ('Data Contract', 1, 170, array('Entwurf erstellt','Schema validiert','Review Data Owner','Freigegeben','Aktiv'), DATE'2026-01-05', 26),
    ('Data Contract', 2,  45, array('Entwurf erstellt','Schema validiert','Review Data Owner','Freigegeben','Aktiv','Änderung beantragt','Schema erneut validiert','Review Änderung','Neue Version aktiv'), DATE'2026-01-05', 26),
    ('Data Contract', 3,  20, array('Entwurf erstellt','Schema validiert','Review Data Owner','Verworfen'), DATE'2026-01-05', 26),
    ('Data Contract', 4,  25, array('Entwurf erstellt','Review Data Owner','Freigegeben','Aktiv'), DATE'2026-01-05', 12),
    ('Data Contract', 5,  40, array('Entwurf erstellt','Schema validiert','Review Data Owner','Freigegeben','Aktiv','Änderung beantragt','Neue Version aktiv'), DATE'2026-01-05', 26),
    -- Data Product
    ('Data Product', 1, 110, array('Angelegt','Metadaten erfasst','Data Contract verknüpft','Qualitätsprüfung','Freigabe Data Owner','Veröffentlicht'), DATE'2026-01-05', 26),
    ('Data Product', 2,  25, array('Angelegt','Metadaten erfasst','Data Contract verknüpft','Qualitätsprüfung','Metadaten erfasst','Data Contract verknüpft','Qualitätsprüfung','Freigabe Data Owner','Veröffentlicht'), DATE'2026-01-05', 26),
    ('Data Product', 3,  15, array('Angelegt','Metadaten erfasst','Data Contract verknüpft','Qualitätsprüfung','Freigabe Data Owner','Abgelehnt'), DATE'2026-01-05', 26),
    ('Data Product', 4,  20, array('Angelegt','Metadaten erfasst','Data Contract verknüpft','Freigabe Data Owner','Veröffentlicht'), DATE'2026-01-05', 26),
    ('Data Product', 5,  20, array('Angelegt','Metadaten erfasst','Qualitätsprüfung','Freigabe Data Owner','Veröffentlicht'), DATE'2026-01-05', 26),
    ('Data Product', 6,  10, array('Angelegt','Veröffentlicht'), DATE'2026-05-18', 7)
  AS t(process, variant_id, n_cases, activities, start_from, weeks)
),
cases AS (
  SELECT
    v.process, v.variant_id, v.activities,
    concat(CASE v.process WHEN 'Access Request' THEN 'AR' WHEN 'Data Contract' THEN 'DC' ELSE 'DP' END,
           '-', lpad(CAST(v.variant_id * 1000 + case_no AS STRING), 5, '0')) AS case_id,
    element_at(array('Finance', 'Sales', 'HR', 'Supply Chain'), CAST(pmod(abs(hash(v.process, case_no)), 4) + 1 AS INT)) AS domain,
    timestampadd(HOUR, CAST(pmod(abs(hash(v.process, v.variant_id, case_no)), v.weeks * 7 * 24) AS INT),
                 CAST(v.start_from AS TIMESTAMP)) AS case_start
  FROM variants v
  LATERAL VIEW explode(sequence(1, v.n_cases)) AS case_no
),
people AS (
  SELECT *,
    concat('user_',     lpad(CAST(pmod(abs(hash(case_id, 'req')), 80) AS STRING), 3, '0')) AS requester,
    concat('owner_',    lpad(CAST(pmod(abs(hash(case_id, 'own')), 20) AS STRING), 2, '0')) AS data_owner,
    concat('security_', lpad(CAST(pmod(abs(hash(case_id, 'sec')),  5) AS STRING), 2, '0')) AS security_officer,
    concat('admin_',    lpad(CAST(pmod(abs(hash(case_id, 'adm')),  4) AS STRING), 2, '0')) AS admin,
    (process = 'Data Product' AND variant_id = 6) AS via_batch,
    pmod(abs(hash(case_id, 'sod')), 100) < 4 AS sod_violation   -- ca. 4 %: Data Owner = Antragsteller
  FROM cases
),
events AS (
SELECT
  p.process,
  p.case_id,
  p.domain,
  a.pos AS step_no,
  'transition' AS event_type,
  IF(a.pos = 0, CAST(NULL AS STRING), element_at(p.activities, a.pos)) AS from_activity,
  a.activity,
  CASE
    WHEN p.via_batch THEN 'svc_batch_import'
    WHEN a.pos = 0 AND a.activity = 'Berechtigung erteilt' THEN p.admin            -- Vergabe ohne Antrag
    WHEN a.pos = 0 THEN p.requester
    WHEN a.activity IN ('Prüfung Data Owner', 'Review Data Owner', 'Freigabe Data Owner', 'Review Änderung')
      THEN IF(p.sod_violation, p.requester, p.data_owner)
    WHEN a.activity = 'Prüfung Security' THEN p.security_officer
    WHEN a.activity IN ('Berechtigung erteilt', 'Schema validiert', 'Schema erneut validiert',
                        'Qualitätsprüfung', 'Veröffentlicht', 'Aktiv', 'Neue Version aktiv') THEN 'system'
    ELSE p.requester
  END AS actor,
  CASE
    WHEN p.via_batch THEN 'batch'
    WHEN a.pos = 0 AND a.activity = 'Berechtigung erteilt' THEN 'admin_api'
    WHEN p.process = 'Data Contract' AND p.variant_id = 5 AND a.activity = 'Neue Version aktiv' THEN 'api'
    WHEN a.activity IN ('Berechtigung erteilt', 'Schema validiert', 'Schema erneut validiert',
                        'Qualitätsprüfung', 'Veröffentlicht', 'Aktiv', 'Neue Version aktiv') THEN 'system'
    ELSE 'ui'
  END AS channel,
  -- Wartezeit bis zur Aktivität = typische Dauer × Faktor; Freigaben mit langem Ausläufer (Fristverletzungen)
  timestampadd(
    MINUTE,
    CAST(60 * aggregate(sequence(0, a.pos), 0D, (acc, i) -> acc + IF(i = 0, 0D,
      element_at(map(
        'Beantragt', 4D, 'Prüfung Data Owner', 30D, 'Prüfung Security', 24D, 'Berechtigung erteilt', 3D, 'Abgelehnt', 4D,
        'Entwurf erstellt', 4D, 'Schema validiert', 1D, 'Review Data Owner', 40D, 'Freigegeben', 4D, 'Aktiv', 6D, 'Verworfen', 8D,
        'Änderung beantragt', 500D, 'Schema erneut validiert', 1D, 'Review Änderung', 36D, 'Neue Version aktiv', 6D,
        'Angelegt', 4D, 'Metadaten erfasst', 20D, 'Data Contract verknüpft', 30D, 'Qualitätsprüfung', 12D,
        'Freigabe Data Owner', 40D, 'Veröffentlicht', 4D
      ), element_at(p.activities, i + 1))
      * IF(element_at(p.activities, i + 1) IN ('Prüfung Data Owner', 'Review Data Owner', 'Freigabe Data Owner', 'Prüfung Security', 'Review Änderung'),
           0.3D + 4D * pow(pmod(abs(hash(p.case_id, i)), 1000) / 1000D, 4),
           0.5D + pmod(abs(hash(p.case_id, i)), 1000) / 1000D))) AS INT),
    p.case_start
  ) AS event_ts
FROM people p
LATERAL VIEW posexplode(p.activities) a AS pos, activity
),
-- Vom System abgewiesene Versuche (event_type 'rejected'): kein Statuswechsel, nur Nachweis
rejected AS (
  SELECT process, case_id, domain, 99 AS step_no, 'rejected' AS event_type,
         CASE process WHEN 'Data Contract' THEN 'Entwurf erstellt' ELSE 'Angelegt' END AS from_activity,
         CASE process WHEN 'Data Contract' THEN 'Review Data Owner' ELSE 'Veröffentlicht' END AS activity,
         requester AS actor, 'ui' AS channel,
         timestampadd(MINUTE, 30, case_start) AS event_ts
  FROM people
  WHERE (process = 'Data Contract' AND variant_id = 1 AND case_start >= TIMESTAMP'2026-04-06' AND pmod(abs(hash(case_id, 'rej')), 100) < 15)
     OR (process = 'Data Product'  AND variant_id = 1 AND case_start >= TIMESTAMP'2026-05-18' AND pmod(abs(hash(case_id, 'rej')), 100) < 25)
),
all_events AS (
  SELECT * FROM events UNION ALL SELECT * FROM rejected
)
SELECT
  process, case_id, domain, step_no, event_type, from_activity, activity, actor, channel,
  -- Release des Data Managers zum Eventzeitpunkt (siehe app_releases in 02_process_model.sql)
  CASE WHEN event_ts >= TIMESTAMP'2026-05-18' THEN '2.5'
       WHEN event_ts >= TIMESTAMP'2026-04-06' THEN '2.4'
       WHEN event_ts >= TIMESTAMP'2026-03-30' THEN '2.3'
       ELSE '2.2' END AS app_version,
  event_ts
FROM all_events;
