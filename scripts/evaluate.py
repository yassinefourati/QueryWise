"""Evaluate result correctness, not exact model-generated SQL text."""
import argparse, json, time, urllib.request, urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description='Run evals/cases.json against the default Northstar source (select it in Settings first).');p.add_argument('--url',default='http://localhost:8000');args=p.parse_args()
def post(route,body):
    req=urllib.request.Request(args.url.rstrip('/')+'/api/'+route,data=json.dumps(body).encode(),headers={'Content-Type':'application/json','X-Querywise-Client':'1'})
    try:
        with urllib.request.urlopen(req,timeout=100) as r:return r.status,json.load(r)
    except urllib.error.HTTPError as e:return e.code,json.load(e)
def canonical(rows):
    return sorted([tuple(round(v,2) if isinstance(v,(float,int)) else v for v in row) for row in rows],key=str)
results=[]
for case in json.loads((ROOT/'evals/cases.json').read_text()):
    start=time.monotonic()
    try:
        status,answer=post('ask',{'question':case['question']})
        if case.get('clarification'):
            ok=status==422
        else:
            ref_status,reference=post('query',{'sql':case['sql']})
            ok=status==200 and ref_status==200 and canonical(answer['rows'])==canonical(reference['rows'])
        result={'question':case['question'],'passed':ok,'seconds':round(time.monotonic()-start,2),'response':answer}
    except Exception as e:result={'question':case['question'],'passed':False,'error':str(e)}
    results.append(result);print(('PASS' if result['passed'] else 'FAIL')+' '+case['question'])
Path('eval-results.json').write_text(json.dumps(results,indent=2))
print(f'{sum(r["passed"] for r in results)}/{len(results)} passed. Results: eval-results.json')
