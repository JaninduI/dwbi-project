/* =====================================================================
   07_load_fact.sql
   Staging -> Warehouse.Fact_Order_Sales
   Grain: one row per (order_id, product_id, seller_id)
   Run AFTER 06_load_dimensions.sql. Re-runnable.

   Fact column names follow the Task 4 design. If SSMS reports
   "Invalid column name", compare with sp_help 'Warehouse.Fact_Order_Sales'.
   ===================================================================== */
USE Olist_DW;
GO
SET LANGUAGE us_english;
GO

/* ---------- 0. Reset ---------- */
DELETE FROM Warehouse.Fact_Order_Sales;
DBCC CHECKIDENT ('Warehouse.Fact_Order_Sales', RESEED, 0);
GO

/* ---------- 1. Load ---------- */
;WITH items AS      -- aggregate source order-item records to the fact grain
(
    SELECT
        LTRIM(RTRIM(order_id))   AS order_id,
        LTRIM(RTRIM(product_id)) AS product_id,
        LTRIM(RTRIM(seller_id))  AS seller_id,
        COUNT(*)                                        AS quantity,
        MAX(TRY_CAST(price         AS DECIMAL(12,2)))   AS unit_price,
        MAX(TRY_CAST(freight_value AS DECIMAL(12,2)))   AS unit_freight_value
    FROM Staging.stg_order_items
    GROUP BY LTRIM(RTRIM(order_id)), LTRIM(RTRIM(product_id)), LTRIM(RTRIM(seller_id))
),
ord AS              -- typed order dates (NULLIF guards against '' -> 1900-01-01)
(
    SELECT
        LTRIM(RTRIM(order_id))    AS order_id,
        LTRIM(RTRIM(customer_id)) AS customer_id,
        TRY_CAST(NULLIF(LTRIM(RTRIM(order_purchase_timestamp)),      '') AS DATETIME) AS purchase_ts,
        TRY_CAST(NULLIF(LTRIM(RTRIM(order_delivered_customer_date)), '') AS DATETIME) AS delivered_ts,
        TRY_CAST(NULLIF(LTRIM(RTRIM(order_estimated_delivery_date)), '') AS DATETIME) AS estimated_ts
    FROM Staging.stg_orders
),
pay_total AS        -- order-level payment totals (all payment records)
(
    SELECT
        LTRIM(RTRIM(order_id)) AS order_id,
        SUM(TRY_CAST(payment_value        AS DECIMAL(12,2))) AS total_value,
        SUM(TRY_CAST(payment_installments AS INT))           AS total_installments
    FROM Staging.stg_payments
    GROUP BY LTRIM(RTRIM(order_id))
),
pay_primary AS      -- primary payment type = highest payment_value (ties: lowest sequence)
(
    SELECT order_id, payment_type
    FROM (
        SELECT
            LTRIM(RTRIM(order_id))                 AS order_id,
            LOWER(LTRIM(RTRIM(payment_type)))      AS payment_type,
            ROW_NUMBER() OVER (
                PARTITION BY LTRIM(RTRIM(order_id))
                ORDER BY TRY_CAST(payment_value AS DECIMAL(12,2)) DESC,
                         TRY_CAST(payment_sequential AS INT) ASC) AS rn
        FROM Staging.stg_payments
    ) x
    WHERE rn = 1
),
rev AS              -- one review per order: the most recent by creation date
(
    SELECT order_id, review_score
    FROM (
        SELECT
            LTRIM(RTRIM(order_id))         AS order_id,
            TRY_CAST(review_score AS INT)  AS review_score,
            ROW_NUMBER() OVER (
                PARTITION BY LTRIM(RTRIM(order_id))
                ORDER BY TRY_CAST(NULLIF(LTRIM(RTRIM(review_creation_date)),   '') AS DATETIME) DESC,
                         TRY_CAST(NULLIF(LTRIM(RTRIM(review_answer_timestamp)), '') AS DATETIME) DESC,
                         review_id) AS rn
        FROM Staging.stg_reviews
    ) x
    WHERE rn = 1
)
INSERT INTO Warehouse.Fact_Order_Sales
(
    order_id,
    order_purchase_date_key,
    customer_key, customer_location_key,
    product_key,
    seller_key,   seller_location_key,
    payment_key,
    quantity, unit_price, total_price,
    unit_freight_value, total_freight_value,
    order_total_payment_value, order_total_installments,
    delivery_duration_days, is_delivered_late,
    review_score
)
SELECT
    i.order_id,
    ISNULL(dd.date_key,      -1),
    ISNULL(c.customer_key,   -1),
    ISNULL(cl.location_key,  -1),
    ISNULL(p.product_key,    -1),
    ISNULL(s.seller_key,     -1),
    ISNULL(sl.location_key,  -1),
    ISNULL(dp.payment_key,   -1),

    i.quantity,
    ISNULL(i.unit_price, 0),
    i.quantity * ISNULL(i.unit_price, 0),
    ISNULL(i.unit_freight_value, 0),
    i.quantity * ISNULL(i.unit_freight_value, 0),

    ISNULL(pt.total_value, 0),
    ISNULL(pt.total_installments, 0),

    -- whole calendar days between purchase and delivery; NULL if not delivered
    CASE WHEN o.purchase_ts IS NULL OR o.delivered_ts IS NULL THEN NULL
         ELSE DATEDIFF(DAY, CAST(o.purchase_ts AS DATE), CAST(o.delivered_ts AS DATE)) END,

    -- 1 if delivered after the estimated date; NULL if not delivered
    CASE WHEN o.delivered_ts IS NULL OR o.estimated_ts IS NULL THEN NULL
         WHEN CAST(o.delivered_ts AS DATE) > CAST(o.estimated_ts AS DATE) THEN 1
         ELSE 0 END,

    CASE WHEN r.review_score BETWEEN 1 AND 5 THEN r.review_score END

