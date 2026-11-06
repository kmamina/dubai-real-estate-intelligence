"""
config.py - every setting and business rule lives here, in one place.

Why: if a threshold or a label changes, you edit ONE file instead of hunting
through the code. It also lets an interviewer see your business rules at a glance.
"""
from pathlib import Path

# ---------- Folders (relative to the project root, so it works on any PC) ----------
PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = PROJECT_ROOT / "data" / "raw"
PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"
REPORTS_DIR = PROJECT_ROOT / "reports"
LOGS_DIR = PROJECT_ROOT / "logs"

# ---------- Business definitions ----------
SQM_TO_SQFT = 10.7639          # 1 square metre = 10.7639 square feet
NOT_SPECIFIED = "Not specified"  # label used instead of inventing missing values

# ---------- Schema: the columns we expect in every DLD file ----------
EXPECTED_COLUMNS = [
    "TRANSACTION_NUMBER", "INSTANCE_DATE", "GROUP_EN", "PROCEDURE_EN",
    "IS_OFFPLAN_EN", "IS_FREE_HOLD_EN", "USAGE_EN", "AREA_EN", "PROP_TYPE_EN",
    "PROP_SB_TYPE_EN", "TRANS_VALUE", "PROCEDURE_AREA", "ACTUAL_AREA",
    "ROOMS_EN", "PARKING", "NEAREST_METRO_EN", "NEAREST_MALL_EN",
    "NEAREST_LANDMARK_EN", "TOTAL_BUYER", "TOTAL_SELLER",
    "MASTER_PROJECT_EN", "PROJECT_EN",
]
NUMERIC_COLUMNS = ["TRANS_VALUE", "PROCEDURE_AREA", "ACTUAL_AREA", "TOTAL_BUYER", "TOTAL_SELLER"]

# Column dropped from the cleaned table (99.6% missing). It stays in the raw file.
DROP_FROM_CLEAN = ["MASTER_PROJECT_EN"]

# ---------- Allowed category values (anything else is reported, not silently accepted) ----------
ALLOWED_GROUPS = ["Sales", "Mortgage", "Gifts"]
ALLOWED_VALUES = {
    "IS_OFFPLAN_EN": ["Off-Plan", "Ready"],
    "IS_FREE_HOLD_EN": ["Free Hold", "Non Free Hold"],
    "USAGE_EN": ["Residential", "Commercial"],
    "PROP_TYPE_EN": ["Unit", "Land", "Building"],
}

# ---------- Property category (what a business user calls the property) ----------
# In DLD data a VILLA is stored as PROP_TYPE = Building / PROP_SB_TYPE = Villa,
# and "Unit" also includes offices and shops. So we map (type, subtype) -> category.
PROPERTY_CATEGORY_MAP = {
    ("Unit", "Flat"): "Apartment",
    ("Building", "Villa"): "Villa",
    ("Unit", "Hotel Apartment"): "Hotel Unit",
    ("Unit", "Hotel Rooms"): "Hotel Unit",
    ("Unit", "Office"): "Commercial Unit",
    ("Unit", "Shop"): "Commercial Unit",
    ("Unit", "Show Rooms"): "Commercial Unit",
    ("Unit", "Warehouse"): "Commercial Unit",
    ("Unit", "Workshop"): "Commercial Unit",
    ("Unit", "Gymnasium"): "Commercial Unit",
    ("Unit", "Stacked Townhouses"): "Other Unit",
    ("Building", "Building"): "Building",
}
# Anything with PROP_TYPE = Land becomes "Land"; anything unmapped becomes "Other".
PRICE_KPI_CATEGORIES = ["Apartment", "Villa"]   # price-per-sq-ft is reported only for these

# ---------- Price-per-sq-ft thresholds (AED per sq ft) - ASSUMPTIONS, reviewed against the data ----------
PPSF_INVALID_LOW = 100       # below this: almost certainly not a real market price
PPSF_REVIEW_LOW = 300        # 100 to 300: suspicious, needs review
PPSF_REVIEW_HIGH = 10_000    # 10,000 to 50,000: could be ultra-luxury or an error
PPSF_INVALID_HIGH = 50_000   # above this: impossible for a flat or villa
