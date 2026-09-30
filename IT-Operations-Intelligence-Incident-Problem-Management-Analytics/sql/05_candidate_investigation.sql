-- =====================================================================
-- 05_candidate_investigation.sql
-- Purpose : investigate the two candidate patterns with evidence from
--           the data, building the chain
--   observed fact -> pattern -> contributing factor -> hypothesis
--   -> what needs validation
-- This is hypothesis-building. The data cannot prove causation.
-- =====================================================================
USE it_incidents;

-- ---------------------------------------------------------------------
-- CANDIDATE 1 : Category 46 recurring across many callers
-- ---------------------------------------------------------------------

-- C1. Who handles Category 46, and how well?
-- Result on incidents_final_v2: spread over 37 named groups plus
-- unassigned (38 rows). The largest, Group 70, handles 294 of 1,993
-- incidents (about 15%).
--   avg reassignments 0.05 to 1.57 across the 12 largest groups (1,689 of
--     1,993 incidents, 85%); dataset-wide average 0.99 (C7a) — Category
--     46's own average (0.92, C5) is close to, not above, that average
--   avg reopens near zero in almost every group (fixes hold)
--   breach rates vary 24.8% to 78.2% among groups with n >= 100
SELECT assignment_group,
       COUNT(*)                          AS total_incidents,
       AVG(reassignment_count)           AS avg_reassignments,
       AVG(reopen_count)                 AS avg_reopens,
       SUM(CASE WHEN made_sla = 'false' THEN 1 ELSE 0 END) AS breached,
       ROUND(SUM(CASE WHEN made_sla = 'false' THEN 1 ELSE 0 END)
             / COUNT(*) * 100, 1)        AS breach_rate_pct
FROM incidents_final_v2
WHERE category = 'Category 46'
GROUP BY assignment_group
ORDER BY total_incidents DESC;

-- C2. How fragmented is ownership? (expected: 38 rows = 37 named groups plus unassigned)
SELECT COUNT(DISTINCT assignment_group) AS groups_handling_cat46,
       COUNT(*)                         AS incidents
FROM incidents_final_v2
WHERE category = 'Category 46';

-- C3. How many different callers raise Category 46 repeatedly?
-- Result on v2: 15 callers at 10+ each, from
-- Caller 3763 (28) down to Caller 1663 (10).
SELECT caller_id, COUNT(*) AS incident_count
FROM incidents_final_v2
WHERE category = 'Category 46'
GROUP BY caller_id
HAVING COUNT(*) >= 10
ORDER BY incident_count DESC;

-- ---------------------------------------------------------------------
-- CANDIDATE 2 : Caller 1904 + Category 51
-- ---------------------------------------------------------------------

-- C4. Who handles it, and is there any variation in handling?
-- Result: ALL 399 incidents went to Group 64, average reassignments
-- 0.0000, average reopens 0.0000, 22 breached SLA. Perfectly uniform
-- handling is consistent with a system-generated or highly standardised source.
SELECT assignment_group,
       COUNT(*)                AS total_incidents,
       AVG(reassignment_count) AS avg_reassignments,
       AVG(reopen_count)       AS avg_reopens,
       SUM(CASE WHEN made_sla = 'false' THEN 1 ELSE 0 END) AS breached
FROM incidents_final_v2
WHERE caller_id = 'Caller 1904' AND category = 'Category 51'
GROUP BY assignment_group
ORDER BY total_incidents DESC;

-- ---------------------------------------------------------------------
-- MONITORING BASELINES (the "before" numbers for the KPIs)
-- ---------------------------------------------------------------------

-- C5. Category 46 baselines, on incidents_final_v2 (DQ-08 corrected).
-- Result: 0.9237 avg reassignments, 54.1% breach, n=1,993
-- (dataset-wide breach rate for comparison, on v2: 39.4%, see 03 query B5)
-- Original v1 figures (superseded): 0.8343 avg reassignments, 25.9% breach.
SELECT AVG(reassignment_count) AS baseline_avg_reassignments,
       ROUND(SUM(CASE WHEN made_sla = 'false' THEN 1 ELSE 0 END)
             / COUNT(*) * 100, 1) AS baseline_sla_breach_pct
FROM incidents_final_v2
WHERE category = 'Category 46';

-- C6. Caller 1904 / Category 51 baseline. Result: 399
SELECT COUNT(*) AS baseline_incident_count
FROM incidents_final_v2
WHERE caller_id = 'Caller 1904' AND category = 'Category 51';

-- C7. Comparator for the Category 46 reassignment baseline.
-- STATUS: run on v2, 24 Sep 2026.
-- C7a result: dataset-wide avg reassignments 0.9880, breach 39.4%, n=20,769.
-- Honest finding: Category 46's own average (0.9237, C5) is BELOW the
-- dataset-wide average, not above it — the reassignment figure does not
-- support "high", and the write-up should not claim it does. The breach
-- rate (54.1% vs 39.4% overall, C5) is the stronger piece of evidence.
-- C7a. Dataset-wide averages (same measures as C5).
SELECT ROUND(AVG(reassignment_count), 4) AS all_avg_reassignments,
       ROUND(SUM(CASE WHEN made_sla = 'false' THEN 1 ELSE 0 END)
             / COUNT(*) * 100, 1)        AS all_breach_pct,
       COUNT(*)                          AS all_incidents
FROM incidents_final_v2;

-- C7b. The same two measures per category (40+ incidents, D-06), ranked,
-- so the position of Category 46 is visible.
-- Result: Category 46 ranks 18th of 26 categories by avg reassignments
-- (top: Category 13 at 2.36, Category 34 at 1.78). It is mid-to-low on
-- this measure, which is why C7a's finding matters for the write-up.
SELECT category,
       COUNT(*)                          AS incidents,
       ROUND(AVG(reassignment_count), 4) AS avg_reassignments,
       ROUND(SUM(CASE WHEN made_sla = 'false' THEN 1 ELSE 0 END)
             / COUNT(*) * 100, 1)        AS breach_pct
FROM incidents_final_v2
WHERE category <> '?'
GROUP BY category
HAVING COUNT(*) >= 40
ORDER BY avg_reassignments DESC;

-- C8. How much of Category 46 is repeat reporting by the same caller?
-- STATUS: run on v2, 24 Sep 2026.
-- Result: 1,079 of 1,993 incidents (54.1%) come from the 203 callers who
-- raised Category 46 three or more times. The originally estimated
-- lower bound (8%, from just the top-20 overall list) badly understated
-- this — most of Category 46 is repeat reporting, not one-off tickets.
SELECT SUM(CASE WHEN n >= 3 THEN n ELSE 0 END) AS incidents_from_callers_with_3plus,
       COUNT(CASE WHEN n >= 3 THEN 1 END)      AS callers_with_3plus,
       SUM(n)                                  AS category46_incidents
FROM (SELECT caller_id, COUNT(*) AS n
      FROM incidents_final_v2
      WHERE category = 'Category 46'
      GROUP BY caller_id) t;

