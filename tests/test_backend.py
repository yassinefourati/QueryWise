import json, sqlite3
from pathlib import Path
from types import SimpleNamespace
import httpx
import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.database import execute, validate, QueryRejected, ROOT
from backend.connectors import ConnectionFailed, ElasticsearchConnector, build, redact
from backend.mongo_sql import translate
from backend.sources import registry, system_prompt, catalog as source_catalog
from backend.state import State, SecretUnavailable, mask
import backend.main as api_module
import backend.providers as providers

HEADERS={'X-Querywise-Client':'1'}
client=TestClient(app,base_url='http://localhost',headers=HEADERS)
CATALOG=json.loads((ROOT/'dist/catalog.json').read_text(encoding='utf-8'))

@pytest.fixture(autouse=True)
def sample_is_active():
    """Every test starts and ends on the built-in sample with demo settings."""
    for key in ('active_source',*providers.SETTINGS): registry.state.delete(key)
    registry._active=None
    yield
    for key in ('active_source',*providers.SETTINGS): registry.state.delete(key)
    registry._active=None

def make_db(path):
    with sqlite3.connect(path) as c:
        c.executescript('''CREATE TABLE widgets (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE sales (id INTEGER PRIMARY KEY, widget_id INTEGER NOT NULL REFERENCES widgets(id), amount REAL NOT NULL);
INSERT INTO widgets VALUES (1,'Sprocket'),(2,'Cog');
INSERT INTO sales VALUES (1,1,10.5),(2,1,4.5),(3,2,7);''')
    return path

def add_source(**body):
    r=client.post('/api/sources',json=body); assert r.status_code==201,r.text
    return r.json()['id']

# Sample dataset: correct results and the original guards ---------------------------------------------
@pytest.mark.parametrize('entry',CATALOG,ids=lambda e:e['id'])
def test_sample_queries_return_real_results(entry):
    result=client.post('/api/query',json={'sql':entry['sql']})
    assert result.status_code==200,result.text
    payload=result.json()
    with sqlite3.connect(ROOT/'data/sample.db') as conn:
        expected=conn.execute(entry['sql']).fetchall()
    assert payload['rows']==[list(row) for row in expected]
    assert payload['truncated'] is False

def test_revenue_consistent_across_groupings():
    grouped=[sum(r[-1] for r in execute(e['sql'])['rows']) for e in CATALOG if e['id'] in {'monthly','category','province','segment'}]
    assert len(set(grouped))==1

@pytest.mark.parametrize('sql',[
    'DELETE FROM orders', 'SELECT 1; DROP TABLE orders',
    'PRAGMA query_only=OFF','ATTACH DATABASE "/tmp/other" AS other',
    'SELECT * FROM sqlite_master','SELECT * FROM pg_catalog.pg_roles',
    "SELECT load_extension('danger')", "SELECT readfile('/etc/passwd')",
    'SELECT randomblob(1000000000)', 'SELECT pg_sleep(100)',
    'SELECT * INTO copied FROM orders',
    'WITH removed AS (DELETE FROM orders RETURNING *) SELECT * FROM removed',
    'WITH RECURSIVE x AS (SELECT 1 UNION ALL SELECT 1 FROM x) SELECT * FROM x',
    'SELECT * FROM orders FOR UPDATE',
    'SELECT * FROM secret_table',
    'SELECT * FROM orders UNION SELECT * FROM customers',
    'SELECT * FROM generate_series(1,1000000000)',
    'WITH orders AS (SELECT * FROM customers) SELECT * FROM orders',
    'SELECT * FROM qw_pack_history',
    "SELECT * FROM read_parquet('/etc/passwd')",
])
def test_unsafe_sql_rejected(sql):
    with pytest.raises(QueryRejected): execute(sql)

def test_logical_operators_and_case_are_not_functions():
    r=execute("SELECT CASE WHEN status='completed' THEN 1 ELSE 0 END AS done, COUNT(*) AS n FROM orders WHERE status='completed' AND id>0 OR id<0 GROUP BY 1")
    assert r['rows']==[[1,execute("SELECT COUNT(*) FROM orders WHERE status='completed'")['rows'][0][0]]]

