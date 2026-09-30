# Data

## Source

**Incident management process enriched event log**, an anonymised extract from a ServiceNow instance used by an IT company. Published on the UCI Machine Learning Repository:
https://archive.ics.uci.edu/dataset/498/incident+management+process+enriched+event+log

Also mirrored on Kaggle (search the dataset title). Check the licence and citation terms on the source page before redistributing. Cite as: *Incident management process enriched event log*, UCI Machine Learning Repository (dataset 498).

## What is in this folder

The raw CSV is **not committed** to this repository — it is a third-party dataset and redistributing it here would mean republishing someone else's data under this repo without confirming the licence terms allow it. Download it from the source above and place it here as:

```
data/incident_event_log.csv
```

The repository `.gitignore` excludes `data/*.csv`, so the file cannot be committed by accident.

`sample_rows.csv` in this folder holds a handful of **fabricated, illustrative rows** with the same column headers as the real file, so the structure is visible without downloading anything. It is not extracted from the real dataset and does not represent real incidents.

## Shape of the file used in this project

| Item | Value |
|------|-------|
| Event rows loaded | 119,998 |
| Distinct incidents (`number`) | 20,769 |
| Average rows per incident | about 5.8 (maximum 58) |
| Columns | 36 |
| Period | `opened_at` spans 29 Feb 2016 to 13 May 2016 in the loaded file |

> The public description of the source dataset quotes a larger size (141,712 events, 24,918 incidents). The file used here loaded 119,998 rows and 20,769 incidents. All figures in this repository refer to the loaded file. This is a documented discrepancy, cause not confirmed (DQ-12 in `documentation/Data_Quality_Log.md`).

## The file is an event log

Each time an incident is updated, ServiceNow writes a new row. One incident can therefore appear many times. Analysis must run on the collapsed one-row-per-incident view built in `sql/02_incident_level_model.sql`, not on the raw rows.

## Loading it

1. Create the schema and table with `sql/01_data_profiling.sql`.
2. Replace `<PATH>` in the `LOAD DATA LOCAL INFILE` statement with the absolute path to the CSV.
3. If MySQL reports "local data is disabled", run `SET GLOBAL local_infile = 1;` and connect with `mysql --local-infile=1`.
4. Confirm `SELECT COUNT(*)` returns the row count you expect for your copy of the file.

## Known quirks (details in the Data Quality Log)

- Dates are day-first text (`29/2/2016 11:29`).
- Missing values are the literal `?`.
- `cmdb_ci` (asset) is `?` on 99.75% of incidents.
- `incident_state` contains an artefact value `-100`.

## Privacy

The data is anonymised at source. Callers, groups and categories are opaque labels. Do not attempt to re-identify individuals or systems.
