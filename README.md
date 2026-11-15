# Dubai Real Estate Intelligence

An end-to-end analytics project on Dubai Land Department (DLD) transaction data for 2026 (1 January to 4 November): a Python cleaning pipeline, a SQL Server database with duplicate protection, reporting views, and a five-page Power BI dashboard.

> **Data note:** the raw DLD file and the Power BI file (which embeds data) are not included in this repository. TODO: add the official data source link and confirm its licence before sharing either.

## Dashboard

<!-- TODO: add screenshots to docs/images/ and keep these lines -->
| Overview | Area analysis |
|---|---|
| ![Overview](docs/images/overview.png) | ![Area](docs/images/area.png) |

| Property analysis | Transaction trends |
|---|---|
| ![Property](docs/images/property.png) | ![Trends](docs/images/trends.png) |

Data Quality page: `docs/images/data_quality.png`

## Key findings

All figures are for eligible sales transactions (see [Metric definitions](#metric-definitions)).

1. **Scale:** 136K eligible sales worth AED 415.9bn, an average of AED 3.06M per transaction and AED 1,974 per sq ft (apartments and villas).
2. **Apartments dominate by count:** 106K transactions (77.8%), against about 11K each for land and villas.
3. **Sales value is concentrated in a few communities:** Business Bay leads with AED 22.9bn, followed by Madinat Al Mataar (18.5bn) and Al Yelayiss 1 (16.7bn).
4. **Value rank is not price rank:** Palm Jumeirah (AED 4,367 per sq ft), Palm Jabal Ali (3,578) and Burj Khalifa (3,321) are the most expensive per sq ft, while Madinat Al Mataar, 2nd by value, is among the cheapest of the top 10 (1,612). Large total value there comes from volume, not high prices.
5. **Activity slowed after the first quarter:** monthly sales fell from about 17K in January and February to about 10K in May, recovered to 14K in June and July, then sat at 11-12K from August to October.
6. **Communities move differently:** Madinat Al Mataar grew month by month through spring (782 in January to over 1,200 in May), while Jumeirah Village Circle and Al Yelayiss 1 fell over the same months.

These are descriptions of one partial year. They show no year-on-year growth and no seasonality (see [Limitations](#limitations)).

## Architecture

```
DLD CSV  ->  Python cleaning  ->  SQL Server  ->  rpt views  ->  Power BI
(data/raw)   (src/cleaning.py)    raw / stg /      (sql/08)      (5 pages)
                                  core / ops
```

- **raw:** the CSV exactly as read. **stg:** cleaned rows. **core:** deduplicated fact and dimension tables. **ops:** run log and data-quality results.
- **Duplicate protection, two layers:** the whole file is fingerprinted (SHA-256) so reloading the same file is skipped; each row also has a hash so overlapping files only insert new rows.
- **Nothing is silently deleted.** Exact duplicates are kept and flagged, and rows with implausible prices are excluded from KPIs but stay in the database.

## Repository layout

| Path | What it holds |
|---|---|
| `src/` | `config.py` (all business rules and thresholds), `cleaning.py`, `loading.py`, `db.py`, `run_pipeline.py` (full pipeline), `run_cleaning.py` (cleaning only) |
| `sql/` | Numbered scripts 01-09: database, tables, indexes, checks, load procedure, reporting views |
| `docs/` | `cleaning_rules.md`, `database_design.md`, `kpi_definitions.md` |
| `notebooks/` | Investigation and cleaning-decision notebooks (outputs cleared) |
| `reports/` | Data-quality reports per loaded file |
| `logs/` | Local pipeline run log (not committed) |

## How to run

**Requirements:** Python 3.11+ (pandas 3.x), SQL Server with SSMS, and Microsoft ODBC Driver 18 for SQL Server.

1. Install packages:
   ```
   pip install -r requirements.txt
   ```
2. Copy `.env.example` to `.env` and set `DRE_SQL_SERVER` (your server name) and `DRE_SQL_DATABASE` (`DubaiRealEstate`).
3. In SSMS, run the scripts in `sql/` in order, 01 to 09. Script 06 creates the load procedure `ops.usp_load_core`, which the pipeline needs. Script 07 runs post-load checks and 09 checks that the views reconcile.
   (If you run the pipeline first, the load fails with "Could not find stored procedure"; run script 06 and retry.)
4. Put the DLD CSV in `data/raw/`, then run:
   ```
   python src/run_pipeline.py
   ```
   or pass a path: `python src/run_pipeline.py data/raw/transactions-2026-11-04.csv`
5. Open the Power BI report and click **Refresh**. Update the date slicers if you loaded newer data.

Running the pipeline a second time on the same file prints `SKIPPED` and inserts nothing.

## Metric definitions

Full details are in [`docs/kpi_definitions.md`](docs/kpi_definitions.md).

- **Eligible sales transaction:** group = Sales, counted once per transaction number, price per sq ft not flagged implausible. Mortgages and gifts are never included.
- **Price per sq ft:** apartments and villas only; total value divided by total area in sq ft (size-weighted).
- **Reliable area price:** shown only for communities with at least 30 eligible apartment/villa sales.
- **Partial month:** November 2026 holds data through 4 November only and is never compared with complete months.

## Data quality at a glance

- 184,851 rows read; 0 rejected.
- 273 raw area spellings standardised to 268 areas.
- 469 rows with implausible prices excluded from KPIs and 188 flagged for review.
- `MASTER_PROJECT_EN` is almost entirely empty and is dropped from the cleaned table; nearest metro and mall are about half empty.

## Limitations

- **One partial year** (to 4 November): no year-on-year growth, no seasonality.
- **Area unit is assumed:** `ACTUAL_AREA` is treated as square metres (see `docs/cleaning_rules.md`, rule R5). TODO: confirm in the official DLD data dictionary.
- **Price thresholds are judgement calls** (100 / 300 / 10,000 / 50,000 AED per sq ft), set in `src/config.py`.
- **Total sales value includes land and commercial units**, so it is not "residential market value".
- **Off-plan and ready sales sit in different communities**, so their price gap is not like-for-like.
- Rental yield cannot be calculated from sales data.

## Possible next steps

- Off-plan vs ready view and a community volume ranking in the dashboard.
- Automated tests for the cleaning rules.
- Scheduled pipeline runs and incremental monthly loads.
