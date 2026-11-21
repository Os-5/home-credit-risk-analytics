/* ============================================================
   Step 7: fixes found by the readiness check (01_view_readiness_check.ipynb)
   Run in SSMS. Safe to re-run (CREATE OR ALTER). Changes view DEFINITIONS only -
   no data in the stg tables is touched.

   F1  ORGANIZATION_TYPE: NULL -> 'Not applicable'         (55,374 rows; avoids '(Blank)' in Power BI)
   F2  Bureau debt: negative balances floored at 0, debt-to-credit ratio capped at 1,
       new flag BUREAU_DEBT_EXCEEDS_CREDIT_FLAG              (2,114 ratio rows and 1,296 debt rows were out of range)
   F3  Installment groups: customers whose installments have no recorded payment
       move from 'Never late' to 'No installment history'    (8 rows)
   ============================================================ */
USE HomeCreditDB;
GO

CREATE OR ALTER VIEW analytics.vw_application_clean AS
SELECT
    a.SK_ID_CURR,
    a.TARGET,
    CASE a.TARGET WHEN 1 THEN 'Payment difficulty' ELSE 'No difficulty' END AS TARGET_LABEL,
    a.NAME_CONTRACT_TYPE                                   AS CONTRACT_TYPE,

    -- Demographics
    CASE WHEN a.CODE_GENDER IN ('F','M') THEN a.CODE_GENDER ELSE 'Unknown' END AS GENDER,
    CAST(-a.DAYS_BIRTH / 365.25 AS DECIMAL(5,1))           AS AGE_YEARS,
    CASE
        WHEN -a.DAYS_BIRTH / 365.25 < 25 THEN '20-24'
        WHEN -a.DAYS_BIRTH / 365.25 < 35 THEN '25-34'
        WHEN -a.DAYS_BIRTH / 365.25 < 45 THEN '35-44'
        WHEN -a.DAYS_BIRTH / 365.25 < 55 THEN '45-54'
        WHEN -a.DAYS_BIRTH / 365.25 < 65 THEN '55-64'
        ELSE '65+'
    END                                                    AS AGE_GROUP,
    a.CNT_CHILDREN,
    a.CNT_FAM_MEMBERS,
    a.NAME_FAMILY_STATUS                                   AS FAMILY_STATUS,
    a.NAME_EDUCATION_TYPE                                  AS EDUCATION,
    a.NAME_HOUSING_TYPE                                    AS HOUSING_TYPE,
    a.FLAG_OWN_CAR,
    a.FLAG_OWN_REALTY,
    a.OWN_CAR_AGE,                                          -- NULL when no car (structural)

    -- Employment (365243 is a placeholder, not a real value)
    a.NAME_INCOME_TYPE                                     AS INCOME_TYPE,
    ISNULL(a.OCCUPATION_TYPE, 'Not reported')              AS OCCUPATION,
    ISNULL(NULLIF(a.ORGANIZATION_TYPE, 'XNA'), 'Not applicable') AS ORGANIZATION_TYPE,
    CASE WHEN a.DAYS_EMPLOYED = 365243 THEN NULL
         ELSE CAST(-a.DAYS_EMPLOYED / 365.25 AS DECIMAL(5,1)) END AS YEARS_EMPLOYED,
    CASE WHEN a.DAYS_EMPLOYED = 365243 THEN 1 ELSE 0 END   AS EMPLOYMENT_NOT_REPORTED_FLAG,

    -- Income and loan
    a.AMT_INCOME_TOTAL                                     AS INCOME,
    CASE
        WHEN a.AMT_INCOME_TOTAL <  90000  THEN '1. Under 90K'
        WHEN a.AMT_INCOME_TOTAL < 135000  THEN '2. 90K-135K'
        WHEN a.AMT_INCOME_TOTAL < 180000  THEN '3. 135K-180K'
        WHEN a.AMT_INCOME_TOTAL < 270000  THEN '4. 180K-270K'
        ELSE                                   '5. 270K+'
    END                                                    AS INCOME_BAND,
    CASE WHEN a.AMT_INCOME_TOTAL > 1000000 THEN 1 ELSE 0 END AS INCOME_OUTLIER_FLAG,
    a.AMT_CREDIT                                           AS LOAN_AMOUNT,
    a.AMT_ANNUITY                                          AS ANNUITY,
    a.AMT_GOODS_PRICE                                      AS GOODS_PRICE,
    CAST(a.AMT_CREDIT  / NULLIF(a.AMT_INCOME_TOTAL, 0) AS DECIMAL(10,2)) AS CREDIT_INCOME_RATIO,
    CAST(a.AMT_ANNUITY / NULLIF(a.AMT_INCOME_TOTAL, 0) AS DECIMAL(10,4)) AS ANNUITY_INCOME_RATIO,
    CAST(a.AMT_CREDIT  / NULLIF(a.AMT_ANNUITY, 0)      AS DECIMAL(10,1)) AS LOAN_TERM_MONTHS_EST,

    -- Other risk signals
    a.EXT_SOURCE_1, a.EXT_SOURCE_2, a.EXT_SOURCE_3,
    a.REGION_RATING_CLIENT                                 AS REGION_RATING,
    a.DEF_30_CNT_SOCIAL_CIRCLE,
    a.DEF_60_CNT_SOCIAL_CIRCLE,
    a.AMT_REQ_CREDIT_BUREAU_YEAR
