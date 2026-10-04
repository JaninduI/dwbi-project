# Olist Data Warehouse and BI Solution (IT3101 DWBI Assignment)

Builds the `Olist_DW` database (Staging, Warehouse and Mart schemas) on SQL Server from the Olist Brazilian e-commerce CSV files. The scripts are the source of truth.

## Requirements
- SQL Server 2017 or later (needed for `BULK INSERT ... FORMAT = 'CSV'`) and SSMS
- The 9 Olist CSV files (Kaggle: *Brazilian E-Commerce Public Dataset by Olist*). They are not included in this submission.
- Power BI Desktop to open `powerbi/Olist_Sales_Dashboard.pbix`

## One-time preparation
1. Put the 9 CSVs in a plain folder such as `C:\olist_dataset\archive\`. Do not use OneDrive, Desktop or Documents, because `BULK INSERT` runs as the SQL Server service account and cannot read personal folders.
2. Open `03_load_staging.sql` and edit the single line `DECLARE @DataPath ...` to your folder.

## Run order (one script at a time: click in the editor, Ctrl+A, F5)
| # | Script | What it does |
|---|--------|--------------|
| 1 | `01_create_database_and_schemas.sql` | Creates `Olist_DW` and the Staging, Warehouse and Mart schemas |
| 2 | `02_create_staging_tables.sql` | Creates 9 all-NVARCHAR staging tables |
| 3 | `03_load_staging.sql` | Bulk-loads the 9 CSV files into Staging |
| 4 | `04_verify_staging.sql` | Row counts, quote-contamination check, join integrity (expect all PASS) |
| 5 | `05_create_warehouse_tables.sql` | Creates the star schema: 6 dimensions + `Fact_Order_Sales` (7 tables) |
| 6 | `06_load_dimensions.sql` | Loads the six dimensions |
| 7 | `05a_profile_staging.sql` | Read-only profiling of Staging. It uses `Dim_Location`, so it runs after step 6 |
| 8 | `07_load_fact.sql` | Loads `Warehouse.Fact_Order_Sales` |
| 9 | `08_validate_etl.sql` | PASS/FAIL reconciliation of the warehouse against Staging |
| 10 | `09_create_sales_mart.sql` | Creates `Mart.vw_Sales_Detail`, `Mart.Sales_Monthly_Category` and the `sales_team` role |
| 11 | `10_mart_queries_validation.sql` | Reconciles the mart with the warehouse and runs example queries |

## Note on the review file
`documentation/04_Load_and_Transform_Reviews.sql` is NOT part of the run order. It records how the review file's multi-line comments were first handled (a raw all-text buffer table, then `TRY_CAST` validation). `03_load_staging.sql` now loads the reviews directly with `FORMAT = 'CSV'`, and the documentation script begins by truncating `stg_reviews` and refilling it from its own raw table, which could leave `stg_reviews` empty. Do not run it after `03`.

## Expected staging row counts
| Table | Rows |
|---|---|
| stg_orders | 99,441 |
| stg_order_items | 112,650 |
| stg_customers | 99,441 |
| stg_products | 32,951 |
| stg_sellers | 3,095 |
| stg_payments | 103,886 |
| stg_reviews | 99,224 |
| stg_geolocation | 1,000,163 |
| stg_category_translation | 71 |

## Key results after a full run
- Fact rows: 102,425. Units: 112,650. Revenue: 13,591,643.70. Freight: 2,251,909.54.
- Scripts 06, 07 and 09 are re-runnable.

## Power BI
The report reads `Mart.vw_Sales_Detail` and `Warehouse.Dim_Date`. Change the SQL Server connection to your own server name before refreshing.

## Troubleshooting
| Symptom | Fix |
|---|---|
| `Operating system error code 5 (Access is denied)` | Move the CSVs to a plain folder such as `C:\olist_dataset\archive\` |
| `Cannot bulk load ... could not be opened` | Check `@DataPath` and the file names |
| Load reports 0 rows and no error | Wrong `ROWTERMINATOR`; keep `0x0a` in `03_load_staging.sql` |
| `Incorrect syntax near 'CSV'` | SQL Server older than 2017 |
