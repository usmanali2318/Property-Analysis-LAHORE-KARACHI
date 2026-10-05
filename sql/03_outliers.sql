-- deliverable 1 part 2: outliers
-- iqr on month over month change (mom_pct) per series, not on price level
-- price trends up for 15 years so a level based iqr would just flag recent years


-- step 1: iqr fences per series
-- needs 12+ monthly changes to be fair, shorter series get no fences
-- multiplier is 1.5, switch to 3 if too many months get flagged (see step 5)
DROP TABLE IF EXISTS series_stats;
CREATE TABLE series_stats AS
WITH q AS (
    SELECT city, property_type, area, area_size,
           COUNT(*) AS n_changes,
           percentile_cont(0.25) WITHIN GROUP (ORDER BY mom_pct) AS q1,
           percentile_cont(0.75) WITHIN GROUP (ORDER BY mom_pct) AS q3
    FROM monthly_clean
    WHERE mom_pct IS NOT NULL
    GROUP BY city, property_type, area, area_size
    HAVING COUNT(*) >= 12
)
SELECT *,
       q1 - 1.5 * (q3 - q1) AS lower_fence,
       q3 + 1.5 * (q3 - q1) AS upper_fence
FROM q;


-- step 2: flag the outlier months
UPDATE monthly_clean SET is_outlier = FALSE;

UPDATE monthly_clean m
SET is_outlier = TRUE
FROM series_stats s
WHERE m.city = s.city AND m.property_type = s.property_type
  AND m.area = s.area AND m.area_size = s.area_size
  AND m.mom_pct IS NOT NULL
  AND (m.mom_pct < s.lower_fence OR m.mom_pct > s.upper_fence);


-- step 3: decision per series, mean or median
-- outliers present -> median, none -> mean, no fences (too short) -> too_short
-- recorded per series not once globally
DROP TABLE IF EXISTS series_method;
CREATE TABLE series_method AS
SELECT m.city, m.property_type, m.area, m.area_size,
       COUNT(*) AS n_months,
       COUNT(*) FILTER (WHERE m.is_outlier) AS n_outliers,
       CASE WHEN s.city IS NULL THEN 'too_short'
            WHEN COUNT(*) FILTER (WHERE m.is_outlier) > 0 THEN 'median'
            ELSE 'mean' END AS method
FROM monthly_clean m
LEFT JOIN series_stats s
  ON m.city = s.city AND m.property_type = s.property_type
 AND m.area = s.area AND m.area_size = s.area_size
GROUP BY m.city, m.property_type, m.area, m.area_size, s.city;


-- step 4: summary of the decisions, how many series per method
SELECT method,
       COUNT(*) AS series,
       ROUND(AVG(n_outliers * 100.0 / n_months), 1) AS avg_pct_months_flagged
FROM series_method
GROUP BY method
ORDER BY method;


-- step 5: where are the flagged months, by property type and citywide vs per area
-- if median series have avg_pct_months_flagged above about 10 in step 4,
-- change 1.5 to 3 in step 1 and rerun steps 1 to 4
SELECT property_type,
       CASE WHEN area = '(citywide)' THEN 'citywide' ELSE 'per_area' END AS level,
       COUNT(*) FILTER (WHERE is_outlier) AS outlier_months,
       COUNT(*)                           AS months
FROM monthly_clean
GROUP BY 1, 2
ORDER BY 1, 2;


-- step 6: the 15 biggest flagged jumps, to eyeball whether theyre real moves or scrape errors
SELECT city, property_type, area, area_size, month,
       price_pkr, ROUND(mom_pct * 100, 1) AS mom_pct, is_outlier
FROM monthly_clean
WHERE is_outlier
ORDER BY ABS(mom_pct) DESC
LIMIT 15;


/*
flagged outliers with iqr on mom_pct per series (not on price level, since price trends up). 
fences are q1 - k x iqr and q3 + k x iqr. series need 12+ monthly changes to get fences

first pass with k = 1.5 flagged 10.9% of months (6,835 of 62,493), 11.9% on average per series, 
and put 543 of 562 series on median so it wasnt separating anything. switched to k = 3

[results with k = 3: % of months flagged, series per method, citywide vs per area split]

method per series: median if it has outliers, mean if none, too_short if no fences (5 series).
recorded per series in series_method not once globally

biggest flagged jumps are all per area series (specific blocks, sectors, phases), none citywide. jumps of 100 to 280% in a single month, 
e.g. north karachi sector 11-c/1 flats +278% in aug 2025. no real market quadruples in a month so these are most likely thin sample noise (few listings that month) not market events

flagged months get handled before any growth or cagr work, especially for new schemes in deliverable 5 where the early months are exactly when the sample is thinnest
*/