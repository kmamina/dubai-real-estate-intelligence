"""
cleaning.py - the reusable cleaning functions.

Pipeline order (each step is a small function so you can explain it in an interview):
  1. load_raw            read the CSV as text, change nothing
  2. validate_schema     stop early if the file structure is wrong
  3. trim_text           remove stray spaces
  4. convert_types       text -> numbers and dates
  5. check_domains       report unexpected category values
  6. split_rejected      hard-rule failures go to a separate file
  7. standardise_area    one spelling per area
  8. build_clean_table   rename, label missing values, add flags and KPI columns
"""
from pathlib import Path

import numpy as np
import pandas as pd

import config


# ----------------------------------------------------------------- helpers
class Metrics:
    """Collects (section, metric, value) rows for the data-quality report."""

    def __init__(self):
        self.rows = []

    def add(self, section, metric, value):
        self.rows.append((section, metric, value))

    def to_frame(self):
        return pd.DataFrame(self.rows, columns=["section", "metric", "value"])


def find_input_file(arg=None):
    """Use the file given on the command line, else the newest CSV in data/raw."""
    if arg:
        path = Path(arg)
        if not path.is_absolute():
            path = Path.cwd() / path
        if not path.exists():
            raise FileNotFoundError(f"Input file not found: {path}")
        return path
    files = sorted(config.RAW_DIR.glob("*.csv"), key=lambda f: f.stat().st_mtime)
    if not files:
        raise FileNotFoundError(f"No CSV files found in {config.RAW_DIR}")
    return files[-1]


# ----------------------------------------------------------------- steps
def load_raw(path):
    # dtype=str: read everything as text so nothing is guessed or silently changed.
    return pd.read_csv(path, dtype=str)


def validate_schema(df):
    """Stop the pipeline if expected columns are missing. Extra columns only warn."""
    missing = [c for c in config.EXPECTED_COLUMNS if c not in df.columns]
    if missing:
        raise ValueError(f"Schema check failed. Missing columns: {missing}")
    return [c for c in df.columns if c not in config.EXPECTED_COLUMNS]


def trim_text(df):
    """Trim leading/trailing spaces and collapse double spaces. Returns {column: cells changed}."""
    changed = {}
    for col in df.columns:
        before = df[col]
        after = before.str.strip().str.replace(r"\s+", " ", regex=True)
        n = int((before.notna() & (before != after)).sum())
        if n:
            changed[col] = n
        df[col] = after
    return changed


def convert_types(df):
    """Text -> numbers/dates. Values that cannot convert become empty and are counted."""
    failures = {}
    for col in config.NUMERIC_COLUMNS:
        converted = pd.to_numeric(df[col], errors="coerce")
        failures[col] = int((df[col].notna() & converted.isna()).sum())
        df[col] = converted
    converted = pd.to_datetime(df["INSTANCE_DATE"], errors="coerce")
    failures["INSTANCE_DATE"] = int((df["INSTANCE_DATE"].notna() & converted.isna()).sum())
    df["INSTANCE_DATE"] = converted
    return failures


def check_domains(df):
    """Count values outside the allowed lists (reported, not deleted)."""
    out = {}
    for col, allowed in config.ALLOWED_VALUES.items():
        out[col] = int((df[col].notna() & ~df[col].isin(allowed)).sum())
    out["GROUP_EN"] = int((df["GROUP_EN"].notna() & ~df["GROUP_EN"].isin(config.ALLOWED_GROUPS)).sum())
    return out


def split_rejected(df):
    """Hard rules: a row failing any of these cannot be trusted at all."""
    is_sale = df["GROUP_EN"].eq("Sales")
    rules = {
        "missing_transaction_number": df["TRANSACTION_NUMBER"].isna() | df["TRANSACTION_NUMBER"].eq(""),
        "invalid_date": df["INSTANCE_DATE"].isna(),
        "unexpected_group": ~df["GROUP_EN"].isin(config.ALLOWED_GROUPS),
        "sales_invalid_value": is_sale & ~(df["TRANS_VALUE"] > 0),
        "sales_invalid_area": is_sale & ~(df["ACTUAL_AREA"] > 0),
    }
    reason = pd.Series("", index=df.index)
    counts = {}
    for name, mask in rules.items():
        counts[name] = int(mask.sum())
        reason = reason.where(~mask, reason + name + ";")
    rejected_mask = reason != ""
    rejected = df[rejected_mask].copy()
    rejected["reject_reason"] = reason[rejected_mask]
    return df[~rejected_mask].copy(), rejected, counts