FROM stg.application_train AS a;
GO

CREATE OR ALTER VIEW analytics.vw_bureau_by_customer AS
SELECT
    SK_ID_CURR,
    COUNT(*)                                                        AS BUREAU_LOAN_COUNT,
    SUM(CASE WHEN CREDIT_ACTIVE = 'Active' THEN 1 ELSE 0 END)       AS BUREAU_ACTIVE_COUNT,
    SUM(CASE WHEN CREDIT_ACTIVE = 'Closed' THEN 1 ELSE 0 END)       AS BUREAU_CLOSED_COUNT,
    SUM(CASE WHEN CREDIT_DAY_OVERDUE > 0 THEN 1 ELSE 0 END)         AS BUREAU_OVERDUE_LOAN_COUNT,
    MAX(CREDIT_DAY_OVERDUE)                                         AS BUREAU_MAX_DAYS_OVERDUE,
    SUM(AMT_CREDIT_SUM)                                             AS BUREAU_TOTAL_CREDIT,
    SUM(CASE WHEN AMT_CREDIT_SUM_DEBT IS NULL THEN NULL
             WHEN AMT_CREDIT_SUM_DEBT > 0     THEN AMT_CREDIT_SUM_DEBT
             ELSE 0 END)                                            AS BUREAU_TOTAL_DEBT,   -- negative balances floored at 0
    SUM(AMT_CREDIT_SUM_OVERDUE)                                     AS BUREAU_TOTAL_OVERDUE_AMT
FROM stg.bureau
GROUP BY SK_ID_CURR;
GO

