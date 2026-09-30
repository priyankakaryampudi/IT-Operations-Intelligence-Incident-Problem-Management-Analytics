# Analysis Walkthrough: the story, script by script

This is the project told in the order it happened. Each chapter follows the same shape: **the question**, **the script**, **what it showed**, **what went wrong or what was decided**, and **what it led to**. Every number is taken from the other documents in this repository; nothing new is claimed here.

## Where this project comes from

During my internship at Protiviti, while working on a client engagement, I noticed that incident management wasn't handled through any formal system. When something went wrong, it was simply communicated verbally: someone would flag it to the person responsible, and it would get resolved, informally, without being logged anywhere. It worked, in the sense that things got fixed.

But it made me pause and ask: what if a bigger incident came up, one that needed real investigation rather than a quick fix? And what if the same kind of issue kept happening, quietly, in the background, with no one able to see that pattern because nothing was ever recorded? There was no way to know.

That question stayed with me, and it's what this project is built around: what becomes visible once incidents are actually captured, and what you can do with that visibility. The analysis itself runs on a separate, real, anonymised, publicly available ServiceNow incident dataset (not the client's own data), so that the question could be answered end to end without touching anything confidential.

## The story in one paragraph

A ServiceNow log looked like an incident table but was really an event log, so the first job was to build a trustworthy one-row-per-incident model. On that model, normal performance was measured: volume alone was not the problem, but Category 34 was very slow and three groups missed SLA far more than the rest. The real question was which problems *come back*. The obvious idea (same asset breaking twice) failed because the asset field is 99.75% empty, so recurrence was redefined by caller and category. That surfaced two very different patterns: a category with no clear owner (Category 46) and a suspiciously uniform stream of tickets (Caller 1904 / Category 51). Each was written as fact, pattern and hypothesis, given a different intervention type, an owner and a baseline KPI. Finally the recurrence rule was tested for sensitivity and re-implemented in Python.

## The whole chain at a glance

| Step | Script | Question asked | What it showed | What it led to |
|------|--------|----------------|----------------|----------------|
| 1 | `sql/01_data_profiling.sql` | What is the shape of this file? | 119,998 rows but 20,769 incidents; dates are day-first text; `?` marks missing values | The file is an event log; it must be collapsed before any counting |
| 2 | `sql/02_incident_level_model.sql` | How do we get one row per incident? | First attempt gave 22,136 rows; a tie-breaker gave exactly 20,769. Later found the tie-break rule sorted dates as text (DQ-08) and built a corrected `incidents_final_v2` | `incidents_final_v2` is the published model; every figure below is on v2 |
| 3 | `sql/03_operational_baseline.sql` | What does normal look like? | 39.4% SLA breach; Category 34 about 58 days; Groups 10, 37, 31 lead breach at 74-86% | Volume alone does not identify the problem; go looking for recurrence |
| 4 | `sql/04_recurrence_detection.sql` | Which problems keep coming back? | Asset idea rejected (99.75% missing); caller + category gives 73,359 pairs | Summarise instead of list; two patterns stand out |
| 5 | `sql/05_candidate_investigation.sql` | Why might each pattern repeat? | Category 46: 37 named groups plus unassigned, no clear owner. Caller 1904 / Category 51: 399 identical tickets, one group | Two hypotheses, two different interventions, three baseline KPIs |
| 6 | `sql/06_sensitivity_validation.sql` and `python/recurrence_validation.py` | Does the finding depend on the window or on two extreme callers? | Run at 7/14/30 days on v1 and v2: recurrence is stable (73,339 → 73,359 pairs at 14 days) even though SLA and backlog were not | The check that turns a finding into a robust finding |
| 7 | `dashboard/`, `process/`, the three PDFs | How do we communicate and act on it? | Three pages, AS-IS to TO-BE, executive brief | A decision, an owner and a metric for each pattern |

---

## Chapter 1: Is this really incident data? (`sql/01`)

**Question.** Before analysing anything, what does the file actually contain?

**What the script does.** Loads every column as text except three integer columns (so the import cannot fail or mangle values), then profiles the shape: row count, distinct incidents, rows per incident, incident states, date format, placeholders.

