import asyncio, os
from typing import Literal
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool
from starlette.middleware.trustedhost import TrustedHostMiddleware
from .database import ROOT, ROW_LIMIT, execute, validate, QueryRejected
from .connectors import KINDS, ConnectionFailed
from .sources import registry, SourceUnavailable, catalog as source_catalog, describe_schema, system_prompt, dialect_name
from . import providers
from .providers import ProviderError

app=FastAPI(title='Querywise',version='1.0.0',description='Natural-language database analysis with a read-only query gateway.')
model_lock=asyncio.Semaphore(1)
state=registry.state
# Local single-user app: refuse other Host headers (DNS rebinding) and require a custom header on writes (CSRF).
HOSTS=['localhost','127.0.0.1','[::1]',*[h.strip() for h in os.getenv('QUERYWISE_ALLOWED_HOSTS','').split(',') if h.strip()]]
app.add_middleware(TrustedHostMiddleware,allowed_hosts=HOSTS)
@app.middleware('http')
async def require_client_header(request: Request, call_next):
    if request.url.path.startswith('/api/') and request.method not in {'GET','HEAD','OPTIONS'} and request.headers.get('x-querywise-client')!='1':
        return JSONResponse({'detail':'Missing X-Querywise-Client header. Use the Querywise UI or send X-Querywise-Client: 1.'},status_code=403)
    response=await call_next(request)
    # UI files revalidate on every load so a browser never keeps running an outdated app.js; API responses are never cached.
    response.headers.setdefault('Cache-Control','no-store' if request.url.path.startswith('/api/') else 'no-cache')
    return response

class SQLRequest(BaseModel): sql: str=Field(min_length=1,max_length=12000)
class AskRequest(BaseModel): question: str=Field(min_length=3,max_length=1200)
ENV_NAME=r'^[A-Z_][A-Z0-9_]{0,63}$'
class SourceRequest(BaseModel):
    name: str|None=Field(None,min_length=1,max_length=80)
    kind: Literal[tuple(KINDS)]|None=None
    url: str|None=Field(None,max_length=2000); url_env: str|None=Field(None,pattern=ENV_NAME+'|^$')
    path: str|None=Field(None,max_length=1000); path_env: str|None=Field(None,pattern=ENV_NAME+'|^$')
    username: str|None=Field(None,max_length=200); password: str|None=Field(None,max_length=500); password_env: str|None=Field(None,pattern=ENV_NAME+'|^$')
    api_key: str|None=Field(None,max_length=500); api_key_env: str|None=Field(None,pattern=ENV_NAME+'|^$')
    schema_name: str|None=Field(None,alias='schema',pattern=r'^([A-Za-z_][A-Za-z0-9_$]{0,127})?$')
    database: str|None=Field(None,pattern=r'^([A-Za-z0-9_.-]{1,64})?$')
    tables: list[str]|None=Field(None,max_length=500)
    definitions: str|None=Field(None,max_length=4000); description: str|None=Field(None,max_length=200)
    questions: str|None=Field(None,max_length=500,pattern=r'^([\w./ -]+\.json)?$')
    ca_cert: str|None=Field(None,max_length=1000); verify_tls: bool|None=None
    table: str|None=Field(None,pattern=r'^([A-Za-z_][A-Za-z0-9_]{0,63})?$')
    def data(self): return self.model_dump(by_alias=True,exclude_none=True)
class SettingsRequest(BaseModel):
    provider: Literal['demo','ollama','anthropic']|None=None
    anthropic_api_key: str|None=Field(None,max_length=400)
    anthropic_model: str|None=Field(None,pattern=r'^[a-z0-9][a-z0-9.\-]{1,80}$')
    anthropic_effort: Literal['low','medium','high','xhigh','max']|None=None
    anthropic_workspace_id: str|None=Field(None,pattern=r'^[A-Za-z0-9_-]{1,100}$')
    ollama_url: str|None=Field(None,pattern=r'^https?://[^\s]{1,300}$')
    ollama_model: str|None=Field(None,pattern=r'^[A-Za-z0-9][\w.:/\-]{0,120}$')
    clear: list[Literal['anthropic_api_key','anthropic_model','anthropic_effort','anthropic_workspace_id','ollama_url','ollama_model','provider']]=[]
