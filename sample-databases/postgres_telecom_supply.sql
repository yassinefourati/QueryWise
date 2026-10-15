-- =====================================================================================
--  TELECOM & SUPPLY CHAIN  -  PostgreSQL 12+  -  40 tables
--  Topic : mobile operator (phone numbers, SIMs, devices, calls, SMS, data, billing,
--          support, number porting, roaming) + procurement (suppliers, contracts,
--          products, purchase orders, receipts, supplier invoices/payments, stock).
--  Data  : random but reproducible (fixed seed), every business date between
--          1999-01-01 and CURRENT_DATE, child dates never precede parent dates.
--          Natural keys (phone numbers, ICCID, IMSI, IMEI, e-mails, invoice/PO numbers,
--          VAT numbers ...) are unique and enforced by UNIQUE constraints.
--  Size  : scale 1 is about 11 million rows (~2 GB, ~7 min). Change telecom.scale
--          below: 0.01 = quick smoke test, 1 = default, 5 = about 55 million rows.
--  Run   : createdb telecom_db
--          psql -v ON_ERROR_STOP=1 -d telecom_db -f postgres_telecom_supply.sql
--          Everything is created in schema "telecom"; re-running drops and rebuilds it.
-- =====================================================================================

SET client_encoding = 'UTF8';
SET client_min_messages = warning;
SET telecom.scale = '1';
SET max_parallel_workers_per_gather = 0;   -- keeps random() reproducible
SET work_mem = '256MB';
SELECT setseed(0.1999);

BEGIN;

DROP SCHEMA IF EXISTS telecom CASCADE;
DROP SCHEMA IF EXISTS telecom_gen CASCADE;
CREATE SCHEMA telecom;
CREATE SCHEMA telecom_gen;               -- generator helpers, dropped at the end
SET LOCAL search_path = telecom, telecom_gen, public;

-- -------------------------------------------------------------------------------------
-- Generator helpers
-- -------------------------------------------------------------------------------------
CREATE FUNCTION telecom_gen.rows_for(base numeric) RETURNS int LANGUAGE sql STABLE AS $$
  SELECT greatest(1, round(base * coalesce(nullif(current_setting('telecom.scale', true), ''), '1')::numeric))::int
$$;
CREATE FUNCTION telecom_gen.rint(lo bigint, hi bigint) RETURNS bigint LANGUAGE sql VOLATILE AS $$
  SELECT lo + floor(random() * (hi - lo + 1))::bigint
$$;
CREATE FUNCTION telecom_gen.rdate(lo date, hi date) RETURNS date LANGUAGE sql VOLATILE AS $$
  SELECT lo + floor(random() * (greatest(hi - lo, 0) + 1))::int
$$;
CREATE FUNCTION telecom_gen.rts(lo timestamp, hi timestamp) RETURNS timestamp LANGUAGE sql VOLATILE AS $$
  SELECT date_trunc('second', lo + random() * greatest(hi - lo, interval '0'))
$$;
-- Dates skewed toward recent years: the customer base grows over time.
CREATE FUNCTION telecom_gen.grow_date(lo date, hi date) RETURNS date LANGUAGE sql VOLATILE AS $$
  SELECT lo + floor(power(random(), 0.75) * (greatest(hi - lo, 0) + 1))::int
$$;
CREATE FUNCTION telecom_gen.pick(arr text[]) RETURNS text LANGUAGE sql VOLATILE AS $$
  SELECT arr[1 + floor(random() * cardinality(arr))::int]
$$;
-- Maps 0..m-1 one-to-one onto pseudo-random values in [0, m) for m = 10^n: the multiplier
-- ends in 3, so it is coprime to m (golden-ratio multiplicative hashing).
CREATE FUNCTION telecom_gen.scramble(k bigint, m bigint) RETURNS bigint LANGUAGE sql IMMUTABLE AS $$
  SELECT ((k::numeric * (floor(m * 0.0618033988749) * 10 + 3)) % m)::bigint
