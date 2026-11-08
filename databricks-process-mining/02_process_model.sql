-- =====================================================================
-- Data Manager – Soll-Prozesse und Governance-Regeln (Konfiguration)
--
-- Diese Tabellen sind die EINZIGE Stelle, die bei Prozessänderungen gepflegt
-- wird. Alle Views, Datasets und das Dashboard werten sie automatisch aus.
--
--   process_catalog            Prozesse, Verantwortliche, Beschreibung
--   process_model_activities   Aktivitäten je Prozess: Reihenfolge, Ende, Kontrollschritt
--   process_model_transitions  erlaubte direkte Übergänge (alles andere = Abweichung)
--   governance_rules           Regeln über den Pfad hinaus: Funktionstrennung (sod), Fristen (sla)
--   finding_severity           Schweregrad und empfohlene Maßnahme je Befund-Typ
--   process_graph_layout       Position der Aktivitäten im Prozessgraphen (Raster 800 breit)
--
-- System-Ebene (gehört dem Data-Manager-Entwicklungsteam, NICHT der Governance):
--   app_releases                Releases des Data Managers (für Zuordnung "seit Release X")
--   system_allowed_transitions  vom Data Manager technisch erlaubte Übergänge je Gültigkeitszeitraum.
--                               In Produktion automatisch aus workflow_definition.json geladen
--                               (Export der Status-Maschine, siehe EVENT_STANDARD.md).
-- =====================================================================

CREATE OR REPLACE TABLE main.data_manager_pm.process_catalog AS
SELECT * FROM VALUES
  ('Access Request', 'Data Security Office',     'Zugriff auf Datenprodukte beantragen, prüfen und vergeben'),
  ('Data Contract',  'Data Architecture',        'Data Contracts erstellen, prüfen, freigeben und versionieren'),
  ('Data Product',   'Data Product Management',  'Datenprodukte anlegen, prüfen, freigeben und veröffentlichen')
AS t(process, owner, description);

-- step_order: Reihenfolge im Soll-Prozess (für die Klassifizierung von Abweichungen)
-- is_terminal: zulässige Ende-Aktivität  ·  is_control: Kontrollschritt (Umgehung = kritisch)
-- '▶ Start' und '■ Ende' sind Pseudo-Aktivitäten und müssen je Prozess vorhanden sein.
CREATE OR REPLACE TABLE main.data_manager_pm.process_model_activities AS
SELECT * FROM VALUES
  ('Access Request', '▶ Start',                  0, false, false),
  ('Access Request', 'Beantragt',                1, false, false),
  ('Access Request', 'Prüfung Data Owner',       2, false, true),
  ('Access Request', 'Prüfung Security',         3, false, true),
  ('Access Request', 'Berechtigung erteilt',     4, false, false),
  ('Access Request', 'Abgelehnt',               90, true,  false),
  ('Access Request', '■ Ende',                  99, true,  false),

  ('Data Contract',  '▶ Start',                  0, false, false),
  ('Data Contract',  'Entwurf erstellt',         1, false, false),
  ('Data Contract',  'Schema validiert',         2, false, true),
  ('Data Contract',  'Review Data Owner',        3, false, true),
  ('Data Contract',  'Freigegeben',              4, false, false),
  ('Data Contract',  'Aktiv',                    5, false, false),
  ('Data Contract',  'Änderung beantragt',       6, false, false),
  ('Data Contract',  'Schema erneut validiert',  7, false, true),
  ('Data Contract',  'Review Änderung',          8, false, true),
  ('Data Contract',  'Neue Version aktiv',       9, false, false),
  ('Data Contract',  'Verworfen',               90, true,  false),
  ('Data Contract',  '■ Ende',                  99, true,  false),

  ('Data Product',   '▶ Start',                  0, false, false),
  ('Data Product',   'Angelegt',                 1, false, false),
  ('Data Product',   'Metadaten erfasst',        2, false, false),
  ('Data Product',   'Data Contract verknüpft',  3, false, true),
  ('Data Product',   'Qualitätsprüfung',         4, false, true),
  ('Data Product',   'Freigabe Data Owner',      5, false, true),
  ('Data Product',   'Veröffentlicht',           6, false, false),
  ('Data Product',   'Abgelehnt',               90, true,  false),
  ('Data Product',   '■ Ende',                  99, true,  false)
