-- deliverable 4: lahore vs karachi gap over time
-- citywide series that exist in both cities, one row per size and month
-- months where only one city has data are dropped by the join
-- flagged outlier months are left out (only 3 citywide ones, so almost no effect)


-- step 1: monthly gap table
-- ratio above 1 means lahore is pricier, below 1 karachi is pricier
-- gap_pct = pricier minus cheaper over cheaper, same as the pricier_by_pct in deliverable 2
DROP TABLE IF EXISTS city_gap_monthly;
CREATE TABLE city_gap_monthly AS
WITH lahore AS (
    SELECT property_type, area_size, size_marla, month,
           price_pkr AS lahore_price
    FROM monthly_clean
    WHERE city = 'Lahore'
      AND area = '(citywide)'
      AND NOT is_outlier
),
karachi AS (
    SELECT property_type, area_size, month,
           price_pkr AS karachi_price
    FROM monthly_clean
    WHERE city = 'Karachi'
      AND area = '(citywide)'
      AND NOT is_outlier
)
SELECT property_type, area_size, size_marla, month,
       lahore_price, karachi_price,
       ROUND(lahore_price::numeric / karachi_price, 3) AS lahore_to_karachi_ratio,
       CASE WHEN lahore_price >= karachi_price THEN 'Lahore' ELSE 'Karachi' END AS pricier_city,
       ROUND((GREATEST(lahore_price, karachi_price) - LEAST(lahore_price, karachi_price)) * 100.0
             / LEAST(lahore_price, karachi_price), 1) AS gap_pct
FROM lahore
JOIN karachi USING (property_type, area_size, month);


-- step 2: how many months each pair overlaps
-- expect 10 pairs, flats start later than houses
SELECT property_type, area_size,
       MIN(month) AS first_overlap,
       MAX(month) AS last_overlap,
       COUNT(*)   AS months
FROM city_gap_monthly
GROUP BY property_type, area_size, size_marla
ORDER BY property_type, size_marla;


-- step 3: average ratio every two years
-- 1.00 = same price, above 1 lahore pricier, below 1 karachi pricier
-- NULL = the pair had no data that year
SELECT property_type, area_size,
       ROUND(AVG(lahore_to_karachi_ratio) FILTER (WHERE EXTRACT(YEAR FROM month) = 2012), 2) AS y2012,
       ROUND(AVG(lahore_to_karachi_ratio) FILTER (WHERE EXTRACT(YEAR FROM month) = 2014), 2) AS y2014,
       ROUND(AVG(lahore_to_karachi_ratio) FILTER (WHERE EXTRACT(YEAR FROM month) = 2016), 2) AS y2016,
       ROUND(AVG(lahore_to_karachi_ratio) FILTER (WHERE EXTRACT(YEAR FROM month) = 2018), 2) AS y2018,
       ROUND(AVG(lahore_to_karachi_ratio) FILTER (WHERE EXTRACT(YEAR FROM month) = 2020), 2) AS y2020,
       ROUND(AVG(lahore_to_karachi_ratio) FILTER (WHERE EXTRACT(YEAR FROM month) = 2022), 2) AS y2022,
       ROUND(AVG(lahore_to_karachi_ratio) FILTER (WHERE EXTRACT(YEAR FROM month) = 2024), 2) AS y2024,
       ROUND(AVG(lahore_to_karachi_ratio) FILTER (WHERE EXTRACT(YEAR FROM month) = 2026), 2) AS y2026
FROM city_gap_monthly
GROUP BY property_type, area_size, size_marla
ORDER BY property_type, size_marla;


-- step 4: widening, narrowing or stable
-- compares the average gap in the first 12 overlap months with the last 12 months
-- more than 5 points up = widening, more than 5 down = narrowing, else stable (5 is a dial)
-- gap_pct has no sign, so a pair that swapped places can look stable or widening here
-- swapped_places flags those, read it together with step 3
WITH numbered AS (
    SELECT property_type, area_size, size_marla, gap_pct, pricier_city, month,
           ROW_NUMBER() OVER (PARTITION BY property_type, area_size ORDER BY month)      AS months_from_start,
           ROW_NUMBER() OVER (PARTITION BY property_type, area_size ORDER BY month DESC) AS months_from_end
    FROM city_gap_monthly
),
start_vs_now AS (
    SELECT property_type, area_size, size_marla,
           ROUND(AVG(gap_pct) FILTER (WHERE months_from_start <= 12), 1) AS gap_first_12m,
           ROUND(AVG(gap_pct) FILTER (WHERE months_from_end   <= 12), 1) AS gap_last_12m,
           (ARRAY_AGG(pricier_city ORDER BY month))[1]      AS pricier_at_start,
           (ARRAY_AGG(pricier_city ORDER BY month DESC))[1] AS pricier_now
    FROM numbered
    GROUP BY property_type, area_size, size_marla
)
SELECT property_type, area_size,
       gap_first_12m, gap_last_12m,
       gap_last_12m - gap_first_12m AS change_in_gap,
       CASE WHEN gap_last_12m - gap_first_12m >  5 THEN 'widening'
            WHEN gap_last_12m - gap_first_12m < -5 THEN 'narrowing'
            ELSE 'stable' END AS trend,
       pricier_at_start, pricier_now,
       CASE WHEN pricier_at_start <> pricier_now THEN 'yes' ELSE 'no' END AS swapped_places
