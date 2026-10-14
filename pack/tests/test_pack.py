import json
import sqlite3
from pathlib import Path
import pytest
from sqlalchemy import create_engine,text,event,select
from sqlalchemy.exc import IntegrityError
from tools.models import model,SQL_KINDS
from tools.sql_runner import migrate,seed,verify,ledger,apply_step
from tools.parquet_runner import build,verify as verify_parquet,read_manifest
from tools.document_fixtures import fixtures
from tools.mongo_runner import validators
from tools.elastic_runner import mapping

@pytest.mark.parametrize('kind',SQL_KINDS)
def test_business_model_constraints_and_analytics(kind):
    # Executes business logic on SQLite, NOT on the named remote engine.
    s=model(kind);e=create_engine('sqlite://')
    @event.listens_for(e,'connect')
    def enable(conn,_):conn.execute('PRAGMA foreign_keys=ON')
    s['metadata'].create_all(e)
    with e.begin() as c:
        for name,rows in s['data'].items():
            if rows:c.execute(s['metadata'].tables[name].insert(),rows)
        c.execute(text(f"ALTER TABLE {s['fact']} ADD COLUMN {s['flag']} INTEGER DEFAULT 0 NOT NULL"))
        c.execute(text(f"UPDATE {s['fact']} SET {s['flag']}=CASE WHEN {s['rule']} THEN 1 ELSE 0 END"))
    assert len(verify(e,kind,1))==len(s['data'])+3
    # A real foreign-key violation must fail with FK enforcement enabled.
    t=s['metadata'].tables[s['fact']]
    key=next(col.name for col in t.c if col.foreign_keys)
    invalid=dict(s['data'][s['fact']][0],id=999999);invalid[key]=999999
    with pytest.raises(IntegrityError):
        with e.begin() as c:c.execute(t.insert().values(**invalid))
    e.dispose()

def test_sqlite_upgrade_resume_and_seed():
    e=create_engine('sqlite://')
    migrate(e,'sqlite',1)
    s=model('sqlite')
    with e.begin() as c:
        for n,rows in s['data'].items():
            if rows:c.execute(s['metadata'].tables[n].insert(),rows)
    migrate(e,'sqlite',2);migrate(e,'sqlite',2)
    assert len(verify(e,'sqlite',1))==10
    with e.connect() as c:
        assert c.execute(text('SELECT SUM(overdue_flag) FROM loans')).scalar()==24

def test_sqlite_standalone_sql_scripts():
    root=Path(__file__).resolve().parents[1]
    with sqlite3.connect(':memory:') as c:
        c.execute('PRAGMA foreign_keys=ON')
        for filename in ['V001__schema.sql','V002__business_flags.sql','seed.sql']:
            c.executescript((root/'sqlite'/filename).read_text())
        assert c.execute('SELECT COUNT(*) FROM loans').fetchone()[0]==120
        assert c.execute('SELECT SUM(overdue_flag) FROM loans').fetchone()[0]==24

def test_seed_idempotency_and_scale_change():
    e=create_engine('sqlite://');migrate(e,'sqlite',2);seed(e,'sqlite',1);seed(e,'sqlite',1)
    with pytest.raises(RuntimeError):seed(e,'sqlite',2)
    assert len(verify(e,'sqlite',1))==10

def test_dirty_migration_blocks_retry():
    e=create_engine('sqlite://');h=ledger(e)
    def fail():raise RuntimeError('simulated interrupted DDL')
    with pytest.raises(RuntimeError):apply_step(e,h,'test','abc',fail)
    with pytest.raises(RuntimeError):apply_step(e,h,'test','abc',lambda:None)
    with e.connect() as c:assert c.execute(select(h.c.state).where(h.c.version=='test')).scalar()=='dirty'

def test_checksum_change_blocks_retry():
    e=create_engine('sqlite://');h=ledger(e)
    apply_step(e,h,'test','abc',lambda:None)
    with pytest.raises(RuntimeError):apply_step(e,h,'test','changed',lambda:None)

def test_existing_migration_lock_blocks():
    e=create_engine('sqlite://');h=ledger(e)
    with e.begin() as c:c.execute(h.insert().values(version='__lock__',checksum='x',state='locked'))
    with pytest.raises(IntegrityError):migrate(e,'sqlite',2)

def test_retail_independent_reconciliation():
    d=model('mysql')['data'];orders={r['id']:r for r in d['orders']}
    for o in d['orders']:
        total=sum(l['quantity']*l['unit_cents']-l['discount_cents'] for l in d['order_lines'] if l['order_id']==o['id'])
        paid=sum(p['amount_cents'] for p in d['payments'] if p['order_id']==o['id'])
        assert paid==(total if o['status']=='completed' else 0)
    for r in d['returns']:
        l=next(l for l in d['order_lines'] if l['id']==r['line_id'])
        assert orders[l['order_id']]['status']=='completed' and r['quantity']<=l['quantity']

def test_insurance_independent_reconciliation():
    d=model('db2')['data']
    for claim in d['claims']:
        reserve=sum(r['delta_cents'] for r in d['reserve_changes'] if r['claim_id']==claim['id'])
        assert reserve==(150000 if claim['status']=='open' else 0)

def test_mongo_references_and_additive_contract():
    d=fixtures('mongodb')
    assert all(r['learner_id'] in {x['_id'] for x in d['learners']} and r['course_id'] in {x['_id'] for x in d['courses']} for r in d['enrollments'])
    assert all(r['enrollment_id'] in {x['_id'] for x in d['enrollments']} for r in d['attempts'])
    assert len({(r['learner_id'],r['course_id'],r['cohort']) for r in d['enrollments']})==120
    assert 'learning_minutes' not in validators(1)['enrollments']['$jsonSchema']['required']
    assert 'learning_minutes' in validators(2)['enrollments']['$jsonSchema']['required']

def test_search_fixture_mapping_and_conversion():
    d=fixtures('elasticsearch')
    for name,rows in d.items():
        props=mapping(name)['properties']
        assert all(set(row)<=set(props) for row in rows)
    assert mapping('requests',2)['properties']['latency_seconds']['type']=='double'
    assert all(r['deployment_id'] in {x['deployment_id'] for x in d['deployments']} for r in d['requests'])
    assert any(r['duration_ms']==0 for r in fixtures('elasticsearch',10)['requests'])

def test_excel_fixture_relationships_and_balances():
    d=fixtures('excel');awards={a['id']:a for a in d['awards']}
    for row in d['disbursements']:
        assert row['award_id'] in awards and awards[row['award_id']]['status']=='approved'
    for a in d['awards']:
        paid=sum(r['amount_cents'] for r in d['disbursements'] if r['award_id']==a['id'])
        assert 0<=paid<=a['committed_cents']
    assert len(d['milestones'])==len(awards)

def test_parquet_native_upgrade(tmp_path):
    build(1,tmp_path,1);build(2,tmp_path,1)
    assert verify_parquet(tmp_path,1)['readings']==1200
    with pytest.raises(RuntimeError):build(2,tmp_path,1)

def test_parquet_checksum_detects_change(tmp_path):
    build(1,tmp_path,1)
    path=tmp_path/'v1/sites.parquet';path.write_bytes(path.read_bytes()+b'changed')
    with pytest.raises(ValueError):read_manifest(tmp_path/'v1')

@pytest.mark.parametrize('kind',SQL_KINDS)
def test_scale_doubles_facts_without_duplicate_ids(kind):
    s=model(kind,2)
    assert len(s['data'][s['fact']])==240
    for rows in s['data'].values():assert len({r['id'] for r in rows})==len(rows)
