/* ============================================================
   Step 6: installments -> one row per INSTALLMENT -> one row per CUSTOMER
   Run AFTER load_installments.py has finished. May take a few minutes.
   ============================================================ */
USE HomeCreditDB;
GO

/* ---------- 6.1 Index to speed up grouping ---------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_inst_curr' AND object_id = OBJECT_ID('stg.installments_payments'))
    CREATE CLUSTERED INDEX IX_inst_curr ON stg.installments_payments (SK_ID_CURR, SK_ID_PREV);
GO

/* ---------- 6.2 Collapse partial payments: ONE ROW PER INSTALLMENT ----------
   Group = previous loan + schedule version + installment number.
   AMT_PAID = total of all partial payments; DAYS_LAST_PAYMENT = date of the last one. */
DROP TABLE IF EXISTS analytics.installment_level;
GO
SELECT
    SK_ID_PREV,
    SK_ID_CURR,
    NUM_INSTALMENT_VERSION,
    NUM_INSTALMENT_NUMBER,
    MAX(DAYS_INSTALMENT)       AS DAYS_INSTALMENT,
    MAX(DAYS_ENTRY_PAYMENT)    AS DAYS_LAST_PAYMENT,
    MAX(AMT_INSTALMENT)        AS AMT_INSTALMENT,
    SUM(AMT_PAYMENT)           AS AMT_PAID,
    COUNT(*)                   AS PAYMENT_ROWS
INTO analytics.installment_level
FROM stg.installments_payments
GROUP BY SK_ID_PREV, SK_ID_CURR, NUM_INSTALMENT_VERSION, NUM_INSTALMENT_NUMBER;
GO
CREATE CLUSTERED INDEX IX_instlevel_curr ON analytics.installment_level (SK_ID_CURR);
GO

/* ---------- 6.3 One row per customer ----------
   DAYS_LAST_PAYMENT - DAYS_INSTALMENT > 0  means the installment was paid LATE.
   Installments with no payment recorded are counted separately (not assumed late). */
CREATE OR ALTER VIEW analytics.vw_installments_by_customer AS
SELECT
    SK_ID_CURR,
    COUNT(*)                                                           AS INST_COUNT,
    SUM(CASE WHEN DAYS_LAST_PAYMENT IS NULL THEN 1 ELSE 0 END)         AS INST_NO_PAYMENT_RECORDED,
    SUM(CASE WHEN DAYS_LAST_PAYMENT > DAYS_INSTALMENT THEN 1 ELSE 0 END)           AS INST_LATE_COUNT,
    SUM(CASE WHEN DAYS_LAST_PAYMENT - DAYS_INSTALMENT > 30 THEN 1 ELSE 0 END)      AS INST_LATE_30PLUS_COUNT,
    SUM(CASE WHEN AMT_PAID < AMT_INSTALMENT - 0.01 THEN 1 ELSE 0 END)  AS INST_UNDERPAID_COUNT,
    CAST(AVG(CASE WHEN DAYS_LAST_PAYMENT IS NOT NULL
                  THEN 1.0 * (DAYS_LAST_PAYMENT - DAYS_INSTALMENT) END) AS DECIMAL(8,2)) AS INST_AVG_DAYS_LATE,
    MAX(DAYS_LAST_PAYMENT - DAYS_INSTALMENT)                           AS INST_MAX_DAYS_LATE
FROM analytics.installment_level
GROUP BY SK_ID_CURR;
GO

