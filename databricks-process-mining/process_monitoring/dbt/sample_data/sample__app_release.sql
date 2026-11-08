{{ config(enabled = var('use_sample_data') | as_bool, materialized = 'table', tags = ['sample']) }}
SELECT * FROM VALUES
  ('2.2', TIMESTAMP'2026-01-01 00:00:00', 'Ausgangsstand'),
  ('2.3', TIMESTAMP'2026-03-30 00:00:00', 'Access Request: Security-Prüfung für interne Datenprodukte optional'),
  ('2.4', TIMESTAMP'2026-04-06 00:00:00', 'Data Contract: Schema-Validierung vor Review erzwungen'),
  ('2.5', TIMESTAMP'2026-05-18 00:00:00', 'Data Product: Batch-Import für Migration aktiviert')
AS t(version, released_at, notes)
