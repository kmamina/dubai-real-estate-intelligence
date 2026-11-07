-- 08_create_reporting_views.sql
-- Creates the [rpt] schema and the views that answer the business questions and feed Power BI.
-- A VIEW is a saved SELECT. It stores no data; it always shows the latest rows of the tables underneath.
-- Business definitions used everywhere (documented in docs/kpi_definitions.md):
--   Sales transactions / value : Sales rows with is_sales_kpi_row = 1   (counted once per transaction number,
--                                implausible prices excluded)
--   Price per sq ft            : Apartments and Villas with is_price_kpi_row = 1,
--                                SUM(value) / SUM(sq ft)  (weighted by size, so big flats count more than studios)
--   Reliable area price        : an area needs at least 30 price rows (ASSUMPTION) before its price is shown

USE [DubaiRealEstate];
GO

IF SCHEMA_ID(N'rpt') IS NULL EXEC (N'CREATE SCHEMA [rpt]');
GO

-- =====================================================================================================
-- 1. Base view: every eligible Sale, with readable names. All other sales views read from this one.
--    Concept: JOIN (fact -> dim_area, fact -> dim_property)
-- =====================================================================================================
CREATE OR ALTER VIEW [rpt].[v_sales] AS
SELECT
    f.transaction_key,
    f.transaction_number,
    f.transaction_datetime,
    f.transaction_date,
    f.transaction_month,
    f.is_partial_month,
    a.area_name,
    p.property_type,
    p.property_subtype,
    p.property_category,
    CASE f.is_offplan WHEN 1 THEN 'Off-Plan' WHEN 0 THEN 'Ready' ELSE 'Unknown' END AS sale_stage,
    f.procedure_name,
    f.rooms,
    f.project_name,
    f.transaction_value_aed,
    f.actual_area_sqm,
    f.actual_area_sqft,
    f.price_per_sqft,
    f.price_flag,
    f.is_price_kpi_row
FROM [core].[fact_transactions] AS f
JOIN [core].[dim_area]     AS a ON a.area_key = f.area_key
JOIN [core].[dim_property] AS p ON p.property_key = f.property_key
WHERE f.transaction_group = 'Sales'
  AND f.is_sales_kpi_row = 1;
GO

-- =====================================================================================================
-- 2. Executive KPIs: one row.   Concepts: CTEs, CROSS JOIN, median with PERCENTILE_CONT
-- =====================================================================================================
CREATE OR ALTER VIEW [rpt].[v_kpi_overview] AS
WITH totals AS (
    SELECT COUNT(*)                                       AS sales_transactions,
           SUM(transaction_value_aed)                     AS total_sales_value_aed,
           CAST(AVG(transaction_value_aed) AS DECIMAL(18,2)) AS avg_transaction_value_aed
    FROM [rpt].[v_sales]
),
median_value AS (
    SELECT DISTINCT CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY transaction_value_aed) OVER () AS DECIMAL(18,2))
           AS median_transaction_value_aed
    FROM [rpt].[v_sales]
),
price AS (
    SELECT COUNT(*) AS price_rows,
           CAST(CAST(SUM(transaction_value_aed) AS FLOAT) / NULLIF(CAST(SUM(actual_area_sqft) AS FLOAT), 0)
                AS DECIMAL(18,2)) AS price_per_sqft_weighted
    FROM [rpt].[v_sales]
    WHERE is_price_kpi_row = 1
),
median_price AS (
    SELECT DISTINCT CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_per_sqft) OVER () AS DECIMAL(18,2))
           AS price_per_sqft_median
    FROM [rpt].[v_sales]
    WHERE is_price_kpi_row = 1
)
SELECT t.sales_transactions, t.total_sales_value_aed, t.avg_transaction_value_aed,
       m.median_transaction_value_aed, p.price_rows, p.price_per_sqft_weighted, mp.price_per_sqft_median
FROM totals AS t
CROSS JOIN median_value AS m
CROSS JOIN price AS p
CROSS JOIN median_price AS mp;
GO