FROM items i
LEFT JOIN ord o                  ON o.order_id = i.order_id
LEFT JOIN Warehouse.Dim_Date dd  ON dd.full_date = CAST(o.purchase_ts AS DATE)
LEFT JOIN Warehouse.Dim_Customer c  ON c.customer_id = o.customer_id
LEFT JOIN Warehouse.Dim_Location cl ON cl.zip_code_prefix = c.customer_zip_prefix
LEFT JOIN Warehouse.Dim_Product  p  ON p.product_id = i.product_id
LEFT JOIN Warehouse.Dim_Seller   s  ON s.seller_id = i.seller_id
LEFT JOIN Warehouse.Dim_Location sl ON sl.zip_code_prefix = s.seller_zip_prefix
LEFT JOIN pay_total   pt         ON pt.order_id = i.order_id
LEFT JOIN pay_primary pp         ON pp.order_id = i.order_id
LEFT JOIN Warehouse.Dim_Payment dp ON dp.payment_type = pp.payment_type
LEFT JOIN rev r                  ON r.order_id = i.order_id;
GO

/* ---------- 2. Quick check (full validation is in 08_validate_etl.sql) ---------- */
SELECT
    COUNT(*)                                   AS fact_rows,            -- expect 102,425
    SUM(quantity)                              AS total_units,          -- expect = staging order_items rows
    SUM(total_price)                           AS fact_revenue,         -- expect = SUM(price) in staging
    SUM(total_freight_value)                   AS fact_freight,         -- expect = SUM(freight_value) in staging
    SUM(CASE WHEN customer_location_key = -1 THEN 1 ELSE 0 END) AS unknown_customer_location,
    SUM(CASE WHEN seller_location_key   = -1 THEN 1 ELSE 0 END) AS unknown_seller_location,
    SUM(CASE WHEN payment_key           = -1 THEN 1 ELSE 0 END) AS unknown_payment,
    SUM(CASE WHEN review_score IS NULL       THEN 1 ELSE 0 END) AS no_review,
    SUM(CASE WHEN delivery_duration_days IS NULL THEN 1 ELSE 0 END) AS not_delivered
FROM Warehouse.Fact_Order_Sales;

SELECT
    COUNT(*)                                   AS staging_item_rows,
    SUM(TRY_CAST(price AS DECIMAL(12,2)))         AS staging_revenue,
    SUM(TRY_CAST(freight_value AS DECIMAL(12,2))) AS staging_freight
FROM Staging.stg_order_items;
GO