def _standardise_name(text):
    """'DUBAI MARINA' / 'Dubai  Marina ' -> 'Dubai Marina'. Roman numerals stay uppercase."""
    roman = {"i", "ii", "iii", "iv"}
    words = []
    for w in text.split(" "):
        lw = w.lower()
        words.append(lw.upper() if lw in roman else lw.capitalize())
    return " ".join(words)


def standardise_area(series):
    mapping = {v: _standardise_name(v) for v in series.dropna().unique()}
    return series.map(mapping)


def _classify_property(ptype, subtype):
    key = (ptype, subtype)
    if key in config.PROPERTY_CATEGORY_MAP:
        return config.PROPERTY_CATEGORY_MAP[key]
    if ptype == "Land":
        return "Land"
    return "Other"


RENAME = {
    "TRANSACTION_NUMBER": "transaction_number", "INSTANCE_DATE": "transaction_datetime",
    "GROUP_EN": "transaction_group", "PROCEDURE_EN": "procedure",
    "IS_OFFPLAN_EN": "is_offplan", "IS_FREE_HOLD_EN": "is_freehold",
    "USAGE_EN": "usage", "AREA_EN": "area_name", "PROP_TYPE_EN": "property_type",
    "PROP_SB_TYPE_EN": "property_subtype", "TRANS_VALUE": "transaction_value_aed",
    "PROCEDURE_AREA": "procedure_area_sqm", "ACTUAL_AREA": "actual_area_sqm",
    "ROOMS_EN": "rooms", "PARKING": "parking", "NEAREST_METRO_EN": "nearest_metro",
    "NEAREST_MALL_EN": "nearest_mall", "NEAREST_LANDMARK_EN": "nearest_landmark",
    "TOTAL_BUYER": "total_buyers", "TOTAL_SELLER": "total_sellers",
    "PROJECT_EN": "project_name",
}
LABEL_MISSING = ["property_subtype", "rooms", "parking", "nearest_metro",
                 "nearest_mall", "nearest_landmark", "project_name"]


