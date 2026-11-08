-- =====================================================================
-- Einmaliges Setup (Metastore-Admin bzw. Recht CREATE CONNECTION): Data Manager in Unity Catalog einbinden
--
-- Liest die PostgreSQL-Datenbank des Data Managers read-only als Foreign Catalog (Lakehouse Federation).
-- Datenbank-User: Rolle dm_event_reader (data_manager/python/sql/postgres/001 + 002), möglichst Read-Replica.
-- Danach liest das dbt-Projekt (../dbt) die Quellen dm_pg.governance.* – keine weitere Kopie-Logik nötig.
-- HINWEIS: Databricks-spezifisch, lokal NICHT getestet.
-- =====================================================================
-- Zugangsdaten als Databricks-Secrets (Scope 'data-manager'); User = databricks_federation (Rolle dm_event_reader).
CREATE CONNECTION IF NOT EXISTS dm_postgres TYPE postgresql
OPTIONS (
  host     secret('data-manager', 'pg-host'),      -- Read-Replica empfohlen
  port     '5432',
  user     secret('data-manager', 'pg-user'),
  password secret('data-manager', 'pg-password')
);

CREATE FOREIGN CATALOG IF NOT EXISTS dm_pg USING CONNECTION dm_postgres
OPTIONS (database 'datamanager');

-- Nur das Monitoring-Team und der Kopier-Job dürfen lesen (personenbezogene Daten: actor):
-- GRANT USE CATALOG ON CATALOG dm_pg TO `dm-monitoring-job`;
-- GRANT USE SCHEMA, SELECT ON SCHEMA dm_pg.governance TO `dm-monitoring-job`;

-- Das Data Product (Job-Service-Principal) braucht Lesezugriff auf den Foreign Catalog
-- und Schreibrechte im Ziel-Schema:
-- GRANT USE CATALOG ON CATALOG dm_pg TO `<service-principal>`;
-- GRANT USE SCHEMA, SELECT ON SCHEMA dm_pg.governance TO `<service-principal>`;
-- GRANT USE CATALOG ON CATALOG main TO `<service-principal>`;
-- GRANT USE SCHEMA, CREATE TABLE, CREATE VIEW ON SCHEMA main.process_monitoring TO `<service-principal>`;

-- Kontrolle: Vollständigkeit der Übernahme (z. B. täglich; erwartet 0)
-- SELECT COUNT(*) AS missing
-- FROM dm_pg.governance.process_event p
-- LEFT ANTI JOIN main.process_monitoring.stg_dm__process_event b ON b.event_id = CAST(p.event_id AS STRING)
-- WHERE p.recorded_at < current_timestamp() - INTERVAL 1 HOUR;