class SavedQuery(BaseModel):
    list: Literal['history','saved']
    entry: dict

def active_or_503():
    try: return registry.active()
    except SourceUnavailable as e: raise HTTPException(503,str(e)) from e
def summary(active):
    return {'id':active.id,'name':active.name,'kind':active.kind,'kind_label':KINDS[active.kind]['label'],'dialect':dialect_name(active),'tables':len(active.schema['tables']),'discovered_at':active.discovered_at}

@app.get('/api/health')
def health():
    values=providers.current(state)
    try: active=summary(registry.active()); error=None
    except SourceUnavailable as e: active,error=None,str(e)
    return {'app':'querywise','provider':values['provider'],'dialect':active and active['dialect'],'model':providers.model_name(values),'model_verified':False,'source':active,'source_error':error}
@app.get('/api/schema')
def schema():
    active=active_or_503()
    return {'source':summary(active),'dialect':dialect_name(active),'tables':active.schema['tables'],'schema':describe_schema(active.schema),
            'definitions':active.source.config.get('definitions',''),'description':active.source.config.get('description',''),'controls':KINDS[active.kind]['controls'],'limits':KINDS[active.kind].get('limits',''),
            'sample_period':['2026-01-01','2026-09-30'] if active.id=='sample' else None,'row_limit':ROW_LIMIT}
@app.get('/api/catalog')
def catalog(): return source_catalog(active_or_503())
@app.post('/api/query')
def query(body: SQLRequest):
    active=active_or_503()
    try: return execute(body.sql,active)
    except QueryRejected as e: raise HTTPException(400,str(e)) from e
@app.post('/api/ask')
async def ask(body: AskRequest):
    values=providers.current(state)
    if values['provider']=='demo': raise HTTPException(503,'AI mode is disabled. Choose Ollama or Anthropic in Settings (or set AI_PROVIDER), or select a sample question.')
    if model_lock.locked(): raise HTTPException(429,'Another AI question is running. Try again shortly.')
    async with model_lock:
        active=await run_in_threadpool(active_or_503)
        try: output=await providers.generate(values,system_prompt(active),body.question)
        except ProviderError as e: raise HTTPException(e.status,e.message) from e
        if output.clarification or not output.sql.strip(): raise HTTPException(422,output.clarification or 'Please clarify the metric, grouping, and time period.')
        try:
            validate(output.sql,active.connector.dialect,active.tables)
            result=await run_in_threadpool(execute,output.sql,active)
        except QueryRejected as e: raise HTTPException(400,f'Generated SQL was rejected: {e}') from e
        return {**result,'title':output.title,'explanation':output.explanation,'chart':output.chart,'provider':values['provider'],'model':providers.model_name(values)}

# Sources: list, add, edit, test, select, refresh, remove. Secrets are write-only; responses carry masks.
@app.get('/api/sources')
def list_sources():
    active_id=registry.active_id()
    return {'active':active_id,'sources':[s.public(active_id) for s in registry.sources().values()],
            'kinds':{k:{'label':v['label'],'target':v['target'],'example':v['example'],'controls':v['controls'],'limits':v.get('limits','')} for k,v in KINDS.items()}}
def source_or_404(source_id):
    try: return registry.get(source_id)
    except KeyError as e: raise HTTPException(404,'Unknown source.') from e
@app.post('/api/sources',status_code=201)
def add_source(body: SourceRequest):
    if not body.name or not body.kind: raise HTTPException(422,'Name and kind are required.')
    try: source_id=registry.save(body.data())
    except ValueError as e: raise HTTPException(422,str(e)) from e
    return registry.get(source_id).public(registry.active_id())
