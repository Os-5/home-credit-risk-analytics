/* ============================================================
   Step 10: warehouse.usp_Load_Warehouse  -  full, atomic refresh of the star schema
   - snapshots the prepared source once (#src)
   - rebuilds every dimension (deterministic surrogate keys via ROW_NUMBER) + the 'Unassigned' member (-1)
   - loads the fact table by joining back to the dimensions
   - reconciles to the staging tables and the analytics view INSIDE the transaction:
       any FAIL  -> ROLLBACK (the previous warehouse stays intact) and the run is logged as 'Rolled back'
       all PASS  -> COMMIT
   - every run is logged in warehouse.ETL_Run_Log, every check in warehouse.Reconciliation_Result
   Usage:  EXEC warehouse.usp_Load_Warehouse;
   ============================================================ */
USE HomeCreditDB;
GO

CREATE OR ALTER PROCEDURE warehouse.usp_Load_Warehouse
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @RunID INT, @src INT = 0, @fact INT = 0, @failed BIT = 0;
    DECLARE @e DECIMAL(38,2), @a DECIMAL(38,2);
    DECLARE @Recon TABLE (CheckName VARCHAR(120), ExpectedValue VARCHAR(60), ActualValue VARCHAR(60), Status VARCHAR(10));

    INSERT INTO warehouse.ETL_Run_Log (StartedAt, Status) VALUES (SYSDATETIME(), 'Running');
    SET @RunID = SCOPE_IDENTITY();

    BEGIN TRY
        BEGIN TRANSACTION;

        /* 0. Snapshot the prepared source ONCE. The unique index doubles as a duplicate-application guard. */
        SELECT * INTO #src FROM warehouse.vw_Source_Prepared;
        CREATE UNIQUE CLUSTERED INDEX IX_src_ApplicationID ON #src (ApplicationID);
        SELECT @src = COUNT(*) FROM #src;

        /* 1. Clear (fact first because of the foreign keys) */
        DELETE FROM warehouse.Fact_LoanApplications;
        DELETE FROM warehouse.Dim_Customer;
        DELETE FROM warehouse.Dim_Household;
        DELETE FROM warehouse.Dim_Employment;
        DELETE FROM warehouse.Dim_Organization;
        DELETE FROM warehouse.Dim_LoanProfile;
        DELETE FROM warehouse.Dim_RiskAndHistory;

        /* 2. 'Unassigned' member (key -1) in every dimension: facts never carry a NULL foreign key */
        INSERT INTO warehouse.Dim_Customer (CustomerKey, Gender, AgeGroup, AgeGroupSort, FamilyStatus, ChildrenBand, ChildrenBandSort, EducationLevel, EducationSort) VALUES (-1, 'Unassigned', 'Unassigned', 99, 'Unassigned', 'Unassigned', 99, 'Unassigned', 99);
        INSERT INTO warehouse.Dim_Household (HouseholdKey, HousingType, OwnsCar, OwnsRealty, RegionRating) VALUES (-1, 'Unassigned', 'Unassigned', 'Unassigned', 0);
        INSERT INTO warehouse.Dim_Employment (EmploymentKey, IncomeSource, IncomeSourceDetail, OccupationType, EmploymentTenureBand, EmploymentTenureSort) VALUES (-1, 'Unassigned', 'Unassigned', 'Unassigned', 'Unassigned', 99);
        INSERT INTO warehouse.Dim_Organization (OrganizationKey, OrganizationType, OrganizationSector) VALUES (-1, 'Unassigned', 'Unassigned');
        INSERT INTO warehouse.Dim_LoanProfile (LoanProfileKey, ContractType, IncomeBand, IncomeBandSort, CreditToIncomeBand, CreditToIncomeSort, AnnuityToIncomeBand, AnnuityToIncomeSort) VALUES (-1, 'Unassigned', 'Unassigned', 99, 'Unassigned', 99, 'Unassigned', 99);
        INSERT INTO warehouse.Dim_RiskAndHistory (RiskHistoryKey, BureauHistoryGroup, BureauHistorySort, BureauOverdueGroup, BureauOverdueSort, PreviousRefusalGroup, PreviousRefusalSort, InstallmentLateGroup, InstallmentLateSort, InstallmentSevereLateGroup, InstallmentSevereLateSort, InstallmentUnderpaidGroup, InstallmentUnderpaidSort) VALUES (-1, 'Unassigned', 99, 'Unassigned', 99, 'Unassigned', 99, 'Unassigned', 99, 'Unassigned', 99, 'Unassigned', 99);

        /* 3. Dimensions: one row per distinct attribute combination; keys are deterministic (same data -> same keys) */
        INSERT INTO warehouse.Dim_Customer (CustomerKey, Gender, AgeGroup, AgeGroupSort, FamilyStatus, ChildrenBand, ChildrenBandSort, EducationLevel, EducationSort)
        SELECT ROW_NUMBER() OVER (ORDER BY Gender, AgeGroup, FamilyStatus, ChildrenBand, EducationLevel), Gender, AgeGroup, AgeGroupSort, FamilyStatus, ChildrenBand, ChildrenBandSort, EducationLevel, EducationSort
        FROM (SELECT DISTINCT Gender, AgeGroup, AgeGroupSort, FamilyStatus, ChildrenBand, ChildrenBandSort, EducationLevel, EducationSort FROM #src) AS d;

        INSERT INTO warehouse.Dim_Household (HouseholdKey, HousingType, OwnsCar, OwnsRealty, RegionRating)
        SELECT ROW_NUMBER() OVER (ORDER BY HousingType, OwnsCar, OwnsRealty, RegionRating), HousingType, OwnsCar, OwnsRealty, RegionRating
        FROM (SELECT DISTINCT HousingType, OwnsCar, OwnsRealty, RegionRating FROM #src) AS d;

        INSERT INTO warehouse.Dim_Employment (EmploymentKey, IncomeSource, IncomeSourceDetail, OccupationType, EmploymentTenureBand, EmploymentTenureSort)
        SELECT ROW_NUMBER() OVER (ORDER BY IncomeSource, IncomeSourceDetail, OccupationType, EmploymentTenureBand), IncomeSource, IncomeSourceDetail, OccupationType, EmploymentTenureBand, EmploymentTenureSort
        FROM (SELECT DISTINCT IncomeSource, IncomeSourceDetail, OccupationType, EmploymentTenureBand, EmploymentTenureSort FROM #src) AS d;

        INSERT INTO warehouse.Dim_Organization (OrganizationKey, OrganizationType, OrganizationSector)
        SELECT ROW_NUMBER() OVER (ORDER BY OrganizationType, OrganizationSector), OrganizationType, OrganizationSector
        FROM (SELECT DISTINCT OrganizationType, OrganizationSector FROM #src) AS d;

        INSERT INTO warehouse.Dim_LoanProfile (LoanProfileKey, ContractType, IncomeBand, IncomeBandSort, CreditToIncomeBand, CreditToIncomeSort, AnnuityToIncomeBand, AnnuityToIncomeSort)
        SELECT ROW_NUMBER() OVER (ORDER BY ContractType, IncomeBand, CreditToIncomeBand, AnnuityToIncomeBand), ContractType, IncomeBand, IncomeBandSort, CreditToIncomeBand, CreditToIncomeSort, AnnuityToIncomeBand, AnnuityToIncomeSort
        FROM (SELECT DISTINCT ContractType, IncomeBand, IncomeBandSort, CreditToIncomeBand, CreditToIncomeSort, AnnuityToIncomeBand, AnnuityToIncomeSort FROM #src) AS d;

        INSERT INTO warehouse.Dim_RiskAndHistory (RiskHistoryKey, BureauHistoryGroup, BureauHistorySort, BureauOverdueGroup, BureauOverdueSort, PreviousRefusalGroup, PreviousRefusalSort, InstallmentLateGroup, InstallmentLateSort, InstallmentSevereLateGroup, InstallmentSevereLateSort, InstallmentUnderpaidGroup, InstallmentUnderpaidSort)
        SELECT ROW_NUMBER() OVER (ORDER BY BureauHistoryGroup, BureauOverdueGroup, PreviousRefusalGroup, InstallmentLateGroup, InstallmentSevereLateGroup, InstallmentUnderpaidGroup), BureauHistoryGroup, BureauHistorySort, BureauOverdueGroup, BureauOverdueSort, PreviousRefusalGroup, PreviousRefusalSort, InstallmentLateGroup, InstallmentLateSort, InstallmentSevereLateGroup, InstallmentSevereLateSort, InstallmentUnderpaidGroup, InstallmentUnderpaidSort
        FROM (SELECT DISTINCT BureauHistoryGroup, BureauHistorySort, BureauOverdueGroup, BureauOverdueSort, PreviousRefusalGroup, PreviousRefusalSort, InstallmentLateGroup, InstallmentLateSort, InstallmentSevereLateGroup, InstallmentSevereLateSort, InstallmentUnderpaidGroup, InstallmentUnderpaidSort FROM #src) AS d;

        /* 4. Fact table: LEFT JOIN + ISNULL(-1) so a row can never be silently dropped */
        INSERT INTO warehouse.Fact_LoanApplications
               (ApplicationID, CustomerKey, HouseholdKey, EmploymentKey, OrganizationKey, LoanProfileKey, RiskHistoryKey,
                PaymentDifficultyFlag, IncomeAmount, IncomeAmountCapped, LoanAmount, AnnuityAmount, GoodsPriceAmount, BureauTotalCredit, BureauTotalDebt, CreditToIncomeRatio, AnnuityToIncomeRatio, EstimatedLoanTermMonths, BureauDebtToCreditRatio, PreviousRefusalRate, InstallmentLateRate, ExtSource1, ExtSource2, ExtSource3, AgeYears, YearsEmployed, OwnCarAge, ChildrenCount, FamilyMemberCount, BureauCreditCount, BureauActiveCount, BureauClosedCount, BureauOverdueCreditCount, BureauMaxDaysOverdue, PreviousApplicationCount, PreviousApprovedCount, PreviousRefusedCount, PreviousDaysSinceLastDecision, InstallmentCount, InstallmentLateCount, InstallmentLate30PlusCount, InstallmentUnderpaidCount, InstallmentNoPaymentCount, InstallmentAvgDaysLate, InstallmentMaxDaysLate, BureauEnquiriesLastYear, SocialCircleDefaults30, SocialCircleDefaults60, IncomeOutlierFlag, BureauDebtExceedsCreditFlag)
        SELECT p.ApplicationID,
               ISNULL(c.CustomerKey, -1),
               ISNULL(h.HouseholdKey, -1),
               ISNULL(e.EmploymentKey, -1),
               ISNULL(o.OrganizationKey, -1),
               ISNULL(l.LoanProfileKey, -1),
               ISNULL(r.RiskHistoryKey, -1),
               p.PaymentDifficultyFlag, p.IncomeAmount, p.IncomeAmountCapped, p.LoanAmount, p.AnnuityAmount, p.GoodsPriceAmount, p.BureauTotalCredit, p.BureauTotalDebt, p.CreditToIncomeRatio, p.AnnuityToIncomeRatio, p.EstimatedLoanTermMonths, p.BureauDebtToCreditRatio, p.PreviousRefusalRate, p.InstallmentLateRate, p.ExtSource1, p.ExtSource2, p.ExtSource3, p.AgeYears, p.YearsEmployed, p.OwnCarAge, p.ChildrenCount, p.FamilyMemberCount, p.BureauCreditCount, p.BureauActiveCount, p.BureauClosedCount, p.BureauOverdueCreditCount, p.BureauMaxDaysOverdue, p.PreviousApplicationCount, p.PreviousApprovedCount, p.PreviousRefusedCount, p.PreviousDaysSinceLastDecision, p.InstallmentCount, p.InstallmentLateCount, p.InstallmentLate30PlusCount, p.InstallmentUnderpaidCount, p.InstallmentNoPaymentCount, p.InstallmentAvgDaysLate, p.InstallmentMaxDaysLate, p.BureauEnquiriesLastYear, p.SocialCircleDefaults30, p.SocialCircleDefaults60, p.IncomeOutlierFlag, p.BureauDebtExceedsCreditFlag
        FROM #src AS p
        LEFT JOIN warehouse.Dim_Customer AS c ON c.Gender = p.Gender AND c.AgeGroup = p.AgeGroup AND c.FamilyStatus = p.FamilyStatus AND c.ChildrenBand = p.ChildrenBand AND c.EducationLevel = p.EducationLevel
        LEFT JOIN warehouse.Dim_Household AS h ON h.HousingType = p.HousingType AND h.OwnsCar = p.OwnsCar AND h.OwnsRealty = p.OwnsRealty AND h.RegionRating = p.RegionRating
        LEFT JOIN warehouse.Dim_Employment AS e ON e.IncomeSource = p.IncomeSource AND e.IncomeSourceDetail = p.IncomeSourceDetail AND e.OccupationType = p.OccupationType AND e.EmploymentTenureBand = p.EmploymentTenureBand
        LEFT JOIN warehouse.Dim_Organization AS o ON o.OrganizationType = p.OrganizationType AND o.OrganizationSector = p.OrganizationSector
        LEFT JOIN warehouse.Dim_LoanProfile AS l ON l.ContractType = p.ContractType AND l.IncomeBand = p.IncomeBand AND l.CreditToIncomeBand = p.CreditToIncomeBand AND l.AnnuityToIncomeBand = p.AnnuityToIncomeBand
        LEFT JOIN warehouse.Dim_RiskAndHistory AS r ON r.BureauHistoryGroup = p.BureauHistoryGroup AND r.BureauOverdueGroup = p.BureauOverdueGroup AND r.PreviousRefusalGroup = p.PreviousRefusalGroup AND r.InstallmentLateGroup = p.InstallmentLateGroup AND r.InstallmentSevereLateGroup = p.InstallmentSevereLateGroup AND r.InstallmentUnderpaidGroup = p.InstallmentUnderpaidGroup;
        SELECT @fact = COUNT(*) FROM warehouse.Fact_LoanApplications;

        /* 5. Reconciliation (inside the transaction) */
        SELECT @e = (SELECT COUNT(*) FROM analytics.vw_application_full); SELECT @a = (SELECT COUNT(*) FROM warehouse.Fact_LoanApplications);
        INSERT INTO @Recon VALUES ('Fact rows = rows in analytics.vw_application_full', CAST(CAST(@e AS BIGINT) AS VARCHAR(40)), CAST(CAST(@a AS BIGINT) AS VARCHAR(40)), CASE WHEN ABS(@e - @a) < 0.5 THEN 'PASS' ELSE 'FAIL' END);
        SELECT @e = (SELECT COUNT(*) FROM warehouse.Fact_LoanApplications); SELECT @a = (SELECT COUNT(DISTINCT ApplicationID) FROM warehouse.Fact_LoanApplications);
        INSERT INTO @Recon VALUES ('Distinct ApplicationID = fact rows', CAST(CAST(@e AS BIGINT) AS VARCHAR(40)), CAST(CAST(@a AS BIGINT) AS VARCHAR(40)), CASE WHEN ABS(@e - @a) < 0.5 THEN 'PASS' ELSE 'FAIL' END);
        SELECT @e = (SELECT SUM(CAST(TARGET AS INT)) FROM stg.application_train); SELECT @a = (SELECT SUM(CAST(PaymentDifficultyFlag AS INT)) FROM warehouse.Fact_LoanApplications);
        INSERT INTO @Recon VALUES ('Payment-difficulty cases = SUM(TARGET) in staging', CAST(CAST(@e AS BIGINT) AS VARCHAR(40)), CAST(CAST(@a AS BIGINT) AS VARCHAR(40)), CASE WHEN ABS(@e - @a) < 0.5 THEN 'PASS' ELSE 'FAIL' END);
        SELECT @e = (SELECT SUM(AMT_INCOME_TOTAL) FROM stg.application_train); SELECT @a = (SELECT SUM(IncomeAmount) FROM warehouse.Fact_LoanApplications);
        INSERT INTO @Recon VALUES ('Total income = staging', CAST(@e AS VARCHAR(40)), CAST(@a AS VARCHAR(40)), CASE WHEN ABS(@e - @a) < 0.5 THEN 'PASS' ELSE 'FAIL' END);
        SELECT @e = (SELECT SUM(AMT_CREDIT) FROM stg.application_train); SELECT @a = (SELECT SUM(LoanAmount) FROM warehouse.Fact_LoanApplications);
        INSERT INTO @Recon VALUES ('Total loan amount = staging', CAST(@e AS VARCHAR(40)), CAST(@a AS VARCHAR(40)), CASE WHEN ABS(@e - @a) < 0.5 THEN 'PASS' ELSE 'FAIL' END);
        SELECT @e = (SELECT SUM(BUREAU_LOAN_COUNT) FROM analytics.vw_application_full); SELECT @a = (SELECT SUM(BureauCreditCount) FROM warehouse.Fact_LoanApplications);
        INSERT INTO @Recon VALUES ('Bureau credits = analytics view', CAST(CAST(@e AS BIGINT) AS VARCHAR(40)), CAST(CAST(@a AS BIGINT) AS VARCHAR(40)), CASE WHEN ABS(@e - @a) < 0.5 THEN 'PASS' ELSE 'FAIL' END);
        SELECT @e = (SELECT SUM(PREV_APPLICATION_COUNT) FROM analytics.vw_application_full); SELECT @a = (SELECT SUM(PreviousApplicationCount) FROM warehouse.Fact_LoanApplications);
        INSERT INTO @Recon VALUES ('Previous applications = analytics view', CAST(CAST(@e AS BIGINT) AS VARCHAR(40)), CAST(CAST(@a AS BIGINT) AS VARCHAR(40)), CASE WHEN ABS(@e - @a) < 0.5 THEN 'PASS' ELSE 'FAIL' END);
        SELECT @e = (SELECT SUM(INST_COUNT) FROM analytics.vw_application_full); SELECT @a = (SELECT SUM(InstallmentCount) FROM warehouse.Fact_LoanApplications);
        INSERT INTO @Recon VALUES ('Installments = analytics view', CAST(CAST(@e AS BIGINT) AS VARCHAR(40)), CAST(CAST(@a AS BIGINT) AS VARCHAR(40)), CASE WHEN ABS(@e - @a) < 0.5 THEN 'PASS' ELSE 'FAIL' END);
        SELECT @e = (SELECT SUM(INST_LATE_COUNT) FROM analytics.vw_application_full); SELECT @a = (SELECT SUM(InstallmentLateCount) FROM warehouse.Fact_LoanApplications);
        INSERT INTO @Recon VALUES ('Late installments = analytics view', CAST(CAST(@e AS BIGINT) AS VARCHAR(40)), CAST(CAST(@a AS BIGINT) AS VARCHAR(40)), CASE WHEN ABS(@e - @a) < 0.5 THEN 'PASS' ELSE 'FAIL' END);
        SELECT @e = (SELECT 0); SELECT @a = (SELECT COUNT(*) FROM warehouse.Fact_LoanApplications WHERE CustomerKey = -1 OR HouseholdKey = -1 OR EmploymentKey = -1 OR OrganizationKey = -1 OR LoanProfileKey = -1 OR RiskHistoryKey = -1);
        INSERT INTO @Recon VALUES ('Fact rows pointing to an ''Unassigned'' member (expect 0)', CAST(CAST(@e AS BIGINT) AS VARCHAR(40)), CAST(CAST(@a AS BIGINT) AS VARCHAR(40)), CASE WHEN ABS(@e - @a) < 0.5 THEN 'PASS' ELSE 'FAIL' END);
        SELECT @e = (SELECT 0); SELECT @a = (SELECT COUNT(*) FROM warehouse.Dim_Organization WHERE OrganizationSector = 'Unmapped');
        INSERT INTO @Recon VALUES ('Organization types missing from Map_OrganizationSector (expect 0)', CAST(CAST(@e AS BIGINT) AS VARCHAR(40)), CAST(CAST(@a AS BIGINT) AS VARCHAR(40)), CASE WHEN ABS(@e - @a) < 0.5 THEN 'PASS' ELSE 'FAIL' END);
        SELECT @a = (SELECT MAX(n) FROM (SELECT COUNT(*) AS n FROM warehouse.Dim_Customer UNION ALL SELECT COUNT(*) AS n FROM warehouse.Dim_Household UNION ALL SELECT COUNT(*) AS n FROM warehouse.Dim_Employment UNION ALL SELECT COUNT(*) AS n FROM warehouse.Dim_Organization UNION ALL SELECT COUNT(*) AS n FROM warehouse.Dim_LoanProfile UNION ALL SELECT COUNT(*) AS n FROM warehouse.Dim_RiskAndHistory) x);
        INSERT INTO @Recon VALUES ('Largest dimension has at most 10,000 rows', '<= 10000', CAST(CAST(@a AS BIGINT) AS VARCHAR(40)), CASE WHEN @a <= 10000 THEN 'PASS' ELSE 'WARN' END);

        IF EXISTS (SELECT 1 FROM @Recon WHERE Status = 'FAIL') SET @failed = 1;

        IF @failed = 1 ROLLBACK TRANSACTION; ELSE COMMIT TRANSACTION;

        /* table variables survive a rollback, so failed checks are still recorded */
        INSERT INTO warehouse.Reconciliation_Result (RunID, CheckName, ExpectedValue, ActualValue, Status)
        SELECT @RunID, CheckName, ExpectedValue, ActualValue, Status FROM @Recon;

        UPDATE warehouse.ETL_Run_Log
        SET FinishedAt = SYSDATETIME(),
            Status     = CASE WHEN @failed = 1 THEN 'Rolled back' ELSE 'Succeeded' END,
            SourceRows = @src,
            FactRows   = CASE WHEN @failed = 1 THEN NULL ELSE @fact END,
            Message    = CASE WHEN @failed = 1 THEN 'Reconciliation failed - warehouse left unchanged. See warehouse.Reconciliation_Result.'
                              ELSE 'Load committed - all reconciliation checks passed.' END
        WHERE RunID = @RunID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        UPDATE warehouse.ETL_Run_Log
        SET FinishedAt = SYSDATETIME(), Status = 'Failed', Message = LEFT(ERROR_MESSAGE(), 2000)
        WHERE RunID = @RunID;
        THROW;
    END CATCH;

    /* result sets for the person running the load */
    SELECT RunID, StartedAt, FinishedAt, Status, SourceRows, FactRows, Message FROM warehouse.ETL_Run_Log WHERE RunID = @RunID;
    SELECT CheckName, ExpectedValue, ActualValue, Status FROM warehouse.Reconciliation_Result WHERE RunID = @RunID ORDER BY ResultID;
END;
GO

/* Run the load now */
EXEC warehouse.usp_Load_Warehouse;
GO
