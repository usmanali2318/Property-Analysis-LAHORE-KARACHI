# exports the tables the dashboard needs from postgres to data/processed/*.csv
# run once after the sql files, again whenever the sql changes
import os
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.engine import URL

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "processed"
load_dotenv(ROOT / ".env")

QUERIES = {
    "overview_stats": """
        SELECT COUNT(*) AS records,
               COUNT(DISTINCT (city, property_type, area, area_size)) AS series,
               MAX(month) AS latest_month
        FROM monthly_clean
    """,
    "home_trend": """
        SELECT city, month, price_pkr
        FROM monthly_clean
        WHERE property_type = 'houses' AND area = '(citywide)' AND area_size = '5 Marla'
        ORDER BY month
    """,
    "city_size_comparison": """
        SELECT * FROM city_size_comparison ORDER BY property_type, size_marla
    """,
    "citywide_change": """
        SELECT property_type, city, area_size, size_marla,
               chg_6m_pct, chg_12m_pct, chg_24m_pct, pattern
        FROM price_summary
        LEFT JOIN trend_check USING (city, property_type, area, area_size)
        WHERE area = '(citywide)'
        ORDER BY property_type, size_marla, city
    """,
    "top_gainers": """
        SELECT city, property_type, area, area_size, months, n_outliers, months_up, chg_12m_pct
        FROM price_summary
        JOIN series_method USING (city, property_type, area, area_size)
        JOIN trend_check USING (city, property_type, area, area_size)
        WHERE area <> '(citywide)' AND pattern = 'sustained'
        ORDER BY chg_12m_pct DESC
        LIMIT 10
    """,
    "city_gap_monthly": """
        SELECT property_type, area_size, size_marla, month, lahore_to_karachi_ratio
        FROM city_gap_monthly
        ORDER BY property_type, size_marla, month
    """,
    "citywide_status": """
        SELECT property_type, city, area_size, size_marla, is_excluded,
               MIN(month) AS first_month, COUNT(*) AS months
        FROM price_index_monthly
        WHERE area = '(citywide)'
        GROUP BY property_type, city, area_size, size_marla, is_excluded
        ORDER BY property_type, size_marla, city
    """,
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    engine = create_engine(URL.create(
        "postgresql+psycopg2",
        username=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "5432")),
        database=os.getenv("DB_NAME", "zameen_analysis"),
    ))
    for name, sql in QUERIES.items():
        table = pd.read_sql(sql, engine)
        table.to_csv(OUT / f"{name}.csv", index=False)
        print(f"{name}: {len(table)} rows")


if __name__ == "__main__":
    main()