**What it showed.**
- P1 and P2: **119,998 rows but 20,769 distinct incidents**, about 5.8 rows each.
- P3 and P4: one incident has 58 rows (INC0019396); the most common case is exactly 3 rows (4,942 incidents). Multiple rows are normal, not noise.
- P5: two terminal states (`Resolved` and `Closed`) plus an artefact value `-100`.
- P6: dates look like `29/2/2016 11:29`, day-first text.
- P7: `?` stands for missing. `cmdb_ci` (asset) is `?` on 20,717 incidents, `assignment_group` on 2,157 (was 2,205 pre-DQ-08), `category` on 7 (was 10).

**Why it matters.** Counting rows would measure how often incidents were *touched*, not how many occurred. This is DQ-01 to DQ-05 in the Data Quality Log.

**Led to.** A model with one row per incident.

## Chapter 2: Building the unit of analysis (`sql/02`)

**Question.** Which single row best represents each incident?

**What the script does.** Uses `ROW_NUMBER() OVER (PARTITION BY number ORDER BY sys_updated_at DESC, sys_mod_count DESC)` and keeps rank 1, creating the view `incidents_final`.

**What went wrong, and the fix.** The first version returned **22,136 rows instead of 20,769**, because some incidents had two rows tied on the same timestamp. Adding `sys_mod_count DESC` as a tie-breaker reconciled the count exactly (decisions D-03, D-04). Choosing by time, not by `state = 'Closed'`, avoids dropping incidents that only reached `Resolved`.

**The open issue.** `sys_updated_at` is text, so it sorts alphabetically. That is DQ-08. The script provides `incidents_final_v2` (parsed ordering) and a diagnostic that counts incidents where the two views pick a different row. v1 is superseded and kept for the DQ-08 comparison; the two rules pick a different row for 8,018 of 20,769 incidents, and v2 is the published model.

**Led to.** Every later query reads from this view, never from the raw table.

## Chapter 3: What does normal look like? (`sql/03`)

**Question.** Before hunting for problems, what is normal performance?

**What the script does.** Volume by category (B1) and priority (B2), resolution time by category (B3), SLA breach by group (B4), overall breach (B5), backlog (B6), backlog ageing (B7). Results are read with minimum sample sizes: groups with 100+ incidents, categories with 40+ (D-06), and `?` is never treated as a real group.

**What it showed.**
- **Volume alone does not identify the problem.** Categories 26, 42 and 53 carry the load (2,823, 2,814, 2,345) but resolve in roughly 90 to 130 hours (4 to 5 days) on average.
- **One resolution-time outlier.** Category 34 averages 1,383 hours (about 58 days on both models) over 439 incidents, roughly twice the next slowest meaningful category.
- **SLA reliability is uneven** — and worse than first published. On the corrected model (`incidents_final_v2`, see DQ-08), 8,174 of 20,769 breached (39.4%), not the originally reported 16.9%. Group 10 leads at 85.6%, with Groups 37 and 31 close behind (78.9%, 73.8%). Group 70 handles 7,369 incidents at 18.6% — far below the overall rate despite by far the largest volume, so scale and reliability can coexist, just at different numbers than first thought.
- **Ownership gap.** Incidents with no assignment group recorded breach SLA at 51.4% on the corrected model (1,108 of 2,157) (v1: 28.3% of 2,205) — a finding in itself, since unrecorded ownership is exactly the routing problem the framework looks for.
- **Backlog — resolved, not just reported.** The originally published 38.6% backlog was itself the DQ-08 bug: on the corrected model, only **1 record (0.0%)** still shows as open: INC0029233, which carries resolved and closed timestamps and is most likely not a real open ticket. See Data Quality Log, DQ-11.
- Category 46 is high volume (1,993) with a moderate resolution time: flagged as "check against SLA and recurrence next".

**Led to.** A slow category is not the same as a *recurring* problem. The next question is what comes back.

## Chapter 4: Which problems keep coming back? (`sql/04`)

**Question.** Where does the same problem repeat, soon after the first time?

