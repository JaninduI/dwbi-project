USE Olist_DW;
GO


CREATE TABLE Staging.stg_orders
(
    order_id VARCHAR(50),
    customer_id VARCHAR(50),
    order_status VARCHAR(30),

    order_purchase_timestamp DATETIME,
    order_approved_at DATETIME,
    order_delivered_carrier_date DATETIME,
    order_delivered_customer_date DATETIME,
    order_estimated_delivery_date DATETIME
);
GO

CREATE TABLE Staging.stg_order_items
(
    order_id VARCHAR(50),
    order_item_id INT,
    product_id VARCHAR(50),
    seller_id VARCHAR(50),

    shipping_limit_date DATETIME,

    price DECIMAL(10,2),
    freight_value DECIMAL(10,2)
);
GO


CREATE TABLE Staging.stg_customers
(
    customer_id VARCHAR(50),
    customer_unique_id VARCHAR(50),

    customer_zip_code_prefix INT,

    customer_city VARCHAR(100),
    customer_state VARCHAR(10)
);
GO


CREATE TABLE Staging.stg_products
(
    product_id VARCHAR(50),

    product_category_name VARCHAR(100),

    product_name_length INT,
    product_description_length INT,
    product_photos_qty INT,

    product_weight_g DECIMAL(10,2),

    product_length_cm DECIMAL(10,2),
    product_height_cm DECIMAL(10,2),
    product_width_cm DECIMAL(10,2)
);
GO

CREATE TABLE Staging.stg_sellers
(
    seller_id VARCHAR(50),

    seller_zip_code_prefix INT,

    seller_city VARCHAR(100),
    seller_state VARCHAR(10)
);
GO

CREATE TABLE Staging.stg_payments
(
    order_id VARCHAR(50),

    payment_sequential INT,

    payment_type VARCHAR(50),

    payment_installments INT,

    payment_value DECIMAL(10,2)
);
GO


CREATE TABLE Staging.stg_reviews
(
    review_id VARCHAR(50),

    order_id VARCHAR(50),

    review_score INT,

    review_comment_title VARCHAR(255),

    review_comment_message VARCHAR(MAX),

    review_creation_date DATETIME,

    review_answer_timestamp DATETIME
);
GO


CREATE TABLE Staging.stg_geolocation
(
    geolocation_zip_code_prefix INT,

    geolocation_lat DECIMAL(10,6),

    geolocation_lng DECIMAL(10,6),

    geolocation_city VARCHAR(100),

    geolocation_state VARCHAR(10)
);
GO

CREATE TABLE Staging.stg_category_translation
(
    product_category_name VARCHAR(100),

    product_category_name_english VARCHAR(100)
);
GO

SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA='Staging';