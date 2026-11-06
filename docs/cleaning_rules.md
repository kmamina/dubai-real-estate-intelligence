# Cleaning rules (v1)

Source: `transactions-2026-11-04.csv` (DLD transactions, 184,851 rows, 22 columns, 2026-01-01 to 2026-11-04).
Raw data is never edited. Every rule below is implemented in `src/cleaning.py`; thresholds live in `src/config.py`.
Items marked **ASSUMPTION** are my judgement and should be reviewed, not treated as facts.

## R1. Only Sales rows feed price and value KPIs
| | |
|---|---|
| Issue | One file mixes Sales (136,602), Mortgage (40,283) and Gifts (7,966). |
| Why it matters | Mortgage amounts and gifts are not sale prices. Mixing them inflates every price KPI. |
| Detect | `value_counts()` on `GROUP_EN`. |
| Handle | Keep all groups in the cleaned table; KPI columns are True only for Sales. |
| Verify | Group counts add up to rows read; `sales_rows_total` = 136,602 in the quality report. |

## R2. Repeated transaction numbers are not automatically duplicates
| | |
|---|---|
| Issue | 889 transaction numbers cover 6,798 rows. Mortgage portfolios legitimately cover several properties. Inside Sales only 25 numbers repeat (2 rows each), and the rows differ only in nearest metro (24) or nearest mall (1). Some numbers also appear in two groups (a sale and a mortgage). |
| Why it matters | Summing value over repeated rows would double count. Deleting rows would lose real units. |
| Detect | `duplicated()` by group and number; compare which columns differ between the rows. |
| Handle | Keep every row. `is_primary_row` marks the first row per (group, transaction number). Sales KPIs use primary rows only. |
| Verify | `repeat_rows_of_same_transaction_number_Sales` = 25 = rows removed from Sales KPIs. |
| ASSUMPTION | The 25 Sales pairs are the same property listed once per nearby metro station. |

## R3. Rows identical in all columns are flagged, not deleted
| | |
|---|---|
| Issue | 463 rows are identical in all 22 columns (none in Sales). The file has no unit ID. |
| Why it matters | Two identical flats in one mortgage look identical but are separate units. |
| Detect | `df.duplicated()` over all columns. |
| Handle | Keep, and report the count. |
| Verify | `rows_identical_in_all_columns (kept)` = 463. |

## R4. Property category (flat, villa, commercial...)
| | |
|---|---|
| Issue | In this data a villa is `PROP_TYPE = Building` / subtype `Villa` (10,584 Sales rows), and `Unit` also contains offices, shops and hotel rooms. |
| Why it matters | Filtering on `Unit` would drop villas and mix offices into "apartments". |
| Detect | Cross-tab of `PROP_TYPE_EN` against `PROP_SB_TYPE_EN` for Sales. |
| Handle | `property_category` from a mapping in `config.py`: Apartment, Villa, Hotel Unit, Commercial Unit, Other Unit, Building, Land, Other. |
| Verify | Every row has a category; Apartment (Unit/Flat) = 106,400 Sales rows. |

## R5. Area size unit and price per sq ft
| | |
|---|---|
| Issue | `ACTUAL_AREA` has no unit stated in the file. |
| Why it matters | Price per sq ft is wrong by a factor of 10.76 if the unit is wrong. |
| Detect | Median price per sq ft after conversion. |
| Handle | Treat `ACTUAL_AREA` as square metres; sq ft = sqm x 10.7639; price per sq ft = value / sq ft (Sales only). |
| Verify | Median is about 1,709 AED/sq ft for apartments and 1,750 for villas, which is realistic. |
| ASSUMPTION | Confirm the unit in the official DLD data dictionary. |

## R6. Implausible prices
| | |
|---|---|
| Issue | Apartment/villa Sales with price per sq ft under 100 (as low as about 0.6 AED) or above 50,000 (up to about 1.2 million). Example: a 71 sqm Marina flat at 919,789,428 AED. |
| Why it matters | A few extreme rows distort totals and averages. |
| Detect | Price per sq ft distribution and the lowest/highest rows. |
| Handle | `price_flag`: invalid (<100 or >50,000) = excluded from all Sales KPIs; review (100-300 or 10,000-50,000) = kept in transaction KPIs, excluded from price-per-sq-ft KPIs; ok = used. Values are never edited. |
| Verify | Sales flags: ok 116,327; invalid_low 466; invalid_high 3; review_low 148; review_high 40; not_assessed 19,618. |
| ASSUMPTION | The four thresholds are my judgement from the observed distribution (1st percentile about 545, 99th about 4,500 for apartments). Review them. |

## R7. Area names
| | |
|---|---|
| Issue | 273 spellings for 268 areas (e.g. "BUSINESS BAY" and "Business Bay"); many names are all capitals. |
| Why it matters | The same area would appear twice in charts. |
| Detect | Compare unique names with unique lower-cased, trimmed names. |
| Handle | Trim spaces, then capitalise each word (roman numerals I, II, III, IV stay uppercase). Official DLD spellings (e.g. "Barshaa") are kept. |
| Verify | 273 before, 268 after. |
| Note | A few names may need manual touch-ups (for example "Dmcc-ez2"). |

## R8. Missing values
| | |
|---|---|
| Issue | `MASTER_PROJECT_EN` 99.6% missing; metro, mall, landmark 39-52%; parking 22.8%; rooms 14.9%; project 12.9%. |
| Why it matters | Guessing values would invent facts. Some gaps are structural (land and offices have no rooms). |
| Detect | `isna().mean()` per column. |
| Handle | Drop `MASTER_PROJECT_EN` from the cleaned table (kept in raw). Label other text gaps "Not specified". |
| Verify | Counts per column in the quality report. |

## R9. Whitespace
| | |
|---|---|
| Issue | Stray or double spaces in procedure, parking, metro and project names. |
| Handle | Trim and collapse spaces in every text column; count the cells changed (3,083). |

## R10. Hard rejection rules
Rows are moved to `rejected_<file>.csv` (not deleted from raw) if: transaction number missing, date unparseable, group not Sales/Mortgage/Gifts, or a Sales row has value or area <= 0. In this file: **0 rejected**.

## R11. Partial month
Data ends on 2026-11-04, so November 2026 is flagged `is_partial_month`. No year-on-year growth or seasonality claims.
