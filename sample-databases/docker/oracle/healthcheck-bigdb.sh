#!/usr/bin/env bash
# Healthy = the database is open AND the first-start data load has finished.
# The load script drops a marker on the data volume; a volume loaded some other way counts as finished
# once QW_READER exists (creating it is the load's last step), and gets the marker then.
MARKER=/opt/oracle/oradata/.bigdb_loaded
healthcheck.sh || exit 1
[ -f "$MARKER" ] && exit 0
n=$(echo "SELECT COUNT(*) FROM dba_users WHERE username = 'QW_READER';" \
    | sqlplus -s "system/${ORACLE_PASSWORD}@//localhost:1521/FREEPDB1" | tr -dc '0-9')
[ "$n" = "1" ] && [ ! -f /tmp/load.sql ] && touch "$MARKER"