def build_clean_table(df, source_name, metrics):
    df = df.drop(columns=config.DROP_FROM_CLEAN).copy()

    # 1. Area names: one spelling per area
    areas_before = df["AREA_EN"].nunique()
    original_area = df["AREA_EN"]
    df["AREA_EN"] = standardise_area(df["AREA_EN"])
    metrics.add("corrected", "area_rows_respelled", int((original_area != df["AREA_EN"]).sum()))
    metrics.add("corrected", "unique_areas_before", areas_before)
    metrics.add("corrected", "unique_areas_after", df["AREA_EN"].nunique())

    # 2. Yes/No text -> real booleans
    df["IS_OFFPLAN_EN"] = df["IS_OFFPLAN_EN"].map({"Off-Plan": True, "Ready": False}).astype("boolean")
    df["IS_FREE_HOLD_EN"] = df["IS_FREE_HOLD_EN"].map({"Free Hold": True, "Non Free Hold": False}).astype("boolean")

    # 3. Property category uses the ORIGINAL type/subtype, before missing values are labelled
    df["property_category"] = [_classify_property(t, s) for t, s in zip(df["PROP_TYPE_EN"], df["PROP_SB_TYPE_EN"])]

    # 4. Rename, then label missing categorical values (never invent a value)
    df = df.rename(columns=RENAME)
    for col in LABEL_MISSING:
        n = int(df[col].isna().sum())
        if n:
            metrics.add("corrected", f"missing_labelled_not_specified_{col}", n)
        df[col] = df[col].fillna(config.NOT_SPECIFIED)

    # 5. Traceability: where did this row come from?
    df.insert(0, "source_row_number", df.index + 1)   # 1-based data row in the CSV
    df.insert(0, "source_file", source_name)

    # 6. Dates
    dt = df["transaction_datetime"]
    df["transaction_date"] = dt.dt.normalize()
    df["transaction_month"] = dt.dt.to_period("M").dt.to_timestamp()
    last_month = dt.max().to_period("M").to_timestamp()
    last_day = last_month + pd.offsets.MonthEnd(0)
    df["is_partial_month"] = (df["transaction_month"] == last_month) & (dt.max().normalize() < last_day)

    # 7. Area in sq ft and price per sq ft (Sales only)
    df["actual_area_sqft"] = df["actual_area_sqm"] * config.SQM_TO_SQFT
    is_sale = df["transaction_group"].eq("Sales")
    df["price_per_sqft"] = np.where(is_sale, df["transaction_value_aed"] / df["actual_area_sqft"], np.nan)

    # 8. Row flags
    df["is_primary_row"] = ~df.duplicated(subset=["transaction_group", "transaction_number"], keep="first")

    assessed = is_sale & df["property_category"].isin(config.PRICE_KPI_CATEGORIES)
    p = df["price_per_sqft"]
    df["price_flag"] = np.select(
        [~assessed, p < config.PPSF_INVALID_LOW, p > config.PPSF_INVALID_HIGH,
         p < config.PPSF_REVIEW_LOW, p > config.PPSF_REVIEW_HIGH],
        ["not_assessed", "invalid_low", "invalid_high", "review_low", "review_high"],
        default="ok")

    df["is_sales_kpi_row"] = is_sale & df["is_primary_row"] & ~df["price_flag"].isin(["invalid_low", "invalid_high"])
    df["is_price_kpi_row"] = df["is_sales_kpi_row"] & df["price_flag"].eq("ok") & df["property_category"].isin(config.PRICE_KPI_CATEGORIES)

    # 9. Flag counts for the report
    for grp, n in df.loc[~df["is_primary_row"]].groupby("transaction_group").size().items():
        metrics.add("flagged", f"repeat_rows_of_same_transaction_number_{grp}", int(n))
    for flag, n in df.loc[is_sale, "price_flag"].value_counts().items():
        metrics.add("flagged", f"sales_price_flag_{flag}", int(n))
    metrics.add("flagged", "rows_in_partial_month", int(df["is_partial_month"].sum()))
    metrics.add("flagged", "partial_month", last_month.strftime("%Y-%m"))
    metrics.add("kpi_populations", "sales_rows_total", int(is_sale.sum()))
    metrics.add("kpi_populations", "sales_kpi_rows (transactions and value)", int(df["is_sales_kpi_row"].sum()))
    metrics.add("kpi_populations", "price_kpi_rows (price per sq ft)", int(df["is_price_kpi_row"].sum()))

    ordered = ["source_file", "source_row_number", "transaction_number", "transaction_datetime",
               "transaction_date", "transaction_month", "is_partial_month", "transaction_group",
               "procedure", "is_offplan", "is_freehold", "usage", "area_name", "property_type",
               "property_subtype", "property_category", "project_name", "rooms", "parking",
               "nearest_metro", "nearest_mall", "nearest_landmark", "total_buyers", "total_sellers",
               "transaction_value_aed", "procedure_area_sqm", "actual_area_sqm", "actual_area_sqft",
               "price_per_sqft", "price_flag", "is_primary_row", "is_sales_kpi_row", "is_price_kpi_row"]
    return df[ordered].reset_index(drop=True)


# ----------------------------------------------------------------- orchestration
def run_pipeline(path):
    """Run every step on one CSV. Returns (clean, rejected, metrics)."""
    metrics = Metrics()
    raw = load_raw(path)
    extra = validate_schema(raw)

    metrics.add("input", "source_file", path.name)
    metrics.add("input", "rows_read", len(raw))
    metrics.add("input", "columns_read", raw.shape[1])
    metrics.add("input", "unexpected_extra_columns", ", ".join(extra) if extra else "none")
    for col, pct in (raw.isna().mean() * 100).round(1).sort_values(ascending=False).items():
        metrics.add("missing_pct_raw", col, pct)

    df = raw.copy()
    trimmed = trim_text(df)
    metrics.add("corrected", "text_cells_trimmed_total", sum(trimmed.values()))
    for col, n in trimmed.items():
        metrics.add("corrected", f"text_cells_trimmed_{col}", n)

    metrics.add("flagged", "rows_identical_in_all_columns (kept)", int(df.duplicated().sum()))

    for col, n in convert_types(df).items():
        metrics.add("type_conversion_failures", col, n)
    for col, n in check_domains(df).items():
        metrics.add("unexpected_category_values", col, n)

    kept, rejected, reject_counts = split_rejected(df)
    metrics.add("rejected", "rows_rejected_total", len(rejected))
    for rule, n in reject_counts.items():
        metrics.add("rejected", f"rule_{rule}", n)

    clean = build_clean_table(kept, path.name, metrics)
    metrics.add("input", "rows_clean", len(clean))
    return clean, rejected, metrics