AS t(process, activity, step_order, is_terminal, is_control);

CREATE OR REPLACE TABLE main.data_manager_pm.process_model_transitions AS
SELECT * FROM VALUES
  ('Access Request', '▶ Start',                 'Beantragt'),
  ('Access Request', 'Beantragt',               'Prüfung Data Owner'),
  ('Access Request', 'Prüfung Data Owner',      'Prüfung Security'),
  ('Access Request', 'Prüfung Data Owner',      'Abgelehnt'),
  ('Access Request', 'Prüfung Security',        'Berechtigung erteilt'),
  ('Access Request', 'Prüfung Security',        'Abgelehnt'),
  ('Access Request', 'Berechtigung erteilt',    '■ Ende'),
  ('Access Request', 'Abgelehnt',               '■ Ende'),

  ('Data Contract',  '▶ Start',                 'Entwurf erstellt'),
  ('Data Contract',  'Entwurf erstellt',        'Schema validiert'),
  ('Data Contract',  'Schema validiert',        'Review Data Owner'),
  ('Data Contract',  'Review Data Owner',       'Freigegeben'),
  ('Data Contract',  'Review Data Owner',       'Verworfen'),
  ('Data Contract',  'Freigegeben',             'Aktiv'),
  ('Data Contract',  'Aktiv',                   '■ Ende'),
  ('Data Contract',  'Aktiv',                   'Änderung beantragt'),
  ('Data Contract',  'Änderung beantragt',      'Schema erneut validiert'),
  ('Data Contract',  'Schema erneut validiert', 'Review Änderung'),
  ('Data Contract',  'Review Änderung',         'Neue Version aktiv'),
  ('Data Contract',  'Review Änderung',         'Verworfen'),               -- Änderung ablehnen
  ('Data Contract',  'Neue Version aktiv',      '■ Ende'),
  ('Data Contract',  'Verworfen',               '■ Ende'),

  ('Data Product',   '▶ Start',                 'Angelegt'),
  ('Data Product',   'Angelegt',                'Metadaten erfasst'),
  ('Data Product',   'Metadaten erfasst',       'Data Contract verknüpft'),
  ('Data Product',   'Data Contract verknüpft', 'Qualitätsprüfung'),
  ('Data Product',   'Qualitätsprüfung',        'Metadaten erfasst'),        -- erlaubte Nachbesserung
  ('Data Product',   'Qualitätsprüfung',        'Freigabe Data Owner'),
  ('Data Product',   'Freigabe Data Owner',     'Veröffentlicht'),
  ('Data Product',   'Freigabe Data Owner',     'Abgelehnt'),
  ('Data Product',   'Veröffentlicht',          '■ Ende'),
  ('Data Product',   'Abgelehnt',               '■ Ende')
AS t(process, src, tgt);

-- rule_type 'sod': activity_a und activity_b dürfen NICHT von derselben Person ausgeführt werden
-- rule_type 'sla': von activity_a bis activity_b höchstens max_hours
CREATE OR REPLACE TABLE main.data_manager_pm.governance_rules AS
SELECT * FROM VALUES
  ('Access Request', 'AR-SOD-01', 'sod', 'Beantragt',        'Prüfung Data Owner',   CAST(NULL AS INT), 'Antragsteller genehmigt eigenen Antrag',       'kritisch'),
  ('Data Contract',  'DC-SOD-01', 'sod', 'Entwurf erstellt', 'Review Data Owner',    NULL,              'Autor reviewt eigenen Data Contract',          'kritisch'),
  ('Data Product',   'DP-SOD-01', 'sod', 'Angelegt',         'Freigabe Data Owner',  NULL,              'Ersteller gibt eigenes Datenprodukt frei',     'kritisch'),
  ('Access Request', 'AR-SLA-01', 'sla', 'Beantragt',        'Berechtigung erteilt', 120,               'Zugriff innerhalb von 5 Tagen',                'mittel'),
  ('Data Contract',  'DC-SLA-01', 'sla', 'Entwurf erstellt', 'Freigegeben',          168,               'Freigabe innerhalb von 7 Tagen',               'mittel'),
  ('Data Product',   'DP-SLA-01', 'sla', 'Angelegt',         'Veröffentlicht',       240,               'Veröffentlichung innerhalb von 10 Tagen',      'mittel')
