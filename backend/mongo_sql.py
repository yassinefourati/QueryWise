"""Translate a validated, single-collection SELECT into a read-only MongoDB aggregation pipeline.

Supported: column/alias projection, *, WHERE (=, <>, <, <=, >, >=, IN, BETWEEN, LIKE, IS [NOT] NULL, AND/OR/NOT),
GROUP BY, COUNT(*)/COUNT(col)/COUNT(DISTINCT col)/SUM/AVG/MIN/MAX, ROUND around those, ORDER BY, LIMIT, OFFSET.
Anything else is rejected with a clear message; the pipeline never contains $out, $merge, $lookup or $function."""
import re
import sqlglot
from sqlglot import exp
from .database import QueryRejected

LIMITS = 'MongoDB sources support single-collection SELECTs with WHERE, GROUP BY, aggregates, ORDER BY and LIMIT.'
COMPARE = {exp.EQ: '$eq', exp.NEQ: '$ne', exp.GT: '$gt', exp.GTE: '$gte', exp.LT: '$lt', exp.LTE: '$lte'}
FLIP = {'$gt': '$lt', '$gte': '$lte', '$lt': '$gt', '$lte': '$gte', '$eq': '$eq', '$ne': '$ne'}
AGGREGATES = {exp.Sum: '$sum', exp.Avg: '$avg', exp.Min: '$min', exp.Max: '$max'}

def unsupported(what): raise QueryRejected(f'{what} cannot be translated for MongoDB. {LIMITS}')

def literal(node):
    if isinstance(node, exp.Paren): return literal(node.this)
    if isinstance(node, exp.Null): return None
    if isinstance(node, exp.Boolean): return node.this
    if isinstance(node, exp.Neg): return -literal(node.this)
    if isinstance(node, exp.Literal):
        if node.is_string: return node.this
        text = node.this
        return float(text) if any(c in text for c in '.eE') else int(text)
    unsupported(f'The value {node.sql()}')

def field(node):
    if isinstance(node, exp.Paren): return field(node.this)
    if isinstance(node, exp.Column): return node.name
    unsupported(f'The expression {node.sql()}')

def condition(node):
    if isinstance(node, exp.Paren): return condition(node.this)
    if isinstance(node, exp.And): return {'$and': [condition(node.left), condition(node.right)]}
    if isinstance(node, exp.Or): return {'$or': [condition(node.left), condition(node.right)]}
    if isinstance(node, exp.Not):
        inner = node.this.this if isinstance(node.this, exp.Paren) else node.this
        if isinstance(inner, exp.Is): return {field(inner.this): {'$ne': None}}
        return {'$nor': [condition(node.this)]}
    if type(node) in COMPARE:
        op = COMPARE[type(node)]
        if isinstance(node.left, exp.Column): return {field(node.left): {op: literal(node.right)}}
        if isinstance(node.right, exp.Column): return {field(node.right): {FLIP[op]: literal(node.left)}}
        unsupported(f'The comparison {node.sql()}')
    if isinstance(node, exp.In):
        if node.args.get('query'): unsupported('A subquery')
        return {field(node.this): {'$in': [literal(v) for v in node.expressions]}}
    if isinstance(node, exp.Between): return {field(node.this): {'$gte': literal(node.args['low']), '$lte': literal(node.args['high'])}}
    if isinstance(node, exp.Is): return {field(node.this): None}
    if isinstance(node, exp.Like):
        pattern = '^' + ''.join('.*' if c == '%' else '.' if c == '_' else re.escape(c) for c in literal(node.expression)) + '$'
        return {field(node.this): {'$regex': pattern}}
    unsupported(f'The condition {node.sql()}')

def output_name(node):
    return node.alias if isinstance(node, exp.Alias) else node.name if isinstance(node, exp.Column) else node.sql()

