"""Immutable sensor dataset versions. A completed directory is published by rename."""
import argparse,json,hashlib,os,shutil,sys,tempfile
from pathlib import Path
from tools.document_fixtures import fixtures
ROOT=Path(__file__).resolve().parents[1]
SCHEMAS={
 'sites':'id INTEGER, region VARCHAR, latitude DECIMAL(9,6), longitude DECIMAL(9,6)',
 'sensors':'id INTEGER, site_id INTEGER, serial VARCHAR, unit VARCHAR',
 'readings':'id BIGINT, sensor_id INTEGER, observed_on DATE, value_c DECIMAL(8,3)',
 'calibrations':'id INTEGER, sensor_id INTEGER, calibrated_on DATE, offset_c DECIMAL(8,3)'}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def literal(p):return "'"+str(p).replace("'","''")+"'"
def read_manifest(folder):
    manifest=json.loads((folder/'manifest.json').read_text())
    for name,h in manifest['sha256'].items():
        p=(folder/name).resolve()
        if not p.is_relative_to(folder.resolve()):raise ValueError('Invalid manifest path')
        if sha(p)!=h:raise ValueError('Dataset checksum mismatch')
    return manifest
def build(version,base,scale):
    import duckdb
    base.mkdir(parents=True,exist_ok=True);target=base/f'v{version}'
    if target.exists():raise RuntimeError('Version exists; verify it or select a new output directory')
    tmp=Path(tempfile.mkdtemp(prefix=f'v{version}-staging-',dir=base));c=duckdb.connect()
    try:
        if version==1:
            for name,rows in fixtures('parquet',scale).items():
                c.execute(f'CREATE TABLE {name} ({SCHEMAS[name]})')
                c.executemany(f'INSERT INTO {name} VALUES ({",".join("?" for _ in rows[0])})',[list(r.values()) for r in rows])
                c.execute(f'COPY {name} TO {literal(tmp/(name+".parquet"))} (FORMAT PARQUET, COMPRESSION ZSTD)')
        else:
            previous=read_manifest(base/'v1')
            if previous['scale']!=scale:raise ValueError('Scale differs from v1')
            for name in SCHEMAS:
                source=base/'v1'/(name+'.parquet')
                if name!='readings':shutil.copy2(source,tmp/source.name)
                c.execute(f'CREATE VIEW {name} AS SELECT * FROM read_parquet({literal(source)})')
            c.execute("CREATE VIEW upgraded AS SELECT id,sensor_id,observed_on,value_c AS temperature_c, CASE WHEN value_c IS NULL THEN 'missing' WHEN value_c < -5 OR value_c > 30 THEN 'outlier' ELSE 'valid' END quality FROM readings")
            c.execute(f'COPY upgraded TO {literal(tmp/"readings.parquet")} (FORMAT PARQUET, COMPRESSION ZSTD)')
            # A flat serving file works with Querywise's single-Parquet registration.
            c.execute(f'''COPY (SELECT r.*,s.site_id,p.region,p.latitude,p.longitude,
                r.temperature_c+k.offset_c calibrated_c FROM upgraded r
                JOIN sensors s ON s.id=r.sensor_id JOIN sites p ON p.id=s.site_id
                JOIN calibrations k ON k.sensor_id=s.id)
                TO {literal(tmp/'analytics_readings.parquet')} (FORMAT PARQUET, COMPRESSION ZSTD)''')
        manifest={'version':version,'scale':scale,'sha256':{p.name:sha(p) for p in sorted(tmp.glob('*.parquet'))}}
        (tmp/'manifest.json').write_text(json.dumps(manifest,indent=2))
        os.rename(tmp,target)
    finally:
        c.close()
        if tmp.exists():shutil.rmtree(tmp)
def verify(base,scale):
    import duckdb
    c=duckdb.connect();s=fixtures('parquet',scale)
    try:
        for version in [1,2]:
            folder=base/f'v{version}';m=read_manifest(folder);assert m['scale']==scale
            for name,rows in s.items():
                actual=c.execute(f'SELECT * FROM read_parquet({literal(folder/(name+".parquet"))}) ORDER BY id').fetchall()
                assert len(actual)==len(rows)
                for a,r in zip(actual,rows):
                    expected=list(r.values())
                    if version==2 and name=='readings':
                        v=r['value_c'];expected+=['missing' if v is None else 'outlier' if v < -5 or v > 30 else 'valid']
                    for x,y in zip(a,expected):
                        if y is None:assert x is None
                        elif isinstance(y,(int,float)):assert abs(float(x)-y)<1e-6
                        else:assert str(x)==y
            if version==2:
                p=literal(folder/'analytics_readings.parquet')
                count,missing=c.execute(f"SELECT COUNT(*),SUM(CASE WHEN quality='missing' THEN 1 ELSE 0 END) FROM read_parquet({p})").fetchone()
                assert count==len(s['readings']) and missing==sum(r['value_c'] is None for r in s['readings'])
                # Check calibration join cardinality and transformation, not just counts.
                result=c.execute(f'SELECT id,calibrated_c FROM read_parquet({p}) ORDER BY id').fetchall()
                for (_,v),r in zip(result,s['readings']):
                    expected=None if r['value_c'] is None else r['value_c']+(0.1 if r['sensor_id']%2 else -0.1)
                    assert (v is None and expected is None) or (v is not None and expected is not None and abs(float(v)-expected)<1e-6)
        return {'source':'parquet','status':'PASS','readings':len(s['readings']),'versions':[1,2]}
    finally:c.close()
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['seed','migrate','verify']);p.add_argument('--output',type=Path,default=ROOT/'output/sensors');p.add_argument('--scale',type=int,default=1);a=p.parse_args()
    if a.action=='verify':print(json.dumps(verify(a.output,a.scale)))
    else:build(1 if a.action=='seed' else 2,a.output,a.scale);print(f'{a.action}: complete')
if __name__=='__main__':main()
