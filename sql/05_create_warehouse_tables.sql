/* =====================================================================
   05_create_warehouse_tables.sql
   Purpose : Creates the Warehouse star schema (Task 4).
             Structure only - no data. Loading happens in Task 5's ETL
             scripts (06_load_dimensions.sql, 07_load_fact.sql).

   Business process : Product-level sales transactions (order fulfilment)
   Grain             : One row = one product, from one seller, within
                        one order (order_id + product_id + seller_id).
                        See the report, Task 4, for the full justification
                        (order_items repeats a row per physical unit; price
                        and freight_value are verified constant within an
                        order+product+seller group, so aggregating to this
                        grain with an explicit "quantity" measure is lossless).

   Design assumptions (documented, not accidental):
     - order_id is kept as a degenerate dimension on the fact table so BI
       tools can de-duplicate order-level measures (review_score,
       delivery_duration_days, order_total_payment_value) rather than
       double-counting them across a multi-line order.
     - Dim_Location is one shared dimension, referenced twice (customer
       side and seller side), consistent with Task 3's design decision.
     - Dim_Payment holds a small set of payment TYPES. An order's
       payment_key is its DOMINANT payment type (the payment record with
       the highest payment_value for that order); order_total_payment_value
       and order_total_installments are summed across all payment records
       for the order (verified: only 2,961 of 99,440 orders have more than
       one payment record).
     - Every dimension has an "Unknown" row at surrogate key -1, so a fact
       row can always be linked even when a lookup value is missing.

   Safe to re-run: drops and recreates all Warehouse tables.
   ===================================================================== */
USE Olist_DW;
GO

DROP TABLE IF EXISTS Warehouse.Fact_Order_Sales;
DROP TABLE IF EXISTS Warehouse.Dim_Date;
DROP TABLE IF EXISTS Warehouse.Dim_Customer;
DROP TABLE IF EXISTS Warehouse.Dim_Product;
DROP TABLE IF EXISTS Warehouse.Dim_Seller;
DROP TABLE IF EXISTS Warehouse.Dim_Location;
DROP TABLE IF EXISTS Warehouse.Dim_Payment;
GO

/* ---------------------------------------------------------------------
   Dim_Date : one row per calendar day covering the dataset's date range
   (2016-09-01 to 2018-12-31 comfortably covers all order timestamps).
   date_key is a Kimball-style YYYYMMDD integer surrogate key.
   --------------------------------------------------------------------- */
CREATE TABLE Warehouse.Dim_Date
(
    date_key        INT          NOT NULL PRIMARY KEY,   -- e.g. 20170815
    full_date       DATE         NOT NULL,
    day_of_month    TINYINT      NOT NULL,
    day_name        NVARCHAR(10) NOT NULL,
    day_of_week     TINYINT      NOT NULL,                -- 1=Sunday .. 7=Saturday
    is_weekend      BIT          NOT NULL,
    month_number    TINYINT      NOT NULL,
    month_name      NVARCHAR(10) NOT NULL,
    quarter         TINYINT      NOT NULL,
    year            SMALLINT     NOT NULL
);
GO
-- Unknown-date placeholder row
INSERT INTO Warehouse.Dim_Date
    (date_key, full_date, day_of_month, day_name, day_of_week, is_weekend,
     month_number, month_name, quarter, year)
VALUES (-1, '1900-01-01', 1, N'Unknown', 1, 0, 1, N'Unknown', 1, 1900);
GO

/* ---------------------------------------------------------------------
   Dim_Customer
   --------------------------------------------------------------------- */
