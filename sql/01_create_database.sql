-- 01_create_database.sql
-- Run in SSMS while connected to your server (any database selected is fine).
-- Safe to run more than once: it only creates the database if it does not exist.

IF DB_ID(N'DubaiRealEstate') IS NULL
BEGIN
    CREATE DATABASE [DubaiRealEstate];
END;
GO
