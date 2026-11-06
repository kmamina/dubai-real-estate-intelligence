-- 06_create_load_procedure.sql
-- A stored procedure = a saved, named block of SQL. Python calls it after filling stg.transactions.
-- It (1) adds new areas, (2) adds new property types, (3) inserts only NEW fact rows.
-- Needs SQL Server 2016 SP1 or later (CREATE OR ALTER).

USE [DubaiRealEstate];
GO

CREATE OR ALTER PROCEDURE [ops].[usp_load_core]
    @run_id        INT,
    @rows_inserted INT OUTPUT          -- OUTPUT parameter: hands a number back to the caller
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. New areas. NOT EXISTS = "only if this name is not already in the dimension".
    INSERT INTO [core].[dim_area] (area_name)
    SELECT DISTINCT s.area_name
    FROM [stg].[transactions] AS s
    WHERE NOT EXISTS (SELECT 1 FROM [core].[dim_area] AS a WHERE a.area_name = s.area_name);

    -- 2. New property type / subtype pairs.
    INSERT INTO [core].[dim_property] (property_type, property_subtype, property_category)
    SELECT DISTINCT s.property_type, s.property_subtype, s.property_category
    FROM [stg].[transactions] AS s
    WHERE NOT EXISTS (SELECT 1 FROM [core].[dim_property] AS p
                      WHERE p.property_type = s.property_type AND p.property_subtype = s.property_subtype);

    -- 3. New fact rows. The JOINs swap names for keys; NOT EXISTS on row_hash blocks rows loaded before.
    INSERT INTO [core].[fact_transactions] (
        row_hash, run_id, source_file, source_row_number, transaction_number, transaction_datetime,
        transaction_date, transaction_month, is_partial_month, transaction_group, procedure_name,
        is_offplan, is_freehold, usage_type, area_key, property_key, project_name, rooms, parking,
        nearest_metro, nearest_mall, nearest_landmark, total_buyers, total_sellers,
        transaction_value_aed, procedure_area_sqm, actual_area_sqm, actual_area_sqft, price_per_sqft,
        price_flag, is_primary_row, is_sales_kpi_row, is_price_kpi_row)
    SELECT
        s.row_hash, s.run_id, s.source_file, s.source_row_number, s.transaction_number, s.transaction_datetime,
        s.transaction_date, s.transaction_month, s.is_partial_month, s.transaction_group, s.procedure_name,
        s.is_offplan, s.is_freehold, s.usage_type, a.area_key, p.property_key, s.project_name, s.rooms, s.parking,
        s.nearest_metro, s.nearest_mall, s.nearest_landmark, s.total_buyers, s.total_sellers,
        s.transaction_value_aed, s.procedure_area_sqm, s.actual_area_sqm, s.actual_area_sqft, s.price_per_sqft,
        s.price_flag, s.is_primary_row, s.is_sales_kpi_row, s.is_price_kpi_row
    FROM [stg].[transactions] AS s
    JOIN [core].[dim_area]     AS a ON a.area_name = s.area_name
    JOIN [core].[dim_property] AS p ON p.property_type = s.property_type
                                   AND p.property_subtype = s.property_subtype
    WHERE s.run_id = @run_id
      AND NOT EXISTS (SELECT 1 FROM [core].[fact_transactions] AS f WHERE f.row_hash = s.row_hash);

    SET @rows_inserted = @@ROWCOUNT;   -- must come straight after the INSERT
END;
GO
