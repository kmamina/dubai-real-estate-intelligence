-- 02_create_tables.sql  (v2: text columns widened; PARKING can hold long lists of bay numbers)
-- Creates 4 schemas and 7 tables. Safe to run more than once (each object is created only if missing).
-- Layers:  [raw] original text  ->  [stg] typed staging  ->  [core] cleaned star schema;  [ops] run logs and quality results.

USE [DubaiRealEstate];
GO

-- ---------------------------------------------------------------- schemas
IF SCHEMA_ID(N'raw')  IS NULL EXEC (N'CREATE SCHEMA [raw]');
IF SCHEMA_ID(N'stg')  IS NULL EXEC (N'CREATE SCHEMA [stg]');
IF SCHEMA_ID(N'core') IS NULL EXEC (N'CREATE SCHEMA [core]');
IF SCHEMA_ID(N'ops')  IS NULL EXEC (N'CREATE SCHEMA [ops]');
GO

-- ---------------------------------------------------------------- ops.pipeline_runs
-- One row per pipeline execution (the "who ran what, when, and did it work" record).
IF OBJECT_ID(N'ops.pipeline_runs', N'U') IS NULL
BEGIN
    CREATE TABLE [ops].[pipeline_runs] (
        run_id                INT IDENTITY(1,1) NOT NULL
                              CONSTRAINT PK_pipeline_runs PRIMARY KEY,
        started_at            DATETIME2(0)  NOT NULL,
        finished_at           DATETIME2(0)  NULL,
        source_file           NVARCHAR(260) NOT NULL,
        file_size_bytes       BIGINT        NULL,
        file_hash             CHAR(64)      NULL,      -- SHA-256 of the file; stops the same file loading twice
        status                VARCHAR(20)   NOT NULL
                              CONSTRAINT CK_pipeline_runs_status CHECK (status IN ('RUNNING','SUCCESS','FAILED','SKIPPED')),
        rows_read             INT           NULL,
        rows_rejected         INT           NULL,
        rows_inserted         INT           NULL,
        rows_skipped_existing INT           NULL,
        message               NVARCHAR(1000) NULL
    );
END;
GO

-- ---------------------------------------------------------------- ops.dq_results
-- The data-quality report, stored as rows so Power BI page 5 can read it.
IF OBJECT_ID(N'ops.dq_results', N'U') IS NULL
BEGIN
    CREATE TABLE [ops].[dq_results] (
        dq_id         BIGINT IDENTITY(1,1) NOT NULL
                      CONSTRAINT PK_dq_results PRIMARY KEY,
        run_id        INT           NOT NULL
                      CONSTRAINT FK_dq_results_run REFERENCES [ops].[pipeline_runs](run_id),
        section       VARCHAR(60)   NOT NULL,
        metric        VARCHAR(200)  NOT NULL,
        value_numeric DECIMAL(18,2) NULL,
        value_text    NVARCHAR(200) NULL
    );
END;
GO

-- ---------------------------------------------------------------- raw.transactions
-- Exactly what the CSV contained, all as text. Nothing cleaned, nothing guessed.
IF OBJECT_ID(N'raw.transactions', N'U') IS NULL
BEGIN
    CREATE TABLE [raw].[transactions] (
        raw_id            BIGINT IDENTITY(1,1) NOT NULL
                          CONSTRAINT PK_raw_transactions PRIMARY KEY,
        run_id            INT           NOT NULL
                          CONSTRAINT FK_raw_transactions_run REFERENCES [ops].[pipeline_runs](run_id),
        source_file       NVARCHAR(260) NOT NULL,
        source_row_number INT           NOT NULL,
        [TRANSACTION_NUMBER] NVARCHAR(1000) NULL,
        [INSTANCE_DATE] NVARCHAR(1000) NULL,
        [GROUP_EN] NVARCHAR(1000) NULL,
        [PROCEDURE_EN] NVARCHAR(1000) NULL,
        [IS_OFFPLAN_EN] NVARCHAR(1000) NULL,
        [IS_FREE_HOLD_EN] NVARCHAR(1000) NULL,
        [USAGE_EN] NVARCHAR(1000) NULL,
        [AREA_EN] NVARCHAR(1000) NULL,
        [PROP_TYPE_EN] NVARCHAR(1000) NULL,
        [PROP_SB_TYPE_EN] NVARCHAR(1000) NULL,
        [TRANS_VALUE] NVARCHAR(1000) NULL,
        [PROCEDURE_AREA] NVARCHAR(1000) NULL,
        [ACTUAL_AREA] NVARCHAR(1000) NULL,
        [ROOMS_EN] NVARCHAR(1000) NULL,
        [PARKING] NVARCHAR(1000) NULL,
        [NEAREST_METRO_EN] NVARCHAR(1000) NULL,
        [NEAREST_MALL_EN] NVARCHAR(1000) NULL,
        [NEAREST_LANDMARK_EN] NVARCHAR(1000) NULL,
        [TOTAL_BUYER] NVARCHAR(1000) NULL,
        [TOTAL_SELLER] NVARCHAR(1000) NULL,
        [MASTER_PROJECT_EN] NVARCHAR(1000) NULL,
        [PROJECT_EN] NVARCHAR(1000) NULL,
        loaded_at         DATETIME2(0)  NOT NULL
                          CONSTRAINT DF_raw_transactions_loaded_at DEFAULT SYSDATETIME()
    );
END;
GO

