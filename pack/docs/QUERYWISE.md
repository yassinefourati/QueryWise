# Connect the datasets to Querywise

The pack lives inside the Querywise repository (`pack/`). The app reads sources either from the UI (Settings → Data sources, stored encrypted in the local app-state DB) or from a secret-free registry file named by `QUERYWISE_SOURCES_FILE`.

1. Migrate, seed and verify the selected source in this pack (run from `pack/`).
2. Create a reader account/role separately from the migrator (`<engine>/reader_role.sql`, `mongodb/reader_role.json`, `elasticsearch/reader_privileges.json`).
3. Connect it, either way:
   - **UI:** Settings → Data sources → Add connection. Choose the kind, paste the reader URL (password in the Password field), Test connection, then Save & connect. For file sources use a path such as `pack/output/library.sqlite`, `pack/output/sensors/v2` (each Parquet file becomes a table) or `pack/excel/fixtures` (CSV) / `pack/output/grants/grants-v2.xlsx`.
   - **Registry file:** `python -m tools.make_querywise_config --only sqlite parquet --output querywise-sources.json`, then set `QUERYWISE_SOURCES_FILE=pack/querywise-sources.json` and the `QUERYWISE_*_URL` / `QUERYWISE_*_PATH` variables it names (in the root `.env` or your shell). Registry entries carry the pack's business definitions and point the catalog at `pack/<engine>/questions.json`.
4. Selecting a source tests the connection first; only then does the app discover tables, columns, types and keys. `/api/schema`, `/api/catalog` and the AI prompt use that discovered schema. `qw_pack_history` is never exposed.

For Docker, mount the pack's output directory read-only into the app and use container paths, for example `/app/user-data/pack/library.sqlite`. A Windows host path is not a container path. Use `host.docker.internal` for host database servers.

| Source | Querywise path | Native exercises beyond the app |
|---|---|---|
| SQLite/PostgreSQL/MySQL/MariaDB/SQL Server/Oracle | Discovered-table SELECT, supported functions, ≤ 6 joins | DDL, stored code, administrative operations |
| Db2 LUW | Generic ANSI SQL through SQLAlchemy (`ibm_db_sa`) | Engine-specific SQL in `analytics.sql` |
| MongoDB | SQL translated to `$match/$group/$project/$sort/$limit` on one collection, top-level fields | `$lookup`/`$unwind`, nested lessons, cross-collection scores |
| Elasticsearch | Elasticsearch SQL API, one index or alias per query | Raw Query DSL, percentiles, cross-index correlation |
| Excel / CSV | Each sheet or CSV file is a table in in-memory SQLite; cached formula values | Formula recalculation, workbook editing, inferred FKs |
| Parquet | Each file in a folder is a table in in-memory DuckDB | Multi-version catalogs, dataset-wide migration logic |

Do not infer that a native engine exercise is automatically supported in the app. The sample definitions describe the business rules, but AI output still requires review.
