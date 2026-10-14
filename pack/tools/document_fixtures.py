"""Pure, deterministic fixtures for document/search/file sources."""
from datetime import date,timedelta
def fixtures(kind,scale=1):
    if not 1<=scale<=1000:raise ValueError('scale must be 1..1000')
    n=120*scale
    if kind=='mongodb':
        courses=[{'_id':i,'title':f'Course {i}','category':['data','cloud','backend'][i%3],'lessons': [{'lesson_id':j,'title':f'Lesson {j}','duration_minutes':10+j} for j in range(1,5)]} for i in range(1,7)]
        learners=[{'_id':i,'learner_code':f'SYN-L{i:04}','profile':{'country':['CA','TN','FR'][i%3],'language':['fr','en'][i%2]}} for i in range(1,31)]
        enrollments=[{'_id':i,'learner_id':(i-1)%30+1,'course_id':(i-1)%6+1,'cohort':f'2026-{(i-1)//30+1:04}','status':'cancelled' if i%11==0 else 'active','duration_seconds':i%61*60,'schema_version':1} for i in range(1,n+1)]
        attempts=[{'_id':i,'enrollment_id':(i-1)//2+1,'lesson_id':i%4+1,'score':None if i%13==0 else i%101,'submitted_on':(date(2026,1,1)+timedelta(days=i%270)).isoformat()} for i in range(1,n*2+1)]
        return dict(courses=courses,learners=learners,enrollments=enrollments,attempts=attempts)
    if kind=='elasticsearch':
        requests=[{'event_id':str(i),'service':['api','worker','gateway'][i%3],'environment':'staging' if i%17==0 else 'production','observed_at':f'2026-09-{i%28+1:02}T12:00:00Z','duration_ms':i%1200,'status_code':500 if i%11==0 else 200,'trace_id':f'trace-{i:08}','deployment_id':str(i%12+1),'location':{'lat':45+i%10/10,'lon':-73-i%10/10},'schema_version':1} for i in range(1,n+1)]
        deployments=[{'deployment_id':str(i),'service':['api','worker','gateway'][i%3],'version':f'1.{i}.0','observed_at':f'2026-09-{i:02}T00:00:00Z','result':'failed' if i%5==0 else 'successful'} for i in range(1,13)]
        incidents=[{'incident_id':str(i),'service':['api','worker','gateway'][i%3],'severity':['sev1','sev2'][i%2],'observed_at':f'2026-09-{i:02}T13:00:00Z','recovery_minutes':None if i%5==0 else 20+i} for i in range(1,13)]
        return dict(requests=requests,deployments=deployments,incidents=incidents)
    if kind=='excel':
        donors=[dict(id=i,name=f'Synthetic donor {i}',country=['CA','TN','FR'][i%3]) for i in range(1,13)]
        programs=[dict(id=i,name=['Literacy','Food access','Water','Youth'][i-1],region=['East','West'][i%2]) for i in range(1,5)]
        awards=[dict(id=i,donor_id=(i-1)%12+1,program_id=(i-1)%4+1,awarded_on=(date(2026,1,1)+timedelta(days=i%180)).isoformat(),committed_cents=100000+i*1000,status='cancelled' if i%13==0 else 'approved') for i in range(1,n+1)]
        disbursements=[dict(id=a['id']*2+j,award_id=a['id'],posted_on='2026-09-30',amount_cents=a['committed_cents']//4,category=['equipment','training'][j]) for a in awards if a['status']=='approved' for j in range(2)]
        milestones=[dict(id=i,award_id=i,label='Completion evidence',due_on='2026-10-31',completed_on='' if i%3 else '2026-09-15') for i in range(1,n+1)]
        return dict(donors=donors,programs=programs,awards=awards,disbursements=disbursements,milestones=milestones)
    if kind=='parquet':
        sites=[dict(id=i,region=['north','south'][i%2],latitude=45+i/10,longitude=-73-i/10) for i in range(1,5)]
        sensors=[dict(id=i,site_id=(i-1)%4+1,serial=f'SENSOR{i:04}',unit='C') for i in range(1,13)]
        readings=[dict(id=i,sensor_id=(i-1)%12+1,observed_on=(date(2026,1,1)+timedelta(days=(i-1)//12%270)).isoformat(),value_c=None if i%19==0 else round(-10+i%45+i%10/10,1)) for i in range(1,n*10+1)]
        calibrations=[dict(id=i,sensor_id=i,calibrated_on='2026-01-01',offset_c=0.1 if i%2 else -0.1) for i in range(1,13)]
        return dict(sites=sites,sensors=sensors,readings=readings,calibrations=calibrations)
    raise ValueError(kind)
