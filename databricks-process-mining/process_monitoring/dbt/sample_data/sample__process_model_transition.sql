{{ config(enabled = var('use_sample_data') | as_bool, materialized = 'table', tags = ['sample']) }}
SELECT * FROM VALUES
  ('2026.1', 'Access Request', '▶ Start',                 'Beantragt'),
  ('2026.1', 'Access Request', 'Beantragt',               'Prüfung Data Owner'),
  ('2026.1', 'Access Request', 'Prüfung Data Owner',      'Prüfung Security'),
  ('2026.1', 'Access Request', 'Prüfung Data Owner',      'Abgelehnt'),
  ('2026.1', 'Access Request', 'Prüfung Security',        'Berechtigung erteilt'),
  ('2026.1', 'Access Request', 'Prüfung Security',        'Abgelehnt'),
  ('2026.1', 'Access Request', 'Berechtigung erteilt',    '■ Ende'),
  ('2026.1', 'Access Request', 'Abgelehnt',               '■ Ende'),

  ('2026.1', 'Data Contract',  '▶ Start',                 'Entwurf erstellt'),
  ('2026.1', 'Data Contract',  'Entwurf erstellt',        'Schema validiert'),
  ('2026.1', 'Data Contract',  'Schema validiert',        'Review Data Owner'),
  ('2026.1', 'Data Contract',  'Review Data Owner',       'Freigegeben'),
  ('2026.1', 'Data Contract',  'Review Data Owner',       'Verworfen'),
  ('2026.1', 'Data Contract',  'Freigegeben',             'Aktiv'),
  ('2026.1', 'Data Contract',  'Aktiv',                   '■ Ende'),
  ('2026.1', 'Data Contract',  'Aktiv',                   'Änderung beantragt'),
  ('2026.1', 'Data Contract',  'Änderung beantragt',      'Schema erneut validiert'),
  ('2026.1', 'Data Contract',  'Schema erneut validiert', 'Review Änderung'),
  ('2026.1', 'Data Contract',  'Review Änderung',         'Neue Version aktiv'),
  ('2026.1', 'Data Contract',  'Review Änderung',         'Verworfen'),               -- Änderung ablehnen
  ('2026.1', 'Data Contract',  'Neue Version aktiv',      '■ Ende'),
  ('2026.1', 'Data Contract',  'Verworfen',               '■ Ende'),

  ('2026.1', 'Data Product',   '▶ Start',                 'Angelegt'),
  ('2026.1', 'Data Product',   'Angelegt',                'Metadaten erfasst'),
  ('2026.1', 'Data Product',   'Metadaten erfasst',       'Data Contract verknüpft'),
  ('2026.1', 'Data Product',   'Data Contract verknüpft', 'Qualitätsprüfung'),
  ('2026.1', 'Data Product',   'Qualitätsprüfung',        'Metadaten erfasst'),        -- erlaubte Nachbesserung
  ('2026.1', 'Data Product',   'Qualitätsprüfung',        'Freigabe Data Owner'),
  ('2026.1', 'Data Product',   'Freigabe Data Owner',     'Veröffentlicht'),
  ('2026.1', 'Data Product',   'Freigabe Data Owner',     'Abgelehnt'),
  ('2026.1', 'Data Product',   'Veröffentlicht',          '■ Ende'),
  ('2026.1', 'Data Product',   'Abgelehnt',               '■ Ende')
AS t(model_version, process, src, tgt)
