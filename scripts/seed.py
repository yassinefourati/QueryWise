"""Generate deterministic, fictional retail data shared by browser and Python."""
import json, random, sqlite3
from pathlib import Path
from datetime import date, timedelta
ROOT = Path(__file__).resolve().parents[1]
rng = random.Random(2027)
schema = '''CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT NOT NULL, province TEXT NOT NULL, segment TEXT NOT NULL);
CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL, price REAL NOT NULL);
CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER NOT NULL REFERENCES customers(id), order_date TEXT NOT NULL, status TEXT NOT NULL);
CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER NOT NULL REFERENCES orders(id), product_id INTEGER NOT NULL REFERENCES products(id), quantity INTEGER NOT NULL, unit_price REAL NOT NULL);'''
customers=[]
first=['Alex','Sam','Charlie','Morgan','Jordan','Taylor','Avery','Cameron','Robin','Sasha','Noor','Jamie','Casey','Emerson','Riley','Quinn']
last=['Martin','Roy','Wilson','Tremblay','Singh']
provinces=['Quebec','Ontario','British Columbia','Alberta','Nova Scotia']
for i in range(80): customers.append([i+1, f'{first[i%16]} {last[i//16]}',provinces[rng.randrange(5)],rng.choice(['Consumer','Business','Enterprise'])])
products=[[1,'Studio headphones','Electronics',189],[2,'Mechanical keyboard','Electronics',129],[3,'USB-C hub','Electronics',79],[4,'4K monitor','Electronics',449],[5,'Desk lamp','Home & Office',69],[6,'Ergonomic chair','Home & Office',349],[7,'Standing desk','Home & Office',599],[8,'Desk organizer','Home & Office',39],[9,'Trail backpack','Outdoors',99],[10,'Insulated bottle','Outdoors',35],[11,'Camping lantern','Outdoors',59],[12,'Travel duffel','Outdoors',119],[13,'Cotton hoodie','Apparel',75],[14,'Everyday tee','Apparel',29],[15,'Rain jacket','Apparel',149],[16,'Wool beanie','Apparel',35]]
orders=[]; items=[]
for i in range(720):
    day=(date(2026,1,1)+timedelta(days=rng.randrange(273))).isoformat()
    orders.append([i+1,rng.randrange(1,81),day,rng.choices(['completed','pending','cancelled'],[87,8,5])[0]])
    for pid in rng.sample(range(1,17),rng.randrange(1,5)):
        p=products[pid-1];items.append([len(items)+1,i+1,pid,rng.randrange(1,5),p[3]])
data={'customers':customers,'products':products,'orders':orders,'order_items':items}
(ROOT/'dist/dataset.json').write_text(json.dumps({'schema':schema,'data':data},separators=(',',':')))
path=ROOT/'data';path.mkdir(exist_ok=True)
db=sqlite3.connect(path/'sample.db');db.executescript('DROP TABLE IF EXISTS order_items; DROP TABLE IF EXISTS orders; DROP TABLE IF EXISTS products; DROP TABLE IF EXISTS customers;'+schema)
for table, rows in data.items(): db.executemany(f'INSERT INTO {table} VALUES ({",".join("?" for _ in rows[0])})',rows)
db.commit();db.close()
print(f'Seeded {len(orders)} orders, {len(items)} line items, {len(customers)} customers.')
