-- deliverable 3: summary table and recent price change
-- built from monthly_clean, replaces the old zameen summary csv


-- step 1: latest month per series
-- everything should end on 2026-08-01, anything else stopped early
SELECT last_month, COUNT(*) AS series
FROM (SELECT MAX(month) AS last_month
      FROM monthly_clean
      GROUP BY city, property_type, area, area_size) series_end
GROUP BY last_month
ORDER BY last_month DESC;


-- step 2: summary table, one row per series
-- price now and 6, 12, 24 months before the latest month
-- FILTER picks one month out of each series, NULL = series is younger than that
-- price_pkr used, index_value is rounded to whole numbers
-- step 3: % change columns, 100.0 forces decimal division on the bigint prices
DROP TABLE IF EXISTS price_summary;
CREATE TABLE price_summary AS
WITH latest AS (
    SELECT MAX(month) AS latest_month
    FROM monthly_clean
),
series_prices AS (
    SELECT city, property_type, area, area_size, size_marla,
           MIN(month) AS first_month,
           COUNT(*)   AS months,
           MAX(price_pkr) FILTER (WHERE month = latest_month)                       AS price_now,
           MAX(price_pkr) FILTER (WHERE month = latest_month - INTERVAL '6 months')  AS price_6m,
           MAX(price_pkr) FILTER (WHERE month = latest_month - INTERVAL '12 months') AS price_12m,
           MAX(price_pkr) FILTER (WHERE month = latest_month - INTERVAL '24 months') AS price_24m
    FROM monthly_clean
    CROSS JOIN latest
    GROUP BY city, property_type, area, area_size, size_marla
)
SELECT series_prices.*,
       ROUND((price_now - price_6m)  * 100.0 / price_6m,  1) AS chg_6m_pct,
       ROUND((price_now - price_12m) * 100.0 / price_12m, 1) AS chg_12m_pct,
       ROUND((price_now - price_24m) * 100.0 / price_24m, 1) AS chg_24m_pct
FROM series_prices;


-- step 4: self check on price_summary
-- rebuild the same prices by counting rows back from the latest month instead of date maths
-- row 1 = latest, 7 = 6 months back, 13 = 12 back, 25 = 24 back
-- expect 562 series and 0 mismatches in every column
WITH ranked_back AS (
    SELECT city, property_type, area, area_size, price_pkr,
           ROW_NUMBER() OVER (PARTITION BY city, property_type, area, area_size
                              ORDER BY month DESC) AS rows_back
    FROM monthly_clean
),
rebuilt AS (
    SELECT city, property_type, area, area_size,
           MAX(price_pkr) FILTER (WHERE rows_back = 1)  AS rebuilt_now,
           MAX(price_pkr) FILTER (WHERE rows_back = 7)  AS rebuilt_6m,
           MAX(price_pkr) FILTER (WHERE rows_back = 13) AS rebuilt_12m,
           MAX(price_pkr) FILTER (WHERE rows_back = 25) AS rebuilt_24m
    FROM ranked_back
    GROUP BY city, property_type, area, area_size
)
SELECT COUNT(*) AS series_checked,
       COUNT(*) FILTER (WHERE price_summary.price_now IS DISTINCT FROM rebuilt.rebuilt_now)  AS mismatch_now,
       COUNT(*) FILTER (WHERE price_summary.price_6m  IS DISTINCT FROM rebuilt.rebuilt_6m)   AS mismatch_6m,
       COUNT(*) FILTER (WHERE price_summary.price_12m IS DISTINCT FROM rebuilt.rebuilt_12m)  AS mismatch_12m,
       COUNT(*) FILTER (WHERE price_summary.price_24m IS DISTINCT FROM rebuilt.rebuilt_24m)  AS mismatch_24m
FROM price_summary
JOIN rebuilt USING (city, property_type, area, area_size);


