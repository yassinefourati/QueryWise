"""Provision every engine in compose.test.yaml: pack migrations + seed as the migrator, then read-only accounts.
Also `--verify-all` runs the pack's verify_all with the migrator URLs. Output never contains passwords."""
import json, os, subprocess, sys, time
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT), str(ROOT/'pack')]
import httpx
from sqlalchemy import create_engine, text
from tests.live_config import ADMIN, READER, SQL_ENGINES, MONGO_ADMIN, ES_URL, ES_ADMIN, ES_KEY_FILE, ES_INDICES
from tools.models import model

RESULTS = Path(os.environ.get('QW_RESULTS', ROOT/'test-results'))
status = {}

def clean(message):
    text_ = str(message)
    for secret in (ADMIN, READER):
        if secret: text_ = text_.replace(secret, '•••')
    return text_

def step(name, fn):
    start = time.monotonic()
    try:
        fn(); status[name] = {'status': 'PASS', 'seconds': round(time.monotonic() - start, 1)}
    except Exception as e:
        status[name] = {'status': 'FAIL', 'seconds': round(time.monotonic() - start, 1), 'error': clean(f'{type(e).__name__}: {e}')[-1500:]}
    print(f'[provision] {name}: {status[name]["status"]} ({status[name]["seconds"]} s)' + (f'\n    {status[name]["error"]}' if 'error' in status[name] else ''), flush=True)

def retry(fn, tries=30, wait=5):
    for attempt in range(tries):
        try: return fn()
        except Exception:
            if attempt == tries - 1: raise
            time.sleep(wait)

def pack_env():
    env = dict(os.environ)
    for kind, cfg in SQL_ENGINES.items(): env[f'PACK_{kind.upper()}_URL'] = cfg['admin']
    env.update(PACK_MONGODB_URL=MONGO_ADMIN, PACK_ELASTICSEARCH_URL=ES_ADMIN, PACK_ORACLE_SCHEMA='QW_COMPLEX', PACK_DB2_SCHEMA='DB2INST1')
    return env

def pack(*args):
    r = subprocess.run([sys.executable, '-m', *args], cwd=ROOT/'pack', env=pack_env(), capture_output=True, text=True, timeout=1800)
    if r.returncode: raise RuntimeError(clean((r.stdout + r.stderr)[-1200:]))
    return r.stdout

def execute(url, statements, autocommit=False):
    engine = create_engine(url, isolation_level='AUTOCOMMIT') if autocommit else create_engine(url)
    try:
        with (engine.connect() if autocommit else engine.begin()) as c:
            # no_parameters: literal % (MySQL host patterns) must not be read as a format placeholder.
            for s in statements: c.execution_options(no_parameters=True).exec_driver_sql(s)
    finally: engine.dispose()

def tables(kind): return list(model(kind)['data'])

def readers(kind):
    t, pw = tables(kind), READER
    if kind == 'postgres':
        execute(SQL_ENGINES[kind]['admin'], [f"CREATE ROLE qw_app LOGIN PASSWORD '{pw}'", 'GRANT USAGE ON SCHEMA public TO qw_app',
                                             *[f'GRANT SELECT ON {x} TO qw_app' for x in t], 'ALTER ROLE qw_app SET default_transaction_read_only = on'])
    elif kind in ('mysql', 'mariadb'):
        db = SQL_ENGINES[kind]['admin'].rsplit('/', 1)[1]
        execute(SQL_ENGINES[kind]['admin'], [f"CREATE USER IF NOT EXISTS 'qw_app'@'%' IDENTIFIED BY '{pw}'", *[f"GRANT SELECT ON {db}.{x} TO 'qw_app'@'%'" for x in t]])
    elif kind == 'sqlserver':
        execute(SQL_ENGINES[kind]['master'], [f"IF SUSER_ID('qw_app') IS NULL CREATE LOGIN qw_app WITH PASSWORD = '{pw}'"], autocommit=True)
        execute(SQL_ENGINES[kind]['admin'], ["IF USER_ID('qw_app') IS NULL CREATE USER qw_app FOR LOGIN qw_app", *[f'GRANT SELECT ON OBJECT::dbo.{x} TO qw_app' for x in t]], autocommit=True)
    elif kind == 'oracle':
        execute(SQL_ENGINES[kind]['dba'], [f'CREATE USER IF NOT EXISTS QW_READER IDENTIFIED BY "{pw}"', 'GRANT CREATE SESSION TO QW_READER',
                                           *[f'GRANT SELECT ON QW_COMPLEX.{x} TO QW_READER' for x in t]], autocommit=True)
    elif kind == 'db2':
        execute(SQL_ENGINES[kind]['admin'], ['GRANT CONNECT ON DATABASE TO USER QWREADER', *[f'GRANT SELECT ON DB2INST1.{x} TO USER QWREADER' for x in t]])  # ibm_db_sa has no AUTOCOMMIT level

