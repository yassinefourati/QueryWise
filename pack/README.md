# Querywise — complex business database migration pack

Eleven separate business domains, with versioned schema/data upgrades, synthetic fixtures, analytics and validation. It is merged into the Querywise repository as `pack/`: run the pack commands from this folder, and connect the outputs to the app from Settings → Data sources (see `docs/QUERYWISE.md`). No AI key is needed to migrate or test these databases; AI keys belong to the app (Settings or the root `.env`), never to this pack.

“Migration” here means **V1 → V2 within each source**, including the data backfill or file conversion. It is not an arbitrary Oracle-to-MongoDB or all-to-all data converter. Each business has different entities and semantics, so transferring a real business between engines requires an explicit field/type/relationship mapping.

| Source | Business | Main structures | Upgrade |
|---|---|---|---|
| SQLite | Public library | 7 tables: branches, members, titles, copies, loans, fines, payments | Overdue snapshot |
| PostgreSQL | Renewable energy | 8 tables: sites, turbines, readings, contracts, outages, crews, work orders, settlements | Reading review flag |
| MySQL | Retail | 8 tables: customers, products, warehouses, inventory, orders, lines, returns, payments | Pending-order review |
| MariaDB | Cold-chain freight | 7 tables: depots, vehicles, drivers, shipments, legs, temperature scans, invoices | Delivery SLA flag |
| SQL Server | Outpatient billing | 7 tables: clinics, patients, clinicians, procedures, appointments, claim lines, remittances | No-show flag |
| Oracle | Airport operations | 8 tables: airports, aircraft, routes, gates, flights, turnarounds, disruptions, crews | Departure-delay flag |
| Db2 LUW | Property insurance | 7 tables: holders, policies, coverages, claims, reserve changes, payments, recoveries | Large-loss flag |
| MongoDB | Online learning | 4 collections, nested lesson arrays and profiles | Seconds → learning minutes |
| Elasticsearch | Service reliability | Requests, deployments, incidents | New mapping + reindex + alias switch |
| Excel | Nonprofit grants | Donors, programs, awards, disbursements, milestones | Calculated remaining commitments |
| Parquet | Environmental sensors | Sites, sensors, readings, calibrations | Typed quality/calibration serving data |

## Quick start — Windows PowerShell

Python 3.12 is the tested Python runtime. Extract this pack into its own directory. Run commands from that root.

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python -m tools.sql_runner sqlite migrate --allow-write
python -m tools.sql_runner sqlite seed --allow-write
python -m tools.sql_runner sqlite verify
python -m tools.parquet_runner seed
python -m tools.parquet_runner migrate
python -m tools.parquet_runner verify
python -m pytest -q
```

SQLite output: `output/library.sqlite`. Parquet versions: `output/sensors/v1` and `v2`. These are generated locally; the download deliberately does not ship a pre-populated output folder that would prevent a clean first run.

On Linux/macOS, use `python3 -m venv .venv`, then `source .venv/bin/activate`. Excel COM scripts require Windows with desktop Microsoft Excel.

## Server engines

```powershell
python -m pip install -r requirements-servers.txt
$env:PACK_POSTGRES_URL='postgresql+psycopg://MIGRATOR:ENCODED_PASSWORD@localhost:5432/qw_complex_energy'
python -m tools.sql_runner postgres migrate --allow-write
python -m tools.sql_runner postgres seed --allow-write --scale 1
python -m tools.sql_runner postgres verify --scale 1
```

Substitute `mysql`, `mariadb`, `sqlserver`, `oracle`, or `db2` and its matching PACK_*_URL. Create an empty dedicated database/schema first. The scripts do not start server containers, accept licenses, create logins or supply passwords. See `docs/SETUP.md` for provisioning and driver prerequisites.

Every relational source includes V001 schema SQL, V002 upgrade SQL, seed SQL, a statement manifest, Python command wrappers, analytics, questions and a data dictionary. The runner stores checksums and states in `qw_pack_history`. A repeated completed migration is skipped; changed checksums or dirty steps block execution.

MongoDB and Elasticsearch use their own scripts and upgrade order. Follow each folder's README. Excel uses `excel/migrate.ps1`. Parquet uses `tools/parquet_runner.py`.

## Test every configured source

```powershell
python -m tools.verify_all
python -m tools.verify_all --require-all
```

The second command fails if any source is unavailable or fails. Missing connections are reported as SKIP, not PASS. `reports/live-results.json` records source-level results. Verification never creates databases or seeds data.

## Scale and business rules

Relational base fixtures have 120 principal facts plus their related rows. `--scale 100` creates 12,000 principal facts. Parquet starts with 1,200 readings, so scale 100 creates 120,000 readings. This is a generator range, not a measured capacity claim. Exact comparison tests load data into memory and are intended for labs. Start at scale 1. Use a fresh database/directory when changing scale.

Amounts are signed integer CAD cents where reversals are allowed; quantities and capacities have checks. Dates are fixed 2026 day-granularity values. NULL, zero, cancellation, partial payment, refund and adjustment are separate states. The insurance reserve table stores **deltas**, not snapshots. Never sum reserve snapshots as if they were deltas.

The model is intentionally richer than the earlier two-table connector fixture, while still being a finite teaching dataset. It is not a complete ERP, medical billing system, actuarial model or production migration framework.

## Querywise integration

Follow `docs/QUERYWISE.md`. Use separate reader credentials. The app discovers each source's tables and columns, grounds the AI prompt in them, and enforces its own read-only controls. MongoDB queries go through a restricted SQL→aggregation translator (single collection, no joins), Elasticsearch through its SQL API, Excel/CSV and Parquet through in-memory SQLite/DuckDB. Creating these databases does not extend those limits.

Python dependencies come from the repository root: `requirements.txt` here includes `../requirements-dev.txt`, and `requirements-servers.txt` includes `../requirements-connectors.txt`. Generated data (`output/`) and `querywise-sources.json` are git-ignored by the root `.gitignore`.

## Verification and recovery

See `reports/VERIFICATION.md` for what actually ran. See `docs/OPERATIONS.md` for backup, migration ordering, lock/dirty-state recovery and forward-only rollback strategy. Source-specific documentation includes the limitations for each engine. No production endpoints were accessed.
