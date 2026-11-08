{{ config(enabled = var('use_sample_data') | as_bool, tags = ['acceptance']) }}
WITH s AS (SELECT * FROM {{ ref('mart_findings_summary') }} WHERE domain_scope = 'Alle'),
checks AS (
  SELECT 'Zeilen' AS pruefung, CAST(COUNT(*) AS STRING) AS ist, '14' AS soll FROM s
  UNION ALL SELECT 'aktive kritische', CAST(COUNT_IF(severity = 'kritisch' AND status <> 'nicht mehr aufgetreten') AS STRING), '7' FROM s
  UNION ALL SELECT 'neu', concat_ws(' | ', collect_list(concat(process, ': ', finding, ' (', cases, ', ', first_seen, ')'))),
                   'Data Product: Data Contract verknüpft, Qualitätsprüfung, Freigabe Data Owner umgangen (10, 2026-05-21)'
            FROM s WHERE status = 'neu'
  UNION ALL SELECT 'AR Security umgangen',
                   concat_ws(' | ', cases, first_seen, pct_last_4w, status, channels, first_release, system_status),
                   '90 | 2026-04-02 | 29.2 | tritt weiterhin auf | system | 2.3 | vom System erlaubt'
            FROM s WHERE finding = 'Prüfung Security umgangen'
  UNION ALL SELECT 'DC Schema validiert umgangen', concat_ws(' | ', cases, last_seen, status), '25 | 2026-03-30 | nicht mehr aufgetreten'
            FROM s WHERE finding = 'Schema validiert umgangen'
  UNION ALL SELECT 'Scopes vorhanden', CAST(COUNT(DISTINCT domain_scope) AS STRING), '5' FROM {{ ref('mart_findings_summary') }}
)
SELECT * FROM checks WHERE NOT (ist <=> soll)