-- =====================================================================================================
-- 3. Area summary: value, volume, price per sq ft, ranks, and difference from the Dubai average.
--    Concepts: GROUP BY, conditional SUM(CASE...), RANK() OVER, comparing a row to the whole market
--    Answers: Q1 (highest value), Q2 (highest price per sq ft), Q3 (highest volume), Q8 (price differences)
-- =====================================================================================================
CREATE OR ALTER VIEW [rpt].[v_area_summary] AS
WITH area_stats AS (
    SELECT area_name,
           COUNT(*)                                                           AS sales_transactions,
           SUM(transaction_value_aed)                                         AS total_value_aed,
           CAST(AVG(transaction_value_aed) AS DECIMAL(18,2))                  AS avg_transaction_value_aed,
           SUM(CASE WHEN is_price_kpi_row = 1 THEN 1 ELSE 0 END)              AS price_sample_size,
           SUM(CASE WHEN is_price_kpi_row = 1 THEN transaction_value_aed END) AS price_value_aed,
           SUM(CASE WHEN is_price_kpi_row = 1 THEN actual_area_sqft END)      AS price_area_sqft
    FROM [rpt].[v_sales]
    GROUP BY area_name
),
with_price AS (
    SELECT area_name, sales_transactions, total_value_aed, avg_transaction_value_aed, price_sample_size,
           CASE WHEN price_sample_size >= 30
                THEN CAST(CAST(price_value_aed AS FLOAT) / NULLIF(CAST(price_area_sqft AS FLOAT), 0) AS DECIMAL(18,2))
           END AS price_per_sqft
    FROM area_stats
),
market AS (
    SELECT CAST(SUM(price_value_aed) AS FLOAT) / NULLIF(CAST(SUM(price_area_sqft) AS FLOAT), 0) AS market_price_per_sqft
    FROM area_stats
),
ranked AS (
    SELECT w.*, m.market_price_per_sqft,
           RANK() OVER (ORDER BY w.total_value_aed DESC)     AS rank_by_value,
           RANK() OVER (ORDER BY w.sales_transactions DESC)  AS rank_by_volume,
           RANK() OVER (ORDER BY w.price_per_sqft DESC)      AS price_rank_raw
    FROM with_price AS w
    CROSS JOIN market AS m
)
SELECT area_name, sales_transactions, total_value_aed, avg_transaction_value_aed, price_sample_size, price_per_sqft,
       rank_by_value, rank_by_volume,
       CASE WHEN price_per_sqft IS NOT NULL THEN price_rank_raw END AS rank_by_price_per_sqft,
       CASE WHEN price_per_sqft IS NOT NULL
            THEN CAST((price_per_sqft / NULLIF(market_price_per_sqft, 0) - 1) * 100 AS DECIMAL(8,2))
       END AS pct_vs_market_price_per_sqft
FROM ranked;
GO

-- =====================================================================================================
-- 4. Property summary by category and subtype.  Answers Q4 (apartment vs villa) and Q6 (most transacted types)
--    Concept: a window over an aggregate, SUM(COUNT(*)) OVER (), gives each row's share of the total
--    price_value_aed / price_area_sqft are kept so Power BI can recompute the weighted price per sq ft.
-- =====================================================================================================
CREATE OR ALTER VIEW [rpt].[v_property_summary] AS
SELECT property_category,
       property_subtype,
       COUNT(*)                                          AS sales_transactions,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_transactions,
       SUM(transaction_value_aed)                        AS total_value_aed,
       CAST(AVG(transaction_value_aed) AS DECIMAL(18,2)) AS avg_transaction_value_aed,
       SUM(CASE WHEN is_price_kpi_row = 1 THEN 1 ELSE 0 END)              AS price_sample_size,
       SUM(CASE WHEN is_price_kpi_row = 1 THEN transaction_value_aed END) AS price_value_aed,
       SUM(CASE WHEN is_price_kpi_row = 1 THEN actual_area_sqft END)      AS price_area_sqft,
       CAST(CAST(SUM(CASE WHEN is_price_kpi_row = 1 THEN transaction_value_aed END) AS FLOAT)
            / NULLIF(CAST(SUM(CASE WHEN is_price_kpi_row = 1 THEN actual_area_sqft END) AS FLOAT), 0)
            AS DECIMAL(18,2))                                              AS price_per_sqft