def test_limited_results():
    r=execute('SELECT * FROM order_items')
    assert len(r['rows'])==500 and r['truncated']

def test_readonly_authorizer_preserves_tables():
    assert execute('SELECT COUNT(*) AS n FROM orders')['rows']==[[720]]

def test_simple_cte():
    assert execute('WITH totals AS (SELECT COUNT(*) AS n FROM orders) SELECT n FROM totals')['rows']==[[720]]

def test_missing_column_is_error():
    assert client.post('/api/query',json={'sql':'SELECT password FROM customers'}).status_code==400

def test_api_health_and_assets():
    health=client.get('/api/health').json()
    assert health['app']=='querywise' and health['source']['id']=='sample'
    assert client.get('/').status_code==200
    assert client.get('/dataset.json').status_code==200
    schema=client.get('/api/schema').json()
    assert schema['row_limit']==500 and {t['name'] for t in schema['tables']}=={'customers','orders','order_items','products'}

def test_demo_does_not_fake_ai():
    response=client.post('/api/ask',json={'question':'What is our revenue?'})
    assert response.status_code==503

def test_input_limits():
    assert client.post('/api/query',json={'sql':'x'*12001}).status_code==422
    assert client.post('/api/ask',json={'question':'x'*1201}).status_code==422

def test_postgres_catalog_parses():
    import sqlglot
    for entry in CATALOG:
        sql=sqlglot.transpile(entry['sql'],read='sqlite',write='postgres')[0]
        assert validate(sql,dialect='postgres')

def test_ui_files_revalidate_and_api_is_not_cached():
    assert client.get('/app.js').headers['cache-control']=='no-cache'
    assert client.get('/api/health').headers['cache-control']=='no-store'

def test_writes_need_client_header_and_local_host():
    bare=TestClient(app,base_url='http://localhost')
    assert bare.post('/api/query',json={'sql':'SELECT 1'}).status_code==403
    assert bare.get('/api/health').status_code==200
    assert TestClient(app,base_url='http://attacker.example').get('/api/health').status_code==400

# Source switching, connection checks, discovery, generalized allowlist ---------------------------------
def test_switch_discovers_schema_and_generalizes_allowlist(tmp_path):
    sid=add_source(name='Widgets',kind='sqlite',path=str(make_db(tmp_path/'widgets.sqlite')),definitions='Amounts are CAD.')
    r=client.post(f'/api/sources/{sid}/select'); assert r.status_code==200,r.text
    schema=client.get('/api/schema').json()
    sales=next(t for t in schema['tables'] if t['name']=='sales')
    assert [c['name'] for c in sales['columns']]==['id','widget_id','amount']
    assert sales['foreign_keys']==[{'columns':['widget_id'],'table':'widgets','references':['id']}] and sales['row_count']==3
    assert client.post('/api/query',json={'sql':'SELECT w.name, SUM(s.amount) AS amount FROM sales s JOIN widgets w ON w.id=s.widget_id GROUP BY w.name ORDER BY w.name'}).json()['rows']==[['Cog',7.0],['Sprocket',15.0]]
    rejected=client.post('/api/query',json={'sql':'SELECT COUNT(*) FROM orders'})
    assert rejected.status_code==400 and 'outside the allowed schema' in rejected.json()['detail']
    prompt=system_prompt(registry.active())
    assert 'sales(id INTEGER PRIMARY KEY, widget_id INTEGER REFERENCES widgets(id)' in prompt and 'Amounts are CAD.' in prompt and 'order_items' not in prompt
    assert all('FROM' in e['sql'] for e in client.get('/api/catalog').json())
    assert client.get('/api/health').json()['source']['id']==sid
    assert client.post('/api/sources/sample/select').status_code==200
    assert client.post('/api/query',json={'sql':'SELECT COUNT(*) FROM orders'}).json()['rows']==[[720]]

def test_failed_connection_keeps_previous_source(tmp_path):
    sid=add_source(name='Missing',kind='sqlite',path=str(tmp_path/'nope.sqlite'))
    r=client.post(f'/api/sources/{sid}/select')
    assert r.status_code==400 and 'not found' in r.json()['detail']
    assert client.get('/api/health').json()['source']['id']=='sample'
    assert client.post(f'/api/sources/{sid}/test').status_code==400

