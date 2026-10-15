#!/usr/bin/env bash
# Runs once, on the first start with an empty data volume (docker-entrypoint-initdb.d).
# Generates the telecom schema, then creates the read-only login Querywise uses.
set -euo pipefail
: "${BIGDB_PG_READER_PASSWORD:?Set BIGDB_PG_READER_PASSWORD for the read-only telecom_reader login}"

sed "s/SET telecom.scale = '1'/SET telecom.scale = '${BIGDB_SCALE:-1}'/" /opt/bigdb/postgres_telecom_supply.sql > /tmp/load.sql
echo "bigdb: generating telecom data at scale ${BIGDB_SCALE:-1} (about 7 minutes at scale 1)..."
psql -v ON_ERROR_STOP=1 -q --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /tmp/load.sql > /dev/null
rm -f /tmp/load.sql

psql -v ON_ERROR_STOP=1 -q --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -v pw="$BIGDB_PG_READER_PASSWORD" <<'SQL'
CREATE ROLE telecom_reader LOGIN PASSWORD :'pw';
GRANT CONNECT ON DATABASE telecom_db TO telecom_reader;
GRANT USAGE ON SCHEMA telecom TO telecom_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA telecom TO telecom_reader;
ALTER ROLE telecom_reader SET default_transaction_read_only = on;
SQL
echo "bigdb: telecom database ready."
