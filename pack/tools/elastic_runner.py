"""Versioned reliability indices, blocking reindex and atomic read-alias switch."""
import os,argparse,json,sys
from tools.document_fixtures import fixtures
PREFIX='qw-complex-reliability-'
def mapping(name,version=1):
    fields={'observed_at':{'type':'date'},'service':{'type':'keyword'}}
    if name=='requests':fields.update(event_id={'type':'keyword'},environment={'type':'keyword'},duration_ms={'type':'long'},status_code={'type':'integer'},trace_id={'type':'keyword'},deployment_id={'type':'keyword'},location={'type':'geo_point'},schema_version={'type':'integer'})
    if name=='deployments':fields.update(deployment_id={'type':'keyword'},version={'type':'keyword'},result={'type':'keyword'})
    if name=='incidents':fields.update(incident_id={'type':'keyword'},severity={'type':'keyword'},recovery_minutes={'type':'integer'})
    if name=='requests' and version==2:fields['latency_seconds']={'type':'double'}
    return {'dynamic':'strict','properties':fields}
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['migrate','seed','verify']);p.add_argument('--target',type=int,choices=[1,2],default=2);p.add_argument('--scale',type=int,default=1);p.add_argument('--allow-write',action='store_true');a=p.parse_args()
    if a.action!='verify' and not a.allow_write:p.error('--allow-write required; pause all writers during migration')
    from elasticsearch import Elasticsearch,helpers
    url=os.environ.get('PACK_ELASTICSEARCH_URL')
    if not url:p.error('Set PACK_ELASTICSEARCH_URL')
    options={'request_timeout':120}
    if os.environ.get('PACK_ELASTICSEARCH_API_KEY'):options['api_key']=os.environ['PACK_ELASTICSEARCH_API_KEY']
    if os.environ.get('PACK_ELASTICSEARCH_CA_CERT'):options['ca_certs']=os.environ['PACK_ELASTICSEARCH_CA_CERT']
    client=Elasticsearch(url,**options);spec=fixtures('elasticsearch',a.scale)
    try:
        if a.action=='migrate':
            for name in spec:
                idx=PREFIX+name+'-v1'
                if not client.indices.exists(index=idx):client.indices.create(index=idx,mappings=mapping(name),settings={'number_of_shards':1,'number_of_replicas':0})
            alias=PREFIX+'requests';v1=alias+'-v1';v2=alias+'-v2'
            if not client.indices.exists_alias(name=alias):client.indices.put_alias(index=v1,name=alias)
            if a.target==2:
                if client.indices.exists(index=v2):
                    targets=client.indices.get_alias(name=alias)
                    if v2 in targets:print('Already migrated to v2');return
                    raise RuntimeError('Unswitched v2 exists. Inspect failed reindex before recovery; destination will not be overwritten')
                client.indices.create(index=v2,mappings=mapping('requests',2),settings={'number_of_shards':1,'number_of_replicas':0})
                response=client.reindex(source={'index':v1},dest={'index':v2,'op_type':'create'},script={'lang':'painless','source':'ctx._source.latency_seconds = ctx._source.duration_ms / 1000.0; ctx._source.schema_version = 2;'},wait_for_completion=True,refresh=True)
                if response.get('failures') or response.get('timed_out') or response.get('version_conflicts'):raise RuntimeError('Incomplete reindex; alias unchanged')
                if client.count(index=v1)['count']!=client.count(index=v2)['count']:raise RuntimeError('Count mismatch; alias unchanged')
                for hit in helpers.scan(client,index=v1,query={'query':{'match_all':{}}}):
                    old=hit['_source'];new=client.get(index=v2,id=hit['_id'])['_source']
                    assert new==dict(old,latency_seconds=old['duration_ms']/1000,schema_version=2)
                client.indices.update_aliases(actions=[{'remove':{'index':v1,'alias':alias}},{'add':{'index':v2,'alias':alias}}])
        elif a.action=='seed':
            if any(client.count(index=PREFIX+name+'-v1')['count'] for name in spec):raise RuntimeError('Seed requires empty v1 indices')
            if client.indices.exists(index=PREFIX+'requests-v2'):raise RuntimeError('Seed v1 before migrating to v2')
            actions=[]
            for name,rows in spec.items():
                key={'requests':'event_id','deployments':'deployment_id','incidents':'incident_id'}[name]
                actions.extend({'_op_type':'create','_index':PREFIX+name+'-v1','_id':r[key],'_source':r} for r in rows)
            helpers.bulk(client,actions,refresh=True)
        else:
            for name,rows in spec.items():
                idx=PREFIX+name+('-v2' if name=='requests' else '-v1')
                if name=='requests':rows=[dict(r,latency_seconds=r['duration_ms']/1000,schema_version=2) for r in rows]
                actual=[h['_source'] for h in helpers.scan(client,index=idx,query={'query':{'match_all':{}}})]
                key={'requests':'event_id','deployments':'deployment_id','incidents':'incident_id'}[name]
                assert sorted(actual,key=lambda r:int(r[key]))==rows
            alias=client.indices.get_alias(name=PREFIX+'requests');assert list(alias)==[PREFIX+'requests-v2']
        print(json.dumps({'source':'elasticsearch','action':a.action,'status':'PASS'}))
    finally:client.close()
if __name__=='__main__':
    try:main()
    except Exception as e:print(f'elasticsearch: FAIL ({type(e).__name__}); details redacted',file=sys.stderr);sys.exit(1)
