from pathlib import Path
import pandas as pd

FILE = Path("data/raw/application_train.csv")
try:
    df = pd.read_csv(FILE, encoding="utf-8")
except UnicodeDecodeError:
    df = pd.read_csv(FILE, encoding="cp1252")

print("\n--- 1. DAYS_EMPLOYED = 365243 ---")
mask = df["DAYS_EMPLOYED"] == 365243
print("Rows:", mask.sum(), f"({mask.mean()*100:.2f}%)")
print("Target rate (anomaly):", round(df.loc[mask, "TARGET"].mean()*100, 2), "%")
print("Target rate (others): ", round(df.loc[~mask, "TARGET"].mean()*100, 2), "%")
print(df.loc[mask, "NAME_INCOME_TYPE"].value_counts())

print("\n--- 2. INCOME OUTLIERS ---")
print(df["AMT_INCOME_TOTAL"].quantile([.5, .9, .99, .999, 1]))
print("Applications with income > 1M:", (df["AMT_INCOME_TOTAL"] > 1_000_000).sum())

print("\n--- 3. OWN_CAR_AGE vs FLAG_OWN_CAR ---")
print(pd.crosstab(df["FLAG_OWN_CAR"], df["OWN_CAR_AGE"].isna(),
                  rownames=["FLAG_OWN_CAR"], colnames=["OWN_CAR_AGE missing"]))

print("\n--- 4. AGE ---")
print((-df["DAYS_BIRTH"] / 365.25).describe().round(1))

print("\n--- 5. CATEGORICAL COLUMNS ---")
rows = []
for col in df.select_dtypes(include="object").columns:
    vc = df[col].value_counts(dropna=False)
    rows.append({"column": col, "unique": df[col].nunique(),
                 "missing": df[col].isna().sum(),
                 "top_values": "; ".join(f"{k}={v}" for k, v in vc.head(5).items())})
cats = pd.DataFrame(rows)
print(cats.to_string(index=False))

Path("reports").mkdir(exist_ok=True)
cats.to_csv("reports/application_categoricals.csv", index=False)
df.isna().sum().sort_values(ascending=False).rename("missing_count") \
  .to_frame().assign(missing_pct=lambda x: (x.missing_count/len(df)*100).round(2)) \
  .to_csv("reports/application_missing_values_full.csv")
print("\nSaved reports.")