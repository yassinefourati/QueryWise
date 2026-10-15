# Telecom & supply chain database (40 tables, 1999 -> today). The data is generated inside the database on the
# container's first start (about 7 minutes at scale 1); later starts reuse the data volume.
FROM postgres:16-alpine
COPY sample-databases/postgres_telecom_supply.sql /opt/bigdb/postgres_telecom_supply.sql
COPY sample-databases/docker/postgres/10-load-telecom.sh /docker-entrypoint-initdb.d/10-load-telecom.sh
ENV POSTGRES_USER=telecom_owner \
    POSTGRES_DB=telecom_db \
    BIGDB_SCALE=1
