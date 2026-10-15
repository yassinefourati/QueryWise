# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-10-14

First public release.

### Ask questions in plain language
- Natural-language questions answered with read-only SQL and the actual result rows.
- AI providers: **Anthropic Claude** (structured output, optional workspace ID, server-side refusal fallback) and **Ollama** (local models). A **demo** mode runs suggested questions with no model.
- Clarifications instead of invented numbers when a question is ambiguous or asks for data that doesn't exist.

### Connect any of 11 data source kinds
- SQLite, PostgreSQL, MySQL, MariaDB, SQL Server, Oracle, Db2, MongoDB, Elasticsearch, Excel/CSV and Parquet.
- Switching sources from the UI tests the connection first, then discovers every table, column, type and key.
- The discovered schema grounds the AI prompt and becomes the table allowlist.
- MongoDB questions are translated to aggregation pipelines; Elasticsearch questions run through its SQL API.

### Read-only by design
- One SELECT per request, allowlisted tables and functions, at most six joins, a 500-row cap.
- Each engine adds its own guard: read-only transactions, timeouts and rollback.
- Local-only host check and a required client header on every write request.

### Secrets stay local
- API keys and connection passwords are encrypted at rest in a git-ignored app-state database (Fernet).
- Only masked values (last 4 characters) are ever returned to the browser.
- Environment variables override saved values.

### Interface
- Clean, theme-aware UI with light and dark mode.
- Chart types: bars, columns, line, area, share, stacked, heatmap, scatter, map and single value, with hover details and CSV export.
- Saved queries and history are stored on the backend, with a browser-only fallback.
- A browser-only demo runs the sample database in SQLite/WASM without a backend.

### Data and tests
- Northstar sample dataset.
- Migration pack with 11 synthetic business databases (versioned migrations, seed data, verification).
- Two large sample databases (40 tables each, data from 1999 to today), runnable with Docker.
- Unit and pack test suites.
- A Docker test stack that runs every engine, the backend and the frontend together (`scripts/run_live_tests.ps1`).
