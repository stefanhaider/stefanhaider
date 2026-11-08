SELECT version, CAST(released_at AS TIMESTAMP) AS released_at, notes
FROM {{ dm_source('app_release') }}
