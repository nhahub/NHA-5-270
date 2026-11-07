Healthcare Supply Chain Analytics Engine

## Project Overview
This repository contains the data staging layer, integrity checks, and automated CI pipeline for the Healthcare Supply Chain Analytics project[span_4](start_span)[span_4](end_span)[span_5](start_span)[span_5](end_span). Managed by Hossam (Technical Analytics Lead), the project processes, validates, and analyzes multi-source supply chain data (shipments, inventory, purchase orders, and patient cases) using SQL Server and Python pipelines[span_6](start_span)[span_6](end_span)[span_7](start_span)[span_7](end_span).

## Repository Structure
- data/: Contains the raw staging CSV datasets (Staging_in.csv, Staging_inventory_daily.csv, Staging_purchase_orders.csv, Staging_patient_cases.csv, etc.).
- scripts/: Contains SQL Server QC and staging scripts, specifically Task11_Integrity_Checks_FINAL.sql.
- .github/workflows/: Contains the GitHub Actions YAML configuration (run-sql.yml) for automated SQL Server deployment and query execution.

`text
├── data/
│   ├── Staging_in.csv
│   ├── Staging_inventory_daily.csv
│   ├── Staging_purchase_orders.csv
│   ├── Staging_patient_cases.csv
│   ├── Staging_hospitals.csv
│   ├── Staging_items.csv
│   └── Staging_suppliers.csv
├── scripts/
│   └── Task11_Integrity_Checks_FINAL.sql
└── .github/
    └── workflows/
        └── run-sql.yml
## Automated Execution (CI/CD)
The project utilizes GitHub Actions running a Microsoft SQL Server 2022 Docker container on Ubuntu. Every push or pull request automatically:
1. Deploys SQL Server 2022[span_10](start_span)[span_10](end_span).
2. Creates the database SupplyChainProject_DB[span_11](start_span)[span_11](end_span).
3. Imports staging CSV tables.
4. Executes the data integrity and duplication checks (Task11_Integrity_Checks_FINAL.sql) to verify zero variance against expected baseline counts