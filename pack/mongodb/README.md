# Online learning — MongoDB

Four collections: courses with embedded lessons, learners with nested profiles, enrollments, and assessment attempts. Missing scores are different from a zero score. Repeated course enrollments use distinct cohorts. All learners are synthetic.

Set PACK_MONGODB_URL to a local/authenticated server URI. The scripts use only the dedicated `qw_complex_learning` database. The migrator needs collection creation, collMod, index, read and write privileges. Use a separate read-only Querywise user.

```sh
python -m tools.mongo_runner migrate --target 1 --allow-write
python -m tools.mongo_runner seed --scale 1 --allow-write
python -m tools.mongo_runner migrate --target 2 --allow-write
python -m tools.mongo_runner verify --scale 1
```

V1 creates validators and indexes. V2 adds learning_minutes, derived from duration_seconds, and moves schema_version to 2. The backfill is additive and resumable. Validators accept both versions during backfill and require v2 afterward. A persistent unique lock prevents concurrent migration jobs; inspect a stale lock after a crashed process before manually removing it. Stop application writes during this lab upgrade.

Seed uses stable IDs and setOnInsert, so an interrupted seed can resume without duplicates. Verification compares every expected document and computes active learning minutes independently. Native aggregation examples in analytics.json include lookup/unwind; Querywise v5 does NOT expose arbitrary Mongo pipelines, nested lesson arrays or cross-collection joins. Register scalar fields or build a separate flattened collection for those questions.

Forward-only. Back up before migration. Restore the dedicated database to roll back; no automatic destructive cleanup is supplied. Changing fixture scale requires a fresh database.
