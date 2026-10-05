from pathlib import Path

import pandas as pd
import plotly.express as px
import streamlit as st

import ui
from db import CITY_COLORS, SIZE_COLORS, load, show_takeaway

st.set_page_config(page_title="PakProp Index", page_icon=str(Path(__file__).parent / "assets" / "favicon.png"), layout="wide")
ui.inject_css()

stats = load("overview_stats").iloc[0]
latest = pd.to_datetime(stats["latest_month"])
ui.header(f"DATA TO {latest:%b %Y}".upper())

tab_home, tab_compare, tab_change, tab_gap, tab_notes = st.tabs([
    ":material/home: Home", ":material/compare_arrows: Compare",
    ":material/trending_up: Recent change", ":material/show_chart: Convergence",
    ":material/fact_check: Data notes"])

# ---------------------------------------------------------------- home
with tab_home:
    ui.hero("PAKISTAN REAL ESTATE",
            "Lahore or Karachi: where are property prices really moving?",
            "Fifteen years of monthly prices from Zameen.com's official Price Index, "
            "for houses and flats in Lahore and Karachi. Prices in PKR, plot sizes in Marla and Kanal.",
            "BY SYED USMAN ALI")
    ui.metric_cards([
        ("RECORDS", f"{int(stats['records']):,}", "monthly price records used"),
        ("HISTORIES", f"{int(stats['series']):,}", "price histories after cleaning"),
        ("CITIES", "2", "Lahore, Karachi"),
        ("LATEST MONTH", f"{latest:%b %Y}", "Jan 2011 to now"),
    ])

    ui.section("5 MARLA HOUSE PRICE OVER TIME")
    trend = load("home_trend")
    trend["month"] = pd.to_datetime(trend["month"])
    trend["PKR Lakh"] = trend["price_pkr"].astype(float) / 100000
    with st.container(key="card_home_trend"):
        ui.show(px.line(trend, x="month", y="PKR Lakh", color="city", color_discrete_map=CITY_COLORS,
                        labels={"month": "", "city": ""}),
                fmt=",.1f", suffix=" Lakh", date=True)

    ui.section("HOW IT WORKS")
    ui.steps([
        ("Collect", "Monthly price index history from Zameen.com for Lahore and Karachi, houses and flats."),
        ("Clean", "Fake placeholder series are set aside and unusual months are flagged."),
        ("Compare", "Price gaps by plot size, recent change and how the gap moved over time."),
        ("Read", "Every tab has the chart with my written takeaway below it."),
    ])

# ------------------------------------------------------------- compare
with tab_compare:
    ui.section("LAHORE VS KARACHI BY PLOT SIZE")
    comparison = load("city_size_comparison")
    with st.container(key="card_compare"):
        col_type, col_measure = st.columns(2)
        property_type = col_type.radio("Property type", ["houses", "flats"], horizontal=True, key="cmp_type")
        measure = col_measure.radio("Measure", ["Median price", "Median price per sq ft"],
                                    horizontal=True, key="cmp_measure")
        if measure == "Median price":
            lahore_col, karachi_col = "lhr_med_price", "khi_med_price"
        else:
            lahore_col, karachi_col = "lhr_med_psf", "khi_med_psf"

        view = comparison[comparison["property_type"] == property_type].copy()
        view["Lahore"] = view[lahore_col].astype(float)
        view["Karachi"] = view[karachi_col].astype(float)
        higher = view[["Lahore", "Karachi"]].max(axis=1)
        lower = view[["Lahore", "Karachi"]].min(axis=1)
        view["pricier_city"] = view["Lahore"].ge(view["Karachi"]).map({True: "Lahore", False: "Karachi"})
        view["pricier_by_pct"] = ((higher - lower) * 100 / lower).round(1)

        by_city = view.melt(id_vars=["area_size"], value_vars=["Lahore", "Karachi"],
                            var_name="city", value_name="value")
        ui.show(px.bar(by_city, x="area_size", y="value", color="city", barmode="group",
                       color_discrete_map=CITY_COLORS,
                       category_orders={"area_size": view["area_size"].tolist()},
                       labels={"area_size": "Plot size", "value": measure}),
                fmt=",.0f", prefix="PKR ", suffix="" if measure == "Median price" else " / sq ft")
        st.dataframe(view[["area_size", "Lahore", "Karachi", "pricier_city", "pricier_by_pct"]],
                     hide_index=True, use_container_width=True)
        st.caption("Last 12 months, outlier months left out. pricier_by_pct is how much higher the pricier city is.")
    ui.section("MY TAKEAWAY")
    with st.container(key="card_compare_text"):
        show_takeaway("02_city_size_comparison.md")

