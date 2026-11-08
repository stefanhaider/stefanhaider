SELECT release, process, src, tgt, since_release, note, channels
FROM {{ dm_source('workflow_transition') }}
