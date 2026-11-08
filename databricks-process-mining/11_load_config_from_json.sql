-- =====================================================================
-- PRODUKTION: Konfiguration aus den JSON-Dateien laden (statt der Beispielwerte in 02)
--
--   governance_model.json    -> process_model_activities, process_model_transitions
--   workflow_definition.json -> system_allowed_transitions (mit Historie, SCD Typ 2)
--
-- Ablage der Dateien z. B. in einem Unity-Catalog-Volume. Ausführung als Job nach jedem
-- Release (Workflow) bzw. jeder Freigabe des Soll-Modells (Governance).
-- HINWEIS: Databricks-spezifisch (read_files, MERGE) – lokal NICHT getestet.
-- =====================================================================

-- ---- Soll-Modell -----------------------------------------------------
CREATE OR REPLACE TEMP VIEW gm AS
SELECT explode(processes) AS p
FROM read_files('/Volumes/main/data_manager_pm/config/governance_model.json', format => 'json', multiLine => true);

CREATE OR REPLACE TABLE main.data_manager_pm.process_model_activities AS
SELECT p.process, a.name AS activity, a.step_order, a.is_terminal, a.is_control
FROM gm LATERAL VIEW explode(p.activities) x AS a;

CREATE OR REPLACE TABLE main.data_manager_pm.process_model_transitions AS
SELECT p.process, t[0] AS src, t[1] AS tgt
FROM gm LATERAL VIEW explode(p.allowed_transitions) x AS t;

-- ---- Status-Maschine (Historie behalten!) ------------------------------
CREATE OR REPLACE TEMP VIEW wf AS
SELECT w.process, t.`from` AS src, t.`to` AS tgt, t.since_release, t.note, r.release, r.released_at
FROM (SELECT explode(workflows) AS w, release
      FROM read_files('/Volumes/main/data_manager_pm/config/workflow_definition.json', format => 'json', multiLine => true)) x
JOIN main.data_manager_pm.app_releases r ON r.version = x.release
LATERAL VIEW explode(w.transitions) y AS t;

-- 1) Übergänge, die im neuen Release fehlen: schließen
MERGE INTO main.data_manager_pm.system_allowed_transitions s
USING (SELECT DISTINCT process, release, released_at FROM wf) rel
ON s.process = rel.process AND s.valid_to IS NULL
   AND NOT EXISTS (SELECT 1 FROM wf WHERE wf.process = s.process AND wf.src = s.src AND wf.tgt = s.tgt)
WHEN MATCHED THEN UPDATE SET s.valid_to = rel.released_at;

-- 2) Neue Übergänge: öffnen
INSERT INTO main.data_manager_pm.system_allowed_transitions
SELECT wf.process, wf.src, wf.tgt, wf.released_at, NULL, wf.release, wf.note
FROM wf
LEFT ANTI JOIN main.data_manager_pm.system_allowed_transitions s
  ON s.process = wf.process AND s.src = wf.src AND s.tgt = wf.tgt AND s.valid_to IS NULL;
