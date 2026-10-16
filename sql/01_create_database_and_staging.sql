/* ============================================================
   Home Credit Risk Analytics - Step 1: database + staging table
   Run in SSMS (connected to your SQL Server instance).
   ============================================================ */

IF DB_ID('HomeCreditDB') IS NULL
    CREATE DATABASE HomeCreditDB;
GO

USE HomeCreditDB;
GO

IF SCHEMA_ID('stg') IS NULL       EXEC('CREATE SCHEMA stg');        -- raw loaded data, untouched
GO
IF SCHEMA_ID('analytics') IS NULL EXEC('CREATE SCHEMA analytics');  -- cleaned views for Power BI
GO

DROP TABLE IF EXISTS stg.application_train;
GO

/* Grain: ONE ROW PER LOAN APPLICATION (SK_ID_CURR is unique - verified in Python).
   Values are stored exactly as in the CSV. Cleaning happens in the analytics view. */
CREATE TABLE stg.application_train (
    SK_ID_CURR                    INT            NOT NULL PRIMARY KEY,
    TARGET                        TINYINT        NOT NULL,   -- 1 = payment difficulties
    NAME_CONTRACT_TYPE            VARCHAR(30)    NULL,
    CODE_GENDER                   VARCHAR(5)     NULL,
    FLAG_OWN_CAR                  CHAR(1)        NULL,
    FLAG_OWN_REALTY               CHAR(1)        NULL,
    CNT_CHILDREN                  SMALLINT       NULL,
    AMT_INCOME_TOTAL              DECIMAL(18,2)  NULL,
    AMT_CREDIT                    DECIMAL(18,2)  NULL,
    AMT_ANNUITY                   DECIMAL(18,2)  NULL,
    AMT_GOODS_PRICE               DECIMAL(18,2)  NULL,
    NAME_TYPE_SUITE               VARCHAR(30)    NULL,
    NAME_INCOME_TYPE              VARCHAR(30)    NULL,
    NAME_EDUCATION_TYPE           VARCHAR(40)    NULL,
    NAME_FAMILY_STATUS            VARCHAR(30)    NULL,
    NAME_HOUSING_TYPE             VARCHAR(30)    NULL,
    REGION_POPULATION_RELATIVE    FLOAT          NULL,
    DAYS_BIRTH                    INT            NULL,
    DAYS_EMPLOYED                 INT            NULL,       -- 365243 = placeholder
    DAYS_REGISTRATION             FLOAT          NULL,
    DAYS_ID_PUBLISH               INT            NULL,
    OWN_CAR_AGE                   FLOAT          NULL,
    OCCUPATION_TYPE               VARCHAR(40)    NULL,
    CNT_FAM_MEMBERS               SMALLINT       NULL,
    REGION_RATING_CLIENT          TINYINT        NULL,
    REGION_RATING_CLIENT_W_CITY   TINYINT        NULL,
    WEEKDAY_APPR_PROCESS_START    VARCHAR(12)    NULL,
    HOUR_APPR_PROCESS_START       TINYINT        NULL,
    ORGANIZATION_TYPE             VARCHAR(40)    NULL,       -- 'XNA' = not applicable
    EXT_SOURCE_1                  FLOAT          NULL,
    EXT_SOURCE_2                  FLOAT          NULL,
    EXT_SOURCE_3                  FLOAT          NULL,
    OBS_30_CNT_SOCIAL_CIRCLE      SMALLINT       NULL,
    DEF_30_CNT_SOCIAL_CIRCLE      SMALLINT       NULL,
    OBS_60_CNT_SOCIAL_CIRCLE      SMALLINT       NULL,
    DEF_60_CNT_SOCIAL_CIRCLE      SMALLINT       NULL,
    DAYS_LAST_PHONE_CHANGE        FLOAT          NULL,
    AMT_REQ_CREDIT_BUREAU_HOUR    SMALLINT       NULL,
    AMT_REQ_CREDIT_BUREAU_DAY     SMALLINT       NULL,
    AMT_REQ_CREDIT_BUREAU_WEEK    SMALLINT       NULL,
    AMT_REQ_CREDIT_BUREAU_MON     SMALLINT       NULL,
    AMT_REQ_CREDIT_BUREAU_QRT     SMALLINT       NULL,
    AMT_REQ_CREDIT_BUREAU_YEAR    SMALLINT       NULL
);
GO