def test_connection_errors_are_clear_and_redacted(monkeypatch):
    r=client.post('/api/sources/test',json={'name':'x','kind':'postgres','url':'mysql+pymysql://u:hunter2secret@localhost/db'})
    assert r.status_code==400 and 'not PostgreSQL' in r.json()['detail'] and 'hunter2secret' not in r.text
    assert redact('failed for postgresql://admin:pw123456@db.internal:5432/x','pw123456')=='failed for postgresql://•••@db.internal:5432/x'
    import importlib
    real=importlib.import_module
    def fake(name,*a):
        if name=='pymongo': raise ImportError(name)
        return real(name,*a)
    monkeypatch.setattr(importlib,'import_module',fake)
    r=client.post('/api/sources/test',json={'name':'m','kind':'mongodb','url':'mongodb://localhost:27017/app'})
    assert r.status_code==400 and 'optional package "pymongo"' in r.json()['detail']

def test_env_variable_overrides_stored_path(tmp_path,monkeypatch):
    monkeypatch.setenv('QW_TEST_DB_PATH',str(make_db(tmp_path/'env.sqlite')))
    sid=add_source(name='Env path',kind='sqlite',path=str(tmp_path/'stored-but-missing.sqlite'),path_env='QW_TEST_DB_PATH')
    assert client.post(f'/api/sources/{sid}/select').status_code==200
    assert client.post('/api/query',json={'sql':'SELECT COUNT(*) FROM widgets'}).json()['rows']==[[2]]

def test_builtin_sources_cannot_be_edited_or_removed():
    assert client.delete('/api/sources/sample').status_code==409
    assert client.put('/api/sources/sample',json={'name':'x'}).status_code==409

def test_removing_active_source_falls_back_to_default(tmp_path):
    sid=add_source(name='Temp',kind='sqlite',path=str(make_db(tmp_path/'t.sqlite')))
    client.post(f'/api/sources/{sid}/select')
    assert client.delete(f'/api/sources/{sid}').json()['active']=='sample'
    assert client.get('/api/health').json()['source']['id']=='sample'

def test_pack_sqlite_source_matches_expected_results(tmp_path):
    from sqlalchemy import create_engine
    from tools.sql_runner import migrate, seed
    engine=create_engine(f'sqlite:///{tmp_path/"library.sqlite"}'); migrate(engine,'sqlite',2); seed(engine,'sqlite',1); engine.dispose()
    sid=add_source(name='Library',kind='sqlite',path=str(tmp_path/'library.sqlite'),questions='pack/sqlite/questions.json')
    assert client.post(f'/api/sources/{sid}/select').status_code==200
    tables={t['name'] for t in client.get('/api/schema').json()['tables']}
    assert tables=={'branches','members','titles','copies','loans','fines','fine_payments'}  # qw_pack_history is hidden
    expected=json.loads((ROOT/'pack/sqlite/expected_results.scale1.json').read_text(encoding='utf-8'))
    entries=client.get('/api/catalog').json(); assert {e['id'] for e in entries}==set(expected)
    for e in entries:
        r=client.post('/api/query',json={'sql':e['sql']}).json()
        assert r['columns']==expected[e['id']]['columns'] and r['rows']==expected[e['id']]['rows']

def test_excel_and_csv_sources(tmp_path):
    openpyxl=pytest.importorskip('openpyxl')
    from datetime import date
    book=openpyxl.Workbook(); sheet=book.active; sheet.title='Award List'
    sheet.append(['ID','Program Name','Committed (cents)','Awarded On']); sheet.append([1,'Water',100000,date(2026,1,5)]); sheet.append([2,'Youth',250000,date(2026,2,1)])
    book.save(tmp_path/'grants.xlsx')
    sid=add_source(name='Grants',kind='excel',path=str(tmp_path/'grants.xlsx'))
    assert client.post(f'/api/sources/{sid}/select').status_code==200
    table=client.get('/api/schema').json()['tables'][0]
    assert table['name']=='award_list' and [c['name'] for c in table['columns']]==['id','program_name','committed_cents','awarded_on']
    assert client.post('/api/query',json={'sql':'SELECT program_name, committed_cents, awarded_on FROM award_list ORDER BY id'}).json()['rows']==[['Water',100000,'2026-01-05'],['Youth',250000,'2026-02-01']]
    csv_id=add_source(name='Grant CSVs',kind='excel',path='pack/excel/fixtures')
    assert client.post(f'/api/sources/{csv_id}/select').status_code==200
    assert client.post('/api/query',json={'sql':"SELECT COUNT(*) FROM awards WHERE status='approved'"}).json()['rows']==[[111]]

