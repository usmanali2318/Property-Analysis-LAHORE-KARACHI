-- deliverable 1 part 1: cleaning
-- works on non-excluded rows only, raw table stays untouched


-- step 1: clean working table
-- same data minus excluded rows, plus mom_pct (month over month change per series)
-- is_outlier starts false, gets filled in 03_outliers.sql
-- expect 62,493 rows
DROP TABLE IF EXISTS monthly_clean;
CREATE TABLE monthly_clean AS
SELECT city, property_type, area, area_size, size_marla, month,
       price_pkr, price_per_sqft_pkr, index_value,
       price_pkr::numeric / NULLIF(LAG(price_pkr) OVER w, 0) - 1 AS mom_pct,
       FALSE AS is_outlier
FROM price_index_monthly
WHERE NOT is_excluded
WINDOW w AS (PARTITION BY city, property_type, area, area_size ORDER BY month);


-- step 2: null / zero / negative check, expect 0 everywhere
SELECT COUNT(*) FILTER (WHERE price_pkr IS NULL OR price_pkr <= 0)                     AS bad_price,
       COUNT(*) FILTER (WHERE price_per_sqft_pkr IS NULL OR price_per_sqft_pkr <= 0)   AS bad_sqft_price,
       COUNT(*) FILTER (WHERE index_value IS NULL OR index_value <= 0)                 AS bad_index
FROM monthly_clean;


-- step 3: duplicate check on the series key + month, expect 0 rows
SELECT city, property_type, area, area_size, month, COUNT(*)
FROM monthly_clean
GROUP BY city, property_type, area, area_size, month
HAVING COUNT(*) > 1;


-- step 4: price vs price per sqft sanity check
-- price / price_per_sqft gives an implied area. it doesnt match the plot size label
-- (comes out around 60 to 80% of it) so i check it stays stable over time instead
-- cv = std dev / mean of the implied area, high cv means price and sqft price disagree
-- look at the top rows and pick a cutoff
SELECT city, property_type, area, area_size,
       COUNT(*) AS months,
       ROUND(AVG(price_pkr::numeric / price_per_sqft_pkr)) AS avg_implied_sqft,
       ROUND(STDDEV(price_pkr::numeric / price_per_sqft_pkr)
             / AVG(price_pkr::numeric / price_per_sqft_pkr), 3) AS cv
FROM monthly_clean
GROUP BY city, property_type, area, area_size
ORDER BY cv DESC
LIMIT 15;


-- step 5: short series (under 12 months), these stay out of outlier stats and cagr
-- expect 5: naya nazimabad block m, askari 12, central park block bb, nsit city, scheme 33 sector 34-a
SELECT city, property_type, area, area_size, COUNT(*) AS months
FROM monthly_clean
GROUP BY city, property_type, area, area_size
HAVING COUNT(*) < 12
ORDER BY months;


/*
worked on a clean copy (monthly_clean) with the 30 excluded series left out, raw table untouched. 62,493 rows

added mom_pct, the month over month price change per series, since price trends up for 15 years and raw price cant show whats unusual

checks: no nulls, zeros or negatives in price, price per sqft or index, no duplicate keys

price / price_per_sqft doesnt match the plot size label (comes out around 60 to 80% of it even in real series) so i checked it stays stable within a series instead. 
cv was 0.000 everywhere (only naya nazimabad block m had none, it has 1 month). so price per sqft is just price divided by a fixed area per series, it passes the check but adds no independent info. within a series price and price per sqft grow at the same rate

5 series are under 12 months (naya nazimabad block m, askari 12, central park block bb, nsit city, scheme 33 sector 34-a) so they stay out of outlier stats and cagr
*/
