"""Versioned single-operator lab migrations. Never logs connection URLs."""
import argparse, hashlib, json, os, sys
from pathlib import Path
from datetime import date, datetime
from decimal import Decimal
from sqlalchemy import create_engine, MetaData, Table, Column, String, Integer, select, text, event
from tools.models import model, SQL_KINDS

ROOT=Path(__file__).resolve().parents[1]
def digest(b): return hashlib.sha256(b).hexdigest()
def canonical(v):
    if isinstance(v,(date,datetime)): return v.isoformat()
    if isinstance(v,(Decimal,float)): return str(Decimal(str(v)).normalize())
    return v
def close(a,b):
    if a is None or b is None: return a is b
    if isinstance(a,(int,float,Decimal)) and isinstance(b,(int,float,Decimal)):
        return abs(Decimal(str(a))-Decimal(str(b)))<=Decimal('0.000001')
    return canonical(a)==canonical(b)
def connect(kind,url_env=None):
    env=url_env or f'PACK_{kind.upper()}_URL'
    url=os.getenv(env)
    if kind=='sqlite' and not url:
        (ROOT/'output').mkdir(exist_ok=True)
        url='sqlite:///'+str(ROOT/'output/library.sqlite')
    if not url: raise RuntimeError(f'Missing environment variable {env}')
    e=create_engine(url,pool_pre_ping=True)
    expected={'postgres':'postgresql','sqlserver':'mssql','db2':'ibm_db_sa'}.get(kind,kind)
    if e.dialect.name not in ({'mysql','mariadb'} if kind=='mariadb' else {expected}):
        raise RuntimeError('Connection dialect does not match selected source')
    if kind=='sqlite':
        @event.listens_for(e,'connect')
        def fk(dbapi,_): dbapi.execute('PRAGMA foreign_keys=ON')
    return e
def ledger(e):
    m=MetaData()
    t=Table('qw_pack_history',m,Column('version',String(80),primary_key=True),
            Column('checksum',String(64),nullable=False),Column('state',String(16),nullable=False))
    m.create_all(e)
    return t
def apply_step(e,h,key,checksum,operation):
    with e.begin() as c:
        old=c.execute(select(h).where(h.c.version==key)).mappings().first()
        if old:
            if old['checksum']!=checksum or old['state']!='applied':
                raise RuntimeError(f'{key}: checksum mismatch or dirty migration. Restore/reconcile before retrying; never edit history blindly.')
            print(f'{key}: already applied');return
        c.execute(h.insert().values(version=key,checksum=checksum,state='dirty'))
    operation()
    with e.begin() as c:
        c.execute(h.update().where(h.c.version==key).values(state='applied'))
    print(f'{key}: applied')
def migrate(e,kind,target):
    folder=ROOT/kind
    steps=json.loads((folder/'migrations.json').read_text())
    h=ledger(e)
    # Persistent mutex. A crashed process leaves it present intentionally.
    with e.begin() as c:
        c.execute(h.insert().values(version='__lock__',checksum='single-operator',state='locked'))
    try:
        for step in steps:
            if step['version']>target: continue
            # JSON holds statement boundaries; never split arbitrary SQL on semicolons.
            statements=step['statements']
            checksum=digest(json.dumps(statements,sort_keys=True).encode())
            def run(statements=statements):
                for sql in statements:
                    with e.begin() as c: c.execute(text(sql))
            apply_step(e,h,f'{kind}:V{step["version"]:03}',checksum,run)
    finally:
        with e.begin() as c: c.execute(h.delete().where(h.c.version=='__lock__'))
def seed(e,kind,scale):
    spec=model(kind,scale);h=ledger(e)
    checksum=digest((ROOT/'tools/models.py').read_bytes()+str(scale).encode())
    def run():
        with e.begin() as c:
            for name,rows in spec['data'].items():
                if rows: c.execute(spec['metadata'].tables[name].insert(),rows)
    apply_step(e,h,f'{kind}:seed',checksum,run)
    # Upgrade flags are derived from data, including newly seeded rows.
    with e.begin() as c:
        c.execute(text(f"UPDATE {spec['fact']} SET {spec['flag']} = CASE WHEN {spec['rule']} THEN 1 ELSE 0 END"))
def verify(e,kind,scale):
    spec=model(kind,scale); checks=[]
    with e.connect() as c:
        for name,expected in spec['data'].items():
            t=spec['metadata'].tables[name]
            actual=c.execute(select(t).order_by(t.c.id)).mappings().all()
            assert len(actual)==len(expected),f'{name}: row count'
            for a,b in zip(actual,expected):
                assert all(close(a[k],v) for k,v in b.items()),f'{name}: value mismatch at id {b["id"]}'
            checks.append(f'{name}: exact fixture rows')
        # Expected results from independent SQLite execution of same fixture.
        reference=create_engine('sqlite://')
        spec['metadata'].create_all(reference)
        with reference.begin() as r:
            for name,rows in spec['data'].items():
                if rows:r.execute(spec['metadata'].tables[name].insert(),rows)
            r.execute(text(f"ALTER TABLE {spec['fact']} ADD COLUMN {spec['flag']} INTEGER DEFAULT 0 NOT NULL"))
            r.execute(text(f"UPDATE {spec['fact']} SET {spec['flag']}=CASE WHEN {spec['rule']} THEN 1 ELSE 0 END"))
            for name,_,sql in spec['queries']:
                expected=r.execute(text(sql)).fetchall(); actual=c.execute(text(sql)).fetchall()
                assert len(actual)==len(expected) and all(len(a)==len(b) and all(close(x,y) for x,y in zip(a,b)) for a,b in zip(actual,expected)),f'{name}: analytics mismatch'
                checks.append(f'{name}: query results')
        reference.dispose()
    return checks
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('kind',choices=SQL_KINDS);p.add_argument('action',choices=['migrate','seed','verify','status'])
    p.add_argument('--url-env');p.add_argument('--scale',type=int,default=1);p.add_argument('--target',type=int,choices=[1,2],default=2)
    p.add_argument('--allow-write',action='store_true')
    a=p.parse_args()
    if a.action in {'migrate','seed'} and not a.allow_write:p.error('Mutation requires --allow-write on a dedicated empty lab database/schema')
    e=None
    try:
        e=connect(a.kind,a.url_env)
        if a.action=='migrate':migrate(e,a.kind,a.target)
        elif a.action=='seed':seed(e,a.kind,a.scale)
        elif a.action=='verify':print(json.dumps({'source':a.kind,'status':'PASS','checks':verify(e,a.kind,a.scale)},indent=2))
        else:
            with e.connect() as c: print(json.dumps([dict(r) for r in c.execute(text('SELECT version,state,checksum FROM qw_pack_history ORDER BY version')).mappings()],indent=2))
    except Exception as exc:
        # Driver exceptions can contain passwords, URLs or hostnames.
        print(f'{a.kind}: FAIL ({type(exc).__name__}). See docs/TROUBLESHOOTING.md; connection details redacted.',file=sys.stderr)
        return 1
    finally:
        if e is not None:e.dispose()
    return 0
if __name__=='__main__':sys.exit(main())
