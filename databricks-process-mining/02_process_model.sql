-- =====================================================================
-- Soll-Prozess (Referenzmodell) für das Conformance Checking
--
-- process_model_activities : Aktivitäten des Standardprozesses mit Reihenfolge
-- process_model_transitions: erlaubte direkte Übergänge (inkl. Start/Ende)
--
-- Alles, was hier NICHT steht, gilt als Abweichung. Für den echten Prozess
-- nur diese beiden Tabellen pflegen; alle Datasets werten sie automatisch aus.
-- =====================================================================
CREATE OR REPLACE TABLE main.process_mining.process_model_activities AS
SELECT * FROM VALUES
  ('▶ Start',              0, false),
  ('Auftrag angelegt',     1, false),
  ('Kreditprüfung',        2, false),
  ('Auftrag freigegeben',  3, false),
  ('Lieferung',            4, false),
  ('Rechnung gestellt',    5, false),
  ('Zahlung erhalten',     6, false),
  ('Storniert',           90, true),   -- zulässiger Abbruch (Terminal-Aktivität)
  ('■ Ende',              99, true)
AS t(activity, step_order, is_terminal);

CREATE OR REPLACE TABLE main.process_mining.process_model_transitions AS
SELECT * FROM VALUES
  ('▶ Start',             'Auftrag angelegt'),
  ('Auftrag angelegt',    'Kreditprüfung'),
  ('Kreditprüfung',       'Auftrag freigegeben'),
  ('Kreditprüfung',       'Storniert'),           -- Kredit abgelehnt
  ('Auftrag freigegeben', 'Lieferung'),
  ('Lieferung',           'Rechnung gestellt'),
  ('Rechnung gestellt',   'Zahlung erhalten'),
  ('Zahlung erhalten',    '■ Ende'),
  ('Storniert',           '■ Ende')
AS t(src, tgt);
