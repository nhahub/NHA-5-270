/*******************************************************************************
  PROJECT  : Healthcare Supply Chain Analytics Engine
  MODULE   : Task 11 - SQL Staging, Duplicate & Key Integrity Checks
  AUTHOR   : Hossam - Technical Analytics Lead
  DATABASE : SupplyChainProject_DB
  DATE     : October 2026
  NOTE     : Read-only QC suite. No Raw or Staging data is modified.
  REVIEW   : 31 Oct 2026 - three changes only; sections 0-3, 5, 6 and 8 are unchanged.
             Section 4 : cleaning arithmetic (4b) and keep-first with a fixed order (4c) added.
             Section 7 : item codes are trimmed and upper-cased before the test; 7b added.
             Section 9 : new, one query per figure of report section 7.
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

    /* 4b. Cleaning arithmetic | Expected: 2,187 rows - 19 identical copies - 5 conflicting second rows = 2,163 rows */
    SELECT COUNT(*)                         AS Total_Rows,
           COUNT(DISTINCT po_id)            AS Rows_After_Cleaning,
           COUNT(*) - COUNT(DISTINCT po_id) AS Rows_Removed
    FROM dbo.syn_po;

    /* 4c. Keep-first with a fixed order | Expected: 5 rows, Dropped_minus_Kept = 10
           In each conflicting po_id the row with the lower qty_ordered is rank 1 and is kept; the order
           does not depend on how the rows are stored. In the source sheet the kept row is also the first
           row of its group in all 5 groups. */
    ;WITH c AS (
        SELECT po_id
        FROM dbo.syn_po
        GROUP BY po_id
        HAVING COUNT(*) > 1
           AND COUNT(DISTINCT CAST(qty_ordered AS nvarchar(100))) > 1),
    r AS (
        SELECT p.po_id, p.qty_ordered, p.qty_received,
               ROW_NUMBER() OVER (PARTITION BY p.po_id
                                  ORDER BY TRY_CAST(p.qty_ordered AS decimal(18,2)) ASC) AS keep_rank
        FROM dbo.syn_po p
        JOIN c ON c.po_id = p.po_id)
    SELECT po_id,
           MAX(CASE WHEN keep_rank = 1 THEN CAST(qty_ordered AS nvarchar(100)) END) AS Kept_Qty,
           MAX(CASE WHEN keep_rank = 2 THEN CAST(qty_ordered AS nvarchar(100)) END) AS Dropped_Qty,
           MAX(CASE WHEN keep_rank = 2 THEN TRY_CAST(qty_ordered AS decimal(18,2)) END)
             - MAX(CASE WHEN keep_rank = 1 THEN TRY_CAST(qty_ordered AS decimal(18,2)) END) AS Dropped_minus_Kept,
           MAX(CASE WHEN keep_rank = 1 THEN CAST(qty_received AS nvarchar(100)) END)       AS Qty_Received_Kept_Row
    FROM r
    GROUP BY po_id
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

