/* ============================================================
   Step 3: staging tables for the history data
   Run in SSMS BEFORE load_history_tables.py
   ============================================================ */
USE HomeCreditDB;
GO

/* Grain: ONE ROW PER EXTERNAL (BUREAU) CREDIT.
   A customer can have many rows -> never join this directly to the application table. */
DROP TABLE IF EXISTS stg.bureau;
GO
CREATE TABLE stg.bureau (
    SK_ID_BUREAU             INT            NOT NULL PRIMARY KEY,
    SK_ID_CURR               INT            NOT NULL,
    CREDIT_ACTIVE            VARCHAR(20)    NULL,
    CREDIT_CURRENCY          VARCHAR(20)    NULL,
    DAYS_CREDIT              INT            NULL,
    CREDIT_DAY_OVERDUE       INT            NULL,
    AMT_CREDIT_SUM           DECIMAL(18,2)  NULL,
    AMT_CREDIT_SUM_DEBT      DECIMAL(18,2)  NULL,
    AMT_CREDIT_SUM_OVERDUE   DECIMAL(18,2)  NULL,
    CREDIT_TYPE              VARCHAR(60)    NULL,
    CNT_CREDIT_PROLONG       SMALLINT       NULL
);
CREATE INDEX IX_bureau_curr ON stg.bureau (SK_ID_CURR);
GO

/* Grain: ONE ROW PER PREVIOUS APPLICATION AT HOME CREDIT. */
DROP TABLE IF EXISTS stg.previous_application;
GO
CREATE TABLE stg.previous_application (
    SK_ID_PREV               INT            NOT NULL PRIMARY KEY,
    SK_ID_CURR               INT            NOT NULL,
    NAME_CONTRACT_TYPE       VARCHAR(30)    NULL,
    AMT_ANNUITY              DECIMAL(18,2)  NULL,
    AMT_APPLICATION          DECIMAL(18,2)  NULL,
    AMT_CREDIT               DECIMAL(18,2)  NULL,
    NAME_CONTRACT_STATUS     VARCHAR(20)    NULL,   -- Approved / Refused / Canceled / Unused offer
    DAYS_DECISION            INT            NULL,   -- negative = days before current application
    CODE_REJECT_REASON       VARCHAR(20)    NULL,
    NAME_CLIENT_TYPE         VARCHAR(20)    NULL,
    NAME_PORTFOLIO           VARCHAR(20)    NULL,
    CNT_PAYMENT              SMALLINT       NULL
);
CREATE INDEX IX_prev_curr ON stg.previous_application (SK_ID_CURR);
GO
