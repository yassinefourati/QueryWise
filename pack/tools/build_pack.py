"""Regenerate committed SQL and fixtures deterministically. Does not connect to servers."""
import json, hashlib, csv
from pathlib import Path
from sqlalchemy.schema import CreateTable,CreateIndex
from sqlalchemy import UniqueConstraint
from sqlalchemy.dialects import sqlite,postgresql,mysql,mssql,oracle
from ibm_db_sa.base import DB2Dialect
from tools.models import model, SQL_KINDS,TOPICS

ROOT=Path(__file__).resolve().parents[1]
DIALECTS={'sqlite':sqlite.dialect(),'postgres':postgresql.dialect(),'mysql':mysql.dialect(),
          'mariadb':mysql.dialect(),'sqlserver':mssql.dialect(),'oracle':oracle.dialect(),'db2':DB2Dialect()}
def write(path,content):
    p=ROOT/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(content,encoding='utf-8')
def dump(path,obj):write(path,json.dumps(obj,indent=2,default=str)+'\n')
def build():
    for kind in SQL_KINDS:
        s=model(kind);d=DIALECTS[kind]
        ddl=[str(CreateTable(t).compile(dialect=d)).strip() for t in s['metadata'].sorted_tables]
        # Oracle rejects an index on a column list a UNIQUE constraint already indexes (ORA-01408).
        unique=lambda t:{tuple(c.name for c in u.columns) for u in t.constraints if isinstance(u,UniqueConstraint)}
        ddl += [str(CreateIndex(idx).compile(dialect=d)).strip() for t in s['metadata'].sorted_tables for idx in sorted(t.indexes,key=lambda x:x.name)
                if not (kind=='oracle' and tuple(c.name for c in idx.columns) in unique(t))]
        if kind=='oracle': alter=f"ALTER TABLE {s['fact']} ADD ({s['flag']} INTEGER DEFAULT 0 NOT NULL)"
        elif kind in {'sqlserver','mysql','mariadb'}:alter=f"ALTER TABLE {s['fact']} ADD {s['flag']} INTEGER NOT NULL DEFAULT 0"
        else:alter=f"ALTER TABLE {s['fact']} ADD COLUMN {s['flag']} INTEGER DEFAULT 0 NOT NULL"
        upgrade=[alter,f"UPDATE {s['fact']} SET {s['flag']}=CASE WHEN {s['rule']} THEN 1 ELSE 0 END",f"CREATE INDEX ix_{s['fact'][:14]}_flag ON {s['fact']} ({s['flag']})"]
        dump(f'{kind}/migrations.json',[{'version':1,'statements':ddl},{'version':2,'statements':upgrade}])
        for i,statements in [(1,ddl),(2,upgrade)]:
            write(f'{kind}/V{i:03}__'+('schema.sql' if i==1 else 'business_flags.sql'),'-- Generated for '+kind+'. Single-operator lab only. See README before execution.\n'+';\n\n'.join(statements)+';\n')
        seed=[]
        for name,rows in s['data'].items():
            t=s['metadata'].tables[name]
            seed.extend(str(t.insert().values(**row).compile(dialect=d,compile_kwargs={'literal_binds':True}))+';' for row in rows)
        seed.append(upgrade[1]+';')
        begin='BEGIN TRANSACTION;\n' if kind=='sqlserver' else 'BEGIN;\n' if kind in {'sqlite','postgres','mysql','mariadb'} else ''
        write(f'{kind}/seed.sql','-- Scale 1 deterministic synthetic data; run once after V002.\n'+begin+'\n'.join(seed)+'\nCOMMIT;\n')
        write(f'{kind}/analytics.sql','\n\n'.join(f'-- {name}: {question}\n{sql};' for name,question,sql in s['queries'])+'\n')
        dump(f'{kind}/questions.json',[{'id':name,'question':q,'sql':sql,'querywise_compatible':kind!='db2'} for name,q,sql in s['queries']])
        dictionary=[]
        for t in s['metadata'].tables.values():
            for c in t.c:dictionary.append({'table':t.name,'column':c.name,'type':str(c.type),'nullable':c.nullable,'primary_key':c.primary_key,'references':[f.target_fullname for f in c.foreign_keys]})
        dump(f'{kind}/data_dictionary.json',dictionary)
        write(f'{kind}/README.md',f'''# {TOPICS[kind]} — {kind}

Synthetic data; fixed 2026 reporting period. Money is integer CAD cents, not float dollars. Dates have day granularity; no timezone conversion is implied. Each table's primary key defines its grain. Column-level types and relationships are in `data_dictionary.json`.

## Run from the pack root

```sh
python -m tools.sql_runner {kind} migrate --allow-write
python -m tools.sql_runner {kind} seed --allow-write --scale 1
python -m tools.sql_runner {kind} verify --scale 1
python -m tools.sql_runner {kind} status
```

Use `PACK_{kind.upper()}_URL` for the migrator connection. SQLite defaults to `output/library.sqlite`. Set credentials outside the source tree. Provision a dedicated empty database/schema and a separate read-only Querywise account first. A URL does not create the database or install native drivers.

V001 creates {len(s['data'])} tables, foreign keys, checks, unique keys and FK indexes. V002 adds `{s['flag']}` to `{s['fact']}` and backfills it with `{s['rule']}`. It is a migration-time snapshot; subsequent application writes must maintain/recalculate this flag. Seed refreshes it after loading fixtures.

Migrations can also be inspected as SQL files. Choose the Python runner OR manual SQL; manual execution does not update the runner's history. The JSON manifest is the runner's authoritative statement list. Never mix paths on the same schema.

Base fixture: {sum(map(len,s['data'].values()))} rows. `--scale 10` creates ten times the main facts, with dimensions kept stable or expanded where uniqueness requires it. Scale is immutable after seeding: create another database to change it. Seed is fixture loading, not an upsert into operational data.

Verification checks every seeded value and compares analytics with an independently loaded SQLite reference. It is not a claim of optimizer performance, concurrency safety or production throughput. View `analytics.sql` for the advanced business questions. Aggregate independent child tables before joining them to avoid fan-out.

## Recovery

Forward-only migrations. There is no destructive automatic down migration. Take a database-native backup first; for a failed DDL migration restore the dedicated lab schema, diagnose, and retry. A dirty history row must never be marked applied without reconciliation. See `docs/OPERATIONS.md`.
''')
        for action in ['migrate','seed','verify']:
            write(f'{kind}/{action}.py',f"import sys\nfrom pathlib import Path\nsys.path.insert(0,str(Path(__file__).resolve().parents[1]))\nfrom tools.sql_runner import main\nif __name__=='__main__':\n    sys.argv[1:1]=['{kind}','{action}']\n    sys.exit(main())\n")
    print('Generated seven relational domains')
if __name__=='__main__':build()
