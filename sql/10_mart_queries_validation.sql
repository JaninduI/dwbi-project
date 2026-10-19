/* =====================================================================
   10_mart_queries_validation.sql
   A) Reconciliation of the mart against the warehouse fact table
   B) Example analytical queries a sales analyst would run
   Screenshot each result grid for the report.
   ===================================================================== */
USE Olist_DW;
GO

/* ---------- A. Reconciliation ---------- */
SELECT metric, warehouse_value, mart_view, mart_table,
       CASE WHEN warehouse_value = mart_view
             AND (mart_table IS NULL OR warehouse_value = mart_table)
            THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
    SELECT 'Fact rows / view rows' AS metric,
           CAST((SELECT COUNT(*) FROM Warehouse.Fact_Order_Sales) AS DECIMAL(18,2)) AS warehouse_value,
           CAST((SELECT COUNT(*) FROM Mart.vw_Sales_Detail)       AS DECIMAL(18,2)) AS mart_view,
           CAST(NULL AS DECIMAL(18,2)) AS mart_table
    UNION ALL
    SELECT 'Units',
           CAST((SELECT SUM(quantity)   FROM Warehouse.Fact_Order_Sales)       AS DECIMAL(18,2)),
           CAST((SELECT SUM(units)      FROM Mart.vw_Sales_Detail)             AS DECIMAL(18,2)),
           CAST((SELECT SUM(units)      FROM Mart.Sales_Monthly_Category)      AS DECIMAL(18,2))
    UNION ALL
    SELECT 'Item revenue',
           CAST((SELECT SUM(total_price) FROM Warehouse.Fact_Order_Sales)      AS DECIMAL(18,2)),
           CAST((SELECT SUM(item_revenue) FROM Mart.vw_Sales_Detail)           AS DECIMAL(18,2)),
           CAST((SELECT SUM(revenue)     FROM Mart.Sales_Monthly_Category)     AS DECIMAL(18,2))
    UNION ALL
    SELECT 'Freight',
           CAST((SELECT SUM(total_freight_value) FROM Warehouse.Fact_Order_Sales) AS DECIMAL(18,2)),
           CAST((SELECT SUM(freight_value)       FROM Mart.vw_Sales_Detail)       AS DECIMAL(18,2)),
           CAST((SELECT SUM(freight)             FROM Mart.Sales_Monthly_Category) AS DECIMAL(18,2))
    UNION ALL
    SELECT 'Distinct orders',
           CAST((SELECT COUNT(DISTINCT order_id) FROM Warehouse.Fact_Order_Sales) AS DECIMAL(18,2)),
           CAST((SELECT COUNT(DISTINCT order_id) FROM Mart.vw_Sales_Detail)       AS DECIMAL(18,2)),
           CAST(NULL AS DECIMAL(18,2))
) r;
GO

/* ---------- B1. Top 10 product categories by revenue (from the aggregate table) ---------- */
SELECT TOP 10
    category_name_en,
    SUM(units)   AS units,
    SUM(revenue) AS revenue,
    SUM(freight) AS freight
FROM Mart.Sales_Monthly_Category
GROUP BY category_name_en
ORDER BY SUM(revenue) DESC;
GO

/* ---------- B2. Monthly trend: orders, revenue, average order value (from the view) ---------- */
SELECT
    order_year,
    order_month_number,
    COUNT(DISTINCT order_id)                                   AS orders,
    SUM(units)                                                 AS units,
    SUM(item_revenue)                                          AS revenue,
    CAST(SUM(item_revenue) / COUNT(DISTINCT order_id) AS DECIMAL(10,2)) AS avg_order_value
FROM Mart.vw_Sales_Detail
GROUP BY order_year, order_month_number
ORDER BY order_year, order_month_number;
GO

/* ---------- B3. Top 10 customer states by revenue (from the view) ---------- */
SELECT TOP 10
    customer_state,
    COUNT(DISTINCT order_id)      AS orders,
    COUNT(DISTINCT customer_unique_id) AS customers,
    SUM(item_revenue)             AS revenue,
    CAST(SUM(item_revenue) / COUNT(DISTINCT order_id) AS DECIMAL(10,2)) AS avg_order_value
FROM Mart.vw_Sales_Detail
GROUP BY customer_state
ORDER BY SUM(item_revenue) DESC;
GO
