"""Read-only connectors. Each one tests connectivity, discovers tables/columns/keys, and runs validated SELECTs.

Every connector receives SQL that already passed `database.validate` for the source's discovered tables.
The connector then adds the engine's own read-only and timeout controls. Optional drivers are imported
lazily and fail with an install hint. Error messages are redacted: no URLs, passwords or API keys."""
import csv, importlib, re, sqlite3, threading, time
from contextlib import closing
from datetime import date, datetime
from pathlib import Path
from urllib.parse import quote, urlsplit, urlunsplit
import httpx
from .database import QueryRejected, ROW_LIMIT, TIMEOUT_SECONDS, FUNCTIONS, ROOT

FETCH = ROW_LIMIT + 1
HIDDEN_TABLES = {'qw_pack_history'}  # Migration ledgers are never exposed to analytics.
MAX_TABLES, MAX_FILE_BYTES = 200, 300 * 1024 * 1024
IDENTIFIER = re.compile(r'^[A-Za-z_][A-Za-z0-9_$]{0,127}$')

KINDS = {
    'sqlite': {'label': 'SQLite', 'dialect': 'sqlite', 'target': 'path', 'example': 'data/my-database.sqlite',
               'controls': 'Opened with mode=ro and query_only, a table/function authorizer, and a ~3 s progress-handler interrupt.'},
    'postgres': {'label': 'PostgreSQL', 'dialect': 'postgres', 'target': 'url', 'example': 'postgresql+psycopg://reader@localhost:5432/database',
                 'controls': 'READ ONLY transaction, 3 s statement_timeout, 1 s lock_timeout, search_path pinned, always rolled back.'},
    'mysql': {'label': 'MySQL', 'dialect': 'mysql', 'target': 'url', 'example': 'mysql+pymysql://reader@localhost:3306/database',
              'controls': 'START TRANSACTION READ ONLY, MAX_EXECUTION_TIME 3000 ms, always rolled back.'},
    'mariadb': {'label': 'MariaDB', 'dialect': 'mysql', 'target': 'url', 'example': 'mariadb+pymysql://reader@localhost:3307/database',
                'controls': 'START TRANSACTION READ ONLY, max_statement_time 3 s, always rolled back.'},
    'sqlserver': {'label': 'SQL Server', 'dialect': 'tsql', 'target': 'url', 'example': 'mssql+pyodbc://reader@localhost:1433/database?driver=ODBC+Driver+18+for+SQL+Server&Encrypt=yes',
                  'controls': 'SQL Server has no read-only transaction mode: relies on the SELECT validator, a db_datareader-only login, a 3 s ODBC query timeout, a 1 s lock timeout and rollback.'},
    'oracle': {'label': 'Oracle', 'dialect': 'oracle', 'target': 'url', 'example': 'oracle+oracledb://reader@localhost:1521/?service_name=FREEPDB1',
               'controls': 'SET TRANSACTION READ ONLY, 3 s driver call timeout, always rolled back.'},
    'db2': {'label': 'Db2 LUW', 'dialect': None, 'target': 'url', 'example': 'ibm_db_sa://reader@localhost:50000/DATABASE',
            'controls': 'Generic ANSI SQL dialect. Relies on the SELECT validator, a SELECT-only user and rollback; no driver-level timeout is set (use Db2 WLM limits).'},
    'mongodb': {'label': 'MongoDB', 'dialect': None, 'target': 'url', 'example': 'mongodb://reader@localhost:27017/?authSource=database',
                'controls': 'SQL is translated to an aggregation pipeline containing only $match/$group/$project/$sort/$skip/$limit (never $out/$merge), with maxTimeMS 3000.',
                'limits': 'MongoDB sources accept single-collection SELECTs with WHERE, GROUP BY, COUNT/SUM/AVG/MIN/MAX, ROUND, ORDER BY and LIMIT over top-level fields. Joins, subqueries, CTEs, window functions, HAVING and nested-array access are not translated.'},
    'elasticsearch': {'label': 'Elasticsearch', 'dialect': None, 'target': 'url', 'example': 'https://localhost:9200',
                      'controls': 'Queries go through the Elasticsearch SQL API, which is read-only, with request_timeout 3 s. Use an API key with read-only index privileges.',
                      'limits': 'Elasticsearch SQL: one index or alias per query (no joins). Quote index names containing "-" with double quotes. Nested-type fields and percentile/geo aggregations are not available.'},
    'excel': {'label': 'Excel / CSV', 'dialect': 'sqlite', 'target': 'path', 'example': 'pack/output/grants/grants-v2.xlsx',
              'controls': 'Workbook sheets or CSV files are loaded into an in-memory SQLite database with query_only, an authorizer and a ~3 s interrupt. Files are never written.',
              'limits': 'Each sheet (or CSV file) becomes one table; its first row is the header. Excel formulas are not evaluated: cached values saved by Excel are read. Relationships are not inferred.'},
    'parquet': {'label': 'Parquet', 'dialect': 'duckdb', 'target': 'path', 'example': 'pack/output/sensors/v2',
                'controls': 'Files are loaded into in-memory DuckDB, then file-system access and configuration are locked; queries are interrupted after ~3 s.',
                'limits': 'A file becomes one table; a folder registers each *.parquet file as a table. Data is loaded at connect time: re-select the source to reload changed files.'},
}

