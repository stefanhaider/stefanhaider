SELECT process, owner, description FROM {{ dm_source('process_catalog') }}