AS t(process, rule_id, rule_type, activity_a, activity_b, max_hours, description, severity);

CREATE OR REPLACE TABLE main.data_manager_pm.finding_severity AS
SELECT * FROM VALUES
  ('Kontrolle umgangen',             'kritisch', 1, 'Kontrollschritt in der Applikation erzwingen'),
  ('Funktionstrennung verletzt',     'kritisch', 1, 'Vier-Augen-Prinzip in der Applikation erzwingen'),
  ('Abbruch an unzulässiger Stelle', 'hoch',     2, 'Statusübergang in der Applikation sperren'),
  ('Schritt übersprungen',           'hoch',     2, 'Prüfen, ob der Schritt optional ist; sonst erzwingen'),
  ('Unzulässiger Übergang',          'hoch',     2, 'Statusübergang prüfen und ggf. sperren'),
  ('Kein gültiger Abschluss',        'hoch',     2, 'Abgebrochene oder hängende Vorgänge klären'),
  ('Rücksprung / Wiederholung',      'mittel',   3, 'Soll-Prozess ergänzen oder Ursache beheben'),
  ('Zusätzliche Aktivität',          'mittel',   3, 'Soll-Prozess ergänzen oder Aktivität unterbinden'),
  ('Frist überschritten',            'mittel',   3, 'Erinnerung und Eskalation einrichten')
AS t(finding_type, severity, severity_rank, recommended_action);

-- Layout des Prozessgraphen: Standardprozess senkrecht bei x = 400, Abweichungen seitlich.
-- Aktivitäten ohne Eintrag werden automatisch rechts (x = 740) untereinander platziert.
CREATE OR REPLACE TABLE main.data_manager_pm.process_graph_layout AS
SELECT * FROM VALUES
  ('Access Request', '▶ Start',                 400D,  24D),
  ('Access Request', 'Beantragt',               400D, 100D),
  ('Access Request', 'Prüfung Data Owner',      400D, 180D),
  ('Access Request', 'Prüfung Security',        400D, 260D),
  ('Access Request', 'Berechtigung erteilt',    400D, 340D),
  ('Access Request', 'Abgelehnt',               660D, 340D),
  ('Access Request', '■ Ende',                  400D, 420D),

  ('Data Contract',  '▶ Start',                 400D,  24D),
  ('Data Contract',  'Entwurf erstellt',        400D, 100D),
  ('Data Contract',  'Schema validiert',        400D, 180D),
  ('Data Contract',  'Review Data Owner',       400D, 260D),
  ('Data Contract',  'Verworfen',               150D, 340D),
  ('Data Contract',  'Freigegeben',             400D, 340D),
  ('Data Contract',  'Aktiv',                   400D, 420D),
  ('Data Contract',  'Änderung beantragt',      660D, 420D),
  ('Data Contract',  'Schema erneut validiert', 660D, 500D),
  ('Data Contract',  'Review Änderung',         660D, 580D),
  ('Data Contract',  'Neue Version aktiv',      660D, 660D),
  ('Data Contract',  '■ Ende',                  400D, 740D),

  ('Data Product',   '▶ Start',                 400D,  24D),
  ('Data Product',   'Angelegt',                400D, 100D),
  ('Data Product',   'Metadaten erfasst',       400D, 180D),
  ('Data Product',   'Data Contract verknüpft', 400D, 260D),
  ('Data Product',   'Qualitätsprüfung',        400D, 340D),
  ('Data Product',   'Freigabe Data Owner',     400D, 420D),
  ('Data Product',   'Veröffentlicht',          400D, 500D),
  ('Data Product',   'Abgelehnt',               660D, 500D),
  ('Data Product',   '■ Ende',                  400D, 580D)