class ConnectionFailed(Exception):
    """Connection or discovery failure. The message is safe to show: no URL, password or API key."""

def require(module, package, label):
    try: return importlib.import_module(module)
    except ImportError as e:
        raise ConnectionFailed(f'The {label} connector needs the optional package "{package}", which is not installed. Install the connector drivers with: pip install -r requirements-connectors.txt') from e

def redact(error, *secrets):
    """First line of a driver error with credentials removed."""
    text = (str(error).strip() or type(error).__name__).splitlines()[0]
    for s in sorted({s for s in secrets if s and len(s) >= 3}, key=len, reverse=True): text = text.replace(s, '•••')
    text = re.sub(r'([a-z][a-z0-9+.-]*://)[^\s/@]+@', r'\1•••@', text, flags=re.I)
    return text[:300]

def resolve_path(value):
    if not value: raise ConnectionFailed('No file or folder path is configured for this source.')
    raw = str(value)
    for prefix in ('sqlite:///', 'file:///', 'file:'):
        if raw.lower().startswith(prefix): raw = raw[len(prefix):]
    path = Path(raw).expanduser()
    return path if path.is_absolute() else ROOT/path

def ident(name, fallback='column'):
    clean = re.sub(r'\W+', '_', str(name or '').strip().lower()).strip('_') or fallback
    return 'c_' + clean if clean[0].isdigit() else clean

def quoted(name): return '"' + str(name).replace('"', '""') + '"'

def keep(name, allowed):
    return name.lower() not in HIDDEN_TABLES and not name.lower().startswith('sqlite_') and (not allowed or name.lower() in allowed)

class Connector:
    kind, dialect = '', 'sqlite'
    def __init__(self, cfg):
        self.cfg, self.label, self.schema = cfg, KINDS[cfg['kind']]['label'], None
        self.allowed = {t.lower() for t in cfg.get('tables') or []}  # Optional registry subset.
    def test(self): raise NotImplementedError
    def discover(self): raise NotImplementedError
    def run(self, sql, tables): raise NotImplementedError
    def close(self): pass

# SQLite family ---------------------------------------------------------------------------------
def _authorize(tables):
    def authorizer(action, arg1, arg2, db, source):
        if action == sqlite3.SQLITE_SELECT: return sqlite3.SQLITE_OK
        if action == sqlite3.SQLITE_READ and (arg1 or '').lower() in tables: return sqlite3.SQLITE_OK
        if action == sqlite3.SQLITE_FUNCTION and (arg2 or '').upper() in FUNCTIONS: return sqlite3.SQLITE_OK
        return sqlite3.SQLITE_DENY
    return authorizer

def sqlite_run(conn, sql, tables):
    start = time.monotonic()
    conn.set_authorizer(_authorize(tables))
    conn.set_progress_handler(lambda: int(time.monotonic() - start > TIMEOUT_SECONDS), 1000)
    try:
        cur = conn.execute(sql); return [d[0] for d in cur.description], cur.fetchmany(FETCH)
    except sqlite3.Error as e:
        if 'interrupted' in str(e): raise QueryRejected(f'Query exceeded the {TIMEOUT_SECONDS}-second limit.') from e
        raise QueryRejected(f'Database rejected the query: {e}') from e
    finally: conn.set_authorizer(None); conn.set_progress_handler(None, 1000)

