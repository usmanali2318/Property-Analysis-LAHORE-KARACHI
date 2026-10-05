-- deliverable 0: data load
-- db: zameen_analysis, source: zameen_index_monthly.csv
-- run step 0 on the default postgres db, rest on zameen_analysis


-- step 0: make the db (run once on postgres)
-- CREATE DATABASE zameen_analysis;


-- step 1: main table, one row per series per month
-- pk also stops duplicates. renamed csv "index" to index_value (reserved word)
CREATE TABLE IF NOT EXISTS price_index_monthly (
    city               TEXT    NOT NULL,
    property_type      TEXT    NOT NULL,
    area               TEXT    NOT NULL,
    area_size          TEXT    NOT NULL,
    month              DATE    NOT NULL,
    price_pkr          BIGINT  NOT NULL,
    price_per_sqft_pkr INTEGER NOT NULL,
    index_value        NUMERIC NOT NULL,
    PRIMARY KEY (city, property_type, area, area_size, month)
);


-- step 2: load the csv (not sql, do it in pgadmin)
-- right click table > import/export data > import, csv, header on, delimiter ,
-- psql way: \copy price_index_monthly FROM 'path/to/file.csv' CSV HEADER


-- step 3: did everything load. expect 67973
SELECT COUNT(*) AS total_rows
FROM price_index_monthly;


-- step 4: date range. expect 2011-01-01 to 2026-08-01
SELECT MIN(month) AS first_month,
       MAX(month) AS last_month
FROM price_index_monthly;


-- step 5: rows per city and type
-- expect karachi flats 19177, karachi houses 19879, lahore flats 7047, lahore houses 21870
SELECT city, property_type, COUNT(*) AS rows
FROM price_index_monthly
GROUP BY city, property_type
ORDER BY city, property_type;


-- step 6: how many series (city + type + area + size). expect 592 (52 citywide, 540 per area)
SELECT COUNT(*) AS series,
       COUNT(*) FILTER (WHERE area = '(citywide)') AS citywide_series
FROM (SELECT DISTINCT city, property_type, area, area_size
      FROM price_index_monthly) t;


-- step 7: numeric plot size so sizes sort properly, 1 kanal = 20 marla
-- per area rows stay null since their area_size is "All" or a phase name
ALTER TABLE price_index_monthly ADD COLUMN IF NOT EXISTS size_marla NUMERIC;

UPDATE price_index_monthly
SET size_marla = CASE
    WHEN area_size ILIKE '% Marla' THEN split_part(area_size, ' ', 1)::NUMERIC
    WHEN area_size ILIKE '% Kanal' THEN split_part(area_size, ' ', 1)::NUMERIC * 20
END;


-- step 8: check the conversion. expect 13 sizes, 3 marla (3) up to 20 kanal (400)
SELECT area_size, size_marla, COUNT(*) AS rows
FROM price_index_monthly
WHERE size_marla IS NOT NULL
GROUP BY area_size, size_marla
ORDER BY size_marla;


-- step 9: exclusion flag. flagging not deleting so raw data stays
-- every query after this uses WHERE NOT is_excluded
ALTER TABLE price_index_monthly
    ADD COLUMN IF NOT EXISTS is_excluded BOOLEAN DEFAULT FALSE;


-- step 10: reset flags so the next steps can be rerun clean
UPDATE price_index_monthly SET is_excluded = FALSE;


-- step 11: flag the placeholder series
-- zameen returns one shared fake series for sizes it has no data for
-- found them by their identical min/max price instead of hardcoding sizes
-- houses: 11,899,277 to 67,462,081 / flats: 5,591,040 to 25,225,200
-- hits 8, 12, 14 marla and 4, 8, 10, 20 kanal in both cities
-- real ones (10 marla, 1 kanal, 2 kanal) stay. expect 28 series flagged
UPDATE price_index_monthly p
SET is_excluded = TRUE
FROM (
    SELECT city, property_type, area, area_size
    FROM price_index_monthly
    GROUP BY city, property_type, area, area_size
    HAVING (MIN(price_pkr) = 11899277 AND MAX(price_pkr) = 67462081)
        OR (MIN(price_pkr) = 5591040  AND MAX(price_pkr) = 25225200)
) bad
WHERE p.city = bad.city AND p.property_type = bad.property_type
  AND p.area = bad.area AND p.area_size = bad.area_size;


-- step 11b: also drop lahore 1 and 2 kanal flats
-- real series but broken, 1 kanal costs less than 3 marla and 2 kanal is in the billions
-- would mess up the city gap. expect 2 more series (216 rows)
UPDATE price_index_monthly
SET is_excluded = TRUE
WHERE property_type = 'flats'
  AND city = 'Lahore'
  AND area = '(citywide)'
  AND area_size IN ('1 Kanal', '2 Kanal');


-- step 12: check the exclusions
-- expect 30 excluded series (5,480 rows) and 562 kept (62,493 rows)
SELECT is_excluded,
       COUNT(DISTINCT (city, property_type, area, area_size)) AS series,
       COUNT(*) AS rows
FROM price_index_monthly
GROUP BY is_excluded
ORDER BY is_excluded;


-- step 13: citywide series that survived, this is the comparison set for deliverable 2
-- expect 22. houses: 3, 5, 7, 10 marla, 1 and 2 kanal in both cities
-- flats: 3, 5, 7, 10 marla in both cities + karachi only 1 and 2 kanal
-- (karachi only ones have no lahore pair so they stay out of the gap comparison)
SELECT property_type, area_size, size_marla,
       COUNT(DISTINCT city) AS cities,
       MIN(month)           AS first_month
FROM price_index_monthly
WHERE area = '(citywide)' AND NOT is_excluded
GROUP BY property_type, area_size, size_marla
ORDER BY property_type, size_marla;
