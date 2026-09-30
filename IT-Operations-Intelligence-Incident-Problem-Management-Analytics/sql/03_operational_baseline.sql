-- =====================================================================
-- 03_operational_baseline.sql
-- Purpose : describe normal operational performance BEFORE looking for
--           problems: volume, resolution speed, SLA reliability, backlog.
-- Reads   : incidents_final_v2 (one row per incident, DQ-08 corrected, see 02)
-- Reading rules applied to results (not in the SQL):
--   * SLA by group: ignore groups with < 100 incidents (small-n noise)
--   * resolution time: ignore categories with < 40 incidents
--   * '?' is a missing-value placeholder, never a real category/group
-- =====================================================================
USE it_incidents;

-- B1. Volume by category
-- Top 10 on incidents_final_v2:
--   Cat 26 (2,823) | 42 (2,814) | 53 (2,345) | 46 (1,993) | 32 (1,276)
--   Cat 9 (940) | 37 (936) | 23 (879) | 20 (869) | 57 (731)
SELECT category, COUNT(*) AS incident_count
FROM incidents_final_v2
GROUP BY category
ORDER BY incident_count DESC;

-- B2. Volume by priority
SELECT priority, COUNT(*) AS incident_count
FROM incidents_final_v2
GROUP BY priority
ORDER BY incident_count DESC;

-- B3. Resolution time by category (dates are text: parse them first)
-- Standouts (n >= 40) on incidents_final_v2:
--   Cat 34 = 1,383 h (~57.6 days, n = 439) | Cat 55 = 674 h (n = 106) |
--   Cat 22 = 530 h (n = 47) | Cat 45 = 479 h (n = 526) |
--   Cat 46 = 334 h (n = 1,919) | Cat 19 = 291 h | Cat 24 = 278 h |
--   Cat 61 = 188 h | Cat 57 = 169 h
SELECT category,
       AVG(TIMESTAMPDIFF(HOUR,
           STR_TO_DATE(opened_at,   '%d/%m/%Y %H:%i'),
           STR_TO_DATE(resolved_at, '%d/%m/%Y %H:%i'))) AS avg_resolution_hours,
       COUNT(*) AS incident_count
FROM incidents_final_v2
WHERE resolved_at IS NOT NULL AND resolved_at <> ''
GROUP BY category
ORDER BY avg_resolution_hours DESC;

-- B4. SLA breach rate by assignment group, on incidents_final_v2
-- (DQ-08 corrected; run 29 Sep 2026, n >= 100 shown, breach % desc;
-- 31 rows incl. '?', reproduced independently in pandas on the loaded file):
--   Grp 10 85.6% (271) | Grp 37 78.9% (133) | Grp 31 73.8% (168)
--   Grp 66 69.2% (334) | Grp 72 68.8% (298) | Grp 57 67.7% (254)
--   Grp 22 66.7% (141) | Grp 29 66.5% (200) | Grp 33 64.0% (172)
--   Grp 76 61.8% (165) | Grp 20 59.6% (342) | Grp 65 59.5% (252)
--   Grp 6 58.6% (220) | Grp 25 57.2% (1,080) | Grp 48 55.1% (138)
--   Grp 5 54.5% (123) | ? 51.4% (2,157) | Grp 28 50.0% (478)
--   Grp 54 50.0% (152) | Grp 73 49.4% (502) | Grp 56 43.8% (128)
--   Grp 27 43.6% (436) | Grp 23 42.3% (745) | Grp 55 41.1% (246)
--   Grp 30 39.4% (236) | Grp 58 39.0% (123) | Grp 24 37.2% (907)
--   Grp 39 36.2% (995) | Grp 46 33.3% (129) | Grp 70 18.6% (7,369)
--   Grp 64 10.9% (695)
-- Original v1 figures (superseded, see README "Data quality, resolved"):
--   Grp 5 32.5% | Grp 48 32.4% | Grp 66 31.7% | Grp 12 31.1% | Grp 37 30.7% |
--   Grp 31 29.0% | Grp 22 28.7% | '?' 28.3% | Grp 57 27.6% | Grp 72 26.4% |
--   Grp 73 25.7% | Grp 29 25.0% | Grp 70 8.4% (7,189).
SELECT assignment_group,
       COUNT(*) AS total_incidents,
       SUM(CASE WHEN made_sla = 'false' THEN 1 ELSE 0 END) AS breached,
       ROUND(SUM(CASE WHEN made_sla = 'false' THEN 1 ELSE 0 END)
             / COUNT(*) * 100, 1) AS breach_rate_pct
FROM incidents_final_v2
GROUP BY assignment_group
ORDER BY breach_rate_pct DESC;

-- B5. Overall SLA breach rate (the benchmark for B4 and for KPI targets)
-- Result on incidents_final_v2 (corrected): 8,174 breached of 20,769 = 39.4% (confirmed by B5; earlier documents said ~8,183)
-- Original v1 result (superseded): 3,517 breached of 20,769 = 16.9%
SELECT SUM(made_sla = 'false') AS breached,
       COUNT(*)                AS total,
       ROUND(SUM(made_sla = 'false') / COUNT(*) * 100, 1) AS breach_rate_pct
FROM incidents_final_v2;

-- B6. Backlog: incidents still flagged active
-- Result on incidents_final_v2 (corrected): 1 (0.0% of 20,769) — the state
-- is "New". The 38.6% backlog originally published was itself a DQ-08
-- artifact: the buggy final-row rule was picking a mid-lifecycle row for
-- most incidents instead of their actual closing row. There is no real
-- backlog in this dataset once the correct row is selected.
-- Original v1 result (superseded): 8,019 (38.6% of 20,769).
SELECT COUNT(*) AS still_open FROM incidents_final_v2 WHERE active = 'true';

-- B7. Backlog ageing: oldest open incidents. Not meaningful on v2 — only
-- one incident is still open (see B6) — kept for reference and to show
-- the query still runs cleanly against the corrected view.
SELECT number, STR_TO_DATE(opened_at, '%d/%m/%Y %H:%i') AS opened
FROM incidents_final_v2
WHERE active = 'true'
ORDER BY opened
LIMIT 20;
