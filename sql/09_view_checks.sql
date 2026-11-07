-- 09_view_checks.sql
-- Run each query separately (highlight it, F5). "Expected" values come from running the same view logic
-- on your cleaned CSV in a second SQL engine, so a mismatch means something is different in SQL Server.
-- Money is in AED; small rounding differences in the last decimal are fine.

USE [DubaiRealEstate];
GO

-- 1. Executive KPIs (one row).
--    Expected: sales_transactions 136108 | total_sales_value_aed about 415,931,026,714 | avg 3,055,889.64
--              median 1,414,000.00 | price_rows 116304 | price_per_sqft_weighted 1974.01 | price_per_sqft_median 1712.44
SELECT * FROM [rpt].[v_kpi_overview];

-- 2. Q1 + Q3: top 5 areas by total value.  Expected (area: transactions, value rank, volume rank):
--    Business Bay 5465 (1, 3) | Madinat Al Mataar 12912 (2, 1) | Al Yelayiss 1 3949 (3, 6)
--    Palm Deira 3858 (4, 7)   | Palm Jumeirah 943 (5, 47)
SELECT TOP 5 area_name, sales_transactions, total_value_aed, rank_by_value, rank_by_volume
FROM [rpt].[v_area_summary]
ORDER BY rank_by_value;

-- 3. Q3: top 5 areas by number of transactions.
--    Expected: Madinat Al Mataar 12912 | Jumeirah Village Circle 8666 | Business Bay 5465
--              Dubai Land Residence Complex 5294 | Majan 4494
SELECT TOP 5 area_name, sales_transactions, rank_by_volume
FROM [rpt].[v_area_summary]
ORDER BY rank_by_volume;

-- 4. Q2 + Q8: highest price per sq ft (only areas with at least 30 price rows).
--    Expected: Jumeirah Second 8358.03 (n=32) | Jumeirah First 6501.67 (70) | Bluewaters 5654.43 (60)
--              La Mer 5155.05 (84) | Marsa Dubai 4532.99 (345)
SELECT TOP 5 area_name, price_sample_size, price_per_sqft, rank_by_price_per_sqft, pct_vs_market_price_per_sqft
FROM [rpt].[v_area_summary]
WHERE rank_by_price_per_sqft IS NOT NULL
ORDER BY rank_by_price_per_sqft;

-- 5. How many areas, and how many have a reliable price?  Expected: areas 249, areas_with_reliable_price 119
SELECT COUNT(*) AS areas,
       SUM(CASE WHEN price_per_sqft IS NOT NULL THEN 1 ELSE 0 END) AS areas_with_reliable_price
FROM [rpt].[v_area_summary];

-- 6. Q4 + Q6: property categories (re-aggregating the view; shows why we keep the sums, not only the ratio).
--    Expected: Apartment 105925 @ 2030.86 | Land 11124 | Villa 10567 @ 1751.94 | Commercial Unit 5545
--              Hotel Unit 2938 | Other Unit 6 | Building 3   (total 136108)
SELECT property_category,
       SUM(sales_transactions) AS sales_transactions,
       CAST(CAST(SUM(price_value_aed) AS FLOAT) / NULLIF(CAST(SUM(price_area_sqft) AS FLOAT), 0) AS DECIMAL(18,2)) AS price_per_sqft
FROM [rpt].[v_property_summary]
GROUP BY property_category
ORDER BY sales_transactions DESC;

-- 7. Q5: off-plan vs ready (apartments and villas).
--    Expected: Apartment Off-Plan 79066 @ 2162.54 | Apartment Ready 26859 @ 1708.97
--              Villa Off-Plan 7629 @ 1825.77      | Villa Ready 2938 @ 1593.75
SELECT property_category, sale_stage, sales_transactions, price_per_sqft
FROM [rpt].[v_stage_summary]
WHERE property_category IN ('Apartment', 'Villa')
ORDER BY property_category, sale_stage;

-- 8. Rooms (apartments).  Expected: 1 B/R 42931 @ 1812.70 | Studio 32581 @ 1764.45 | 2 B/R 23922 @ 2000.66
--                                    3 B/R 5708 @ 2498.88 | 4 B/R 670 @ 3579.10
SELECT TOP 5 rooms, sales_transactions, price_per_sqft
FROM [rpt].[v_rooms_summary]
WHERE property_category = 'Apartment'
ORDER BY sales_transactions DESC;

-- 9. Q7: monthly trend.  Expected transactions: Jan 17253, Feb 17010, Mar 13494, Apr 14009, May 10264, Jun 13919,
--    Jul 13929, Aug 11699, Sep 11178, Oct 11898, Nov 1455 (PARTIAL: is_partial_month = 1, mom_change_pct empty).
--    Expected mom_change_pct: Feb -1.41, Mar -20.67, Apr 3.82, May -26.73, Jun 35.61, Jul 0.07, Aug -16.01, Sep -4.45, Oct 6.44
SELECT transaction_month, is_partial_month, sales_transactions, total_value_aed, price_per_sqft,
       mom_change_pct, cumulative_value_aed
FROM [rpt].[v_monthly_trend]
ORDER BY transaction_month;

-- 10. Q9: unusual values.  Expected: invalid_high 3 | invalid_low 466 | review_high 40 | review_low 148
--     | Top 50 transaction value 47   (total 704; 3 of the top 50 are already price-flagged)
SELECT review_reason, COUNT(*) AS rows_to_review
FROM [rpt].[v_outliers_review]
GROUP BY review_reason
ORDER BY review_reason;

-- 11. Look at the biggest ones.
SELECT TOP 10 transaction_number, transaction_date, area_name, property_category,
       transaction_value_aed, actual_area_sqft, price_per_sqft, review_reason
FROM [rpt].[v_outliers_review]
ORDER BY transaction_value_aed DESC;

-- 12. Page 4: transactions per group (first row of each transaction number).
--     Expected totals: Sales 136577 | Mortgage 34958 | Gifts 7965
SELECT transaction_group, SUM(transactions) AS transactions
FROM [rpt].[v_group_monthly]
GROUP BY transaction_group
ORDER BY transactions DESC;

-- 13. Pipeline views.  Expected: your runs with their statuses; most recent successful run has run_recency = 1.
SELECT TOP 10 * FROM [rpt].[v_pipeline_runs] ORDER BY run_id DESC;
SELECT TOP 10 run_id, run_recency, section, metric, value_numeric, value_text FROM [rpt].[v_dq_results] ORDER BY run_id DESC, section;
GO
