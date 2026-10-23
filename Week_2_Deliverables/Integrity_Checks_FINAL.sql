/*******************************************************************************
  PROJECT  : Healthcare Supply Chain Analytics Engine
  MODULE   : Task 11 - SQL Staging, Duplicate & Key Integrity Checks
  AUTHOR   : Hossam - Technical Analytics Lead
  DATABASE : SupplyChainProject_DB
  DATE     : October 2026
  NOTE     : Read-only QC suite. No Raw or Staging data is modified.
*******************************************************************************/
USE SupplyChainProject_DB;
GO

/* 0. Bind staging tables to synonyms (spaces in table names are ignored) */
DECLARE @map TABLE (syn sysname, tbl sysname);
INSERT INTO @map VALUES
    ('syn_in',    'Staging_in'),
    ('syn_inv',   'Staging_inventory_daily'),
    ('syn_po',    'Staging_purchase_orders'),
    ('syn_cases', 'Staging_patient_cases');

DECLARE @syn sysname, @tbl sysname, @t nvarchar(400);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT syn, tbl FROM @map;
OPEN c;
FETCH NEXT FROM c INTO @syn, @tbl;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @t = NULL;
    SELECT TOP (1) @t = QUOTENAME(s.name) + '.' + QUOTENAME(t.name)
    FROM sys.tables t
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE REPLACE(REPLACE(t.name, CHAR(160), ''), ' ', '') = @tbl;

    IF @t IS NULL
    BEGIN
        RAISERROR('Table %s was not found.', 16, 1, @tbl);
        BREAK;
    END;

    IF OBJECT_ID('dbo.' + @syn, 'SN') IS NOT NULL EXEC('DROP SYNONYM dbo.' + @syn);
    EXEC('CREATE SYNONYM dbo.' + @syn + ' FOR ' + @t);
    PRINT @syn + ' -> ' + @t;
    FETCH NEXT FROM c INTO @syn, @tbl;
END;
CLOSE c;
DEALLOCATE c;
GO

/* 1. Row counts */
SELECT 'in' AS table_name, COUNT(*) AS row_count FROM dbo.syn_in
UNION ALL SELECT 'inventory_daily', COUNT(*) FROM dbo.syn_inv
UNION ALL SELECT 'purchase_orders', COUNT(*) FROM dbo.syn_po
UNION ALL SELECT 'patient_cases',   COUNT(*) FROM dbo.syn_cases;
GO

/* 2. PK uniqueness - in | Expected: 46 / 46 / 0 */
SELECT COUNT(*)                      AS Total_Rows,
       COUNT(DISTINCT id)            AS Distinct_IDs,
       COUNT(*) - COUNT(DISTINCT id) AS Duplicate_Count
FROM dbo.syn_in;
GO

/* 3. Full-row duplicates - inventory_daily | Expected: 162 */
BEGIN TRY
    WITH d AS (
        SELECT ROW_NUMBER() OVER (
            PARTITION BY record_id, [date], hospital_id, item_id, opening_stock, received_qty,
                         requested_qty, dispensed_qty, unmet_demand_qty, expired_writeoff_qty,
                         damaged_lost_qty, stock_adjustment_qty, closing_stock, stock_value_egp,
                         avg_daily_dispensed_7d, days_of_cover, fill_rate_pct,
                         stock_expiring_30d_qty, reorder_point, stockout_flag
            ORDER BY (SELECT NULL)) AS rn
        FROM dbo.syn_inv)
    SELECT COUNT(*) AS Total_Rows,
           SUM(CASE WHEN rn > 1 THEN 1 ELSE 0 END) AS Full_Duplicate_Rows
    FROM d;

    SELECT record_id, COUNT(*) AS Row_Occurrence_Count
    FROM dbo.syn_inv
    GROUP BY record_id
    HAVING COUNT(*) > 1
    ORDER BY record_id;
END TRY
BEGIN CATCH
    PRINT 'Section 3 failed: ' + ERROR_MESSAGE();
END CATCH;
GO

/* 4. purchase_orders | Expected: 19 full duplicates + 5 conflicting po_id groups */
BEGIN TRY
    WITH d AS (
        SELECT ROW_NUMBER() OVER (
            PARTITION BY po_id, order_date, hospital_id, item_id, supplier_id, supplier_name_raw,
                         qty_ordered, expected_delivery_date, received_date, qty_received,
                         unit_cost_egp, po_status
            ORDER BY (SELECT NULL)) AS rn
        FROM dbo.syn_po)
    SELECT COUNT(*) AS Total_Rows,
           SUM(CASE WHEN rn > 1 THEN 1 ELSE 0 END) AS Full_Duplicate_Rows
    FROM d;

    SELECT po_id,
           COUNT(*)                                   AS Row_Occurrence_Count,
           COUNT(DISTINCT CAST(qty_ordered AS nvarchar(100))) AS Distinct_Qty_Values,
           MIN(CAST(qty_ordered AS nvarchar(100)))    AS Min_Qty,
           MAX(CAST(qty_ordered AS nvarchar(100)))    AS Max_Qty
    FROM dbo.syn_po
    GROUP BY po_id
    HAVING COUNT(*) > 1
       AND COUNT(DISTINCT CAST(qty_ordered AS nvarchar(100))) > 1
    ORDER BY po_id;
