from pathlib import Path

import pandas as pd
import streamlit as st

ROOT = Path(__file__).resolve().parent.parent
TAKEAWAYS = ROOT / "analysis" / "takeaways"
DATA = ROOT / "data" / "processed"

# chart colours, green and dark grey to match the green and white theme
CITY_COLORS = {"Lahore": "#10b981", "Karachi": "#064e3b"}
SIZE_COLORS = ["#064e3b", "#10b981", "#0f766e", "#34d399", "#14532d", "#2dd4bf"]


@st.cache_data
def load(name):
    # tables exported from postgres by scripts/export_tables.py
    path = DATA / f"{name}.csv"
    if not path.exists():
        st.error(f"missing data/processed/{name}.csv, run scripts/export_tables.py first")
        st.stop()
    return pd.read_csv(path)


def show_takeaway(filename):
    # shows the written takeaway from analysis/takeaways/, every line break becomes a paragraph
    path = TAKEAWAYS / filename
    if path.exists():
        text = path.read_text(encoding="utf-8").strip()
        st.markdown(text.replace("\n", "\n\n"))
    else:
        st.info(f"takeaway not written yet: analysis/takeaways/{filename}")