/* 7. Item codes outside I001-I030 | Examples: I3O1, I099, I000 | codes are trimmed and upper-cased first, so a valid code with spaces or lower case is not listed */
BEGIN TRY
    SELECT src, item_id AS raw_item_id, COUNT(*) AS Row_Count
    FROM (
        SELECT 'inventory_daily' AS src, CAST(item_id AS nvarchar(100)) AS item_id FROM dbo.syn_inv
        UNION ALL SELECT 'purchase_orders', CAST(item_id AS nvarchar(100)) FROM dbo.syn_po
        UNION ALL SELECT 'patient_cases',   CAST(key_drug_item_id AS nvarchar(100)) FROM dbo.syn_cases
    ) i
    WHERE item_id IS NULL
       OR UPPER(LTRIM(RTRIM(item_id))) NOT LIKE 'I[0-9][0-9][0-9]'
       OR TRY_CAST(SUBSTRING(UPPER(LTRIM(RTRIM(item_id))), 2, 3) AS int) NOT BETWEEN 1 AND 30
    GROUP BY src, item_id
    ORDER BY src, item_id;

    /* 7b. Split used in report section 5 | Expected invalid rows 35 / 8 / 22 and case-or-space-only rows 180 / 0 / 50 */
    SELECT i.src,
           SUM(CASE WHEN n.norm = 'I099' THEN 1 ELSE 0 END) AS I099,
           SUM(CASE WHEN n.norm = 'I000' THEN 1 ELSE 0 END) AS I000,
           SUM(CASE WHEN n.norm = 'I3O1' THEN 1 ELSE 0 END) AS I3O1,
           SUM(CASE WHEN n.norm LIKE 'I[0-9][0-9][0-9]'
                     AND TRY_CAST(SUBSTRING(n.norm, 2, 3) AS int) BETWEEN 1 AND 30
                     AND (N'[' + i.item_id + N']') COLLATE Latin1_General_BIN2
                         <> (N'[' + n.norm + N']') COLLATE Latin1_General_BIN2
                    THEN 1 ELSE 0 END) AS Case_Or_Space_Only,
           SUM(CASE WHEN n.norm IS NULL
                      OR n.norm NOT LIKE 'I[0-9][0-9][0-9]'
                      OR TRY_CAST(SUBSTRING(n.norm, 2, 3) AS int) NOT BETWEEN 1 AND 30
                    THEN 1 ELSE 0 END) AS Invalid_Rows
    FROM (
        SELECT 'inventory_daily' AS src, CAST(item_id AS nvarchar(100)) AS item_id FROM dbo.syn_inv
        UNION ALL SELECT 'purchase_orders', CAST(item_id AS nvarchar(100)) FROM dbo.syn_po
        UNION ALL SELECT 'patient_cases',   CAST(key_drug_item_id AS nvarchar(100)) FROM dbo.syn_cases
    ) i
    CROSS APPLY (SELECT UPPER(LTRIM(RTRIM(i.item_id))) AS norm) n
    GROUP BY i.src
    ORDER BY i.src;
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

/* 9. Missing and invalid values | one row per figure of report section 7 (rows_found must equal expected_in_report)
      Blank = NULL or empty text; text instead of a number = a value that is not numeric.
      Dates use explicit formats: yyyy-mm-dd, dd/mm/yyyy (style 103), dd-Mon-yy, Excel serial number (base 30 Dec 1899). */
