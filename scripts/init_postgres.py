"""Initialize ONLY an empty development database, with a schema identical to the sample."""
import json, os
from pathlib import Path
from sqlalchemy import create_engine, inspect, text
ROOT=Path(__file__).resolve().parents[1]
url=os.environ['POSTGRES_ADMIN_URL']
engine=create_engine(url)
with engine.begin() as conn:
    if inspect(conn).get_table_names(schema='public'):
        raise SystemExit('Refusing to seed a non-empty public schema. Use an empty development database.')
    payload=json.loads((ROOT/'dist/dataset.json').read_text())
    for stmt in payload['schema'].split(';'):
        if stmt.strip(): conn.execute(text(stmt))
    for table,rows in payload['data'].items():
        names=[f'p{i}' for i in range(len(rows[0]))]
        sql=text(f'INSERT INTO {table} VALUES ({",".join(":"+n for n in names)})')
        conn.execute(sql,[dict(zip(names,row)) for row in rows])
print('Development PostgreSQL database seeded. Create a SELECT-only application role per README.')