FROM start_vs_now
ORDER BY property_type, size_marla;


-- step 5: since when
-- 12 month rolling average of the gap (smooths the month to month noise)
-- smallest and largest gap month per pair, if the smallest is far back and the gap has grown since, it has been widening since then
WITH rolling AS (
    SELECT property_type, area_size, size_marla, month,
           AVG(gap_pct) OVER recent_year AS rolling_gap,
           COUNT(*)     OVER recent_year AS months_in_window
    FROM city_gap_monthly
    WINDOW recent_year AS (PARTITION BY property_type, area_size
                           ORDER BY month ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
),
ranked AS (
    SELECT property_type, area_size, size_marla, month, rolling_gap,
           ROW_NUMBER() OVER (PARTITION BY property_type, area_size ORDER BY rolling_gap ASC)  AS smallest_rank,
           ROW_NUMBER() OVER (PARTITION BY property_type, area_size ORDER BY rolling_gap DESC) AS largest_rank,
           ROW_NUMBER() OVER (PARTITION BY property_type, area_size ORDER BY month DESC)       AS latest_rank
    FROM rolling
    WHERE months_in_window = 12
)
SELECT property_type, area_size,
       MAX(month)                      FILTER (WHERE smallest_rank = 1) AS smallest_gap_month,
       ROUND(MAX(rolling_gap)          FILTER (WHERE smallest_rank = 1), 1) AS smallest_gap_pct,
       MAX(month)                      FILTER (WHERE largest_rank = 1)  AS largest_gap_month,
       ROUND(MAX(rolling_gap)          FILTER (WHERE largest_rank = 1), 1)  AS largest_gap_pct,
       ROUND(MAX(rolling_gap)          FILTER (WHERE latest_rank = 1), 1)   AS gap_now_pct
FROM ranked
GROUP BY property_type, area_size, size_marla
ORDER BY property_type, size_marla;


-- step 6: months where the pricier city switched
-- pairs sitting near the same price can flip a lot from small moves, so count them but dont over read
WITH flips AS (
    SELECT property_type, area_size, size_marla, month, pricier_city,
           LAG(pricier_city) OVER (PARTITION BY property_type, area_size ORDER BY month) AS previous_pricier
    FROM city_gap_monthly
)
SELECT property_type, area_size,
       COUNT(*)   AS times_switched,
       MIN(month) AS first_switch,
       MAX(month) AS last_switch
FROM flips
WHERE previous_pricier IS NOT NULL
  AND pricier_city <> previous_pricier
GROUP BY property_type, area_size, size_marla
ORDER BY property_type, size_marla;

/*

I looked at the Lahore to Karachi price ratio every month for the 10 sizes that exist in both cities, from 2011 to August 2026. A ratio of 1 means the same price, above 1 means Lahore is more expensive and below 1 means Karachi is more expensive.

For houses, Lahore was catching up with Karachi for a long time and then Karachi moved away again. In 2011 Karachi 10 Marla houses were almost 3 times the Lahore price (gap 183%), and by 2024 the two were almost the same. The same direction for 7 Marla (gap 69% to 9.5%), 1 Kanal (51% to 36%) and 2 Kanal (33% to 22%). For most sizes the gap was smallest between 2022 and 2024: 2 Kanal in October 2022, 7 Marla in March 2023, 5 Marla in August 2023, 1 Kanal in December 2023 and 10 Marla in June 2024. Lahore was even the more expensive city for houses 5, 7 and 10 Marla for some time, but Karachi took it back in the first half of 2025. Since the smallest point the gap is opening again: 2 Kanal from 1.1% to 21.8%, 1 Kanal from 10.5% to 36.2% and 5 Marla from 2.9% to 16.5%. This agrees with deliverable 3, where Karachi houses grew 32 to 58% in 24 months and Lahore 11 to 15%.

Houses 3 Marla is different. Lahore was more expensive from 2015 to 2023, then Karachi became more expensive in January 2024 and now the gap is 84%, the biggest in the whole history. Karachi 3 Marla houses was also jump driven in deliverable 3, so I take this one with care.

Flats go the other way. Karachi flats were more expensive until about 2021 to 2023 and now Lahore is more expensive at 3, 5 and 7 Marla. For 3 Marla flats Karachi was 21% higher at the start, the two crossed in 2023 and now Lahore is 60% higher, the biggest gap in the history. Flats 7 Marla crossed a few times, the last in November 2024, and Lahore is 27% higher now. Flats 5 Marla crossed in November 2022 and Lahore is 19% higher. Flats 10 Marla is the only pair that really converged. It also swapped places but the other way: Lahore was 25% higher at the start (ratio 1.28 in 2012) and Karachi is 7.8% higher now. It is near the same price since 2022 (smallest gap 1.9% in January 2023) and it switched the more expensive city 7 times, so it moves around the same price. Houses 2 Kanal also switched 10 times between October 2021 and April 2024 for the same reason, so I do not read much into those switches.

So in the long run the gap was closing for most sizes, but the turning point is around 2023 to 2024. Since then the houses are diverging again with Karachi going up, and the small flats are diverging in favor of Lahore.

One note: the first and last 12 months comparison only looks at the size of the gap and not the direction, so I checked it with a swapped places column. All four flats pairs swapped places and none of the houses did, so for flats 5 and 7 Marla the stable and widening labels really mean the two cities changed places.

*/