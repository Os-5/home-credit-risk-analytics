"""
Load application_train.csv into SQL Server (stg.application_train).

Setup (once):
    python -m pip install pandas sqlalchemy pyodbc
    Make sure "ODBC Driver 17 (or 18) for SQL Server" is installed.

Run from the project root:
    python scripts/load_application_train.py
"""
from pathlib import Path
import urllib.parse
import pandas as pd
from sqlalchemy import create_engine, text

# ---------- CONFIG: edit these two lines if needed ----------
SERVER = "G3EEFAR"      # e.g. "localhost", r".\SQLEXPRESS", or "DESKTOP-XXXX"
DRIVER = "ODBC Driver 17 for SQL Server"   # or "ODBC Driver 18 for SQL Server"
# -------------------------------------------------------------

DATABASE = "HomeCreditDB"
CSV_FILE = Path("data/raw/application_train.csv")
TABLE, SCHEMA = "application_train", "stg"
CHUNK = 20_000

KEEP = [
    "SK_ID_CURR", "TARGET", "NAME_CONTRACT_TYPE", "CODE_GENDER", "FLAG_OWN_CAR",
    "FLAG_OWN_REALTY", "CNT_CHILDREN", "AMT_INCOME_TOTAL", "AMT_CREDIT",
    "AMT_ANNUITY", "AMT_GOODS_PRICE", "NAME_TYPE_SUITE", "NAME_INCOME_TYPE",
    "NAME_EDUCATION_TYPE", "NAME_FAMILY_STATUS", "NAME_HOUSING_TYPE",
    "REGION_POPULATION_RELATIVE", "DAYS_BIRTH", "DAYS_EMPLOYED",
    "DAYS_REGISTRATION", "DAYS_ID_PUBLISH", "OWN_CAR_AGE", "OCCUPATION_TYPE",
    "CNT_FAM_MEMBERS", "REGION_RATING_CLIENT", "REGION_RATING_CLIENT_W_CITY",
    "WEEKDAY_APPR_PROCESS_START", "HOUR_APPR_PROCESS_START", "ORGANIZATION_TYPE",
    "EXT_SOURCE_1", "EXT_SOURCE_2", "EXT_SOURCE_3",
    "OBS_30_CNT_SOCIAL_CIRCLE", "DEF_30_CNT_SOCIAL_CIRCLE",
    "OBS_60_CNT_SOCIAL_CIRCLE", "DEF_60_CNT_SOCIAL_CIRCLE",
    "DAYS_LAST_PHONE_CHANGE",
    "AMT_REQ_CREDIT_BUREAU_HOUR", "AMT_REQ_CREDIT_BUREAU_DAY",
    "AMT_REQ_CREDIT_BUREAU_WEEK", "AMT_REQ_CREDIT_BUREAU_MON",
    "AMT_REQ_CREDIT_BUREAU_QRT", "AMT_REQ_CREDIT_BUREAU_YEAR",
]

# Columns that are whole numbers in SQL but read as float by pandas because of NaN
INT_COLS = [
    "CNT_CHILDREN", "CNT_FAM_MEMBERS", "DAYS_BIRTH", "DAYS_EMPLOYED",
    "DAYS_ID_PUBLISH", "REGION_RATING_CLIENT", "REGION_RATING_CLIENT_W_CITY",
    "HOUR_APPR_PROCESS_START", "OBS_30_CNT_SOCIAL_CIRCLE",
    "DEF_30_CNT_SOCIAL_CIRCLE", "OBS_60_CNT_SOCIAL_CIRCLE",
    "DEF_60_CNT_SOCIAL_CIRCLE", "AMT_REQ_CREDIT_BUREAU_HOUR",
    "AMT_REQ_CREDIT_BUREAU_DAY", "AMT_REQ_CREDIT_BUREAU_WEEK",
    "AMT_REQ_CREDIT_BUREAU_MON", "AMT_REQ_CREDIT_BUREAU_QRT",
    "AMT_REQ_CREDIT_BUREAU_YEAR",
]


def read_chunks():
    for enc in ("utf-8", "cp1252"):
        try:
            # Probe the whole file once so we know which encoding works
            with open(CSV_FILE, encoding=enc) as f:
                for _ in f:
                    pass
            print(f"Encoding OK: {enc}")
            return pd.read_csv(CSV_FILE, usecols=KEEP, chunksize=CHUNK, encoding=enc)
        except UnicodeDecodeError:
            print(f"{enc} failed, trying next...")
    raise RuntimeError("Could not decode the CSV with utf-8 or cp1252.")


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
        conn.execute(text(f"TRUNCATE TABLE {SCHEMA}.{TABLE}"))  # safe to re-run

    total = 0
    for i, chunk in enumerate(read_chunks(), start=1):
        chunk = chunk[KEEP].copy()
        for col in INT_COLS:
            chunk[col] = chunk[col].astype("Int64")
        chunk.to_sql(TABLE, engine, schema=SCHEMA, if_exists="append",
                     index=False, chunksize=CHUNK)
        total += len(chunk)
        print(f"Chunk {i}: loaded {total:,} rows")

    with engine.connect() as conn:
        n = conn.execute(text(f"SELECT COUNT(*) FROM {SCHEMA}.{TABLE}")).scalar()
    print(f"\nDone. Rows in SQL Server: {n:,}  (expected 307,511)")


if __name__ == "__main__":
    main()