-- step 5: biggest single month move per citywide series, last 12 months
-- flagged outlier months excluded, they would win every time
WITH recent_moves AS (
    SELECT city, property_type, area, area_size, month, mom_pct,
           ROW_NUMBER() OVER (PARTITION BY city, property_type, area, area_size
                              ORDER BY ABS(mom_pct) DESC) AS move_rank
    FROM monthly_clean
    WHERE NOT is_outlier
      AND mom_pct IS NOT NULL
      AND month > (SELECT MAX(month) - INTERVAL '12 months' FROM monthly_clean)
)
SELECT property_type, city, area_size,
       month AS biggest_move_month,
       ROUND(mom_pct * 100, 1) AS mom_pct
FROM recent_moves
WHERE move_rank = 1
  AND area = '(citywide)'
ORDER BY property_type, area_size, city;


-- step 6: spike or sustained, last 12 months
-- sustained = 8+ of 12 months up and the biggest up month is under half of the 12m change
-- no growth = 12m change is 0 or below, anything else = spike driven
-- flagged months stay in on purpose, a single huge jump is what spike driven should catch
-- needs 12 monthly changes, so series under 13 months of history drop out
-- chg_12m_pct is not kept in this table, it already lives in price_summary and would be ambiguous in the joins below
DROP TABLE IF EXISTS trend_check;
CREATE TABLE trend_check AS
SELECT city, property_type, area, area_size,
       COUNT(*) FILTER (WHERE mom_pct > 0) AS months_up,
       ROUND(MAX(mom_pct) * 100, 1)        AS biggest_up_pct,
       CASE WHEN chg_12m_pct <= 0 THEN 'no growth'
            WHEN COUNT(*) FILTER (WHERE mom_pct > 0) >= 8
             AND MAX(mom_pct) * 100 < 0.5 * chg_12m_pct THEN 'sustained'
            ELSE 'spike driven' END AS pattern
FROM monthly_clean
JOIN price_summary USING (city, property_type, area, area_size)
WHERE mom_pct IS NOT NULL
  AND month > (SELECT MAX(month) - INTERVAL '12 months' FROM monthly_clean)
GROUP BY city, property_type, area, area_size, chg_12m_pct
HAVING COUNT(*) = 12;


-- step 7a: citywide changes with momentum and pattern
-- speeding up = last 6 months make up more than half of the 12m change
SELECT property_type, city, area_size,
       chg_6m_pct, chg_12m_pct, chg_24m_pct,
       CASE WHEN chg_12m_pct <= 0 THEN 'n/a'
            WHEN chg_6m_pct > chg_12m_pct / 2 THEN 'speeding up'
            ELSE 'slowing' END AS momentum,
       pattern
FROM price_summary
LEFT JOIN trend_check USING (city, property_type, area, area_size)
WHERE area = '(citywide)'
ORDER BY property_type, size_marla, city;


-- step 7b: top 10 per area gainers over 12 months
-- months and flagged months shown to spot thin series, switch DESC to ASC for the bottom 10
SELECT city, property_type, area, area_size,
       months, n_outliers, chg_12m_pct, pattern
FROM price_summary
JOIN series_method USING (city, property_type, area, area_size)
LEFT JOIN trend_check USING (city, property_type, area, area_size)
WHERE area <> '(citywide)'
  AND chg_12m_pct IS NOT NULL
ORDER BY chg_12m_pct DESC
LIMIT 10;


-- step 7c: top 10 per area gainers over 12 months, sustained ones only
-- the plain top 10 in 7b is all spike driven series carrying flagged months, not real appreciation
-- switch DESC to ASC for the bottom 10
SELECT city, property_type, area, area_size,
       months, n_outliers, months_up, chg_12m_pct
FROM price_summary
JOIN series_method USING (city, property_type, area, area_size)
JOIN trend_check USING (city, property_type, area, area_size)
WHERE area <> '(citywide)'
  AND pattern = 'sustained'
ORDER BY chg_12m_pct DESC
LIMIT 10;


-- step 8: series that stop before the latest month
-- price_now is NULL for these, so all their change columns are NULL
-- expect 17 (16 ending 2026-05, 1 ending 2026-07)
SELECT city, property_type, area, area_size,
       MAX(month) AS last_month, COUNT(*) AS months
FROM monthly_clean
GROUP BY city, property_type, area, area_size
HAVING MAX(month) < (SELECT MAX(month) FROM monthly_clean)
ORDER BY last_month, city, property_type, area;


