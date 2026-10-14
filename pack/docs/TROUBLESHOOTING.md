# Troubleshooting without exposing credentials

CLI failures print exception class only because drivers can include passwords, connection strings and server names in their messages. Use the database's local logs or inspect a failing connection locally; never paste a complete URL or environment dump into a ticket.

| Symptom | Check |
|---|---|
| Missing PACK_*_URL | Export variables into the shell running Python. `.env.example` is documentation; scripts do not auto-load it. |
| ModuleNotFoundError | Install requirements-servers.txt for that runtime, or only the driver listed in SETUP.md. |
| pyodbc import/connection error | Install native ODBC manager and Microsoft ODBC Driver 18. Check TLS trust and driver name. |
| Db2 library error | IBM CLI platform support, shared library dependencies, server edition and licensing. |
| Checksum/dirty history | Read migration state with `status`; restore or reconcile the dedicated lab target. Do not mark it applied just to proceed. |
| SQL lock insert fails | Another operator or a crashed migration owns `__lock__`. Confirm no process is active before DBA recovery. |
| Seed fails after --target 1 | SQL seed expects V002. Finish migrate to target 2, then seed. To test populated-v1 upgrade, use the included pytest test or a manually staged v1 fixture. |
| Native SQL seed then Python fails | Manual SQL does not populate Python history; choose one execution path for a fresh schema. |
| MongoDB duplicate index key | Check cohort uniqueness and whether this was a fresh synthetic database. Do not overwrite real data. |
| Elasticsearch v2 already exists | If alias already targets v2, migration is complete. Otherwise inspect failed reindex before rebuilding only the incomplete destination. |
| Excel COM unavailable | Run on Windows with desktop Excel installed. Excel Online, Linux and headless containers do not supply COM. |
| Excel hash mismatch | File changed after generation. Use reviewed inputs and a new version rather than disabling the integrity check. |
| Parquet destination exists | Verify it or choose --output for a new fixture. Versions are immutable. |
| Querywise rejects native example | The app uses restricted analytics languages. Consult QUERYWISE.md; native database capability is broader. |

For assertions, run the targeted local test with `python -m pytest tests/test_pack.py -x -vv`. This exposes synthetic fixture IDs, not database credentials. Server-specific failures still require local driver/server investigation.
