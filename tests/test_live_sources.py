"""Live app tests against every engine in compose.test.yaml (run by scripts/live/run_all.sh after provision.py).
Skipped unless QW_LIVE=1. Each test drives the real API: test the connection, switch, discover, query, and check guards."""
import json, os, time
from decimal import Decimal
from pathlib import Path
import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.connectors import build
from backend.database import QueryRejected, ROOT
from backend.sources import registry
from tests.live_config import ADMIN, READER, SQL_ENGINES, MONGO_READER, ES_URL, ES_KEY_FILE

pytestmark = pytest.mark.skipif(os.getenv('QW_LIVE') != '1', reason='Live engines run only inside compose.test.yaml')
client = TestClient(app, base_url='http://localhost', headers={'X-Querywise-Client': '1'})
RO_TRANSACTION = {'postgres', 'mysql', 'mariadb', 'oracle'}  # Engines whose guard blocks writes even for an admin login.
NO_TIMEOUT = {'db2'}                                          # Documented: no driver-level timeout.

@pytest.fixture(autouse=True)
def back_to_sample():
    yield
    client.post('/api/sources/sample/select')

def no_secrets(text):
    assert ADMIN not in text and READER not in text and 'Wr0ngPassw0rdX' not in text

def connect(**body):
    r = client.post('/api/sources', json=body); assert r.status_code == 201, r.text
    sid = r.json()['id']
    r = client.post(f'/api/sources/{sid}/select'); assert r.status_code == 200, r.text
    no_secrets(r.text)
    return sid

def query(sql):
    r = client.post('/api/query', json={'sql': sql}); no_secrets(r.text)
    return r

def close(a, b):
    if a is None or b is None: return a is b
    if isinstance(b, (int, float)) and isinstance(a, (int, float, str, Decimal)):
        return abs(float(a) - float(b)) <= 1e-6 * max(1, abs(float(b)))
    return str(a).lower() == str(b).lower() if isinstance(b, str) else a == b

def check_questions(kind):
    """Every pack question for this engine must reproduce the SQLite reference results exactly (numeric tolerance)."""
    expected = json.loads((ROOT/f'pack/{kind}/expected_results.scale1.json').read_text(encoding='utf-8'))
    questions = json.loads((ROOT/f'pack/{kind}/questions.json').read_text(encoding='utf-8'))
    failures = []
    for q in questions:
        r = query(q['sql'])
        if r.status_code != 200: failures.append(f'{q["id"]}: HTTP {r.status_code} {r.json()["detail"]}'); continue
        rows, want = r.json()['rows'], expected[q['id']]['rows']
        if len(rows) != len(want) or not all(len(a) == len(b) and all(close(x, y) for x, y in zip(a, b)) for a, b in zip(rows, want)):
            failures.append(f'{q["id"]}: got {rows[:3]} want {want[:3]}')
        if [c.lower() for c in r.json()['columns']] != [c.lower() for c in expected[q['id']]['columns']]:
            failures.append(f'{q["id"]}: columns {r.json()["columns"]}')
    return failures

@pytest.mark.parametrize('kind', list(SQL_ENGINES))
def test_sql_engine_end_to_end(kind):
    from tools.models import model
    cfg, spec = SQL_ENGINES[kind], model(kind)
    common = {'name': f'Live {kind}', 'kind': kind, 'url': cfg['reader'], **({'schema': cfg['schema']} if cfg['schema'] else {})}
    # 1. Wrong credentials: clear error, nothing secret echoed, active source unchanged.
    r = client.post('/api/sources/test', json={**common, 'password': 'Wr0ngPassw0rdX'})
    assert r.status_code == 400 and 'failed' in r.json()['detail'].lower(), r.text
    no_secrets(r.text)
    # 2. Correct reader credentials: test → discover → activate.
    sid = connect(**common, password=READER, questions=f'pack/{kind}/questions.json')
    tables = {t['name'].lower() for t in client.get('/api/schema').json()['tables']}
    assert tables == set(spec['data']), tables                     # qw_pack_history stays hidden
    # 3. Pack analytics through the gateway match the reference results.
    assert check_questions(kind) == []
    # 4. Generalized allowlist: Northstar tables do not exist here.
    assert query('SELECT COUNT(*) FROM orders').status_code == 400 or 'orders' in spec['data']
    # 5. Timeout guard.
    fact = spec['fact']
    if kind not in NO_TIMEOUT:
        start = time.monotonic()
        # 120^5 row combinations with a predicate no planner can push down: far beyond 3 s unless cancelled.
        r = query(f'SELECT COUNT(*) AS n FROM {fact} a, {fact} b, {fact} c, {fact} d, {fact} e WHERE a.id * b.id + c.id * d.id + e.id < 0')
        assert r.status_code == 400 and time.monotonic() - start < 20, r.text
    # 6. Even bypassing the validator, the reader cannot write and nothing changes.
    before = query(f'SELECT COUNT(*) AS n FROM {fact}').json()['rows'][0][0]
    active = registry.active()
    with pytest.raises(QueryRejected): active.connector.run(f'DELETE FROM {fact}', active.tables)
    if kind in RO_TRANSACTION:  # The read-only transaction alone blocks an admin login too.
        admin = build({'kind': kind, 'url': cfg['admin'], **({'schema': cfg['schema']} if cfg['schema'] else {})})
        try:
            with pytest.raises(QueryRejected): admin.run(f'DELETE FROM {fact}', active.tables)
            # Prove the read-only transaction itself (PostgreSQL's server-side cursor would reject DELETE even earlier).
            with admin.get_engine().connect() as conn:
                trans = conn.begin()
                try:
                    for statement in admin.guards(): conn.exec_driver_sql(statement)
                    with pytest.raises(Exception, match='(?i)read.only|ORA-01456'): conn.exec_driver_sql(f'DELETE FROM {fact}')
                finally: trans.rollback()
        finally: admin.close()
    assert query(f'SELECT COUNT(*) AS n FROM {fact}').json()['rows'][0][0] == before
    client.delete(f'/api/sources/{sid}')

