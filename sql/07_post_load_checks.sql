-- 07_post_load_checks.sql
-- Run each query separately (highlight it, F5) after your first successful load.
-- The "Expected" values are what I computed from your CSV with Python, so they are your reconciliation test.

USE [DubaiRealEstate];
GO

-- 1. Row counts.  Expected: raw 184851, stg 184851, fact 184851, dim_area 268, dim_property 42
SELECT 'raw.transactions' AS table_name, COUNT(*) AS row_count FROM [raw].[transactions]
UNION ALL SELECT 'stg.transactions',        COUNT(*) FROM [stg].[transactions]
UNION ALL SELECT 'core.fact_transactions',  COUNT(*) FROM [core].[fact_transactions]
UNION ALL SELECT 'core.dim_area',           COUNT(*) FROM [core].[dim_area]
UNION ALL SELECT 'core.dim_property',       COUNT(*) FROM [core].[dim_property];

-- 2. Run log.  Expected: newest row SUCCESS, rows_read 184851, rows_rejected 0, rows_inserted 184851, rows_skipped_existing 0
SELECT TOP 5 run_id, source_file, status, rows_read, rows_rejected, rows_inserted, rows_skipped_existing,
       started_at, finished_at
FROM [ops].[pipeline_runs]
ORDER BY run_id DESC;

-- 3. Rows per group.  Expected: Sales 136602, Mortgage 40283, Gifts 7966
SELECT transaction_group, COUNT(*) AS row_count
FROM [core].[fact_transactions]
GROUP BY transaction_group
ORDER BY row_count DESC;

-- 4. KPI populations.  Expected: sales_kpi_rows 136108, price_kpi_rows 116304
SELECT SUM(CAST(is_sales_kpi_row AS INT)) AS sales_kpi_rows,
       SUM(CAST(is_price_kpi_row AS INT)) AS price_kpi_rows
FROM [core].[fact_transactions];

-- 5. First JOIN + GROUP BY analysis: top 5 areas by total Sales value (KPI rows only).
--    Expected: Business Bay 5465 / ~22.94bn, Madinat Al Mataar 12912 / ~18.50bn, Al Yelayiss 1 3949 / ~16.70bn,
--              Palm Deira 3858 / ~14.63bn, Palm Jumeirah 943 / ~12.85bn   (AED)
SELECT TOP 5 a.area_name,
       COUNT(*)                    AS sales_transactions,
       SUM(f.transaction_value_aed) AS total_value_aed
FROM [core].[fact_transactions] AS f
JOIN [core].[dim_area] AS a ON a.area_key = f.area_key
WHERE f.is_sales_kpi_row = 1
GROUP BY a.area_name
ORDER BY total_value_aed DESC;

-- 6. Total Sales value of KPI rows.  Expected: about 415,931,026,714 AED
SELECT SUM(transaction_value_aed) AS total_sales_value_aed
FROM [core].[fact_transactions]
WHERE is_sales_kpi_row = 1;

-- 7. Quality metrics stored for the latest successful run.
--    Expected: rejected = 0; load rows_inserted_into_core 184851, rows_skipped_already_in_core 0
SELECT section, metric, value_numeric, value_text
FROM [ops].[dq_results]
WHERE run_id = (SELECT MAX(run_id) FROM [ops].[pipeline_runs] WHERE status = 'SUCCESS')
  AND section IN ('rejected', 'flagged', 'load')
ORDER BY dq_id;
GO
