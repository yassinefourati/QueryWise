"""Local app-state database (git-ignored): sources, provider settings, encrypted secrets, query history.

Secrets are encrypted at rest with Fernet. The key comes from QUERYWISE_SECRET_KEY (a passphrase,
stretched with PBKDF2 and a per-install salt) or, when that is unset, from a generated key file that
lives next to the database. Plaintext secrets never leave this module except to build connections."""
import base64, hashlib, hmac, json, os, secrets, sqlite3, threading, time
from contextlib import contextmanager
from pathlib import Path
from cryptography.fernet import Fernet, InvalidToken
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = '''CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, secret INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS sources (id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL, config TEXT NOT NULL, secrets TEXT, created_at REAL NOT NULL);
CREATE TABLE IF NOT EXISTS schemas (source_id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, schema TEXT NOT NULL, discovered_at REAL NOT NULL);
CREATE TABLE IF NOT EXISTS queries (id INTEGER PRIMARY KEY AUTOINCREMENT, list TEXT NOT NULL CHECK (list IN ('history','saved')), entry TEXT NOT NULL, created_at REAL NOT NULL);'''
LIMITS = {'history': 40, 'saved': 50}

class SecretUnavailable(RuntimeError): pass

def mask(value):
    """Show only the last four characters of long secrets, nothing of short ones."""
    if not value: return ''
    return '••••' + value[-4:] if len(value) >= 12 else '••••'

class State:
    def __init__(self, directory=None):
        self.dir = Path(directory or os.getenv('QUERYWISE_STATE_DIR') or ROOT/'.querywise')
        self.dir.mkdir(parents=True, exist_ok=True)
        self.path = self.dir/'state.db'
        self.lock = threading.RLock(); self._fernet = None
        with self.db() as c: c.executescript(SCHEMA)

    @contextmanager
    def db(self):
        with self.lock:
            c = sqlite3.connect(self.path, timeout=5); c.row_factory = sqlite3.Row
            try:
                yield c; c.commit()
            finally: c.close()

    # Encryption -----------------------------------------------------------------------------
    def fernet(self):
        if self._fernet: return self._fernet
        passphrase = os.getenv('QUERYWISE_SECRET_KEY', '')
        if passphrase:
            with self.db() as c:
                row = c.execute("SELECT value FROM settings WHERE key='kdf_salt'").fetchone()
                salt = row['value'] if row else base64.b64encode(secrets.token_bytes(16)).decode()
                if not row: c.execute("INSERT INTO settings (key, value) VALUES ('kdf_salt', ?)", (salt,))
            kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=base64.b64decode(salt), iterations=600_000)
            key = base64.urlsafe_b64encode(kdf.derive(passphrase.encode()))
        else:
            path = self.dir/'secret.key'
            if not path.exists():
                try:
                    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                    with os.fdopen(fd, 'wb') as f: f.write(Fernet.generate_key())
                except FileExistsError: pass
            key = path.read_bytes().strip()
        self._fernet, self._key = Fernet(key), key
        return self._fernet

    def fingerprint(self, material: bytes) -> str:
        """Keyed hash: detects changed connection settings without storing a guessable digest of secrets."""
        self.fernet(); return hmac.new(self._key, material, hashlib.sha256).hexdigest()

    def encrypt(self, data: dict) -> str:
        return self.fernet().encrypt(json.dumps(data).encode()).decode()

    def decrypt(self, token: str) -> dict:
        if not token: return {}
        try: return json.loads(self.fernet().decrypt(token.encode()))
        except InvalidToken as e:
            raise SecretUnavailable('A stored secret cannot be decrypted with the current key (QUERYWISE_SECRET_KEY or .querywise/secret.key changed). Re-enter it in Settings.') from e

    # Settings -------------------------------------------------------------------------------
    def get(self, key, default=None):
        with self.db() as c: row = c.execute('SELECT value, secret FROM settings WHERE key=?', (key,)).fetchone()
        if not row: return default
        return self.decrypt(row['value'])['v'] if row['secret'] else row['value']

    def put(self, key, value, secret=False):
        stored = self.encrypt({'v': value}) if secret else value
        with self.db() as c: c.execute('INSERT INTO settings (key, value, secret) VALUES (?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, secret=excluded.secret', (key, stored, int(secret)))

    def delete(self, key):
        with self.db() as c: c.execute('DELETE FROM settings WHERE key=?', (key,))

    # Sources --------------------------------------------------------------------------------
    def sources(self):
        with self.db() as c: rows = c.execute('SELECT * FROM sources ORDER BY created_at').fetchall()
        return [{'id': r['id'], 'name': r['name'], 'kind': r['kind'], 'config': json.loads(r['config']), 'secrets_token': r['secrets']} for r in rows]

    def save_source(self, source_id, name, kind, config, secret_values):
        token = self.encrypt(secret_values) if secret_values else None
        with self.db() as c:
            c.execute('INSERT INTO sources (id, name, kind, config, secrets, created_at) VALUES (?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name, kind=excluded.kind, config=excluded.config, secrets=excluded.secrets',
                      (source_id, name, kind, json.dumps(config), token, time.time()))
            c.execute('DELETE FROM schemas WHERE source_id=?', (source_id,))

    def delete_source(self, source_id):
        with self.db() as c:
            c.execute('DELETE FROM sources WHERE id=?', (source_id,)); c.execute('DELETE FROM schemas WHERE source_id=?', (source_id,))

    def cached_schema(self, source_id, fingerprint):
        with self.db() as c: row = c.execute('SELECT * FROM schemas WHERE source_id=? AND fingerprint=?', (source_id, fingerprint)).fetchone()
        return (json.loads(row['schema']), row['discovered_at']) if row else (None, None)

    def cache_schema(self, source_id, fingerprint, schema):
        with self.db() as c: c.execute('INSERT INTO schemas VALUES (?,?,?,?) ON CONFLICT(source_id) DO UPDATE SET fingerprint=excluded.fingerprint, schema=excluded.schema, discovered_at=excluded.discovered_at', (source_id, fingerprint, json.dumps(schema), time.time()))

    # History and saved queries --------------------------------------------------------------
    def queries(self, name):
        with self.db() as c: rows = c.execute('SELECT id, entry FROM queries WHERE list=? ORDER BY id DESC', (name,)).fetchall()
        return [{**json.loads(r['entry']), 'id': r['id']} for r in rows]

    def add_query(self, name, entry):
        with self.db() as c:
            cur = c.execute('INSERT INTO queries (list, entry, created_at) VALUES (?,?,?)', (name, json.dumps(entry), time.time()))
            c.execute('DELETE FROM queries WHERE list=? AND id NOT IN (SELECT id FROM queries WHERE list=? ORDER BY id DESC LIMIT ?)', (name, name, LIMITS[name]))
            return cur.lastrowid

    def delete_query(self, query_id):
        with self.db() as c: c.execute('DELETE FROM queries WHERE id=?', (query_id,))

    def clear_queries(self, name):
        with self.db() as c: c.execute('DELETE FROM queries WHERE list=?', (name,))