CREATE TABLE Warehouse.Dim_Customer
(
    customer_key         INT IDENTITY(1,1) PRIMARY KEY,
    customer_id          NVARCHAR(50)  NOT NULL,   -- natural key (per-order id in source)
    customer_unique_id   NVARCHAR(50)  NULL,       -- stable id for the same real person
    customer_city        NVARCHAR(100) NULL,
    customer_state       NVARCHAR(5)   NULL,
    customer_zip_prefix  NVARCHAR(10)  NULL
);
GO
SET IDENTITY_INSERT Warehouse.Dim_Customer ON;
INSERT INTO Warehouse.Dim_Customer (customer_key, customer_id, customer_unique_id, customer_city, customer_state, customer_zip_prefix)
VALUES (-1, N'UNKNOWN', N'UNKNOWN', N'Unknown', N'NA', N'00000');
SET IDENTITY_INSERT Warehouse.Dim_Customer OFF;
GO

/* ---------------------------------------------------------------------
   Dim_Product
   --------------------------------------------------------------------- */
CREATE TABLE Warehouse.Dim_Product
(
    product_key            INT IDENTITY(1,1) PRIMARY KEY,
    product_id             NVARCHAR(50)  NOT NULL,
    category_name_pt       NVARCHAR(100) NULL,      -- original Portuguese category
    category_name_en       NVARCHAR(100) NULL,      -- translated English category
    product_weight_g       DECIMAL(10,2) NULL,
    product_length_cm      DECIMAL(10,2) NULL,
    product_height_cm      DECIMAL(10,2) NULL,
    product_width_cm       DECIMAL(10,2) NULL
);
GO
SET IDENTITY_INSERT Warehouse.Dim_Product ON;
INSERT INTO Warehouse.Dim_Product
    (product_key, product_id, category_name_pt, category_name_en,
     product_weight_g, product_length_cm, product_height_cm, product_width_cm)
VALUES (-1, N'UNKNOWN', N'Unknown', N'Unknown', NULL, NULL, NULL, NULL);
SET IDENTITY_INSERT Warehouse.Dim_Product OFF;
GO

/* ---------------------------------------------------------------------
   Dim_Seller
   --------------------------------------------------------------------- */
CREATE TABLE Warehouse.Dim_Seller
(
    seller_key           INT IDENTITY(1,1) PRIMARY KEY,
    seller_id            NVARCHAR(50)  NOT NULL,
    seller_city          NVARCHAR(100) NULL,
    seller_state         NVARCHAR(5)   NULL,
    seller_zip_prefix    NVARCHAR(10)  NULL
);
GO
SET IDENTITY_INSERT Warehouse.Dim_Seller ON;
INSERT INTO Warehouse.Dim_Seller (seller_key, seller_id, seller_city, seller_state, seller_zip_prefix)
VALUES (-1, N'UNKNOWN', N'Unknown', N'NA', N'00000');
SET IDENTITY_INSERT Warehouse.Dim_Seller OFF;
GO

/* ---------------------------------------------------------------------
   Dim_Location : one row per DISTINCT zip_code_prefix (deduplicated -
   the raw geolocation source has 261,831 duplicate rows per Task 2).
   Shared by both the customer side and the seller side of the fact table.
   --------------------------------------------------------------------- */
CREATE TABLE Warehouse.Dim_Location
(
    location_key      INT IDENTITY(1,1) PRIMARY KEY,
    zip_code_prefix   NVARCHAR(10)   NOT NULL,
    city              NVARCHAR(100)  NULL,
    state             NVARCHAR(5)    NULL,
    latitude          DECIMAL(10,6)  NULL,
    longitude         DECIMAL(10,6)  NULL
);
GO
SET IDENTITY_INSERT Warehouse.Dim_Location ON;
INSERT INTO Warehouse.Dim_Location (location_key, zip_code_prefix, city, state, latitude, longitude)
VALUES (-1, N'00000', N'Unknown', N'NA', NULL, NULL);
SET IDENTITY_INSERT Warehouse.Dim_Location OFF;
GO

/* ---------------------------------------------------------------------
   Dim_Payment : small dimension, one row per distinct payment TYPE.
   --------------------------------------------------------------------- */
