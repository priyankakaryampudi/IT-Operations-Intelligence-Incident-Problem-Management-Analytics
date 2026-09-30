#!/usr/bin/env python3
"""
recurrence_validation.py
IT Operations Intelligence & Incident Problem Management Analytics

Independent re-implementation of the recurrence rule used in
sql/04_recurrence_detection.sql and sql/06_sensitivity_validation.sql.

It does three jobs:
  1. RECONCILE  - reproduce the SQL pair count (same definition), so the
                  two implementations can be compared line by line.
  2. SENSITIVITY- repeat the count for several windows (default 7/14/30)
                  and optionally exclude suspected automated callers.
  3. SIMULATE   - apply the rule the way an automated flag would: walk
                  through incidents in time order and flag any incident
                  that repeats an earlier caller + category inside the
                  window. Writes the flagged incidents to CSV.

Rules (both use the calendar-day difference, as MySQL DATEDIFF)
  Pair count      (SQL R4 / 06-V1): same caller_id AND same category AND the
                  later incident opened 0..WINDOW days after the earlier one,
                  each pair counted once (number_a < number_b).
  Incident flag   (SQL 06-V2): an incident is flagged when at least one
                  STRICTLY earlier incident (earlier timestamp) with the same
                  caller_id AND category opened 0..WINDOW calendar days before it.

Usage
    python recurrence_validation.py --input data/incident_event_log.csv
    python recurrence_validation.py --input data/incident_event_log.csv \
        --windows 7 14 30 --exclude-callers "Caller 1904" "Caller 290" \
        --expect-14d-pairs 73359 --expect-14d-flagged 5238 --out-dir python/output

Requires: pandas, numpy  (pip install pandas numpy)
"""
import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd

DATE_FMT = "%d/%m/%Y %H:%M"          # dates are D/M/YYYY HH:MM text


def load_incident_level(path: str, final_row_mode: str = "parsed") -> pd.DataFrame:
    """Collapse the event log to one row per incident (final recorded state).

    final_row_mode
      'text'   : mirrors SQL view v1  (ORDER BY sys_updated_at TEXT desc,
                 sys_mod_count desc)
      'parsed' : mirrors SQL view v2  (ORDER BY parsed timestamp desc,
                 sys_mod_count desc)  -- the corrected rule
    """
    df = pd.read_csv(path, dtype=str, keep_default_na=False)
    df["sys_mod_count"] = pd.to_numeric(df["sys_mod_count"], errors="coerce").fillna(0)
    if final_row_mode == "text":
        df = df.sort_values(["number", "sys_updated_at", "sys_mod_count"],
                            ascending=[True, False, False], kind="mergesort")
    elif final_row_mode == "parsed":
        df["_upd"] = pd.to_datetime(df["sys_updated_at"], format=DATE_FMT, errors="coerce")
        df = df.sort_values(["number", "_upd", "sys_mod_count"],
                            ascending=[True, False, False], kind="mergesort")
    else:
        raise ValueError("final_row_mode must be 'text' or 'parsed'")
    inc = df.drop_duplicates("number", keep="first").copy()
    inc["opened_dt"] = pd.to_datetime(inc["opened_at"], format=DATE_FMT, errors="coerce")
    inc["opened_day"] = inc["opened_dt"].dt.normalize()
    return inc.reset_index(drop=True)


def _eligible(inc: pd.DataFrame, exclude_callers) -> pd.DataFrame:
    m = inc["caller_id"].notna() & (inc["caller_id"] != "") & inc["opened_day"].notna()
    if exclude_callers:
        m &= ~inc["caller_id"].isin(exclude_callers)
    return inc[m]


def count_pairs(inc: pd.DataFrame, window: int, exclude_callers=None) -> int:
    """SQL-equivalent pair count for one window (see module docstring)."""
    total = 0
    for _, g in _eligible(inc, exclude_callers).groupby(["caller_id", "category"], sort=False):
        if len(g) < 2:
            continue
        g = g.sort_values("number")                       # a.number < b.number
        days = (g["opened_day"].values.astype("datetime64[D]")
                .astype("int64"))
        diff = days[None, :] - days[:, None]               # b - a
        upper = np.triu(np.ones_like(diff, dtype=bool), k=1)
        total += int(((diff >= 0) & (diff <= window) & upper).sum())
    return total


