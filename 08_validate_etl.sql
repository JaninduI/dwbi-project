/* =====================================================================
   08_validate_etl.sql
   Post-load validation of Warehouse.Fact_Order_Sales against Staging.
   Result set 1: PASS/FAIL table (screenshot for the report).
   Result set 2: unknown-member usage (informational).
   ===================================================================== */
USE Olist_DW;
GO

SELECT ord, check_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS status
FROM (

/* ---- Reconciliation against staging ---- */
SELECT 1 AS ord, 'Fact rows = distinct (order, product, seller) groups in staging' AS check_name,
       CAST((SELECT COUNT(*) FROM (SELECT 1 AS x FROM Staging.stg_order_items
             GROUP BY LTRIM(RTRIM(order_id)), LTRIM(RTRIM(product_id)), LTRIM(RTRIM(seller_id))) g) AS DECIMAL(18,2)) AS expected,
       CAST((SELECT COUNT(*) FROM Warehouse.Fact_Order_Sales) AS DECIMAL(18,2)) AS actual
UNION ALL SELECT 2, 'Total units = staging order_items rows',
       CAST((SELECT COUNT(*) FROM Staging.stg_order_items) AS DECIMAL(18,2)),
       CAST((SELECT SUM(quantity) FROM Warehouse.Fact_Order_Sales) AS DECIMAL(18,2))
UNION ALL SELECT 3, 'Revenue: SUM(total_price) = staging SUM(price)',
       CAST((SELECT SUM(TRY_CAST(price AS DECIMAL(12,2))) FROM Staging.stg_order_items) AS DECIMAL(18,2)),
       CAST((SELECT SUM(total_price) FROM Warehouse.Fact_Order_Sales) AS DECIMAL(18,2))
UNION ALL SELECT 4, 'Freight: SUM(total_freight_value) = staging SUM(freight_value)',
       CAST((SELECT SUM(TRY_CAST(freight_value AS DECIMAL(12,2))) FROM Staging.stg_order_items) AS DECIMAL(18,2)),
       CAST((SELECT SUM(total_freight_value) FROM Warehouse.Fact_Order_Sales) AS DECIMAL(18,2))
UNION ALL SELECT 5, 'Distinct orders in fact = distinct orders in staging order_items',
       CAST((SELECT COUNT(DISTINCT LTRIM(RTRIM(order_id))) FROM Staging.stg_order_items) AS DECIMAL(18,2)),
       CAST((SELECT COUNT(DISTINCT order_id) FROM Warehouse.Fact_Order_Sales) AS DECIMAL(18,2))

/* ---- Grain ---- */
UNION ALL SELECT 6, 'Duplicate grain rows (order_id, product_key, seller_key)', 0,
       CAST((SELECT COUNT(*) FROM (SELECT 1 AS x FROM Warehouse.Fact_Order_Sales
             GROUP BY order_id, product_key, seller_key HAVING COUNT(*) > 1) d) AS DECIMAL(18,2))

/* ---- Orphan foreign keys ---- */
UNION ALL SELECT 7, 'Orphan keys: order_purchase_date_key', 0,
       CAST((SELECT COUNT(*) FROM Warehouse.Fact_Order_Sales f WHERE NOT EXISTS (SELECT 1 FROM Warehouse.Dim_Date d WHERE d.date_key = f.order_purchase_date_key)) AS DECIMAL(18,2))
UNION ALL SELECT 8, 'Orphan keys: customer_key', 0,
       CAST((SELECT COUNT(*) FROM Warehouse.Fact_Order_Sales f WHERE NOT EXISTS (SELECT 1 FROM Warehouse.Dim_Customer d WHERE d.customer_key = f.customer_key)) AS DECIMAL(18,2))
UNION ALL SELECT 9, 'Orphan keys: customer_location_key', 0,
       CAST((SELECT COUNT(*) FROM Warehouse.Fact_Order_Sales f WHERE NOT EXISTS (SELECT 1 FROM Warehouse.Dim_Location d WHERE d.location_key = f.customer_location_key)) AS DECIMAL(18,2))
UNION ALL SELECT 10, 'Orphan keys: product_key', 0,
       CAST((SELECT COUNT(*) FROM Warehouse.Fact_Order_Sales f WHERE NOT EXISTS (SELECT 1 FROM Warehouse.Dim_Product d WHERE d.product_key = f.product_key)) AS DECIMAL(18,2))
UNION ALL SELECT 11, 'Orphan keys: seller_key', 0,
       CAST((SELECT COUNT(*) FROM Warehouse.Fact_Order_Sales f WHERE NOT EXISTS (SELECT 1 FROM Warehouse.Dim_Seller d WHERE d.seller_key = f.seller_key)) AS DECIMAL(18,2))
UNION ALL SELECT 12, 'Orphan keys: seller_location_key', 0,
       CAST((SELECT COUNT(*) FROM Warehouse.Fact_Order_Sales f WHERE NOT EXISTS (SELECT 1 FROM Warehouse.Dim_Location d WHERE d.location_key = f.seller_location_key)) AS DECIMAL(18,2))
UNION ALL SELECT 13, 'Orphan keys: payment_key', 0,
       CAST((SELECT COUNT(*) FROM Warehouse.Fact_Order_Sales f WHERE NOT EXISTS (SELECT 1 FROM Warehouse.Dim_Payment d WHERE d.payment_key = f.payment_key)) AS DECIMAL(18,2))

/* ---- Order-level measures replicated consistently ---- */
UNION ALL SELECT 14, 'Orders with inconsistent review_score across their lines', 0,
       CAST((SELECT COUNT(*) FROM (SELECT 1 AS x FROM Warehouse.Fact_Order_Sales
             GROUP BY order_id HAVING COUNT(DISTINCT review_score) > 1) d) AS DECIMAL(18,2))
UNION ALL SELECT 15, 'Orders with inconsistent order_total_payment_value across their lines', 0,
       CAST((SELECT COUNT(*) FROM (SELECT 1 AS x FROM Warehouse.Fact_Order_Sales
             GROUP BY order_id HAVING COUNT(DISTINCT order_total_payment_value) > 1) d) AS DECIMAL(18,2))
UNION ALL SELECT 16, 'Payment total (one value per order) = staging SUM(payment_value) for fact orders',
       CAST((SELECT SUM(TRY_CAST(payment_value AS DECIMAL(12,2))) FROM Staging.stg_payments
             WHERE LTRIM(RTRIM(order_id)) IN (SELECT DISTINCT LTRIM(RTRIM(order_id)) FROM Staging.stg_order_items)) AS DECIMAL(18,2)),
       CAST((SELECT SUM(v) FROM (SELECT MAX(order_total_payment_value) AS v FROM Warehouse.Fact_Order_Sales GROUP BY order_id) o) AS DECIMAL(18,2))
UNION ALL SELECT 17, 'review_score outside 1-5', 0,
       CAST((SELECT COUNT(*) FROM Warehouse.Fact_Order_Sales WHERE review_score IS NOT NULL AND review_score NOT BETWEEN 1 AND 5) AS DECIMAL(18,2))

/* ---- Unknown-member explanations ---- */
UNION ALL SELECT 18, 'Rows with payment_key = -1 = fact rows whose order has no payment record in staging',
       CAST((SELECT COUNT(*) FROM Warehouse.Fact_Order_Sales f
             WHERE NOT EXISTS (SELECT 1 FROM Staging.stg_payments p WHERE LTRIM(RTRIM(p.order_id)) = f.order_id)) AS DECIMAL(18,2)),
       CAST((SELECT COUNT(*) FROM Warehouse.Fact_Order_Sales WHERE payment_key = -1) AS DECIMAL(18,2))

) v
ORDER BY ord;

/* ---- Unknown-member usage (informational) ---- */
SELECT 'order_purchase_date_key' AS fk, COUNT(*) AS rows_using_unknown_member FROM Warehouse.Fact_Order_Sales WHERE order_purchase_date_key = -1
UNION ALL SELECT 'customer_key',          COUNT(*) FROM Warehouse.Fact_Order_Sales WHERE customer_key = -1
UNION ALL SELECT 'customer_location_key', COUNT(*) FROM Warehouse.Fact_Order_Sales WHERE customer_location_key = -1
UNION ALL SELECT 'product_key',           COUNT(*) FROM Warehouse.Fact_Order_Sales WHERE product_key = -1
UNION ALL SELECT 'seller_key',            COUNT(*) FROM Warehouse.Fact_Order_Sales WHERE seller_key = -1
UNION ALL SELECT 'seller_location_key',   COUNT(*) FROM Warehouse.Fact_Order_Sales WHERE seller_location_key = -1
UNION ALL SELECT 'payment_key',           COUNT(*) FROM Warehouse.Fact_Order_Sales WHERE payment_key = -1;
GO