BEGIN TRY
    SELECT table_name, column_name, finding, expected_in_report, rows_found,
           CASE WHEN rows_found = expected_in_report THEN N'Match' ELSE N'CHECK' END AS status
    FROM (
    SELECT 1 AS ord, N'in' AS table_name, N'country' AS column_name, N'Encoding error in Cote d''Ivoire' AS finding, 6 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_in t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[country] AS nvarchar(4000)))), N'') AS v) a
    WHERE v LIKE N'%' + NCHAR(195) + NCHAR(180) + N'%'
    UNION ALL
    SELECT 2 AS ord, N'in' AS table_name, N'pq first sent to client date' AS column_name, N'Text Pre-PQ Process in a date column' AS finding, 21 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_in t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[pq first sent to client date] AS nvarchar(4000)))), N'') AS v) a
    WHERE v = N'Pre-PQ Process'
    UNION ALL
    SELECT 3 AS ord, N'in' AS table_name, N'po sent to vendor date' AS column_name, N'Text Date Not Captured in a date column' AS finding, 1 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_in t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[po sent to vendor date] AS nvarchar(4000)))), N'') AS v) a
    WHERE v = N'Date Not Captured'
    UNION ALL
    SELECT 4 AS ord, N'in' AS table_name, N'weight (kilograms)' AS column_name, N'Text instead of a number' AS finding, 8 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_in t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[weight (kilograms)] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NOT NULL AND TRY_CAST(v AS decimal(38,6)) IS NULL
    UNION ALL
    SELECT 5 AS ord, N'in' AS table_name, N'freight cost (usd)' AS column_name, N'Text instead of a number' AS finding, 8 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_in t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[freight cost (usd)] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NOT NULL AND TRY_CAST(v AS decimal(38,6)) IS NULL
    UNION ALL
    SELECT 6 AS ord, N'in' AS table_name, N'dosage' AS column_name, N'Blank' AS finding, 8 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_in t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[dosage] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 7 AS ord, N'in' AS table_name, N'receiving_inspection_result' AS column_name, N'Blank' AS finding, 6 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_in t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[receiving_inspection_result] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 8 AS ord, N'in' AS table_name, N'batch_number' AS column_name, N'Blank' AS finding, 3 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_in t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[batch_number] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 9 AS ord, N'in' AS table_name, N'expiry_date' AS column_name, N'Blank' AS finding, 2 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_in t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[expiry_date] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 10 AS ord, N'inventory_daily' AS table_name, N'closing_stock' AS column_name, N'Text ''-''' AS finding, 15 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_inv t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[closing_stock] AS nvarchar(4000)))), N'') AS v) a
    WHERE v = N'-'
    UNION ALL
    SELECT 11 AS ord, N'inventory_daily' AS table_name, N'closing_stock' AS column_name, N'Text ''?''' AS finding, 13 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_inv t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[closing_stock] AS nvarchar(4000)))), N'') AS v) a
    WHERE v = N'?'
    UNION ALL
    SELECT 12 AS ord, N'inventory_daily' AS table_name, N'closing_stock' AS column_name, N'Number with thousands separator' AS finding, 15 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_inv t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[closing_stock] AS nvarchar(4000)))), N'') AS v) a
    WHERE v LIKE N'%,%' AND TRY_CAST(REPLACE(v, N',', N'') AS decimal(38,6)) IS NOT NULL
    UNION ALL
    SELECT 13 AS ord, N'inventory_daily' AS table_name, N'closing_stock' AS column_name, N'Text instead of a number (total)' AS finding, 43 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_inv t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[closing_stock] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NOT NULL AND TRY_CAST(v AS decimal(38,6)) IS NULL
    UNION ALL
    SELECT 14 AS ord, N'inventory_daily' AS table_name, N'stock_value_egp' AS column_name, N'Text with EGP prefix' AS finding, 86 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_inv t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[stock_value_egp] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NOT NULL AND TRY_CAST(v AS decimal(38,6)) IS NULL
    UNION ALL
    SELECT 15 AS ord, N'inventory_daily' AS table_name, N'stockout_flag' AS column_name, N'Y / N / TRUE / FALSE instead of 0 / 1' AS finding, 203 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_inv t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[stockout_flag] AS nvarchar(4000)))), N'') AS v) a
    WHERE v NOT IN (N'0', N'1')
    UNION ALL
    SELECT 16 AS ord, N'inventory_daily' AS table_name, N'received_qty' AS column_name, N'Negative quantity' AS finding, 43 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_inv t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[received_qty] AS nvarchar(4000)))), N'') AS v) a
    WHERE TRY_CAST(v AS decimal(38,6)) < 0
    UNION ALL
    SELECT 17 AS ord, N'inventory_daily' AS table_name, N'unmet_demand_qty' AS column_name, N'Blank' AS finding, 1678 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_inv t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[unmet_demand_qty] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 18 AS ord, N'inventory_daily' AS table_name, N'days_of_cover' AS column_name, N'Blank' AS finding, 624 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_inv t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[days_of_cover] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 19 AS ord, N'inventory_daily' AS table_name, N'dispensed_qty' AS column_name, N'Blank' AS finding, 348 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_inv t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[dispensed_qty] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 20 AS ord, N'inventory_daily' AS table_name, N'reorder_point' AS column_name, N'Blank' AS finding, 255 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_inv t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[reorder_point] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 21 AS ord, N'inventory_daily' AS table_name, N'avg_daily_dispensed_7d' AS column_name, N'Blank' AS finding, 244 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_inv t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[avg_daily_dispensed_7d] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 22 AS ord, N'inventory_daily' AS table_name, N'stock_value_egp' AS column_name, N'Blank' AS finding, 236 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_inv t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[stock_value_egp] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 23 AS ord, N'inventory_daily' AS table_name, N'closing_stock' AS column_name, N'Blank' AS finding, 154 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_inv t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[closing_stock] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 24 AS ord, N'inventory_daily' AS table_name, N'received_qty' AS column_name, N'Blank' AS finding, 99 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_inv t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[received_qty] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 25 AS ord, N'inventory_daily' AS table_name, N'requested_qty' AS column_name, N'Blank' AS finding, 99 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_inv t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[requested_qty] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 26 AS ord, N'purchase_orders' AS table_name, N'po_status' AS column_name, N'Non-standard spelling (14 raw spellings)' AS finding, 211 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_po t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[po_status] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NOT NULL AND (N'[' + CAST(t.[po_status] AS nvarchar(100)) + N']') COLLATE Latin1_General_BIN2 NOT IN (N'[Received]', N'[Partially Received]', N'[In Transit]', N'[Rejected]')
    UNION ALL
    SELECT 27 AS ord, N'purchase_orders' AS table_name, N'unit_cost_egp' AS column_name, N'Dollar format' AS finding, 23 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_po t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[unit_cost_egp] AS nvarchar(4000)))), N'') AS v) a
    WHERE v LIKE N'$%'
    UNION ALL
    SELECT 28 AS ord, N'purchase_orders' AS table_name, N'unit_cost_egp' AS column_name, N'Text with EGP prefix' AS finding, 39 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_po t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[unit_cost_egp] AS nvarchar(4000)))), N'') AS v) a
    WHERE v LIKE N'EGP%'
    UNION ALL
    SELECT 29 AS ord, N'purchase_orders' AS table_name, N'qty_received' AS column_name, N'Text unknown' AS finding, 8 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_po t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[qty_received] AS nvarchar(4000)))), N'') AS v) a
    WHERE v = N'unknown'
    UNION ALL
    SELECT 30 AS ord, N'purchase_orders' AS table_name, N'qty_received' AS column_name, N'Text see GRN' AS finding, 7 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_po t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[qty_received] AS nvarchar(4000)))), N'') AS v) a
    WHERE v = N'see GRN'
    UNION ALL
    SELECT 31 AS ord, N'purchase_orders' AS table_name, N'qty_received' AS column_name, N'Blank' AS finding, 179 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_po t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[qty_received] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 32 AS ord, N'purchase_orders' AS table_name, N'received_date' AS column_name, N'Blank' AS finding, 194 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_po t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[received_date] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 33 AS ord, N'patient_cases' AS table_name, N'age_years' AS column_name, N'Text in days' AS finding, 44 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_cases t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[age_years] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NOT NULL AND TRY_CAST(v AS decimal(38,6)) IS NULL
    UNION ALL
    SELECT 34 AS ord, N'patient_cases' AS table_name, N'age_years' AS column_name, N'Blank' AS finding, 207 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_cases t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[age_years] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 35 AS ord, N'patient_cases' AS table_name, N'gender' AS column_name, N'Variants other than F or M' AS finding, 518 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_cases t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[gender] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NOT NULL AND (N'[' + CAST(t.[gender] AS nvarchar(100)) + N']') COLLATE Latin1_General_BIN2 NOT IN (N'[F]', N'[M]')
    UNION ALL
    SELECT 36 AS ord, N'patient_cases' AS table_name, N'gender' AS column_name, N'Blank' AS finding, 133 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_cases t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[gender] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 37 AS ord, N'patient_cases' AS table_name, N'severity' AS column_name, N'Numeric code 1, 2 or 3' AS finding, 107 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_cases t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[severity] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IN (N'1', N'2', N'3')
    UNION ALL
    SELECT 38 AS ord, N'patient_cases' AS table_name, N'severity' AS column_name, N'Blank' AS finding, 247 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_cases t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[severity] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 39 AS ord, N'patient_cases' AS table_name, N'icu_admission' AS column_name, N'Variants other than Y or N' AS finding, 238 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_cases t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[icu_admission] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NOT NULL AND (N'[' + CAST(t.[icu_admission] AS nvarchar(100)) + N']') COLLATE Latin1_General_BIN2 NOT IN (N'[Y]', N'[N]')
    UNION ALL
    SELECT 40 AS ord, N'patient_cases' AS table_name, N'treatment_delay_hours' AS column_name, N'Text with h suffix' AS finding, 59 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_cases t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[treatment_delay_hours] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NOT NULL AND TRY_CAST(v AS decimal(38,6)) IS NULL
    UNION ALL
    SELECT 41 AS ord, N'patient_cases' AS table_name, N'treatment_delay_hours' AS column_name, N'Blank' AS finding, 103 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_cases t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[treatment_delay_hours] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 42 AS ord, N'patient_cases' AS table_name, N'length_of_stay_days' AS column_name, N'Text with days suffix' AS finding, 52 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_cases t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[length_of_stay_days] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NOT NULL AND TRY_CAST(v AS decimal(38,6)) IS NULL
    UNION ALL
    SELECT 43 AS ord, N'patient_cases' AS table_name, N'length_of_stay_days' AS column_name, N'Blank' AS finding, 411 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_cases t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[length_of_stay_days] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 44 AS ord, N'patient_cases' AS table_name, N'discharge_date' AS column_name, N'Blank' AS finding, 449 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_cases t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[discharge_date] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT 45 AS ord, N'patient_cases' AS table_name, N'outcome' AS column_name, N'Blank' AS finding, 39 AS expected_in_report, COUNT_BIG(*) AS rows_found
    FROM dbo.syn_cases t CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[outcome] AS nvarchar(4000)))), N'') AS v) a
    WHERE v IS NULL
    UNION ALL
    SELECT t2.ord, t2.table_name, v2.column_name, v2.finding, v2.expected_in_report, v2.rows_found
    FROM (
        SELECT 1001 AS ord, N'inventory_daily' AS table_name,
               SUM(CASE WHEN f.fmt = N'dd/mm/yyyy'  THEN 1 ELSE 0 END) AS n_slash,
               SUM(CASE WHEN f.fmt = N'dd-Mon-yy'   THEN 1 ELSE 0 END) AS n_mon,
               SUM(CASE WHEN f.fmt = N'Excel serial' THEN 1 ELSE 0 END) AS n_serial,
               SUM(CASE WHEN p.d_parsed < '20260101' OR p.d_parsed > '20260331' THEN 1 ELSE 0 END) AS n_oop
        FROM dbo.syn_inv t
        CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[date] AS nvarchar(4000)))), N'') AS v) a
        CROSS APPLY (SELECT CASE
                  WHEN a.v IS NULL THEN N'blank'
                  WHEN a.v LIKE N'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%' THEN N'ISO'
                  WHEN a.v LIKE N'%/%/%' THEN N'dd/mm/yyyy'
                  WHEN a.v LIKE N'[0-9]%-[A-Za-z][A-Za-z][A-Za-z]-[0-9][0-9]' THEN N'dd-Mon-yy'
                  WHEN TRY_CAST(a.v AS decimal(18,4)) IS NOT NULL THEN N'Excel serial'
                  ELSE N'other' END AS fmt) f
        CROSS APPLY (SELECT CASE f.fmt
                  WHEN N'ISO'          THEN TRY_CONVERT(date, LEFT(a.v, 10), 23)
                  WHEN N'dd/mm/yyyy'   THEN TRY_CONVERT(date, a.v, 103)
                  WHEN N'dd-Mon-yy'    THEN TRY_CONVERT(date, CONCAT(N'20', RIGHT(a.v, 2), N'-',
                                              RIGHT(N'0' + CAST((CHARINDEX(SUBSTRING(a.v, NULLIF(CHARINDEX(N'-', a.v), 0) + 1, 3),
                                                     N'JanFebMarAprMayJunJulAugSepOctNovDec') + 2) / 3 AS nvarchar(2)), 2), N'-',
                                              RIGHT(N'0' + LEFT(a.v, NULLIF(CHARINDEX(N'-', a.v), 0) - 1), 2)), 23)
                  WHEN N'Excel serial' THEN DATEADD(day, CAST(TRY_CAST(a.v AS decimal(18,4)) AS int), CAST('18991230' AS date))
                  END AS d_parsed) p
    ) t2
    CROSS APPLY (VALUES
        (N'date', N'Mixed format dd/mm/yyyy', 417, t2.n_slash),
        (N'date', N'Mixed format dd-Mon-yy', 108, t2.n_mon),
        (N'date', N'Mixed format Excel serial number', 43, t2.n_serial),
        (N'date', N'Outside 1 Jan to 31 Mar 2026 (Out_of_Period)', 43, t2.n_oop)
    ) v2 (column_name, finding, expected_in_report, rows_found)
    UNION ALL
    SELECT t2.ord, t2.table_name, v2.column_name, v2.finding, v2.expected_in_report, v2.rows_found
    FROM (
        SELECT 1002 AS ord, N'purchase_orders' AS table_name,
               SUM(CASE WHEN f.fmt = N'dd/mm/yyyy'  THEN 1 ELSE 0 END) AS n_slash,
               SUM(CASE WHEN f.fmt = N'dd-Mon-yy'   THEN 1 ELSE 0 END) AS n_mon,
               SUM(CASE WHEN f.fmt = N'Excel serial' THEN 1 ELSE 0 END) AS n_serial,
               SUM(CASE WHEN p.d_parsed < '20260101' OR p.d_parsed > '20260331' THEN 1 ELSE 0 END) AS n_oop
        FROM dbo.syn_po t
        CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[order_date] AS nvarchar(4000)))), N'') AS v) a
        CROSS APPLY (SELECT CASE
                  WHEN a.v IS NULL THEN N'blank'
                  WHEN a.v LIKE N'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%' THEN N'ISO'
                  WHEN a.v LIKE N'%/%/%' THEN N'dd/mm/yyyy'
                  WHEN a.v LIKE N'[0-9]%-[A-Za-z][A-Za-z][A-Za-z]-[0-9][0-9]' THEN N'dd-Mon-yy'
                  WHEN TRY_CAST(a.v AS decimal(18,4)) IS NOT NULL THEN N'Excel serial'
                  ELSE N'other' END AS fmt) f
        CROSS APPLY (SELECT CASE f.fmt
                  WHEN N'ISO'          THEN TRY_CONVERT(date, LEFT(a.v, 10), 23)
                  WHEN N'dd/mm/yyyy'   THEN TRY_CONVERT(date, a.v, 103)
                  WHEN N'dd-Mon-yy'    THEN TRY_CONVERT(date, CONCAT(N'20', RIGHT(a.v, 2), N'-',
                                              RIGHT(N'0' + CAST((CHARINDEX(SUBSTRING(a.v, NULLIF(CHARINDEX(N'-', a.v), 0) + 1, 3),
                                                     N'JanFebMarAprMayJunJulAugSepOctNovDec') + 2) / 3 AS nvarchar(2)), 2), N'-',
                                              RIGHT(N'0' + LEFT(a.v, NULLIF(CHARINDEX(N'-', a.v), 0) - 1), 2)), 23)
                  WHEN N'Excel serial' THEN DATEADD(day, CAST(TRY_CAST(a.v AS decimal(18,4)) AS int), CAST('18991230' AS date))
                  END AS d_parsed) p
    ) t2
    CROSS APPLY (VALUES
        (N'order_date', N'Mixed format dd/mm/yyyy', 61, t2.n_slash),
        (N'order_date', N'Mixed format dd-Mon-yy', 23, t2.n_mon),
        (N'order_date', N'Mixed format Excel serial number', 8, t2.n_serial)
    ) v2 (column_name, finding, expected_in_report, rows_found)
    UNION ALL
    SELECT t2.ord, t2.table_name, v2.column_name, v2.finding, v2.expected_in_report, v2.rows_found
    FROM (
        SELECT 1003 AS ord, N'patient_cases' AS table_name,
               SUM(CASE WHEN f.fmt = N'dd/mm/yyyy'  THEN 1 ELSE 0 END) AS n_slash,
               SUM(CASE WHEN f.fmt = N'dd-Mon-yy'   THEN 1 ELSE 0 END) AS n_mon,
               SUM(CASE WHEN f.fmt = N'Excel serial' THEN 1 ELSE 0 END) AS n_serial,
               SUM(CASE WHEN p.d_parsed < '20260101' OR p.d_parsed > '20260331' THEN 1 ELSE 0 END) AS n_oop
        FROM dbo.syn_cases t
        CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(CAST(t.[admission_date] AS nvarchar(4000)))), N'') AS v) a
        CROSS APPLY (SELECT CASE
                  WHEN a.v IS NULL THEN N'blank'
                  WHEN a.v LIKE N'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%' THEN N'ISO'
                  WHEN a.v LIKE N'%/%/%' THEN N'dd/mm/yyyy'
                  WHEN a.v LIKE N'[0-9]%-[A-Za-z][A-Za-z][A-Za-z]-[0-9][0-9]' THEN N'dd-Mon-yy'
                  WHEN TRY_CAST(a.v AS decimal(18,4)) IS NOT NULL THEN N'Excel serial'
                  ELSE N'other' END AS fmt) f
        CROSS APPLY (SELECT CASE f.fmt
                  WHEN N'ISO'          THEN TRY_CONVERT(date, LEFT(a.v, 10), 23)
                  WHEN N'dd/mm/yyyy'   THEN TRY_CONVERT(date, a.v, 103)
                  WHEN N'dd-Mon-yy'    THEN TRY_CONVERT(date, CONCAT(N'20', RIGHT(a.v, 2), N'-',
                                              RIGHT(N'0' + CAST((CHARINDEX(SUBSTRING(a.v, NULLIF(CHARINDEX(N'-', a.v), 0) + 1, 3),
                                                     N'JanFebMarAprMayJunJulAugSepOctNovDec') + 2) / 3 AS nvarchar(2)), 2), N'-',
                                              RIGHT(N'0' + LEFT(a.v, NULLIF(CHARINDEX(N'-', a.v), 0) - 1), 2)), 23)
                  WHEN N'Excel serial' THEN DATEADD(day, CAST(TRY_CAST(a.v AS decimal(18,4)) AS int), CAST('18991230' AS date))
                  END AS d_parsed) p
    ) t2
    CROSS APPLY (VALUES
        (N'admission_date', N'Mixed format dd/mm/yyyy', 223, t2.n_slash),
        (N'admission_date', N'Mixed format dd-Mon-yy', 50, t2.n_mon),
        (N'admission_date', N'Mixed format Excel serial number', 13, t2.n_serial)
    ) v2 (column_name, finding, expected_in_report, rows_found)
    ) q
    ORDER BY ord, finding;
END TRY
BEGIN CATCH
    PRINT 'Section 9 failed: ' + ERROR_MESSAGE();
END CATCH;
GO