END TRY
BEGIN CATCH
    PRINT 'Section 4 failed: ' + ERROR_MESSAGE();
END CATCH;
GO

/* 5. patient_cases | Expected: 67 */
BEGIN TRY
    WITH d AS (
        SELECT ROW_NUMBER() OVER (
            PARTITION BY case_id, hospital_id, admission_date, age_years, gender, diagnosis,
                         severity, key_drug_item_id, treatment_status, treatment_delay_hours,
                         icu_admission, complication, length_of_stay_days, discharge_date, outcome
            ORDER BY (SELECT NULL)) AS rn
        FROM dbo.syn_cases)
    SELECT COUNT(*) AS Total_Rows,
           SUM(CASE WHEN rn > 1 THEN 1 ELSE 0 END) AS Full_Duplicate_Rows
    FROM d;

    SELECT case_id, COUNT(*) AS Row_Occurrence_Count
    FROM dbo.syn_cases
    GROUP BY case_id
    HAVING COUNT(*) > 1
    ORDER BY case_id;
END TRY
BEGIN CATCH
    PRINT 'Section 5 failed: ' + ERROR_MESSAGE();
END CATCH;
GO

/* 6. hospital_id integrity | Expected orphan H-E: 23 / 4 / 10 */
BEGIN TRY
    SELECT src, hospital_id AS raw_value, COUNT(*) AS Row_Count
    FROM (
        SELECT 'inventory_daily' AS src, CAST(hospital_id AS nvarchar(100)) AS hospital_id FROM dbo.syn_inv
        UNION ALL SELECT 'purchase_orders', CAST(hospital_id AS nvarchar(100)) FROM dbo.syn_po
        UNION ALL SELECT 'patient_cases',   CAST(hospital_id AS nvarchar(100)) FROM dbo.syn_cases
    ) r
    GROUP BY src, hospital_id
    ORDER BY src, hospital_id;

    SELECT src, hospital_norm, COUNT(*) AS Orphan_Rows
    FROM (
        SELECT 'inventory_daily' AS src,
               UPPER(LTRIM(RTRIM(REPLACE(CAST(hospital_id AS nvarchar(100)), '_', '-')))) AS hospital_norm
        FROM dbo.syn_inv
        UNION ALL
        SELECT 'purchase_orders',
               UPPER(LTRIM(RTRIM(REPLACE(CAST(hospital_id AS nvarchar(100)), '_', '-'))))
        FROM dbo.syn_po
        UNION ALL
        SELECT 'patient_cases',
               UPPER(LTRIM(RTRIM(REPLACE(CAST(hospital_id AS nvarchar(100)), '_', '-'))))
        FROM dbo.syn_cases
    ) n
    WHERE hospital_norm IS NULL
       OR hospital_norm NOT IN ('H-A', 'H-B', 'H-C', 'H-D')
    GROUP BY src, hospital_norm
    ORDER BY src, hospital_norm;
END TRY
BEGIN CATCH
    PRINT 'Section 6 failed: ' + ERROR_MESSAGE();
END CATCH;
GO

/* 7. Item codes outside I001-I030 | Examples: I3O1, I099, I000 */
BEGIN TRY
    SELECT src, item_id AS raw_item_id, COUNT(*) AS Row_Count
    FROM (
        SELECT 'inventory_daily' AS src, CAST(item_id AS nvarchar(100)) AS item_id FROM dbo.syn_inv
        UNION ALL SELECT 'purchase_orders', CAST(item_id AS nvarchar(100)) FROM dbo.syn_po
        UNION ALL SELECT 'patient_cases',   CAST(key_drug_item_id AS nvarchar(100)) FROM dbo.syn_cases
    ) i
    WHERE item_id IS NULL
       OR item_id NOT LIKE 'I[0-9][0-9][0-9]'
       OR TRY_CAST(SUBSTRING(item_id, 2, 3) AS int) NOT BETWEEN 1 AND 30
    GROUP BY src, item_id
    ORDER BY src, item_id;
END TRY
BEGIN CATCH
    PRINT 'Section 7 failed: ' + ERROR_MESSAGE();
END CATCH;
GO

/* 8. S09 = Regional Distribution Center, not a commercial vendor */
BEGIN TRY
    SELECT CAST(supplier_id AS nvarchar(100))       AS supplier_id,
           CAST(supplier_name_raw AS nvarchar(200)) AS supplier_name_raw,
           COUNT(*) AS Row_Count
    FROM dbo.syn_po
    WHERE CAST(supplier_id AS nvarchar(100)) = 'S09'
    GROUP BY CAST(supplier_id AS nvarchar(100)), CAST(supplier_name_raw AS nvarchar(200));
END TRY
BEGIN CATCH
    PRINT 'Section 8 failed: ' + ERROR_MESSAGE();
END CATCH;
GO