-- ---------------------------------------------------------------- stg.transactions
-- Cleaned rows from Python, correctly typed, waiting to be merged into [core]. Emptied at the start of each run.
IF OBJECT_ID(N'stg.transactions', N'U') IS NULL
BEGIN
    CREATE TABLE [stg].[transactions] (
        run_id                INT           NOT NULL,
        row_hash              CHAR(64)      NOT NULL,
        source_file           NVARCHAR(260) NOT NULL,
        source_row_number     INT           NOT NULL,
        transaction_number    VARCHAR(50)   NOT NULL,
        transaction_datetime  DATETIME2(0)  NOT NULL,
        transaction_date      DATE          NOT NULL,
        transaction_month     DATE          NOT NULL,
        is_partial_month      BIT           NOT NULL,
        transaction_group     VARCHAR(20)   NOT NULL,
        procedure_name        NVARCHAR(100) NULL,
        is_offplan            BIT           NULL,
        is_freehold           BIT           NULL,
        usage_type            VARCHAR(30)   NULL,
        area_name             NVARCHAR(200) NOT NULL,
        property_type         VARCHAR(30)   NOT NULL,
        property_subtype      NVARCHAR(100) NOT NULL,
        property_category     VARCHAR(30)   NOT NULL,
        project_name          NVARCHAR(300) NULL,
        rooms                 NVARCHAR(50)  NULL,
        parking               NVARCHAR(1000)  NULL,
        nearest_metro         NVARCHAR(200) NULL,
        nearest_mall          NVARCHAR(200) NULL,
        nearest_landmark      NVARCHAR(200) NULL,
        total_buyers          INT           NULL,
        total_sellers         INT           NULL,
        transaction_value_aed DECIMAL(18,2) NOT NULL,
        procedure_area_sqm    DECIMAL(18,2) NULL,
        actual_area_sqm       DECIMAL(18,2) NOT NULL,
        actual_area_sqft      DECIMAL(18,2) NOT NULL,
        price_per_sqft        DECIMAL(18,2) NULL,
        price_flag            VARCHAR(20)   NOT NULL,
        is_primary_row        BIT           NOT NULL,
        is_sales_kpi_row      BIT           NOT NULL,
        is_price_kpi_row      BIT           NOT NULL
    );
END;
GO

-- ---------------------------------------------------------------- core.dim_area
-- One row per area (community). The fact table points to it with area_key.
IF OBJECT_ID(N'core.dim_area', N'U') IS NULL
BEGIN
    CREATE TABLE [core].[dim_area] (
        area_key  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_area PRIMARY KEY,
        area_name NVARCHAR(200) NOT NULL CONSTRAINT UQ_dim_area_name UNIQUE
    );
END;
GO

-- ---------------------------------------------------------------- core.dim_property
-- One row per (property type, subtype) pair, with the business category.
IF OBJECT_ID(N'core.dim_property', N'U') IS NULL
BEGIN
    CREATE TABLE [core].[dim_property] (
        property_key      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_property PRIMARY KEY,
        property_type     VARCHAR(30)   NOT NULL,
        property_subtype  NVARCHAR(100) NOT NULL,
        property_category VARCHAR(30)   NOT NULL,
        CONSTRAINT UQ_dim_property UNIQUE (property_type, property_subtype)
    );
END;
GO

-- ---------------------------------------------------------------- core.fact_transactions
-- The cleaned transactions. One row per CSV row that passed validation.
IF OBJECT_ID(N'core.fact_transactions', N'U') IS NULL
BEGIN
    CREATE TABLE [core].[fact_transactions] (
        transaction_key       BIGINT IDENTITY(1,1) NOT NULL
                              CONSTRAINT PK_fact_transactions PRIMARY KEY,
        row_hash              CHAR(64)      NOT NULL,   -- fingerprint of the row; blocks duplicate loading
        run_id                INT           NOT NULL
                              CONSTRAINT FK_fact_run REFERENCES [ops].[pipeline_runs](run_id),
        source_file           NVARCHAR(260) NOT NULL,
        source_row_number     INT           NOT NULL,
        transaction_number    VARCHAR(50)   NOT NULL,
        transaction_datetime  DATETIME2(0)  NOT NULL,
        transaction_date      DATE          NOT NULL,
        transaction_month     DATE          NOT NULL,
        is_partial_month      BIT           NOT NULL,
        transaction_group     VARCHAR(20)   NOT NULL
                              CONSTRAINT CK_fact_group CHECK (transaction_group IN ('Sales','Mortgage','Gifts')),
        procedure_name        NVARCHAR(100) NULL,
        is_offplan            BIT           NULL,
        is_freehold           BIT           NULL,
        usage_type            VARCHAR(30)   NULL,
        area_key              INT           NOT NULL
                              CONSTRAINT FK_fact_area REFERENCES [core].[dim_area](area_key),
        property_key          INT           NOT NULL
                              CONSTRAINT FK_fact_property REFERENCES [core].[dim_property](property_key),
        project_name          NVARCHAR(300) NULL,
        rooms                 NVARCHAR(50)  NULL,
        parking               NVARCHAR(1000)  NULL,
        nearest_metro         NVARCHAR(200) NULL,
        nearest_mall          NVARCHAR(200) NULL,
        nearest_landmark      NVARCHAR(200) NULL,
        total_buyers          INT           NULL,
        total_sellers         INT           NULL,
        transaction_value_aed DECIMAL(18,2) NOT NULL,
        procedure_area_sqm    DECIMAL(18,2) NULL,
        actual_area_sqm       DECIMAL(18,2) NOT NULL,
        actual_area_sqft      DECIMAL(18,2) NOT NULL,
        price_per_sqft        DECIMAL(18,2) NULL,
        price_flag            VARCHAR(20)   NOT NULL,
        is_primary_row        BIT           NOT NULL,
        is_sales_kpi_row      BIT           NOT NULL,
        is_price_kpi_row      BIT           NOT NULL,
        loaded_at             DATETIME2(0)  NOT NULL
                              CONSTRAINT DF_fact_loaded_at DEFAULT SYSDATETIME()
    );
END;
GO