def sqlite_discover(conn, allowed=()):
    tables = []
    for name, kind in conn.execute("SELECT name, type FROM sqlite_master WHERE type IN ('table','view') ORDER BY name").fetchall():
        if not keep(name, allowed): continue
        columns = [{'name': c[1], 'type': c[2] or 'ANY', 'nullable': not c[3], 'primary_key': bool(c[5])} for c in conn.execute(f'PRAGMA table_info({quoted(name)})')]
        fks = [{'columns': [f[3]], 'table': f[2], 'references': [f[4] or 'id']} for f in conn.execute(f'PRAGMA foreign_key_list({quoted(name)})')]
        count = conn.execute(f'SELECT COUNT(*) FROM {quoted(name)}').fetchone()[0]
        tables.append({'name': name, 'kind': kind, 'columns': columns, 'foreign_keys': fks, 'row_count': count})
    return tables[:MAX_TABLES]

class SQLiteConnector(Connector):
    kind, dialect = 'sqlite', 'sqlite'
    def __init__(self, cfg):
        super().__init__(cfg); self.path = resolve_path(cfg.get('path') or cfg.get('url'))
    def connect(self):
        if not self.path.is_file():
            if self.cfg.get('sample'): raise ConnectionFailed('Sample database is missing. Run python scripts/seed.py first.')
            raise ConnectionFailed(f'SQLite file not found: {self.path}')
        conn = sqlite3.connect(f'{self.path.resolve().as_uri()}?mode=ro', uri=True, timeout=3, check_same_thread=False)
        conn.execute('PRAGMA query_only=ON'); return conn
    def test(self):
        try:
            with closing(self.connect()) as c: c.execute('SELECT COUNT(*) FROM sqlite_master').fetchone()
        except sqlite3.Error as e: raise ConnectionFailed(f'SQLite could not open the file: {e}') from e
    def discover(self):
        with closing(self.connect()) as c: return sqlite_discover(c, self.allowed)
    def run(self, sql, tables):
        try: conn = self.connect()
        except ConnectionFailed as e: raise QueryRejected(str(e)) from e
        with closing(conn): return sqlite_run(conn, sql, tables)

def _cell(value):
    if isinstance(value, datetime): return value.date().isoformat() if value.time() == datetime.min.time() else value.isoformat(sep=' ')
    if isinstance(value, date): return value.isoformat()
    return None if value == '' else value

def _typed(values):
    """Infer one SQLite type per column; CSV numbers arrive as text."""
    def number(v):
        if isinstance(v, (int, float)) and not isinstance(v, bool): return v
        try: return int(v)
        except (TypeError, ValueError):
            try: return float(v)
            except (TypeError, ValueError): return None
    present = [v for v in values if v is not None]
    numbers = [number(v) for v in present]
    if present and all(n is not None for n in numbers):
        kind = 'INTEGER' if all(isinstance(n, int) for n in numbers) else 'REAL'
        return kind, [None if v is None else number(v) for v in values]
    return 'TEXT', [None if v is None else str(v) for v in values]

