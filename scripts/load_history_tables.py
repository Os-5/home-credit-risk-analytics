"""
Load bureau.csv and previous_application.csv into SQL Server staging tables.

Run from the project root AFTER running sql/03_create_history_staging.sql:
    python scripts/load_history_tables.py
"""
from pathlib import Path
import urllib.parse
import pandas as pd
from sqlalchemy import create_engine, text

# ---------- CONFIG: use the SAME values as in load_application_train.py ----------
SERVER = "G3EEFAR"
DRIVER = "ODBC Driver 17 for SQL Server"
# --------------------------------------------------------------------------------

DATABASE = "HomeCreditDB"
RAW = Path("data/raw")
CHUNK = 50_000

JOBS = [
    {
        "csv": "bureau.csv",
        "table": "bureau",
        "cols": ["SK_ID_BUREAU", "SK_ID_CURR", "CREDIT_ACTIVE", "CREDIT_CURRENCY",
                 "DAYS_CREDIT", "CREDIT_DAY_OVERDUE", "AMT_CREDIT_SUM",
                 "AMT_CREDIT_SUM_DEBT", "AMT_CREDIT_SUM_OVERDUE", "CREDIT_TYPE",
                 "CNT_CREDIT_PROLONG"],
        "int_cols": ["DAYS_CREDIT", "CREDIT_DAY_OVERDUE", "CNT_CREDIT_PROLONG"],
    },
    {
        "csv": "previous_application.csv",
        "table": "previous_application",
        "cols": ["SK_ID_PREV", "SK_ID_CURR", "NAME_CONTRACT_TYPE", "AMT_ANNUITY",
                 "AMT_APPLICATION", "AMT_CREDIT", "NAME_CONTRACT_STATUS",
                 "DAYS_DECISION", "CODE_REJECT_REASON", "NAME_CLIENT_TYPE",
                 "NAME_PORTFOLIO", "CNT_PAYMENT"],
        "int_cols": ["DAYS_DECISION", "CNT_PAYMENT"],
    },
]


def pick_encoding(path):
    for enc in ("utf-8", "cp1252"):
        try:
            with open(path, encoding=enc) as f:
                for _ in f:
                    pass
            return enc
        except UnicodeDecodeError:
            continue
    return "latin1"


def load(engine, job):
    path = RAW / job["csv"]
    enc = pick_encoding(path)
    print(f"\n{job['csv']}  (encoding: {enc})")

    with engine.begin() as conn:
        conn.execute(text(f"TRUNCATE TABLE stg.{job['table']}"))

    total = 0
    for i, chunk in enumerate(
        pd.read_csv(path, usecols=job["cols"], chunksize=CHUNK, encoding=enc), start=1
    ):
        chunk = chunk[job["cols"]].copy()
        for col in job["int_cols"]:
            chunk[col] = chunk[col].astype("Int64")
        chunk.to_sql(job["table"], engine, schema="stg", if_exists="append",
                     index=False, chunksize=CHUNK)
        total += len(chunk)
        if i % 5 == 0:
            print(f"  loaded {total:,} rows...")

    with engine.connect() as conn:
        n = conn.execute(text(f"SELECT COUNT(*) FROM stg.{job['table']}")).scalar()
    print(f"  DONE. Rows in SQL Server: {n:,}  (CSV rows read: {total:,})")


def main():
    conn_str = (
        f"DRIVER={{{DRIVER}}};SERVER={SERVER};DATABASE={DATABASE};"
        "Trusted_Connection=yes;TrustServerCertificate=yes;"
    )
    engine = create_engine(
        "mssql+pyodbc:///?odbc_connect=" + urllib.parse.quote_plus(conn_str),
        fast_executemany=True,
    )
    for job in JOBS:
        load(engine, job)


if __name__ == "__main__":
    main()
