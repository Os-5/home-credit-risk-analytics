/* ============================================================
   Step 8: WAREHOUSE (star schema) - tables, constraints, control tables
   Run in SSMS AFTER 07_view_fixes.sql. Safe to re-run: dimensions and fact are dropped and recreated,
   control tables (run log, reconciliation results, data dictionary) are kept.

   Design: Kimball dimensional model, grain = ONE ROW PER LOAN APPLICATION.
   Fact_LoanApplications
      +-- Dim_Customer       (demographic profile)
      +-- Dim_Household      (housing, assets, region)
      +-- Dim_Employment     (income source, occupation, tenure)
      +-- Dim_Organization   (employer sector > type hierarchy)
      +-- Dim_LoanProfile    (contract type, income and affordability bands)
      +-- Dim_RiskAndHistory (bureau / previous-application / installment track record)
   Conventions: PascalCase, surrogate keys end in 'Key', sort helpers end in 'Sort',
   key -1 = 'Unassigned' member in every dimension, no NULLs in dimension attributes.
   ============================================================ */
USE HomeCreditDB;
GO

IF SCHEMA_ID('warehouse') IS NULL EXEC('CREATE SCHEMA warehouse');
GO

/* ---------- drop in dependency order ---------- */
DROP TABLE IF EXISTS warehouse.Fact_LoanApplications;
DROP TABLE IF EXISTS warehouse.Dim_Customer;
DROP TABLE IF EXISTS warehouse.Dim_Household;
DROP TABLE IF EXISTS warehouse.Dim_Employment;
DROP TABLE IF EXISTS warehouse.Dim_Organization;
DROP TABLE IF EXISTS warehouse.Dim_LoanProfile;
DROP TABLE IF EXISTS warehouse.Dim_RiskAndHistory;
DROP TABLE IF EXISTS warehouse.Map_OrganizationSector;
GO