def flag_repeats(inc: pd.DataFrame, window: int, exclude_callers=None) -> pd.DataFrame:
    """Automation simulation, same rule as SQL 06-V2.

    Flag an incident when the nearest STRICTLY earlier incident from the same
    caller + category opened no more than `window` calendar days before it.
    (If the nearest earlier one is too far back, every earlier one is.)
    Incidents opened at the identical minute do not flag each other, exactly
    as `a.opened < b.opened` behaves in the SQL.
    """
    key = ["caller_id", "category"]
    e = _eligible(inc, exclude_callers).sort_values(key + ["opened_dt", "number"])
    # one row per distinct timestamp, so ties cannot point at each other
    stamps = e.drop_duplicates(key + ["opened_dt"])[key + ["opened_dt", "opened_day"]].copy()
    grp = stamps.groupby(key, sort=False)
    stamps["prev_dt"] = grp["opened_dt"].shift(1)
    stamps["prev_day"] = grp["opened_day"].shift(1)
    e = e.merge(stamps[key + ["opened_dt", "prev_dt", "prev_day"]],
                on=key + ["opened_dt"], how="left")
    e["days_since_previous"] = (e["opened_day"] - e["prev_day"]).dt.days
    e["hours_since_previous"] = ((e["opened_dt"] - e["prev_dt"]).dt.total_seconds() / 3600).round(1)
    out = e[e["prev_dt"].notna() & (e["days_since_previous"] <= window)]
    return out[["number", "caller_id", "category", "assignment_group", "opened_dt",
                "days_since_previous", "hours_since_previous"]].reset_index(drop=True)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--input", required=True, help="path to incident_event_log.csv")
    ap.add_argument("--windows", type=int, nargs="+", default=[7, 14, 30])
    ap.add_argument("--exclude-callers", nargs="*", default=[],
                    help='e.g. "Caller 1904" "Caller 290"')
    ap.add_argument("--final-row-mode", choices=["text", "parsed"], default="parsed",
                    help="text = mirrors SQL v1, parsed = mirrors SQL v2")
    ap.add_argument("--expect-14d-pairs", type=int, default=None,
                    help="published SQL value to reconcile against (73359 in parsed mode, 73339 in text mode)")
    ap.add_argument("--expect-14d-flagged", type=int, default=None,
                    help="SQL 06-V2 value for 14 days (5238 in parsed mode)")
    ap.add_argument("--out-dir", default="python/output")
    args = ap.parse_args(argv)

    inc = load_incident_level(args.input, args.final_row_mode)
    print(f"Incident-level rows : {len(inc):,}  (mode: {args.final_row_mode})")

    rows = []
    for w in args.windows:
        pairs = count_pairs(inc, w, args.exclude_callers)
        flagged = flag_repeats(inc, w, args.exclude_callers)
        rows.append({"window_days": w,
                     "pairs_sql_definition": pairs,
                     "incidents_flagged": len(flagged),
                     "pct_of_all_incidents": round(100 * len(flagged) / len(inc), 1)})
    summary = pd.DataFrame(rows)
    print("\nSensitivity summary"
          + (f"  (excluding {', '.join(args.exclude_callers)})" if args.exclude_callers else ""))
    print(summary.to_string(index=False))

    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    summary.to_csv(out / "sensitivity_summary.csv", index=False)
    flag_repeats(inc, 14, args.exclude_callers).to_csv(out / "flagged_incidents_14d.csv", index=False)

    top = (_eligible(inc, args.exclude_callers)
           .groupby(["caller_id", "category"]).size()
           .loc[lambda s: s >= 3].sort_values(ascending=False).head(20))
    top.rename("incident_count").to_csv(out / "top_caller_category.csv")
    print("\nTop caller + category combinations (>= 3 incidents)")
    print(top.head(10).to_string())

    rc = 0
    can_check = 14 in args.windows and not args.exclude_callers
    row14 = summary.loc[summary.window_days == 14] if can_check else None
    for label, col, expected in (
            ("14d pairs", "pairs_sql_definition", args.expect_14d_pairs),
            ("14d incidents flagged", "incidents_flagged", args.expect_14d_flagged)):
        if expected is None or not can_check:
            continue
        got = int(row14[col].iloc[0])
        status = "PASS" if got == expected else "FAIL"
        print(f"\nReconciliation vs SQL ({label}): python={got:,} sql={expected:,} -> {status}")
        rc = rc or (0 if status == "PASS" else 1)
    return rc


if __name__ == "__main__":
    sys.exit(main())