def test_parquet_source_is_locked_down(tmp_path):
    duckdb=pytest.importorskip('duckdb')
    con=duckdb.connect(); con.execute(f"COPY (SELECT range AS id, range % 3 AS bucket FROM range(1200)) TO '{tmp_path/'events.parquet'}' (FORMAT PARQUET)"); con.close()
    sid=add_source(name='Events',kind='parquet',path=str(tmp_path))
    assert client.post(f'/api/sources/{sid}/select').status_code==200
    assert client.post('/api/query',json={'sql':'SELECT bucket, COUNT(*) AS n FROM events GROUP BY bucket ORDER BY bucket'}).json()['rows']==[[0,400],[1,400],[2,400]]
    r=client.post('/api/query',json={'sql':'SELECT * FROM events'}).json(); assert len(r['rows'])==500 and r['truncated']
    active=registry.active()
    with pytest.raises(QueryRejected): active.connector.run(f"COPY events TO '{tmp_path/'leak.csv'}'",active.tables)  # Even bypassing the validator.
    assert not (tmp_path/'leak.csv').exists()

def test_mongo_translation():
    fields={'enrollments':['_id','course_id','status','learning_minutes']}
    coll,pipeline,cols=translate("SELECT course_id, ROUND(SUM(learning_minutes), 1) AS minutes, COUNT(*) AS n FROM enrollments WHERE status = 'active' AND course_id IN (1, 2) GROUP BY course_id ORDER BY minutes DESC LIMIT 5",fields,501)
    assert coll=='enrollments' and cols==['course_id','minutes','n']
    assert pipeline==[{'$match':{'$and':[{'status':{'$eq':'active'}},{'course_id':{'$in':[1,2]}}]}},
                      {'$group':{'_id':{'g0':'$course_id'},'a1':{'$sum':'$learning_minutes'},'a2':{'$sum':1}}},
                      {'$project':{'_id':0,'course_id':'$_id.g0','minutes':{'$round':['$a1',1]},'n':'$a2'}},{'$sort':{'minutes':-1}},{'$limit':5}]
    _,pipeline,cols=translate('SELECT * FROM enrollments WHERE learning_minutes >= 10 ORDER BY course_id',fields,501)
    assert cols==fields['enrollments'] and pipeline[-1]=={'$project':{c:1 for c in fields['enrollments']}} and pipeline[-2]=={'$limit':501}
    assert not any(stage.keys()&{'$out','$merge','$lookup'} for stage in pipeline)
    for sql in ['SELECT a.x FROM enrollments a JOIN attempts b ON a._id=b.enrollment_id','SELECT course_id FROM enrollments GROUP BY course_id HAVING COUNT(*)>1']:
        with pytest.raises(QueryRejected): translate(sql,fields,501)

