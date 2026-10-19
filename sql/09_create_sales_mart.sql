/* =====================================================================
   09_create_sales_mart.sql
   Sales Performance Data Mart (schema Mart) built on the Warehouse star schema.
   Objects:
     Mart.vw_Sales_Detail          flattened view at the fact grain
     Mart.Sales_Monthly_Category   pre-aggregated table (month x category)
     Role sales_team               read-only access to the Mart schema
   Re-runnable. Run after 07_load_fact.sql.
   ===================================================================== */
USE Olist_DW;
GO

/* ---------- 1. Schema ---------- */
IF SCHEMA_ID('Mart') IS NULL EXEC('CREATE SCHEMA Mart');
GO

/* ---------- 2. Flattened detail view (fact grain: order, product, seller) ---------- */
CREATE OR ALTER VIEW Mart.vw_Sales_Detail
AS
SELECT
    f.order_sales_key,
    f.order_id,

    d.full_date            AS order_date,
    d.year                 AS order_year,
    d.quarter              AS order_quarter,
    d.month_number         AS order_month_number,
    d.month_name           AS order_month_name,
    d.day_name             AS order_day_name,
    d.is_weekend           AS is_weekend_order,

    p.product_id,
    p.category_name_en     AS product_category,

    s.seller_id,
    s.seller_city,
    s.seller_state,

    c.customer_unique_id,
    c.customer_city,
    c.customer_state,

    pay.payment_type       AS primary_payment_type,

    f.quantity             AS units,
    f.unit_price,
    f.total_price          AS item_revenue,
    f.total_freight_value  AS freight_value,
    f.total_price + f.total_freight_value AS gross_value
FROM Warehouse.Fact_Order_Sales f
JOIN Warehouse.Dim_Date     d   ON d.date_key     = f.order_purchase_date_key
JOIN Warehouse.Dim_Product  p   ON p.product_key  = f.product_key
JOIN Warehouse.Dim_Seller   s   ON s.seller_key   = f.seller_key
JOIN Warehouse.Dim_Customer c   ON c.customer_key = f.customer_key
JOIN Warehouse.Dim_Payment  pay ON pay.payment_key = f.payment_key;
GO

/* ---------- 3. Pre-aggregated table (grain: year-month x product category) ---------- */
IF OBJECT_ID('Mart.Sales_Monthly_Category', 'U') IS NOT NULL
    DROP TABLE Mart.Sales_Monthly_Category;
GO

CREATE TABLE Mart.Sales_Monthly_Category
(
    sales_year        SMALLINT      NOT NULL,
    month_number      TINYINT       NOT NULL,
    year_month        CHAR(7)       NOT NULL,   -- 'YYYY-MM'
    month_name        VARCHAR(20)   NOT NULL,
    category_name_en  NVARCHAR(200) NOT NULL,
    orders            INT           NOT NULL,   -- distinct orders in this group (NOT additive across categories)
    units             INT           NOT NULL,
    revenue           DECIMAL(14,2) NOT NULL,   -- item revenue, excludes freight
    freight           DECIMAL(14,2) NOT NULL,
    CONSTRAINT PK_Sales_Monthly_Category PRIMARY KEY (year_month, category_name_en)
);
GO

INSERT INTO Mart.Sales_Monthly_Category
    (sales_year, month_number, year_month, month_name, category_name_en, orders, units, revenue, freight)
SELECT
    d.year,
    d.month_number,
    CONCAT(d.year, '-', RIGHT('0' + CAST(d.month_number AS VARCHAR(2)), 2)),
    d.month_name,
    ISNULL(p.category_name_en, 'Unknown'),
    COUNT(DISTINCT f.order_id),
    SUM(f.quantity),
    SUM(f.total_price),
    SUM(f.total_freight_value)
FROM Warehouse.Fact_Order_Sales f
JOIN Warehouse.Dim_Date    d ON d.date_key    = f.order_purchase_date_key
JOIN Warehouse.Dim_Product p ON p.product_key = f.product_key
GROUP BY d.year, d.month_number, d.month_name, ISNULL(p.category_name_en, 'Unknown');
GO

/* ---------- 4. Department access: read-only role on the Mart schema ---------- */
IF DATABASE_PRINCIPAL_ID('sales_team') IS NULL
    CREATE ROLE sales_team;
GO
GRANT SELECT ON SCHEMA::Mart TO sales_team;
GO

/* ---------- 5. Quick check ---------- */
SELECT 'Mart.vw_Sales_Detail'        AS mart_object, COUNT(*) AS row_count FROM Mart.vw_Sales_Detail
UNION ALL
SELECT 'Mart.Sales_Monthly_Category',                COUNT(*)              FROM Mart.Sales_Monthly_Category;
GO
