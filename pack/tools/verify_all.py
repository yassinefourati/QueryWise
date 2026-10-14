"""Read-only verification. Missing prerequisites are SKIP, never PASS."""
import os,sys,json,argparse,subprocess,shutil
from pathlib import Path
from tools.models import SQL_KINDS
ROOT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser();p.add_argument('--require-all',action='store_true');p.add_argument('--scale',type=int,default=1);a=p.parse_args()
    results=[]
    for kind in [*SQL_KINDS,'mongodb','elasticsearch','excel','parquet']:
        if kind in SQL_KINDS:
            command=[sys.executable,'-m','tools.sql_runner',kind,'verify','--scale',str(a.scale)]
            exists=bool(os.getenv('PACK_'+kind.upper()+'_URL')) or (kind=='sqlite' and (ROOT/'output/library.sqlite').exists())
        elif kind in {'mongodb','elasticsearch'}:
            command=[sys.executable,'-m','tools.'+('mongo_runner' if kind=='mongodb' else 'elastic_runner'),'verify','--scale',str(a.scale)]
            exists=bool(os.getenv('PACK_'+kind.upper()+'_URL'))
        elif kind=='parquet':
            command=[sys.executable,'-m','tools.parquet_runner','verify','--scale',str(a.scale)];exists=(ROOT/'output/sensors/v2/manifest.json').exists()
        else:
            command=['pwsh','-File',str(ROOT/'excel/migrate.ps1'),'-Action','verify'];exists=os.name=='nt' and bool(shutil.which('pwsh')) and (ROOT/'output/grants/grants-v2.xlsx').exists()
        if not exists:results.append({'source':kind,'status':'SKIP','reason':'Endpoint, fixture or required native runtime unavailable'});continue
        try:
            r=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=300)
            results.append({'source':kind,'status':'PASS' if r.returncode==0 else 'FAIL','exit_code':r.returncode})
        except subprocess.TimeoutExpired:results.append({'source':kind,'status':'FAIL','reason':'Verification timeout'})
    (ROOT/'reports').mkdir(exist_ok=True)
    (ROOT/'reports/live-results.json').write_text(json.dumps(results,indent=2))
    print(json.dumps(results,indent=2))
    return int(any(r['status']=='FAIL' or (a.require_all and r['status']=='SKIP') for r in results))
if __name__=='__main__':sys.exit(main())