def test_elasticsearch_connector_uses_sql_api():
    seen=[]
    def handler(request):
        seen.append((request.method,request.url.path,request.headers.get('authorization')))
        if request.url.path=='/': return httpx.Response(200,json={'version':{'number':'9.1.0'}})
        if request.url.path=='/_resolve/index/*': return httpx.Response(200,json={'indices':[{'name':'requests-v2'},{'name':'.security'}],'aliases':[],'data_streams':[]})
        if request.url.path.endswith('/_count'): return httpx.Response(200,json={'count':3})
        if request.url.path.endswith('/_mapping'): return httpx.Response(200,json={'requests-v2':{'mappings':{'properties':{'service':{'type':'keyword'},'geo':{'properties':{'lat':{'type':'double'}}}}}}})
        if request.url.path=='/_sql': return httpx.Response(200,json={'columns':[{'name':'service','type':'keyword'},{'name':'n','type':'long'}],'rows':[['api',2],['worker',1]]})
        return httpx.Response(404)
    ElasticsearchConnector.transport=httpx.MockTransport(handler)
    try:
        es=build({'kind':'elasticsearch','url':'https://es.local:9200','api_key':'secret-api-key-123'})
        es.test(); tables=es.discover()
        assert [t['name'] for t in tables]==['requests-v2'] and [c['name'] for c in tables[0]['columns']]==['service','geo.lat'] and tables[0]['row_count']==3
        sql=validate('SELECT service, COUNT(*) AS n FROM "requests-v2" GROUP BY service',None,{'requests-v2'})
        assert es.run(sql,{'requests-v2'})==(['service','n'],[['api',2],['worker',1]])
        assert all(auth=='ApiKey secret-api-key-123' for *_,auth in seen) and ('POST','/_sql',seen[-1][2]) in seen
    finally: ElasticsearchConnector.transport=None

# Secrets: encryption at rest, masking, precedence ------------------------------------------------------
def test_secrets_are_encrypted_and_masked(tmp_path,monkeypatch):
    state=State(tmp_path/'s1'); state.put('anthropic_api_key','sk-ant-test-0123456789abcd',secret=True)
    state.save_source('x','X','postgres',{},{'url':'postgresql://u:topsecretpw@h/db'})
    raw=(tmp_path/'s1/state.db').read_bytes()
    assert b'sk-ant-test' not in raw and b'topsecretpw' not in raw
    assert State(tmp_path/'s1').get('anthropic_api_key')=='sk-ant-test-0123456789abcd'
    assert mask('sk-ant-test-0123456789abcd')=='••••abcd' and mask('short')=='••••' and mask('')==''
    monkeypatch.setenv('QUERYWISE_SECRET_KEY','first passphrase')
    s2=State(tmp_path/'s2'); s2.put('k','value-123456789',secret=True); assert not (tmp_path/'s2/secret.key').exists()
    monkeypatch.setenv('QUERYWISE_SECRET_KEY','changed passphrase')
    with pytest.raises(SecretUnavailable): State(tmp_path/'s2').get('k')

def test_api_never_returns_stored_secrets(tmp_path):
    key='sk-ant-api-key-that-must-stay-private-9876'
    r=client.put('/api/settings',json={'provider':'anthropic','anthropic_api_key':key}); assert r.status_code==200
    setting=r.json()['settings']['anthropic_api_key']
    assert setting=={'set':True,'masked':'••••9876','origin':'stored','env':'ANTHROPIC_API_KEY','locked':False}
    sid=add_source(name='PG',kind='postgres',url='postgresql+psycopg://reader@localhost/db',password='pg-password-xyz1')
    for body in (client.get('/api/settings').text,client.get('/api/sources').text,client.get('/api/health').text):
        assert key not in body and 'pg-password-xyz1' not in body
    secrets=next(s for s in client.get('/api/sources').json()['sources'] if s['id']==sid)['secrets']
    assert secrets['password']['masked']=='••••xyz1' and secrets['url']['set']
    client.delete(f'/api/sources/{sid}')

def test_environment_overrides_and_locks_settings(monkeypatch):
    client.put('/api/settings',json={'anthropic_api_key':'stored-key-0000000000'})
    monkeypatch.setenv('ANTHROPIC_API_KEY','env-key-111111111111')
    assert providers.current(registry.state)['anthropic_api_key']=='env-key-111111111111'
    assert client.get('/api/settings').json()['settings']['anthropic_api_key']['origin']=='env'
    assert client.put('/api/settings',json={'anthropic_api_key':'other'}).status_code==409

# AI providers: Ollama, Anthropic (mocked), concurrency and clarification ------------------------------
class FakeResponse:
    def __init__(self, answer): self.answer=answer
    def raise_for_status(self): pass
    def json(self): return {'message':{'content':json.dumps(self.answer)}}