CREATE OR ALTER VIEW analytics.vw_application_enriched AS
SELECT
    c.*,

    -- Bureau
    CASE WHEN b.SK_ID_CURR IS NULL THEN 0 ELSE 1 END     AS HAS_BUREAU_HISTORY,
    ISNULL(b.BUREAU_LOAN_COUNT, 0)                        AS BUREAU_LOAN_COUNT,
    ISNULL(b.BUREAU_ACTIVE_COUNT, 0)                      AS BUREAU_ACTIVE_COUNT,
    ISNULL(b.BUREAU_CLOSED_COUNT, 0)                      AS BUREAU_CLOSED_COUNT,
    ISNULL(b.BUREAU_OVERDUE_LOAN_COUNT, 0)                AS BUREAU_OVERDUE_LOAN_COUNT,
    b.BUREAU_MAX_DAYS_OVERDUE,
    b.BUREAU_TOTAL_CREDIT,
    b.BUREAU_TOTAL_DEBT,
    CAST(CASE WHEN b.BUREAU_TOTAL_CREDIT > 0
              THEN CASE WHEN b.BUREAU_TOTAL_DEBT / b.BUREAU_TOTAL_CREDIT > 1 THEN 1
                        ELSE b.BUREAU_TOTAL_DEBT / b.BUREAU_TOTAL_CREDIT END
         END AS DECIMAL(10,3))                              AS BUREAU_DEBT_TO_CREDIT_RATIO,   -- capped at 1
    CASE WHEN b.BUREAU_TOTAL_CREDIT > 0 AND b.BUREAU_TOTAL_DEBT > b.BUREAU_TOTAL_CREDIT
         THEN 1 ELSE 0 END                                  AS BUREAU_DEBT_EXCEEDS_CREDIT_FLAG,
    CASE
        WHEN b.SK_ID_CURR IS NULL           THEN '0. No bureau record'
        WHEN b.BUREAU_LOAN_COUNT <= 3       THEN '1. 1-3 credits'
        WHEN b.BUREAU_LOAN_COUNT <= 7       THEN '2. 4-7 credits'
        ELSE                                     '3. 8+ credits'
    END                                                   AS BUREAU_HISTORY_GROUP,
    CASE WHEN b.BUREAU_OVERDUE_LOAN_COUNT > 0 THEN 'Has overdue credit'
         WHEN b.SK_ID_CURR IS NULL            THEN 'No bureau record'
         ELSE 'No overdue credit' END                     AS BUREAU_OVERDUE_GROUP,

    -- Previous applications
    CASE WHEN p.SK_ID_CURR IS NULL THEN 0 ELSE 1 END      AS HAS_PREVIOUS_APPLICATIONS,
    ISNULL(p.PREV_APPLICATION_COUNT, 0)                   AS PREV_APPLICATION_COUNT,
    ISNULL(p.PREV_APPROVED_COUNT, 0)                      AS PREV_APPROVED_COUNT,
    ISNULL(p.PREV_REFUSED_COUNT, 0)                       AS PREV_REFUSED_COUNT,
    p.PREV_REFUSAL_RATE,
    p.PREV_DAYS_SINCE_LAST_DECISION,
    CASE
        WHEN p.SK_ID_CURR IS NULL           THEN '0. No previous applications'
        WHEN p.PREV_REFUSED_COUNT = 0       THEN '1. Never refused'
        WHEN p.PREV_REFUSAL_RATE < 0.5      THEN '2. Some refusals'
        ELSE                                     '3. Mostly refused'
    END                                                   AS PREV_REFUSAL_GROUP
FROM analytics.vw_application_clean AS c
LEFT JOIN analytics.vw_bureau_by_customer   AS b ON b.SK_ID_CURR = c.SK_ID_CURR
LEFT JOIN analytics.vw_previous_by_customer AS p ON p.SK_ID_CURR = c.SK_ID_CURR;
GO