# -------------------------------------------------------- recent change
with tab_change:
    ui.section("RECENT PRICE CHANGE")
    citywide = load("citywide_change")
    change_cols = ["chg_6m_pct", "chg_12m_pct", "chg_24m_pct"]
    citywide[change_cols] = citywide[change_cols].astype(float)
    with st.container(key="card_change"):
        col_type, col_period = st.columns(2)
        property_type = col_type.radio("Property type", ["houses", "flats"], horizontal=True, key="chg_type")
        period = col_period.radio("Period", ["6 months", "12 months", "24 months"],
                                  horizontal=True, index=1, key="chg_period")
        period_col = {"6 months": "chg_6m_pct", "12 months": "chg_12m_pct", "24 months": "chg_24m_pct"}[period]
        view = citywide[citywide["property_type"] == property_type]
        ui.show(px.bar(view, x="area_size", y=period_col, color="city", barmode="group",
                       color_discrete_map=CITY_COLORS,
                       category_orders={"area_size": view["area_size"].drop_duplicates().tolist()},
                       labels={"area_size": "Plot size", period_col: f"Price change over {period} (%)"}),
                fmt="+.1f", suffix="%")
        st.dataframe(view[["area_size", "city"] + change_cols + ["pattern"]],
                     hide_index=True, use_container_width=True)
        st.caption("Changes are in rupees, not adjusted for inflation. sustained = most months up, "
                   "jump driven = a few months did most of the work.")

    ui.section("TOP AREA GAINERS, STEADY GROWTH ONLY")
    gainers = load("top_gainers")
    with st.container(key="card_gainers"):
        st.dataframe(gainers, hide_index=True, use_container_width=True)
        st.caption("Jump driven areas are left out, their gains come from single months.")
    ui.section("MY TAKEAWAY")
    with st.container(key="card_change_text"):
        show_takeaway("03_summary_and_change.md")

# ---------------------------------------------------------- convergence
with tab_gap:
    ui.section("LAHORE VS KARACHI GAP OVER TIME")
    gap = load("city_gap_monthly")
    gap["month"] = pd.to_datetime(gap["month"])
    gap["lahore_to_karachi_ratio"] = gap["lahore_to_karachi_ratio"].astype(float)
    with st.container(key="card_gap"):
        property_type = st.radio("Property type", ["houses", "flats"], horizontal=True, key="gap_type")
        view = gap[gap["property_type"] == property_type]
        sizes = view["area_size"].drop_duplicates().tolist()
        chosen = st.multiselect("Plot sizes", sizes, default=sizes, key="gap_sizes")
        view = view[view["area_size"].isin(chosen)]
        fig = px.line(view, x="month", y="lahore_to_karachi_ratio", color="area_size",
                      color_discrete_sequence=SIZE_COLORS,
                      labels={"month": "", "lahore_to_karachi_ratio": "Lahore price / Karachi price"})
        fig.add_hline(y=1, line_dash="dash", annotation_text="same price")
        ui.show(fig, fmt=".2f", suffix="x", date=True)
        st.caption("Above 1: Lahore is more expensive. Below 1: Karachi is more expensive.")
    ui.section("MY TAKEAWAY")
    with st.container(key="card_gap_text"):
        show_takeaway("04_convergence.md")

# ---------------------------------------------------------------- notes
with tab_notes:
    ui.section("WHAT WAS LOADED AND SET ASIDE")
    with st.container(key="card_notes_load"):
        show_takeaway("00_data_load.md")
    ui.section("CITYWIDE HISTORIES, KEPT VS EXCLUDED")
    status = load("citywide_status")
    status["status"] = status["is_excluded"].map({True: "excluded", False: "kept"})
    with st.container(key="card_notes_table"):
        st.dataframe(status[["property_type", "city", "area_size", "status", "first_month", "months"]],
                     hide_index=True, use_container_width=True)
    ui.section("CLEANING AND UNUSUAL MONTHS")
    with st.container(key="card_notes_clean"):
        show_takeaway("01_cleaning_outliers.md")