class FakeOllama:
    answer={}
    def __init__(self,**kwargs): pass
    async def __aenter__(self): return self
    async def __aexit__(self,*args): pass
    async def post(self,url,json):
        assert url.endswith('/api/chat')
        assert json['stream'] is False
        assert json['format']['type']=='object'
        return FakeResponse(self.answer)

def mock_model(monkeypatch,sql,clarification=''):
    monkeypatch.setenv('AI_PROVIDER','ollama')
    monkeypatch.setattr(providers.httpx,'AsyncClient',FakeOllama)
    FakeOllama.answer={'sql':sql,'title':'Orders','explanation':'All sample orders.','chart':'table','clarification':clarification}

def test_model_sql_executed(monkeypatch):
    mock_model(monkeypatch,'SELECT COUNT(*) AS orders FROM orders')
    response=client.post('/api/ask',json={'question':'Count the orders'})
    assert response.status_code==200,response.text
    assert response.json()['rows']==[[720]]

def test_model_cannot_bypass_guard(monkeypatch):
    mock_model(monkeypatch,'DELETE FROM orders')
    response=client.post('/api/ask',json={'question':'Count the orders'})
    assert response.status_code==400
    assert execute('SELECT COUNT(*) FROM orders')['rows']==[[720]]

def test_model_clarification(monkeypatch):
    mock_model(monkeypatch,'','Profit data is unavailable. Would you like revenue?')
    response=client.post('/api/ask',json={'question':'What is our profit?'})
    assert response.status_code==422
    assert 'Profit' in response.json()['detail']

def test_one_ai_question_at_a_time(monkeypatch):
    mock_model(monkeypatch,'SELECT 1 FROM orders')
    monkeypatch.setattr(api_module,'model_lock',SimpleNamespace(locked=lambda:True))
    assert client.post('/api/ask',json={'question':'Count the orders'}).status_code==429

class FakeAnthropic:
    calls=[]; stop_reason='end_turn'; answer={}
    def __init__(self,api_key,**kwargs):
        self.api_key=api_key; FakeAnthropic.headers=kwargs.get('default_headers'); create=self.create
        self.messages=SimpleNamespace(create=create); self.beta=SimpleNamespace(messages=SimpleNamespace(create=create))
    async def create(self,**kwargs):
        FakeAnthropic.calls.append({**kwargs,'api_key':self.api_key})
        return SimpleNamespace(stop_reason=FakeAnthropic.stop_reason,content=[SimpleNamespace(type='thinking',thinking=''),SimpleNamespace(type='text',text=json.dumps(FakeAnthropic.answer))])
    async def __aenter__(self): return self
    async def __aexit__(self,*args): pass

@pytest.fixture
def claude(monkeypatch):
    import anthropic
    monkeypatch.setattr(anthropic,'AsyncAnthropic',FakeAnthropic)
    FakeAnthropic.calls,FakeAnthropic.stop_reason=[],'end_turn'
    FakeAnthropic.answer={'sql':'SELECT COUNT(*) AS widgets FROM widgets','title':'Widgets','explanation':'Counts widgets.','chart':'table','clarification':''}
    return FakeAnthropic

def test_anthropic_answers_from_discovered_schema(claude,tmp_path):
    sid=add_source(name='Widgets',kind='sqlite',path=str(make_db(tmp_path/'w.sqlite')))
    client.post(f'/api/sources/{sid}/select')
    client.put('/api/settings',json={'provider':'anthropic','anthropic_api_key':'sk-ant-stored-key-424242'})
    r=client.post('/api/ask',json={'question':'How many widgets?'})
    assert r.status_code==200,r.text
    assert r.json()['rows']==[[2]] and r.json()['provider']=='anthropic' and r.json()['model']=='claude-opus-5-5'
    call=claude.calls[-1]
    assert call['api_key']=='sk-ant-stored-key-424242' and call['model']=='claude-opus-5-5'
    assert call['output_config']['format']=={'type':'json_schema','schema':providers.ANSWER_SCHEMA} and call['output_config']['effort']=='medium'
    assert call['fallbacks']=='default' and call['betas']==['server-side-fallback-2026-07-01']
    assert 'widgets(id INTEGER PRIMARY KEY, name TEXT)' in call['system'] and 'order_items' not in call['system']
    assert call['messages']==[{'role':'user','content':'How many widgets?'}]