def aggregate(node, key):
    """Return a $group accumulator, or None when `node` is not an aggregate."""
    if isinstance(node, exp.Count):
        arg = node.this
        if isinstance(arg, exp.Star) or arg is None: return {key: {'$sum': 1}}, None
        if isinstance(arg, exp.Distinct): return {key: {'$addToSet': '$' + field(arg.expressions[0])}}, {'$size': '$' + key}
        return {key: {'$sum': {'$cond': [{'$gt': ['$' + field(arg), None]}, 1, 0]}}}, None
    if type(node) in AGGREGATES: return {key: {AGGREGATES[type(node)]: '$' + field(node.this)}}, None
    return None

def translate(sql, fields, fetch):
    """Return (collection, pipeline, output columns). `fields` maps lowercase collection names to discovered fields."""
    tree = sqlglot.parse_one(sql)
    if not isinstance(tree, exp.Select): unsupported('This statement')
    if tree.args.get('with'): unsupported('A CTE')
    if tree.args.get('joins'): unsupported('A join')
    if tree.args.get('having'): unsupported('HAVING')
    if tree.args.get('distinct'): unsupported('SELECT DISTINCT')
    if any(isinstance(n, (exp.Subquery, exp.Window)) for n in tree.walk()): unsupported('A subquery or window function')
    source = tree.args.get('from') or tree.args.get('from_')
    if not source or not isinstance(source.this, exp.Table): unsupported('A query without a collection')
    collection = source.this.name
    pipeline = []
    if tree.args.get('where'): pipeline.append({'$match': condition(tree.args['where'].this)})
    groups = [field(g) for g in (tree.args['group'].expressions if tree.args.get('group') else [])]
    selected = tree.expressions
    has_aggregate = any(n.find(exp.AggFunc) for n in selected)
    order = tree.args['order'].expressions if tree.args.get('order') else []
    if groups or has_aggregate:
        group, project, columns = {'_id': {f'g{i}': '$' + g for i, g in enumerate(groups)} if groups else None}, {'_id': 0}, []
        for i, node in enumerate(selected):
            name, inner = output_name(node), node.this if isinstance(node, exp.Alias) else node
            rounding = None
            if isinstance(inner, exp.Round):
                rounding = literal(inner.args['decimals']) if inner.args.get('decimals') else 0
                inner = inner.this
            if isinstance(inner, exp.Column) and inner.name in groups: value = f'$_id.g{groups.index(inner.name)}'
            else:
                result = aggregate(inner, f'a{i}')
                if not result: unsupported(f'The select expression {node.sql()}')
                accumulator, final = result; group.update(accumulator); value = final or f'$a{i}'
            project[name] = {'$round': [value, rounding]} if rounding is not None else value
            columns.append(name)
        pipeline += [{'$group': group}, {'$project': project}]
        sort = {}
        for o in order:
            target = o.this
            name = next((output_name(s) for s in selected if (s.this if isinstance(s, exp.Alias) else s) == target or output_name(s) == output_name(target)), None)
            if name is None: unsupported(f'ORDER BY {target.sql()} (order by a selected column or alias)')
            sort[name] = -1 if o.args.get('desc') else 1
        if sort: pipeline.append({'$sort': sort})
    else:
        if any(isinstance(n, exp.Star) for n in selected): columns = fields.get(collection.lower(), ['_id']); project = {c: 1 for c in columns}
        else:
            project, columns = {}, []
            for node in selected:
                name = output_name(node); project[name] = '$' + field(node.this if isinstance(node, exp.Alias) else node); columns.append(name)
        if '_id' not in columns: project['_id'] = 0
        aliases = {output_name(n): field(n.this) for n in selected if isinstance(n, exp.Alias)}
        sort = {aliases.get(field(o.this), field(o.this)): -1 if o.args.get('desc') else 1 for o in order}
        if sort: pipeline.append({'$sort': sort})  # Sort on source fields before projecting.
    offset = tree.args.get('offset')
    if offset: pipeline.append({'$skip': literal(offset.expression)})
    limit = tree.args.get('limit')
    cap = min(literal(limit.expression), fetch) if limit else fetch
    if not (groups or has_aggregate): pipeline.append({'$limit': cap}); pipeline.append({'$project': project})
    else: pipeline.append({'$limit': cap})
    return collection, pipeline, columns
