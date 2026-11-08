{{ config(enabled = var('use_sample_data') | as_bool, materialized = 'table', tags = ['sample']) }}
SELECT * FROM VALUES ('2026.1', 'Data Governance Office', DATE'2026-01-01', true)
AS t(model_version, approved_by, approved_at, is_current)
