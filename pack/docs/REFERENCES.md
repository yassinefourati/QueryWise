# Primary technical references

Consult the documentation matching your installed server and client versions. These references guide the implementation; they are not proof that every remote engine was executed in this environment.

- SQLAlchemy engine/dialect configuration: https://docs.sqlalchemy.org/21/core/engines.html
- MySQL/MariaDB dialect behavior: https://docs.sqlalchemy.org/en/21/dialects/mysql.html
- Oracle dialect / driver behavior: https://docs.sqlalchemy.org/en/20/dialects/oracle.html
- MongoDB schema validation: https://www.mongodb.com/docs/manual/core/schema-validation/
- Elasticsearch reindex API: https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-reindex
- Elasticsearch migration guidance: https://www.elastic.co/docs/manage-data/migrate
- Db2 LUW documentation entry point: https://www.ibm.com/docs/en/db2
- Microsoft Excel automation reference: https://learn.microsoft.com/en-us/office/vba/api/overview/excel
- DuckDB Parquet overview: https://duckdb.org/docs/stable/data/parquet/overview

Migration design: build destination mappings before reindexing; retain old Elasticsearch indices; stage MongoDB validator changes around data backfills; treat DDL transaction behavior as engine-specific. File versions are explicit and retain the original source.
