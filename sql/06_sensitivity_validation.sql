-- =====================================================================
-- 06_sensitivity_validation.sql
-- Purpose : test how sensitive the recurrence finding is to the window
--           choice (7 / 14 / 30 days) and to the two extreme callers,
--           and provide the SQL side of the SQL-vs-Python reconciliation
--           (python/recurrence_validation.py is the other side).
--
-- RESULTS LOG
--   Run against the real file, 24 Sep 2026. All cells below reconcile
--   with the independent Python implementation (recurrence_validation.py).
--
--   window | V1 pairs  | V2 flagged (%)   | V3 pairs excl. 1904/290 | V4 pairs (v2 view)
--   -------+-----------+------------------+-------------------------+-------------------
--    7     | 51,007    | 4,213 (20.3%)    | 7,291 (v2)              | 51,014
--   14     | 73,339    | 5,238 (25.2%)    | 9,647 (v2)              | 73,359
--   30     | 100,642   | 6,406 (30.8%)    | 13,322 (v2)             | 100,701
--
--   V3 flagged incidents excl. 1904/290 (python, parsed): 3,555 / 4,578 / 5,745,
--   i.e. 22.8% of the 20,093 remaining incidents at 14 days (25.2% with them in).
--   V2 flagged on v2: 4,213 / 5,238 / 6,406. Old v1 flags (superseded, kept
--   as a note): 4,210 / 5,228 / 6,380.
--
--   Recurrence barely moves between v1 and v2 (DQ-08 does not meaningfully
--   affect it, unlike SLA and backlog). V2 flagged % at 14 days (25.2%; 5,238 of 20,769 on v2) is
--   the reproducible basis for the dashboard's "Recurrence Rate" card;
--   see dashboard/README.md.
--
--   14-day V1 = 73,339 is the originally published figure (04 / R4);
--   Reconcile with Python (same file, same final-row mode as the view used):
--     python python/recurrence_validation.py --input data/incident_event_log.csv \
--            --final-row-mode parsed --expect-14d-pairs 73359 --expect-14d-flagged 5238
--   V1, V2 and V3 use the calendar-day difference (DATEDIFF) in both SQL and
--   Python, so they should match exactly. Any difference is a logic error to
--   investigate, not rounding.
-- =====================================================================
USE it_incidents;

-- V1. Pair counts per window (same definition as 04 / R4).
-- Expected 14-day value: 73,339 (v1, kept for the DQ-08 comparison).
SELECT w.window_days,
       COUNT(*) AS recurrence_pairs
FROM (SELECT 7 AS window_days UNION ALL SELECT 14 UNION ALL SELECT 30) w
JOIN incidents_final a
JOIN incidents_final b
  ON a.caller_id = b.caller_id
 AND a.category  = b.category
 AND a.number    < b.number
WHERE a.caller_id IS NOT NULL AND a.caller_id <> ''
  AND DATEDIFF(STR_TO_DATE(b.opened_at, '%d/%m/%Y %H:%i'),
               STR_TO_DATE(a.opened_at, '%d/%m/%Y %H:%i')) BETWEEN 0 AND w.window_days
GROUP BY w.window_days
ORDER BY w.window_days;

-- V2. Incident-level view: how many INCIDENTS have at least one earlier
-- incident from the same caller + category inside the window?
-- (This is the number an automated flag would actually raise.)
SELECT w.window_days,
       COUNT(DISTINCT b.number)                                AS incidents_flagged,
       ROUND(COUNT(DISTINCT b.number) / (SELECT COUNT(*) FROM incidents_final_v2) * 100, 1)
                                                               AS pct_of_all_incidents
FROM (SELECT 7 AS window_days UNION ALL SELECT 14 UNION ALL SELECT 30) w
JOIN incidents_final_v2 a
JOIN incidents_final_v2 b
  ON a.caller_id = b.caller_id
 AND a.category  = b.category
 AND STR_TO_DATE(a.opened_at, '%d/%m/%Y %H:%i') < STR_TO_DATE(b.opened_at, '%d/%m/%Y %H:%i')
WHERE a.caller_id IS NOT NULL AND a.caller_id <> ''
  AND DATEDIFF(STR_TO_DATE(b.opened_at, '%d/%m/%Y %H:%i'),
               STR_TO_DATE(a.opened_at, '%d/%m/%Y %H:%i')) BETWEEN 0 AND w.window_days
GROUP BY w.window_days
ORDER BY w.window_days;

-- V3. Robustness (on incidents_final_v2): repeat V1 excluding the two suspected automated
-- sources. If the picture survives, the finding is not driven by them.
SELECT w.window_days, COUNT(*) AS recurrence_pairs_excl_1904_290
FROM (SELECT 7 AS window_days UNION ALL SELECT 14 UNION ALL SELECT 30) w
JOIN incidents_final_v2 a
JOIN incidents_final_v2 b
  ON a.caller_id = b.caller_id
 AND a.category  = b.category
 AND a.number    < b.number
WHERE a.caller_id NOT IN ('', 'Caller 1904', 'Caller 290')
  AND DATEDIFF(STR_TO_DATE(b.opened_at, '%d/%m/%Y %H:%i'),
               STR_TO_DATE(a.opened_at, '%d/%m/%Y %H:%i')) BETWEEN 0 AND w.window_days
GROUP BY w.window_days
ORDER BY w.window_days;

-- V4. Model sensitivity: repeat V1 on incidents_final_v2 (see 02) by
-- replacing the table name. Any difference from V1 measures the impact
-- of the final-row ordering limitation (DQ-08).