class ExcelConnector(Connector):
    """Workbook sheets or CSV files, loaded into a read-only in-memory SQLite database."""
    kind, dialect = 'excel', 'sqlite'
    def __init__(self, cfg):
        super().__init__(cfg); self.path = resolve_path(cfg.get('path')); self.conn = None; self.lock = threading.Lock()
    def files(self):
        if self.path.is_dir(): files = sorted(p for p in self.path.iterdir() if p.suffix.lower() in {'.xlsx', '.xlsm', '.csv'} and not p.name.startswith('~$'))
        elif self.path.is_file(): files = [self.path]
        else: raise ConnectionFailed(f'Spreadsheet path not found: {self.path}')
        if not files: raise ConnectionFailed('No .xlsx, .xlsm or .csv files were found in the folder.')
        if sum(f.stat().st_size for f in files) > MAX_FILE_BYTES: raise ConnectionFailed('The spreadsheets are larger than 300 MB; load them into a database instead.')
        return files
    def sheets(self):
        for f in self.files():
            if f.suffix.lower() == '.csv':
                with open(f, newline='', encoding='utf-8-sig') as handle: rows = list(csv.reader(handle))
                yield f.stem, rows
                continue
            openpyxl = require('openpyxl', 'openpyxl', 'Excel')
            book = openpyxl.load_workbook(f, read_only=True, data_only=True)  # data_only: cached formula values.
            try:
                for sheet in book.worksheets: yield sheet.title, [list(r) for r in sheet.iter_rows(values_only=True)]
            finally: book.close()
    def load(self):
        conn, used = sqlite3.connect(':memory:', check_same_thread=False), set()
        try:
            for title, rows in self.sheets():
                rows = [r for r in rows if any(v not in (None, '') for v in r)]
                if not rows: continue
                name = ident(title, 'sheet')
                while name in used: name += '_2'
                used.add(name)
                headers, seen = [], set()
                for i, h in enumerate(rows[0]):
                    col = ident(h, f'column_{i + 1}')
                    while col in seen: col += '_2'
                    seen.add(col); headers.append(col)
                body = [[_cell(r[i]) if i < len(r) else None for i in range(len(headers))] for r in rows[1:]]
                typed = [_typed([row[i] for row in body]) for i in range(len(headers))]
                conn.execute(f'CREATE TABLE {quoted(name)} (' + ', '.join(f'{quoted(h)} {t[0]}' for h, t in zip(headers, typed)) + ')')
                conn.executemany(f'INSERT INTO {quoted(name)} VALUES ({",".join("?" * len(headers))})', [[t[1][j] for t in typed] for j in range(len(body))])
            conn.commit(); conn.execute('PRAGMA query_only=ON')
        except ConnectionFailed: conn.close(); raise
        except Exception as e:
            conn.close(); raise ConnectionFailed(f'The spreadsheet could not be read: {redact(e)}') from e
        if self.conn: self.conn.close()
        self.conn = conn
    def test(self):
        with self.lock: self.load()
    def discover(self):
        with self.lock:
            if not self.conn: self.load()
            return sqlite_discover(self.conn, self.allowed)
    def run(self, sql, tables):
        with self.lock:
            if not self.conn:
                try: self.load()
                except ConnectionFailed as e: raise QueryRejected(str(e)) from e
            return sqlite_run(self.conn, sql, tables)
    def close(self):
        if self.conn: self.conn.close(); self.conn = None

# DuckDB / Parquet ------------------------------------------------------------------------------
class ParquetConnector(Connector):
    kind, dialect = 'parquet', 'duckdb'
    def __init__(self, cfg):
        super().__init__(cfg); self.path = resolve_path(cfg.get('path')); self.con = None; self.lock = threading.Lock()
    def files(self):
        if self.path.is_dir(): files = {ident(p.stem, 'table'): p for p in sorted(self.path.glob('*.parquet'))}
        elif self.path.is_file(): files = {ident(self.cfg.get('table') or self.path.stem, 'table'): self.path}
        else: raise ConnectionFailed(f'Parquet path not found: {self.path}')
        if not files: raise ConnectionFailed('No .parquet files were found in the folder.')
        if sum(p.stat().st_size for p in files.values()) > MAX_FILE_BYTES: raise ConnectionFailed('The Parquet files are larger than 300 MB; query them with a dedicated engine instead.')
        return files
    def load(self):
        duckdb = require('duckdb', 'duckdb', 'Parquet')
        con = duckdb.connect(':memory:')
        try:
            for name, path in self.files().items():
                if not keep(name, self.allowed): continue
                con.execute(f"CREATE TABLE {quoted(name)} AS SELECT * FROM read_parquet('{str(path).replace(chr(39), chr(39) * 2)}')")
            # After loading, queries cannot reach the file system or change these settings.
            con.execute('SET enable_external_access=false'); con.execute('SET lock_configuration=true')
        except ConnectionFailed: con.close(); raise
        except Exception as e:
            con.close(); raise ConnectionFailed(f'DuckDB could not read the Parquet data: {redact(e)}') from e
        if self.con: self.con.close()
        self.con = con
    def test(self):
        with self.lock: self.load()
    def discover(self):
        with self.lock:
            if not self.con: self.load()
            tables = []
            for (name,) in self.con.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='main' ORDER BY 1").fetchall():
                columns = [{'name': c, 'type': t, 'nullable': n == 'YES', 'primary_key': False} for c, t, n in self.con.execute('SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_name=? ORDER BY ordinal_position', [name]).fetchall()]
                tables.append({'name': name, 'kind': 'table', 'columns': columns, 'foreign_keys': [], 'row_count': self.con.execute(f'SELECT COUNT(*) FROM {quoted(name)}').fetchone()[0]})
            return tables
    def run(self, sql, tables):
        duckdb = require('duckdb', 'duckdb', 'Parquet')
        with self.lock:
            if not self.con:
                try: self.load()
                except ConnectionFailed as e: raise QueryRejected(str(e)) from e
            cur = self.con.cursor(); timer = threading.Timer(TIMEOUT_SECONDS, cur.interrupt); timer.start()
            try:
                cur.execute(sql); return [d[0] for d in cur.description], cur.fetchmany(FETCH)
            except duckdb.Error as e:
                if 'interrupt' in str(e).lower(): raise QueryRejected(f'Query exceeded the {TIMEOUT_SECONDS}-second limit.') from e
                raise QueryRejected(f'DuckDB rejected the query: {redact(e)}') from e
            finally: timer.cancel(); cur.close()
    def close(self):
        if self.con: self.con.close(); self.con = None

