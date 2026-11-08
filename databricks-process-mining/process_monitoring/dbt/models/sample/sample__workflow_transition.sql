-- Status-Maschine je Release, wie sie dm-sync-governance bei jedem Deploy schreiben würde.
-- Basis: alle Soll-Übergänge außer "Review Änderung → Verworfen" (im System nicht implementiert),
-- plus zusätzliche Übergänge mit Gültigkeit von/bis Release.
WITH releases AS (SELECT version, released_at FROM {{ ref('sample__app_release') }}),
base AS (
  SELECT process, src, tgt, '2.2' AS since_release, 'Standard-Workflow' AS note,
         TIMESTAMP'2026-01-01 00:00:00' AS from_ts, CAST(NULL AS TIMESTAMP) AS to_ts
  FROM {{ ref('sample__process_model_transition') }}
  WHERE NOT (process = 'Data Contract' AND src = 'Review Änderung' AND tgt = 'Verworfen')
),
extra AS (
  SELECT * FROM VALUES
    ('Access Request', 'Prüfung Data Owner',      'Beantragt',            '2.2', 'Rückfrage an Antragsteller',                     TIMESTAMP'2026-01-01 00:00:00', CAST(NULL AS TIMESTAMP)),
    ('Access Request', 'Prüfung Data Owner',      'Berechtigung erteilt', '2.3', 'Security-Prüfung optional (interne Daten)',      TIMESTAMP'2026-03-30 00:00:00', NULL),
    ('Access Request', 'Beantragt',               'Berechtigung erteilt', '2.2', 'Express-Vergabe (Feature-Flag, ungenutzt)',      TIMESTAMP'2026-01-01 00:00:00', NULL),
    ('Data Contract',  'Entwurf erstellt',        'Review Data Owner',    '2.2', 'bis Release 2.4: Schema-Validierung optional',   TIMESTAMP'2026-01-01 00:00:00', TIMESTAMP'2026-04-06 00:00:00'),
    ('Data Contract',  'Änderung beantragt',      'Neue Version aktiv',   '2.2', 'REST-API: PATCH aktiviert neue Version direkt',  TIMESTAMP'2026-01-01 00:00:00', NULL),
    ('Data Product',   'Data Contract verknüpft', 'Freigabe Data Owner',  '2.2', 'Qualitätsprüfung überspringbar',                 TIMESTAMP'2026-01-01 00:00:00', NULL),
    ('Data Product',   'Metadaten erfasst',       'Qualitätsprüfung',     '2.2', 'Data Contract optional',                         TIMESTAMP'2026-01-01 00:00:00', NULL),
    ('Data Product',   'Metadaten erfasst',       'Freigabe Data Owner',  '2.2', 'Contract und Qualität überspringbar (ungenutzt)', TIMESTAMP'2026-01-01 00:00:00', NULL)
  AS t(process, src, tgt, since_release, note, from_ts, to_ts)
)
SELECT r.version AS release, x.process, x.src, x.tgt, x.since_release, x.note, CAST(NULL AS STRING) AS channels
FROM (SELECT * FROM base UNION ALL SELECT * FROM extra) x
JOIN releases r ON r.released_at >= x.from_ts AND (x.to_ts IS NULL OR r.released_at < x.to_ts)
