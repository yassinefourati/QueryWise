# Querywise

**Ask your databases questions in plain language and get back the SQL, the real rows and a chart, read-only.**

Querywise is a self-hosted analytics assistant. You type a business question ("Which routes carried the most passengers?"). A language model (Anthropic Claude or a local Ollama model) writes SQL for the database you've connected. Querywise checks that SQL against the database's real schema and runs it read-only, then shows the actual result as a chart, a table and the SQL itself. The model only ever sees the schema and your question, never your data.

It connects to **11 kinds of data sources**: SQLite, PostgreSQL, MySQL, MariaDB, SQL Server, Oracle, Db2, MongoDB, Elasticsearch, Excel/CSV and Parquet. It also ships with sample databases from a small store up to two 40-table, 10-million-row histories, so you can try it immediately.

![Querywise answering a question about the sample database](docs/images/ask-light.png)

| Dark mode | Multi-series charts | Data sources |
|---|---|---|
| ![Dark mode](docs/images/ask-dark.png) | ![Heatmap chart](docs/images/chart-heatmap.png) | ![Settings: data sources](docs/images/settings.png) |

**Version:** 1.0.0 — see the [changelog](CHANGELOG.md). **License:** [MIT](LICENSE).

## Contents

- [Features](#features)
- [Quick start](#quick-start)
- [How it works](#how-it-works)
- [1. Run with Docker Desktop](#1-run-with-docker-desktop)
- [2. Choose a model and connect data](#2-choose-a-model-and-connect-data-settings)
- [3. Run Python directly](#3-run-python-directly)
- [Secrets](#secrets-where-they-live-and-why-they-cannot-be-pushed) · [Environment variables](#environment-variables) · [Data sources and connectors](#data-sources-and-connectors)
- [Sample data](#large-sample-databases) · [Migration pack](#the-migration-pack-pack) · [What each database contains](docs/DATABASES.md)
- [Read-only execution policy](#read-only-execution-policy) · [Testing](#test-and-measure) · [Project structure](#project-structure) · [License](#license)

## Features

- **Plain-language questions → read-only SQL → real results.** Every answer shows the generated SQL, the result rows and a chart. You can edit the SQL and run it again.
- **Bring your own database.** Add a connection in Settings. Querywise tests it, discovers every table, column, type and key, and uses that schema both to guide the model and as a strict table allowlist.
- **11 connectors,** each with its own read-only and timeout controls. MongoDB questions are translated to aggregation pipelines, and Elasticsearch questions run through its SQL API.
- **Choice of model:** Anthropic Claude (structured output, optional workspace ID) or any local Ollama model. Demo mode works with no model at all.
- **Safe by design:**
  - one SELECT per request, allowlisted functions, at most six joins and a 500-row cap;
  - each engine's own read-only transaction and timeout, with every query rolled back;
  - local-only access with protection against cross-site requests (CSRF) and DNS rebinding.
- **Secrets stay on your machine.** API keys and passwords are encrypted at rest in a git-ignored local database, and the browser only ever sees `••••abcd`-style masks.
- **Visualizations that fit the data:** bars, columns, line, area, share, stacked, heatmap, scatter, map and single value, with hover details, CSV export, saved queries and history.
- **Light and dark themes,** a responsive layout, and a browser-only demo (SQLite compiled to WebAssembly) that needs no server.
- **Tested against real engines.** One script starts every supported database, the backend and the frontend in Docker and runs all test suites against them.

## Quick start

You need [Docker Desktop](https://www.docker.com/products/docker-desktop/).

```bash
git clone https://github.com/yassinefourati/QueryWise.git
cd QueryWise
docker compose up --build
```

Open **http://localhost:8000**. The suggested sample questions work right away. To ask your own questions, open **Settings → AI provider**: paste an Anthropic API key, or point it at a local Ollama model. Then try *"How is revenue trending by month?"*

To explore larger data, see [Large sample databases](#large-sample-databases) or [docs/DATABASES.md](docs/DATABASES.md). That guide has example questions for every sample database, from easy to hard.

## How it works

```
Your question ──► FastAPI backend ──► AI provider (Claude / Ollama): sees the schema and the question, never row data
                       │                         │
                       │      ◄── structured answer: SQL + title + chart type (or a clarification)
                       ▼
          SQL validator (one SELECT, discovered tables only, allowlisted functions, ≤ 6 joins)
                       ▼
          Connector for the active source (read-only transaction, timeout, rollback, 500-row cap)
                       ▼
          Rows ──► UI: chart · table · SQL · CSV export
```

**Scope:** a local, single-user tool with no login. Don't expose it to the internet. Each question is answered independently; there is no follow-up chat context.

## 1. Run with Docker Desktop

```powershell
docker compose up --build
```

Open **http://localhost:8000**. The app starts on the Northstar sample in demo mode. The port is bound to localhost only. The container runs with a read-only root filesystem, all capabilities dropped and `no-new-privileges`. The only writable path is the named volume `querywise-state` mounted at `/app/state`, which holds the app-state database and its key file.

To include optional connector drivers in the image, pass them as a build argument:

```powershell
$env:CONNECTORS = 'PyMySQL==1.2.3 pymongo==4.18.3 duckdb==1.5.6 openpyxl==3.1.5'
docker compose up --build
```

To query local files (SQLite, Excel, Parquet) from the container, mount them read-only in `compose.yaml`, for example `./pack/output:/app/user-data/pack:ro`. Then use the container path in Settings.

Stop with `docker compose down`. Add `-v` to also delete the saved settings, sources and keys.

**What is in each database, and example questions to ask (easy → hard):** see [docs/DATABASES.md](docs/DATABASES.md).

## 2. Choose a model and connect data (Settings)

Open Settings with the gear icon in the header.

**AI provider tab**
- **Anthropic Claude:** paste your API key, then use *Save & test*. The test checks the key and model without generating text. The default model is `claude-opus-5-5` at effort `medium`. For Opus 5.5, Opus 5, Fable 5.1 and Sonnet 5.5, server-side refusal fallback (`fallbacks: "default"`) is on; set `ANTHROPIC_FALLBACKS=off` to disable it.
- **Ollama:** install it from https://ollama.com and run `ollama pull qwen2.5:7b`. In Docker the default URL is `http://host.docker.internal:11434`. If Docker cannot reach it, set Ollama's `OLLAMA_HOST=0.0.0.0:11434` and firewall it.

**Data sources tab**
1. Click *Add connection* and choose the kind.
2. Enter a URL (put the password in the Password field), a file or folder path, or the *name* of an environment variable that holds the value.
3. Click *Test connection*, then *Save & connect*.
4. Optionally add business definitions, for example how revenue is computed. They are added to the AI prompt.

A failed switch leaves the previous source active.

Settings set by environment variables are shown as locked in the UI.

## 3. Run Python directly

Use Python 3.12 or later (Docker uses 3.12). In PowerShell:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements-dev.txt
.\.venv\Scripts\python -m pip install -r requirements-connectors.txt   # optional drivers
.\.venv\Scripts\python scripts/seed.py
.\.venv\Scripts\python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

Python does not read `.env` automatically; set variables in your shell (`$env:ANTHROPIC_API_KEY = '...'`) or use the Settings UI. Docker Compose reads `.env` itself. API docs are at **http://localhost:8000/docs**. Every non-GET API call needs the header `X-Querywise-Client: 1`; the UI sends it.

## Secrets: where they live and why they cannot be pushed

API keys, database URLs and passwords are only ever read at runtime from one of two places:

1. **Environment variables**, usually from your local `.env`. `.env` is listed in `.gitignore`; only `.env.example`, which contains placeholders only, is meant to be committed.
2. **The local app-state database** `.querywise/state.db`. Secrets are encrypted there with Fernet (AES-128-CBC + HMAC-SHA256). The key comes from one of two sources:
   - a passphrase in `QUERYWISE_SECRET_KEY`, stretched with PBKDF2-SHA256 (600,000 iterations, per-install salt);
   - otherwise, a random key generated into `.querywise/secret.key` with mode 0600.

   The whole `.querywise/` folder is git-ignored. In Docker it lives on the `querywise-state` volume, never in the image.

Tracked files never contain secrets. The source registry (`QUERYWISE_SOURCES_FILE`) names environment variables instead of holding values. API responses return masks only, never stored secrets. Connection errors are redacted: any `user:password@` in a URL and any known password or key are replaced with `•••`. `.gitignore` also excludes `data/`, `pack/output/`, generated registries, `*.key`, `*.db`, `*.sqlite`, `*.parquet` and `*.xlsx`. A test (`test_secret_locations_are_git_ignored_and_template_is_empty`) fails if these rules or the placeholder-only template regress. If you change `QUERYWISE_SECRET_KEY` or lose `secret.key`, saved secrets become unreadable and the UI asks you to re-enter them.

**Precedence:** a non-empty environment variable wins, then the value saved in the app-state database, then the default. For sources, a variable named by the source (`url_env`, `path_env`, `api_key_env`) overrides the saved encrypted value. Sources defined by the environment (`DATABASE_URL`, `QUERYWISE_SOURCES_FILE`) override saved sources with the same id.

## Environment variables

| Variable | Purpose |
|---|---|
| `AI_PROVIDER` | `demo`, `ollama` or `anthropic`. Leave empty to choose in the UI. |
| `ANTHROPIC_API_KEY` | Claude API key. Leave empty to paste it in Settings instead. |
| `ANTHROPIC_MODEL` | Default `claude-opus-5-5`. |
| `ANTHROPIC_EFFORT` | `low`, `medium` (default), `high`, `xhigh` or `max`. |
| `ANTHROPIC_WORKSPACE_ID` | Only for API keys not scoped to a workspace (Anthropic then answers 400 "must include the anthropic-workspace-id header"). Also settable in Settings. |
| `ANTHROPIC_FALLBACKS` | `on` (default) or `off`: server-side refusal fallback on supported models. |
| `OLLAMA_URL`, `OLLAMA_MODEL` | Ollama endpoint and model (default `qwen2.5:7b`). |
| `OLLAMA_DEFAULT_URL` | Default Ollama URL when neither the environment nor Settings sets one (Docker: `http://host.docker.internal:11434`). |
| `QUERYWISE_SECRET_KEY` | Passphrase used to encrypt saved secrets. If unset, a key file is generated. |
| `QUERYWISE_STATE_DIR` | App-state folder (default `./.querywise`; `/app/state` in Docker). |
| `QUERYWISE_SOURCES_FILE` | Secret-free source registry JSON (see `pack/tools/make_querywise_config.py`). |
| `QUERYWISE_DEFAULT_SOURCE` | Source id to use until one is chosen in the UI (default `sample`, or `database_url` when `DATABASE_URL` is set). |
| `QUERYWISE_*_URL`, `QUERYWISE_*_PATH`, `QUERYWISE_ELASTICSEARCH_API_KEY` | Reader credentials or paths referenced by the registry. |
| `DATABASE_URL` | Legacy: a PostgreSQL database with the Northstar schema, added as source `database_url`. |
| `QUERYWISE_ALLOWED_HOSTS` | Extra accepted `Host` headers besides `localhost`, `127.0.0.1` and `[::1]`. |
| `CONNECTORS` | Docker build argument: optional driver packages to install. |
| `PACK_*` | Migrator URLs used only by `pack/tools`, never by the app. |

## Data sources and connectors

Each kind first passes through the shared gateway described under [Read-only execution policy](#read-only-execution-policy). The connector then adds its own controls:

| Kind | Driver (optional) | Read-only and timeout controls | Translation / limits |
|---|---|---|---|
| SQLite | built in | `mode=ro`, `query_only`, table/function authorizer, ~3 s progress handler | — |
| PostgreSQL | `psycopg` (core) | `READ ONLY` transaction, 3 s `statement_timeout`, 1 s `lock_timeout`, pinned `search_path`, rollback | — |
| MySQL | `PyMySQL` | `START TRANSACTION READ ONLY`, `MAX_EXECUTION_TIME` 3000 ms, rollback | — |
| MariaDB | `PyMySQL` | `START TRANSACTION READ ONLY`, `max_statement_time` 3 s, rollback | — |
| SQL Server | `pyodbc` + ODBC Driver 18 | No server-side read-only transaction exists. Relies on the validator, a `db_datareader` login, a 3 s ODBC query timeout, a 1 s lock timeout and rollback. | T-SQL dialect |
| Oracle | `oracledb` | `SET TRANSACTION READ ONLY`, 3 s driver call timeout, rollback | — |
| Db2 LUW | `ibm_db_sa` | Validator, SELECT-only user, rollback. **No driver timeout**; use Db2 WLM. | Generic ANSI SQL dialect |
| MongoDB | `pymongo` | Pipeline uses only `$match/$group/$project/$sort/$skip/$limit`, with `maxTimeMS` 3000 | SQL is translated to an aggregation: single collection, WHERE, GROUP BY, COUNT/SUM/AVG/MIN/MAX, ROUND, ORDER BY, LIMIT, top-level fields. No joins, subqueries, CTEs, HAVING or window functions. The schema is inferred from 200 sampled documents. |
| Elasticsearch | none (HTTP) | Elasticsearch SQL API (read-only by design), `request_timeout` 3 s, API key or basic auth, TLS verification | One index or alias per query; quote names containing `-`. No nested fields, percentiles or Query DSL. |
| Excel / CSV | `openpyxl` (xlsx) | Loaded into in-memory SQLite with `query_only`, authorizer and ~3 s interrupt; files never written | Each sheet or CSV file becomes a table, with the first row as header. Formulas are not evaluated; cached values are read. No inferred FKs. 300 MB cap. |
| Parquet | `duckdb` | Loaded into in-memory DuckDB, then file-system access and configuration are locked; ~3 s interrupt | A file or a folder (one table per `*.parquet`) is loaded at connect time; re-select the source to reload. 300 MB cap. |

Discovery hides `sqlite_*` tables and the pack's `qw_pack_history` ledger, and can be limited to a table list. The catalog of suggested questions comes from one of three places:
- the Northstar catalog, when the Northstar tables are present (transpiled to the source's dialect);
- a source's `questions` file, for example `pack/<engine>/questions.json`;
- otherwise, generated row-count and preview queries.

Every suggestion is validated against the source before it is shown.

## Large sample databases

`sample-databases/` holds two large synthetic databases for realistic, harder questions. Each has 40 tables and data running from 1999 to today:

| Database | Engine | Rows (scale 1) |
|---|---|---|
| Telecom & supply chain | PostgreSQL | about 11.2 million |
| Banking & insurance | Oracle Free | about 15.3 million |

```powershell
.\scripts\bigdb.ps1 up      # builds and starts Querywise with both databases registered as sources
.\scripts\bigdb.ps1 down    # stops them (the data is kept; add -Purge to delete it)
```

Each database generates its own data on first start: about 7 minutes for PostgreSQL and 20 for Oracle. `-Scale 0.05` gives a quick small version. Credentials are created randomly in `sample-databases/.env.bigdb`, which is git-ignored. See [docs/DATABASES.md](docs/DATABASES.md#13-telecom--supply-chain--postgresql-large) for the tables, business rules and example questions.

## The migration pack (`pack/`)

`pack/` holds eleven synthetic business domains, each with versioned V1→V2 migrations, seed data, analytics, questions, expected results and verify scripts. Run its commands from `pack/`; dependencies come from the root requirements files.

```powershell
cd pack
python -m tools.sql_runner sqlite migrate --allow-write
python -m tools.sql_runner sqlite seed --allow-write
python -m tools.sql_runner sqlite verify
python -m tools.parquet_runner seed; python -m tools.parquet_runner migrate; python -m tools.parquet_runner verify
```

`tools/sql_runner.py` records checksums and states in `qw_pack_history`. It skips completed steps and blocks on changed checksums, dirty steps or an existing lock; the tests cover all three cases. Outputs go to `pack/output/`, which is git-ignored. To connect the outputs, use Settings, or generate a registry with `python -m tools.make_querywise_config --only sqlite parquet` and set `QUERYWISE_SOURCES_FILE`. See `pack/docs/QUERYWISE.md`, `pack/docs/SETUP.md` and `pack/reports/VERIFICATION.md`.

## What was verified, and what was not

Run on 2026-10-14 with `scripts/run_live_tests.ps1` in Docker (see [Live test stack](#live-test-stack-every-engine-in-docker)). Every stage exited 0.

| Check | Result |
|---|---|
| Unit + pack tests (89), browser SQLite/WASM | PASS |
| Pack migrate → seed → verify, natively | PASS: SQLite, PostgreSQL 16, MySQL 8.4, MariaDB 11.4, SQL Server 2022, Oracle Free 23, Db2 11.5.9, MongoDB 8.0, Elasticsearch 9.1, Parquet. **Excel SKIP**: the native COM script needs Windows desktop Excel, and it failed when run on this Windows machine (see `pack/reports/VERIFICATION.md`). |
| App end to end, per engine (reader accounts) | PASS for all of the above. Covered: a wrong password gives a clear error and leaks no secret; the switch discovers the expected tables; pack questions match `expected_results.scale1.json`; the 3 s timeout fires (not Db2, which has no driver timeout); a reader write is blocked; the read-only transaction blocks an admin write (PostgreSQL, MySQL, MariaDB, Oracle). |
| Running backend container (HTTP) | PASS: all 11 sources test, switch and run their suggested queries; no secrets in any response. |
| Standalone frontend (nginx + API proxy) in headless Chromium | PASS: every source connected from Settings and rendered its schema, stats and a result; no console errors; no secrets in the DOM; no horizontal overflow at 390 px. Static-only hosting falls back to the WASM demo. |
| Anthropic | Live on 2026-10-14: key + model check passed, and one question on the Northstar sample returned correct SQL and results (`claude-opus-5-5`, structured output, workspace header). The remaining cases are mocked. Ollama: mocked only. |

## Live test stack (every engine in Docker)

```powershell
.\scripts\run_live_tests.ps1 -AcceptLicenses   # build, start, run every test, then leave the stack running
.\scripts\run_live_tests.ps1 -Down             # stop and delete everything
```

`compose.test.yaml` starts the following on an internal network, with no database ports published:
- PostgreSQL, MySQL, MariaDB, SQL Server, Oracle Free, Db2 Community, MongoDB and Elasticsearch;
- the backend, at `http://localhost:8000`;
- the standalone frontend (nginx), at `http://localhost:8080`;
- a runner image (`Dockerfile.test`) with every driver plus Chromium.

Passwords are generated per run in the process environment and never written to disk. `-AcceptLicenses` accepts the SQL Server Developer, Microsoft ODBC Driver 18 and Db2 Community licenses for these test containers. Db2 needs a privileged container. The runner provisions migrator and reader accounts, runs every suite, and writes JUnit XML, `frontend.json`, `verify_all.json` and screenshots to `test-results/` (git-ignored). After a run, both apps stay up with all 11 sources registered.

## Architecture

```
dist/ (vanilla JS UI) ──► FastAPI backend/main.py ──► providers.py (demo │ Ollama │ Anthropic)
                                 │                          ▲ prompt built from discovered schema
                                 ├─► sources.py registry ───┘  (builtin sample, env/registry file, saved sources)
                                 │      └─► connectors.py  test → discover → run (per-engine read-only controls)
                                 ├─► database.py  validate(): one SELECT, discovered-table allowlist, function allowlist, ≤6 joins
                                 └─► state.py  .querywise/state.db (encrypted secrets, sources, schema cache, history)
```

- `backend/mongo_sql.py`: SQL → MongoDB aggregation translator.
- `dist/db-worker.js`: browser SQLite demo (unchanged).
- `dist/catalog.json`: Northstar sample questions.
- `scripts/seed.py`: deterministic sample generator (random seed 2027).
- `scripts/evaluate.py`: model evaluation for the Northstar sample.
- `tests/`: backend tests.
- `pack/tests/`: pack tests, run by the same `pytest`.

No raw row data is sent to the model. The prompt contains the question, the discovered table and column names and types, the keys, row counts, and the source's business definitions. The explanation is model-generated and should be reviewed; the displayed values come from the database.

## Northstar sample data and business rules

All data is fictional: 80 customers, 16 products, 720 orders and 1,855 order items, from January to September 2026.

| Table | Keys and relationships |
| --- | --- |
| customers | `id` primary key; `name`, `province`, `segment` |
| orders | `id` primary key; `customer_id` → customers; `order_date`, `status` |
| products | `id` primary key; `name`, `category`, `price` |
| order_items | `id` primary key; `order_id` → orders; `product_id` → products; `quantity`, `unit_price` |

Revenue is `SUM(quantity * unit_price)` for completed orders only. Amounts are CAD before tax. There are no tax, discount, refund, cost or profit records. Average order value uses distinct completed order IDs. This teaching dataset uses floating-point money for portability; use decimal types in a financial system.

## Read-only execution policy

The gateway applies these controls to every source, whether the SQL was typed or generated:

1. SQLGlot parses exactly one SELECT. Mutations, SELECT INTO, row locks, recursive CTEs and set operations are rejected.
2. Only the active source's **discovered** tables are allowed. They can be narrowed to a configured subset. Cross-schema access is disabled, and CTE names cannot shadow source tables.
3. SQL functions are allowlisted. File, extension, network, sleep and arbitrary user-defined function calls are rejected. `CASE`/`IF` and date-part helpers are allowed; in this sqlglot version `AND`/`OR` are no longer mistaken for functions.
4. At most six joins.
5. Each connector then applies its engine's own read-only transaction and timeout controls (table above), and always rolls back.
6. Results are capped at 500 rows, with an explicit truncation flag. The cap does not prevent expensive planning or aggregation.
7. The API accepts only local `Host` headers, which guards against DNS rebinding. State-changing calls require `X-Querywise-Client: 1`, which guards against CSRF.
8. The browser demo uses its own query filter, `query_only`, and a Web Worker that is terminated after four seconds. Backend controls are authoritative.

Approved-by-policy SELECTs run automatically. Prompt instructions are not the security boundary. Use SELECT-only database accounts.

## Optional PostgreSQL with the Northstar schema

Use an empty local development database. For example:

```powershell
docker run --name querywise-postgres -e POSTGRES_PASSWORD=local_admin_password -e POSTGRES_DB=querywise -p 127.0.0.1:5432:5432 -d postgres:17
$env:POSTGRES_ADMIN_URL = 'postgresql+psycopg://postgres:local_admin_password@localhost:5432/querywise'
.\.venv\Scripts\python scripts/init_postgres.py
```

The initializer refuses a non-empty `public` schema. Create a restricted role (replace the illustrative password):

```sql
CREATE ROLE querywise_reader LOGIN PASSWORD 'change_this_local_password';
GRANT CONNECT ON DATABASE querywise TO querywise_reader;
GRANT USAGE ON SCHEMA public TO querywise_reader;
GRANT SELECT ON customers, orders, products, order_items TO querywise_reader;
ALTER ROLE querywise_reader SET default_transaction_read_only = on;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
```

Then add the database in Settings → Data sources, or set `DATABASE_URL` in `.env`. Use `host.docker.internal` from Docker and `localhost` from the host. The Northstar suggestions are transpiled to PostgreSQL.

## Test and measure

```powershell
.\.venv\Scripts\python -m pytest -q        # backend + pack tests (pytest.ini sets the paths)
node scripts/test_browser_sql.cjs          # SQLite/WASM worker used by the hosted demo
.\.venv\Scripts\python scripts/evaluate.py --url http://localhost:8000
```

The evaluation compares the model's result rows with independently executed reference SQL for the **Northstar sample**: select it in Settings first. It reports accuracy and latency and saves `eval-results.json` (git-ignored). Matching results on one dataset can still hide mistakes; extend the cases as you learn.

## A focused learning path

1. Read the reference SQL and change a business metric; confirm the result manually.
2. Run the evaluation cases against your chosen model before editing the prompt.
3. Connect a pack source and add business definitions; compare answers with and without them.
4. Add paraphrases and ambiguous requests. Measure errors and clarification quality.
5. Add a plan-and-preview step before execution, and measure its effect on accuracy and latency.
6. Add authenticated users, per-user permissions, audit records and rate limiting before considering shared deployment.

## Deployment and privacy

- The hosted site serves only the browser demo and the downloadable source. It has no Python runtime, model or database connections.
- The Python app is a local single-user project. It has no login, tenant isolation or server audit trail. Do not expose it directly to the internet.
- Query history and saved queries (question text and SQL) are stored unencrypted in the app-state database; secrets are the only encrypted values. Clear history from the UI.
- Google Fonts is optional. SQL.js is vendored, with its license in `dist/vendor/`.

## Primary references

- Anthropic structured outputs: https://platform.claude.com/docs/en/build-with-claude/structured-outputs
- Ollama structured outputs: https://docs.ollama.com/capabilities/structured-outputs
- SQLGlot: https://sqlglot.com/
- SQLite read-only URI connections: https://www.sqlite.org/uri.html
- SQLite authorizer: https://www.sqlite.org/c3ref/set_authorizer.html
- Elasticsearch SQL: https://www.elastic.co/docs/explore-analyze/query-filter/languages/sql
- SQL.js: https://github.com/sql-js/sql.js

## Project structure

```
backend/            FastAPI app: API, SQL validator, connectors, source registry, AI providers, encrypted app state
dist/               Frontend (plain HTML/CSS/JS, no build step) and the in-browser SQLite/WASM demo
docs/               Database guide (DATABASES.md) and README images
pack/               Migration pack: 11 synthetic business databases with migrations, seeds and verification
sample-databases/   Two large PostgreSQL / Oracle sample databases with Docker images
scripts/            Seeding, evaluation, packaging, live test stack, big-database launcher
tests/              Unit tests and live tests (live tests run inside compose.test.yaml)
frontend/           nginx configuration for serving the UI as a standalone container
evals/              Question/answer cases for measuring model accuracy
```

## Contributing

Issues and pull requests are welcome. Before opening a pull request:

1. Run `python -m pytest -q` (unit and pack tests) and `node scripts/test_browser_sql.cjs`.
2. For connector changes, run the full engine suite with `.\scripts\run_live_tests.ps1 -AcceptLicenses`.
3. Never commit secrets. `.env`, `.querywise/` and generated data are git-ignored, and a test fails if the ignore rules regress.

## License

[MIT](LICENSE) © 2026 Yassine Fourati. Sample data is synthetic. Third-party components keep their own licenses: SQL.js (`dist/vendor/`) and Leaflet (`dist/vendor/leaflet/`).