AS t(process, activity, x, y);


-- ---------------------------------------------------------------------
-- System-Ebene
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE main.data_manager_pm.app_releases AS
SELECT * FROM VALUES
  ('2.2', TIMESTAMP'2026-01-01 00:00:00', 'Ausgangsstand'),
  ('2.3', TIMESTAMP'2026-03-30 00:00:00', 'Access Request: Security-Prüfung für interne Datenprodukte optional'),
  ('2.4', TIMESTAMP'2026-04-06 00:00:00', 'Data Contract: Schema-Validierung vor Review erzwungen'),
  ('2.5', TIMESTAMP'2026-05-18 00:00:00', 'Data Product: Batch-Import für Migration aktiviert')
AS t(version, released_at, notes);

-- Erlaubte Übergänge laut Status-Maschine des Data Managers.
-- valid_to NULL = im aktuellen Release erlaubt. Ein Event ist "vom System erlaubt",
-- wenn zum Eventzeitpunkt ein passender Eintrag gültig war.
CREATE OR REPLACE TABLE main.data_manager_pm.system_allowed_transitions AS
WITH base AS (   -- alle Soll-Übergänge sind implementiert ...
  SELECT process, src, tgt, TIMESTAMP'2026-01-01 00:00:00' AS valid_from, CAST(NULL AS TIMESTAMP) AS valid_to,
         '2.2' AS since_release, 'Standard-Workflow' AS note
  FROM main.data_manager_pm.process_model_transitions
  WHERE NOT (process = 'Data Contract' AND src = 'Review Änderung' AND tgt = 'Verworfen')   -- ... außer: Änderung ablehnen fehlt
),
extra AS (       -- ... und das System erlaubt zusätzlich:
  SELECT * FROM VALUES
    ('Access Request', 'Prüfung Data Owner',      'Beantragt',              TIMESTAMP'2026-01-01 00:00:00', CAST(NULL AS TIMESTAMP), '2.2', 'Rückfrage an Antragsteller'),
    ('Access Request', 'Prüfung Data Owner',      'Berechtigung erteilt',   TIMESTAMP'2026-03-30 00:00:00', NULL,                    '2.3', 'Security-Prüfung optional (interne Daten)'),
    ('Access Request', 'Beantragt',               'Berechtigung erteilt',   TIMESTAMP'2026-01-01 00:00:00', NULL,                    '2.2', 'Express-Vergabe (Feature-Flag, ungenutzt)'),
    ('Data Contract',  'Entwurf erstellt',        'Review Data Owner',      TIMESTAMP'2026-01-01 00:00:00', TIMESTAMP'2026-04-06 00:00:00', '2.2', 'bis Release 2.4: Schema-Validierung optional'),
    ('Data Contract',  'Änderung beantragt',      'Neue Version aktiv',     TIMESTAMP'2026-01-01 00:00:00', NULL,                    '2.2', 'REST-API: PATCH aktiviert neue Version direkt'),
    ('Data Product',   'Data Contract verknüpft', 'Freigabe Data Owner',    TIMESTAMP'2026-01-01 00:00:00', NULL,                    '2.2', 'Qualitätsprüfung überspringbar'),
    ('Data Product',   'Metadaten erfasst',       'Qualitätsprüfung',       TIMESTAMP'2026-01-01 00:00:00', NULL,                    '2.2', 'Data Contract optional'),
    ('Data Product',   'Metadaten erfasst',       'Freigabe Data Owner',    TIMESTAMP'2026-01-01 00:00:00', NULL,                    '2.2', 'Contract und Qualität überspringbar (ungenutzt)')
  AS t(process, src, tgt, valid_from, valid_to, since_release, note)
)
SELECT * FROM base UNION ALL SELECT * FROM extra;
