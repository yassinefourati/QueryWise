# Server and workstation setup

Use the application's existing server lab or databases you already run locally. This pack does not bundle a second fleet of containers or start all enterprise engines together. On a 32 GB workstation, run one large server at a time. Server installation, licensing and native driver installation remain environment prerequisites.

## Python drivers

| Engine | Python package / URL dialect | Additional prerequisite |
|---|---|---|
| SQLite | Built-in sqlite3 / sqlite | Writable output directory for migration; reader opens file read-only |
| PostgreSQL | psycopg[binary] / postgresql+psycopg | Dedicated database and schema owner |
| MySQL | PyMySQL / mysql+pymysql | InnoDB default, enforced CHECK constraints |
| MariaDB | PyMySQL / mariadb+pymysql | InnoDB default, dedicated database |
| SQL Server | pyodbc / mssql+pyodbc | Microsoft ODBC Driver 18, native ODBC manager on Linux, trusted server certificate |
| Oracle | oracledb / oracle+oracledb | Thin mode supported server; PDB service and schema quota |
| Db2 LUW | ibm_db and ibm_db_sa / ibm_db_sa | Compatible IBM CLI/native libraries, LUW server, appropriate license |
| MongoDB | pymongo | Create/collMod/index/data privileges on qw_complex_learning |
| Elasticsearch | elasticsearch | Compatible 9.x server, CA trust and scoped API key |
| Excel | None for PowerShell COM | Windows desktop Excel installed; PowerShell 7 for supplied commands |
| Parquet | duckdb | Local filesystem and available memory |

Install all Python drivers using `python -m pip install -r requirements-servers.txt`, or install only the needed package. Packages do not install your database server or Microsoft ODBC Driver. Use the exact tested package pins as a starting point; validate changes in a fresh virtual environment.

## Provisioning examples — run as your local DBA

Passwords and logins are intentionally not embedded. Provision authentication separately using your normal secret-management workflow. The examples create target containers, not unrestricted application accounts.

PostgreSQL:

```sql
CREATE DATABASE qw_complex_energy;
-- Connect to qw_complex_energy as the migration owner; use public schema.
```

MySQL:

```sql
CREATE DATABASE qw_complex_retail CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
-- Connect to this database as a scoped migration user; verify InnoDB default.
```

MariaDB:

```sql
CREATE DATABASE qw_complex_freight CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

SQL Server:

```sql
CREATE DATABASE qw_complex_clinic;
GO
USE qw_complex_clinic;
GO
-- Provision a mapped migration user authorized for dbo and the required DDL.
```

Oracle: create/provision QW_COMPLEX in the desired PDB, with CREATE SESSION, CREATE TABLE, CREATE ROLE if it owns role provisioning, and a bounded tablespace quota. Configure the service name; do not run in SYS/SYSTEM. An existing user's default schema is used by the migrator. Reader grants should be issued by the owner or DBA after migration.

Db2 LUW: provision a dedicated database (example QWCMPLX — Db2 database names are limited to 8 characters) and schema QW_COMPLEX with an appropriate owner. The Python migrator uses the connection's CURRENT SCHEMA. **Ensure CURRENT SCHEMA is QW_COMPLEX before running**—configure `CurrentSchema=QW_COMPLEX` in the driver's connection settings, or use a migration user whose default schema is QW_COMPLEX. Setting PACK_DB2_SCHEMA only affects generated Querywise configuration, not the server session. Do not assume another user has the same default schema.

For Oracle and Db2, set PACK_ORACLE_SCHEMA/PACK_DB2_SCHEMA to the actual owner before generating Querywise source configuration. If you change schema names, regenerate/review role grants accordingly.

## Permissions

Run each relational `reader_role.sql` after schema creation as the owner/DBA. These templates create a role and grant SELECT on business tables only. Attach that role to a separately provisioned reader login/user. The templates are intentionally one-time, not idempotent login provisioning. No reader receives qw_pack_history access, DDL or write permissions through these templates. Existing grants inherited elsewhere can still grant writes; review the full account membership.

SQLite has no server roles. Use operating-system file permissions plus Querywise's read-only URI/authorizer. MongoDB and Elasticsearch have role/API-key privilege templates in their source directories. Configure credentials in process environment variables. Avoid logging full URLs.

For native SQL scripts, use a client that stops on errors (for example psql with ON_ERROR_STOP or sqlcmd with -b). SQL*Plus/sqlcl and Db2 CLP require their own error-stop settings. Prefer the Python runner for consistent dirty-state tracking.
