/* ============================================================
   Step 2: cleaned analytical view + validation checks
   Run AFTER load_application_train.py has finished.
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
    NULLIF(a.ORGANIZATION_TYPE, 'XNA')                     AS ORGANIZATION_TYPE,
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

/* ---------------- VALIDATION: results must match Python ---------------- */

-- 1. Row count (expect 307,511), target sum (expect 24,825), rate (expect ~8.07%)
SELECT COUNT(*)                              AS total_rows,
       SUM(CAST(TARGET AS INT))              AS difficulty_cases,
       CAST(100.0 * AVG(CAST(TARGET AS FLOAT)) AS DECIMAL(5,2)) AS difficulty_rate_pct
FROM stg.application_train;

-- 2. Placeholder group (expect 55,374 rows, ~5.4% rate)
SELECT EMPLOYMENT_NOT_REPORTED_FLAG,
       COUNT(*)                              AS applications,
       CAST(100.0 * AVG(CAST(TARGET AS FLOAT)) AS DECIMAL(5,2)) AS difficulty_rate_pct
FROM analytics.vw_application_clean
GROUP BY EMPLOYMENT_NOT_REPORTED_FLAG;

-- 3. Is missing OCCUPATION mostly pensioners?
SELECT INCOME_TYPE,
       COUNT(*)                                                  AS applications,
       SUM(CASE WHEN OCCUPATION = 'Not reported' THEN 1 ELSE 0 END) AS occupation_missing
FROM analytics.vw_application_clean
GROUP BY INCOME_TYPE
ORDER BY occupation_missing DESC;

-- 4. First real insight: difficulty rate AND volume by income band
SELECT INCOME_BAND,
       COUNT(*)                              AS applications,
       SUM(CAST(TARGET AS INT))              AS difficulty_cases,
       CAST(100.0 * AVG(CAST(TARGET AS FLOAT)) AS DECIMAL(5,2)) AS difficulty_rate_pct
FROM analytics.vw_application_clean
GROUP BY INCOME_BAND
ORDER BY INCOME_BAND;
