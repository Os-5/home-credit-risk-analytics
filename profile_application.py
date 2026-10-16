
from pathlib import Path
import pandas as pd

DATA_FILE = Path("data/raw/application_train.csv")
REPORT_DIR = Path("reports")
REPORT_DIR.mkdir(exist_ok=True)

if not DATA_FILE.exists():
    raise FileNotFoundError(f"File not found: {DATA_FILE.resolve()}")

# Read the main application dataset.
try:
    df = pd.read_csv(DATA_FILE, encoding="utf-8")
except UnicodeDecodeError:
    df = pd.read_csv(DATA_FILE, encoding="cp1252")

print("=" * 65)
print("APPLICATION TRAIN - DATA QUALITY PROFILE")
print("=" * 65)

# 1. Dataset size
print(f"\nRows: {len(df):,}")
print(f"Columns: {len(df.columns):,}")
print(f"Memory usage: {df.memory_usage(deep=True).sum() / 1024**2:.2f} MB")

# 2. Duplicate checks
print("\n--- DUPLICATES ---")
print("Duplicate full rows:", df.duplicated().sum())
print("Duplicate SK_ID_CURR values:", df["SK_ID_CURR"].duplicated().sum())
print("Missing SK_ID_CURR values:", df["SK_ID_CURR"].isna().sum())

# 3. Target distribution
print("\n--- TARGET DISTRIBUTION ---")
target_counts = df["TARGET"].value_counts(dropna=False).sort_index()
print(target_counts)

print("\nTarget percentages:")
print((df["TARGET"].value_counts(normalize=True, dropna=False) * 100).sort_index().round(2))

# 4. Missing values
print("\n--- MISSING VALUES ---")
missing = pd.DataFrame({
    "Missing_Count": df.isna().sum(),
    "Missing_Percent": (df.isna().mean() * 100).round(2)
})
missing = missing[missing["Missing_Count"] > 0]
missing = missing.sort_values("Missing_Percent", ascending=False)

print(f"Columns with missing values: {len(missing)}")
print(missing.head(20).to_string())

# 5. Key business columns
key_columns = [
    "AMT_INCOME_TOTAL",
    "AMT_CREDIT",
    "AMT_ANNUITY",
    "AMT_GOODS_PRICE",
    "DAYS_BIRTH",
    "DAYS_EMPLOYED",
    "CNT_CHILDREN",
    "CNT_FAM_MEMBERS",
]

print("\n--- KEY NUMERIC COLUMNS ---")
print(df[key_columns].describe().round(2).to_string())

# 6. Save reports
missing.to_csv(REPORT_DIR / "application_missing_values.csv")

target_counts.rename_axis("TARGET").reset_index(
    name="Application_Count"
).to_csv(REPORT_DIR / "target_distribution.csv", index=False)

df[key_columns].describe().T.to_csv(
    REPORT_DIR / "application_numeric_summary.csv"
)

print("\nReports saved in:", REPORT_DIR.resolve())
print("Profiling complete.")