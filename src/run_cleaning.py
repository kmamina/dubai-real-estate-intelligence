"""
run_cleaning.py - the command you run.

Usage (from the project root):
    python src/run_cleaning.py                                   # newest CSV in data/raw
    python src/run_cleaning.py data/raw/transactions-2026-11-04.csv
"""
import datetime as dt
import sys

import pandas as pd

import cleaning
import config


def write_report(metrics_df, source_name, stamp):
    config.REPORTS_DIR.mkdir(exist_ok=True)
    stem = source_name.rsplit(".", 1)[0]
    metrics_df.to_csv(config.REPORTS_DIR / f"data_quality_{stem}.csv", index=False)

    lines = [f"# Data quality report: {source_name}", "", f"Generated: {stamp}", ""]
    for section in metrics_df["section"].unique():
        lines += [f"## {section}", "", "| Metric | Value |", "|---|---|"]
        for _, r in metrics_df[metrics_df["section"] == section].iterrows():
            lines.append(f"| {r['metric']} | {r['value']} |")
        lines.append("")
    (config.REPORTS_DIR / f"data_quality_{stem}.md").write_text("\n".join(lines), encoding="utf-8")


def append_run_log(row):
    config.LOGS_DIR.mkdir(exist_ok=True)
    log_path = config.LOGS_DIR / "pipeline_runs.csv"
    pd.DataFrame([row]).to_csv(log_path, mode="a", header=not log_path.exists(), index=False)


def main():
    started = dt.datetime.now()
    run = {"run_id": started.strftime("%Y%m%d_%H%M%S"), "started_at": started.isoformat(timespec="seconds"),
           "source_file": "", "status": "FAILED", "rows_read": 0, "rows_rejected": 0, "rows_clean": 0, "message": ""}
    try:
        path = cleaning.find_input_file(sys.argv[1] if len(sys.argv) > 1 else None)
        run["source_file"] = path.name
        print(f"Processing: {path.name}")

        clean, rejected, metrics = cleaning.run_pipeline(path)

        config.PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
        stem = path.stem
        clean.to_csv(config.PROCESSED_DIR / f"clean_{stem}.csv", index=False)
        rejected.to_csv(config.PROCESSED_DIR / f"rejected_{stem}.csv", index=False)
        write_report(metrics.to_frame(), path.name, started.strftime("%Y-%m-%d %H:%M"))

        run.update(status="SUCCESS", rows_read=int(metrics.to_frame().query("metric == 'rows_read'")["value"].iloc[0]),
                   rows_rejected=len(rejected), rows_clean=len(clean))
        print(f"Rows read: {run['rows_read']:,} | rejected: {len(rejected):,} | clean: {len(clean):,}")
        print(f"Clean file:  data/processed/clean_{stem}.csv")
        print(f"Report:      reports/data_quality_{stem}.md")
    except Exception as exc:
        run["message"] = f"{type(exc).__name__}: {exc}"
        print("PIPELINE FAILED:", run["message"])
        raise
    finally:
        run["finished_at"] = dt.datetime.now().isoformat(timespec="seconds")
        append_run_log(run)


if __name__ == "__main__":
    main()
