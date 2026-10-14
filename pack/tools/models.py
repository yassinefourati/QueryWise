"""Deterministic synthetic business models. No personal or production records."""
from datetime import date, timedelta
from sqlalchemy import (MetaData, Table, Column, Integer, BigInteger, String, Date,
                        Numeric, ForeignKey, CheckConstraint, UniqueConstraint, Index)

SQL_KINDS = ('sqlite','postgres','mysql','mariadb','sqlserver','oracle','db2')
TOPICS = dict(zip(SQL_KINDS, ['Public library lending','Renewable energy operations',
    'Omnichannel retail','Cold-chain freight','Outpatient billing','Airport operations',
    'Property insurance']))
TOPICS.update(mongodb='Online learning', elasticsearch='Service reliability',
              excel='Nonprofit grant administration', parquet='Environmental sensors')

def model(kind, scale=1):
    if kind not in SQL_KINDS or not 1 <= scale <= 1000:
        raise ValueError('Unknown engine or scale outside 1..1000')
    m, data = MetaData(), {}
    def table(name, spec, checks=(), unique=()):
        cols=[]
        for token in spec.split():
            key, typ = token.split(':',1)
            nullable=typ.endswith('?'); typ=typ.rstrip('?')
            fk=None
            if typ.startswith('@'):
                fk=typ[1:]+'.id'; sqltype=Integer
            else:
                sqltype={'id':Integer,'int':Integer,'cents':BigInteger,'text':String(120),
                         'code':String(32),'date':Date,'decimal':Numeric(14,3)}[typ]
            cols.append(Column(key,sqltype,*([ForeignKey(fk)] if fk else []),
                               primary_key=typ=='id', nullable=False if typ=='id' else nullable,
                               autoincrement=False))
        t=Table(name,m,*cols,*[CheckConstraint(x,name=f'ck_{name[:12]}_{i}') for i,x in enumerate(checks)],
                *[UniqueConstraint(*x,name=f'uq_{name[:12]}_{i}') for i,x in enumerate(unique)])
        data[name]=[]
        for c in t.c:
            if c.foreign_keys: Index(f'ix_{name[:12]}_{c.name[:12]}',c)
        return t
    def add(name,*vals): data[name].append(dict(zip(m.tables[name].c.keys(),vals)))
    def day(n): return date(2026,1,1)+timedelta(days=n%270)
    n=120*scale
    if kind=='sqlite':
        table('branches','id:id name:text city:text latitude:decimal longitude:decimal')
        table('members','id:id branch_id:@branches member_code:code joined_on:date',unique=[('member_code',)])
        table('titles','id:id isbn:code title:text genre:code',unique=[('isbn',)])
        table('copies','id:id title_id:@titles branch_id:@branches barcode:code',unique=[('barcode',)])
        table('loans','id:id copy_id:@copies member_id:@members borrowed_on:date due_on:date returned_on:date?',checks=['due_on >= borrowed_on','returned_on IS NULL OR returned_on >= borrowed_on'])
        table('fines','id:id loan_id:@loans assessed_cents:cents waived_cents:cents',checks=['assessed_cents >= 0','waived_cents >= 0 AND waived_cents <= assessed_cents'])
        table('fine_payments','id:id fine_id:@fines paid_on:date amount_cents:cents',checks=['amount_cents > 0'])
        for i in range(1,5): add('branches',i,f'Branch {i}',f'City {i}',45+i/10,-73-i/10)
        for i in range(1,41):
            add('members',i,(i-1)%4+1,f'M{i:04}',day(0)); add('titles',i,f'ISBN{i:09}',f'Synthetic title {i}', ['science','history','fiction'][i%3])
        for i in range(1,n+1):
            add('copies',i,(i-1)%40+1,(i-1)%4+1,f'COPY{i:08}')
            borrowed=day(i); due=borrowed+timedelta(days=14)
            add('loans',i,i,(i-1)%40+1,borrowed,due,None if i%5==0 else due+timedelta(days=i%4-2))
            if i%3==0:
                add('fines',i,i,500,100 if i%2==0 else 0)
                if i%4: add('fine_payments',i,i,due+timedelta(days=4),200)
        fact,flag,rule='loans','overdue_flag',"returned_on IS NULL AND due_on < '2026-10-01'"
        queries=[('outstanding_fines','What are unpaid fines by branch in cents?',"WITH paid AS (SELECT fine_id, SUM(amount_cents) amount FROM fine_payments GROUP BY fine_id) SELECT b.name, SUM(f.assessed_cents-f.waived_cents-COALESCE(p.amount,0)) outstanding_cents FROM fines f JOIN loans l ON l.id=f.loan_id JOIN copies c ON c.id=l.copy_id JOIN branches b ON b.id=c.branch_id LEFT JOIN paid p ON p.fine_id=f.id GROUP BY b.name ORDER BY b.name"),
          ('circulation','Rank genres by loan count.',"SELECT t.genre, COUNT(*) loans, DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) popularity_rank FROM loans l JOIN copies c ON c.id=l.copy_id JOIN titles t ON t.id=c.title_id GROUP BY t.genre ORDER BY loans DESC,t.genre")]
    elif kind=='postgres':
        table('sites','id:id name:text region:code latitude:decimal longitude:decimal')
        table('turbines','id:id site_id:@sites serial:code capacity_kw:int',checks=['capacity_kw > 0'],unique=[('serial',)])
        table('contracts','id:id site_id:@sites starts_on:date ends_on:date rate_micros:int',checks=['ends_on >= starts_on','rate_micros >= 0'])
        table('readings','id:id turbine_id:@turbines observed_on:date energy_wh:cents quality:code',checks=["quality IN ('valid','estimated','invalid')",'energy_wh >= 0'],unique=[('turbine_id','observed_on')])
        table('outages','id:id turbine_id:@turbines started_on:date duration_minutes:int reason:code',checks=['duration_minutes >= 0'])
        table('crews','id:id name:text specialty:code')
        table('work_orders','id:id outage_id:@outages crew_id:@crews cost_cents:cents status:code',checks=['cost_cents >= 0'])
        table('settlements','id:id contract_id:@contracts period_on:date paid_cents:cents',unique=[('contract_id','period_on')])
        for i in range(1,5):
            add('sites',i,f'Wind farm {i}',f'R{i}',46+i/10,-72-i/10);add('contracts',i,i,day(0),date(2026,12,31),85000+i*1000);add('crews',i,f'Crew {i}','mechanical')
        for i in range(1,21): add('turbines',i,(i-1)%4+1,f'T{i:04}',2500)
        # Increase turbine population with scale; dates remain a fixed, comparable period.
        for i in range(21,20*scale+1): add('turbines',i,(i-1)%4+1,f'T{i:07}',2500)
        for i in range(1,n+1):
            tid=(i-1)%(20*scale)+1
            add('readings',i,tid,day((i-1)//(20*scale)),0 if i%17==0 else 120000+i%300, 'invalid' if i%13==0 else 'valid')
            if i%6==0: add('outages',i,tid,day(i),60+i%90,'gearbox');add('work_orders',i,i,(i-1)%4+1,25000+i,'closed' if i%12 else 'open')
        for i in range(1,5): add('settlements',i,i,date(2026,2,1),100000+i*1000)
        fact,flag,rule='readings','review_flag',"quality = 'invalid' OR energy_wh = 0"
        queries=[('valid_energy','Valid energy in Wh per region; exclude estimated and invalid readings.',"SELECT s.region, SUM(r.energy_wh) energy_wh FROM readings r JOIN turbines t ON t.id=r.turbine_id JOIN sites s ON s.id=t.site_id WHERE r.quality='valid' GROUP BY s.region ORDER BY s.region"),('maintenance','Which farms have the greatest maintenance cost?',"SELECT s.name,SUM(w.cost_cents) cost_cents,COUNT(*) jobs FROM work_orders w JOIN outages o ON o.id=w.outage_id JOIN turbines t ON t.id=o.turbine_id JOIN sites s ON s.id=t.site_id GROUP BY s.name ORDER BY cost_cents DESC,s.name")]
    elif kind=='mysql':
        table('customers','id:id customer_code:code segment:code province:code',unique=[('customer_code',)])
        table('products','id:id sku:code category:code price_cents:cents cost_cents:cents',checks=['price_cents >= 0','cost_cents >= 0'],unique=[('sku',)])
        table('warehouses','id:id name:text latitude:decimal longitude:decimal')
        table('inventory','id:id warehouse_id:@warehouses product_id:@products on_hand:int reserved:int',checks=['on_hand >= 0','reserved >= 0 AND reserved <= on_hand'],unique=[('warehouse_id','product_id')])
        table('orders','id:id customer_id:@customers ordered_on:date status:code',checks=["status IN ('completed','cancelled','pending')"])
        table('order_lines','id:id order_id:@orders product_id:@products quantity:int unit_cents:cents discount_cents:cents',checks=['quantity > 0','unit_cents >= 0','discount_cents >= 0 AND discount_cents <= quantity * unit_cents'])
        table('returns','id:id line_id:@order_lines returned_on:date quantity:int refund_cents:cents',checks=['quantity > 0','refund_cents >= 0'])
        table('payments','id:id order_id:@orders paid_on:date amount_cents:cents method:code',checks=['amount_cents > 0'])
        for i in range(1,5): add('warehouses',i,f'Warehouse {i}',45+i/10,-73-i/10)
        for i in range(1,21):
            add('customers',i,f'C{i:04}',['consumer','business'][i%2],['QC','ON','BC'][i%3]);add('products',i,f'SKU{i:05}',['home','outdoors','electronics'][i%3],1000+i*100,500+i*50)
            for w in range(1,5): add('inventory',(i-1)*4+w,w,i,100,10)
        for i in range(1,n+1):
            state='cancelled' if i%10==0 else 'pending' if i%9==0 else 'completed'; add('orders',i,(i-1)%20+1,day(i),state)
            total=0
            for j in range(2):
                lid=2*i-1+j;pid=(lid-1)%20+1; price=1000+pid*100; qty=1+j;disc=100 if i%7==0 else 0
                add('order_lines',lid,i,pid,qty,price,disc);total+=qty*price-disc
                if j==0 and i%6==0 and state=='completed': add('returns',i,lid,day(i)+timedelta(days=5),1,price-disc)
            if state=='completed':
                add('payments',2*i-1,i,day(i),total//2,'card');add('payments',2*i,i,day(i),total-total//2,'wallet')
        fact,flag,rule='orders','review_flag',"status = 'pending'"
        queries=[('net_sales','Net completed sales by category after discounts and refunds, in cents.',"WITH refunds AS (SELECT line_id,SUM(refund_cents) cents FROM returns GROUP BY line_id) SELECT p.category,SUM(l.quantity*l.unit_cents-l.discount_cents-COALESCE(r.cents,0)) net_cents FROM order_lines l JOIN orders o ON o.id=l.order_id JOIN products p ON p.id=l.product_id LEFT JOIN refunds r ON r.line_id=l.id WHERE o.status='completed' GROUP BY p.category ORDER BY p.category"),('payment_reconciliation','Which completed orders have mismatched charges and payments?',"WITH charges AS (SELECT order_id,SUM(quantity*unit_cents-discount_cents) cents FROM order_lines GROUP BY order_id), paid AS (SELECT order_id,SUM(amount_cents) cents FROM payments GROUP BY order_id) SELECT o.id,c.cents charged,COALESCE(p.cents,0) paid FROM orders o JOIN charges c ON c.order_id=o.id LEFT JOIN paid p ON p.order_id=o.id WHERE o.status='completed' AND c.cents<>COALESCE(p.cents,0) ORDER BY o.id")]
    elif kind=='mariadb':
        table('depots','id:id name:text latitude:decimal longitude:decimal')
        table('vehicles','id:id registration:code capacity_kg:int',checks=['capacity_kg > 0'],unique=[('registration',)])
        table('drivers','id:id driver_code:code home_depot_id:@depots',unique=[('driver_code',)])
        table('shipments','id:id origin_id:@depots destination_id:@depots promised_on:date delivered_on:date? weight_kg:int status:code',checks=['origin_id <> destination_id','weight_kg > 0'])
        table('legs','id:id shipment_id:@shipments vehicle_id:@vehicles driver_id:@drivers distance_km:int',checks=['distance_km > 0'])
        table('temperature_scans','id:id leg_id:@legs observed_on:date temperature_c:decimal?')
        table('invoices','id:id shipment_id:@shipments billed_cents:cents fuel_cents:cents',checks=['billed_cents >= 0','fuel_cents >= 0'],unique=[('shipment_id',)])
        for i in range(1,5): add('depots',i,f'Depot {i}',45+i/10,-73-i/10)
        for i in range(1,13): add('vehicles',i,f'TRUCK{i:03}',10000);add('drivers',i,f'DRIVER{i:03}',(i-1)%4+1)
        for i in range(1,n+1):
            due=day(i);delivered=None if i%9==0 else due+timedelta(days=i%3-1)
            add('shipments',i,(i-1)%4+1,i%4+1,due,delivered,100+i,'in_transit' if delivered is None else 'delivered')
            for j in range(2):
                lid=i*2-1+j;add('legs',lid,i,(i-1)%12+1,(i-1)%12+1,150+j*100)
                for k in range(3): add('temperature_scans',(lid-1)*3+k+1,lid,due,None if i%17==0 else (12 if i%7==0 and k==2 else 4))
            add('invoices',i,i,50000+i*100,10000)
        fact,flag,rule='shipments','late_flag','delivered_on > promised_on'
        queries=[('cold_chain','Which shipments have a temperature above 8 C?',"SELECT s.id,MAX(t.temperature_c) peak_c FROM shipments s JOIN legs l ON l.shipment_id=s.id JOIN temperature_scans t ON t.leg_id=l.id GROUP BY s.id HAVING MAX(t.temperature_c)>8 ORDER BY s.id"),('delivery_sla','Delivered and late counts by origin depot.',"SELECT d.name,COUNT(*) delivered,SUM(CASE WHEN s.delivered_on>s.promised_on THEN 1 ELSE 0 END) late FROM shipments s JOIN depots d ON d.id=s.origin_id WHERE s.delivered_on IS NOT NULL GROUP BY d.name ORDER BY d.name")]
    elif kind=='sqlserver':
        table('clinics','id:id name:text region:code')
        table('patients','id:id patient_token:code birth_year:int',checks=['birth_year BETWEEN 1900 AND 2026'],unique=[('patient_token',)])
        table('clinicians','id:id clinic_id:@clinics specialty:code')
        table('procedures','id:id procedure_code:code fee_cents:cents',checks=['fee_cents >= 0'],unique=[('procedure_code',)])
        table('appointments','id:id patient_id:@patients clinician_id:@clinicians scheduled_on:date status:code',checks=["status IN ('attended','cancelled','no_show')"])
        table('claim_lines','id:id appointment_id:@appointments procedure_id:@procedures billed_cents:cents allowed_cents:cents',checks=['billed_cents >= 0','allowed_cents >= 0 AND allowed_cents <= billed_cents'])
        table('remittances','id:id claim_line_id:@claim_lines paid_on:date amount_cents:cents reason:code')
        for i in range(1,5): add('clinics',i,f'Clinic {i}',f'R{i}')
        for i in range(1,21): add('patients',i,f'SYN-P{i:05}',1970+i);add('clinicians',i,(i-1)%4+1,['general','physio'][i%2])
        for i in range(1,6): add('procedures',i,f'PROC{i}',5000+i*1000)
        for i in range(1,n+1):
            status='no_show' if i%10==0 else 'cancelled' if i%11==0 else 'attended';add('appointments',i,(i-1)%20+1,(i-1)%20+1,day(i),status)
            if status=='attended':
                pid=(i-1)%5+1;fee=5000+pid*1000;add('claim_lines',i,i,pid,fee,fee-500)
                add('remittances',2*i-1,i,day(i)+timedelta(days=14),fee-500,'payment')
                if i%8==0: add('remittances',2*i,i,day(i)+timedelta(days=20),-1000,'recoupment')
        fact,flag,rule='appointments','no_show_flag',"status = 'no_show'"
        queries=[('receivables','Allowed receivables after payments and recoupments by clinic.',"WITH paid AS (SELECT claim_line_id,SUM(amount_cents) cents FROM remittances GROUP BY claim_line_id) SELECT c.name,SUM(l.allowed_cents-COALESCE(p.cents,0)) outstanding_cents FROM claim_lines l JOIN appointments a ON a.id=l.appointment_id JOIN clinicians d ON d.id=a.clinician_id JOIN clinics c ON c.id=d.clinic_id LEFT JOIN paid p ON p.claim_line_id=l.id GROUP BY c.name ORDER BY c.name"),('no_shows','No-show appointments by specialty.',"SELECT c.specialty,COUNT(*) appointments,SUM(CASE WHEN a.status='no_show' THEN 1 ELSE 0 END) no_shows FROM appointments a JOIN clinicians c ON c.id=a.clinician_id GROUP BY c.specialty ORDER BY c.specialty")]
    elif kind=='oracle':
        table('airports','id:id iata:code latitude:decimal longitude:decimal',unique=[('iata',)])
        table('aircraft','id:id tail_number:code seats:int',checks=['seats > 0'],unique=[('tail_number',)])
        table('routes','id:id origin_id:@airports destination_id:@airports distance_km:int',checks=['origin_id <> destination_id','distance_km > 0'])
        table('gates','id:id airport_id:@airports gate_code:code',unique=[('airport_id','gate_code')])
        table('flights','id:id route_id:@routes aircraft_id:@aircraft departed_on:date status:code passengers:int delay_minutes:int?',checks=['passengers >= 0',"status IN ('departed','cancelled')"])
        table('turnarounds','id:id flight_id:@flights gate_id:@gates ground_minutes:int target_minutes:int',checks=['ground_minutes >= 0','target_minutes > 0'],unique=[('flight_id',)])
        table('disruptions','id:id flight_id:@flights reason:code cost_cents:cents',checks=['cost_cents >= 0'])
        table('crew_assignments','id:id flight_id:@flights crew_code:code role_code:code',unique=[('flight_id','crew_code')])
        for i in range(1,5):
            add('airports',i,['YUL','YYZ','YVR','YQB'][i-1],45+i/10,-73-i/10);add('gates',i,i,'A1');add('routes',i,i,i%4+1,500+i*400)
        for i in range(1,11): add('aircraft',i,f'SYN-{i:03}',180)
        for i in range(1,n+1):
            cancelled=i%13==0;rid=(i-1)%4+1;add('flights',i,rid,(i-1)%10+1,day(i),'cancelled' if cancelled else 'departed',0 if cancelled else 100+i%70,None if cancelled else i%50)
            if not cancelled: add('turnarounds',i,i,rid,35+i%30,45)
            if i%7==0: add('disruptions',i,i,'weather',50000+i*10)
            for j in range(2): add('crew_assignments',i*2-1+j,i,f'CREW{(i+j)%20:03}',['pilot','copilot'][j])
        fact,flag,rule='flights','delay_flag','delay_minutes >= 15'
        queries=[('route_load','Seat occupancy inputs for departed flights by route.',"SELECT r.id, SUM(f.passengers) passengers,SUM(a.seats) seats FROM flights f JOIN routes r ON r.id=f.route_id JOIN aircraft a ON a.id=f.aircraft_id WHERE f.status='departed' GROUP BY r.id ORDER BY r.id"),('turnaround','Average ground duration and missed targets per origin airport.',"SELECT a.iata,AVG(t.ground_minutes*1.0) avg_minutes,SUM(CASE WHEN t.ground_minutes>t.target_minutes THEN 1 ELSE 0 END) missed FROM turnarounds t JOIN flights f ON f.id=t.flight_id JOIN routes r ON r.id=f.route_id JOIN airports a ON a.id=r.origin_id GROUP BY a.iata ORDER BY a.iata")]
    else:
        table('policyholders','id:id holder_code:code region:code',unique=[('holder_code',)])
        table('policies','id:id holder_id:@policyholders policy_number:code starts_on:date ends_on:date premium_cents:cents',checks=['ends_on >= starts_on','premium_cents >= 0'],unique=[('policy_number',)])
        table('coverages','id:id policy_id:@policies peril:code limit_cents:cents deductible_cents:cents',checks=['limit_cents > 0','deductible_cents >= 0'],unique=[('policy_id','peril')])
        table('claims','id:id coverage_id:@coverages loss_on:date status:code reported_cents:cents',checks=['reported_cents >= 0',"status IN ('open','closed','denied')"])
        table('reserve_changes','id:id claim_id:@claims posted_on:date delta_cents:cents')
        table('claim_payments','id:id claim_id:@claims posted_on:date amount_cents:cents',checks=['amount_cents > 0'])
        table('recoveries','id:id claim_id:@claims posted_on:date amount_cents:cents',checks=['amount_cents > 0'])
        for i in range(1,21):
            add('policyholders',i,f'H{i:04}',['east','west'][i%2]);add('policies',i,i,f'POL{i:06}',day(0),date(2026,12,31),120000)
            for j in range(2): add('coverages',2*i-1+j,i,['fire','water'][j],50000000,100000)
        for i in range(1,n+1):
            closed=i%4==0;denied=i%11==0;status='denied' if denied else 'closed' if closed else 'open'
            add('claims',i,(i-1)%40+1,day(i),status,200000+i*100)
            if not denied:
                add('reserve_changes',2*i-1,i,day(i),200000)
                add('reserve_changes',2*i,i,day(i)+timedelta(days=5),-200000 if closed else -50000)
                add('claim_payments',i,i,day(i)+timedelta(days=5),180000 if closed else 50000)
                if i%6==0: add('recoveries',i,i,day(i)+timedelta(days=10),10000)
        fact,flag,rule='claims','large_loss_flag','reported_cents >= 210000'
        queries=[('incurred','Net incurred loss in cents by peril: paid + remaining reserve - recoveries.',"WITH r AS (SELECT claim_id,SUM(delta_cents) cents FROM reserve_changes GROUP BY claim_id), p AS (SELECT claim_id,SUM(amount_cents) cents FROM claim_payments GROUP BY claim_id), x AS (SELECT claim_id,SUM(amount_cents) cents FROM recoveries GROUP BY claim_id) SELECT v.peril,SUM(COALESCE(p.cents,0)+COALESCE(r.cents,0)-COALESCE(x.cents,0)) incurred_cents FROM claims c JOIN coverages v ON v.id=c.coverage_id LEFT JOIN r ON r.claim_id=c.id LEFT JOIN p ON p.claim_id=c.id LEFT JOIN x ON x.claim_id=c.id WHERE c.status<>'denied' GROUP BY v.peril ORDER BY v.peril"),('closed_reserves','Closed claims incorrectly retaining a reserve (expected empty).',"SELECT c.id,SUM(r.delta_cents) remaining_cents FROM claims c JOIN reserve_changes r ON r.claim_id=c.id WHERE c.status='closed' GROUP BY c.id HAVING SUM(r.delta_cents)<>0 ORDER BY c.id")]
    queries += [('upgrade_flags',f'Count records marked by {flag} after migration.',f'SELECT {flag},COUNT(*) records FROM {fact} GROUP BY {flag} ORDER BY {flag}')]
    return {'metadata':m,'data':data,'fact':fact,'flag':flag,'rule':rule,'queries':queries}
