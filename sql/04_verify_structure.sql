-- 04_verify_structure.sql
-- Run each query separately (highlight it, press F5) and compare with the expected result.

USE [DubaiRealEstate];
GO

-- 1. Tables per schema. Expected: core 3, ops 2, raw 1, stg 1.
SELECT s.name AS schema_name, t.name AS table_name
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE s.name IN ('raw', 'stg', 'core', 'ops')
ORDER BY s.name, t.name;

-- 2. Column count per table (JOIN + GROUP BY). Expected: fact 35, stg 35, raw 27 (ops: pipeline_runs 11, dq_results 6; dim_area 2, dim_property 4).
SELECT s.name AS schema_name, t.name AS table_name, COUNT(c.column_id) AS column_count
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.columns AS c ON c.object_id = t.object_id
WHERE s.name IN ('raw', 'stg', 'core', 'ops')
GROUP BY s.name, t.name
ORDER BY s.name, t.name;

-- 3. Indexes created. Expected: 9 indexes created by script 03 (plus the primary-key and unique-constraint indexes).
SELECT OBJECT_SCHEMA_NAME(i.object_id) AS schema_name, OBJECT_NAME(i.object_id) AS table_name,
       i.name AS index_name, i.type_desc, i.is_unique
FROM sys.indexes AS i
WHERE OBJECT_SCHEMA_NAME(i.object_id) IN ('raw', 'stg', 'core', 'ops') AND i.name IS NOT NULL
ORDER BY schema_name, table_name, i.name;
GO