/* ---------- 6.4 Full application view (feeds Power BI) ----------
   Builds on vw_application_enriched; LEFT JOIN keeps every application exactly once. */
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
        WHEN i.SK_ID_CURR IS NULL                                  THEN '0. No installment history'
        WHEN i.INST_LATE_COUNT = 0                                 THEN '1. Never late'
        WHEN 1.0 * i.INST_LATE_COUNT
             / NULLIF(i.INST_COUNT - i.INST_NO_PAYMENT_RECORDED, 0) <= 0.10 THEN '2. Late in up to 10% of installments'
        WHEN 1.0 * i.INST_LATE_COUNT
             / NULLIF(i.INST_COUNT - i.INST_NO_PAYMENT_RECORDED, 0) <= 0.30 THEN '3. Late in 10-30%'
        ELSE                                                            '4. Late in over 30%'
    END                                                     AS INST_LATE_GROUP,
    CASE
        WHEN i.SK_ID_CURR IS NULL            THEN '0. No installment history'
        WHEN i.INST_LATE_30PLUS_COUNT > 0    THEN '2. Ever 30+ days late'
        ELSE                                      '1. Never 30+ days late'
    END                                                     AS INST_SEVERE_LATE_GROUP,
    CASE
        WHEN i.SK_ID_CURR IS NULL            THEN '0. No installment history'
        WHEN i.INST_UNDERPAID_COUNT > 0      THEN '2. Has underpaid installments'
        ELSE                                      '1. Always paid in full'
    END                                                     AS INST_UNDERPAID_GROUP
FROM analytics.vw_application_enriched AS e
LEFT JOIN analytics.vw_installments_by_customer AS i ON i.SK_ID_CURR = e.SK_ID_CURR;
GO

/* ====================== CHECKS ====================== */

-- A. Raw rows loaded (must equal the "Rows read from CSV" the loader printed, ~13.6M)
SELECT COUNT(*) AS raw_payment_rows FROM stg.installments_payments;

-- B. How many rows collapsed into installments (the partial-payment effect)
SELECT (SELECT COUNT(*) FROM stg.installments_payments) AS raw_rows,
       (SELECT COUNT(*) FROM analytics.installment_level) AS installment_rows,
       (SELECT COUNT(*) FROM analytics.installment_level WHERE PAYMENT_ROWS > 1) AS installments_with_multiple_rows;

-- C. Sanity: due date should be identical across rows of the same installment (expect 0)
SELECT COUNT(*) AS groups_with_conflicting_due_dates
FROM (SELECT 1 AS x
      FROM stg.installments_payments
      GROUP BY SK_ID_PREV, NUM_INSTALMENT_VERSION, NUM_INSTALMENT_NUMBER
      HAVING MIN(DAYS_INSTALMENT) <> MAX(DAYS_INSTALMENT)) t;

-- D. Final view keeps exactly one row per application (expect 307511 / 307511)
SELECT COUNT(*) AS rows_in_full_view, COUNT(DISTINCT SK_ID_CURR) AS distinct_applications
FROM analytics.vw_application_full;

-- E. Coverage
SELECT SUM(HAS_INSTALLMENT_HISTORY) AS applicants_with_installment_history
FROM analytics.vw_application_full;

-- F. Insight: difficulty rate by how often the customer paid late before
SELECT INST_LATE_GROUP,
       COUNT(*)                                       AS applications,
       SUM(CAST(TARGET AS INT))                       AS difficulty_cases,
       CAST(100.0 * AVG(CAST(TARGET AS FLOAT)) AS DECIMAL(5,2)) AS difficulty_rate_pct
FROM analytics.vw_application_full
GROUP BY INST_LATE_GROUP
ORDER BY INST_LATE_GROUP;

-- G. Insight: severe lateness (30+ days)
SELECT INST_SEVERE_LATE_GROUP,
       COUNT(*)                                       AS applications,
       SUM(CAST(TARGET AS INT))                       AS difficulty_cases,
       CAST(100.0 * AVG(CAST(TARGET AS FLOAT)) AS DECIMAL(5,2)) AS difficulty_rate_pct
FROM analytics.vw_application_full
GROUP BY INST_SEVERE_LATE_GROUP
ORDER BY INST_SEVERE_LATE_GROUP;

-- H. Insight: underpayment
SELECT INST_UNDERPAID_GROUP,
       COUNT(*)                                       AS applications,
       SUM(CAST(TARGET AS INT))                       AS difficulty_cases,
       CAST(100.0 * AVG(CAST(TARGET AS FLOAT)) AS DECIMAL(5,2)) AS difficulty_rate_pct
FROM analytics.vw_application_full
GROUP BY INST_UNDERPAID_GROUP
ORDER BY INST_UNDERPAID_GROUP;
