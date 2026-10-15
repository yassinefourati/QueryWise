# Banking & insurance database (40 tables, 1999 -> today). The data is generated inside the database on the
# container's first start (database creation plus about 15 minutes at scale 1); later starts reuse the data volume.
FROM gvenzl/oracle-free:23-slim
COPY sample-databases/oracle_bank_insurance.sql /opt/bigdb/oracle_bank_insurance.sql
COPY sample-databases/docker/oracle/10-load-bank.sh /container-entrypoint-initdb.d/10-load-bank.sh
COPY sample-databases/docker/oracle/healthcheck-bigdb.sh /opt/bigdb/healthcheck-bigdb.sh
ENV APP_USER=BANK \
    BIGDB_SCALE=1
HEALTHCHECK --interval=30s --timeout=10s --start-period=40m --retries=10 CMD ["bash", "/opt/bigdb/healthcheck-bigdb.sh"]
