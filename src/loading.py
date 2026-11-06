"""
loading.py - everything that touches SQL Server during a load.

Flow for one new file:
    create run row -> raw.transactions -> stg.transactions -> ops.usp_load_core -> ops.dq_results -> close run row
Duplicate protection (two layers):
    1. file_hash: the exact same file is never loaded twice.
    2. row_hash : a row already in core.fact_transactions is never inserted again (handles overlapping files).
"""
import hashlib

import pandas as pd

import config

CHUNK = 20_000

STG_COLUMNS = [
    "run_id", "row_hash", "source_file", "source_row_number", "transaction_number",
    "transaction_datetime", "transaction_date", "transaction_month", "is_partial_month",
    "transaction_group", "procedure_name", "is_offplan", "is_freehold", "usage_type",
    "area_name", "property_type", "property_subtype", "property_category", "project_name",
    "rooms", "parking", "nearest_metro", "nearest_mall", "nearest_landmark",
    "total_buyers", "total_sellers", "transaction_value_aed", "procedure_area_sqm",
    "actual_area_sqm", "actual_area_sqft", "price_per_sqft", "price_flag",
    "is_primary_row", "is_sales_kpi_row", "is_price_kpi_row",
]
CLEAN_TO_STG = {"procedure": "procedure_name", "usage": "usage_type"}
BOOL_COLUMNS = ["is_partial_month", "is_offplan", "is_freehold",
                "is_primary_row", "is_sales_kpi_row", "is_price_kpi_row"]


# ------------------------------------------------------------ fingerprints
def file_sha256(path):
    """SHA-256 fingerprint of the whole file (read in chunks so memory stays small)."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def compute_row_hashes(raw):
    """
    One SHA-256 per CSV row, built from the ORIGINAL text of all 22 columns plus an occurrence number.
    The occurrence number matters: 463 rows are identical in every column, and each must get its own hash.
    """
    text = raw[config.EXPECTED_COLUMNS].fillna("")
    key = text.iloc[:, 0]
    for col in text.columns[1:]:
        key = key + "\x1f" + text[col]
    occurrence = key.groupby(key).cumcount()
    final = key + "\x1e" + occurrence.astype(str)
    return pd.Series([hashlib.sha256(s.encode("utf-8")).hexdigest() for s in final], index=raw.index)


# ------------------------------------------------------------ preparing rows
def _to_python_rows(df, columns):
    """DataFrame -> list of tuples with plain Python values (None for missing). pyodbc needs this."""
    cols = []
    for c in columns:
        s = df[c].astype(object)
        s = s.where(df[c].notna(), None)
        cols.append(s.tolist())
    return list(zip(*cols))


def prepare_raw_rows(raw, run_id, source_file):
    rows = _to_python_rows(raw, config.EXPECTED_COLUMNS)
    return [(run_id, source_file, i + 1) + r for i, r in enumerate(rows)]


def prepare_stage_rows(clean, run_id):
    df = clean.copy()
    df.insert(0, "run_id", run_id)
    df = df.rename(columns=CLEAN_TO_STG)
    df["transaction_datetime"] = df["transaction_datetime"].dt.strftime("%Y-%m-%d %H:%M:%S")
    df["transaction_date"] = df["transaction_date"].dt.strftime("%Y-%m-%d")
    df["transaction_month"] = df["transaction_month"].dt.strftime("%Y-%m-%d")
    for c in BOOL_COLUMNS:
        df[c] = df[c].astype("Int64")        # True/False -> 1/0, missing stays missing
    return _to_python_rows(df, STG_COLUMNS)


def prepare_dq_rows(metrics_df, run_id):
    rows = []
    for section, metric, value in metrics_df.itertuples(index=False):
        try:
            rows.append((run_id, str(section)[:60], str(metric)[:200], float(value), None))
        except (TypeError, ValueError):
            rows.append((run_id, str(section)[:60], str(metric)[:200], None, str(value)[:200]))
    return rows


# ------------------------------------------------------------ database steps
def find_successful_run(cur, file_hash):
    cur.execute("SELECT TOP 1 run_id FROM ops.pipeline_runs WHERE file_hash = ? AND status = 'SUCCESS'", file_hash)
    row = cur.fetchone()
    return row[0] if row else None


def create_run(cur, path, file_hash, status, message=None):
    cur.execute(
        "INSERT INTO ops.pipeline_runs (started_at, source_file, file_size_bytes, file_hash, status, message) "
        "OUTPUT INSERTED.run_id VALUES (SYSDATETIME(), ?, ?, ?, ?, ?)",
        path.name, path.stat().st_size, file_hash, status, message)
    return cur.fetchone()[0]


def finish_run(cur, run_id, status, rows_read=None, rows_rejected=None,
               rows_inserted=None, rows_skipped=None, message=None):
    cur.execute(
        "UPDATE ops.pipeline_runs SET finished_at = SYSDATETIME(), status = ?, rows_read = ?, rows_rejected = ?, "
        "rows_inserted = ?, rows_skipped_existing = ?, message = ? WHERE run_id = ?",
        status, rows_read, rows_rejected, rows_inserted, rows_skipped, (message or "")[:1000] or None, run_id)


def _bulk_insert(cur, sql, rows):
    cur.fast_executemany = True
    for i in range(0, len(rows), CHUNK):
        cur.executemany(sql, rows[i:i + CHUNK])


def load_raw(cur, rows):
    cols = ", ".join(f"[{c}]" for c in config.EXPECTED_COLUMNS)
    marks = ", ".join("?" * (3 + len(config.EXPECTED_COLUMNS)))
    sql = f"INSERT INTO [raw].[transactions] (run_id, source_file, source_row_number, {cols}) VALUES ({marks})"
    _bulk_insert(cur, sql, rows)


def load_stage(cur, rows):
    cur.execute("TRUNCATE TABLE [stg].[transactions]")
    cols = ", ".join(f"[{c}]" for c in STG_COLUMNS)
    marks = ", ".join("?" * len(STG_COLUMNS))
    _bulk_insert(cur, f"INSERT INTO [stg].[transactions] ({cols}) VALUES ({marks})", rows)


def merge_core(cur, run_id):
    """Calls the stored procedure; returns how many NEW fact rows were inserted."""
    cur.execute("SET NOCOUNT ON; DECLARE @ins INT; "
                "EXEC ops.usp_load_core @run_id = ?, @rows_inserted = @ins OUTPUT; SELECT @ins;", run_id)
    return cur.fetchone()[0]


def save_dq(cur, rows):
    _bulk_insert(cur, "INSERT INTO ops.dq_results (run_id, section, metric, value_numeric, value_text) "
                      "VALUES (?, ?, ?, ?, ?)", rows)