FROM [rpt].[v_sales]
GROUP BY property_category, property_subtype;
GO

-- =====================================================================================================
-- 5. Off-plan vs ready, by property category.  Answers Q5.
-- =====================================================================================================
CREATE OR ALTER VIEW [rpt].[v_stage_summary] AS
SELECT property_category,
       sale_stage,
       COUNT(*)                                          AS sales_transactions,
       SUM(transaction_value_aed)                        AS total_value_aed,
       CAST(AVG(transaction_value_aed) AS DECIMAL(18,2)) AS avg_transaction_value_aed,
       SUM(CASE WHEN is_price_kpi_row = 1 THEN 1 ELSE 0 END)              AS price_sample_size,
       SUM(CASE WHEN is_price_kpi_row = 1 THEN transaction_value_aed END) AS price_value_aed,
       SUM(CASE WHEN is_price_kpi_row = 1 THEN actual_area_sqft END)      AS price_area_sqft,
       CAST(CAST(SUM(CASE WHEN is_price_kpi_row = 1 THEN transaction_value_aed END) AS FLOAT)
            / NULLIF(CAST(SUM(CASE WHEN is_price_kpi_row = 1 THEN actual_area_sqft END) AS FLOAT), 0)
            AS DECIMAL(18,2))                                              AS price_per_sqft
FROM [rpt].[v_sales]
GROUP BY property_category, sale_stage;
GO

-- =====================================================================================================
-- 6. Rooms analysis (Apartments and Villas only).  Power BI page 3.
-- =====================================================================================================
CREATE OR ALTER VIEW [rpt].[v_rooms_summary] AS
SELECT property_category,
       rooms,
       COUNT(*)                                          AS sales_transactions,
       SUM(transaction_value_aed)                        AS total_value_aed,
       CAST(AVG(transaction_value_aed) AS DECIMAL(18,2)) AS avg_transaction_value_aed,
       SUM(CASE WHEN is_price_kpi_row = 1 THEN 1 ELSE 0 END)              AS price_sample_size,
       SUM(CASE WHEN is_price_kpi_row = 1 THEN transaction_value_aed END) AS price_value_aed,
       SUM(CASE WHEN is_price_kpi_row = 1 THEN actual_area_sqft END)      AS price_area_sqft,
       CAST(CAST(SUM(CASE WHEN is_price_kpi_row = 1 THEN transaction_value_aed END) AS FLOAT)
            / NULLIF(CAST(SUM(CASE WHEN is_price_kpi_row = 1 THEN actual_area_sqft END) AS FLOAT), 0)
            AS DECIMAL(18,2))                                              AS price_per_sqft
FROM [rpt].[v_sales]
WHERE property_category IN ('Apartment', 'Villa')
GROUP BY property_category, rooms;
GO