def test_anthropic_env_settings_clarification_and_refusal(claude,monkeypatch):
    monkeypatch.setenv('AI_PROVIDER','anthropic'); monkeypatch.setenv('ANTHROPIC_API_KEY','sk-ant-env-key-1'); monkeypatch.setenv('ANTHROPIC_MODEL','claude-haiku-5-5')
    claude.answer={'sql':'','title':'Profit','explanation':'','chart':'table','clarification':'Profit is not available; revenue is.'}
    r=client.post('/api/ask',json={'question':'What is our profit?'})
    assert r.status_code==422 and 'revenue' in r.json()['detail']
    assert claude.calls[-1]['model']=='claude-haiku-5-5' and 'fallbacks' not in claude.calls[-1] and claude.calls[-1]['api_key']=='sk-ant-env-key-1'
    claude.stop_reason='refusal'
    assert client.post('/api/ask',json={'question':'Anything'}).status_code==422

def test_anthropic_workspace_header(claude):
    client.put('/api/settings',json={'provider':'anthropic','anthropic_api_key':'sk-ant-stored-key-424242','anthropic_workspace_id':'wrkspc_01TestWorkspace'})
    claude.answer={'sql':'SELECT COUNT(*) AS n FROM orders','title':'Orders','explanation':'','chart':'table','clarification':''}
    assert client.post('/api/ask',json={'question':'How many orders?'}).status_code==200
    assert claude.headers=={'anthropic-workspace-id':'wrkspc_01TestWorkspace'}
    client.put('/api/settings',json={'clear':['anthropic_workspace_id']}); client.post('/api/ask',json={'question':'How many orders?'})
    assert claude.headers is None

def test_anthropic_without_key_is_explicit(monkeypatch):
    monkeypatch.setenv('AI_PROVIDER','anthropic')
    r=client.post('/api/ask',json={'question':'How many orders?'})
    assert r.status_code==503 and 'API key' in r.json()['detail']

# History and saved queries -------------------------------------------------------------------------------
def test_history_and_saved_queries():
    client.delete('/api/queries',params={'list':'saved'})
    qid=client.post('/api/queries',json={'list':'saved','entry':{'title':'Orders','sql':'SELECT COUNT(*) FROM orders','mode':'sql','rows':[[1]]}}).json()['id']
    saved=client.get('/api/queries',params={'list':'saved'}).json()
    assert saved[0]['id']==qid and saved[0]['sql']=='SELECT COUNT(*) FROM orders' and 'rows' not in saved[0]
    client.delete(f'/api/queries/{qid}'); assert client.get('/api/queries',params={'list':'saved'}).json()==[]

# Repository hygiene: secrets live only in env vars or the git-ignored app-state DB ---------------------
def test_secret_locations_are_git_ignored_and_template_is_empty():
    ignored=(ROOT/'.gitignore').read_text(encoding='utf-8').splitlines()
    assert {'.env','.querywise/','data/','pack/output/','!.env.example','*.key'}<=set(ignored)
    for line in (ROOT/'.env.example').read_text(encoding='utf-8').splitlines():
        if line and not line.startswith('#') and any(k in line for k in ('KEY','PASSWORD','SECRET','_URL=postgres','_URL=mysql')):
            assert line.endswith('='),f'.env.example must ship placeholders only: {line}'
    real_key=__import__('re').compile(r'sk-ant-(api|admin)\d\d-[A-Za-z0-9_-]{20,}')
    for path in [*ROOT.glob('*.*'),*(p for d in ('backend','dist','scripts','tests','evals','pack') for p in (ROOT/d).rglob('*') if p.is_file() and 'output' not in p.parts and '__pycache__' not in p.parts)]:
        if path.suffix in {'.py','.js','.json','.md','.txt','.yaml','.ini','.html','.sql','.example','.ps1','.cjs'}:
            assert not real_key.search(path.read_text(encoding='utf-8',errors='ignore')),f'API key-like value in {path}'