**Attempt 1: same asset, same category (R1, R2).** The plan was a self-join on `cmdb_ci` and category within 14 days. Every returned row showed `?` as the asset, so it was matching any two incidents in a category. The coverage check explained why: only 52 incidents carry a real asset, at most 3 each. **The idea was rejected and documented, not worked around** (D-07, DQ-06).

**Attempt 2: same caller, same category (R3 to R6).**
- R3: the caller field is populated. Top callers: Caller 1904 (437), Caller 290 (239), Caller 4514 (128).
- R4: the join returns **73,339 pairs** within 14 days on the original model (73,359 on the DQ-08-corrected model — recurrence barely moves). Too many to read, because one caller with hundreds of incidents creates combinatorially many pairs (DQ-09).
- R5: so summarise instead of list. Combinations seen 3+ times: **Caller 1904 / Category 51 = 399** and **Caller 290 / Category 28 = 212**, far above the rest. Category 46 also appears across at least eight different callers.
- R6: is that extreme volume a short burst? The first query returned a first-seen date *after* the last-seen date, because dates were compared as text (DQ-07). Parsing first gave the true spans: about two months each (Caller 1904, 5 March to 9 May 2016). Sustained, not a one-day spike.

**Why 14 days.** Seven may miss slow repeats; 30 risks catching unrelated incidents that share a category; 14 is a common operational cycle (D-08). It is a judgement, which is why Chapter 6 exists.

**Led to.** Two candidates, chosen for depth over breadth (D-11): the cleanest systemic story (Category 46) and the most concentrated one (Caller 1904 / Category 51). Caller 290 / Category 28 and the Caller 4514 combinations are logged as next candidates.

## Chapter 5: Fact, pattern, hypothesis (`sql/05`)

**Question.** For each candidate, what does the evidence say, and how far can it be pushed?

**Candidate 1: Category 46 (C1 to C3, C5).**
- Fact: 1,993 incidents spread over **37 named assignment groups plus unassigned**; the largest, Group 70, handles 294 (14.8%, the lowest top-group share of any category with 100+ incidents).
- Pattern: reassignments near the dataset average (0.92 vs 0.99 overall, `sql/05` C7a — not a differentiator); breach **54.1% against 39.4% overall** (the real signal); reopens near zero.
- Hypothesis: no clearly defined owning team, so tickets are routed reactively. Classified as a **routing and ownership** problem; proposed owner Service Desk / IT Governance.
- Needs validation: what Category 46 represents, and whether a triage rule can be defined.

**Candidate 2: Caller 1904 / Category 51 (C4, C6).**
- Fact: 399 incidents in about two months.
- Pattern: **all 399 went to Group 64**, reassignments 0.0000, reopens 0.0000, 22 breached. Completely uniform handling.
- Hypothesis: may be a system or service account logging one condition repeatedly; requires validation. Classified as an **automation opportunity**; proposed owner Automation / Platform team with Group 64.
- Needs validation: person or automated source, and what triggers each ticket.

**Why two different fixes matters.** Treating both as "a slow category" would have missed that one is about *who owns it* and the other about *whether a human should be handling it at all*. Each finding is written as a hypothesis, because the data shows association and cannot prove cause (D-12).

**Baselines before recommendations (D-14).** Category 46 reassignments 0.9237 and breach 54.1% (on `incidents_final_v2`; the originally published 0.8343 / 25.9% were on the pre-correction model); Caller 1904 / Category 51 volume 399 (unchanged between models).

## Chapter 6: Is the finding robust? (`sql/06` and `python/`)

**Question.** Would a different window, or removing the two extreme callers, change the conclusion?

**SQL side (`sql/06`).**
- V1: pair counts for 7, 14 and 30 days (14-day value: 73,339 on the original model).
- V2: how many *incidents* an automated flag would raise, and what share of all incidents that is.
- V3: the same as V1 excluding Callers 1904 and 290. If the picture survives, it is not driven by them.
- V4: repeat on `incidents_final_v2` to measure the DQ-08 effect.

**Python side (`python/recurrence_validation.py`).** An independent re-implementation of the same rule, doing three jobs: **reconcile** (reproduce the SQL pair count), **sensitivity** (7/14/30 days, optional caller exclusion), and **simulate** (walk incidents in time order, flag repeats, write them to CSV). Two implementations of one definition expose logic errors in either.

