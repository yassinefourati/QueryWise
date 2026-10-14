"""A narrow analytics gateway: parsing, allowlists, read-only connectors, bounded results."""
import os, time
from pathlib import Path
import sqlglot
from sqlglot import exp

ROOT = Path(__file__).resolve().parents[1]
ROW_LIMIT, TIMEOUT_SECONDS, MAX_JOINS = 500, 3, 6
# The Northstar sample tables. Connected sources replace this with their discovered tables.
TABLES = {'customers', 'orders', 'order_items', 'products'}
# Pure scalar/aggregate/window functions. File, extension, network, sleep and arbitrary UDF calls stay rejected.
FUNCTIONS = {'SUM','AVG','COUNT','MIN','MAX','ROUND','SUBSTRING','SUBSTR','COALESCE','LOWER','UPPER','LENGTH','ABS','CAST','NULLIF','TRIM','TIME_TO_STR','TS_OR_DS_TO_DATE','DATE','STRFTIME','EXTRACT','DATE_TRUNC','TIMESTAMP_TRUNC','TO_CHAR','ROW_NUMBER','RANK','DENSE_RANK','LAG','LEAD',
             # Conditional/date-part equivalents that sqlglot emits for other dialects, plus SQLite's runtime names for them.
             'CASE','IF','IIF','IFNULL','TS_OR_DS_TO_TIMESTAMP','YEAR','MONTH','DAY','CONCAT'}
DATABASE_URL = os.getenv('DATABASE_URL', '')
if DATABASE_URL and not DATABASE_URL.startswith('postgresql'):
    raise RuntimeError('DATABASE_URL must be PostgreSQL; omit it to use sample SQLite, or add other engines as sources.')
DIALECT = 'postgres' if DATABASE_URL else 'sqlite'  # Dialect of the default source; the active source may differ.

class QueryRejected(ValueError): pass

def validate(sql: str, dialect: str | None = DIALECT, tables=None) -> str:
    """Accept exactly one read-only SELECT over the allowed tables. Returns normalized SQL for `dialect`."""
    allowed = {t.lower() for t in (TABLES if tables is None else tables)}
    if not sql or len(sql) > 12000: raise QueryRejected('SQL must contain 1–12,000 characters.')
    try: trees = sqlglot.parse(sql, read=dialect)
    except sqlglot.errors.ParseError as e: raise QueryRejected('SQL could not be parsed. Check its syntax.') from e
    if len(trees) != 1 or not isinstance(trees[0], exp.Select):
        raise QueryRejected('Only one SELECT statement is allowed.')
    tree = trees[0]
    # SELECT is required for every statement. Data-modifying CTEs and SELECT INTO are rejected.
    forbidden = (exp.Insert, exp.Update, exp.Delete, exp.Create, exp.Drop, exp.Alter, exp.Command, exp.Into, exp.Lock, exp.Union, exp.Intersect, exp.Except)
    if any(isinstance(n, forbidden) for n in tree.walk()):
        raise QueryRejected('Only read-only SELECT queries are supported.')
    if any(w.args.get('recursive') for w in tree.find_all(exp.With)):
        raise QueryRejected('Recursive CTEs are disabled.')
    ctes = {cte.alias.lower() for cte in tree.find_all(exp.CTE)}
    if any(name in allowed for name in ctes): raise QueryRejected('CTE names must not shadow source tables.')
    for table in tree.find_all(exp.Table):
        if not isinstance(table.this, exp.Identifier) or table.name.lower() not in allowed | ctes:
            raise QueryRejected('Query references a table outside the allowed schema.')
        if table.db or table.catalog: raise QueryRejected('Cross-schema access is disabled.')
    for fn in tree.find_all(exp.Func):
        if isinstance(fn, exp.Connector): continue  # AND/OR/XOR are logical operators that sqlglot models as Func.
        name = (fn.name if isinstance(fn, exp.Anonymous) else fn.sql_name()).upper()
        if name not in FUNCTIONS: raise QueryRejected(f'Function {name} is not enabled for analytics.')
    if len(list(tree.find_all(exp.Join))) > MAX_JOINS: raise QueryRejected(f'At most {MAX_JOINS} joins are allowed.')
    # Strip optimizer comments/hints and normalize syntax before the database sees it.
    return tree.sql(dialect=dialect, comments=False)

def json_value(v):
    if v is None or isinstance(v, (bool, int, float, str)): return v
    if hasattr(v, 'as_integer_ratio'): return float(v)  # Decimal
    if hasattr(v, 'isoformat'): return v.isoformat()     # date, datetime, time
    if isinstance(v, (bytes, bytearray, memoryview)): return bytes(v).decode(errors='replace')
    return str(v)                                         # ObjectId, UUID, intervals…

def normalize(rows): return [[json_value(v) for v in row] for row in rows]

def execute(sql: str, source=None) -> dict:
    """Validate against the active (or given) source's discovered tables, then run it read-only."""
    from .sources import registry
    active = source or registry.active()
    safe = validate(sql, active.connector.dialect, active.tables)
    start = time.monotonic()
    columns, rows = active.connector.run(safe, active.tables)
    return {'sql': safe, 'columns': list(columns), 'rows': normalize(rows[:ROW_LIMIT]), 'truncated': len(rows) > ROW_LIMIT,
            'elapsed_ms': round((time.monotonic() - start) * 1000, 1), 'source': active.id}