# SQLAlchemy server engines ---------------------------------------------------------------------
SQLALCHEMY = {'postgres': {'postgresql'}, 'mysql': {'mysql'}, 'mariadb': {'mysql', 'mariadb'}, 'sqlserver': {'mssql'}, 'oracle': {'oracle'}, 'db2': {'ibm_db_sa', 'db2'}}
DRIVER_PACKAGES = {'psycopg': 'psycopg[binary]', 'psycopg2': 'psycopg2-binary', 'pymysql': 'PyMySQL', 'pyodbc': 'pyodbc', 'oracledb': 'oracledb', 'ibm_db': 'ibm_db', 'ibm_db_sa': 'ibm_db_sa', 'MySQLdb': 'mysqlclient'}

class SQLAlchemyConnector(Connector):
    def __init__(self, cfg):
        super().__init__(cfg)
        from sqlalchemy.engine import make_url
        self.kind, self.dialect = cfg['kind'], KINDS[cfg['kind']]['dialect']
        self.db_schema = cfg.get('schema') or None
        if self.db_schema and not IDENTIFIER.match(self.db_schema): raise ConnectionFailed('Schema names may contain only letters, digits, _ and $.')
        raw = cfg.get('url') or ''
        if not raw:
            hint = f' Environment variable {cfg["url_env"]} is not set.' if cfg.get('url_env') else ''
            raise ConnectionFailed(f'No connection URL is configured for this {self.label} source.{hint}')
        try: url = make_url(raw)
        except Exception as e: raise ConnectionFailed(f'The connection URL is not valid. Expected a form like {KINDS[self.kind]["example"]}') from e
        if url.get_backend_name() not in SQLALCHEMY[self.kind]: raise ConnectionFailed(f'This URL is for "{url.get_backend_name()}", not {self.label}.')
        if cfg.get('username'): url = url.set(username=cfg['username'])
        if cfg.get('password'): url = url.set(password=cfg['password'])
        self.url, self.secrets, self.engine = url, (raw, url.password or '', cfg.get('password') or ''), None
    def get_engine(self):
        if self.engine: return self.engine
        from sqlalchemy import create_engine
        args = {'postgres': {'connect_timeout': 5}, 'mysql': {'connect_timeout': 5, 'read_timeout': 15}, 'mariadb': {'connect_timeout': 5, 'read_timeout': 15},
                'sqlserver': {'timeout': 5}, 'oracle': {'tcp_connect_timeout': 5}}.get(self.kind, {})
        try: self.engine = create_engine(self.url, pool_pre_ping=True, pool_size=2, max_overflow=0, connect_args=args)
        except ImportError as e:
            package = DRIVER_PACKAGES.get((e.name or '').split('.')[0], e.name or 'driver')
            raise ConnectionFailed(f'The {self.label} connector needs the optional package "{package}", which is not installed. Install the connector drivers with: pip install -r requirements-connectors.txt') from e
        except Exception as e: raise ConnectionFailed(f'{self.label} connection could not be configured: {redact(e, *self.secrets)}') from e
        return self.engine
    def error(self, e): return redact(getattr(e, 'orig', None) or e, *self.secrets)
    def probe(self): return {'oracle': 'SELECT 1 FROM DUAL', 'db2': 'SELECT 1 FROM SYSIBM.SYSDUMMY1'}.get(self.kind, 'SELECT 1')
    def guards(self):
        s = self.db_schema
        return {'postgres': ['SET TRANSACTION READ ONLY', f"SET LOCAL statement_timeout = '{TIMEOUT_SECONDS * 1000}ms'", "SET LOCAL lock_timeout = '1000ms'", f'SET LOCAL search_path TO {quoted(s or "public")}, pg_catalog'],
                'mysql': [f'SET SESSION MAX_EXECUTION_TIME={TIMEOUT_SECONDS * 1000}', 'START TRANSACTION READ ONLY'],
                'mariadb': [f'SET SESSION max_statement_time={TIMEOUT_SECONDS}', 'START TRANSACTION READ ONLY'],
                'sqlserver': ['SET LOCK_TIMEOUT 1000'],
                'oracle': ([f'ALTER SESSION SET CURRENT_SCHEMA = {s}'] if s else []) + ['SET TRANSACTION READ ONLY'],
                'db2': [f'SET SCHEMA {s}'] if s else []}[self.kind]
    def driver_timeout(self, conn):
        raw = conn.connection.dbapi_connection
        if self.kind == 'sqlserver': raw.timeout = TIMEOUT_SECONDS          # pyodbc query timeout (seconds)
        if self.kind == 'oracle': raw.call_timeout = TIMEOUT_SECONDS * 1000  # python-oracledb round-trip timeout (ms)
    def test(self):
        engine = self.get_engine()
        try:
            with engine.connect() as c: c.exec_driver_sql(self.probe()).scalar()
        except ConnectionFailed: raise
        except Exception as e: raise ConnectionFailed(f'{self.label} connection failed: {self.error(e)}') from e
    def discover(self):
        from sqlalchemy import inspect
        try:
            insp = inspect(self.get_engine())
            names = [(n, 'table') for n in insp.get_table_names(schema=self.db_schema)] + [(n, 'view') for n in insp.get_view_names(schema=self.db_schema)]
            tables = []
            for name, kind in names:
                if not keep(name, self.allowed): continue
                columns = []
                try: pk = set(insp.get_pk_constraint(name, schema=self.db_schema).get('constrained_columns') or [])
                except Exception: pk = set()
                for c in insp.get_columns(name, schema=self.db_schema):
                    try: typ = str(c['type'])
                    except Exception: typ = type(c['type']).__name__.upper()
                    columns.append({'name': c['name'], 'type': typ, 'nullable': bool(c.get('nullable', True)), 'primary_key': c['name'] in pk})
                try: fks = [{'columns': f['constrained_columns'], 'table': f['referred_table'], 'references': f['referred_columns']} for f in insp.get_foreign_keys(name, schema=self.db_schema)]
                except Exception: fks = []
                tables.append({'name': name, 'kind': kind, 'columns': columns, 'foreign_keys': fks, 'row_count': None})
                if len(tables) >= MAX_TABLES: break
            return tables
        except ConnectionFailed: raise
        except Exception as e: raise ConnectionFailed(f'{self.label} schema discovery failed: {self.error(e)}') from e
    def run(self, sql, tables):
        try: engine = self.get_engine()
        except ConnectionFailed as e: raise QueryRejected(str(e)) from e
        try:
            with engine.connect() as conn:
                trans = conn.begin()
                try:
                    for statement in self.guards(): conn.exec_driver_sql(statement)
                    self.driver_timeout(conn)
                    options = {'no_parameters': True, 'stream_results': self.kind == 'postgres'}
                    result = conn.execution_options(**options).exec_driver_sql(sql)
                    columns, rows = list(result.keys()), result.fetchmany(FETCH); result.close()
                    return columns, rows
                finally: trans.rollback()  # Nothing a query does is ever committed.
        except Exception as e:
            raise QueryRejected(f'{self.label} rejected the query or it exceeded the {TIMEOUT_SECONDS}-second limit: {self.error(e)}') from e
    def close(self):
        if self.engine: self.engine.dispose(); self.engine = None

