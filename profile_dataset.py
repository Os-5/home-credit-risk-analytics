
from pathlib import Path
import pandas as pd

DATA_DIR = Path("data/raw")

if not DATA_DIR.exists():
    raise FileNotFoundError(
        f"Dataset folder not found: {DATA_DIR.resolve()}"
    )

csv_files = sorted(DATA_DIR.glob("*.csv"))

if not csv_files:
    raise FileNotFoundError(
        f"No CSV files found in {DATA_DIR.resolve()}"
    )

print("=" * 75)
print("HOME CREDIT DEFAULT RISK - DATA INVENTORY")
print("=" * 75)

inventory = []

for file in csv_files:
    size_mb = file.stat().st_size / (1024 ** 2)

    # Read only the header first to avoid loading large files.
    try:
        columns = pd.read_csv(
            file,
            nrows=0,
            encoding="utf-8"
        ).columns.tolist()
    except UnicodeDecodeError:
        print(f"UTF-8 decoding failed for {file.name}; trying cp1252...")
        columns = pd.read_csv(
            file,
            nrows=0,
            encoding="cp1252"
        ).columns.tolist()

    inventory.append({
        "File": file.name,
        "Size_MB": round(size_mb, 2),
        "Column_Count": len(columns),
        "Columns": columns,
    })

    print(f"\nFile: {file.name}")
    print(f"Size: {size_mb:.2f} MB")
    print(f"Columns: {len(columns)}")
    print("Column names:", ", ".join(columns))

inventory_df = pd.DataFrame(inventory)

print("\n" + "=" * 75)
print("INVENTORY SUMMARY")
print("=" * 75)

print(
    inventory_df[["File", "Size_MB", "Column_Count"]]
    .to_string(index=False)
)

Path("reports").mkdir(exist_ok=True)

inventory_df.drop(columns=["Columns"]).to_csv(
    "reports/data_inventory.csv", index=False
)

print("\nSaved inventory to reports/data_inventory.csv")