$$;
-- Appends the Luhn check digit (ICCID, IMEI).
CREATE FUNCTION telecom_gen.luhn(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT p || ((10 - sum(CASE WHEN (length(p) - i) % 2 = 0
                              THEN (substr(p, i, 1)::int * 2) % 10 + (substr(p, i, 1)::int * 2) / 10
                              ELSE substr(p, i, 1)::int END) % 10) % 10)::text
  FROM generate_series(1, length(p)) i
$$;
CREATE FUNCTION telecom_gen.first_name() RETURNS text LANGUAGE sql VOLATILE AS $$
  SELECT telecom_gen.pick('{James,Mary,John,Patricia,Robert,Jennifer,Michael,Linda,David,Elizabeth,Yassine,Amira,Mohamed,Fatma,Ahmed,Leila,Karim,Sofia,Lucas,Emma,Louis,Chloe,Hugo,Ines,Mateo,Lucia,Luca,Giulia,Lukas,Hannah,Jan,Anna,Sven,Ingrid,Hiroshi,Yuki,Wei,Mei,Arjun,Priya,Chinedu,Amara,Joao,Ana,Diego,Valentina,Liam,Olivia,Omar,Nour,Sami,Rania,Ivan,Olga,Kenji,Aiko,Pablo,Carmen,Noah,Ava}'::text[])
$$;
CREATE FUNCTION telecom_gen.last_name() RETURNS text LANGUAGE sql VOLATILE AS $$
  SELECT telecom_gen.pick('{Smith,Johnson,Williams,Brown,Jones,Garcia,Miller,Davis,Martin,Bernard,Dubois,Moreau,Laurent,Muller,Schmidt,Schneider,Fischer,Weber,Rossi,Russo,Ferrari,Esposito,Fernandez,Lopez,Martinez,Gonzalez,Silva,Santos,Costa,Pereira,Jansen,DeVries,Peeters,Nielsen,Hansen,Johansson,Nowak,Kowalski,Ben Ali,Trabelsi,Gharbi,Haddad,Mansour,Khalil,Okafor,Mensah,Kamau,Patel,Sharma,Singh,Tanaka,Suzuki,Sato,Wang,Li,Zhang,Chen,Kim,Murphy,Kelly}'::text[])
$$;

-- =====================================================================================
--  1-4  REFERENCE DATA
-- =====================================================================================
CREATE TABLE currencies (
  currency_code   char(3)      PRIMARY KEY,
  name            varchar(40)  NOT NULL UNIQUE,
  symbol          varchar(5)   NOT NULL,
  minor_units     smallint     NOT NULL DEFAULT 2
);
INSERT INTO currencies VALUES
 ('USD','US Dollar','$',2),('EUR','Euro','€',2),('GBP','Pound Sterling','£',2),('CHF','Swiss Franc','CHF',2),
 ('SEK','Swedish Krona','kr',2),('NOK','Norwegian Krone','kr',2),('DKK','Danish Krone','kr',2),('PLN','Polish Zloty','zł',2),
 ('TND','Tunisian Dinar','DT',3),('MAD','Moroccan Dirham','DH',2),('EGP','Egyptian Pound','E£',2),('ZAR','South African Rand','R',2),
 ('NGN','Nigerian Naira','₦',2),('KES','Kenyan Shilling','KSh',2),('AED','UAE Dirham','AED',2),('SAR','Saudi Riyal','SAR',2),
 ('INR','Indian Rupee','₹',2),('JPY','Japanese Yen','¥',0),('CNY','Chinese Yuan','CN¥',2),('BRL','Brazilian Real','R$',2),
 ('MXN','Mexican Peso','MX$',2),('AUD','Australian Dollar','A$',2);

CREATE TABLE countries (
  country_id      smallint     PRIMARY KEY,
  iso_code        char(2)      NOT NULL UNIQUE,
  name            varchar(60)  NOT NULL UNIQUE,
  dial_code       varchar(4)   NOT NULL UNIQUE,
  region          varchar(20)  NOT NULL,
  currency_code   char(3)      NOT NULL REFERENCES currencies,
  vat_rate        numeric(5,4) NOT NULL
);
INSERT INTO countries VALUES
 (1,'US','United States','1','North America','USD',0.0700),(2,'GB','United Kingdom','44','Europe','GBP',0.2000),
 (3,'FR','France','33','Europe','EUR',0.2000),(4,'DE','Germany','49','Europe','EUR',0.1900),
 (5,'ES','Spain','34','Europe','EUR',0.2100),(6,'IT','Italy','39','Europe','EUR',0.2200),
 (7,'NL','Netherlands','31','Europe','EUR',0.2100),(8,'BE','Belgium','32','Europe','EUR',0.2100),
 (9,'CH','Switzerland','41','Europe','CHF',0.0810),(10,'SE','Sweden','46','Europe','SEK',0.2500),
 (11,'NO','Norway','47','Europe','NOK',0.2500),(12,'DK','Denmark','45','Europe','DKK',0.2500),
 (13,'PL','Poland','48','Europe','PLN',0.2300),(14,'PT','Portugal','351','Europe','EUR',0.2300),
 (15,'IE','Ireland','353','Europe','EUR',0.2300),(16,'AT','Austria','43','Europe','EUR',0.2000),
 (17,'TN','Tunisia','216','Africa','TND',0.1900),(18,'MA','Morocco','212','Africa','MAD',0.2000),
 (19,'EG','Egypt','20','Africa','EGP',0.1400),(20,'ZA','South Africa','27','Africa','ZAR',0.1500),
 (21,'NG','Nigeria','234','Africa','NGN',0.0750),(22,'KE','Kenya','254','Africa','KES',0.1600),
 (23,'AE','United Arab Emirates','971','Middle East','AED',0.0500),(24,'SA','Saudi Arabia','966','Middle East','SAR',0.1500),
 (25,'IN','India','91','Asia','INR',0.1800),(26,'JP','Japan','81','Asia','JPY',0.1000),
 (27,'CN','China','86','Asia','CNY',0.1300),(28,'BR','Brazil','55','South America','BRL',0.1700),
 (29,'MX','Mexico','52','North America','MXN',0.1600),(30,'AU','Australia','61','Oceania','AUD',0.1000);

CREATE TABLE cities (
  city_id         int          PRIMARY KEY,          -- (country_id - 1) * 5 + n
  country_id      smallint     NOT NULL REFERENCES countries,
  name            varchar(60)  NOT NULL,
  population      int          NOT NULL,
  UNIQUE (country_id, name)
);
INSERT INTO cities
SELECT (c.country_id - 1) * 5 + t.ord, c.country_id, t.name, rint(80000, 9000000)
FROM (VALUES
 ('US','New York|Los Angeles|Chicago|Houston|Phoenix'),('GB','London|Manchester|Birmingham|Glasgow|Leeds'),
 ('FR','Paris|Lyon|Marseille|Toulouse|Lille'),('DE','Berlin|Hamburg|Munich|Cologne|Frankfurt'),
 ('ES','Madrid|Barcelona|Valencia|Seville|Bilbao'),('IT','Rome|Milan|Naples|Turin|Bologna'),
 ('NL','Amsterdam|Rotterdam|The Hague|Utrecht|Eindhoven'),('BE','Brussels|Antwerp|Ghent|Liege|Bruges'),
 ('CH','Zurich|Geneva|Basel|Bern|Lausanne'),('SE','Stockholm|Gothenburg|Malmo|Uppsala|Linkoping'),
 ('NO','Oslo|Bergen|Trondheim|Stavanger|Tromso'),('DK','Copenhagen|Aarhus|Odense|Aalborg|Esbjerg'),
 ('PL','Warsaw|Krakow|Lodz|Wroclaw|Gdansk'),('PT','Lisbon|Porto|Braga|Coimbra|Faro'),
 ('IE','Dublin|Cork|Limerick|Galway|Waterford'),('AT','Vienna|Graz|Linz|Salzburg|Innsbruck'),
 ('TN','Tunis|Sfax|Sousse|Kairouan|Bizerte'),('MA','Casablanca|Rabat|Marrakesh|Fes|Tangier'),
 ('EG','Cairo|Alexandria|Giza|Luxor|Port Said'),('ZA','Johannesburg|Cape Town|Durban|Pretoria|Gqeberha'),
 ('NG','Lagos|Abuja|Kano|Ibadan|Port Harcourt'),('KE','Nairobi|Mombasa|Kisumu|Nakuru|Eldoret'),
 ('AE','Dubai|Abu Dhabi|Sharjah|Ajman|Al Ain'),('SA','Riyadh|Jeddah|Mecca|Medina|Dammam'),
 ('IN','Mumbai|Delhi|Bangalore|Chennai|Kolkata'),('JP','Tokyo|Osaka|Yokohama|Nagoya|Sapporo'),
 ('CN','Shanghai|Beijing|Shenzhen|Guangzhou|Chengdu'),('BR','Sao Paulo|Rio de Janeiro|Brasilia|Salvador|Fortaleza'),
 ('MX','Mexico City|Guadalajara|Monterrey|Puebla|Tijuana'),('AU','Sydney|Melbourne|Brisbane|Perth|Adelaide')
) v(iso, names)
JOIN countries c ON c.iso_code = v.iso
CROSS JOIN LATERAL unnest(string_to_array(v.names, '|')) WITH ORDINALITY t(name, ord);

-- Daily (business days) FX history 1999 -> today as a random walk that drifts toward a
-- realistic present-day level. Rates are units of currency per 1 USD.
CREATE TABLE exchange_rates (
  currency_code   char(3)       NOT NULL REFERENCES currencies,
  rate_date       date          NOT NULL,
  units_per_usd   numeric(18,6) NOT NULL CHECK (units_per_usd > 0),
  PRIMARY KEY (currency_code, rate_date)
);
INSERT INTO exchange_rates
SELECT code, d, round((r1999 * exp(sum(step) OVER (PARTITION BY code ORDER BY d)))::numeric, 6)
FROM (
  SELECT c.code, c.r1999, d::date AS d,
         ln(c.r_now / c.r1999) / ((current_date - DATE '1999-01-01') * 5.0 / 7) + (random() - 0.5) * c.vol * 0.5 AS step
  FROM (VALUES ('EUR',0.86,0.92,0.012),('GBP',0.61,0.79,0.012),('CHF',1.38,0.88,0.012),('SEK',8.1,10.5,0.014),
               ('NOK',7.6,10.6,0.014),('DKK',6.4,6.9,0.012),('PLN',3.9,4.0,0.016),('TND',1.18,3.1,0.008),
               ('MAD',9.3,10.0,0.008),('EGP',3.4,48.0,0.010),('ZAR',6.1,18.2,0.020),('NGN',22.0,1500.0,0.012),
               ('KES',61.0,129.0,0.010),('AED',3.6725,3.6725,0.0),('SAR',3.75,3.75,0.0),('INR',42.5,84.0,0.008),
               ('JPY',113.0,150.0,0.012),('CNY',8.28,7.15,0.004),('BRL',1.2,5.4,0.020),('MXN',9.5,18.5,0.016),
               ('AUD',1.55,1.52,0.014)) c(code, r1999, r_now, vol)
  CROSS JOIN generate_series(DATE '1999-01-01', current_date, interval '1 day') d
  WHERE extract(isodow FROM d) < 6
) s;

-- Yearly average FX used to price local-currency documents (helper, dropped at the end).
CREATE TABLE telecom_gen.fx_year AS
SELECT currency_code, extract(year FROM rate_date)::int AS yr, avg(units_per_usd) AS rate
FROM exchange_rates GROUP BY 1, 2
UNION ALL
SELECT 'USD', y, 1 FROM generate_series(1999, extract(year FROM current_date)::int) y;
CREATE UNIQUE INDEX ON telecom_gen.fx_year (currency_code, yr);

-- =====================================================================================
--  5  EMPLOYEES (customer care, sales, procurement, network, finance ...)
-- =====================================================================================
CREATE TABLE employees (
  employee_id     int          PRIMARY KEY,
  first_name      varchar(40)  NOT NULL,
  last_name       varchar(40)  NOT NULL,
  email           varchar(120) NOT NULL UNIQUE,
  department      varchar(30)  NOT NULL,
  job_title       varchar(40)  NOT NULL,
  country_id      smallint     NOT NULL REFERENCES countries,
  manager_id      int          REFERENCES employees,
  hired_on        date         NOT NULL,
  terminated_on   date,
  salary_usd      numeric(10,2) NOT NULL,
  CHECK (terminated_on IS NULL OR terminated_on >= hired_on)
);
INSERT INTO employees
SELECT t.g, t.fn, t.ln, lower(replace(t.fn || '.' || t.ln, ' ', '')) || '.' || t.g || '@telco.example.com',
       t.dept,
       CASE WHEN t.g <= 30 THEN 'Director' WHEN t.g <= 300 THEN 'Manager'
            ELSE pick('{Analyst,Specialist,Agent,Engineer,Coordinator,Officer}') END,
       rint(1, 30),
       CASE WHEN t.g > 30 THEN rint(1, least(t.g - 1, 300)) END,
       t.hired_on,
       CASE WHEN random() < 0.25 THEN rdate(t.hired_on, current_date) END,
       round((CASE WHEN t.g <= 30 THEN 150000 WHEN t.g <= 300 THEN 90000 ELSE 45000 END * (0.8 + random() * 0.6))::numeric, 2)
FROM (SELECT g, first_name() AS fn, last_name() AS ln,
             pick('{Customer Care,Customer Care,Sales,Procurement,Network Operations,Finance,IT,Logistics,Marketing}') AS dept,
             CASE WHEN g <= 30 THEN rdate('1999-01-01', '2003-12-31') ELSE grow_date('1999-01-01', current_date) END AS hired_on
      FROM generate_series(1, rows_for(2500)) g) t;

-- =====================================================================================
--  6-10  NETWORK & NUMBERING
-- =====================================================================================
CREATE TABLE carriers (
  carrier_id      int          PRIMARY KEY,
  name            varchar(60)  NOT NULL UNIQUE,
  home_country_id smallint     NOT NULL REFERENCES countries,
  mcc_mnc         char(5)      NOT NULL UNIQUE,
  carrier_type    varchar(10)  NOT NULL CHECK (carrier_type IN ('MNO','MVNO')),
  founded_on      date         NOT NULL
);
INSERT INTO carriers VALUES
 (1,'Orbitel Mobile',3,'20801','MNO','1991-04-02'),(2,'Nordlink Mobile',10,'24001','MNO','1993-09-15'),
 (3,'Atlas Telecom',18,'60401','MNO','1998-06-01'),(4,'Sahara Connect',17,'60502','MNO','1998-11-20'),
 (5,'BlueWave Wireless',1,'31026','MNO','1994-03-08'),(6,'Helix Mobile',4,'26201','MNO','1992-07-01'),
 (7,'Medina Telecom',24,'42001','MNO','1997-02-14'),(8,'Pacifica Wireless',30,'50501','MNO','1993-05-05'),
 (9,'Andes Movil',28,'72405','MNO','1997-10-10'),(10,'Aurora Networks',11,'24201','MNO','1993-01-21'),
 (11,'Cedar Telecom',2,'23410','MNO','1985-01-01'),(12,'Kilimanjaro Mobile',22,'63902','MNO','1999-01-15'),
 (13,'Sakura Mobile',26,'44010','MNO','1992-08-01'),(14,'Dragon Link',27,'46000','MNO','1994-12-01'),
 (15,'Southern Cross Telecom',20,'65501','MNO','1993-06-30'),(16,'Iberia Movil',5,'21401','MNO','1995-10-01'),
 (17,'Alpine Mobile',9,'22801','MNO','1996-03-03'),(18,'Baltic Wave',13,'26002','MVNO','2005-04-01'),
 (19,'Nile Connect',19,'60201','MNO','1998-05-01'),(20,'Gulf Star Telecom',23,'42402','MNO','1996-09-09');

CREATE TABLE cell_towers (
  tower_id        int          PRIMARY KEY,
  tower_code      varchar(12)  NOT NULL UNIQUE,
  city_id         int          NOT NULL REFERENCES cities,
  carrier_id      int          NOT NULL REFERENCES carriers,
  technology      varchar(3)   NOT NULL CHECK (technology IN ('2G','3G','4G','5G')),
  installed_on    date         NOT NULL,
  decommissioned_on date,
  capacity_mbps   int          NOT NULL
);
INSERT INTO cell_towers
SELECT t.g, 'TWR-' || lpad(t.g::text, 6, '0'), 1 + (t.g - 1) % 150, rint(1, 20),
       CASE WHEN t.inst < '2004-01-01' THEN '2G' WHEN t.inst < '2011-01-01' THEN '3G'
            WHEN t.inst < '2019-06-01' THEN '4G' ELSE '5G' END,
       t.inst,
       CASE WHEN t.inst < '2010-01-01' AND random() < 0.3 THEN rdate(t.inst + 3650, current_date) END,
       CASE WHEN t.inst < '2004-01-01' THEN rint(1, 2) WHEN t.inst < '2011-01-01' THEN rint(14, 42)
            WHEN t.inst < '2019-06-01' THEN rint(150, 1000) ELSE rint(1000, 10000) END
FROM (SELECT g, rdate('1999-01-01', current_date - 30) AS inst FROM generate_series(1, 3000) g) t;  -- fixed size

CREATE TABLE number_ranges (
  range_id        int          PRIMARY KEY,           -- country = 1 + (range_id - 1) % 30
  country_id      smallint     NOT NULL REFERENCES countries,
  carrier_id      int          NOT NULL REFERENCES carriers,
  prefix          varchar(4)   NOT NULL,
  number_type     varchar(10)  NOT NULL CHECK (number_type IN ('mobile','fixed','tollfree')),
  allocated_on    date         NOT NULL,
  UNIQUE (country_id, prefix)
);
INSERT INTO number_ranges
SELECT r, 1 + (r - 1) % 30, 1 + (r - 1) % 20, (10 + (r - 1) / 30)::text,
       CASE WHEN r % 7 = 0 THEN 'fixed' WHEN r % 23 = 0 THEN 'tollfree' ELSE 'mobile' END,
       CASE WHEN r <= 120 THEN DATE '1999-01-01' ELSE rdate('1999-01-01', '2012-12-31') END
FROM generate_series(1, 210) r;                     -- fixed size

CREATE TABLE phone_numbers (
  phone_number_id bigint       PRIMARY KEY,           -- range = 1 + (id - 1) % 210
  range_id        int          NOT NULL REFERENCES number_ranges,
  e164            varchar(16)  NOT NULL UNIQUE,
  status          varchar(12)  NOT NULL DEFAULT 'available'
                               CHECK (status IN ('available','assigned','quarantine','reserved')),
  is_golden       boolean      NOT NULL,
  available_since date         NOT NULL
);
INSERT INTO phone_numbers
SELECT x.g, r.range_id, x.e164,
       CASE WHEN random() < 0.01 THEN 'reserved' ELSE 'available' END,
       x.e164 ~ '(\d)\1\1\1', r.allocated_on
FROM (SELECT g, 1 + (g - 1) % 210 AS rid,
             lpad(scramble((g - 1) / 210 + 1, 10000000)::text, 7, '0') AS subscriber_part
      FROM generate_series(1, rows_for(400000)) g) s
JOIN number_ranges r ON r.range_id = s.rid
JOIN countries c ON c.country_id = r.country_id
CROSS JOIN LATERAL (SELECT s.g, '+' || c.dial_code || r.prefix || s.subscriber_part AS e164) x;

CREATE TABLE device_models (
  model_id        int          PRIMARY KEY,           -- release year = 1999 + (id - 1) / 4
  brand           varchar(30)  NOT NULL,
  model_name      varchar(60)  NOT NULL UNIQUE,
  form_factor     varchar(12)  NOT NULL,
  operating_system varchar(20) NOT NULL,
  network_gen     varchar(3)   NOT NULL,
  released_on     date         NOT NULL,
  launch_price_usd numeric(8,2) NOT NULL
);
INSERT INTO device_models
SELECT k, b.brand, b.brand || ' ' || b.series || ' ' || (100 + k * 7), b.form,
       CASE WHEN y < 2008 THEN 'Proprietary RTOS' WHEN k % 3 = 0 THEN 'iOS' ELSE 'Android' END,
       CASE WHEN y < 2004 THEN '2G' WHEN y < 2011 THEN '3G' WHEN y < 2020 THEN '4G' ELSE '5G' END,
       make_date(y, 1, 1),
       round((CASE WHEN y < 2008 THEN 90 ELSE 250 END + (k % 4) * 150 + random() * 100)::numeric, 2)
FROM (SELECT k, 1999 + (k - 1) / 4 AS y FROM generate_series(1, 108) k) m   -- 4 models a year, 1999-2025
CROSS JOIN LATERAL (
  SELECT (ARRAY['Nova','Lumen','Pixelle','Zenko','Orion','Kestrel','Tundra','Vega'])[1 + k % 8] AS brand,
         (ARRAY['Classic','Slide','Flip','Edge','Note','Prime','Ultra','Lite','Max'])[1 + (k * 5) % 9] AS series,
         CASE WHEN y < 2008 THEN (ARRAY['bar','flip','slider'])[1 + k % 3]
              WHEN k % 9 = 0 THEN 'tablet' ELSE 'smartphone' END AS form
) b;

-- =====================================================================================
--  11-15  CUSTOMERS, PLANS, SUBSCRIPTIONS, SIMS, DEVICES
-- =====================================================================================
CREATE TABLE customers (
  customer_id     bigint       PRIMARY KEY,           -- country = 1 + (id - 1) % 30
  customer_type   varchar(10)  NOT NULL CHECK (customer_type IN ('consumer','business')),
  first_name      varchar(40)  NOT NULL,
  last_name       varchar(40)  NOT NULL,
  company_name    varchar(100),
  email           varchar(120) NOT NULL UNIQUE,
  national_id     varchar(20)  NOT NULL UNIQUE,
  birth_date      date,
  country_id      smallint     NOT NULL REFERENCES countries,
  segment         varchar(12)  NOT NULL,
  created_on      date         NOT NULL,
  closed_on       date,
  credit_limit    numeric(12,2) NOT NULL,
  CHECK (closed_on IS NULL OR closed_on >= created_on)
);
INSERT INTO customers
SELECT t.g, t.ctype, t.fn, t.ln,
       CASE WHEN t.ctype = 'business' THEN t.ln || ' ' || pick('{Holdings,Trading,Consulting,Logistics,Foods,Partners,Systems,Studio,Pharma,Motors}')
                                              || ' ' || pick('{Ltd,SA,GmbH,LLC,SARL,BV,Inc,SpA}') END,
       lower(replace(t.fn || '.' || t.ln, ' ', '')) || '.' || t.g || '@'
         || pick('{example.com,example.net,example.org,mail.test,inbox.test}'),
       c.iso_code || lpad(scramble(t.g, 1000000000)::text, 9, '0'),
       CASE WHEN t.ctype = 'consumer' THEN t.created_on - rint(18 * 366, 75 * 365)::int END,
       c.country_id,
       CASE WHEN t.ctype = 'consumer' THEN CASE WHEN random() < 0.55 THEN 'prepaid' ELSE 'postpaid' END
            ELSE CASE WHEN random() < 0.8 THEN 'sme' ELSE 'enterprise' END END,
       t.created_on,
       CASE WHEN random() < 0.15 THEN rdate(t.created_on, current_date) END,
       CASE WHEN t.ctype = 'consumer' THEN rint(1, 20) * 100 ELSE rint(10, 500) * 100 END
FROM (SELECT g, CASE WHEN random() < 0.85 THEN 'consumer' ELSE 'business' END AS ctype,
             first_name() AS fn, last_name() AS ln, grow_date('1999-01-01', current_date) AS created_on
      FROM generate_series(1, rows_for(120000)) g) t
JOIN countries c ON c.country_id = 1 + (t.g - 1) % 30;

CREATE TABLE customer_addresses (
  address_id      bigint       PRIMARY KEY,
  customer_id     bigint       NOT NULL REFERENCES customers,
  address_type    varchar(10)  NOT NULL CHECK (address_type IN ('billing','shipping','service')),
  street          varchar(120) NOT NULL,
  postal_code     varchar(10)  NOT NULL,
  city_id         int          NOT NULL REFERENCES cities,
  valid_from      date         NOT NULL,
  valid_to        date
);
INSERT INTO customer_addresses
SELECT x.g, cu.customer_id,
       CASE x.k WHEN 0 THEN 'billing' WHEN 1 THEN 'shipping' ELSE 'service' END,
       rint(1, 299) || ' ' || pick('{Main,Oak,Station,Harbour,Market,Garden,Park,Church,Mill,Lake,Olive,Palm,Cedar,Bridge}')
         || ' ' || pick('{Street,Avenue,Road,Lane,Boulevard,Way}'),
       lpad(rint(1000, 99999)::text, 5, '0'),
       (cu.country_id - 1) * 5 + rint(1, 5),
       CASE WHEN x.k = 0 THEN cu.created_on ELSE rdate(cu.created_on, coalesce(cu.closed_on, current_date)) END,
       cu.closed_on
FROM (SELECT g, 1 + (g - 1) % rows_for(120000) AS cid, (g - 1) / rows_for(120000) AS k
      FROM generate_series(1, rows_for(160000)) g) x
JOIN customers cu ON cu.customer_id = x.cid;

CREATE TABLE tariff_plans (
  plan_id         int          PRIMARY KEY,           -- launch year = 1999 + (id - 1) / 2
  name            varchar(60)  NOT NULL UNIQUE,
  plan_type       varchar(10)  NOT NULL CHECK (plan_type IN ('prepaid','postpaid')),
  monthly_fee_usd numeric(8,2) NOT NULL,
  included_minutes int         NOT NULL,
  included_sms    int          NOT NULL,
  included_data_mb int         NOT NULL,
  launched_on     date         NOT NULL,
  retired_on      date
);
INSERT INTO tariff_plans
SELECT k, 'Plan ' || y || CASE WHEN k % 2 = 1 THEN ' Essential' ELSE ' Premium' END,
       CASE WHEN k % 2 = 1 THEN 'prepaid' ELSE 'postpaid' END,
       round((CASE WHEN k % 2 = 1 THEN 15 ELSE 45 END * (1 + (y - 1999) * 0.02))::numeric, 2),
       CASE WHEN k % 2 = 1 THEN 100 + (y - 1999) * 20 ELSE 300 + (y - 1999) * 100 END,
       CASE WHEN k % 2 = 1 THEN 50 ELSE 500 END,
       CASE WHEN y < 2003 THEN 0 ELSE round(50 * exp((y - 2003) * 0.32) * CASE WHEN k % 2 = 1 THEN 1 ELSE 4 END)::int END,
       make_date(y, 1, 1),
       CASE WHEN make_date(y + 6, 1, 1) <= current_date THEN make_date(y + 6, 1, 1) END
FROM (SELECT k, 1999 + (k - 1) / 2 AS y FROM generate_series(1, 48) k) p;   -- 2 plans a year, 1999-2022

CREATE TABLE subscriptions (
  subscription_id bigint       PRIMARY KEY,           -- uses phone_number_id = subscription_id
  customer_id     bigint       NOT NULL REFERENCES customers,
  phone_number_id bigint       NOT NULL REFERENCES phone_numbers,
  plan_id         int          NOT NULL REFERENCES tariff_plans,
  start_date      date         NOT NULL,
  end_date        date,
  status          varchar(12)  NOT NULL CHECK (status IN ('active','suspended','terminated')),
  sales_channel   varchar(15)  NOT NULL,
  CHECK (end_date IS NULL OR end_date >= start_date)
);
INSERT INTO subscriptions
SELECT s.g, s.customer_id, s.g, (p.ly - 1999) * 2 + rint(1, 2), s.start_date, s.end_date,
       CASE WHEN s.end_date IS NOT NULL THEN 'terminated' WHEN random() < 0.03 THEN 'suspended' ELSE 'active' END,
       pick('{retail_store,online,call_center,partner,door_to_door}')
FROM (
  SELECT b.g, b.customer_id, b.start_date,
         CASE WHEN b.closed_on IS NOT NULL THEN b.closed_on
              WHEN b.churn < 0.35 THEN rdate(b.start_date, current_date) END AS end_date
  FROM (
    SELECT x.g, x.customer_id, x.churn, cu.closed_on,
           rdate(greatest(cu.created_on, nr.allocated_on),
                 least(greatest(cu.created_on, nr.allocated_on) + 1095, coalesce(cu.closed_on, current_date))) AS start_date,
           greatest(cu.created_on, nr.allocated_on) <= coalesce(cu.closed_on, current_date) AS valid
    FROM (SELECT g, (1 + (g - 1) % 30) + 30 * rint(0, (rows_for(120000) - 1 - (g - 1) % 30) / 30) AS customer_id,
                 random() AS churn
          FROM generate_series(1, rows_for(200000)) g) x            -- customer in the number's country
    JOIN customers cu     ON cu.customer_id = x.customer_id
    JOIN phone_numbers pn ON pn.phone_number_id = x.g
    JOIN number_ranges nr ON nr.range_id = pn.range_id
  ) b
  WHERE b.valid
) s
CROSS JOIN LATERAL (SELECT rint(greatest(1999, extract(year FROM s.start_date)::int - 5),
                                least(2022, extract(year FROM s.start_date)::int)) AS ly) p;

UPDATE phone_numbers pn
SET status = CASE WHEN s.end_date IS NULL THEN 'assigned'
                  WHEN s.end_date > current_date - 90 THEN 'quarantine' ELSE 'available' END
FROM subscriptions s
WHERE s.phone_number_id = pn.phone_number_id;

CREATE TABLE sim_cards (
  sim_id          bigint       PRIMARY KEY,
  subscription_id bigint       NOT NULL REFERENCES subscriptions,
  iccid           varchar(20)  NOT NULL UNIQUE,
  imsi            varchar(15)  NOT NULL UNIQUE,
  sim_type        varchar(8)   NOT NULL CHECK (sim_type IN ('standard','micro','nano','esim')),
  activated_on    date         NOT NULL,
  deactivated_on  date
);
INSERT INTO sim_cards
SELECT a.g, a.subscription_id,
       luhn('8988' || lpad(scramble(a.g, 100000000000000)::text, 14, '0')),
       a.mcc_mnc || lpad(scramble(a.g, 10000000000)::text, 10, '0'),
       CASE WHEN a.act < '2010-01-01' THEN 'standard' WHEN a.act < '2013-01-01' THEN 'micro'
            WHEN a.act < '2018-01-01' OR random() < 0.7 THEN 'nano' ELSE 'esim' END,
       a.act, a.end_date
FROM (
  SELECT x.g, s.subscription_id, s.end_date, ca.mcc_mnc,
         CASE WHEN x.g = s.subscription_id THEN s.start_date
              ELSE rdate(s.start_date, coalesce(s.end_date, current_date)) END AS act
  FROM (SELECT g, CASE WHEN g <= rows_for(200000) THEN g ELSE rint(1, rows_for(200000)) END AS sid
        FROM generate_series(1, rows_for(230000)) g) x
  JOIN subscriptions s  ON s.subscription_id = x.sid
  JOIN phone_numbers pn ON pn.phone_number_id = s.phone_number_id
  JOIN number_ranges nr ON nr.range_id = pn.range_id
  JOIN carriers ca      ON ca.carrier_id = nr.carrier_id
) a;

CREATE TABLE devices (
  device_id       bigint       PRIMARY KEY,
  customer_id     bigint       NOT NULL REFERENCES customers,
  model_id        int          NOT NULL REFERENCES device_models,
  imei            char(15)     NOT NULL UNIQUE,
  purchased_on    date         NOT NULL,
  purchase_price_usd numeric(8,2) NOT NULL,
  warranty_until  date         NOT NULL,
  status          varchar(10)  NOT NULL CHECK (status IN ('in_use','retired','lost','repaired'))
);
INSERT INTO devices
SELECT a.g, a.customer_id, a.model_id, luhn('35' || lpad(scramble(a.g, 1000000000000)::text, 12, '0')),
       a.purchased_on, round((dm.launch_price_usd * (0.7 + random() * 0.4))::numeric, 2),
       a.purchased_on + 730,
       CASE WHEN a.purchased_on < current_date - 1460 THEN pick('{retired,retired,lost,in_use}')
            ELSE pick('{in_use,in_use,in_use,repaired}') END
FROM (
  SELECT b.g, b.customer_id, b.purchased_on,
         (rint(greatest(1999, extract(year FROM b.purchased_on)::int - 3),
               least(2025, extract(year FROM b.purchased_on)::int)) - 1999) * 4 + rint(1, 4) AS model_id
  FROM (
    SELECT x.g, cu.customer_id, rdate(cu.created_on, coalesce(cu.closed_on, current_date)) AS purchased_on
    FROM (SELECT g, rint(1, rows_for(120000)) AS cid FROM generate_series(1, rows_for(180000)) g) x
    JOIN customers cu ON cu.customer_id = x.cid
  ) b
) a
JOIN device_models dm ON dm.model_id = a.model_id;

-- =====================================================================================
--  16-18  USAGE (call detail records, SMS, mobile data)
-- =====================================================================================
CREATE TABLE call_records (
  call_id         bigint       PRIMARY KEY,
  subscription_id bigint       NOT NULL REFERENCES subscriptions,
  tower_id        int          NOT NULL REFERENCES cell_towers,
  started_at      timestamp    NOT NULL,
  duration_sec    int          NOT NULL CHECK (duration_sec >= 0),
  direction       varchar(8)   NOT NULL CHECK (direction IN ('outgoing','incoming')),
  call_type       varchar(14)  NOT NULL CHECK (call_type IN ('local','national','international','voicemail')),
  other_party     varchar(16)  NOT NULL,
  charge_usd      numeric(10,4) NOT NULL
);
INSERT INTO call_records
SELECT c.g, c.sid, c.tower_id, c.started_at, c.duration_sec, c.direction, c.call_type, c.other_party,
       CASE WHEN c.direction = 'incoming' OR c.call_type = 'voicemail' THEN 0
            ELSE round((ceil(c.duration_sec / 60.0) * 0.25 * exp(-(extract(year FROM c.started_at) - 1999) * 0.09)
                        * CASE WHEN c.call_type = 'international' THEN 4 ELSE 1 END)::numeric, 4) END
FROM (
  SELECT x.g, s.subscription_id AS sid,
         ((x.c - 1) * 5 + rint(1, 5)) + 150 * rint(0, (2999 - ((x.c - 1) * 5)) / 150) AS tower_id,
         rts(s.start_date, coalesce(s.end_date, current_date) + interval '86399 seconds') AS started_at,
         greatest(1, round(-ln(1 - random()) * 150))::int AS duration_sec,
         CASE WHEN random() < 0.55 THEN 'outgoing' ELSE 'incoming' END AS direction,
         pick('{local,local,local,national,national,international,voicemail}') AS call_type,
         '+' || rint(20, 99) || rint(100000000, 999999999) AS other_party
  FROM (SELECT g, rint(1, rows_for(200000)) AS sid FROM generate_series(1, rows_for(2500000)) g) z
  CROSS JOIN LATERAL (SELECT z.g, 1 + (z.sid - 1) % 30 AS c) x          -- subscriber's country
  JOIN subscriptions s ON s.subscription_id = z.sid
) c
WHERE c.tower_id <= 3000;

CREATE TABLE sms_records (
  sms_id          bigint       PRIMARY KEY,
  subscription_id bigint       NOT NULL REFERENCES subscriptions,
  sent_at         timestamp    NOT NULL,
  direction       varchar(8)   NOT NULL CHECK (direction IN ('outgoing','incoming')),
  other_party     varchar(16)  NOT NULL,
  segments        smallint     NOT NULL,
  delivery_status varchar(10)  NOT NULL,
  charge_usd      numeric(8,4) NOT NULL
);
INSERT INTO sms_records
SELECT m.g, m.sid, m.sent_at, m.direction, m.other_party, m.segments,
       pick('{delivered,delivered,delivered,delivered,delivered,delivered,failed,pending}'),
       CASE WHEN m.direction = 'incoming' THEN 0
            ELSE round((m.segments * 0.10 * exp(-(extract(year FROM m.sent_at) - 1999) * 0.08))::numeric, 4) END
FROM (
  SELECT z.g, s.subscription_id AS sid,
         rts(s.start_date, coalesce(s.end_date, current_date) + interval '86399 seconds') AS sent_at,
         CASE WHEN random() < 0.5 THEN 'outgoing' ELSE 'incoming' END AS direction,
         '+' || rint(20, 99) || rint(100000000, 999999999) AS other_party,
         CASE WHEN random() < 0.85 THEN 1 ELSE rint(2, 4) END AS segments
  FROM (SELECT g, rint(1, rows_for(200000)) AS sid FROM generate_series(1, rows_for(1200000)) g) z
  JOIN subscriptions s ON s.subscription_id = z.sid
) m;

CREATE TABLE data_sessions (
  session_id      bigint       PRIMARY KEY,
  subscription_id bigint       NOT NULL REFERENCES subscriptions,
  tower_id        int          NOT NULL REFERENCES cell_towers,
  started_at      timestamp    NOT NULL,
  duration_sec    int          NOT NULL,
  technology      varchar(3)   NOT NULL,
  mb_used         numeric(12,3) NOT NULL,
  charge_usd      numeric(10,4) NOT NULL
);
INSERT INTO data_sessions
SELECT d.g, d.sid, d.tower_id, d.started_at, d.duration_sec,
       CASE WHEN d.started_at < '2004-01-01' THEN '2G' WHEN d.started_at < '2011-01-01' THEN '3G'
            WHEN d.started_at < '2019-06-01' OR random() < 0.6 THEN '4G' ELSE '5G' END,
       round((random() * exp((extract(year FROM d.started_at) - 2002) * 0.38))::numeric, 3) AS mb,
       round((random() * 0.5 * exp(-(extract(year FROM d.started_at) - 2002) * 0.12))::numeric, 4)
FROM (
  SELECT z.g, s.subscription_id AS sid,
         ((z.c - 1) * 5 + rint(1, 5)) + 150 * rint(0, (2999 - ((z.c - 1) * 5)) / 150) AS tower_id,
         rts(greatest(s.start_date, DATE '2002-01-01'),               -- mobile data starts with GPRS
             coalesce(s.end_date, current_date) + interval '86399 seconds') AS started_at,
         rint(5, 7200) AS duration_sec
  FROM (SELECT g, sid, 1 + (sid - 1) % 30 AS c
        FROM (SELECT g, rint(1, rows_for(200000)) AS sid FROM generate_series(1, rows_for(1200000)) g) q) z
  JOIN subscriptions s ON s.subscription_id = z.sid
  WHERE coalesce(s.end_date, current_date) >= DATE '2002-01-01'
) d
WHERE d.tower_id <= 3000;

-- =====================================================================================
--  19-21  BILLING (invoices in the customer's local currency)
-- =====================================================================================
CREATE TABLE invoices (
  invoice_id      bigint       PRIMARY KEY,
  subscription_id bigint       NOT NULL REFERENCES subscriptions,
  invoice_no      varchar(24)  NOT NULL UNIQUE,
  billing_period  date         NOT NULL,
  issued_on       date         NOT NULL,
  due_on          date         NOT NULL,
  currency_code   char(3)      NOT NULL REFERENCES currencies,
  subtotal        numeric(14,2) NOT NULL DEFAULT 0,
  tax_amount      numeric(14,2) NOT NULL DEFAULT 0,
  total_amount    numeric(14,2) NOT NULL DEFAULT 0,
  status          varchar(12)  NOT NULL DEFAULT 'open'
                               CHECK (status IN ('open','paid','overdue','written_off')),
  UNIQUE (subscription_id, billing_period)
);
INSERT INTO invoices (invoice_id, subscription_id, invoice_no, billing_period, issued_on, due_on, currency_code)
SELECT v.g, v.sid, 'INV-' || to_char(v.period, 'YYYYMM') || '-' || lpad(v.g::text, 9, '0'),
       v.period, (v.period + interval '1 month')::date, (v.period + interval '1 month')::date + 15, v.currency_code
FROM (
  SELECT y.g, y.sid, y.end_date, y.currency_code,
         (date_trunc('month', y.start_date) + make_interval(months => (y.k * y.stride + rint(0, y.stride - 1))::int))::date AS period
  FROM (
    SELECT x.g, x.sid, x.k, s.start_date, s.end_date, co.currency_code,
           greatest(1, ((extract(year FROM coalesce(s.end_date, current_date)) - extract(year FROM s.start_date)) * 12
                      + extract(month FROM coalesce(s.end_date, current_date)) - extract(month FROM s.start_date) + 1)::int
                      / ceil(rows_for(700000)::numeric / rows_for(200000))::int) AS stride
    FROM (SELECT g, 1 + (g - 1) % rows_for(200000) AS sid, (g - 1) / rows_for(200000) AS k
          FROM generate_series(1, rows_for(700000)) g) x
    JOIN subscriptions s ON s.subscription_id = x.sid
    JOIN countries co    ON co.country_id = 1 + (x.sid - 1) % 30
  ) y
) v
WHERE v.period <= coalesce(v.end_date, current_date)
  AND (v.period + interval '1 month')::date <= current_date;

CREATE TABLE invoice_lines (
  line_id         bigint       PRIMARY KEY,
  invoice_id      bigint       NOT NULL REFERENCES invoices,
  line_no         smallint     NOT NULL,
  line_type       varchar(20)  NOT NULL,
  description     varchar(100) NOT NULL,
  quantity        numeric(12,3) NOT NULL,
  unit_price      numeric(14,4) NOT NULL,
  amount          numeric(14,2) NOT NULL,
  UNIQUE (invoice_id, line_no)
);
INSERT INTO invoice_lines
SELECT l.g, l.invoice_id, l.line_no, l.line_type,
       CASE l.line_type WHEN 'plan_fee' THEN l.plan_name || ' - ' || to_char(l.billing_period, 'Mon YYYY')
                        WHEN 'voice_usage' THEN 'Out-of-bundle minutes'
                        WHEN 'data_usage' THEN 'Out-of-bundle data (MB)'
                        WHEN 'roaming' THEN 'Roaming charges'
                        WHEN 'device_installment' THEN 'Device installment'
                        ELSE 'Value added services' END,
       l.qty, round((l.unit_usd * fx.rate)::numeric, 4), round((l.qty * l.unit_usd * fx.rate)::numeric, 2)
FROM (
  SELECT q.*,
         CASE q.line_type WHEN 'plan_fee' THEN 1 WHEN 'voice_usage' THEN rint(0, 300)
                          WHEN 'data_usage' THEN rint(0, 5000) WHEN 'roaming' THEN rint(1, 50) ELSE 1 END AS qty,
         CASE q.line_type WHEN 'plan_fee' THEN q.monthly_fee_usd WHEN 'voice_usage' THEN 0.05
                          WHEN 'data_usage' THEN 0.01 WHEN 'roaming' THEN 0.80
                          WHEN 'device_installment' THEN round((15 + random() * 40)::numeric, 2)
                          ELSE round((1 + random() * 9)::numeric, 2) END AS unit_usd
  FROM (
    SELECT x.g, i.invoice_id, x.line_no, i.billing_period, i.currency_code, tp.monthly_fee_usd, tp.name AS plan_name,
           CASE x.line_no WHEN 1 THEN 'plan_fee' WHEN 2 THEN 'voice_usage'
                ELSE pick('{data_usage,roaming,device_installment,value_added_service}') END AS line_type
    FROM (SELECT g, 1 + (g - 1) % rows_for(700000) AS iid, (g - 1) / rows_for(700000) + 1 AS line_no
          FROM generate_series(1, rows_for(1800000)) g) x
    JOIN invoices i      ON i.invoice_id = x.iid
    JOIN subscriptions s ON s.subscription_id = i.subscription_id
    JOIN tariff_plans tp ON tp.plan_id = s.plan_id
  ) q
) l
JOIN telecom_gen.fx_year fx ON fx.currency_code = l.currency_code AND fx.yr = extract(year FROM l.billing_period);

UPDATE invoices i
SET subtotal = t.subtotal, tax_amount = round(t.subtotal * co.vat_rate, 2), total_amount = t.subtotal + round(t.subtotal * co.vat_rate, 2)
FROM (SELECT invoice_id, sum(amount) AS subtotal FROM invoice_lines GROUP BY invoice_id) t,
     subscriptions s, customers cu, countries co
WHERE t.invoice_id = i.invoice_id AND s.subscription_id = i.subscription_id
  AND cu.customer_id = s.customer_id AND co.country_id = cu.country_id;

CREATE TABLE payments (
  payment_id      bigint       PRIMARY KEY,
  invoice_id      bigint       NOT NULL REFERENCES invoices,
  paid_on         date         NOT NULL,
  amount          numeric(14,2) NOT NULL,
  currency_code   char(3)      NOT NULL REFERENCES currencies,
  method          varchar(15)  NOT NULL,
  reference       varchar(30)  NOT NULL UNIQUE
);
INSERT INTO payments
SELECT p.invoice_id, p.invoice_id, p.paid_on, p.total_amount, p.currency_code,
       CASE WHEN p.paid_on < '2005-01-01' THEN pick('{cheque,cash,bank_transfer,card}')
            WHEN p.paid_on < '2013-01-01' THEN pick('{direct_debit,card,bank_transfer,cash}')
            ELSE pick('{direct_debit,card,mobile_wallet,mobile_wallet,bank_transfer}') END,
       'PAY-' || to_char(p.paid_on, 'YYYYMMDD') || '-' || lpad(p.invoice_id::text, 10, '0')
FROM (SELECT i.invoice_id, i.total_amount, i.currency_code, least(i.issued_on + rint(0, 40)::int, current_date) AS paid_on,
             random() AS r
      FROM invoices i) p
WHERE p.r < 0.94;

UPDATE invoices i
SET status = CASE WHEN p.invoice_id IS NOT NULL THEN 'paid'
                  WHEN i.due_on < current_date - 730 THEN 'written_off'
                  WHEN i.due_on < current_date THEN 'overdue' ELSE 'open' END
FROM invoices i0
LEFT JOIN payments p ON p.invoice_id = i0.invoice_id
WHERE i0.invoice_id = i.invoice_id;

-- =====================================================================================
--  22-26  CUSTOMER CARE, PORTABILITY, ROAMING
-- =====================================================================================
CREATE TABLE support_tickets (
  ticket_id       bigint       PRIMARY KEY,
  customer_id     bigint       NOT NULL REFERENCES customers,
  assigned_employee_id int     REFERENCES employees,
  channel         varchar(10)  NOT NULL,
  category        varchar(20)  NOT NULL,
  priority        varchar(8)   NOT NULL CHECK (priority IN ('low','medium','high','critical')),
  opened_at       timestamp    NOT NULL,
  closed_at       timestamp,
  status          varchar(16)  NOT NULL,
  satisfaction    smallint     CHECK (satisfaction BETWEEN 1 AND 5)
);
INSERT INTO support_tickets
SELECT t.g, t.customer_id, rint(1, rows_for(2500)),
       CASE WHEN t.opened_at < '2008-01-01' THEN pick('{phone,phone,store,email}')
            ELSE pick('{phone,app,chat,email,store,social}') END,
       pick('{billing,network_coverage,device,sim_activation,porting,roaming,plan_change,complaint}'),
       pick('{low,medium,medium,high,critical}'),
       t.opened_at, t.closed_at,
       CASE WHEN t.closed_at IS NULL THEN pick('{open,in_progress,waiting_customer}') ELSE 'closed' END,
       CASE WHEN t.closed_at IS NOT NULL AND random() < 0.6 THEN rint(1, 5) END
FROM (
  SELECT b.g, b.customer_id, b.opened_at,
         CASE WHEN b.opened_at < current_date - 30 OR random() < 0.5
              THEN least(b.opened_at + random() * interval '20 days', localtimestamp(0)) END AS closed_at
  FROM (
    SELECT x.g, cu.customer_id, rts(cu.created_on, coalesce(cu.closed_on, current_date) + interval '86399 seconds') AS opened_at
    FROM (SELECT g, rint(1, rows_for(120000)) AS cid FROM generate_series(1, rows_for(90000)) g) x
    JOIN customers cu ON cu.customer_id = x.cid
  ) b
) t;

CREATE TABLE ticket_events (
  event_id        bigint       PRIMARY KEY,
  ticket_id       bigint       NOT NULL REFERENCES support_tickets,
  event_seq       smallint     NOT NULL,
  event_at        timestamp    NOT NULL,
  event_type      varchar(16)  NOT NULL,
  employee_id     int          REFERENCES employees,
  note            varchar(200),
  UNIQUE (ticket_id, event_seq)
);
INSERT INTO ticket_events
SELECT x.g, t.ticket_id, x.seq,
       CASE WHEN x.seq = 1 THEN t.opened_at
            ELSE rts(t.opened_at, coalesce(t.closed_at, t.opened_at + interval '7 days')) END,
       CASE WHEN x.seq = 1 THEN 'created' ELSE pick('{assigned,comment,customer_reply,escalated,field_visit}') END,
       CASE WHEN x.seq = 1 THEN NULL ELSE t.assigned_employee_id END,
       pick('{Customer called back,Checked network logs,Refund requested,Replaced SIM,Escalated to tier 2,Waiting for customer,Issue reproduced,Credit note issued}')
FROM (SELECT g, 1 + (g - 1) % rows_for(90000) AS tid, (g - 1) / rows_for(90000) + 1 AS seq
      FROM generate_series(1, rows_for(300000)) g) x
JOIN support_tickets t ON t.ticket_id = x.tid;

CREATE TABLE port_requests (
  port_id         bigint       PRIMARY KEY,
  port_ref        varchar(24)  NOT NULL UNIQUE,
  phone_number_id bigint       NOT NULL REFERENCES phone_numbers,
  from_carrier_id int          NOT NULL REFERENCES carriers,
  to_carrier_id   int          NOT NULL REFERENCES carriers,
  direction       varchar(8)   NOT NULL CHECK (direction IN ('port_in','port_out')),
  requested_on    date         NOT NULL,
  completed_on    date,
  status          varchar(10)  NOT NULL,
  CHECK (from_carrier_id <> to_carrier_id)
);
INSERT INTO port_requests
SELECT p.g, 'MNP-' || to_char(p.requested_on, 'YYYY') || '-' || lpad(p.g::text, 8, '0'),
       p.phone_number_id, p.from_carrier, p.to_carrier,
       CASE WHEN random() < 0.5 THEN 'port_in' ELSE 'port_out' END,
       p.requested_on,
       CASE WHEN p.r < 0.85 THEN least(p.requested_on + rint(1, 10)::int, current_date) END,
       CASE WHEN p.r < 0.85 THEN 'completed' WHEN p.r < 0.95 THEN 'rejected' ELSE 'pending' END
FROM (
  SELECT x.g, pn.phone_number_id, nr.carrier_id AS from_carrier, (nr.carrier_id + rint(0, 18)) % 20 + 1 AS to_carrier,
         rdate(greatest(nr.allocated_on, DATE '2003-01-01'), current_date) AS requested_on,  -- number portability from 2003
         random() AS r
  FROM (SELECT g, rint(1, rows_for(400000)) AS pid FROM generate_series(1, rows_for(25000)) g) x
  JOIN phone_numbers pn ON pn.phone_number_id = x.pid
  JOIN number_ranges nr ON nr.range_id = pn.range_id
) p;

CREATE TABLE roaming_partners (
  partner_id      int          PRIMARY KEY,
  home_carrier_id int          NOT NULL REFERENCES carriers,
  visited_carrier_id int       NOT NULL REFERENCES carriers,
  agreement_start date         NOT NULL,
  agreement_end   date,
  rate_per_min_usd numeric(8,4) NOT NULL,
  rate_per_mb_usd numeric(8,4) NOT NULL,
  UNIQUE (home_carrier_id, visited_carrier_id),
  CHECK (home_carrier_id <> visited_carrier_id)
);
INSERT INTO roaming_partners
SELECT row_number() OVER (ORDER BY r), a, b, st,
       CASE WHEN random() < 0.2 THEN rdate(st + 365, current_date) END,
       round((0.2 + random() * 1.3)::numeric, 4), round((0.01 + random() * 2)::numeric, 4)
FROM (SELECT a, b, random() AS r, rdate('1999-01-01', '2015-12-31') AS st
      FROM generate_series(1, 20) a CROSS JOIN generate_series(1, 20) b WHERE a <> b) pairs
ORDER BY r
LIMIT 150;                                          -- fixed size

CREATE TABLE roaming_events (
  roaming_event_id bigint      PRIMARY KEY,
  subscription_id bigint       NOT NULL REFERENCES subscriptions,
  partner_id      int          NOT NULL REFERENCES roaming_partners,
  event_date      date         NOT NULL,
  minutes_used    int          NOT NULL,
  sms_sent        int          NOT NULL,
  mb_used         numeric(12,3) NOT NULL,
  charge_usd      numeric(12,2) NOT NULL
);
INSERT INTO roaming_events
SELECT e.g, e.sid, e.partner_id, e.event_date, e.minutes, e.sms, e.mb,
       round((e.minutes * rp.rate_per_min_usd + e.mb * rp.rate_per_mb_usd * exp(-(extract(year FROM e.event_date) - 1999) * 0.2)
              + e.sms * 0.3)::numeric, 2)
FROM (
  SELECT x.g, s.subscription_id AS sid, rint(1, 150) AS partner_id,
         rdate(s.start_date, coalesce(s.end_date, current_date)) AS event_date,
         rint(0, 120) AS minutes, rint(0, 40) AS sms, round((random() * 800)::numeric, 3) AS mb
  FROM (SELECT g, rint(1, rows_for(200000)) AS sid FROM generate_series(1, rows_for(250000)) g) x
  JOIN subscriptions s ON s.subscription_id = x.sid
) e
JOIN roaming_partners rp ON rp.partner_id = e.partner_id;

-- =====================================================================================
--  27-33  SUPPLIERS & CATALOG
-- =====================================================================================
CREATE TABLE suppliers (
  supplier_id     int          PRIMARY KEY,
  name            varchar(100) NOT NULL,
  vat_number      varchar(16)  NOT NULL UNIQUE,
  country_id      smallint     NOT NULL REFERENCES countries,
  city_id         int          NOT NULL REFERENCES cities,
  category        varchar(30)  NOT NULL,
  onboarded_on    date         NOT NULL,
  offboarded_on   date,
  rating          numeric(2,1) NOT NULL CHECK (rating BETWEEN 1 AND 5),
  payment_terms_days smallint  NOT NULL,
  CHECK (offboarded_on IS NULL OR offboarded_on >= onboarded_on)
);
INSERT INTO suppliers
SELECT s.g,
       pick('{Global,Prime,Euro,Atlas,Delta,Nexus,Summit,Vertex,Pioneer,Apex,Royal,United,Silver,Coastal}') || ' '
         || pick('{Components,Telecom Supplies,Electronics,Cabling,Logistics,Networks,Devices,Facilities,Print,Software,Power,Packaging}') || ' '
         || pick('{Ltd,SA,GmbH,LLC,SARL,BV,Inc,SpA,AB,Pty}'),
       c.iso_code || lpad(scramble(s.g, 1000000000)::text, 9, '0') || lpad((s.g % 100)::text, 2, '0'),
       c.country_id, (c.country_id - 1) * 5 + rint(1, 5),
       pick('{handsets,network_equipment,it_services,facilities,marketing,logistics,energy,consulting}'),
       s.onboarded_on,
       CASE WHEN random() < 0.2 THEN rdate(s.onboarded_on + 365, current_date) END,
       round((1 + random() * 4)::numeric, 1),
       (ARRAY[15, 30, 30, 45, 60, 90])[rint(1, 6)]
FROM (SELECT g, rint(1, 30) AS cid, rdate('1999-01-01', current_date - 400) AS onboarded_on
      FROM generate_series(1, rows_for(1500)) g) s
JOIN countries c ON c.country_id = s.cid;

CREATE TABLE supplier_contacts (
  contact_id      int          PRIMARY KEY,
  supplier_id     int          NOT NULL REFERENCES suppliers,
  full_name       varchar(80)  NOT NULL,
  role            varchar(30)  NOT NULL,
  email           varchar(120) NOT NULL UNIQUE,
  phone           varchar(20)  NOT NULL,
  is_primary      boolean      NOT NULL
);
INSERT INTO supplier_contacts
SELECT x.g, x.sid, x.fn || ' ' || x.ln,
       pick('{Account Manager,Sales Director,Billing Contact,Logistics Coordinator,Technical Support,CEO}'),
       lower(replace(x.fn || '.' || x.ln, ' ', '')) || '.' || x.g || '@supplier' || x.sid || '.example',
       '+' || c.dial_code || rint(100000000, 999999999), x.k = 0
FROM (SELECT g, 1 + (g - 1) % rows_for(1500) AS sid, (g - 1) / rows_for(1500) AS k, first_name() AS fn, last_name() AS ln
      FROM generate_series(1, rows_for(4500)) g) x
JOIN suppliers su ON su.supplier_id = x.sid
JOIN countries c  ON c.country_id = su.country_id;

CREATE TABLE supplier_contracts (
  contract_id     int          PRIMARY KEY,
  contract_no     varchar(24)  NOT NULL UNIQUE,
  supplier_id     int          NOT NULL REFERENCES suppliers,
  contract_type   varchar(20)  NOT NULL,
  start_date      date         NOT NULL,
  end_date        date         NOT NULL,
  annual_value_usd numeric(14,2) NOT NULL,
  signed_by_employee_id int    NOT NULL REFERENCES employees,
  status          varchar(10)  NOT NULL,
  CHECK (end_date > start_date)
);
INSERT INTO supplier_contracts
SELECT c.g, 'CTR-' || to_char(c.start_date, 'YYYY') || '-' || lpad(c.g::text, 7, '0'), c.supplier_id,
       pick('{framework,master_services,purchase,maintenance,lease,sla}'),
       c.start_date, c.end_date, round((5000 + random() * random() * 2000000)::numeric, 2), rint(1, rows_for(2500)),
       CASE WHEN c.end_date < current_date THEN 'expired' WHEN random() < 0.05 THEN 'terminated' ELSE 'active' END
FROM (
  SELECT b.*, b.start_date + rint(365, 5 * 365)::int AS end_date
  FROM (SELECT x.g, su.supplier_id, rdate(su.onboarded_on, coalesce(su.offboarded_on, current_date)) AS start_date
        FROM (SELECT g, rint(1, rows_for(1500)) AS sid FROM generate_series(1, rows_for(6000)) g) x
        JOIN suppliers su ON su.supplier_id = x.sid) b
) c;

CREATE TABLE product_categories (
  category_id     int          PRIMARY KEY,
  parent_id       int          REFERENCES product_categories,
  name            varchar(40)  NOT NULL UNIQUE
);
INSERT INTO product_categories VALUES
 (1,NULL,'Devices'),(2,NULL,'Network Equipment'),(3,NULL,'IT & Software'),(4,NULL,'Facilities'),
 (5,NULL,'Logistics & Packaging'),(6,NULL,'Marketing'),
 (7,1,'Smartphones'),(8,1,'Feature Phones'),(9,1,'SIM & eSIM Profiles'),(10,1,'Routers & Modems'),
 (11,2,'Radio Antennas'),(12,2,'Fiber & Cabling'),(13,2,'Core Switches'),(14,2,'Power & Batteries'),
 (15,3,'Servers'),(16,3,'Software Licenses'),(17,3,'Laptops'),(18,4,'Office Furniture'),
 (19,4,'Cleaning & Maintenance'),(20,4,'Security Services'),(21,5,'Packaging Materials'),
 (22,5,'Courier Services'),(23,6,'Printed Materials'),(24,6,'Promotional Items');

CREATE TABLE products (
  product_id      int          PRIMARY KEY,
  category_id     int          NOT NULL REFERENCES product_categories,
  sku             varchar(20)  NOT NULL UNIQUE,
  name            varchar(100) NOT NULL,
  unit_of_measure varchar(10)  NOT NULL,
  standard_cost_usd numeric(12,2) NOT NULL,
  introduced_on   date         NOT NULL,
  discontinued_on date
);
INSERT INTO products
SELECT p.g, p.cat, 'SKU-' || lpad(p.cat::text, 2, '0') || '-' || lpad(p.g::text, 7, '0'),
       pick('{Pro,Lite,Max,Eco,Plus,Smart,Ultra,Core,Edge,Flex}') || ' '
         || (ARRAY['Smartphone','Feature Phone','SIM Pack','Router','Antenna','Fiber Cable','Switch','Battery Pack','Rack Server',
                   'License','Laptop','Desk','Cleaning Kit','Guard Service','Carton Box','Courier Bundle','Brochure','Branded Mug'])[p.cat - 6]
         || ' ' || chr(65 + (p.g % 26)) || chr(65 + ((p.g / 26) % 26)) || '-' || (p.g % 900 + 100),
       CASE WHEN p.cat = 12 THEN 'm' WHEN p.cat = 16 THEN 'license' WHEN p.cat IN (20, 22) THEN 'service'
            WHEN p.cat IN (9, 21, 23) THEN 'pack' ELSE 'each' END,
       round((CASE WHEN p.cat IN (13, 15) THEN 2000 + random() * 20000 WHEN p.cat IN (7, 11, 17) THEN 100 + random() * 900
                   WHEN p.cat IN (12, 9, 21, 23, 24) THEN 0.5 + random() * 20 ELSE 10 + random() * 400 END)::numeric, 2),
       p.intro,
       CASE WHEN random() < 0.3 THEN rdate(p.intro + 365, current_date) END
FROM (SELECT g, 7 + (g - 1) % 18 AS cat, rdate('1999-01-01', current_date - 400) AS intro
      FROM generate_series(1, rows_for(4000)) g) p;

CREATE TABLE supplier_products (
  supplier_product_id int      PRIMARY KEY,
  supplier_id     int          NOT NULL REFERENCES suppliers,
  product_id      int          NOT NULL REFERENCES products,
  supplier_sku    varchar(24)  NOT NULL,
  unit_price_usd  numeric(12,2) NOT NULL,
  lead_time_days  smallint     NOT NULL,
  min_order_qty   int          NOT NULL,
  valid_from      date         NOT NULL,
  UNIQUE (supplier_id, product_id)
);
INSERT INTO supplier_products
SELECT x.g, x.sid, pr.product_id, 'S' || x.sid || '-' || lpad(scramble(x.g, 100000000)::text, 8, '0'),
       round((pr.standard_cost_usd * (0.85 + random() * 0.4))::numeric, 2), rint(2, 90),
       (ARRAY[1, 10, 50, 100, 500])[rint(1, 5)], greatest(pr.introduced_on, su.onboarded_on)
FROM (SELECT g, 1 + (g - 1) % rows_for(4000) AS pid,
             1 + ((1 + (g - 1) % rows_for(4000)) * 37 + (g - 1) / rows_for(4000)) % rows_for(1500) AS sid
      FROM generate_series(1, rows_for(15000)) g) x
JOIN products pr  ON pr.product_id = x.pid
JOIN suppliers su ON su.supplier_id = x.sid
ON CONFLICT (supplier_id, product_id) DO NOTHING;

-- =====================================================================================
--  34-40  PROCUREMENT & INVENTORY
-- =====================================================================================
CREATE TABLE warehouses (
  warehouse_id    int          PRIMARY KEY,
  code            varchar(10)  NOT NULL UNIQUE,
  name            varchar(60)  NOT NULL,
  city_id         int          NOT NULL REFERENCES cities,
  capacity_m3     int          NOT NULL,
  opened_on       date         NOT NULL
);
INSERT INTO warehouses
SELECT w, 'WH-' || lpad(w::text, 3, '0'), ci.name || ' Distribution Center', ci.city_id, rint(2000, 60000),
       CASE WHEN w <= 10 THEN DATE '1999-01-01' ELSE rdate('1999-01-01', '2018-12-31') END
FROM generate_series(1, 30) w
JOIN cities ci ON ci.city_id = (w * 5 - 4);          -- fixed size, first city of each country

CREATE TABLE purchase_orders (
  po_id           bigint       PRIMARY KEY,
  po_number       varchar(20)  NOT NULL UNIQUE,
  supplier_id     int          NOT NULL REFERENCES suppliers,
  warehouse_id    int          NOT NULL REFERENCES warehouses,
  buyer_employee_id int        NOT NULL REFERENCES employees,
  order_date      date         NOT NULL,
  expected_date   date         NOT NULL,
  status          varchar(10)  NOT NULL CHECK (status IN ('draft','approved','sent','received','closed','cancelled')),
  currency_code   char(3)      NOT NULL REFERENCES currencies,
  total_amount    numeric(14,2) NOT NULL DEFAULT 0
);
INSERT INTO purchase_orders
SELECT o.g, 'PO-' || to_char(o.order_date, 'YYYY') || '-' || lpad(o.g::text, 8, '0'), o.supplier_id, o.warehouse_id,
       rint(1, rows_for(2500)), o.order_date, o.order_date + rint(3, 60)::int,
       CASE WHEN o.order_date > current_date - 20 THEN pick('{draft,approved,sent}')
            WHEN o.order_date > current_date - 60 THEN pick('{sent,received,received}')
            WHEN random() < 0.04 THEN 'cancelled' ELSE 'closed' END,
       'USD', 0
FROM (SELECT x.g, su.supplier_id, rint(1, 30) AS warehouse_id,
             rdate(greatest(su.onboarded_on, DATE '1999-01-01'), coalesce(su.offboarded_on, current_date)) AS order_date
      FROM (SELECT g, rint(1, rows_for(1500)) AS sid FROM generate_series(1, rows_for(80000)) g) x
      JOIN suppliers su ON su.supplier_id = x.sid) o;

CREATE TABLE purchase_order_lines (
  po_line_id      bigint       PRIMARY KEY,
  po_id           bigint       NOT NULL REFERENCES purchase_orders,
  line_no         smallint     NOT NULL,
  product_id      int          NOT NULL REFERENCES products,
  quantity        int          NOT NULL CHECK (quantity > 0),
  unit_price_usd  numeric(12,2) NOT NULL,
  line_amount     numeric(14,2) NOT NULL,
  UNIQUE (po_id, line_no)
);
INSERT INTO purchase_order_lines
SELECT l.g, l.po_id, l.line_no, l.product_id, l.qty, l.price, l.qty * l.price
FROM (SELECT x.g, x.po_id, x.line_no, pr.product_id, rint(1, 500)::int AS qty,
             round((pr.standard_cost_usd * (0.85 + random() * 0.4))::numeric, 2) AS price
      FROM (SELECT g, 1 + (g - 1) % rows_for(80000) AS po_id, (g - 1) / rows_for(80000) + 1 AS line_no,
                   rint(1, rows_for(4000)) AS pid
            FROM generate_series(1, rows_for(320000)) g) x
      JOIN products pr ON pr.product_id = x.pid) l;

UPDATE purchase_orders po SET total_amount = t.total
FROM (SELECT po_id, sum(line_amount) AS total FROM purchase_order_lines GROUP BY po_id) t
WHERE t.po_id = po.po_id;

CREATE TABLE goods_receipts (
  receipt_id      bigint       PRIMARY KEY,
  receipt_no      varchar(20)  NOT NULL UNIQUE,
  po_id           bigint       NOT NULL REFERENCES purchase_orders,
  warehouse_id    int          NOT NULL REFERENCES warehouses,
  received_on     date         NOT NULL,
  received_by_employee_id int  NOT NULL REFERENCES employees,
  condition       varchar(10)  NOT NULL CHECK (condition IN ('ok','partial','damaged'))
);
INSERT INTO goods_receipts
SELECT row_number() OVER (ORDER BY r.po_id), 'GR-' || lpad(r.po_id::text, 10, '0'), r.po_id, r.warehouse_id,
       r.received_on, rint(1, rows_for(2500)), pick('{ok,ok,ok,ok,ok,ok,partial,damaged}')
FROM (SELECT po_id, warehouse_id, least(expected_date + rint(-2, 10)::int, current_date) AS received_on
      FROM purchase_orders WHERE status IN ('received', 'closed')) r;

CREATE TABLE supplier_invoices (
  supplier_invoice_id bigint   PRIMARY KEY,
  supplier_id     int          NOT NULL REFERENCES suppliers,
  po_id           bigint       NOT NULL REFERENCES purchase_orders,
  invoice_ref     varchar(24)  NOT NULL,
  invoice_date    date         NOT NULL,
  due_date        date         NOT NULL,
  amount_usd      numeric(14,2) NOT NULL,
  status          varchar(10)  NOT NULL DEFAULT 'open' CHECK (status IN ('open','paid','disputed')),
  UNIQUE (supplier_id, invoice_ref)
);
INSERT INTO supplier_invoices
SELECT row_number() OVER (ORDER BY gr.po_id), po.supplier_id, po.po_id,
       'SI-' || to_char(gr.received_on, 'YYYY') || '-' || lpad(po.po_id::text, 9, '0'),
       gr.received_on, gr.received_on + su.payment_terms_days, po.total_amount,
       CASE WHEN random() < 0.02 THEN 'disputed' ELSE 'open' END
FROM goods_receipts gr
JOIN purchase_orders po ON po.po_id = gr.po_id
JOIN suppliers su       ON su.supplier_id = po.supplier_id;

CREATE TABLE supplier_payments (
  supplier_payment_id bigint   PRIMARY KEY,
  supplier_invoice_id bigint   NOT NULL REFERENCES supplier_invoices,
  paid_on         date         NOT NULL,
  amount_usd      numeric(14,2) NOT NULL,
  method          varchar(10)  NOT NULL,
  bank_reference  varchar(30)  NOT NULL UNIQUE
);
INSERT INTO supplier_payments
SELECT p.supplier_invoice_id, p.supplier_invoice_id, p.paid_on, p.amount_usd,
       CASE WHEN p.paid_on < '2008-01-01' THEN pick('{wire,cheque}') ELSE pick('{wire,sepa,sepa,ach}') END,
       'BNK' || to_char(p.paid_on, 'YYYYMMDD') || lpad(p.supplier_invoice_id::text, 10, '0')
FROM (SELECT si.*, least(si.due_date + rint(-10, 20)::int, current_date) AS paid_on
      FROM supplier_invoices si
      WHERE si.status = 'open' AND si.due_date <= current_date + 10) p
WHERE p.paid_on >= p.invoice_date;

UPDATE supplier_invoices si SET status = 'paid'
FROM supplier_payments sp
WHERE sp.supplier_invoice_id = si.supplier_invoice_id;

CREATE TABLE inventory_movements (
  movement_id     bigint       PRIMARY KEY,
  product_id      int          NOT NULL REFERENCES products,
  warehouse_id    int          NOT NULL REFERENCES warehouses,
  receipt_id      bigint       REFERENCES goods_receipts,
  movement_type   varchar(12)  NOT NULL CHECK (movement_type IN ('receipt','issue','transfer_in','transfer_out','adjustment','return')),
  quantity        int          NOT NULL,
  unit_cost_usd   numeric(12,2) NOT NULL,
  moved_at        timestamp    NOT NULL
);
INSERT INTO inventory_movements
SELECT m.g, m.product_id, m.warehouse_id,
       CASE WHEN m.mtype = 'receipt' THEN m.receipt_id END,
       m.mtype,
       CASE WHEN m.mtype IN ('issue', 'transfer_out') THEN -rint(1, 200)
            WHEN m.mtype = 'adjustment' THEN rint(-20, 20) ELSE rint(1, 400) END,
       m.unit_cost, m.moved_at
FROM (
  SELECT x.g, pr.product_id, wh.warehouse_id, x.receipt_id, x.mtype, pr.standard_cost_usd AS unit_cost,
         rts(greatest(pr.introduced_on, wh.opened_on), coalesce(pr.discontinued_on, current_date) + interval '86399 seconds') AS moved_at
  FROM (SELECT g, rint(1, rows_for(4000)) AS pid, rint(1, 30) AS wid,
               rint(1, (SELECT max(receipt_id) FROM goods_receipts)) AS receipt_id,
               pick('{receipt,receipt,issue,issue,issue,transfer_in,transfer_out,adjustment,return}') AS mtype
        FROM generate_series(1, rows_for(500000)) g) x
  JOIN products pr   ON pr.product_id = x.pid
  JOIN warehouses wh ON wh.warehouse_id = x.wid
) m;

-- =====================================================================================
--  Indexes on foreign keys and dates, cleanup, statistics
-- =====================================================================================
CREATE INDEX ON cities (country_id);
CREATE INDEX ON employees (manager_id);
CREATE INDEX ON cell_towers (city_id);
CREATE INDEX ON cell_towers (carrier_id);
CREATE INDEX ON number_ranges (carrier_id);
CREATE INDEX ON phone_numbers (range_id);
CREATE INDEX ON customers (country_id);
CREATE INDEX ON customers (created_on);
CREATE INDEX ON customer_addresses (customer_id);
CREATE INDEX ON subscriptions (customer_id);
CREATE INDEX ON subscriptions (phone_number_id);
CREATE INDEX ON subscriptions (plan_id);
CREATE INDEX ON subscriptions (start_date);
CREATE INDEX ON sim_cards (subscription_id);
CREATE INDEX ON devices (customer_id);
CREATE INDEX ON devices (model_id);
CREATE INDEX ON call_records (subscription_id);
CREATE INDEX ON call_records (started_at);
CREATE INDEX ON call_records (tower_id);
CREATE INDEX ON sms_records (subscription_id);
CREATE INDEX ON sms_records (sent_at);
CREATE INDEX ON data_sessions (subscription_id);
CREATE INDEX ON data_sessions (started_at);
CREATE INDEX ON data_sessions (tower_id);
CREATE INDEX ON invoices (billing_period);
CREATE INDEX ON payments (invoice_id);
CREATE INDEX ON payments (paid_on);
CREATE INDEX ON support_tickets (customer_id);
CREATE INDEX ON support_tickets (assigned_employee_id);
CREATE INDEX ON support_tickets (opened_at);
CREATE INDEX ON ticket_events (employee_id);
CREATE INDEX ON port_requests (phone_number_id);
CREATE INDEX ON roaming_events (subscription_id);
CREATE INDEX ON roaming_events (partner_id);
CREATE INDEX ON roaming_events (event_date);
CREATE INDEX ON suppliers (country_id);
CREATE INDEX ON supplier_contacts (supplier_id);
CREATE INDEX ON supplier_contracts (supplier_id);
CREATE INDEX ON products (category_id);
CREATE INDEX ON supplier_products (product_id);
CREATE INDEX ON purchase_orders (supplier_id);
CREATE INDEX ON purchase_orders (order_date);
CREATE INDEX ON purchase_order_lines (product_id);
CREATE INDEX ON goods_receipts (po_id);
CREATE INDEX ON supplier_invoices (po_id);
CREATE INDEX ON supplier_payments (supplier_invoice_id);
CREATE INDEX ON inventory_movements (product_id);
CREATE INDEX ON inventory_movements (warehouse_id);
CREATE INDEX ON inventory_movements (moved_at);

DROP SCHEMA telecom_gen CASCADE;

COMMIT;

ANALYZE;

-- Row counts and date coverage per table
SELECT table_name,
       (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM telecom.%I', table_name), false, true, '')))[1]::text::bigint AS row_count
FROM information_schema.tables
WHERE table_schema = 'telecom' AND table_type = 'BASE TABLE'
ORDER BY table_name;