@app.put('/api/sources/{source_id}')
def edit_source(source_id: str, body: SourceRequest):
    source_or_404(source_id)
    try: registry.save(body.data(),source_id)
    except PermissionError as e: raise HTTPException(409,str(e)) from e
    except ValueError as e: raise HTTPException(422,str(e)) from e
    return registry.get(source_id).public(registry.active_id())
@app.delete('/api/sources/{source_id}')
def remove_source(source_id: str):
    source_or_404(source_id)
    try: registry.remove(source_id)
    except PermissionError as e: raise HTTPException(409,str(e)) from e
    return {'removed':source_id,'active':registry.active_id()}
def tested(src):
    try: return {'ok':True,'message':f'Connected to {KINDS[src.kind]["label"]}.','elapsed_ms':registry.test(src)}
    except ConnectionFailed as e: raise HTTPException(400,str(e)) from e
@app.post('/api/sources/test')
def test_unsaved(body: SourceRequest):
    try: return tested(registry.unsaved(body.data()))
    except ValueError as e: raise HTTPException(422,str(e)) from e
@app.post('/api/sources/{source_id}/test')
def test_source(source_id: str): return tested(source_or_404(source_id))
@app.post('/api/sources/{source_id}/select')
def select_source(source_id: str):
    source_or_404(source_id)
    try: active=registry.select(source_id)
    except ConnectionFailed as e: raise HTTPException(400,f'Could not switch: {e}') from e
    return {'ok':True,'source':summary(active),'tables':[{'name':t['name'],'columns':len(t['columns'])} for t in active.schema['tables']]}
@app.post('/api/sources/refresh')
def refresh_active():
    try: active=registry.select(registry.active_id())
    except ConnectionFailed as e: raise HTTPException(400,f'Schema refresh failed: {e}') from e
    return {'ok':True,'source':summary(active)}

# Provider settings. Environment variables win and lock the field in the UI.
@app.get('/api/settings')
def get_settings(): return {'settings':providers.public(state),'providers':list(providers.PROVIDERS),'efforts':list(providers.EFFORTS)}
@app.put('/api/settings')
def put_settings(body: SettingsRequest):
    values=body.model_dump(exclude_none=True,exclude={'clear'})
    locked=[providers.SETTINGS[k][0] for k in [*values,*body.clear] if providers.setting(state,k)[1]=='env']
    if locked: raise HTTPException(409,f'{", ".join(locked)} is set in the environment, which overrides stored settings. Unset it to manage this from the UI.')
    for name in body.clear: state.delete(name)
    for name,value in values.items():
        if name=='anthropic_api_key' and not value.strip(): continue
        state.put(name,value.strip(),secret=providers.SETTINGS[name][2])
    return get_settings()
@app.post('/api/settings/check')
async def check_settings():
    try: return {'ok':True,'message':await providers.check(providers.current(state))}
    except ProviderError as e: raise HTTPException(e.status,e.message) from e

# History and saved queries, moved from browser localStorage (the UI keeps localStorage as a fallback).
@app.get('/api/queries')
def list_queries(list: Literal['history','saved']): return state.queries(list)
@app.post('/api/queries',status_code=201)
def add_query(body: SavedQuery):
    entry={k:v for k,v in body.entry.items() if k in {'title','description','sql','mode','chart','note','id','icon','time','source','source_name','question'}}
    if not isinstance(entry.get('sql'),str) or len(entry['sql'])>12000: raise HTTPException(422,'Entries need SQL under 12,000 characters.')
    entry['entry_id']=entry.pop('id',None)
    return {'id':state.add_query(body.list,entry)}
@app.delete('/api/queries/{query_id}')
def delete_query(query_id: int): state.delete_query(query_id); return {'removed':query_id}
@app.delete('/api/queries')
def clear_queries(list: Literal['history','saved']): state.clear_queries(list); return {'cleared':list}

# Same-origin frontend; no permissive CORS or public database connection endpoint.
app.mount('/',StaticFiles(directory=ROOT/'dist',html=True),name='frontend')
