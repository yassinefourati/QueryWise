# Migration operating procedure

## Before applying

1. Provision an isolated empty database/schema and verify its name with a read-only connection. The migrator must own the intended schema, not a production schema.
2. Create a separate least-privilege application reader. Do not configure Querywise with the migration owner's password. Reader-role grant templates are per-source files; attach roles to separately provisioned logins.
3. Take a native backup or snapshot and test restore into a separate target. Record server version, collation, timezone, schema owner and driver versions.
4. Stop application writers. Use one migration operator. SQL has a persistent unique lock row; MongoDB has a unique lock document. Elasticsearch and file migrations require externally enforced single-writer operation.
5. Review V001 and V002 plus fixture grain. Use default schema resolution intentionally. All relational identifiers are unquoted lowercase in generated SQL; Oracle/Db2 may store uppercase catalog names.
6. Run at scale 1, verify all values and reconciliation queries, then test a larger fresh fixture if needed.

## Transaction boundaries

The SQL runner records a step as dirty in a committed transaction before executing it. Each DDL statement commits independently, because not all targeted engines can roll back the full DDL sequence. MySQL/MariaDB/Oracle implicit-commit behavior means a failure can leave partial schema changes. The runner does not pretend every migration is atomic. A successful step becomes applied only after its statements finish.

Seed data inserts use one SQLAlchemy transaction, with a dirty seed marker. MySQL/MariaDB require a transactional storage engine such as InnoDB; verify the server default before applying. No nontransactional-engine guarantee is made. Re-running a completed seed verifies the code/scale checksum and skips duplicate insertion. Never change fixture scale in place.

A crash can leave a lock or dirty marker. Do not delete it blindly. Restore the lab database from a known backup, or compare every affected object and row with the migration before a DBA repairs metadata. No automated repair command is provided. The source SQL files are for manual review/execution; Python uses migrations.json and its checksums. Do not mix manual execution and runner history on one schema.

## Rollback / recovery

- Relational: restore the dedicated database/schema. Forward-only migrations avoid pretending that dropping a new column reverses a data backfill safely.
- MongoDB: v2 is additive and retains duration_seconds; readers could revert after checking schema compatibility. Full rollback requires restoring v1 validators and handling post-upgrade writes. Prefer a tested backup restore for this lab.
- Elasticsearch: old index remains. With writers stopped, reverse the alias switch after reconciling any post-cutover writes. Reindex timeouts require checking whether a server task remains active before retrying.
- Excel: v1 and v2 are separate workbooks, with checksums. Select the prior workbook after reviewing downstream dependencies.
- Parquet: select the retained immutable v1 directory; consumers must use a consistent version. Local directory rename is not a distributed object-store commit protocol.

## Production extensions deliberately outside this pack

Online dual-write/backfill coordination, CDC, distributed migration leases, identity/sequence high-water marks for arbitrary imports, tenant isolation, partition maintenance, temporal tables, index-build concurrency, PII retention, change approval, restore automation, large-scale chunk checkpoints, network failover and cross-vendor all-to-all conversion need source-specific design. This pack's static-ID fixtures are not substitutes for those mechanisms.

## Engine targets

Use current compatible releases within these design baselines: SQLite with window functions; PostgreSQL 16+; MySQL 8.0.16+ with enforced CHECK constraints; MariaDB 10.6+ with InnoDB; SQL Server 2019+; Oracle 19c+; Db2 LUW 11.5+; MongoDB 6+ update pipelines; Elasticsearch 9.x for the bundled 9.x Python client. These are design targets, not a live-certified compatibility matrix. Test your exact version with `--require-all`. Db2 for i and Db2 for z/OS are not targeted.
