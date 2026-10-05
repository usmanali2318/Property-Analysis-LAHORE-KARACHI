-- deliverable 2: lahore vs karachi city size comparison
-- needs monthly_clean with the k = 3 outlier flags from 03_outliers.sql
-- compares citywide series that exist in BOTH cities (houses 3, 5, 7, 10 marla, 1, 2 kanal / flats 3, 5, 7, 10 marla)
-- karachi only 1 and 2 kanal flats have no lahore pair so the join drops them


-- step 1: build the comparison table
-- uses the last 12 months only (prices trend up for 15 years so an all history average is meaningless)
-- flagged outlier months are left out
-- same stat on both sides (avg and median both shown, ranking uses median) because comparing a
-- mean in one city to a median in the other wouldnt be fair
-- pct_diff = (lahore - karachi) / karachi * 100, positive means lahore is pricier
-- price per sqft is there so "3 marla" not being the same size everywhere doesnt fool us
DROP TABLE IF EXISTS city_size_comparison;
CREATE TABLE city_size_comparison AS
WITH base AS (
    SELECT city, property_type, area_size, size_marla, price_pkr, price_per_sqft_pkr
    FROM monthly_clean
    WHERE area = '(citywide)'
      AND NOT is_outlier
      AND month >= (SELECT MAX(month) - INTERVAL '11 months' FROM monthly_clean)
),
per_city AS (
    SELECT city, property_type, area_size, size_marla,
           COUNT(*) AS months,
           AVG(price_pkr) AS avg_price,
           (percentile_cont(0.5) WITHIN GROUP (ORDER BY price_pkr))::numeric AS med_price,
           AVG(price_per_sqft_pkr) AS avg_psf,
           (percentile_cont(0.5) WITHIN GROUP (ORDER BY price_per_sqft_pkr))::numeric AS med_psf
    FROM base
    GROUP BY city, property_type, area_size, size_marla
)
SELECT l.property_type, l.area_size, l.size_marla,
       l.months AS lhr_months, k.months AS khi_months,
       ROUND(l.avg_price) AS lhr_avg_price, ROUND(k.avg_price) AS khi_avg_price,
       ROUND(l.med_price) AS lhr_med_price, ROUND(k.med_price) AS khi_med_price,
       ROUND(l.med_psf)   AS lhr_med_psf,   ROUND(k.med_psf)   AS khi_med_psf,
       ROUND((l.med_price - k.med_price) * 100.0 / k.med_price, 1) AS pct_diff_price,
       ROUND((l.med_psf   - k.med_psf)   * 100.0 / k.med_psf,   1) AS pct_diff_psf
FROM per_city l
JOIN per_city k
  ON l.property_type = k.property_type AND l.area_size = k.area_size
WHERE l.city = 'Lahore' AND k.city = 'Karachi';


-- step 2: coverage check, how many of the 12 months each city has per size
-- expect close to 12 everywhere, low numbers mean the outlier flags ate that size
SELECT property_type, area_size, lhr_months, khi_months
FROM city_size_comparison
ORDER BY property_type, size_marla;


-- step 3: ranked by abs % difference in median price, biggest gap first
-- this is how we find which sizes really diverge and which dont
SELECT RANK() OVER (ORDER BY ABS(pct_diff_price) DESC) AS rank,
       property_type, area_size,
       lhr_med_price, khi_med_price, pct_diff_price
FROM city_size_comparison
ORDER BY rank;


-- step 4: same ranking on price per sqft
-- if a size ranks high on price but low on sqft price, the gap is mostly about size not value
SELECT RANK() OVER (ORDER BY ABS(pct_diff_psf) DESC) AS rank,
       property_type, area_size,
       lhr_med_psf, khi_med_psf, pct_diff_psf
FROM city_size_comparison
ORDER BY rank;


-- step 5: houses vs flats side by side per size, to see where the gap is in each type
SELECT area_size,
       MAX(pct_diff_price) FILTER (WHERE property_type = 'houses') AS houses_pct_diff,
       MAX(pct_diff_price) FILTER (WHERE property_type = 'flats')  AS flats_pct_diff
FROM city_size_comparison
GROUP BY area_size, size_marla
ORDER BY size_marla;
