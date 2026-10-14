"""MongoDB learning domain: additive, resumable v1 -> v2 data migration."""
import argparse,os,sys,json,hashlib
from pathlib import Path
from tools.document_fixtures import fixtures
DB='qw_complex_learning'
def validators(version):
    def schema(required,properties):return {'$jsonSchema':{'bsonType':'object','required':required,'properties':properties}}
    num={'bsonType':['int','long','double']}
    return {
        'courses':schema(['_id','title','category','lessons'],{'_id':num,'title':{'bsonType':'string'},'lessons':{'bsonType':'array'}}),
        'learners':schema(['_id','learner_code','profile'],{'_id':num,'profile':{'bsonType':'object'}}),
        'enrollments':schema(['_id','learner_id','course_id','cohort','status','duration_seconds','schema_version']+(['learning_minutes'] if version==2 else []),{'_id':num,'learner_id':num,'course_id':num,'status':{'enum':['active','cancelled']},'duration_seconds':{**num,'minimum':0},'schema_version':{'enum':[version]},**({'learning_minutes':{**num,'minimum':0}} if version==2 else {})}),
        'attempts':schema(['_id','enrollment_id','lesson_id','score','submitted_on'],{'_id':num,'score':{'bsonType':['int','long','double','null'],'minimum':0,'maximum':100}})}
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['migrate','seed','verify']);p.add_argument('--target',type=int,choices=[1,2],default=2);p.add_argument('--scale',type=int,default=1);p.add_argument('--allow-write',action='store_true');a=p.parse_args()
    if a.action!='verify' and not a.allow_write:p.error('--allow-write required')
    from pymongo import MongoClient,UpdateOne
    url=os.environ.get('PACK_MONGODB_URL')
    if not url:p.error('Set PACK_MONGODB_URL')
    with MongoClient(url,serverSelectionTimeoutMS=5000) as client:
        db=client[DB];hist=db['qw_pack_history'];spec=fixtures('mongodb',a.scale)
        if a.action=='migrate':
            # Atomic unique lock. After a crash, inspect state before clearing it.
            hist.insert_one({'_id':'lock','state':'running'})
            try:
                current=hist.find_one({'_id':'version'})
                checksum=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
                if current and current.get('checksum')!=checksum:raise RuntimeError('Migration code checksum changed')
                version=current['value'] if current else 0
                if a.target<version:raise RuntimeError('Downgrade is unsupported')
                if version==0:
                    for name,validator in validators(1).items():
                        if name not in db.list_collection_names():db.create_collection(name,validator=validator,validationLevel='strict')
                        else:db.command('collMod',name,validator=validator,validationLevel='strict',validationAction='error')
                    db.learners.create_index('learner_code',unique=True)
                    db.enrollments.create_index([('learner_id',1),('course_id',1),('cohort',1)],unique=True)
                    db.attempts.create_index('enrollment_id')
                    hist.replace_one({'_id':'version'},{'_id':'version','value':1,'checksum':checksum},upsert=True);version=1
                if version==1 and a.target==2:
                    # Relax only schema_version during additive backfill, then enforce v2.
                    validator=validators(1)['enrollments'];validator['$jsonSchema']['properties']['schema_version']={'enum':[1,2]}
                    db.command('collMod','enrollments',validator=validator)
                    db.enrollments.update_many({'schema_version':1},[{'$set':{'learning_minutes':{'$divide':['$duration_seconds',60]},'schema_version':2}}])
                    if db.enrollments.count_documents({'schema_version':{'$ne':2}}):raise RuntimeError('Backfill incomplete')
                    db.command('collMod','enrollments',validator=validators(2)['enrollments'])
                    hist.update_one({'_id':'version'},{'$set':{'value':2}})
            finally:hist.delete_one({'_id':'lock'})
        elif a.action=='seed':
            version=hist.find_one({'_id':'version'})
            if not version:raise RuntimeError('Run migrate first')
            if hist.find_one({'_id':'seed'}) not in (None,{'_id':'seed','scale':a.scale}):raise RuntimeError('Scale changed')
            for name,rows in spec.items():
                if name=='enrollments' and version['value']==2:
                    rows=[dict(r,schema_version=2,learning_minutes=r['duration_seconds']/60) for r in rows]
                db[name].bulk_write([UpdateOne({'_id':r['_id']},{'$setOnInsert':r},upsert=True) for r in rows])
            hist.replace_one({'_id':'seed'},{'_id':'seed','scale':a.scale},upsert=True)
        else:
            assert hist.find_one({'_id':'version'})['value']==2
            for name,rows in spec.items():
                if name=='enrollments':rows=[dict(r,schema_version=2,learning_minutes=r['duration_seconds']/60) for r in rows]
                assert list(db[name].find().sort('_id',1))==rows, f'{name}: fixture mismatch'
            actual=list(db.enrollments.aggregate([{'$match':{'status':'active'}},{'$group':{'_id':'$course_id','minutes':{'$sum':'$learning_minutes'}}},{'$sort':{'_id':1}}]))
            expected=[{'_id':i,'minutes':sum(r['duration_seconds']/60 for r in spec['enrollments'] if r['course_id']==i and r['status']=='active')} for i in range(1,7)]
            assert actual==expected
        print(json.dumps({'source':'mongodb','action':a.action,'status':'PASS'}))
if __name__=='__main__':
    try:main()
    except Exception as e:print(f'mongodb: FAIL ({type(e).__name__}); details redacted',file=sys.stderr);sys.exit(1)
