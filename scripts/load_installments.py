"""
Load installments_payments.csv (~13.6M rows) into stg.installments_payments.

Run from the project root AFTER sql/05_create_installments_staging.sql:
    python scripts/load_installments.py

Expect roughly 10-30 minutes depending on your machine. It is safe to re-run
(the table is truncated first). Keep the laptop plugged in and awake.
"""
from pathlib import Path
import time
import urllib.parse
import pandas as pd
from sqlalchemy import create_engine, text

# ---------- CONFIG: use the SAME values as the other loaders ----------
SERVER = "G3EEFAR"
DRIVER = "ODBC Driver 17 for SQL Server"
# ----------------------------------------------------------------------

DATABASE = "HomeCreditDB"
CSV_FILE = Path("data/raw/installments_payments.csv")
CHUNK = 250_000

COLS = ["SK_ID_PREV", "SK_ID_CURR", "NUM_INSTALMENT_VERSION",
        "NUM_INSTALMENT_NUMBER", "DAYS_INSTALMENT", "DAYS_ENTRY_PAYMENT",
        "AMT_INSTALMENT", "AMT_PAYMENT"]
INT_COLS = ["NUM_INSTALMENT_VERSION", "NUM_INSTALMENT_NUMBER",
            "DAYS_INSTALMENT", "DAYS_ENTRY_PAYMENT"]   # float in the CSV because of NaN


def main():
    conn_str = (
        f"DRIVER={{{DRIVER}}};SERVER={SERVER};DATABASE={DATABASE};"
        "Trusted_Connection=yes;TrustServerCertificate=yes;"
    )
    engine = create_engine(
        "mssql+pyodbc:///?odbc_connect=" + urllib.parse.quote_plus(conn_str),
        fast_executemany=True,
    )

    with engine.begin() as conn:
        conn.execute(text("TRUNCATE TABLE stg.installments_payments"))

    start, total = time.time(), 0
    for i, chunk in enumerate(
        pd.read_csv(CSV_FILE, usecols=COLS, chunksize=CHUNK), start=1
    ):
        chunk = chunk[COLS].copy()
        for col in INT_COLS:
            chunk[col] = chunk[col].round().astype("Int64")
        chunk.to_sql("installments_payments", engine, schema="stg",
                     if_exists="append", index=False, chunksize=100_000)
        total += len(chunk)
        print(f"Chunk {i}: {total:,} rows loaded  ({(time.time()-start)/60:.1f} min)")

    with engine.connect() as conn:
        n = conn.execute(text("SELECT COUNT(*) FROM stg.installments_payments")).scalar()
    print(f"\nDone. Rows in SQL Server: {n:,}   Rows read from CSV: {total:,}")
    print("These two numbers must be identical.")


if __name__ == "__main__":
    main()
