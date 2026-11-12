/*******************************************************************************
  PROJECT  : Healthcare Supply Chain Analytics Engine
  MODULE   : Staging layer - create tables and import CSV files
  DATABASE : SupplyChainProject_DB
  NOTE     : Every staging column is NVARCHAR (raw text, no cleaning at this stage).
             Column names match the CSV headers exactly, because
             Task11_Integrity_Checks_FINAL.sql refers to them by name.
             Run BEFORE Task11_Integrity_Checks_FINAL.sql.
*******************************************************************************/
USE SupplyChainProject_DB;
GO

/* Staging_in  (37 columns, 46 data rows) */
DROP TABLE IF EXISTS dbo.Staging_in;
GO
CREATE TABLE dbo.Staging_in (
    [id] NVARCHAR(255),
    [project code] NVARCHAR(255),
    [pq #] NVARCHAR(255),
    [po / so #] NVARCHAR(255),
    [asn/dn #] NVARCHAR(255),
    [country] NVARCHAR(255),
    [managed by] NVARCHAR(255),
    [fulfill via] NVARCHAR(255),
    [vendor inco term] NVARCHAR(255),
    [shipment mode] NVARCHAR(255),
    [pq first sent to client date] NVARCHAR(255),
    [po sent to vendor date] NVARCHAR(255),
    [scheduled delivery date] NVARCHAR(255),
    [delivered to client date] NVARCHAR(255),
    [delivery recorded date] NVARCHAR(255),
    [product group] NVARCHAR(255),
    [sub classification] NVARCHAR(255),
    [vendor] NVARCHAR(255),
    [item description] NVARCHAR(255),
    [molecule/test type] NVARCHAR(255),
    [brand] NVARCHAR(255),
    [dosage] NVARCHAR(255),
    [dosage form] NVARCHAR(255),
    [unit of measure (per pack)] NVARCHAR(255),
    [line item quantity] NVARCHAR(255),
    [line item value] NVARCHAR(255),
    [pack price] NVARCHAR(255),
    [unit price] NVARCHAR(255),
    [manufacturing site] NVARCHAR(255),
    [first line designation] NVARCHAR(255),
    [weight (kilograms)] NVARCHAR(255),
    [freight cost (usd)] NVARCHAR(255),
    [line item insurance (usd)] NVARCHAR(255),
    [batch_number] NVARCHAR(255),
    [expiry_date] NVARCHAR(255),
    [customs_clearance_days] NVARCHAR(255),
    [receiving_inspection_result] NVARCHAR(255)
);
GO
BULK INSERT dbo.Staging_in
FROM '/var/opt/mssql/data_files/Staging_in.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

/* Staging_inventory_daily  (20 columns, 10793 data rows) */
DROP TABLE IF EXISTS dbo.Staging_inventory_daily;
GO
CREATE TABLE dbo.Staging_inventory_daily (
    [record_id] NVARCHAR(255),
    [date] NVARCHAR(255),
    [hospital_id] NVARCHAR(255),
    [item_id] NVARCHAR(255),
    [opening_stock] NVARCHAR(255),
    [received_qty] NVARCHAR(255),
    [requested_qty] NVARCHAR(255),
    [dispensed_qty] NVARCHAR(255),
    [unmet_demand_qty] NVARCHAR(255),
    [expired_writeoff_qty] NVARCHAR(255),
    [damaged_lost_qty] NVARCHAR(255),
    [stock_adjustment_qty] NVARCHAR(255),
    [closing_stock] NVARCHAR(255),
    [stock_value_egp] NVARCHAR(255),
    [avg_daily_dispensed_7d] NVARCHAR(255),
    [days_of_cover] NVARCHAR(255),
    [fill_rate_pct] NVARCHAR(255),
    [stock_expiring_30d_qty] NVARCHAR(255),
    [reorder_point] NVARCHAR(255),
    [stockout_flag] NVARCHAR(255)
);
GO
BULK INSERT dbo.Staging_inventory_daily
FROM '/var/opt/mssql/data_files/Staging_inventory_daily.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

/* Staging_purchase_orders  (12 columns, 2187 data rows) */
DROP TABLE IF EXISTS dbo.Staging_purchase_orders;
GO
CREATE TABLE dbo.Staging_purchase_orders (
    [po_id] NVARCHAR(255),
    [order_date] NVARCHAR(255),
    [hospital_id] NVARCHAR(255),
    [item_id] NVARCHAR(255),
    [supplier_id] NVARCHAR(255),
    [supplier_name_raw] NVARCHAR(255),
    [qty_ordered] NVARCHAR(255),
    [expected_delivery_date] NVARCHAR(255),
    [received_date] NVARCHAR(255),
    [qty_received] NVARCHAR(255),
    [unit_cost_egp] NVARCHAR(255),
    [po_status] NVARCHAR(255)
);
GO
BULK INSERT dbo.Staging_purchase_orders
FROM '/var/opt/mssql/data_files/Staging_purchase_orders.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

/* Staging_patient_cases  (15 columns, 5665 data rows) */
DROP TABLE IF EXISTS dbo.Staging_patient_cases;
GO
CREATE TABLE dbo.Staging_patient_cases (
    [case_id] NVARCHAR(255),
    [hospital_id] NVARCHAR(255),
    [admission_date] NVARCHAR(255),
    [age_years] NVARCHAR(255),
    [gender] NVARCHAR(255),
    [diagnosis] NVARCHAR(255),
    [severity] NVARCHAR(255),
    [key_drug_item_id] NVARCHAR(255),
    [treatment_status] NVARCHAR(255),
    [treatment_delay_hours] NVARCHAR(255),
    [icu_admission] NVARCHAR(255),
    [complication] NVARCHAR(255),
    [length_of_stay_days] NVARCHAR(255),
    [discharge_date] NVARCHAR(255),
    [outcome] NVARCHAR(255)
);
GO
BULK INSERT dbo.Staging_patient_cases
FROM '/var/opt/mssql/data_files/Staging_patient_cases.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

/* Staging_hospitals  (4 columns, 4 data rows) */
DROP TABLE IF EXISTS dbo.Staging_hospitals;
GO
CREATE TABLE dbo.Staging_hospitals (
    [hospital_id] NVARCHAR(255),
    [hospital_name] NVARCHAR(255),
    [hospital_type] NVARCHAR(255),
    [beds] NVARCHAR(255)
);
GO
BULK INSERT dbo.Staging_hospitals
FROM '/var/opt/mssql/data_files/Staging_hospitals.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

/* Staging_items  (10 columns, 30 data rows) */
DROP TABLE IF EXISTS dbo.Staging_items;
GO
CREATE TABLE dbo.Staging_items (
    [item_id] NVARCHAR(255),
    [item_name] NVARCHAR(255),
    [category] NVARCHAR(255),
    [criticality] NVARCHAR(255),
    [unit] NVARCHAR(255),
    [unit_cost_egp] NVARCHAR(255),
    [shelf_life_days] NVARCHAR(255),
    [cold_chain] NVARCHAR(255),
    [default_supplier_id] NVARCHAR(255),
    [baseline_lead_time_days] NVARCHAR(255)
);
GO
BULK INSERT dbo.Staging_items
FROM '/var/opt/mssql/data_files/Staging_items.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

/* Staging_suppliers  (3 columns, 9 data rows) */
DROP TABLE IF EXISTS dbo.Staging_suppliers;
GO
CREATE TABLE dbo.Staging_suppliers (
    [supplier_id] NVARCHAR(255),
    [supplier_name] NVARCHAR(255),
    [historical_on_time_rate] NVARCHAR(255)
);
GO
BULK INSERT dbo.Staging_suppliers
FROM '/var/opt/mssql/data_files/Staging_suppliers.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

/* Row-count check: the step fails if any table was not loaded completely */
DECLARE @chk TABLE (table_name sysname, actual_rows int, expected_rows int);
INSERT INTO @chk VALUES
    ('Staging_in', (SELECT COUNT(*) FROM dbo.Staging_in), 46),
    ('Staging_inventory_daily', (SELECT COUNT(*) FROM dbo.Staging_inventory_daily), 10793),
    ('Staging_purchase_orders', (SELECT COUNT(*) FROM dbo.Staging_purchase_orders), 2187),
    ('Staging_patient_cases', (SELECT COUNT(*) FROM dbo.Staging_patient_cases), 5665),
    ('Staging_hospitals', (SELECT COUNT(*) FROM dbo.Staging_hospitals), 4),
    ('Staging_items', (SELECT COUNT(*) FROM dbo.Staging_items), 30),
    ('Staging_suppliers', (SELECT COUNT(*) FROM dbo.Staging_suppliers), 9);
SELECT table_name, actual_rows, expected_rows,
       CASE WHEN actual_rows = expected_rows THEN 'OK' ELSE 'MISMATCH' END AS status
FROM @chk;
IF EXISTS (SELECT 1 FROM @chk WHERE actual_rows <> expected_rows)
    RAISERROR('Row count mismatch after CSV import.', 16, 1);
GO