def test_mongodb_end_to_end():
    from tools.document_fixtures import fixtures
    base = {'name': 'Live MongoDB', 'kind': 'mongodb', 'url': MONGO_READER, 'username': 'qw_app', 'database': 'qw_complex_learning'}
    r = client.post('/api/sources/test', json={**base, 'password': 'Wr0ngPassw0rdX'}); assert r.status_code == 400; no_secrets(r.text)
    connect(**base, password=READER)
    counts = json.loads((ROOT/'pack/mongodb/expected_counts.json').read_text())
    for coll, n in counts.items(): assert query(f'SELECT COUNT(*) AS n FROM {coll}').json()['rows'] == [[n]]
    f = fixtures('mongodb')
    rows = query("SELECT course_id, SUM(learning_minutes) AS minutes FROM enrollments WHERE status = 'active' GROUP BY course_id ORDER BY course_id").json()['rows']
    assert rows == [[i, sum(e['duration_seconds'] / 60 for e in f['enrollments'] if e['course_id'] == i and e['status'] == 'active')] for i in range(1, 7)]
    scores = [a['score'] for a in f['attempts'] if a['score'] is not None]
    assert query('SELECT COUNT(*) AS n, COUNT(score) AS scored, ROUND(AVG(score), 2) AS avg FROM attempts').json()['rows'] == [[len(f['attempts']), len(scores), round(sum(scores) / len(scores), 2)]]
    assert query('SELECT e.cohort FROM enrollments e JOIN attempts a ON a.enrollment_id = e._id').status_code == 400

def test_elasticsearch_end_to_end():
    from tools.document_fixtures import fixtures
    key = Path(ES_KEY_FILE).read_text().strip()
    r = client.post('/api/sources/test', json={'name': 'x', 'kind': 'elasticsearch', 'url': ES_URL, 'api_key': 'V3JvbmdQYXNzdzByZFg6bm9wZQ=='})
    assert r.status_code == 400 and '401' in r.json()['detail']
    connect(name='Live Elasticsearch', kind='elasticsearch', url=ES_URL, api_key=key)
    tables = {t['name']: t for t in client.get('/api/schema').json()['tables']}
    assert 'qw-complex-reliability-requests' in tables and 'qw-complex-reliability-requests-v2' in tables
    assert 'latency_seconds' in {c['name'] for c in tables['qw-complex-reliability-requests-v2']['columns']}
    counts = json.loads((ROOT/'pack/elasticsearch/expected_counts.json').read_text())
    assert query('SELECT COUNT(*) AS n FROM "qw-complex-reliability-requests"').json()['rows'] == [[counts['requests']]]
    assert query('SELECT COUNT(*) AS n FROM "qw-complex-reliability-incidents-v1"').json()['rows'] == [[counts['incidents']]]
    want = {}
    for row in fixtures('elasticsearch')['requests']:
        if row['status_code'] == 500: want[row['service']] = want.get(row['service'], 0) + 1
    rows = query('SELECT service, COUNT(*) AS errors FROM "qw-complex-reliability-requests" WHERE status_code = 500 GROUP BY service ORDER BY service').json()['rows']
    assert rows == sorted([[s, n] for s, n in want.items()])
    no_secrets(client.get('/api/sources').text); assert key not in client.get('/api/sources').text

def test_file_sources():
    connect(name='Library', kind='sqlite', path='pack/output/library.sqlite', questions='pack/sqlite/questions.json')
    assert check_questions('sqlite') == []
    connect(name='Sensors', kind='parquet', path='pack/output/sensors/v2')
    assert query("SELECT quality, COUNT(*) AS n FROM analytics_readings GROUP BY quality ORDER BY quality").json()['rows'] == [['missing', 63], ['outlier', 239], ['valid', 898]]
    connect(name='Grants CSV', kind='excel', path='pack/excel/fixtures')
    assert query("SELECT COUNT(*) FROM awards WHERE status = 'approved'").json()['rows'] == [[111]]