**Status, stated plainly.** All of V1 to V4 have now been run against the real file, at 7, 14 and 30 days, on both models — the full results log is at the top of `sql/06`. Headline: recurrence is stable across the window choice and across the DQ-08 fix (14-day: 73,339 pairs on v1, 73,359 on v2; 5,228 vs 5,238 incidents flagged, both 25.2%). Excluding Callers 1904 and 290 (V3) cuts the 14-day pair count by about 87% (73,359 to 9,647), so the pair count is dominated by them; the incident-level repeat rate falls only from 25.2% to about 22.8%. The Python script was tested on synthetic data first (SQLite stand-in, brute-force counts, tied timestamps, boundary gaps, out-of-order incident numbers — all matched) before being run against the real file, where it reconciled to the SQL figures above.

**Reading the results.** The interpretation guide in the Analytical Appendix (Section E) says what each outcome would mean, for example: if the top combinations stay stable across windows, the two candidates are not an artefact of the window.

**Reconciling.** V1, V2 and V3 use the calendar-day difference (`DATEDIFF`) in both SQL and Python, so they should match exactly. An earlier version of the Python flag rule used exact elapsed time and could not reconcile with V2 (a pair 14.92 days apart counted in SQL but not in Python); it was aligned and logged as D-18. Any mismatch on the real file is a logic error to investigate.

## Chapter 7: From findings to decisions (`dashboard/`, `process/`, PDFs)

| Artefact | Story chapter it presents |
|----------|---------------------------|
| Dashboard page 1, Operations overview | Chapter 3: normal performance and where it breaks |
| Dashboard page 2, Recurrence intelligence | Chapter 4: how recurrence was measured and what came back |
| Dashboard page 3, Action board | Chapter 5: pattern, intervention, owner, KPI, what needs validation |
| `process/AS_IS_Process.png`, `TO_BE_Process.png` | The change: from resolving verbally with no record to flagging repeats and routing them to root-cause review |
| `01_Executive_Brief.pdf` | The whole story on three pages, with three decisions requested |
| `02_End_to_End_Case_Study.pdf` | The whole story with method |
| `03_Analytical_Appendix.pdf` | The query results behind it |

**The closed loop.** Each pattern has a KPI with a baseline and a direction that would count as success. If the metric does not improve, the pattern is revisited. That is what separates this from a one-off report.

---

## Telling it in 60 seconds

"I took a real ServiceNow log and found it was an event log: 120,000 rows but only 20,769 incidents, so I built a one-row-per-incident model and reconciled it exactly. On that, normal performance looked fine except for one very slow category and a few groups missing SLA. But slow is not recurring, so I tried to measure repeats by asset, found the field was 99.75% empty, and redefined it by caller and category. That surfaced two patterns that need opposite fixes: a category with no clear owner, and a stream of 399 identical tickets that looks automated. For each I set an intervention, an owner and a baseline metric, and I tested the recurrence rule for sensitivity and re-implemented it in Python. The findings are hypotheses, and the write-up says exactly what a service desk would need to confirm."

## Where the story is still thin

These are the honest edges, so a reviewer hears them from you first.

1. **Category 46's reassignment rate is not the differentiator it first looked like.** Now run (`sql/05` C7a/C7b): 0.92 is close to the dataset-wide average of 0.99 and ranks 18th of 26 categories. The breach rate (54.1% vs 39.4% overall) is the evidence that actually holds up; the write-up above has been corrected to say so rather than lead with reassignments.
2. **Category 46 is more repeat-reporting than first estimated.** `sql/05` C8, now run: 54.1% of Category 46 (1,079 of 1,993 incidents) comes from 203 callers who raised it 3+ times — well above the original 8% lower bound, which only counted the top-20 overall list.
3. **Synced state.** The SQL, Python and documentation are on `incidents_final_v2`. The dashboard's recurrence figures (Recurrence Rate, Matching Pairs) come from `sql/06` V2 and V4; see `dashboard/README.md`.