# MongoDB ---------------------------------------------------------------------------------------
def _bson_type(value):
    if isinstance(value, bool): return 'BOOLEAN'
    if isinstance(value, int): return 'BIGINT'
    if isinstance(value, float): return 'DOUBLE'
    if isinstance(value, str): return 'TEXT'
    if isinstance(value, (datetime, date)): return 'TIMESTAMP'
    if isinstance(value, dict): return 'OBJECT'
    if isinstance(value, list): return 'ARRAY'
    return type(value).__name__.upper()  # ObjectId, Decimal128…

class MongoConnector(Connector):
    kind, dialect = 'mongodb', None
    def __init__(self, cfg):
        super().__init__(cfg)
        url = cfg.get('url') or ''
        if not url: raise ConnectionFailed('No MongoDB connection URL is configured.' + (f' Environment variable {cfg["url_env"]} is not set.' if cfg.get('url_env') else ''))
        parts = urlsplit(url)
        if parts.scheme not in {'mongodb', 'mongodb+srv'}: raise ConnectionFailed('MongoDB URLs start with mongodb:// or mongodb+srv://')
        if cfg.get('username'):
            host = parts.netloc.rsplit('@', 1)[-1]
            auth = quote(cfg['username'], safe='') + (':' + quote(cfg['password'], safe='') if cfg.get('password') else '')
            url = urlunsplit((parts.scheme, f'{auth}@{host}', parts.path, parts.query, parts.fragment))
        self.url, self.secrets, self.client = url, (cfg.get('url') or '', cfg.get('password') or '', parts.password or ''), None
        self.database = cfg.get('database') or parts.path.strip('/') or None
    def db(self):
        pymongo = require('pymongo', 'pymongo', 'MongoDB')
        if not self.client: self.client = pymongo.MongoClient(self.url, serverSelectionTimeoutMS=5000, connectTimeoutMS=5000, socketTimeoutMS=15000)
        if not self.database: raise ConnectionFailed('Set the MongoDB database name (in the URL path or the Database field).')
        return self.client[self.database]
    def test(self):
        db = self.db()
        try: self.client.admin.command('ping'); db.list_collection_names()
        except Exception as e: raise ConnectionFailed(f'MongoDB connection failed: {redact(e, *self.secrets)}') from e
    def discover(self):
        db = self.db(); tables = []
        try:
            for name in sorted(db.list_collection_names()):
                if name.startswith('system.') or not keep(name, self.allowed): continue
                fields = {'_id': 'NULL'}  # Keeps _id first; its real type comes from the sampled documents.
                for doc in db[name].find({}, limit=200):
                    for key, value in doc.items():
                        if value is not None and (key not in fields or fields[key] == 'NULL'): fields[key] = _bson_type(value)
                        fields.setdefault(key, 'NULL')
                columns = [{'name': k, 'type': t, 'nullable': k != '_id', 'primary_key': k == '_id'} for k, t in fields.items()]
                tables.append({'name': name, 'kind': 'collection', 'columns': columns, 'foreign_keys': [], 'row_count': db[name].estimated_document_count()})
        except ConnectionFailed: raise
        except Exception as e: raise ConnectionFailed(f'MongoDB schema discovery failed: {redact(e, *self.secrets)}') from e
        return tables[:MAX_TABLES]
    def run(self, sql, tables):
        from .mongo_sql import translate
        fields = {t['name'].lower(): [c['name'] for c in t['columns']] for t in (self.schema or {}).get('tables', [])}
        collection, pipeline, columns = translate(sql, fields, FETCH)
        try:
            db = self.db(); rows = []
            for doc in db[collection].aggregate(pipeline, maxTimeMS=TIMEOUT_SECONDS * 1000):
                rows.append([doc.get(c) for c in columns])
                if len(rows) >= FETCH: break
            return columns, rows
        except ConnectionFailed as e: raise QueryRejected(str(e)) from e
        except Exception as e:
            if type(e).__name__ == 'ExecutionTimeout': raise QueryRejected(f'Query exceeded the {TIMEOUT_SECONDS}-second limit.') from e
            raise QueryRejected(f'MongoDB rejected the query: {redact(e, *self.secrets)}') from e
    def close(self):
        if self.client: self.client.close(); self.client = None

