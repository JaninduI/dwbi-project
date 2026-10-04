 /*Script Name   : 04_Load_and_Transform_Reviews.sql

 Purpose:
 This script performs the raw ingestion and transformation of the
 Olist customer review dataset.

 ETL Flow:

 Source CSV
      |
      ↓
 Staging.stg_reviews_raw
 (Raw landing layer - source format preserved)
      |
      ↓
 Staging.stg_reviews
 (Clean staging layer - transformed data types)
      |
      ↓
 Enterprise Data Warehouse


 Design Rationale:
 The review dataset contains free-text attributes such as review comments.
 These fields may include commas, quotation marks, special characters,
 and variable-length text. Therefore, the data is first loaded into a
 raw staging table without strict data type enforcement.

 Data type conversion is performed during transformation using TRY_CAST()
 to prevent ETL failure caused by unexpected source values.

=====================================================================*/




USE Olist_DW;
GO

/*=====================================================================
 STEP 1: Create Raw Review Staging Table

 Purpose:
 - Preserve the original CSV data
 - Avoid conversion errors during ingestion
 - Allow validation before transformation

 All columns are stored as NVARCHAR because the raw layer represents
 the source data exactly as received.
=====================================================================*/


DROP TABLE IF EXISTS Staging.stg_reviews_raw;
GO

CREATE TABLE Staging.stg_reviews_raw
(
    review_id               NVARCHAR(100),
    order_id                NVARCHAR(100),
    review_score            NVARCHAR(50),
    review_comment_title    NVARCHAR(MAX),
    review_comment_message  NVARCHAR(MAX),
    review_creation_date    NVARCHAR(100),
    review_answer_timestamp NVARCHAR(100)
);
GO
/*=====================================================================
 STEP 2: Load Review CSV File into Raw Staging Layer

 Source:
 olist_order_reviews_dataset.csv

 BULK INSERT configuration:

 FORMAT = CSV
    Enables correct interpretation of quoted CSV fields.

 FIELDQUOTE = '"'
    Handles text values enclosed in quotation marks.

 CODEPAGE = 65001
    Supports UTF-8 encoded characters used in Portuguese text.

 ROWTERMINATOR = 0x0d0a
    Defines Windows line ending format.

 FIRSTROW = 2
    Skips CSV header row.

=====================================================================*/

BULK INSERT Staging.stg_reviews_raw
FROM 'C:\olist_dataset\archive\olist_order_reviews_dataset.csv'
WITH
(
    FORMAT = 'CSV',
    FIELDQUOTE = '"',
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0d0a',
    FIRSTROW = 2,
    CODEPAGE = '65001',
    TABLOCK
);
GO

/*=====================================================================
 STEP 3: Validate Raw Data Loading

 Expected result:
 Approximately 99,224 review records should be loaded.

 Additional inspection is performed to verify:
 - Column alignment
 - Text field integrity
 - Correct handling of review comments
=====================================================================*/



SELECT COUNT(*) AS review_rows
FROM Staging.stg_reviews_raw;

SELECT TOP 10 *
FROM Staging.stg_reviews_raw;

/*=====================================================================
 STEP 4: Validate Target Clean Staging Table

 The structured staging table receives transformed values.

 Review:
 - review_score converted to INTEGER
 - Date attributes converted to DATETIME
=====================================================================*/

USE Olist_DW;
GO

EXEC sp_help 'Staging.stg_reviews';

/*=====================================================================
 STEP 5: Clear Existing Review Staging Data

 Ensures that previous failed loading attempts do not create duplicates.
=====================================================================*/


TRUNCATE TABLE Staging.stg_reviews;
GO

/*=====================================================================
 STEP 6: Transform Raw Review Data into Clean Staging Layer

 Transformations:

 1. review_score:
       NVARCHAR → INT

 2. review_creation_date:
       NVARCHAR → DATETIME

 3. review_answer_timestamp:
       NVARCHAR → DATETIME


 TRY_CAST() is used instead of CAST() because:
 - Invalid values return NULL
 - ETL process continues without failure
=====================================================================*/

INSERT INTO Staging.stg_reviews
(
    review_id,
    order_id,
    review_score,
    review_comment_title,
    review_comment_message,
    review_creation_date,
    review_answer_timestamp
)
SELECT
    review_id,
    order_id,
    TRY_CAST(review_score AS INT),
    review_comment_title,
    review_comment_message,
    TRY_CAST(review_creation_date AS DATETIME),
    TRY_CAST(review_answer_timestamp AS DATETIME)
FROM Staging.stg_reviews_raw;
GO

/*=====================================================================
 STEP 7: Validate Transformed Review Data

 Expected:
 99,224 records should exist in clean staging.

 Verify:
 - Numeric review scores
 - Converted date fields
 - Preserved review comments
=====================================================================*/

SELECT COUNT(*) AS review_count
FROM Staging.stg_reviews;

SELECT TOP 10 *
FROM Staging.stg_reviews;