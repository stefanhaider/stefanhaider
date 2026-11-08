{{ config(enabled = var('use_sample_data') | as_bool, materialized = 'table', tags = ['sample']) }}
SELECT * FROM VALUES
  ('Access Request', 'Data Security Office',    'Zugriff auf Datenprodukte beantragen, prüfen und vergeben'),
  ('Data Contract',  'Data Architecture',       'Data Contracts erstellen, prüfen, freigeben und versionieren'),
  ('Data Product',   'Data Product Management', 'Datenprodukte anlegen, prüfen, freigeben und veröffentlichen')
AS t(process, owner, description)
