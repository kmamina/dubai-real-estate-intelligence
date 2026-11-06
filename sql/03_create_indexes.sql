-- 03_create_indexes.sql
-- Indexes speed up the queries we will run. Think of a book index: the database jumps to the right page
-- instead of reading the whole book. Primary keys already have an index; these are the extra ones.

USE [DubaiRealEstate];
GO

-- Blocks duplicate loading: two rows can never share a row_hash.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_fact_row_hash' AND object_id = OBJECT_ID(N'core.fact_transactions'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_fact_row_hash ON [core].[fact_transactions](row_hash);
END;
GO
-- Monthly trend queries (filter by month and group, then sum the value).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_fact_month_group' AND object_id = OBJECT_ID(N'core.fact_transactions'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_month_group ON [core].[fact_transactions](transaction_month, transaction_group) INCLUDE (transaction_value_aed, is_sales_kpi_row, is_price_kpi_row);
END;
GO
-- Foreign keys are joined constantly, so they get indexes.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_fact_area' AND object_id = OBJECT_ID(N'core.fact_transactions'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_area ON [core].[fact_transactions](area_key);
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_fact_property' AND object_id = OBJECT_ID(N'core.fact_transactions'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_property ON [core].[fact_transactions](property_key);
END;
GO
-- Finding every row of one transaction.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_fact_txn_number' AND object_id = OBJECT_ID(N'core.fact_transactions'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_txn_number ON [core].[fact_transactions](transaction_group, transaction_number);
END;
GO
-- Filtered index: only rows used in Sales KPIs. Smaller and faster for dashboard queries.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_fact_sales_kpi' AND object_id = OBJECT_ID(N'core.fact_transactions'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_sales_kpi ON [core].[fact_transactions](transaction_month, area_key) INCLUDE (transaction_value_aed, price_per_sqft) WHERE is_sales_kpi_row = 1;
END;
GO
-- Raw and log tables.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_raw_run' AND object_id = OBJECT_ID(N'raw.transactions'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_raw_run ON [raw].[transactions](run_id);
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_dq_run' AND object_id = OBJECT_ID(N'ops.dq_results'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_dq_run ON [ops].[dq_results](run_id);
END;
GO
-- The same file (same hash) can only be loaded successfully once.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_runs_file_hash_success' AND object_id = OBJECT_ID(N'ops.pipeline_runs'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_runs_file_hash_success ON [ops].[pipeline_runs](file_hash) WHERE status = 'SUCCESS' AND file_hash IS NOT NULL;
END;
GO
