/* ============================================================
   Step 4: aggregate history to ONE ROW PER CUSTOMER, then join safely.
   Run AFTER load_history_tables.py has finished.
   ============================================================ */
USE HomeCreditDB;
GO

/* ---------- 4.1 Bureau (external credit) -> 1 row per SK_ID_CURR ---------- */
CREATE OR ALTER VIEW analytics.vw_bureau_by_customer AS
SELECT
    SK_ID_CURR,
    COUNT(*)                                                        AS BUREAU_LOAN_COUNT,
    SUM(CASE WHEN CREDIT_ACTIVE = 'Active' THEN 1 ELSE 0 END)       AS BUREAU_ACTIVE_COUNT,
    SUM(CASE WHEN CREDIT_ACTIVE = 'Closed' THEN 1 ELSE 0 END)       AS BUREAU_CLOSED_COUNT,
    SUM(CASE WHEN CREDIT_DAY_OVERDUE > 0 THEN 1 ELSE 0 END)         AS BUREAU_OVERDUE_LOAN_COUNT,
    MAX(CREDIT_DAY_OVERDUE)                                         AS BUREAU_MAX_DAYS_OVERDUE,
    SUM(AMT_CREDIT_SUM)                                             AS BUREAU_TOTAL_CREDIT,
    SUM(AMT_CREDIT_SUM_DEBT)                                        AS BUREAU_TOTAL_DEBT,
    SUM(AMT_CREDIT_SUM_OVERDUE)                                     AS BUREAU_TOTAL_OVERDUE_AMT
FROM stg.bureau
GROUP BY SK_ID_CURR;
GO

/* ---------- 4.2 Previous applications -> 1 row per SK_ID_CURR ---------- */
CREATE OR ALTER VIEW analytics.vw_previous_by_customer AS
SELECT
    SK_ID_CURR,
    COUNT(*)                                                             AS PREV_APPLICATION_COUNT,
    SUM(CASE WHEN NAME_CONTRACT_STATUS = 'Approved' THEN 1 ELSE 0 END)   AS PREV_APPROVED_COUNT,
    SUM(CASE WHEN NAME_CONTRACT_STATUS = 'Refused'  THEN 1 ELSE 0 END)   AS PREV_REFUSED_COUNT,
    SUM(CASE WHEN NAME_CONTRACT_STATUS = 'Canceled' THEN 1 ELSE 0 END)   AS PREV_CANCELED_COUNT,
    CAST(1.0 * SUM(CASE WHEN NAME_CONTRACT_STATUS = 'Refused' THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,3))                                     AS PREV_REFUSAL_RATE,
    -MAX(DAYS_DECISION)                                                  AS PREV_DAYS_SINCE_LAST_DECISION
FROM stg.previous_application
GROUP BY SK_ID_CURR;
GO

/* ---------- 4.3 Enriched application view (feeds Power BI) ----------
   LEFT JOIN from the application view: every application stays exactly once.
   Customers with no history get 0 counts + a "no history" flag/segment. */
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
    CAST(b.BUREAU_TOTAL_DEBT / NULLIF(b.BUREAU_TOTAL_CREDIT, 0) AS DECIMAL(10,3)) AS BUREAU_DEBT_TO_CREDIT_RATIO,
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

/* ====================== CHECKS ====================== */

-- A. The safe join must keep exactly 307,511 rows, no duplicates
SELECT COUNT(*)                    AS rows_in_enriched_view,      -- expect 307511
       COUNT(DISTINCT SK_ID_CURR)  AS distinct_applications       -- expect 307511
FROM analytics.vw_application_enriched;

-- B. WHY we aggregate first: a direct join multiplies rows (expect far MORE than 307,511)
SELECT COUNT(*) AS rows_if_joined_directly
FROM stg.application_train a
JOIN stg.bureau b ON b.SK_ID_CURR = a.SK_ID_CURR;

-- C. Coverage: how many applicants actually have history?
SELECT SUM(HAS_BUREAU_HISTORY)         AS with_bureau_history,
       SUM(HAS_PREVIOUS_APPLICATIONS)  AS with_previous_applications
FROM analytics.vw_application_enriched;

-- D. Insight: difficulty rate by previous-refusal history (rate AND volume)
SELECT PREV_REFUSAL_GROUP,
       COUNT(*)                                       AS applications,
       SUM(CAST(TARGET AS INT))                       AS difficulty_cases,
       CAST(100.0 * AVG(CAST(TARGET AS FLOAT)) AS DECIMAL(5,2)) AS difficulty_rate_pct
FROM analytics.vw_application_enriched
GROUP BY PREV_REFUSAL_GROUP
ORDER BY PREV_REFUSAL_GROUP;

-- E. Insight: difficulty rate by bureau overdue history
SELECT BUREAU_OVERDUE_GROUP,
       COUNT(*)                                       AS applications,
       SUM(CAST(TARGET AS INT))                       AS difficulty_cases,
       CAST(100.0 * AVG(CAST(TARGET AS FLOAT)) AS DECIMAL(5,2)) AS difficulty_rate_pct
FROM analytics.vw_application_enriched
GROUP BY BUREAU_OVERDUE_GROUP
ORDER BY BUREAU_OVERDUE_GROUP;

-- F. Insight: difficulty rate by number of bureau credits
SELECT BUREAU_HISTORY_GROUP,
       COUNT(*)                                       AS applications,
       SUM(CAST(TARGET AS INT))                       AS difficulty_cases,
       CAST(100.0 * AVG(CAST(TARGET AS FLOAT)) AS DECIMAL(5,2)) AS difficulty_rate_pct
FROM analytics.vw_application_enriched
GROUP BY BUREAU_HISTORY_GROUP
ORDER BY BUREAU_HISTORY_GROUP;
