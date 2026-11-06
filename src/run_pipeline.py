"""
run_pipeline.py - the full pipeline: clean the CSV, then load SQL Server.

Usage (from the project root):
    python src/run_pipeline.py                                    # newest CSV in data/raw
    python src/run_pipeline.py data/raw/transactions-2026-11-04.csv
"""
import datetime as dt
import sys
from contextlib import closing

import cleaning
import config
import db
import loading
from run_cleaning import append_run_log, write_report


def main():
    started = dt.datetime.now()
    local = {"run_id": started.strftime("%Y%m%d_%H%M%S"), "started_at": started.isoformat(timespec="seconds"),
             "source_file": "", "status": "FAILED", "rows_read": 0, "rows_rejected": 0, "rows_clean": 0, "message": ""}
    try:
        path = cleaning.find_input_file(sys.argv[1] if len(sys.argv) > 1 else None)
        local["source_file"] = path.name
        print(f"File: {path.name}")
        file_hash = loading.file_sha256(path)
        print(f"File fingerprint: {file_hash[:16]}...")

        with closing(db.get_connection()) as conn:
            cur = conn.cursor()

            # ---- Layer 1 of duplicate protection: has this exact file already been loaded?
            prior = loading.find_successful_run(cur, file_hash)
            if prior:
                msg = f"Same file already loaded successfully in run {prior}. Nothing to do."
                loading.create_run(cur, path, file_hash, "SKIPPED", msg)
                conn.commit()
                local.update(status="SKIPPED", message=msg)
                print("SKIPPED:", msg)
                return

            run_id = loading.create_run(cur, path, file_hash, "RUNNING")
            conn.commit()
            print(f"Run {run_id} started")

            try:
                # ---- Clean (same code as run_cleaning.py)
                clean, rejected, metrics = cleaning.run_pipeline(path)
                config.PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
                clean.to_csv(config.PROCESSED_DIR / f"clean_{path.stem}.csv", index=False)
                rejected.to_csv(config.PROCESSED_DIR / f"rejected_{path.stem}.csv", index=False)
                metrics_df = metrics.to_frame()
                write_report(metrics_df, path.name, started.strftime("%Y-%m-%d %H:%M"))
                rows_read = int(metrics_df.query("metric == 'rows_read'")["value"].iloc[0])
                print(f"Cleaned: {len(clean):,} rows ({len(rejected):,} rejected)")

                # ---- Row fingerprints (layer 2 of duplicate protection)
                raw = cleaning.load_raw(path)
                hashes = loading.compute_row_hashes(raw)
                clean["row_hash"] = hashes.loc[clean["source_row_number"] - 1].to_numpy()
                assert clean["row_hash"].is_unique, "row_hash must be unique inside one file"

                # ---- Load
                print("Loading raw.transactions ...")
                loading.load_raw(cur, loading.prepare_raw_rows(raw, run_id, path.name))
                print("Loading stg.transactions ...")
                loading.load_stage(cur, loading.prepare_stage_rows(clean, run_id))
                print("Merging into core ...")
                inserted = loading.merge_core(cur, run_id)
                skipped = len(clean) - inserted

                metrics.add("load", "rows_inserted_into_core", inserted)
                metrics.add("load", "rows_skipped_already_in_core", skipped)
                loading.save_dq(cur, loading.prepare_dq_rows(metrics.to_frame(), run_id))
                loading.finish_run(cur, run_id, "SUCCESS", rows_read, len(rejected), inserted, skipped)
                conn.commit()

                local.update(status="SUCCESS", rows_read=rows_read, rows_rejected=len(rejected), rows_clean=len(clean))
                print(f"SUCCESS. Inserted {inserted:,} new rows, skipped {skipped:,} already loaded.")
            except Exception as exc:
                conn.rollback()
                msg = f"{type(exc).__name__}: {exc}"
                loading.finish_run(cur, run_id, "FAILED", message=msg)
                conn.commit()
                local["message"] = msg
                raise
    except Exception as exc:
        local["message"] = local["message"] or f"{type(exc).__name__}: {exc}"
        print("PIPELINE FAILED:", local["message"])
        raise
    finally:
        local["finished_at"] = dt.datetime.now().isoformat(timespec="seconds")
        append_run_log(local)


if __name__ == "__main__":
    main()
