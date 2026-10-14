# Airport operations — oracle

Synthetic data; fixed 2026 reporting period. Money is integer CAD cents, not float dollars. Dates have day granularity; no timezone conversion is implied. Each table's primary key defines its grain. Column-level types and relationships are in `data_dictionary.json`.

## Run from the pack root

```sh
python -m tools.sql_runner oracle migrate --allow-write
python -m tools.sql_runner oracle seed --allow-write --scale 1
python -m tools.sql_runner oracle verify --scale 1
python -m tools.sql_runner oracle status
```

Use `PACK_ORACLE_URL` for the migrator connection. SQLite defaults to `output/library.sqlite`. Set credentials outside the source tree. Provision a dedicated empty database/schema and a separate read-only Querywise account first. A URL does not create the database or install native drivers.

V001 creates 8 tables, foreign keys, checks, unique keys and FK indexes. V002 adds `delay_flag` to `flights` and backfills it with `delay_minutes >= 15`. It is a migration-time snapshot; subsequent application writes must maintain/recalculate this flag. Seed refreshes it after loading fixtures.

Migrations can also be inspected as SQL files. Choose the Python runner OR manual SQL; manual execution does not update the runner's history. The JSON manifest is the runner's authoritative statement list. Never mix paths on the same schema.

Base fixture: 510 rows. `--scale 10` creates ten times the main facts, with dimensions kept stable or expanded where uniqueness requires it. Scale is immutable after seeding: create another database to change it. Seed is fixture loading, not an upsert into operational data.

Verification checks every seeded value and compares analytics with an independently loaded SQLite reference. It is not a claim of optimizer performance, concurrency safety or production throughput. View `analytics.sql` for the advanced business questions. Aggregate independent child tables before joining them to avoid fan-out.

## Recovery

Forward-only migrations. There is no destructive automatic down migration. Take a database-native backup first; for a failed DDL migration restore the dedicated lab schema, diagnose, and retry. A dirty history row must never be marked applied without reconciliation. See `docs/OPERATIONS.md`.
