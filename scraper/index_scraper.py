"""
Scraper for Zameen.com's official Real Estate Price Index
(https://www.zameen.com/index/), not the live listings pages.

Data source, for real this time
--------------------------------
Every index page is a Next.js app that embeds its full data as JSON in a
<script id="__NEXT_DATA__"> tag -- this is standard Next.js server-side
rendering, present in the plain HTML response, no browser/JS needed.
Inside it, under props.pageProps.initialState.legionApi.queries, there's a
"getIndexDetail(...)" entry with:
  - avg_price, avg_price_per_sqft, value (index) for the current month
  - six_months_ago / one_year_ago / two_year_ago, each with the same fields
  - index_values: the FULL monthly history back to the index's baseline
    (188 months / ~15.5 years for the sample checked), each with
    month_year, avg_price, avg_price_per_sqft, value
  - maximum.date: the baseline month the index (=100) is set from

This replaces two earlier, much shakier approaches: (1) plain requests
that never found the data because it was being looked for in the wrong
place, and (2) a Playwright/browser-rendering detour that turned out to be
unnecessary -- the data was server-rendered JSON all along, just not
inside a <table> or in the visible text where the earlier version looked
for it. Confirmed against an actual saved page (debug_first_page.html)
from a real run.

Practical effect: plain `requests` again (fast, no browser), and FULL
monthly history per area/size instead of the ~15-month window the old
table-scraping approach was limited to.

Two crawl passes
-----------------
1. City-wide size pages (.../index/buy/{type}/{City}-{id}/{size}/, e.g.
   lahore-1/10-marla/): the citywide average for that plot size, not tied
   to any one area. This is the direct source for "avg 3 Marla house
   price, Lahore vs Karachi" style comparisons. Rows from this pass are
   tagged area="(citywide)". Cheap: a fixed size list x cities x types.
2. Per-area (and per-area-size, where offered) crawl via the "Top Areas"
   and "different Area Sizes" tables, for the "which specific areas are
   the biggest gainers" angle. Note some larger umbrella areas (e.g. "DHA
   Defence") don't have their own size breakdown -- their "different Area
   Sizes" table actually lists sub-phases instead, since a plot-size
   comparison only makes sense one level down at the phase level. Their
   area_size values will reflect that (phase names, not plot sizes).
"""

import csv
import json
import re
import time
from datetime import datetime

import requests
from bs4 import BeautifulSoup
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept-Language": "en-US,en;q=0.9",
}

INDEX_BASE = "https://www.zameen.com/index/buy/"
PROPERTY_TYPES = ["houses", "flats"]

CITIES = [
    {"id": 1, "name": "Lahore"},
    {"id": 2, "name": "Karachi"},
]

# Zameen also publishes a direct city-wide page per plot size, e.g.
# .../index/buy/houses/lahore-1/10-marla/ -- the citywide average for that
# size, not tied to any one area. This is the most direct source for
# "avg 3 Marla house price in Lahore vs Karachi" style comparisons, and
# much cheaper than crawling every area. Not every size exists for every
# city/property_type combo (404s are skipped).
CITY_SIZES = (
    [f"{n}-marla" for n in (3, 5, 7, 8, 10, 12, 14)] +
    [f"{n}-kanal" for n in (1, 2, 4, 8, 10, 20)]
)


def make_session():
    session = requests.Session()
    session.headers.update(HEADERS)
    retries = Retry(total=5, backoff_factor=1.5,
                     status_forcelist=[403, 429, 500, 502, 503, 504])
    session.mount("https://", HTTPAdapter(max_retries=retries))
    return session


SESSION = make_session()


def find_table(soup, required_headers):
    """First <table> whose header row contains all required_headers.
    Checks <th> first, falls back to the first row's <td>."""
    for table in soup.find_all("table"):
        first_row = table.find("tr")
        if first_row is None:
            continue
        header_cells = first_row.find_all("th") or first_row.find_all("td")
        headers = [c.get_text(strip=True) for c in header_cells]
        if all(h in headers for h in required_headers):
            return table
    return None


