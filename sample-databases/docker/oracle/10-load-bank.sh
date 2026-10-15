#!/usr/bin/env bash
# Runs once, on the first start with an empty data volume (container-entrypoint-initdb.d, after APP_USER exists).
# Generates the BANK schema, then creates the read-only QW_READER login Querywise uses.
set -euo pipefail
: "${APP_USER_PASSWORD:?Set APP_USER_PASSWORD for the BANK schema owner}"
: "${BIGDB_ORA_READER_PASSWORD:?Set BIGDB_ORA_READER_PASSWORD for the read-only QW_READER login}"

sed "s/c_scale CONSTANT NUMBER := 1;/c_scale CONSTANT NUMBER := ${BIGDB_SCALE:-1};/" /opt/bigdb/oracle_bank_insurance.sql > /tmp/load.sql
echo "bigdb: generating banking & insurance data at scale ${BIGDB_SCALE:-1} (about 15 minutes at scale 1)..."
sqlplus -s "${APP_USER}/${APP_USER_PASSWORD}@//localhost:1521/FREEPDB1" @/tmp/load.sql > /tmp/bigdb_load.log 2>&1 \
  || { tail -30 /tmp/bigdb_load.log; echo "bigdb: banking load FAILED"; exit 1; }
rm -f /tmp/load.sql

sqlplus -s "system/${ORACLE_PASSWORD}@//localhost:1521/FREEPDB1" > /dev/null <<SQL
WHENEVER SQLERROR EXIT FAILURE
CREATE USER QW_READER IDENTIFIED BY "${BIGDB_ORA_READER_PASSWORD}";
GRANT CREATE SESSION TO QW_READER;
BEGIN
  FOR t IN (SELECT table_name FROM dba_tables WHERE owner = UPPER('${APP_USER}')) LOOP
    EXECUTE IMMEDIATE 'GRANT SELECT ON "' || UPPER('${APP_USER}') || '"."' || t.table_name || '" TO QW_READER';
  END LOOP;
END;
/
EXIT
SQL
# The healthcheck reports healthy only once this marker exists (it lives on the data volume).
touch /opt/oracle/oradata/.bigdb_loaded
echo "bigdb: banking & insurance database ready."