CREATE TABLE Warehouse.Dim_Payment
(
    payment_key    INT IDENTITY(1,1) PRIMARY KEY,
    payment_type   NVARCHAR(30) NOT NULL UNIQUE
);
GO
SET IDENTITY_INSERT Warehouse.Dim_Payment ON;
INSERT INTO Warehouse.Dim_Payment (payment_key, payment_type) VALUES
    (-1, N'unknown'),
    (1,  N'credit_card'),
    (2,  N'boleto'),
    (3,  N'voucher'),
    (4,  N'debit_card'),
    (5,  N'not_defined');
SET IDENTITY_INSERT Warehouse.Dim_Payment OFF;
GO

/* ---------------------------------------------------------------------
   Fact_Order_Sales
   Grain: one row = one product, from one seller, within one order.
   --------------------------------------------------------------------- */
CREATE TABLE Warehouse.Fact_Order_Sales
(
    order_sales_key            BIGINT IDENTITY(1,1) PRIMARY KEY,

    -- Degenerate dimension: lets BI tools de-duplicate order-level measures
    order_id                   NVARCHAR(50) NOT NULL,

    -- Foreign keys
    order_purchase_date_key    INT    NOT NULL,
    customer_key                INT    NOT NULL,
    customer_location_key       INT    NOT NULL,
    product_key                 INT    NOT NULL,
    seller_key                  INT    NOT NULL,
    seller_location_key          INT    NOT NULL,
    payment_key                  INT    NOT NULL,

    -- Line-grain measures (aggregated from unit-level order_items)
    quantity                    INT           NOT NULL,
    unit_price                  DECIMAL(10,2) NOT NULL,
    total_price                 DECIMAL(12,2) NOT NULL,
    unit_freight_value           DECIMAL(10,2) NOT NULL,
    total_freight_value          DECIMAL(12,2) NOT NULL,

    -- Order-level measures, replicated across the order's line items
    -- (see the degenerate-dimension note above for correct aggregation)
    order_total_payment_value    DECIMAL(12,2) NULL,
    order_total_installments     INT           NULL,
    delivery_duration_days       INT           NULL,   -- NULL if not yet delivered
    is_delivered_late            BIT           NULL,    -- NULL if not yet delivered
    review_score                 TINYINT       NULL,    -- NULL if no review submitted

    CONSTRAINT FK_Fact_Date      FOREIGN KEY (order_purchase_date_key) REFERENCES Warehouse.Dim_Date(date_key),
    CONSTRAINT FK_Fact_Customer  FOREIGN KEY (customer_key)            REFERENCES Warehouse.Dim_Customer(customer_key),
    CONSTRAINT FK_Fact_CustLoc   FOREIGN KEY (customer_location_key)   REFERENCES Warehouse.Dim_Location(location_key),
    CONSTRAINT FK_Fact_Product   FOREIGN KEY (product_key)             REFERENCES Warehouse.Dim_Product(product_key),
    CONSTRAINT FK_Fact_Seller    FOREIGN KEY (seller_key)              REFERENCES Warehouse.Dim_Seller(seller_key),
    CONSTRAINT FK_Fact_SellLoc   FOREIGN KEY (seller_location_key)     REFERENCES Warehouse.Dim_Location(location_key),
    CONSTRAINT FK_Fact_Payment   FOREIGN KEY (payment_key)             REFERENCES Warehouse.Dim_Payment(payment_key)
);
GO

-- Helpful indexes for the FK columns (fact tables are read-heavy; FKs alone are not indexed by default in SQL Server)
CREATE INDEX IX_Fact_Date     ON Warehouse.Fact_Order_Sales(order_purchase_date_key);
CREATE INDEX IX_Fact_Customer ON Warehouse.Fact_Order_Sales(customer_key);
CREATE INDEX IX_Fact_Product  ON Warehouse.Fact_Order_Sales(product_key);
CREATE INDEX IX_Fact_Seller   ON Warehouse.Fact_Order_Sales(seller_key);
CREATE INDEX IX_Fact_OrderId  ON Warehouse.Fact_Order_Sales(order_id);
GO

-- Confirm: should list 7 Warehouse tables
SELECT s.name AS schema_name, t.name AS table_name
FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = N'Warehouse'
ORDER BY t.name;
GO
