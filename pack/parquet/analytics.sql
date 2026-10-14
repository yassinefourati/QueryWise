-- Run with DuckDB, from the pack root after seed and migrate.
SELECT region,quality,COUNT(*) readings,AVG(calibrated_c) average_c
FROM read_parquet('output/sensors/v2/analytics_readings.parquet')
GROUP BY region,quality ORDER BY region,quality;

-- Daily trend. NULL temperatures stay NULL; never substitute zero degrees.
SELECT observed_on,AVG(calibrated_c) average_c,COUNT(calibrated_c) measured,
       COUNT(*) total FROM read_parquet('output/sensors/v2/analytics_readings.parquet')
GROUP BY observed_on ORDER BY observed_on;
