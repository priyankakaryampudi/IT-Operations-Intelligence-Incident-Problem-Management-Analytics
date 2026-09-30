# Data Dictionary

**Project:** IT Operations Intelligence & Incident Problem Management Analytics
**Source table:** `incident_event_log` (raw, one row per incident *event*)
**Analytical model:** `incidents_final_v2` (one row per *incident*, DQ-08-corrected; see `sql/02_incident_level_model.sql`)

Definitions describe the standard ServiceNow meaning of each field. The dataset is anonymised, so identifiers such as callers, groups, categories and assets are opaque labels (`Caller 1904`, `Group 70`, `Category 46`). 33 of the 36 columns are loaded as text and three as integers and typed at query time.

## 1. Raw fields

| # | Field | Loaded as | Meaning | Used in this project |
|---|-------|-----------|---------|----------------------|
| 1 | `number` | text | Incident identifier (`INC0019396`). Repeats across event rows. | Key. Grouping and de-duplication. |
| 2 | `incident_state` | text | Workflow state at this event: New, Active, Awaiting User Info / Problem / Vendor / Evidence, Resolved, Closed, and `-100` (unknown). | Profiled only. **Not** used to choose the final row (two terminal states exist). |
| 3 | `active` | text | `true` while the incident is open. | Backlog measure. |
| 4 | `reassignment_count` | int | Times the incident was reassigned between groups/people. | Routing and ownership evidence. |
| 5 | `reopen_count` | int | Times a resolved incident was reopened. | Fix-quality evidence. |
| 6 | `sys_mod_count` | int | Running count of modifications to the record. | Tie-breaker for the final row. |
| 7 | `made_sla` | text | `true` if the SLA target was met, `false` if breached. | SLA breach rate. |
| 8 | `caller_id` | text | Affected user or account that raised the incident. | Recurrence dimension. |
| 9 | `opened_by` | text | Who logged the incident. | Not used. |
| 10 | `opened_at` | text | Time the incident was opened. Format `D/M/YYYY HH:MM`. | Resolution time, recurrence windows. |
| 11 | `sys_created_by` | text | System field: record creator. | Not used. |
| 12 | `sys_created_at` | text | System field: record creation time. | Not used. |
| 13 | `sys_updated_by` | text | System field: last updater. | Not used. |
| 14 | `sys_updated_at` | text | Time of this event row. Format `D/M/YYYY HH:MM`. | Final-row selection (see DQ-08). |
| 15 | `contact_type` | text | Channel used to raise the incident. | Not used. |
| 16 | `location` | text | Location code. | Not used. |
| 17 | `category` | text | Incident category (`Category 46`). `?` = missing. | Volume, resolution, recurrence. |
| 18 | `subcategory` | text | Finer classification. | Not used. |
| 19 | `u_symptom` | text | Reported symptom. | Not used. |
| 20 | `cmdb_ci` | text | Affected configuration item (asset). `?` on 99.75% of incidents. | Tested for recurrence, then rejected (DQ-06). |
| 21 | `impact` | text | Business impact rating. | Not used. |
| 22 | `urgency` | text | Urgency rating. | Not used. |
| 23 | `priority` | text | Priority derived from impact and urgency. | Volume by priority (query B2). |
| 24 | `assignment_group` | text | Group that owns the incident (`Group 70`). `?` = missing. | SLA by group, ownership analysis. |
| 25 | `assigned_to` | text | Individual assignee. | Not used. |
| 26 | `knowledge` | text | Whether a knowledge article was used. | Not used. |
| 27 | `u_priority_confirmation` | text | Priority confirmation flag. | Not used. |
| 28 | `notify` | text | Notification setting. | Not used. |
| 29 | `problem_id` | text | Linked problem record, if any. | Not used. |
| 30 | `rfc` | text | Linked change request, if any. | Not used. |
| 31 | `vendor` | text | Vendor involved, if any. | Not used. |
| 32 | `caused_by` | text | Change that caused the incident, if any. | Not used. |
| 33 | `closed_code` | text | Closure code. | Not used. |
| 34 | `resolved_by` | text | Who resolved the incident. | Not used. |
| 35 | `resolved_at` | text | Resolution time. Format `D/M/YYYY HH:MM`. | Resolution time. |
| 36 | `closed_at` | text | Closure time. | Not used. |

## 2. Derived fields and measures

| Name | Where | Definition |
|------|-------|------------|
| `incidents_final` | SQL view | One row per incident: the row with the latest `sys_updated_at` sorted as **text**, ties broken by highest `sys_mod_count`. 20,769 rows. Superseded — kept for the DQ-08 before/after comparison. |
| `incidents_final_v2` | SQL view | Same rule, but ordered on the *parsed* timestamp (corrects DQ-08). **The published model.** 20,769 rows; picks a different row than v1 for 8,018 incidents. |
| Resolution hours | SQL / DAX | `TIMESTAMPDIFF(HOUR, opened_at, resolved_at)` on parsed dates, resolved incidents only. |
| Breached | SQL / DAX | Incidents with `made_sla = 'false'`. |
| SLA breach rate | SQL / DAX | Breached / total incidents. Overall, on `incidents_final_v2`: 8,174 / 20,769 = **39.4%** (was 3,517 / 20,769 = 16.9% on the pre-correction model). |
| Backlog | SQL / DAX | Incidents with `active = 'true'`. On `incidents_final_v2`: 1 = **0.0%** (was 8,019 = 38.6% on the pre-correction model — see DQ-11). |
| Recurrence pair | SQL / Python | Two incidents with the same `caller_id` and `category`, the later opened 0 to 14 days after the earlier one (`DATEDIFF` on parsed dates), each pair counted once. |
| Repeat incident | Python | An incident whose caller + category had an earlier incident inside the window (chronological rule used for the automation simulation). |

## 3. Value conventions

- `?` is the placeholder for a missing value (not a real category, group or asset).
- `-100` in `incident_state` is an anonymisation artefact meaning unknown.
- Dates are day-first and not zero-padded (`29/2/2016 11:29`). Always parse with `STR_TO_DATE(col, '%d/%m/%Y %H:%i')`.