def find_table_after_heading(soup, heading_substring):
    """First <table> that appears after a heading/text containing heading_substring."""
    node = soup.find(string=re.compile(heading_substring, re.I))
    if node is None:
        return None
    return node.find_next("table")


def extract_label_links(table):
    """[(label, href), ...] from a table's rows: first cell text + first link in the row."""
    out = []
    if table is None:
        return out
    for row in table.find_all("tr")[1:]:
        cells = row.find_all("td")
        if not cells:
            continue
        label = cells[0].get_text(strip=True)
        link = row.find("a", href=True)
        if label and link:
            out.append((label, link["href"]))
    return out


def get_city_areas(property_type, city_name, city_id):
    """[(area_name, area_url), ...] from the city page's Top Areas table."""
    url = f"{INDEX_BASE}{property_type}/{city_name}-{city_id}/"
    resp = SESSION.get(url, timeout=15)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")
    return extract_label_links(find_table(soup, ["Index"]))


def get_area_sizes(soup):
    """[(size_name, size_url), ...] from the area page's 'different Area Sizes' table."""
    return extract_label_links(find_table_after_heading(soup, "different Area Sizes"))


def extract_index_detail(soup):
    """Pull the getIndexDetail(...) query's `data` object out of __NEXT_DATA__."""
    script = soup.find("script", id="__NEXT_DATA__")
    if script is None or not script.string:
        return None
    try:
        data = json.loads(script.string)
    except json.JSONDecodeError:
        return None
    try:
        queries = data["props"]["pageProps"]["initialState"]["legionApi"]["queries"]
    except (KeyError, TypeError):
        return None
    for key, q in queries.items():
        if key.startswith("getIndexDetail("):
            return q.get("data")
    return None


def month_date_str(month_year_iso):
    """'2026-08-01T00:00:00.000+05:00' -> '2026-08-01'."""
    if not month_year_iso:
        return None
    try:
        return datetime.fromisoformat(month_year_iso).date().replace(day=1).isoformat()
    except ValueError:
        return month_year_iso[:7] + "-01"


def parse_index_detail(detail):
    """Monthly rows + summary dict straight from the JSON, no string parsing needed."""
    if not detail:
        return [], {}

    monthly_rows = []
    for item in (detail.get("index_values") or []):
        month = month_date_str(item.get("month_year"))
        if not month:
            continue
        monthly_rows.append({
            "month": month,
            "price_pkr": item.get("avg_price"),
            "price_per_sqft_pkr": item.get("avg_price_per_sqft"),
            "index": item.get("value"),
        })
    # index_values comes newest-first; store oldest-first for readability.
    monthly_rows.reverse()

    summary = {
        "current_price_pkr": detail.get("avg_price"),
        "current_price_per_sqft_pkr": detail.get("avg_price_per_sqft"),
        "current_index": detail.get("value"),
    }
    if monthly_rows:
        summary["current_month"] = monthly_rows[-1]["month"][:7]
    maximum = detail.get("maximum") or {}
    if maximum.get("date"):
        summary["index_baseline"] = maximum["date"]
    for key, field in (("6mo", "six_months_ago"), ("1yr", "one_year_ago"), ("2yr", "two_year_ago")):
        sub = detail.get(field) or {}
        if sub:
            summary[f"{key}_ago_price_pkr"] = sub.get("avg_price")
            summary[f"{key}_ago_price_per_sqft_pkr"] = sub.get("avg_price_per_sqft")
            summary[f"{key}_ago_index"] = sub.get("value")

    return monthly_rows, summary


def fetch_series(url):
    resp = SESSION.get(url, timeout=15)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")
    detail = extract_index_detail(soup)
    monthly_rows, summary = parse_index_detail(detail)
    return soup, monthly_rows, summary


