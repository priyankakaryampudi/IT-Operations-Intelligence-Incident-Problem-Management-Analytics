-- =====================================================================
-- 02_incident_level_model.sql
-- Purpose : collapse the event log (many rows per incident) into ONE row
--           per incident, holding its final recorded state.
-- Every later query in this project reads from this view, never from the
-- raw table. Counting on the raw log would count how often incidents
-- were TOUCHED, not how many incidents occurred.
-- =====================================================================
USE it_incidents;

-- ---------------------------------------------------------------------
-- v1 : SUPERSEDED. Kept for the DQ-08 comparison; v2 is the published model.
-- Rule: keep the most recently updated row per incident.
-- History: the first version ordered by sys_updated_at only and returned
-- 22,136 rows (expected 20,769) because some incidents had two rows tied
-- on the same timestamp. Adding sys_mod_count DESC as tie-breaker fixed
-- it: the count reconciles exactly to 20,769.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS incidents_final;
CREATE VIEW incidents_final AS
SELECT * FROM (
    SELECT e.*,
           ROW_NUMBER() OVER (
               PARTITION BY number
               ORDER BY sys_updated_at DESC, sys_mod_count DESC
           ) AS rn
    FROM incident_event_log e
) ranked
WHERE rn = 1;

-- Reconciliation check. Expected: 20,769 (= P2 in 01_data_profiling.sql)
SELECT COUNT(*) AS incidents_final_rows FROM incidents_final;

-- ---------------------------------------------------------------------
-- RESOLVED (logged as DQ-08 in documentation/Data_Quality_Log.md, run
-- 24 Sep 2026). sys_updated_at is TEXT in D/M/YYYY format, so ORDER BY
-- sys_updated_at sorts alphabetically, not chronologically ('29/2/2016'
-- sorts AFTER '2/3/2016'). The v1 view picks the wrong row for 8,018 of
-- 20,769 incidents (38.6%) as a result. The same class of bug was found
-- and fixed for MIN/MAX(opened_at) in 04 (query R6).
--
-- v2 below orders on the PARSED timestamp and is now the model used for
-- every published figure (03-06, README, case study, appendix,
-- dashboard). v1 is kept only so the diagnostic below, and the
-- before/after comparison in README.md, can show the effect of the bug.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS incidents_final_v2;
CREATE VIEW incidents_final_v2 AS
SELECT * FROM (
    SELECT e.*,
           ROW_NUMBER() OVER (
               PARTITION BY number
               ORDER BY STR_TO_DATE(sys_updated_at, '%d/%m/%Y %H:%i') DESC,
                        sys_mod_count DESC
           ) AS rn
    FROM incident_event_log e
) ranked
WHERE rn = 1;

-- Reconciliation check. Expected: 20,769 (same as v1 — this rule only
-- changes WHICH row is picked per incident, not how many incidents exist)
SELECT COUNT(*) AS incidents_final_v2_rows FROM incidents_final_v2;

-- Diagnostic: for how many incidents do v1 and v2 pick a different row?
-- Result: 8,018 of 20,769 (38.6%).
WITH v1 AS (
    SELECT number, sys_mod_count,
           ROW_NUMBER() OVER (PARTITION BY number
               ORDER BY sys_updated_at DESC, sys_mod_count DESC) AS rn
    FROM incident_event_log
),
v2 AS (
    SELECT number, sys_mod_count,
           ROW_NUMBER() OVER (PARTITION BY number
               ORDER BY STR_TO_DATE(sys_updated_at, '%d/%m/%Y %H:%i') DESC,
                        sys_mod_count DESC) AS rn
    FROM incident_event_log
)
SELECT COUNT(*) AS incidents_where_selected_row_differs
FROM v1 JOIN v2
  ON v1.number = v2.number AND v1.rn = 1 AND v2.rn = 1
WHERE v1.sys_mod_count <> v2.sys_mod_count;
