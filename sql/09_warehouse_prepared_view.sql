/* ============================================================
   Step 9: warehouse.vw_Source_Prepared
   The ONE place where every warehouse transformation (bands, groupings, labels, sort order,
   missing-value handling) is defined. Dimensions are built from SELECT DISTINCT over this view and the
   fact table joins back to the dimensions on the same columns, so the two can never disagree.
   Source: analytics.vw_application_full (after 07_view_fixes.sql).
   ============================================================ */
USE HomeCreditDB;
GO

CREATE OR ALTER VIEW warehouse.vw_Source_Prepared AS
SELECT
    s.SK_ID_CURR AS ApplicationID,
    /* Dim_Customer attributes */
    CASE s.GENDER WHEN 'F' THEN 'Female' WHEN 'M' THEN 'Male' ELSE 'Unknown' END AS Gender,
    ISNULL(s.AGE_GROUP, 'Unknown') AS AgeGroup,
    CASE s.AGE_GROUP WHEN '20-24' THEN 1 WHEN '25-34' THEN 2 WHEN '35-44' THEN 3 WHEN '45-54' THEN 4 WHEN '55-64' THEN 5 WHEN '65+' THEN 6 ELSE 99 END AS AgeGroupSort,
    ISNULL(s.FAMILY_STATUS, 'Unknown') AS FamilyStatus,
    CASE WHEN s.CNT_CHILDREN IS NULL THEN 'Unknown' WHEN s.CNT_CHILDREN >= 3 THEN '3+' ELSE CAST(s.CNT_CHILDREN AS VARCHAR(10)) END AS ChildrenBand,
    CASE WHEN s.CNT_CHILDREN IS NULL THEN 99 WHEN s.CNT_CHILDREN >= 3 THEN 3 ELSE s.CNT_CHILDREN END AS ChildrenBandSort,
    ISNULL(s.EDUCATION, 'Unknown') AS EducationLevel,
    CASE s.EDUCATION WHEN 'Lower secondary' THEN 1 WHEN 'Secondary / secondary special' THEN 2 WHEN 'Incomplete higher' THEN 3 WHEN 'Higher education' THEN 4 WHEN 'Academic degree' THEN 5 ELSE 99 END AS EducationSort,
    /* Dim_Household attributes */
    ISNULL(s.HOUSING_TYPE, 'Unknown') AS HousingType,
    CASE s.FLAG_OWN_CAR WHEN 'Y' THEN 'Yes' WHEN 'N' THEN 'No' ELSE 'Unknown' END AS OwnsCar,
    CASE s.FLAG_OWN_REALTY WHEN 'Y' THEN 'Yes' WHEN 'N' THEN 'No' ELSE 'Unknown' END AS OwnsRealty,
    ISNULL(CAST(s.REGION_RATING AS TINYINT), 0) AS RegionRating,
    /* Dim_Employment attributes */
    CASE WHEN s.INCOME_TYPE IN ('Unemployed', 'Student', 'Businessman', 'Maternity leave') THEN 'Other' ELSE ISNULL(s.INCOME_TYPE, 'Unknown') END AS IncomeSource,
    ISNULL(s.INCOME_TYPE, 'Unknown') AS IncomeSourceDetail,
    ISNULL(s.OCCUPATION, 'Not reported') AS OccupationType,
    CASE WHEN s.YEARS_EMPLOYED IS NULL THEN 'Not reported' WHEN s.YEARS_EMPLOYED < 1 THEN 'Under 1 year' WHEN s.YEARS_EMPLOYED < 3 THEN '1-3 years' WHEN s.YEARS_EMPLOYED < 5 THEN '3-5 years' WHEN s.YEARS_EMPLOYED < 10 THEN '5-10 years' ELSE '10+ years' END AS EmploymentTenureBand,
    CASE WHEN s.YEARS_EMPLOYED IS NULL THEN 6 WHEN s.YEARS_EMPLOYED < 1 THEN 1 WHEN s.YEARS_EMPLOYED < 3 THEN 2 WHEN s.YEARS_EMPLOYED < 5 THEN 3 WHEN s.YEARS_EMPLOYED < 10 THEN 4 ELSE 5 END AS EmploymentTenureSort,
    /* Dim_Organization attributes */
    ISNULL(s.ORGANIZATION_TYPE, 'Not applicable') AS OrganizationType,
    ISNULL(m.OrganizationSector, 'Unmapped') AS OrganizationSector,
    /* Dim_LoanProfile attributes */
    ISNULL(s.CONTRACT_TYPE, 'Unknown') AS ContractType,
    CASE WHEN s.INCOME_BAND LIKE '[0-9]. %' THEN SUBSTRING(s.INCOME_BAND, 4, 100) ELSE ISNULL(s.INCOME_BAND, 'Unknown') END AS IncomeBand,
    CASE WHEN s.INCOME_BAND LIKE '[0-9]. %' THEN CAST(LEFT(s.INCOME_BAND, 1) AS TINYINT) ELSE 99 END AS IncomeBandSort,
    CASE WHEN s.CREDIT_INCOME_RATIO IS NULL THEN 'Unknown' WHEN s.CREDIT_INCOME_RATIO < 2 THEN 'Under 2x' WHEN s.CREDIT_INCOME_RATIO < 3 THEN '2x-3x' WHEN s.CREDIT_INCOME_RATIO < 4 THEN '3x-4x' WHEN s.CREDIT_INCOME_RATIO < 5 THEN '4x-5x' WHEN s.CREDIT_INCOME_RATIO < 7 THEN '5x-7x' ELSE '7x+' END AS CreditToIncomeBand,
    CASE WHEN s.CREDIT_INCOME_RATIO IS NULL THEN 99 WHEN s.CREDIT_INCOME_RATIO < 2 THEN 1 WHEN s.CREDIT_INCOME_RATIO < 3 THEN 2 WHEN s.CREDIT_INCOME_RATIO < 4 THEN 3 WHEN s.CREDIT_INCOME_RATIO < 5 THEN 4 WHEN s.CREDIT_INCOME_RATIO < 7 THEN 5 ELSE 6 END AS CreditToIncomeSort,
    CASE WHEN s.ANNUITY_INCOME_RATIO IS NULL THEN 'Unknown' WHEN s.ANNUITY_INCOME_RATIO < 0.10 THEN 'Under 10%' WHEN s.ANNUITY_INCOME_RATIO < 0.15 THEN '10%-15%' WHEN s.ANNUITY_INCOME_RATIO < 0.20 THEN '15%-20%' WHEN s.ANNUITY_INCOME_RATIO < 0.25 THEN '20%-25%' WHEN s.ANNUITY_INCOME_RATIO < 0.35 THEN '25%-35%' ELSE '35%+' END AS AnnuityToIncomeBand,
    CASE WHEN s.ANNUITY_INCOME_RATIO IS NULL THEN 99 WHEN s.ANNUITY_INCOME_RATIO < 0.10 THEN 1 WHEN s.ANNUITY_INCOME_RATIO < 0.15 THEN 2 WHEN s.ANNUITY_INCOME_RATIO < 0.20 THEN 3 WHEN s.ANNUITY_INCOME_RATIO < 0.25 THEN 4 WHEN s.ANNUITY_INCOME_RATIO < 0.35 THEN 5 ELSE 6 END AS AnnuityToIncomeSort,
    /* Dim_RiskAndHistory attributes */
    CASE WHEN s.BUREAU_HISTORY_GROUP LIKE '[0-9]. %' THEN SUBSTRING(s.BUREAU_HISTORY_GROUP, 4, 100) ELSE ISNULL(s.BUREAU_HISTORY_GROUP, 'Unknown') END AS BureauHistoryGroup,
    CASE WHEN s.BUREAU_HISTORY_GROUP LIKE '[0-9]. %' THEN CAST(LEFT(s.BUREAU_HISTORY_GROUP, 1) AS TINYINT) ELSE 99 END AS BureauHistorySort,
    ISNULL(s.BUREAU_OVERDUE_GROUP, 'Unknown') AS BureauOverdueGroup,
    CASE s.BUREAU_OVERDUE_GROUP WHEN 'No bureau record' THEN 0 WHEN 'No overdue credit' THEN 1 WHEN 'Has overdue credit' THEN 2 ELSE 99 END AS BureauOverdueSort,
    CASE WHEN s.PREV_REFUSAL_GROUP LIKE '[0-9]. %' THEN SUBSTRING(s.PREV_REFUSAL_GROUP, 4, 100) ELSE ISNULL(s.PREV_REFUSAL_GROUP, 'Unknown') END AS PreviousRefusalGroup,
    CASE WHEN s.PREV_REFUSAL_GROUP LIKE '[0-9]. %' THEN CAST(LEFT(s.PREV_REFUSAL_GROUP, 1) AS TINYINT) ELSE 99 END AS PreviousRefusalSort,
    CASE WHEN s.INST_LATE_GROUP LIKE '[0-9]. %' THEN SUBSTRING(s.INST_LATE_GROUP, 4, 100) ELSE ISNULL(s.INST_LATE_GROUP, 'Unknown') END AS InstallmentLateGroup,
    CASE WHEN s.INST_LATE_GROUP LIKE '[0-9]. %' THEN CAST(LEFT(s.INST_LATE_GROUP, 1) AS TINYINT) ELSE 99 END AS InstallmentLateSort,
    CASE WHEN s.INST_SEVERE_LATE_GROUP LIKE '[0-9]. %' THEN SUBSTRING(s.INST_SEVERE_LATE_GROUP, 4, 100) ELSE ISNULL(s.INST_SEVERE_LATE_GROUP, 'Unknown') END AS InstallmentSevereLateGroup,
    CASE WHEN s.INST_SEVERE_LATE_GROUP LIKE '[0-9]. %' THEN CAST(LEFT(s.INST_SEVERE_LATE_GROUP, 1) AS TINYINT) ELSE 99 END AS InstallmentSevereLateSort,
    CASE WHEN s.INST_UNDERPAID_GROUP LIKE '[0-9]. %' THEN SUBSTRING(s.INST_UNDERPAID_GROUP, 4, 100) ELSE ISNULL(s.INST_UNDERPAID_GROUP, 'Unknown') END AS InstallmentUnderpaidGroup,
    CASE WHEN s.INST_UNDERPAID_GROUP LIKE '[0-9]. %' THEN CAST(LEFT(s.INST_UNDERPAID_GROUP, 1) AS TINYINT) ELSE 99 END AS InstallmentUnderpaidSort,
    /* fact measures */
    CAST(s.TARGET AS TINYINT) AS PaymentDifficultyFlag,
    s.INCOME AS IncomeAmount,
    CASE WHEN s.INCOME > 1000000 THEN CAST(1000000 AS DECIMAL(18,2)) ELSE s.INCOME END AS IncomeAmountCapped,
    s.LOAN_AMOUNT AS LoanAmount,
    s.ANNUITY AS AnnuityAmount,
    s.GOODS_PRICE AS GoodsPriceAmount,
    s.BUREAU_TOTAL_CREDIT AS BureauTotalCredit,
    s.BUREAU_TOTAL_DEBT AS BureauTotalDebt,
    s.CREDIT_INCOME_RATIO AS CreditToIncomeRatio,
    s.ANNUITY_INCOME_RATIO AS AnnuityToIncomeRatio,
    s.LOAN_TERM_MONTHS_EST AS EstimatedLoanTermMonths,
    s.BUREAU_DEBT_TO_CREDIT_RATIO AS BureauDebtToCreditRatio,
    s.PREV_REFUSAL_RATE AS PreviousRefusalRate,
    s.INST_LATE_RATE AS InstallmentLateRate,
    s.EXT_SOURCE_1 AS ExtSource1,
    s.EXT_SOURCE_2 AS ExtSource2,
    s.EXT_SOURCE_3 AS ExtSource3,
    s.AGE_YEARS AS AgeYears,
    s.YEARS_EMPLOYED AS YearsEmployed,
    s.OWN_CAR_AGE AS OwnCarAge,
    s.CNT_CHILDREN AS ChildrenCount,
    s.CNT_FAM_MEMBERS AS FamilyMemberCount,
    s.BUREAU_LOAN_COUNT AS BureauCreditCount,
    s.BUREAU_ACTIVE_COUNT AS BureauActiveCount,
    s.BUREAU_CLOSED_COUNT AS BureauClosedCount,
    s.BUREAU_OVERDUE_LOAN_COUNT AS BureauOverdueCreditCount,
    s.BUREAU_MAX_DAYS_OVERDUE AS BureauMaxDaysOverdue,
    s.PREV_APPLICATION_COUNT AS PreviousApplicationCount,
    s.PREV_APPROVED_COUNT AS PreviousApprovedCount,
    s.PREV_REFUSED_COUNT AS PreviousRefusedCount,
    s.PREV_DAYS_SINCE_LAST_DECISION AS PreviousDaysSinceLastDecision,
    s.INST_COUNT AS InstallmentCount,
    s.INST_LATE_COUNT AS InstallmentLateCount,
    s.INST_LATE_30PLUS_COUNT AS InstallmentLate30PlusCount,
    s.INST_UNDERPAID_COUNT AS InstallmentUnderpaidCount,
    s.INST_NO_PAYMENT_RECORDED AS InstallmentNoPaymentCount,
    s.INST_AVG_DAYS_LATE AS InstallmentAvgDaysLate,
    s.INST_MAX_DAYS_LATE AS InstallmentMaxDaysLate,
    s.AMT_REQ_CREDIT_BUREAU_YEAR AS BureauEnquiriesLastYear,
    s.DEF_30_CNT_SOCIAL_CIRCLE AS SocialCircleDefaults30,
    s.DEF_60_CNT_SOCIAL_CIRCLE AS SocialCircleDefaults60,
    CAST(s.INCOME_OUTLIER_FLAG AS TINYINT) AS IncomeOutlierFlag,
    CAST(s.BUREAU_DEBT_EXCEEDS_CREDIT_FLAG AS TINYINT) AS BureauDebtExceedsCreditFlag
FROM analytics.vw_application_full AS s
LEFT JOIN warehouse.Map_OrganizationSector AS m
       ON m.OrganizationType = ISNULL(s.ORGANIZATION_TYPE, 'Not applicable');
GO
