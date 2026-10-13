"""
Profile simulated VELOOP Excel workbooks.
Usage:
  python profile_veloop_data.py workbook1.xlsx [workbook2.xlsx ...]

Requires pandas and openpyxl. Outputs CSV summaries beside the first workbook.
All supplied VELOOP datasets are simulated/fictional; do not present results as
production performance metrics. Repeated IDs are flags for review, not automatic
proof of a data defect (foreign keys may repeat legitimately).
"""
import os
import sys
import pandas as pd


def profile_workbook(path):
    workbook = pd.ExcelFile(path)
    summary, missingness, repeated_ids = [], [], []
    for sheet in workbook.sheet_names:
        df = pd.read_excel(path, sheet_name=sheet)
        summary.append({
            "workbook": os.path.basename(path),
            "sheet": sheet,
            "rows": len(df),
            "columns": len(df.columns),
            "missing_cells": int(df.isna().sum().sum()),
            "duplicate_full_rows": int(df.duplicated().sum()),
        })
        for col in df.columns:
            missing_count = int(df[col].isna().sum())
            if missing_count:
                missingness.append({
                    "workbook": os.path.basename(path),
                    "sheet": sheet,
                    "field": str(col),
                    "missing_count": missing_count,
                    "missing_pct": round(100 * missing_count / max(len(df), 1), 2),
                })
            if "id" in str(col).lower():
                nonnull = df[col].dropna()
                repeated_count = int(nonnull.duplicated().sum())
                if repeated_count:
                    repeated_ids.append({
                        "workbook": os.path.basename(path),
                        "sheet": sheet,
                        "field": str(col),
                        "repeated_values": repeated_count,
                        "review_note": "Confirm key semantics; repeats can be valid for foreign keys.",
                    })
    return summary, missingness, repeated_ids


def main(paths):
    all_summary, all_missingness, all_repeated_ids = [], [], []
    for path in paths:
        s, m, r = profile_workbook(path)
        all_summary.extend(s)
        all_missingness.extend(m)
        all_repeated_ids.extend(r)

    output_dir = os.path.dirname(os.path.abspath(paths[0]))
    pd.DataFrame(all_summary).to_csv(os.path.join(output_dir, "profile_summary.csv"), index=False)
    pd.DataFrame(all_missingness).to_csv(os.path.join(output_dir, "missingness.csv"), index=False)
    pd.DataFrame(all_repeated_ids).to_csv(os.path.join(output_dir, "repeated_id_checks.csv"), index=False)
    print("Profiling complete. Inspect field semantics before treating flags as defects.")
    print("Reminder: supplied VELOOP workbooks contain simulated/fictional data.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("Usage: python profile_veloop_data.py workbook1.xlsx [workbook2.xlsx ...]")
    main(sys.argv[1:])
