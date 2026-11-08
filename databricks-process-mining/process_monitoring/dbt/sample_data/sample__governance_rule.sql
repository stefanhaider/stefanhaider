{{ config(enabled = var('use_sample_data') | as_bool, materialized = 'table', tags = ['sample']) }}
SELECT * FROM VALUES
  ('2026.1', 'Access Request', 'AR-SOD-01', 'sod', 'Beantragt',        'Prüfung Data Owner',   CAST(NULL AS INT), 'Antragsteller genehmigt eigenen Antrag',       'kritisch'),
  ('2026.1', 'Data Contract',  'DC-SOD-01', 'sod', 'Entwurf erstellt', 'Review Data Owner',    NULL,              'Autor reviewt eigenen Data Contract',          'kritisch'),
  ('2026.1', 'Data Product',   'DP-SOD-01', 'sod', 'Angelegt',         'Freigabe Data Owner',  NULL,              'Ersteller gibt eigenes Datenprodukt frei',     'kritisch'),
  ('2026.1', 'Access Request', 'AR-SLA-01', 'sla', 'Beantragt',        'Berechtigung erteilt', 120,               'Zugriff innerhalb von 5 Tagen',                'mittel'),
  ('2026.1', 'Data Contract',  'DC-SLA-01', 'sla', 'Entwurf erstellt', 'Freigegeben',          168,               'Freigabe innerhalb von 7 Tagen',               'mittel'),
  ('2026.1', 'Data Product',   'DP-SLA-01', 'sla', 'Angelegt',         'Veröffentlicht',       240,               'Veröffentlichung innerhalb von 10 Tagen',      'mittel')
AS t(model_version, process, rule_id, rule_type, activity_a, activity_b, max_hours, description, severity)
