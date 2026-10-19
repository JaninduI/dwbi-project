/* =====================================================================
   05a_profile_staging.sql
   Read-only data profiling on the Staging layer (and Dim_Location for
   zip lookups). Returns ONE result table: screenshot it for the report.
   Run AFTER 06_load_dimensions.sql (needs Warehouse.Dim_Location).
   ===================================================================== */
USE Olist_DW;
GO

SELECT * FROM (

/* ---- Row counts ---- */
SELECT 1 AS ord, 'customers: total rows' AS check_name, COUNT(*) AS n FROM Staging.stg_customers
UNION ALL SELECT 2, 'customers: distinct customer_id', COUNT(DISTINCT customer_id) FROM Staging.stg_customers
UNION ALL SELECT 3, 'customers: distinct customer_unique_id', COUNT(DISTINCT customer_unique_id) FROM Staging.stg_customers
UNION ALL SELECT 4, 'customers: blank/NULL city', COUNT(*) FROM Staging.stg_customers WHERE customer_city IS NULL OR LTRIM(RTRIM(customer_city)) = ''
UNION ALL SELECT 5, 'customers: city with leading/trailing spaces or upper-case letters', COUNT(*) FROM Staging.stg_customers WHERE customer_city <> LOWER(LTRIM(RTRIM(customer_city))) COLLATE Latin1_General_CS_AS
UNION ALL SELECT 6, 'customers: zip prefix not found in Dim_Location', COUNT(*) FROM Staging.stg_customers c
           WHERE NOT EXISTS (SELECT 1 FROM Warehouse.Dim_Location l WHERE l.zip_code_prefix = LTRIM(RTRIM(c.customer_zip_code_prefix)))

/* ---- Products ---- */
UNION ALL SELECT 10, 'products: total rows', COUNT(*) FROM Staging.stg_products
UNION ALL SELECT 11, 'products: blank/NULL category', COUNT(*) FROM Staging.stg_products WHERE product_category_name IS NULL OR LTRIM(RTRIM(product_category_name)) = ''
UNION ALL SELECT 12, 'products: category with no English translation', COUNT(*) FROM Staging.stg_products p
           WHERE NULLIF(LTRIM(RTRIM(p.product_category_name)), '') IS NOT NULL
             AND NOT EXISTS (SELECT 1 FROM Staging.stg_category_translation c WHERE LTRIM(RTRIM(c.product_category_name)) = LTRIM(RTRIM(p.product_category_name)))
UNION ALL SELECT 13, 'products: weight missing or not numeric', COUNT(*) FROM Staging.stg_products WHERE TRY_CAST(product_weight_g AS DECIMAL(10,2)) IS NULL
UNION ALL SELECT 14, 'products: any dimension (L/H/W) missing or not numeric', COUNT(*) FROM Staging.stg_products
           WHERE TRY_CAST(product_length_cm AS DECIMAL(10,2)) IS NULL OR TRY_CAST(product_height_cm AS DECIMAL(10,2)) IS NULL OR TRY_CAST(product_width_cm AS DECIMAL(10,2)) IS NULL

/* ---- Sellers ---- */
UNION ALL SELECT 20, 'sellers: total rows', COUNT(*) FROM Staging.stg_sellers
UNION ALL SELECT 21, 'sellers: distinct seller_id', COUNT(DISTINCT seller_id) FROM Staging.stg_sellers
UNION ALL SELECT 22, 'sellers: zip prefix not found in Dim_Location', COUNT(*) FROM Staging.stg_sellers s
           WHERE NOT EXISTS (SELECT 1 FROM Warehouse.Dim_Location l WHERE l.zip_code_prefix = LTRIM(RTRIM(s.seller_zip_code_prefix)))

/* ---- Geolocation ---- */
UNION ALL SELECT 30, 'geolocation: total rows', COUNT(*) FROM Staging.stg_geolocation
UNION ALL SELECT 31, 'geolocation: distinct zip prefixes', COUNT(DISTINCT geolocation_zip_code_prefix) FROM Staging.stg_geolocation
UNION ALL SELECT 32, 'geolocation: zip prefixes with more than one distinct coordinate pair', COUNT(*) FROM
           (SELECT geolocation_zip_code_prefix FROM Staging.stg_geolocation
            GROUP BY geolocation_zip_code_prefix
            HAVING COUNT(DISTINCT geolocation_lat + '|' + geolocation_lng) > 1) x
UNION ALL SELECT 33, 'geolocation: lat/lng missing or not numeric', COUNT(*) FROM Staging.stg_geolocation
           WHERE TRY_CAST(geolocation_lat AS DECIMAL(10,6)) IS NULL OR TRY_CAST(geolocation_lng AS DECIMAL(10,6)) IS NULL

/* ---- Orders ---- */
UNION ALL SELECT 40, 'orders: total rows', COUNT(*) FROM Staging.stg_orders
UNION ALL SELECT 41, 'orders: purchase timestamp not a valid date', COUNT(*) FROM Staging.stg_orders
           WHERE TRY_CAST(NULLIF(LTRIM(RTRIM(order_purchase_timestamp)), '') AS DATETIME) IS NULL
UNION ALL SELECT 42, 'orders: delivered status but no delivery date', COUNT(*) FROM Staging.stg_orders
           WHERE order_status = 'delivered' AND (order_delivered_customer_date IS NULL OR LTRIM(RTRIM(order_delivered_customer_date)) = '')
UNION ALL SELECT 43, 'orders: not delivered (delivery measures will be NULL)', COUNT(*) FROM Staging.stg_orders
           WHERE order_delivered_customer_date IS NULL OR LTRIM(RTRIM(order_delivered_customer_date)) = ''

/* ---- Order items (fact grain) ---- */
UNION ALL SELECT 50, 'order_items: total rows', COUNT(*) FROM Staging.stg_order_items
UNION ALL SELECT 51, 'order_items: distinct (order, product, seller) groups', COUNT(*) FROM
           (SELECT order_id, product_id, seller_id FROM Staging.stg_order_items GROUP BY order_id, product_id, seller_id) x
UNION ALL SELECT 52, 'order_items: groups with more than one row (aggregated into quantity)', COUNT(*) FROM
           (SELECT order_id, product_id, seller_id FROM Staging.stg_order_items GROUP BY order_id, product_id, seller_id HAVING COUNT(*) > 1) x
UNION ALL SELECT 53, 'order_items: price not numeric', COUNT(*) FROM Staging.stg_order_items WHERE TRY_CAST(price AS DECIMAL(12,2)) IS NULL

/* ---- Payments ---- */
UNION ALL SELECT 60, 'payments: total rows', COUNT(*) FROM Staging.stg_payments
UNION ALL SELECT 61, 'payments: distinct payment types', COUNT(DISTINCT LOWER(LTRIM(RTRIM(payment_type)))) FROM Staging.stg_payments
UNION ALL SELECT 62, 'payments: type = not_defined', COUNT(*) FROM Staging.stg_payments WHERE LOWER(LTRIM(RTRIM(payment_type))) = 'not_defined'
UNION ALL SELECT 63, 'payments: orders with more than one payment record', COUNT(*) FROM
           (SELECT order_id FROM Staging.stg_payments GROUP BY order_id HAVING COUNT(*) > 1) x

/* ---- Reviews ---- */
UNION ALL SELECT 70, 'reviews: total rows', COUNT(*) FROM Staging.stg_reviews
UNION ALL SELECT 71, 'reviews: orders with more than one review', COUNT(*) FROM
           (SELECT order_id FROM Staging.stg_reviews GROUP BY order_id HAVING COUNT(*) > 1) x
UNION ALL SELECT 72, 'reviews: score outside 1-5 or not numeric', COUNT(*) FROM Staging.stg_reviews
           WHERE TRY_CAST(review_score AS INT) IS NULL OR TRY_CAST(review_score AS INT) NOT BETWEEN 1 AND 5

) r
ORDER BY ord;
GO
