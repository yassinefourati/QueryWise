#!/bin/bash
# Runs inside the Db2 container after setup. Db2 authenticates operating-system users, so the
# read-only Querywise account is an OS user; its table grants are issued later by provision.py.
set -e
id qwreader >/dev/null 2>&1 || useradd -M -s /sbin/nologin qwreader
echo "qwreader:${QW_READER_PASSWORD}" | chpasswd