CREATE OR ALTER VIEW analytics.vw_application_full AS
SELECT
    e.*,
    CASE WHEN i.SK_ID_CURR IS NULL THEN 0 ELSE 1 END       AS HAS_INSTALLMENT_HISTORY,
    ISNULL(i.INST_COUNT, 0)                                 AS INST_COUNT,
    ISNULL(i.INST_LATE_COUNT, 0)                            AS INST_LATE_COUNT,
    ISNULL(i.INST_LATE_30PLUS_COUNT, 0)                     AS INST_LATE_30PLUS_COUNT,
    ISNULL(i.INST_UNDERPAID_COUNT, 0)                       AS INST_UNDERPAID_COUNT,
    ISNULL(i.INST_NO_PAYMENT_RECORDED, 0)                   AS INST_NO_PAYMENT_RECORDED,
    i.INST_AVG_DAYS_LATE,
    i.INST_MAX_DAYS_LATE,
    CAST(1.0 * i.INST_LATE_COUNT
         / NULLIF(i.INST_COUNT - i.INST_NO_PAYMENT_RECORDED, 0) AS DECIMAL(6,3)) AS INST_LATE_RATE,
    CASE
        WHEN i.SK_ID_CURR IS NULL OR i.INST_COUNT = i.INST_NO_PAYMENT_RECORDED THEN '0. No installment history'
        WHEN i.INST_LATE_COUNT = 0                                 THEN '1. Never late'
        WHEN 1.0 * i.INST_LATE_COUNT
             / NULLIF(i.INST_COUNT - i.INST_NO_PAYMENT_RECORDED, 0) <= 0.10 THEN '2. Late in up to 10% of installments'
        WHEN 1.0 * i.INST_LATE_COUNT
             / NULLIF(i.INST_COUNT - i.INST_NO_PAYMENT_RECORDED, 0) <= 0.30 THEN '3. Late in 10-30%'
        ELSE                                                            '4. Late in over 30%'
    END                                                     AS INST_LATE_GROUP,
    CASE
        WHEN i.SK_ID_CURR IS NULL OR i.INST_COUNT = i.INST_NO_PAYMENT_RECORDED THEN '0. No installment history'
        WHEN i.INST_LATE_30PLUS_COUNT > 0    THEN '2. Ever 30+ days late'
        ELSE                                      '1. Never 30+ days late'
    END                                                     AS INST_SEVERE_LATE_GROUP,
    CASE
        WHEN i.SK_ID_CURR IS NULL OR i.INST_COUNT = i.INST_NO_PAYMENT_RECORDED THEN '0. No installment history'
        WHEN i.INST_UNDERPAID_COUNT > 0      THEN '2. Has underpaid installments'
        ELSE                                      '1. Always paid in full'
    END                                                     AS INST_UNDERPAID_GROUP
FROM analytics.vw_application_enriched AS e
LEFT JOIN analytics.vw_installments_by_customer AS i ON i.SK_ID_CURR = e.SK_ID_CURR;
GO

/* Refresh view metadata (the chain uses SELECT c.* / e.*) */
EXEC sp_refreshview 'analytics.vw_application_enriched';
EXEC sp_refreshview 'analytics.vw_application_full';
GO

/* ====================== VERIFY THE FIXES ====================== */

-- 1. Still one row per application (expect 307511 / 307511)
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT SK_ID_CURR) AS distinct_applications
FROM analytics.vw_application_full;

-- 2. F1: no NULL organization types left (expect 0), 'Not applicable' = 55374
SELECT SUM(CASE WHEN ORGANIZATION_TYPE IS NULL THEN 1 ELSE 0 END)           AS null_org,
       SUM(CASE WHEN ORGANIZATION_TYPE = 'Not applicable' THEN 1 ELSE 0 END) AS not_applicable
FROM analytics.vw_application_full;

-- 3. F2: no negative debt, ratio within [0,1] (expect 0 / 0 / 0)
SELECT SUM(CASE WHEN BUREAU_TOTAL_DEBT < 0 THEN 1 ELSE 0 END)                AS negative_debt_rows,
       SUM(CASE WHEN BUREAU_DEBT_TO_CREDIT_RATIO < 0 OR BUREAU_DEBT_TO_CREDIT_RATIO > 1 THEN 1 ELSE 0 END) AS ratio_out_of_range,
       SUM(BUREAU_DEBT_EXCEEDS_CREDIT_FLAG)                                  AS debt_exceeds_credit_rows
FROM analytics.vw_application_full;

-- 4. F3: late-group counts (the 8 customers move; 'No installment history' should be 15876)
SELECT INST_LATE_GROUP, COUNT(*) AS applications
FROM analytics.vw_application_full
GROUP BY INST_LATE_GROUP ORDER BY INST_LATE_GROUP;

-- 5. Aggregation reconciliation: bureau credits summed over all applications must equal the
--    direct-join row count you saw earlier (expect 1465325)
SELECT SUM(BUREAU_LOAN_COUNT) AS bureau_credits_in_view
FROM analytics.vw_application_full;
