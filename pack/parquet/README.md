# Environmental sensors — Parquet

Four typed datasets: sites, sensors, readings, calibrations. Negative temperatures, zero degrees, missing samples and outliers are represented separately. Base volume is 1,200 readings; --scale 100 yields 120,000 readings.

```sh
python -m tools.parquet_runner seed --scale 1
python -m tools.parquet_runner migrate --scale 1
python -m tools.parquet_runner verify --scale 1
```

V1 writes typed, ZSTD-compressed Parquet. V2 renames value_c to temperature_c, derives quality, and builds a flattened analytics_readings.parquet with location and calibrated temperature. A missing value remains NULL; calibration is applied once. One calibration per sensor is guaranteed by these fixtures; time-varying calibrations would need effective-dated joins.

Each version contains a checksum manifest. Writes stage in the destination filesystem, then rename the completed directory. Single-writer local-filesystem workflow only; object-store atomicity is not assumed. Existing versions are never overwritten. Consumers explicitly select v1 or v2; rollback is a configuration change. No automatic pointer or schema evolution for arbitrary inputs is implied.

Verification checks source row values, version checksums, conversion, join cardinality and calibrated values. Run analytics.sql with DuckDB for daily trends and quality counts. Register the single v2 analytics file in Querywise; the app does not scan a whole data lake.
