# Power BI Dashboard

Three pages, one visual language: clean and minimal, teal for the data, gold reserved for the finding, Verdana throughout, white rounded cards on a warm neutral canvas. The same palette is used in the executive brief, the case study and the process diagrams.

This folder contains only the `.pbix` — no screenshots. Open it in Power BI Desktop to view the report; the section below describes each page in full so the layout and findings are legible without opening the file.

The dashboard itself analyses a public dataset, not client or internship data. The project's origin — an internship observation at Protiviti — is explained in the main `README.md` and `02_End_to_End_Case_Study.pdf`, section 2.

| File | What it is |
|------|------------|
| `IT Operations Intelligence & Incident Problem Management Analytics.pbix` | The Power BI report (3 pages) |

## What each page answers

> **Status.** The headline corrections from DQ-08 (backlog, overall SLA, SLA by group, recurrence) are the results of the `sql/03`, `sql/04` and `sql/06` queries run on `incidents_final_v2`. The table below shows where each value comes from.

**Page 1, Operations overview.** *What does normal look like, and where does it break?* KPI cards (20,769 incidents, backlog 0.0%, recurrence rate 25.2%, average resolution hours); incidents by category (top 10); SLA breach by assignment group (groups with 100+ incidents, `?` excluded, top 10 by breach rate, Group 10 highlighted at 85.6%); average resolution by category (40+ incidents, Category 34 highlighted at about 58 days); backlog open vs closed (1 record, INC0029233, has resolved and closed timestamps and is most likely not a real open ticket). Key observations text: 58 days, breach "62% to 86%" across the worst-performing groups, fewer than 1 in 20,000 incidents open. Method: `sql/03`.

**Page 2, Recurrence intelligence.** *Which problems keep coming back, and how was that measured?* KPI cards (14-day window, 73,359 matching pairs, 99.75% of incidents with no asset); top caller + category combinations (Caller 1904 / Category 51 highlighted, 399); top callers raising Category 46 (15 callers with 10 or more each); a short note on why the method changed from asset to caller + category. Method: `sql/04`.

**Page 3, Action board.** *What happens next, who owns it, how will we know it worked?* The two candidates, with intervention type, evidence, proposed owner, baseline KPI and what needs validation. Category 46: ownership spread across 37 named groups plus unassigned, reassignments 0.05 to 1.57 across the largest groups. Caller 1904 may be a system or service account and requires validation. Method: `sql/05`.

### Where each value comes from

| Item | Source |
|---|---|
| Backlog Pct (0.0%) and the backlog donut (`BacklogCorrected`) | `sql/03` B6, run on `incidents_final_v2` |
| SLA breach by group chart (`SLABreachCorrected`) | `sql/03` B4, run on `incidents_final_v2` |
| Recurrence Rate (25.2%) | `sql/06` V2, 14 days (5,238 of 20,769) |
| Recurrence Window, Matching Pairs (73,359), No Asset Pct (99.75%) | `sql/04` R4, `sql/01` |
| Total Incidents, category charts, average resolution, caller charts | Calculated in the model from the imported incident table |

Recurrence figures come from `sql/04` and `sql/06`, because a DAX self-join over 20,769 incidents is heavy.

## Opening and refreshing the file

- The report was built on a local MySQL database (`it_incidents`, view `incidents_final`). **Refresh will fail on another machine.** To reproduce it, load the data and run the SQL as described in the main README. The imported table currently reads the `incidents_final` view; changing the source in Power Query to `incidents_final_v2` aligns the calculated items with the SQL results (the query name and measures stay the same; category volumes differ by under 1%, for example Category 26: 2,810 vs 2,823).
- The `.pbix` contains a copy of the imported incident data. Check the source licence in `data/README.md` before publishing it.

## Measures used

Table name below is `it_incidents incidents_final` (imported from MySQL schema `it_incidents`).

```DAX
Incidents = COUNTROWS('it_incidents incidents_final')

Breached = CALCULATE(COUNTROWS('it_incidents incidents_final'), 'it_incidents incidents_final'[made_sla] = "false")

SLA Breach Rate = DIVIDE([Breached], [Incidents])

Avg Resolution Days =
DIVIDE(
    AVERAGEX(
        FILTER('it_incidents incidents_final', 'it_incidents incidents_final'[resolved_at] <> BLANK()),
        DATEDIFF('it_incidents incidents_final'[opened_at], 'it_incidents incidents_final'[resolved_at], HOUR)
    ),
    24
)

Avg Resolution Hours (card) =
FORMAT(
    AVERAGEX(
        FILTER('it_incidents incidents_final', 'it_incidents incidents_final'[resolved_at] <> BLANK()),
        DATEDIFF('it_incidents incidents_final'[opened_at], 'it_incidents incidents_final'[resolved_at], HOUR)
    ),
    "#,##0"
) & " hrs"
```

`Backlog Pct`, `Recurrence Rate`, `Recurrence Window`, `Matching Pairs` and `No Asset Pct` are set from the SQL results (see the table above).

Dates arrive day-first (`29/2/2016 11:29`). Convert them in Power Query with a UK locale, or the resolution measures will return blanks.

## Design system

| Element | Value |
|---------|-------|
| Main data colour | Teal `#3D6673` |
| Highlight (findings only) | Gold `#D2B04C` |
| Canvas | Warm neutral `#EFEDE6` |
| Cards | White, thin border, rounded corners |
| Headings and key text | Dark slate `#2B3A42` |
| Body text and labels | Grey `#6B7280` |
| Font | Verdana |
| Page size | 1920 x 1080 |

## Known limitations

- The SLA and resolution charts may show a scrollbar in Power BI if Top N filters are not applied; it does not appear in an exported PDF or screenshot.
- Priority distribution is available in SQL (`03 / B2`) but is not shown in the dashboard.
- Sensitivity results (7 and 30 days, excluding callers) are recorded in the results log at the top of `sql/06`, not in the dashboard.
- Refresh needs a local MySQL database with the `it_incidents` schema.
