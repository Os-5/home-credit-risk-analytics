/* ============================================================
   Step 5: staging table for installments_payments (~13.6M rows)
   Run in SSMS BEFORE load_installments.py
   ============================================================ */
USE HomeCreditDB;
GO

-- Smaller transaction log during the big load (fine for a project database)
ALTER DATABASE HomeCreditDB SET RECOVERY SIMPLE;
GO

/* Grain of the RAW table: one row per payment record.
   An installment can appear on several rows (partial payments), so there is
   deliberately NO primary key here. We collapse it to one row per installment in step 6.
   Left as a heap for a fast load; the index is added after loading. */
DROP TABLE IF EXISTS stg.installments_payments;
GO
CREATE TABLE stg.installments_payments (
    SK_ID_PREV               INT            NOT NULL,
    SK_ID_CURR               INT            NOT NULL,
    NUM_INSTALMENT_VERSION   SMALLINT       NULL,
    NUM_INSTALMENT_NUMBER    SMALLINT       NULL,
    DAYS_INSTALMENT          INT            NULL,   -- due date, days relative to current application
    DAYS_ENTRY_PAYMENT       INT            NULL,   -- actual payment date (NULL = no payment recorded)
    AMT_INSTALMENT           DECIMAL(18,2)  NULL,   -- amount due
    AMT_PAYMENT              DECIMAL(18,2)  NULL    -- amount actually paid
);
GO
