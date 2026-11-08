-- Gültigkeitszeiträume der Status-Maschine aus den Release-Ständen (Gaps and Islands):
-- ein Übergang ist ab dem ersten Release einer zusammenhängenden Folge erlaubt und bis zum
-- ersten Release, in dem er fehlt (valid_to NULL = im aktuellen Release erlaubt).
WITH r AS (
  SELECT version, released_at, ROW_NUMBER() OVER (ORDER BY released_at) AS rn
  FROM {{ ref('stg_dm__app_release') }}
),
wt AS (SELECT * FROM {{ ref('stg_dm__workflow_transition') }}),
pairs AS (SELECT DISTINCT process, src, tgt FROM wt),
grid AS (
  SELECT p.process, p.src, p.tgt, r.rn, r.released_at,
         wt.release IS NOT NULL AS present, wt.note, wt.since_release
  FROM pairs p
  CROSS JOIN r
  LEFT JOIN wt ON wt.process = p.process AND wt.src = p.src AND wt.tgt = p.tgt AND wt.release = r.version
),
isl AS (
  SELECT *, rn - ROW_NUMBER() OVER (PARTITION BY process, src, tgt, present ORDER BY rn) AS grp
  FROM grid
),
runs AS (
  SELECT process, src, tgt, grp,
         MAX(rn) AS last_rn, MIN(released_at) AS valid_from,
         MAX_BY(note, rn) AS note, MAX_BY(since_release, rn) AS since_release
  FROM isl WHERE present
  GROUP BY process, src, tgt, grp
)
SELECT runs.process, runs.src, runs.tgt, runs.valid_from, nxt.released_at AS valid_to,
       runs.since_release, runs.note
FROM runs
LEFT JOIN r nxt ON nxt.rn = runs.last_rn + 1
