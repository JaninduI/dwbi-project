/* =====================================================================
   06_load_dimensions.sql
   Staging -> Warehouse dimension load (Olist_DW)
   - Preserves the -1 unknown-member rows created in 05_create_warehouse_tables.sql
   - Re-runnable: clears loaded rows (key <> -1) and reseeds identities
   ===================================================================== */
USE Olist_DW;
GO
SET LANGUAGE us_english;   -- English day/month names, Sunday = first day of week
GO

/* ---------- 0. Reset (fact first, because of FK constraints) ---------- */
DELETE FROM Warehouse.Fact_Order_Sales;

DELETE FROM Warehouse.Dim_Customer WHERE customer_key <> -1;
DELETE FROM Warehouse.Dim_Product  WHERE product_key  <> -1;
DELETE FROM Warehouse.Dim_Seller   WHERE seller_key   <> -1;
DELETE FROM Warehouse.Dim_Location WHERE location_key <> -1;
DELETE FROM Warehouse.Dim_Payment  WHERE payment_key  <> -1;
DELETE FROM Warehouse.Dim_Date     WHERE date_key     <> -1;

DBCC CHECKIDENT ('Warehouse.Fact_Order_Sales', RESEED, 0);
DBCC CHECKIDENT ('Warehouse.Dim_Customer',     RESEED, 0);
DBCC CHECKIDENT ('Warehouse.Dim_Product',      RESEED, 0);
DBCC CHECKIDENT ('Warehouse.Dim_Seller',       RESEED, 0);
DBCC CHECKIDENT ('Warehouse.Dim_Location',     RESEED, 0);
DBCC CHECKIDENT ('Warehouse.Dim_Payment',      RESEED, 0);
GO

/* ---------- 1. Dim_Date (calendar years covering purchase..estimated delivery) ---------- */
DECLARE @start DATE, @end DATE;

SELECT @start = DATEFROMPARTS(YEAR(MIN(TRY_CAST(order_purchase_timestamp AS DATE))), 1, 1),
       @end   = DATEFROMPARTS(YEAR(MAX(TRY_CAST(order_estimated_delivery_date AS DATE))), 12, 31)
FROM Staging.stg_orders;

;WITH Dates AS
(
    SELECT @start AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM Dates WHERE d < @end
)
INSERT INTO Warehouse.Dim_Date
    (date_key, full_date, day_of_month, day_name, day_of_week, is_weekend,
     month_number, month_name, quarter, year)
SELECT
    YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d),
    d,
    DAY(d),
    DATENAME(WEEKDAY, d),
    DATEPART(WEEKDAY, d),
    CASE WHEN DATEPART(WEEKDAY, d) IN (1, 7) THEN 1 ELSE 0 END,
    MONTH(d),
    DATENAME(MONTH, d),
    DATEPART(QUARTER, d),
    YEAR(d)
FROM Dates
OPTION (MAXRECURSION 0);
GO

/* ---------- 2. Dim_Customer ---------- */
INSERT INTO Warehouse.Dim_Customer
    (customer_id, customer_unique_id, customer_city, customer_state, customer_zip_prefix)
SELECT DISTINCT
    LTRIM(RTRIM(customer_id)),
    LTRIM(RTRIM(customer_unique_id)),
    ISNULL(NULLIF(LOWER(LTRIM(RTRIM(customer_city))), ''), 'unknown'),
    ISNULL(NULLIF(UPPER(LTRIM(RTRIM(customer_state))), ''), 'NA'),
    LTRIM(RTRIM(customer_zip_code_prefix))
FROM Staging.stg_customers
WHERE customer_id IS NOT NULL;
GO

/* ---------- 3. Dim_Product ---------- */
INSERT INTO Warehouse.Dim_Product
    (product_id, category_name_pt, category_name_en,
     product_weight_g, product_length_cm, product_height_cm, product_width_cm)
SELECT DISTINCT
    LTRIM(RTRIM(p.product_id)),
    NULLIF(LTRIM(RTRIM(p.product_category_name)), ''),
    COALESCE(NULLIF(LTRIM(RTRIM(c.product_category_name_english)), ''),
             NULLIF(LTRIM(RTRIM(p.product_category_name)), ''),
             'Unknown'),
    TRY_CAST(p.product_weight_g  AS DECIMAL(10,2)),
    TRY_CAST(p.product_length_cm AS DECIMAL(10,2)),
    TRY_CAST(p.product_height_cm AS DECIMAL(10,2)),
    TRY_CAST(p.product_width_cm  AS DECIMAL(10,2))
