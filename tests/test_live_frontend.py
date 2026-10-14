"""Live tests of the running containers with every engine: the backend over HTTP (app service) and the standalone
frontend (nginx serving dist/ + /api/ proxy) in headless Chromium, plus static-only hosting (WASM demo).
Skipped unless QW_LIVE=1 and the service URLs from compose.test.yaml are set."""
import json, os
from pathlib import Path
import httpx
import pytest
from tests.live_config import ADMIN, READER

APP = os.getenv('QW_APP_URL', '')
FRONTEND = os.getenv('QW_FRONTEND_URL', '')
STATIC = os.getenv('QW_STATIC_URL', '')
pytestmark = pytest.mark.skipif(os.getenv('QW_LIVE') != '1' or not (APP and FRONTEND and STATIC), reason='Runs only against the services in compose.test.yaml')
HEADERS = {'X-Querywise-Client': '1'}
SHOTS = Path(os.getenv('QW_RESULTS', '/results'))/'screenshots'
LIVE = ['live_postgres', 'live_mysql', 'live_mariadb', 'live_sqlserver', 'live_oracle', 'live_db2', 'live_mongodb', 'live_elasticsearch', 'live_sqlite', 'live_parquet', 'live_excel']

def api(method, path, **kw):
    r = httpx.request(method, APP + '/api/' + path, headers=HEADERS, timeout=120, **kw)
    assert ADMIN not in r.text and READER not in r.text, f'secret leaked by {path}'
    return r

@pytest.fixture(autouse=True)
def back_to_sample():
    yield
    api('POST', 'sources/sample/select')

def test_backend_lists_every_source_without_secrets():
    data = api('GET', 'sources').json()
    ids = {s['id'] for s in data['sources']}
    assert set(LIVE) | {'sample'} <= ids
    for s in data['sources']:
        for secret in s['secrets'].values(): assert set(secret) == {'set', 'masked', 'env', 'from_env'}
    assert api('GET', 'health').json()['app'] == 'querywise'

@pytest.mark.parametrize('source_id', LIVE)
def test_backend_switch_and_catalog(source_id):
    r = api('POST', f'sources/{source_id}/test'); assert r.status_code == 200, r.text
    r = api('POST', f'sources/{source_id}/select'); assert r.status_code == 200, r.text
    assert r.json()['source']['tables'] > 0
    schema = api('GET', 'schema').json()
    assert schema['source']['id'] == source_id and schema['tables']
    catalog = api('GET', 'catalog').json(); assert catalog
    failures = [f'{e["id"]}: {r.status_code} {r.text[:200]}' for e in catalog if (r := api('POST', 'query', json={'sql': e['sql']})).status_code != 200]
    assert failures == []

def test_frontend_switches_every_source_through_nginx():
    from playwright.sync_api import sync_playwright
    SHOTS.mkdir(parents=True, exist_ok=True)
    errors, report = [], {}
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={'width': 1400, 'height': 1000})
        page.on('pageerror', lambda e: errors.append(f'pageerror: {e}'))
        page.on('console', lambda m: errors.append(m.text) if m.type == 'error' and 'favicon' not in m.text and '400' not in m.text else None)
        page.goto(FRONTEND)
        try: page.wait_for_selector('#query-status:has-text("rows")', timeout=60000)
        except Exception:
            page.screenshot(path=str(SHOTS/'first-load-failure.png'), full_page=True)
            raise AssertionError(f'First load failed: status={page.inner_text("#query-status")!r} mode={page.inner_text("#mode-description")!r} '
                                 f'error={page.inner_text("#error")!r} console={errors}')
        for source_id in LIVE:
            page.click('#header-settings'); page.wait_for_selector('#settings-dialog[open]')
            page.click('[data-settings-tab="sources"]'); page.wait_for_selector(f'[data-src][data-id="{source_id}"]')
            page.click(f'[data-src="select"][data-id="{source_id}"]')
            page.wait_for_selector('#sources-status.ok, #sources-status.bad', timeout=120000)
            status = page.inner_text('#sources-status')
            page.click('#close-settings')
            ok = 'Connected' in status
            if ok:
                page.wait_for_selector('.suggestion', timeout=30000)
                page.click('.suggestion >> nth=0'); page.wait_for_selector('#query-status:has-text("rows")', timeout=30000)
                page.click('[data-view="schema"]'); cards = page.locator('.schema-card').count()
                page.screenshot(path=str(SHOTS/f'{source_id}-schema.png'), full_page=True)
                page.click('[data-view="explore"]')
                page.screenshot(path=str(SHOTS/f'{source_id}.png'), full_page=True)
                report[source_id] = {'status': status, 'workspace': page.inner_text('#strip-name'), 'tables': cards,
                                     'suggestions': page.locator('.suggestion').count(), 'result': page.inner_text('#query-status')}
            else: report[source_id] = {'status': status}
        page.set_viewport_size({'width': 390, 'height': 844}); page.click('#header-settings'); page.wait_for_selector('#settings-dialog[open]')
        report['mobile_horizontal_overflow'] = page.evaluate('document.documentElement.scrollWidth > window.innerWidth')
        assert ADMIN not in page.content() and READER not in page.content()
        browser.close()
    (SHOTS.parent/'frontend.json').write_text(json.dumps({'sources': report, 'console_errors': errors}, indent=2, ensure_ascii=False))
    failed = {k: v for k, v in report.items() if isinstance(v, dict) and ('Connected' not in v['status'] or not v.get('tables'))}
    assert failed == {} and errors == [] and report['mobile_horizontal_overflow'] is False, (failed, errors)

def test_frontend_serves_assets_and_proxies_api():
    for path, kind in [('/', 'text/html'), ('/app.js', 'javascript'), ('/db-worker.js', 'javascript'), ('/styles.css', 'text/css'), ('/vendor/sql-wasm.wasm', 'application/wasm')]:
        r = httpx.get(FRONTEND + path, timeout=30); assert r.status_code == 200 and kind in r.headers['content-type'], (path, r.headers.get('content-type'))
        assert r.headers.get('x-content-type-options') == 'nosniff'
    health = httpx.get(FRONTEND + '/api/health', timeout=30).json(); assert health['app'] == 'querywise'
    assert httpx.post(FRONTEND + '/api/query', json={'sql': 'SELECT 1'}, timeout=30).status_code == 403  # CSRF header still enforced through the proxy
    assert httpx.get(FRONTEND + '/.env', timeout=30).status_code == 404 and httpx.get(FRONTEND + '/../backend/state.py', timeout=30).status_code in (400, 404)

def test_static_hosting_falls_back_to_wasm_demo():
    from playwright.sync_api import sync_playwright
    SHOTS.mkdir(parents=True, exist_ok=True); errors = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True); page = browser.new_page()
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.goto(STATIC); page.wait_for_selector('#query-status:has-text("rows")', timeout=30000)
        assert 'No model connected' in page.inner_text('#mode-description') and page.inner_text('#stat-revenue').startswith('$')
        page.click('.suggestion >> nth=2'); page.wait_for_selector('#result-title:has-text("customers")', timeout=30000)
        page.screenshot(path=str(SHOTS/'static-wasm-demo.png')); browser.close()
    assert errors == []
