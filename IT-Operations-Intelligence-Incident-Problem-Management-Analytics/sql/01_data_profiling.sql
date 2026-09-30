-- =====================================================================
-- 01_data_profiling.sql
-- IT Operations Intelligence & Incident Problem Management Analytics
-- Purpose : load the raw ServiceNow event log and profile its SHAPE
--           before any analysis is attempted.
-- Engine  : MySQL 8.0+ (window functions are required from step 02)
-- Input   : incident_event_log.csv (see /data/README.md)
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS it_incidents;
USE it_incidents;

-- Every column except three integer columns (reassignment_count,
-- reopen_count, sys_mod_count) is loaded as text on purpose. A raw import should never
-- fail or silently mangle values; typing happens later (see 02 and 03).
DROP TABLE IF EXISTS incident_event_log;
CREATE TABLE incident_event_log (
    number VARCHAR(20),            incident_state VARCHAR(50),
    active VARCHAR(10),            reassignment_count INT,
    reopen_count INT,              sys_mod_count INT,
    made_sla VARCHAR(10),          caller_id VARCHAR(50),
    opened_by VARCHAR(50),         opened_at VARCHAR(50),
    sys_created_by VARCHAR(50),    sys_created_at VARCHAR(50),
    sys_updated_by VARCHAR(50),    sys_updated_at VARCHAR(50),
    contact_type VARCHAR(50),      location VARCHAR(50),
    category VARCHAR(50),          subcategory VARCHAR(50),
    u_symptom VARCHAR(100),        cmdb_ci VARCHAR(50),
    impact VARCHAR(20),            urgency VARCHAR(20),
    priority VARCHAR(20),          assignment_group VARCHAR(50),
    assigned_to VARCHAR(50),       knowledge VARCHAR(10),
    u_priority_confirmation VARCHAR(10), notify VARCHAR(20),
    problem_id VARCHAR(50),        rfc VARCHAR(50),
    vendor VARCHAR(50),            caused_by VARCHAR(50),
    closed_code VARCHAR(50),       resolved_by VARCHAR(50),
    resolved_at VARCHAR(50),       closed_at VARCHAR(50)
);

-- Bulk load. If the server refuses ("local data is disabled"), enable it:
--   SET GLOBAL local_infile = 1;   and connect with:  mysql --local-infile=1
LOAD DATA LOCAL INFILE '<PATH>/incident_event_log.csv'
INTO TABLE incident_event_log
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- ---------------------------------------------------------------------
-- P1. How many ROWS are there?
-- Result in this project: 119,998
-- NOTE: this is the number of event records, NOT the number of incidents.
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS event_rows FROM incident_event_log;

-- ---------------------------------------------------------------------
-- P2. How many distinct INCIDENTS are there?
-- Result: 20,769  (about 5.8 event rows per incident)
-- The gap between P1 and P2 proves the file is an event log.
-- ---------------------------------------------------------------------
SELECT COUNT(DISTINCT number) AS distinct_incidents FROM incident_event_log;

-- ---------------------------------------------------------------------
-- P3. Which incidents were touched the most?
-- Result: the maximum is 58 rows (INC0019396); the top 5 sit at 43-58.
-- ---------------------------------------------------------------------
SELECT number, COUNT(*) AS row_count
FROM incident_event_log
GROUP BY number
ORDER BY row_count DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- P4. Distribution of rows per incident.
-- Result: the largest group is incidents with exactly 3 rows (4,942);
-- only one incident has a single row. Multi-row is the norm, not noise.
-- ---------------------------------------------------------------------
SELECT row_count, COUNT(*) AS num_incidents
FROM (
    SELECT number, COUNT(*) AS row_count
    FROM incident_event_log
    GROUP BY number
) AS incident_rows
GROUP BY row_count
ORDER BY row_count;

-- ---------------------------------------------------------------------
-- P5. What does "finished" look like?
-- Result: New, Active, Awaiting User Info, Awaiting Problem,
-- Awaiting Vendor, Awaiting Evidence, Resolved, Closed, and -100.
-- Two terminal states exist (Resolved AND Closed), and -100 is an
-- anonymisation artefact. Filtering on state = 'Closed' would silently
-- drop incidents that only reached Resolved, so state is NOT used to
-- pick the final row (see 02).
-- ---------------------------------------------------------------------
SELECT DISTINCT incident_state FROM incident_event_log;

-- ---------------------------------------------------------------------
-- P6. Date format check.
-- Result: values look like '29/2/2016 11:29' (D/M/YYYY, day first, no
-- zero padding) stored as TEXT. MySQL cannot do date maths or correct
-- ordering on this. Every date is parsed with:
--   STR_TO_DATE(col, '%d/%m/%Y %H:%i')
-- ---------------------------------------------------------------------
SELECT resolved_at FROM incident_event_log LIMIT 10;

-- ---------------------------------------------------------------------
-- P7. Placeholder audit. Missing values are stored as the literal '?'.
-- (Run after 02 so counts are per incident. Figures on incidents_final_v2,
-- run on incidents_final_v2 — see DQ-08. cmdb_ci is unchanged from v1; category
-- and assignment_group shifted slightly with the corrected row selection.)
--   cmdb_ci          : '?' on 20,717 of 20,769 incidents (99.75%)
--   category         : '?' on 7 incidents (was 10 on v1)
--   assignment_group : '?' on 2,157 incidents (was 2,205 on v1)
-- ---------------------------------------------------------------------
SELECT 'cmdb_ci' AS field, SUM(cmdb_ci = '?') AS placeholder_rows, COUNT(*) AS total FROM incidents_final_v2
UNION ALL
SELECT 'category',          SUM(category = '?'),                   COUNT(*) FROM incidents_final_v2
UNION ALL
SELECT 'assignment_group',  SUM(assignment_group = '?'),           COUNT(*) FROM incidents_final_v2;