# Elasticsearch ---------------------------------------------------------------------------------
def _flatten(properties, prefix=''):
    for name, spec in (properties or {}).items():
        path = prefix + name
        if 'properties' in spec and spec.get('type') in (None, 'object'): yield from _flatten(spec['properties'], path + '.')
        else: yield path, spec.get('type', 'object').upper()

class ElasticsearchConnector(Connector):
    kind, dialect = 'elasticsearch', None
    transport = None  # Tests replace this with httpx.MockTransport.
    def __init__(self, cfg):
        super().__init__(cfg)
        self.url = (cfg.get('url') or '').rstrip('/')
        if not self.url: raise ConnectionFailed('No Elasticsearch URL is configured.' + (f' Environment variable {cfg["url_env"]} is not set.' if cfg.get('url_env') else ''))
        if not self.url.startswith(('http://', 'https://')): raise ConnectionFailed('Elasticsearch URLs start with http:// or https://')
        self.headers = {'Authorization': 'ApiKey ' + cfg['api_key']} if cfg.get('api_key') else {}
        self.auth = (cfg['username'], cfg.get('password') or '') if cfg.get('username') and not cfg.get('api_key') else None
        self.verify = cfg.get('ca_cert') or (cfg.get('verify_tls') is not False)
        self.secrets = (self.url, cfg.get('api_key') or '', cfg.get('password') or '')
    def request(self, method, path, **kwargs):
        try:
            with httpx.Client(base_url=self.url, headers=self.headers, auth=self.auth, verify=self.verify, transport=self.transport, timeout=httpx.Timeout(TIMEOUT_SECONDS + 5, connect=5)) as client:
                r = client.request(method, path, **kwargs)
        except httpx.HTTPError as e: raise ConnectionFailed(f'Cannot reach Elasticsearch: {redact(e, *self.secrets)}') from e
        if r.status_code == 401: raise ConnectionFailed('Elasticsearch rejected the credentials (401). Check the API key or username/password.')
        if r.status_code == 403: raise ConnectionFailed('The Elasticsearch credentials lack the read privileges for this request (403).')
        return r
    def test(self):
        r = self.request('GET', '/')
        if r.status_code != 200 or 'version' not in r.json(): raise ConnectionFailed(f'The URL did not answer like Elasticsearch (HTTP {r.status_code}).')
    def discover(self):
        # _resolve/index lists only what the caller may see and needs index-level view_index_metadata,
        # unlike _cat/indices (cluster:monitor/state). Counts use _count (index-level read).
        resolved = self.request('GET', '/_resolve/index/*', params={'expand_wildcards': 'open'})
        if resolved.status_code != 200: raise ConnectionFailed(f'Elasticsearch could not list indices (HTTP {resolved.status_code}).')
        data = resolved.json()
        names = {i['name']: 'index' for i in data.get('indices', [])} | {a['name']: 'alias' for a in data.get('aliases', [])} | {d['name']: 'data stream' for d in data.get('data_streams', [])}
        tables = []
        for name in sorted(names):
            if name.startswith('.') or not keep(name, self.allowed): continue
            mapping = self.request('GET', f'/{quote(name, safe="")}/_mapping').json()
            props = next(iter(mapping.values()), {}).get('mappings', {}).get('properties', {}) if mapping else {}
            columns = [{'name': c, 'type': t, 'nullable': True, 'primary_key': False} for c, t in _flatten(props)]
            count = self.request('GET', f'/{quote(name, safe="")}/_count')
            tables.append({'name': name, 'kind': names[name], 'columns': columns, 'foreign_keys': [], 'row_count': count.json().get('count') if count.status_code == 200 else None})
            if len(tables) >= MAX_TABLES: break
        return tables
    def run(self, sql, tables):
        body = {'query': sql, 'fetch_size': FETCH, 'request_timeout': f'{TIMEOUT_SECONDS}s', 'page_timeout': f'{TIMEOUT_SECONDS}s'}
        try: r = self.request('POST', '/_sql', params={'format': 'json'}, json=body)
        except ConnectionFailed as e: raise QueryRejected(str(e)) from e
        if r.status_code != 200:
            reason = (r.json().get('error') or {}).get('reason', f'HTTP {r.status_code}') if 'json' in r.headers.get('content-type', '') else f'HTTP {r.status_code}'
            raise QueryRejected(f'Elasticsearch rejected the query: {redact(reason, *self.secrets)}')
        data = r.json()
        if data.get('cursor'):
            try: self.request('POST', '/_sql/close', json={'cursor': data['cursor']})
            except ConnectionFailed: pass
            data['rows'] = data['rows'][:ROW_LIMIT] + [None]  # Marks truncation: more rows exist than were fetched.
        return [c['name'] for c in data['columns']], data['rows']

CONNECTORS = {'sqlite': SQLiteConnector, 'excel': ExcelConnector, 'parquet': ParquetConnector, 'mongodb': MongoConnector, 'elasticsearch': ElasticsearchConnector,
              **{k: SQLAlchemyConnector for k in SQLALCHEMY}}

def build(cfg):
    if cfg.get('kind') not in CONNECTORS: raise ConnectionFailed(f'Unknown source kind "{cfg.get("kind")}".')
    return CONNECTORS[cfg['kind']](cfg)