FROM Staging.stg_products p
LEFT JOIN Staging.stg_category_translation c
       ON LTRIM(RTRIM(p.product_category_name)) = LTRIM(RTRIM(c.product_category_name))
WHERE p.product_id IS NOT NULL;
GO

/* ---------- 4. Dim_Seller ---------- */
INSERT INTO Warehouse.Dim_Seller
    (seller_id, seller_city, seller_state, seller_zip_prefix)
SELECT DISTINCT
    LTRIM(RTRIM(seller_id)),
    ISNULL(NULLIF(LOWER(LTRIM(RTRIM(seller_city))), ''), 'unknown'),
    ISNULL(NULLIF(UPPER(LTRIM(RTRIM(seller_state))), ''), 'NA'),
    LTRIM(RTRIM(seller_zip_code_prefix))
FROM Staging.stg_sellers
WHERE seller_id IS NOT NULL;
GO

/* ---------- 5. Dim_Location: exactly ONE row per zip prefix ---------- */
;WITH g AS
(
    SELECT
        LTRIM(RTRIM(geolocation_zip_code_prefix))       AS zip,
        LOWER(LTRIM(RTRIM(geolocation_city)))           AS city,
        UPPER(LTRIM(RTRIM(geolocation_state)))          AS state,
        TRY_CAST(geolocation_lat AS DECIMAL(10,6))      AS lat,
        TRY_CAST(geolocation_lng AS DECIMAL(10,6))      AS lng
    FROM Staging.stg_geolocation
    WHERE geolocation_zip_code_prefix IS NOT NULL
),
coords AS
(
    SELECT zip,
           CAST(AVG(lat) AS DECIMAL(10,6)) AS latitude,
           CAST(AVG(lng) AS DECIMAL(10,6)) AS longitude
    FROM g
    WHERE lat IS NOT NULL AND lng IS NOT NULL
    GROUP BY zip
),
city_pick AS   -- most frequent city/state spelling per zip
(
    SELECT zip, city, state,
           ROW_NUMBER() OVER (PARTITION BY zip ORDER BY COUNT(*) DESC, city) AS rn
    FROM g
    GROUP BY zip, city, state
)
INSERT INTO Warehouse.Dim_Location (zip_code_prefix, city, state, latitude, longitude)
SELECT cp.zip, cp.city, cp.state, co.latitude, co.longitude
FROM city_pick cp
JOIN coords co ON co.zip = cp.zip
WHERE cp.rn = 1;
GO

/* ---------- 6. Dim_Payment ---------- */
INSERT INTO Warehouse.Dim_Payment (payment_type)
SELECT DISTINCT LOWER(LTRIM(RTRIM(payment_type)))
FROM Staging.stg_payments
WHERE payment_type IS NOT NULL AND LTRIM(RTRIM(payment_type)) <> '';
GO

/* ---------- 7. Quick verification ---------- */
SELECT 'Dim_Customer' AS tbl, COUNT(*) AS total_rows, SUM(CASE WHEN customer_key = -1 THEN 1 ELSE 0 END) AS unknown_rows FROM Warehouse.Dim_Customer
UNION ALL SELECT 'Dim_Product',  COUNT(*), SUM(CASE WHEN product_key  = -1 THEN 1 ELSE 0 END) FROM Warehouse.Dim_Product
UNION ALL SELECT 'Dim_Seller',   COUNT(*), SUM(CASE WHEN seller_key   = -1 THEN 1 ELSE 0 END) FROM Warehouse.Dim_Seller
UNION ALL SELECT 'Dim_Location', COUNT(*), SUM(CASE WHEN location_key = -1 THEN 1 ELSE 0 END) FROM Warehouse.Dim_Location
UNION ALL SELECT 'Dim_Payment',  COUNT(*), SUM(CASE WHEN payment_key  = -1 THEN 1 ELSE 0 END) FROM Warehouse.Dim_Payment
UNION ALL SELECT 'Dim_Date',     COUNT(*), SUM(CASE WHEN date_key     = -1 THEN 1 ELSE 0 END) FROM Warehouse.Dim_Date;

-- Must return 0 rows (one location row per zip prefix)
SELECT zip_code_prefix, COUNT(*) AS n
FROM Warehouse.Dim_Location
GROUP BY zip_code_prefix
HAVING COUNT(*) > 1;
GO