-- =====================================================================================================
-- 7. Monthly trend.  Answers Q7.   Concepts: date grouping, LAG(), running total with a window frame
--    The latest month is PARTIAL, so its month-on-month change is left empty on purpose.
--    The data covers one calendar year only: no year-on-year growth and no seasonality claims.
-- =====================================================================================================
CREATE OR ALTER VIEW [rpt].[v_monthly_trend] AS
WITH monthly AS (
    SELECT transaction_month,
           MAX(CAST(is_partial_month AS INT))                  AS is_partial_month,
           COUNT(*)                                            AS sales_transactions,
           SUM(transaction_value_aed)                          AS total_value_aed,
           CAST(AVG(transaction_value_aed) AS DECIMAL(18,2))   AS avg_transaction_value_aed,
           SUM(CASE WHEN is_price_kpi_row = 1 THEN transaction_value_aed END) AS price_value_aed,
           SUM(CASE WHEN is_price_kpi_row = 1 THEN actual_area_sqft END)      AS price_area_sqft
    FROM [rpt].[v_sales]
    GROUP BY transaction_month
),
with_prev AS (
    SELECT m.*,
           LAG(sales_transactions) OVER (ORDER BY transaction_month) AS prev_month_transactions,
           SUM(total_value_aed) OVER (ORDER BY transaction_month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
               AS cumulative_value_aed
    FROM monthly AS m
)
SELECT transaction_month, is_partial_month, sales_transactions, total_value_aed, avg_transaction_value_aed,
       price_value_aed, price_area_sqft,
       CAST(CAST(price_value_aed AS FLOAT) / NULLIF(CAST(price_area_sqft AS FLOAT), 0) AS DECIMAL(18,2)) AS price_per_sqft,
       prev_month_transactions,
       CASE WHEN is_partial_month = 0 AND prev_month_transactions IS NOT NULL
            THEN CAST(100.0 * (sales_transactions - prev_month_transactions) / NULLIF(prev_month_transactions, 0) AS DECIMAL(8,2))
       END AS mom_change_pct,
       cumulative_value_aed
FROM with_prev;
GO

-- =====================================================================================================
-- 8. Transactions per group per month (Sales, Mortgage, Gifts).  Power BI page 4.
--    Counts the first row of each transaction number (is_primary_row = 1). Groups are never added together.
-- =====================================================================================================
CREATE OR ALTER VIEW [rpt].[v_group_monthly] AS
SELECT transaction_month,
       transaction_group,
       MAX(CAST(is_partial_month AS INT)) AS is_partial_month,
       COUNT(*)                           AS transactions
FROM [core].[fact_transactions]
WHERE is_primary_row = 1
GROUP BY transaction_month, transaction_group;
GO

-- =====================================================================================================
-- 9. Unusual values to investigate.  Answers Q9.   Concepts: ROW_NUMBER(), CTE, UNION-style filtering
--    Two reasons a Sale appears here: (a) price per sq ft flagged in cleaning, (b) one of the 50 biggest Sales.
-- =====================================================================================================
CREATE OR ALTER VIEW [rpt].[v_outliers_review] AS
WITH ranked AS (
    SELECT f.transaction_key, f.transaction_number, f.transaction_date, f.area_key, f.property_key,
           f.transaction_value_aed, f.actual_area_sqft, f.price_per_sqft, f.price_flag,
           ROW_NUMBER() OVER (ORDER BY f.transaction_value_aed DESC) AS value_rank
    FROM [core].[fact_transactions] AS f
    WHERE f.transaction_group = 'Sales' AND f.is_primary_row = 1
)
SELECT r.transaction_key, r.transaction_number, r.transaction_date,
       a.area_name, p.property_category, p.property_subtype,
       r.transaction_value_aed, r.actual_area_sqft, r.price_per_sqft, r.price_flag, r.value_rank,
       CASE WHEN r.price_flag IN ('invalid_low', 'invalid_high', 'review_low', 'review_high')
            THEN CONCAT('Price per sq ft: ', r.price_flag)
            ELSE 'Top 50 transaction value'
       END AS review_reason
FROM ranked AS r
JOIN [core].[dim_area]     AS a ON a.area_key = r.area_key
JOIN [core].[dim_property] AS p ON p.property_key = r.property_key
WHERE r.price_flag IN ('invalid_low', 'invalid_high', 'review_low', 'review_high')
   OR r.value_rank <= 50;
GO

-- =====================================================================================================
-- 10. Pipeline monitoring.  Power BI page 5.
-- =====================================================================================================
CREATE OR ALTER VIEW [rpt].[v_pipeline_runs] AS
SELECT run_id, source_file, status, started_at, finished_at,
       DATEDIFF(SECOND, started_at, finished_at) AS duration_seconds,
       rows_read, rows_rejected, rows_inserted, rows_skipped_existing, message
FROM [ops].[pipeline_runs];
GO

CREATE OR ALTER VIEW [rpt].[v_dq_results] AS
SELECT r.run_id, r.source_file, r.started_at,
       DENSE_RANK() OVER (ORDER BY r.run_id DESC) AS run_recency,   -- 1 = most recent successful run
       d.section, d.metric, d.value_numeric, d.value_text
FROM [ops].[dq_results] AS d
JOIN [ops].[pipeline_runs] AS r ON r.run_id = d.run_id
WHERE r.status = 'SUCCESS';
GO
