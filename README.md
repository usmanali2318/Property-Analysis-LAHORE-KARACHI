# Pakistan Property Price Analysis

Lahore vs Karachi house and flat prices, built on Zameen.com's official Price Index
(monthly, January 2011 to August 2026). The data is cleaned and analysed in PostgreSQL,
and the results are shown in a Streamlit dashboard with written takeaways next to each chart.

## What I found

- **Houses:** Karachi is more expensive than Lahore at every plot size, from 10% at 7 Marla up to 87% at 3 Marla (last 12 months, median prices).
- **Flats:** the other way round at small sizes. Lahore is more expensive at 3, 5 and 7 Marla, while 10 Marla is close to the same price.
- **Recent growth:** over 24 months Karachi houses rose 32 to 58% against 11 to 15% in Lahore.
- **Over time:** for houses, Lahore kept closing the gap until about 2022 to 2024, then Karachi pulled ahead again. For flats, Lahore overtook Karachi at 3, 5 and 7 Marla between 2021 and 2023.
- All changes are in nominal rupees, with no inflation adjustment.

The full written takeaways are in `analysis/takeaways/`.

## Data notes

- Zameen has no data for some plot sizes and repeats one fake price history across them (8, 12 and 14 Marla, 4, 8, 10 and 20 Kanal). I detected these by identical price ranges and confirmed it by comparing every month. Lahore 1 and 2 Kanal flats were also dropped as implausible.
- In total 30 of 592 price histories were flagged with `is_excluded`, not deleted.
- Unusual months are flagged per history (IQR on monthly change, with a 10% minimum move) and left out of the comparisons.
- Out of scope: macro and policy data, and the new housing scheme analysis.

## Project structure

```
zameen-price-analysis/
├── README.md
├── requirements.txt
├── .env.example                 <- copy to .env and fill in your Postgres details
├── .streamlit/
│   └── config.toml              <- green and white theme
├── scraper/
│   └── index_scraper.py
├── data/
│   ├── raw/                     <- zameen_index_monthly.csv
│   └── processed/               <- CSVs the dashboard reads (made by the export script)
├── sql/
│   ├── 01_schema.sql            <- table, load, size_marla, exclusions
│   ├── 02_cleaning.sql
│   ├── 03_outliers.sql
│   ├── 04_city_size_comparison.sql
│   ├── 05_summary_and_change.sql
│   └── 06_convergence_divergence.sql
├── scripts/
│   └── export_tables.py         <- Postgres tables to data/processed/*.csv
├── analysis/
│   └── takeaways/               <- written conclusions, one file per section
└── dashboard/
    ├── app.py
    ├── db.py
    └── ui.py
```

## How to run

1. Install: `python -m pip install -r requirements.txt`
2. Get the data: run `scraper/index_scraper.py`, or use the CSV already in `data/raw/`.
3. In PostgreSQL create a database called `zameen_analysis`, then run the files in `sql/` in order. The CSV is loaded in `01_schema.sql` (pgAdmin: right-click the table, Import/Export Data).
4. Copy `.env.example` to `.env` and set `DB_PASSWORD` (and the other values if yours differ).
5. Export the tables: `python scripts/export_tables.py`
6. Start the dashboard from the repo root: `python -m streamlit run dashboard/app.py`

Once `data/processed/` exists, the dashboard needs no database, so you can commit that folder and deploy it as is. Rerun step 5 if the SQL changes.

## Stack

PostgreSQL, Python (pandas, SQLAlchemy), Streamlit, Plotly.