def to_full_url(href):
    return href if href.startswith("http") else f"https://www.zameen.com{href}"


def main():
    monthly_out, summary_out = [], []

    # Pass 1: direct city-wide size pages -- the primary comparison unit
    # (e.g. "3 Marla houses, Lahore vs Karachi, citywide"). Cheap: a fixed
    # size list x 2 cities x 2 types, no area crawling.
    for property_type in PROPERTY_TYPES:
        for city in CITIES:
            for size_slug in CITY_SIZES:
                url = f"{INDEX_BASE}{property_type}/{city['name']}-{city['id']}/{size_slug}/"
                print(f"[{property_type}] {city['name']} citywide: {size_slug}")
                try:
                    _, monthly_rows, summary = fetch_series(url)
                except requests.exceptions.RequestException as e:
                    print(f"  skipped ({e})")
                    time.sleep(1)
                    continue
                time.sleep(1)
                if not monthly_rows and not summary:
                    # Size doesn't exist for this city/property_type.
                    continue
                size_label = size_slug.replace("-", " ").title()
                tag = dict(city=city["name"], property_type=property_type,
                           area="(citywide)", area_size=size_label)
                for row in monthly_rows:
                    monthly_out.append({**tag, **row})
                summary_out.append({**tag, **summary})

    # Pass 2: per-area (and per-area-size, where the site offers it) crawl,
    # for the "which specific areas are the biggest gainers" angle.
    for property_type in PROPERTY_TYPES:
        for city in CITIES:
            print(f"[{property_type}] City: {city['name']}")
            try:
                areas = get_city_areas(property_type, city["name"], city["id"])
            except requests.exceptions.RequestException as e:
                print(f"  skipped city ({e})")
                continue
            time.sleep(1)

            for area_name, area_url in areas:
                full_area_url = to_full_url(area_url)
                print(f"  {area_name}")

                try:
                    soup, monthly_rows, summary = fetch_series(full_area_url)
                except requests.exceptions.RequestException as e:
                    print(f"    skipped ({e})")
                    time.sleep(2)
                    continue
                time.sleep(1)

                tag = dict(city=city["name"], property_type=property_type,
                           area=area_name, area_size="All")
                for row in monthly_rows:
                    monthly_out.append({**tag, **row})
                summary_out.append({**tag, **summary})

                for size_name, size_url in get_area_sizes(soup):
                    full_size_url = to_full_url(size_url)
                    print(f"    {size_name}")
                    try:
                        _, size_monthly_rows, size_summary = fetch_series(full_size_url)
                    except requests.exceptions.RequestException as e:
                        print(f"      skipped ({e})")
                        time.sleep(2)
                        continue
                    time.sleep(1)

                    size_tag = dict(city=city["name"], property_type=property_type,
                                     area=area_name, area_size=size_name)
                    for row in size_monthly_rows:
                        monthly_out.append({**size_tag, **row})
                    summary_out.append({**size_tag, **size_summary})

    with open("zameen_index_monthly.csv", "w", newline="") as f:
        fieldnames = ["city", "property_type", "area", "area_size",
                      "month", "price_pkr", "price_per_sqft_pkr", "index"]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(monthly_out)

    with open("zameen_index_summary.csv", "w", newline="") as f:
        fieldnames = ["city", "property_type", "area", "area_size",
                      "current_month", "current_price_pkr", "current_price_per_sqft_pkr", "current_index",
                      "6mo_ago_price_pkr", "6mo_ago_price_per_sqft_pkr", "6mo_ago_index",
                      "1yr_ago_price_pkr", "1yr_ago_price_per_sqft_pkr", "1yr_ago_index",
                      "2yr_ago_price_pkr", "2yr_ago_price_per_sqft_pkr", "2yr_ago_index",
                      "index_baseline"]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(summary_out)

    print(f"Done. {len(monthly_out)} monthly rows, {len(summary_out)} area/size summaries.")


if __name__ == "__main__":
    main()