/* ---------- control tables (kept between runs) ---------- */
IF OBJECT_ID('warehouse.ETL_Run_Log') IS NULL
CREATE TABLE warehouse.ETL_Run_Log (
    RunID        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ETL_Run_Log PRIMARY KEY,
    StartedAt    DATETIME2(0)  NOT NULL,
    FinishedAt   DATETIME2(0)  NULL,
    Status       VARCHAR(20)   NOT NULL,      -- Running / Succeeded / Rolled back / Failed
    SourceRows   INT           NULL,
    FactRows     INT           NULL,
    Message      NVARCHAR(2000) NULL
);
GO
IF OBJECT_ID('warehouse.Reconciliation_Result') IS NULL
CREATE TABLE warehouse.Reconciliation_Result (
    ResultID     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Reconciliation_Result PRIMARY KEY,
    RunID        INT           NOT NULL,
    CheckName    VARCHAR(120)  NOT NULL,
    ExpectedValue VARCHAR(60)  NULL,
    ActualValue  VARCHAR(60)   NULL,
    Status       VARCHAR(10)   NOT NULL,      -- PASS / FAIL / WARN
    CheckedAt    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
GO
IF OBJECT_ID('warehouse.Data_Dictionary') IS NULL
CREATE TABLE warehouse.Data_Dictionary (
    TableName    VARCHAR(60)   NOT NULL,
    ColumnName   VARCHAR(60)   NOT NULL,
    DataType     VARCHAR(30)   NOT NULL,
    ColumnRole   VARCHAR(30)   NOT NULL,
    Description  NVARCHAR(500) NOT NULL,
    SourceLineage VARCHAR(120) NULL,
    CONSTRAINT PK_Data_Dictionary PRIMARY KEY (TableName, ColumnName)
);
GO

/* ---------- reference table: organization type -> sector (data-driven, auditable) ---------- */
CREATE TABLE warehouse.Map_OrganizationSector (
    OrganizationType   VARCHAR(40) NOT NULL CONSTRAINT PK_Map_OrganizationSector PRIMARY KEY,
    OrganizationSector VARCHAR(40) NOT NULL
);
GO
INSERT INTO warehouse.Map_OrganizationSector (OrganizationType, OrganizationSector) VALUES
    ('Business Entity Type 1', 'Business Entity'),
    ('Business Entity Type 2', 'Business Entity'),
    ('Business Entity Type 3', 'Business Entity'),
    ('Industry: type 1', 'Industry'),
    ('Industry: type 2', 'Industry'),
    ('Industry: type 3', 'Industry'),
    ('Industry: type 4', 'Industry'),
    ('Industry: type 5', 'Industry'),
    ('Industry: type 6', 'Industry'),
    ('Industry: type 7', 'Industry'),
    ('Industry: type 8', 'Industry'),
    ('Industry: type 9', 'Industry'),
    ('Industry: type 10', 'Industry'),
    ('Industry: type 11', 'Industry'),
    ('Industry: type 12', 'Industry'),
    ('Industry: type 13', 'Industry'),
    ('Trade: type 1', 'Trade'),
    ('Trade: type 2', 'Trade'),
    ('Trade: type 3', 'Trade'),
    ('Trade: type 4', 'Trade'),
    ('Trade: type 5', 'Trade'),
    ('Trade: type 6', 'Trade'),
    ('Trade: type 7', 'Trade'),
    ('Transport: type 1', 'Transport'),
    ('Transport: type 2', 'Transport'),
    ('Transport: type 3', 'Transport'),
    ('Transport: type 4', 'Transport'),
    ('Self-employed', 'Self-employed'),
    ('Government', 'Public Administration & Security'),
    ('Military', 'Public Administration & Security'),
    ('Police', 'Public Administration & Security'),
    ('Security Ministries', 'Public Administration & Security'),
    ('Emergency', 'Public Administration & Security'),
    ('Medicine', 'Health & Education'),
    ('School', 'Health & Education'),
    ('Kindergarten', 'Health & Education'),
    ('University', 'Health & Education'),
    ('Bank', 'Finance & Legal'),
    ('Insurance', 'Finance & Legal'),
    ('Legal Services', 'Finance & Legal'),
    ('Construction', 'Construction & Real Estate'),
    ('Housing', 'Construction & Real Estate'),
    ('Realtor', 'Construction & Real Estate'),
    ('Hotel', 'Hospitality'),
    ('Restaurant', 'Hospitality'),
    ('Electricity', 'Utilities & Services'),
    ('Postal', 'Utilities & Services'),
    ('Security', 'Utilities & Services'),
    ('Cleaning', 'Utilities & Services'),
    ('Services', 'Utilities & Services'),
    ('Telecom', 'Telecom, Media & Culture'),
    ('Mobile', 'Telecom, Media & Culture'),
    ('Advertising', 'Telecom, Media & Culture'),
    ('Culture', 'Telecom, Media & Culture'),
    ('Agriculture', 'Agriculture'),
    ('Other', 'Other'),
    ('Religion', 'Other'),
    ('Not applicable', 'Not applicable');
GO

/* ---------- Dim_Customer: Who the applicant is: demographic profile. One row per distinct combination of the attributes below. ---------- */
CREATE TABLE warehouse.Dim_Customer (
    CustomerKey                  INT          NOT NULL CONSTRAINT PK_Dim_Customer PRIMARY KEY,
    Gender                       VARCHAR(10)  NOT NULL,
    AgeGroup                     VARCHAR(10)  NOT NULL,
    AgeGroupSort                 TINYINT      NOT NULL,
    FamilyStatus                 VARCHAR(30)  NOT NULL,
    ChildrenBand                 VARCHAR(10)  NOT NULL,
    ChildrenBandSort             TINYINT      NOT NULL,
    EducationLevel               VARCHAR(40)  NOT NULL,
    EducationSort                TINYINT      NOT NULL,
    CONSTRAINT UQ_Dim_Customer UNIQUE (Gender, AgeGroup, FamilyStatus, ChildrenBand, EducationLevel)
);
GO

/* ---------- Dim_Household: Where and how the applicant lives: housing, asset ownership and the rating of their region. ---------- */
CREATE TABLE warehouse.Dim_Household (
    HouseholdKey                 INT          NOT NULL CONSTRAINT PK_Dim_Household PRIMARY KEY,
    HousingType                  VARCHAR(30)  NOT NULL,
    OwnsCar                      VARCHAR(10)   NOT NULL,
    OwnsRealty                   VARCHAR(10)   NOT NULL,
    RegionRating                 TINYINT      NOT NULL,
    CONSTRAINT UQ_Dim_Household UNIQUE (HousingType, OwnsCar, OwnsRealty, RegionRating)
);
GO

/* ---------- Dim_Employment: What the applicant does: income source, occupation and length of employment. ---------- */
CREATE TABLE warehouse.Dim_Employment (
    EmploymentKey                INT          NOT NULL CONSTRAINT PK_Dim_Employment PRIMARY KEY,
    IncomeSource                 VARCHAR(30)  NOT NULL,
    IncomeSourceDetail           VARCHAR(30)  NOT NULL,
    OccupationType               VARCHAR(40)  NOT NULL,
    EmploymentTenureBand         VARCHAR(20)  NOT NULL,
    EmploymentTenureSort         TINYINT      NOT NULL,
    CONSTRAINT UQ_Dim_Employment UNIQUE (IncomeSource, IncomeSourceDetail, OccupationType, EmploymentTenureBand)
);
GO

/* ---------- Dim_Organization: The applicant's employer type, as a two-level hierarchy: Sector > Organization type (57 types grouped into 14 sectors). ---------- */
CREATE TABLE warehouse.Dim_Organization (
    OrganizationKey              INT          NOT NULL CONSTRAINT PK_Dim_Organization PRIMARY KEY,
    OrganizationType             VARCHAR(40)  NOT NULL,
    OrganizationSector           VARCHAR(40)  NOT NULL,
    CONSTRAINT UQ_Dim_Organization UNIQUE (OrganizationType, OrganizationSector)
);
GO

/* ---------- Dim_LoanProfile: What was asked for: contract type and how heavy the loan is relative to income. ---------- */
CREATE TABLE warehouse.Dim_LoanProfile (
    LoanProfileKey               INT          NOT NULL CONSTRAINT PK_Dim_LoanProfile PRIMARY KEY,
    ContractType                 VARCHAR(20)  NOT NULL,
    IncomeBand                   VARCHAR(20)  NOT NULL,
    IncomeBandSort               TINYINT      NOT NULL,
    CreditToIncomeBand           VARCHAR(15)  NOT NULL,
    CreditToIncomeSort           TINYINT      NOT NULL,
    AnnuityToIncomeBand          VARCHAR(15)  NOT NULL,
    AnnuityToIncomeSort          TINYINT      NOT NULL,
    CONSTRAINT UQ_Dim_LoanProfile UNIQUE (ContractType, IncomeBand, CreditToIncomeBand, AnnuityToIncomeBand)
);
GO

/* ---------- Dim_RiskAndHistory: The applicant's borrowing track record: external bureau credit, earlier Home Credit applications and installment behaviour (a junk / profile dimension). ---------- */
CREATE TABLE warehouse.Dim_RiskAndHistory (
    RiskHistoryKey               INT          NOT NULL CONSTRAINT PK_Dim_RiskAndHistory PRIMARY KEY,
    BureauHistoryGroup           VARCHAR(40)  NOT NULL,
    BureauHistorySort            TINYINT      NOT NULL,
    BureauOverdueGroup           VARCHAR(30)  NOT NULL,
    BureauOverdueSort            TINYINT      NOT NULL,
    PreviousRefusalGroup         VARCHAR(40)  NOT NULL,
    PreviousRefusalSort          TINYINT      NOT NULL,
    InstallmentLateGroup         VARCHAR(40)  NOT NULL,
    InstallmentLateSort          TINYINT      NOT NULL,
    InstallmentSevereLateGroup   VARCHAR(40)  NOT NULL,
    InstallmentSevereLateSort    TINYINT      NOT NULL,
    InstallmentUnderpaidGroup    VARCHAR(40)  NOT NULL,
    InstallmentUnderpaidSort     TINYINT      NOT NULL,
    CONSTRAINT UQ_Dim_RiskAndHistory UNIQUE (BureauHistoryGroup, BureauOverdueGroup, PreviousRefusalGroup, InstallmentLateGroup, InstallmentSevereLateGroup, InstallmentUnderpaidGroup)
);
GO

/* ---------- Fact_LoanApplications: grain = one row per loan application ---------- */
CREATE TABLE warehouse.Fact_LoanApplications (
    ApplicationID                INT          NOT NULL CONSTRAINT PK_Fact_LoanApplications PRIMARY KEY,   -- degenerate dimension = SK_ID_CURR
    CustomerKey                  INT          NOT NULL,
    HouseholdKey                 INT          NOT NULL,
    EmploymentKey                INT          NOT NULL,
    OrganizationKey              INT          NOT NULL,
    LoanProfileKey               INT          NOT NULL,
    RiskHistoryKey               INT          NOT NULL,
    PaymentDifficultyFlag        TINYINT       NOT NULL,
    IncomeAmount                 DECIMAL(18,2) NOT NULL,
    IncomeAmountCapped           DECIMAL(18,2) NOT NULL,
    LoanAmount                   DECIMAL(18,2) NOT NULL,
    AnnuityAmount                DECIMAL(18,2) NULL,
    GoodsPriceAmount             DECIMAL(18,2) NULL,
    BureauTotalCredit            DECIMAL(18,2) NULL,
    BureauTotalDebt              DECIMAL(18,2) NULL,
    CreditToIncomeRatio          DECIMAL(10,2) NULL,
    AnnuityToIncomeRatio         DECIMAL(10,4) NULL,
    EstimatedLoanTermMonths      DECIMAL(10,1) NULL,
    BureauDebtToCreditRatio      DECIMAL(10,3) NULL,
    PreviousRefusalRate          DECIMAL(5,3)  NULL,
    InstallmentLateRate          DECIMAL(6,3)  NULL,
    ExtSource1                   FLOAT         NULL,
    ExtSource2                   FLOAT         NULL,
    ExtSource3                   FLOAT         NULL,
    AgeYears                     DECIMAL(5,1)  NOT NULL,
    YearsEmployed                DECIMAL(5,1)  NULL,
    OwnCarAge                    FLOAT         NULL,
    ChildrenCount                SMALLINT      NULL,
    FamilyMemberCount            SMALLINT      NULL,
    BureauCreditCount            INT           NOT NULL,
    BureauActiveCount            INT           NOT NULL,
    BureauClosedCount            INT           NOT NULL,
    BureauOverdueCreditCount     INT           NOT NULL,
    BureauMaxDaysOverdue         INT           NULL,
    PreviousApplicationCount     INT           NOT NULL,
    PreviousApprovedCount        INT           NOT NULL,
    PreviousRefusedCount         INT           NOT NULL,
    PreviousDaysSinceLastDecision INT           NULL,
    InstallmentCount             INT           NOT NULL,
    InstallmentLateCount         INT           NOT NULL,
    InstallmentLate30PlusCount   INT           NOT NULL,
    InstallmentUnderpaidCount    INT           NOT NULL,
    InstallmentNoPaymentCount    INT           NOT NULL,
    InstallmentAvgDaysLate       DECIMAL(8,2)  NULL,
    InstallmentMaxDaysLate       INT           NULL,
    BureauEnquiriesLastYear      SMALLINT      NULL,
    SocialCircleDefaults30       SMALLINT      NULL,
    SocialCircleDefaults60       SMALLINT      NULL,
    IncomeOutlierFlag            TINYINT       NOT NULL,
    BureauDebtExceedsCreditFlag  TINYINT       NOT NULL,
    CONSTRAINT FK_Fact_LoanApplications_Dim_Customer FOREIGN KEY (CustomerKey) REFERENCES warehouse.Dim_Customer (CustomerKey),
    CONSTRAINT FK_Fact_LoanApplications_Dim_Household FOREIGN KEY (HouseholdKey) REFERENCES warehouse.Dim_Household (HouseholdKey),
    CONSTRAINT FK_Fact_LoanApplications_Dim_Employment FOREIGN KEY (EmploymentKey) REFERENCES warehouse.Dim_Employment (EmploymentKey),
    CONSTRAINT FK_Fact_LoanApplications_Dim_Organization FOREIGN KEY (OrganizationKey) REFERENCES warehouse.Dim_Organization (OrganizationKey),
    CONSTRAINT FK_Fact_LoanApplications_Dim_LoanProfile FOREIGN KEY (LoanProfileKey) REFERENCES warehouse.Dim_LoanProfile (LoanProfileKey),
    CONSTRAINT FK_Fact_LoanApplications_Dim_RiskAndHistory FOREIGN KEY (RiskHistoryKey) REFERENCES warehouse.Dim_RiskAndHistory (RiskHistoryKey),
    CONSTRAINT CK_Fact_DifficultyFlag CHECK (PaymentDifficultyFlag IN (0, 1)),
    CONSTRAINT CK_Fact_OutlierFlag CHECK (IncomeOutlierFlag IN (0, 1)),
    CONSTRAINT CK_Fact_DebtFlag CHECK (BureauDebtExceedsCreditFlag IN (0, 1))
);
GO

/* ---------- indexes on the foreign keys (join performance) ---------- */
CREATE INDEX IX_Fact_LoanApplications_CustomerKey ON warehouse.Fact_LoanApplications (CustomerKey);
CREATE INDEX IX_Fact_LoanApplications_HouseholdKey ON warehouse.Fact_LoanApplications (HouseholdKey);
CREATE INDEX IX_Fact_LoanApplications_EmploymentKey ON warehouse.Fact_LoanApplications (EmploymentKey);
CREATE INDEX IX_Fact_LoanApplications_OrganizationKey ON warehouse.Fact_LoanApplications (OrganizationKey);
CREATE INDEX IX_Fact_LoanApplications_LoanProfileKey ON warehouse.Fact_LoanApplications (LoanProfileKey);
CREATE INDEX IX_Fact_LoanApplications_RiskHistoryKey ON warehouse.Fact_LoanApplications (RiskHistoryKey);
GO