def sql_engine(kind):
    def run():
        if kind == 'sqlserver': retry(lambda: execute(SQL_ENGINES[kind]['master'], ["IF DB_ID('qw_complex_clinic') IS NULL CREATE DATABASE qw_complex_clinic"], autocommit=True))
        retry(lambda: execute(SQL_ENGINES[kind]['admin'], ['SELECT 1 FROM SYSIBM.SYSDUMMY1' if kind == 'db2' else 'SELECT 1 FROM DUAL' if kind == 'oracle' else 'SELECT 1']), tries=40)
        # In-process (not the CLI) so a failure shows the real driver error, with passwords removed by step().
        from tools.sql_runner import connect, migrate, seed
        os.environ.update(pack_env()); engine = connect(kind)
        try: migrate(engine, kind, 2); seed(engine, kind, 1)
        finally: engine.dispose()
        readers(kind)
    return run

def mongodb():
    pack('tools.mongo_runner', 'migrate', '--allow-write', '--target', '1')
    pack('tools.mongo_runner', 'seed', '--allow-write')
    pack('tools.mongo_runner', 'migrate', '--allow-write')
    from pymongo import MongoClient
    with MongoClient(MONGO_ADMIN, serverSelectionTimeoutMS=10000) as client:
        db = client['qw_complex_learning']
        if not db.command('usersInfo', 'qw_app')['users']:
            db.command('createUser', 'qw_app', pwd=READER, roles=[{'role': 'read', 'db': 'qw_complex_learning'}])

def elasticsearch():
    pack('tools.elastic_runner', 'migrate', '--allow-write', '--target', '1')
    pack('tools.elastic_runner', 'seed', '--allow-write')
    pack('tools.elastic_runner', 'migrate', '--allow-write')
    # Scoped reader key, from pack/elasticsearch/reader_privileges.json plus the read alias.
    # cluster:monitor/main is part of Elasticsearch's documented minimal role for SQL access.
    body = {'name': 'querywise-live-reader', 'role_descriptors': {'qw_reader': {'cluster': ['cluster:monitor/main'], 'indices': [{'names': ES_INDICES, 'privileges': ['read', 'view_index_metadata']}]}}}
    r = httpx.post(ES_URL + '/_security/api_key', json=body, auth=('elastic', ADMIN), timeout=30); r.raise_for_status()
    Path(ES_KEY_FILE).parent.mkdir(parents=True, exist_ok=True); Path(ES_KEY_FILE).write_text(r.json()['encoded'])
    os.chmod(ES_KEY_FILE, 0o600)
    # Native reader user with the same role, for the app container (username + password from its environment).
    r = httpx.put(ES_URL + '/_security/role/qw_reader', json=body['role_descriptors']['qw_reader'], auth=('elastic', ADMIN), timeout=30); r.raise_for_status()
    r = httpx.put(ES_URL + '/_security/user/qw_reader', json={'password': READER, 'roles': ['qw_reader']}, auth=('elastic', ADMIN), timeout=30); r.raise_for_status()

def files():
    pack('tools.sql_runner', 'sqlite', 'migrate', '--allow-write'); pack('tools.sql_runner', 'sqlite', 'seed', '--allow-write')
    if not (ROOT/'pack/output/sensors/v1').exists(): pack('tools.parquet_runner', 'seed')
    if not (ROOT/'pack/output/sensors/v2').exists(): pack('tools.parquet_runner', 'migrate')

def verify_all():
    r = subprocess.run([sys.executable, '-m', 'tools.verify_all'], cwd=ROOT/'pack', env=pack_env(), capture_output=True, text=True, timeout=1800)
    print(clean(r.stdout)); print(clean(r.stderr), file=sys.stderr)
    (RESULTS/'verify_all.json').write_text((ROOT/'pack/reports/live-results.json').read_text())
    return r.returncode

if __name__ == '__main__':
    RESULTS.mkdir(parents=True, exist_ok=True)
    if '--verify-all' in sys.argv: sys.exit(verify_all())
    step('files: sqlite + parquet', files)
    for kind in SQL_ENGINES: step(kind, sql_engine(kind))
    step('mongodb', mongodb)
    step('elasticsearch', elasticsearch)
    (RESULTS/'provision.json').write_text(json.dumps(status, indent=2))
    sys.exit(int(any(s['status'] != 'PASS' for s in status.values())))
