"""Create a secret-free source registry for the Querywise app (QUERYWISE_SOURCES_FILE). Choose only available sources.
Entries name environment variables (url_env/path_env/api_key_env); the app reads the values at runtime."""
import argparse,json,os
from pathlib import Path
from tools.models import model,TOPICS,SQL_KINDS
ROOT=Path(__file__).resolve().parents[1]
def configuration(kinds):
    result=[]
    for kind in kinds:
        cfg={'id':'complex_'+kind,'kind':kind,'name':TOPICS[kind],
             'description':'Synthetic complex business migration fixture',
             'definitions':'Dates refer to 2026. Money is integer CAD cents. Never mix cents and dollars. Pre-aggregate independent child relations before joining. Missing values are not zero. Migration flags are snapshots, not continuously calculated fields.'}
        if kind in SQL_KINDS:
            cfg['url_env']='QUERYWISE_'+kind.upper()+'_URL'
            cfg['tables']=list(model(kind)['data'])
            cfg['questions']=f'pack/{kind}/questions.json'
            if kind=='postgres':cfg['schema']='public'
            if kind in {'oracle','db2'}:cfg['schema']=os.getenv('PACK_'+kind.upper()+'_SCHEMA','QW_COMPLEX')
            if kind=='db2':cfg['definitions']+=' Db2 runs through the generic ANSI SQL path; review analytics.sql for native-only joins.'
        elif kind=='mongodb':
            cfg.update(url_env='QUERYWISE_MONGODB_URL',database='qw_complex_learning',tables=['courses','learners','enrollments','attempts'])
        elif kind=='elasticsearch':
            cfg.update(url_env='QUERYWISE_ELASTICSEARCH_URL',tables=['qw-complex-reliability-requests','qw-complex-reliability-deployments-v1','qw-complex-reliability-incidents-v1'],options={'api_key_env':'QUERYWISE_ELASTICSEARCH_API_KEY'})
        else:
            # Excel: a .xlsx workbook (or the CSV fixture folder). Parquet: the v2 folder, one table per file.
            cfg.update(path_env='QUERYWISE_'+kind.upper()+'_PATH')
            if kind=='parquet':cfg['tables']=['analytics_readings','readings','sensors','sites','calibrations']
            else:cfg['tables']=['donors','programs','awards','disbursements','milestones']
        result.append(cfg)
    return result
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--only',nargs='+',choices=list(TOPICS),required=True);p.add_argument('--output',type=Path,default=ROOT/'querywise-sources.json');a=p.parse_args()
    if a.output.exists():p.error('Output exists; choose a new file to avoid overwriting your registry')
    a.output.write_text(json.dumps(configuration(a.only),indent=2));print(a.output)
if __name__=='__main__':main()