-- step 9: every mismatch from the step 4 self check should be one of those 17
-- date maths and row counting only disagree when a series stops early
-- expect 0 rows
WITH ranked_back AS (
    SELECT city, property_type, area, area_size, price_pkr,
           ROW_NUMBER() OVER (PARTITION BY city, property_type, area, area_size
                              ORDER BY month DESC) AS rows_back
    FROM monthly_clean
),
rebuilt AS (
    SELECT city, property_type, area, area_size,
           MAX(price_pkr) FILTER (WHERE rows_back = 1)  AS rebuilt_now,
           MAX(price_pkr) FILTER (WHERE rows_back = 7)  AS rebuilt_6m,
           MAX(price_pkr) FILTER (WHERE rows_back = 13) AS rebuilt_12m,
           MAX(price_pkr) FILTER (WHERE rows_back = 25) AS rebuilt_24m
    FROM ranked_back
    GROUP BY city, property_type, area, area_size
)
SELECT city, property_type, area, area_size, last_month_in_data
FROM price_summary
JOIN rebuilt USING (city, property_type, area, area_size)
JOIN (SELECT city, property_type, area, area_size, MAX(month) AS last_month_in_data
      FROM monthly_clean
      GROUP BY city, property_type, area, area_size) series_end
  USING (city, property_type, area, area_size)
WHERE (price_summary.price_now IS DISTINCT FROM rebuilt.rebuilt_now
    OR price_summary.price_6m  IS DISTINCT FROM rebuilt.rebuilt_6m
    OR price_summary.price_12m IS DISTINCT FROM rebuilt.rebuilt_12m
    OR price_summary.price_24m IS DISTINCT FROM rebuilt.rebuilt_24m)
  AND last_month_in_data = (SELECT MAX(month) FROM monthly_clean);

/*

I made a summary table from the monthly data to understand the trend better. It has the price now (August 2026) and the price 6, 12 and 24 months before, for every history, and the percentage change for each period. 17 area histories stop before August 2026 (16 end in May 2026 and 1 in July 2026). None of them are citywide, so I left them out of the recent change numbers.

For houses, Karachi grew faster than Lahore in every size. In the last 12 months Karachi houses are up 10 to 22% and Lahore houses are up 6 to 11%. In 24 months it is 32 to 58% for Karachi and 11 to 15% for Lahore. So the gap we saw in the price comparison is getting bigger, because Karachi houses are going away from Lahore. The growth in both cities is steady, most months are going up and no single month is doing all the work. Only Karachi 3 Marla houses is driven by jumps.

Flats are more mixed. Karachi 5 Marla flats grew 11% in one year and Lahore grew 6%. Karachi 7 Marla flats grew 3% while Lahore went down 2.5%. So at these sizes Karachi is coming close to the Lahore premium. At 3 Marla it is opposite, Lahore flats grew 3.7% and Karachi went down 1.3%. Most flats are labelled jump driven, but this mostly means the prices move up and down a lot. When the total growth is small, one month of 4 or 5% is already more than half of it.

The biggest single month moves in the last 12 months are small, between 1 and 9%, and there is no common month for all sizes. I only see two small hints. Karachi flats 1 Kanal and 3 Marla and houses 2 Kanal all had their biggest move as a fall in December 2025. Some Lahore houses had their biggest move in September 2025 and January 2026. The samples are small, so I take this only as a hint.

The top area gainers, like Scheme 33 Sector 19-A houses (+189%), Scheme 33 Sector 32 flats (+170%) and New Lahore City flats (+127%), are all jump driven and have flagged months. So I do not count them as real price growth. The more reliable gainers, where growth was steady and most months went up, grew 30 to 43% in 12 months. 8 of the top 10 are in Karachi and 5 of them are DHA phases (Phase 4, 5, 7 and 7 Extension). These have long histories and almost no flagged months. The top ones in Lahore are Central Park Block E houses (+43%) and Bahria Orchard Phase 4 flats (+31%). Central Park Block E and Gulistan-e-Jauhar Block 3-A have a few flagged months, so these two are less sure.

All changes are in rupees and not adjusted for inflation, so the real growth is lower.

*/