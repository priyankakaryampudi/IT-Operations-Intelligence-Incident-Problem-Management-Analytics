-- =====================================================================
-- 04_recurrence_detection.sql
-- Purpose : detect RECURRENCE (the same problem coming back), not just
--           volume. Documents the first attempt (asset-based), why it
--           failed, and the redesign (caller + category).
-- Reads   : incidents_final_v2 (see 02)
-- =====================================================================
USE it_incidents;

-- ---------------------------------------------------------------------
-- R1. First idea: same ASSET (cmdb_ci) + same category within 14 days.
-- Before trusting it, check whether the asset field is populated.
-- Result: '?' on 20,717 of 20,769 incidents (99.75%). Real asset ids
-- appear on only 52 incidents, at most 3 each. Asset-level recurrence
-- cannot be measured in this dataset.
-- ---------------------------------------------------------------------
SELECT cmdb_ci, COUNT(*) AS cnt
FROM incidents_final_v2
GROUP BY cmdb_ci
ORDER BY cnt DESC
LIMIT 10;

-- R2. REJECTED query: asset-based self-join.
-- Every returned row showed cmdb_ci = '?', so it matched any two
-- incidents of the same category: a meaningless join on a placeholder.
-- Kept here as the documented failure, not as a usable rule.
SELECT a.number AS incident_1, b.number AS incident_2, a.cmdb_ci, a.category,
       DATEDIFF(STR_TO_DATE(b.opened_at, '%d/%m/%Y %H:%i'),
                STR_TO_DATE(a.opened_at, '%d/%m/%Y %H:%i')) AS days_apart
FROM incidents_final_v2 a
JOIN incidents_final_v2 b
  ON a.cmdb_ci = b.cmdb_ci AND a.category = b.category AND a.number < b.number
WHERE a.cmdb_ci IS NOT NULL AND a.cmdb_ci <> ''
  AND DATEDIFF(STR_TO_DATE(b.opened_at, '%d/%m/%Y %H:%i'),
               STR_TO_DATE(a.opened_at, '%d/%m/%Y %H:%i')) BETWEEN 0 AND 14;

-- ---------------------------------------------------------------------
-- R3. Redesign: use the CALLER instead of the asset. Is it populated?
-- Result: usable, no dominant placeholder. Top callers:
--   Caller 1904 = 437 | Caller 290 = 239 | Caller 4514 = 128 |
--   Caller 4414 = 52  | Caller 3763 = 49  | Caller 90 = 49
-- ---------------------------------------------------------------------
SELECT caller_id, COUNT(*) AS cnt
FROM incidents_final_v2
GROUP BY caller_id
ORDER BY cnt DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- R4. Recurrence pairs: same caller + same category, second incident
-- opened 0-14 days after the first. Count first, do not list.
-- Result on the originally published model (v1): 73,339 pairs.
-- Result on incidents_final_v2 (corrected model, see sql/02): 73,359 —
-- recurrence is stable across the DQ-08 fix; see sql/06 for the full
-- sensitivity table. Too many to read either way: one caller with
-- hundreds of incidents produces combinatorially many pairs.
-- (a.number < b.number counts each pair once; DATEDIFF works on the
--  parsed dates because the columns are text.)
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS recurrence_pairs_14d
FROM (
    SELECT a.number AS incident_1, b.number AS incident_2
    FROM incidents_final_v2 a
    JOIN incidents_final_v2 b
      ON a.caller_id = b.caller_id
     AND a.category  = b.category
     AND a.number    < b.number
    WHERE a.caller_id IS NOT NULL AND a.caller_id <> ''
      AND DATEDIFF(STR_TO_DATE(b.opened_at, '%d/%m/%Y %H:%i'),
                   STR_TO_DATE(a.opened_at, '%d/%m/%Y %H:%i')) BETWEEN 0 AND 14
) AS pairs;

-- ---------------------------------------------------------------------
-- R5. Summarise instead of listing: how often does each caller hit each
-- category? A combination seen 3+ times is a repeating pattern.
-- Result on incidents_final_v2 (top 10 of 20):
--   Caller 1904 / Cat 51 = 399 | Caller 290 / Cat 28 = 212 |
--   Caller 4514 / Cat 28 = 47  | Caller 4514 / Cat 23 = 42 |
--   Caller 3763 / Cat 46 = 28  | Caller 1904 / Cat 46 = 26 |
--   Caller 1717 / Cat 37 = 23  | Caller 2630 / Cat 46 = 23 |
--   Caller 290  / Cat 42 = 20  | Caller 1441 / Cat 46 = 20
-- (Essentially unchanged from v1: caller_id, category and opened_at
-- don't move with the final-row fix, unlike made_sla/active/reassignment.)
-- (R5 re-checked 29 Sep 2026 on the loaded file: Caller 1904 / Cat 46 = 26,
-- not 25. Three combinations tie at 14 incidents for the last two top-20
-- slots, so the count of Category 46 callers in the top 20 is 7 or 8
-- depending on tie order; the appendix lists 8.)
-- Category 46 appears for 7-8 different callers within this top-20 list
-- (3763, 1904, 2630, 1441, 1531, 93, 2735) and for 203 callers overall
-- at the >=3 threshold: a cross-caller pattern, not one noisy account.
-- ---------------------------------------------------------------------
SELECT caller_id, category, COUNT(*) AS incident_count
FROM incidents_final_v2
WHERE caller_id IS NOT NULL AND caller_id <> ''
GROUP BY caller_id, category
HAVING COUNT(*) >= 3
ORDER BY incident_count DESC
LIMIT 20;

-- ---------------------------------------------------------------------
-- R6. Sanity check on the two extreme rows (399 and 212 incidents from
-- one caller looks like an automated source, not a person).
-- BUG FOUND: MIN/MAX on raw text returned first_seen '10/5/2016' AFTER
-- last_seen '9/5/2016' because text sorts '1' before '9'. Fixed by
-- parsing before aggregating.
-- Result: Caller 1904 spans 2016-03-05 to 2016-05-09 (437 incidents);
--         Caller 290  spans 2016-03-09 to 2016-05-12 (239 incidents).
-- Both run about two months: sustained, not a one-day burst.
-- DQ-13 note: three incidents have caller_id '?', which the joins treat as
-- a real caller. On v1 this accounts for the 1-pair gap seen between
-- 73,338 and 73,339. The published counts include them; see documentation/Data_Quality_Log.md (DQ-13).
-- ---------------------------------------------------------------------
SELECT caller_id,
       MIN(STR_TO_DATE(opened_at, '%d/%m/%Y %H:%i')) AS first_seen,
       MAX(STR_TO_DATE(opened_at, '%d/%m/%Y %H:%i')) AS last_seen,
       COUNT(*) AS total
FROM incidents_final_v2
WHERE caller_id IN ('Caller 1904', 'Caller 290')
GROUP BY caller_id;
