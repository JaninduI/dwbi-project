/* =====================================================================
   04_verify_staging.sql
   Purpose : Proves the staging load is complete and uncorrupted.
   Run after 03_load_staging.sql. Screenshot the 3 result sets for the
   Task 5 report ("Validation results").

   Expected values were computed from the real CSV files.
   ===================================================================== */
USE Olist_DW;
GO

/* ---- 1. Row counts vs. the source files ---------------------------- */
;WITH actual AS (
    SELECT N'stg_orders' AS table_name, COUNT(*) AS actual_rows FROM Staging.stg_orders
    UNION ALL SELECT N'stg_order_items',          COUNT(*) FROM Staging.stg_order_items
    UNION ALL SELECT N'stg_customers',            COUNT(*) FROM Staging.stg_customers
    UNION ALL SELECT N'stg_products',             COUNT(*) FROM Staging.stg_products
    UNION ALL SELECT N'stg_sellers',              COUNT(*) FROM Staging.stg_sellers
    UNION ALL SELECT N'stg_payments',             COUNT(*) FROM Staging.stg_payments
    UNION ALL SELECT N'stg_reviews',              COUNT(*) FROM Staging.stg_reviews
    UNION ALL SELECT N'stg_geolocation',          COUNT(*) FROM Staging.stg_geolocation
    UNION ALL SELECT N'stg_category_translation', COUNT(*) FROM Staging.stg_category_translation
),
expected AS (
    SELECT * FROM (VALUES
        (N'stg_orders',               99441),
        (N'stg_order_items',         112650),
        (N'stg_customers',            99441),
        (N'stg_products',             32951),
        (N'stg_sellers',               3095),
        (N'stg_payments',            103886),
        (N'stg_reviews',              99224),
        (N'stg_geolocation',        1000163),
        (N'stg_category_translation',    71)
    ) v(table_name, expected_rows)
)
SELECT a.table_name, a.actual_rows, e.expected_rows,
       CASE WHEN a.actual_rows = e.expected_rows THEN 'PASS' ELSE 'FAIL' END AS result
FROM actual a JOIN expected e ON e.table_name = a.table_name
ORDER BY a.table_name;

/* ---- 2. Quote-contamination check (all must be 0) ------------------
   If FORMAT='CSV' was NOT used, stray " characters end up in the data. */
SELECT N'orders keys'        AS check_name, COUNT(*) AS bad_rows FROM Staging.stg_orders
    WHERE order_id LIKE N'%"%' OR customer_id LIKE N'%"%'
UNION ALL SELECT N'order_items keys',  COUNT(*) FROM Staging.stg_order_items
    WHERE order_id LIKE N'%"%' OR product_id LIKE N'%"%' OR seller_id LIKE N'%"%'
UNION ALL SELECT N'customers keys',    COUNT(*) FROM Staging.stg_customers
    WHERE customer_id LIKE N'%"%' OR customer_unique_id LIKE N'%"%' OR customer_zip_code_prefix LIKE N'%"%'
UNION ALL SELECT N'sellers keys',      COUNT(*) FROM Staging.stg_sellers
    WHERE seller_id LIKE N'%"%' OR seller_zip_code_prefix LIKE N'%"%'
UNION ALL SELECT N'products keys',     COUNT(*) FROM Staging.stg_products
    WHERE product_id LIKE N'%"%'
UNION ALL SELECT N'reviews keys',      COUNT(*) FROM Staging.stg_reviews
    WHERE review_id LIKE N'%"%' OR order_id LIKE N'%"%';

/* ---- 3. Join integrity (all must be 0) ------------------------------ */
SELECT N'orders without customer' AS check_name, COUNT(*) AS orphan_rows
FROM Staging.stg_orders o
LEFT JOIN Staging.stg_customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL
UNION ALL
SELECT N'order_items without order', COUNT(*)
FROM Staging.stg_order_items i
LEFT JOIN Staging.stg_orders o ON o.order_id = i.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT N'order_items without product', COUNT(*)
FROM Staging.stg_order_items i
LEFT JOIN Staging.stg_products p ON p.product_id = i.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT N'order_items without seller', COUNT(*)
FROM Staging.stg_order_items i
LEFT JOIN Staging.stg_sellers s ON s.seller_id = i.seller_id
WHERE s.seller_id IS NULL
UNION ALL
SELECT N'payments without order', COUNT(*)
FROM Staging.stg_payments p
LEFT JOIN Staging.stg_orders o ON o.order_id = p.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT N'reviews without order', COUNT(*)
FROM Staging.stg_reviews r
LEFT JOIN Staging.stg_orders o ON o.order_id = r.order_id
WHERE o.order_id IS NULL;

/* ---- 4. Known tricky rows and expected blanks ----------------------- */
-- Expect 2 rows: cities that contain commas inside quotes
--   'novo hamburgo, rio grande do sul, brasil' (RS)
--   'rio de janeiro, rio de janeiro, brasil'   (RJ)
SELECT seller_city, seller_state
FROM Staging.stg_sellers
WHERE seller_city LIKE N'%,%';

-- Expect 2965 (orders never delivered) and 610 (products with no category)
SELECT
    (SELECT COUNT(*) FROM Staging.stg_orders
       WHERE NULLIF(LTRIM(RTRIM(order_delivered_customer_date)), N'') IS NULL) AS blank_delivered_customer_date,
    (SELECT COUNT(*) FROM Staging.stg_products
       WHERE NULLIF(LTRIM(RTRIM(product_category_name)), N'') IS NULL)         AS blank_product_category;
GO
