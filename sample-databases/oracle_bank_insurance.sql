-- =====================================================================================
--  BANKING & INSURANCE (bancassurance group)  -  Oracle 19c / 21c / 23ai  -  40 tables
--  Topic : retail & business banking (branches, customers, KYC, IBAN accounts, ledger
--          transactions, transfers, cards, merchants, ATMs, fraud, loans & schedules)
--          + insurance (products, agents, policies, coverages, beneficiaries, vehicles,
--          properties, premiums, claims, claim payments, reinsurance, audit trail).
--  Data  : random but reproducible (DBMS_RANDOM seed), every business date between
--          1999-01-01 and SYSDATE, child dates never precede parent dates.
--          Natural keys (IBANs with valid mod-97 check digits, card tokens, tax ids,
--          e-mails, loan/policy/claim numbers, VINs, plates ...) are unique and enforced.
--  Size  : scale 1 is about 15 million rows (~2 GB, ~15 min). Change c_scale in gen_rows_for
--          right below: 0.01 = quick smoke test, 1 = default, 3 = about 36 million rows.
--  Run   : sqlplus bank/<password>@//localhost:1521/FREEPDB1 @oracle_bank_insurance.sql
--          (SQLcl and SQL Developer "Run Script" work too). Run it in a dedicated schema:
--          it drops and recreates the 40 tables below. Needs roughly 3 GB of tablespace.
-- =====================================================================================

WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET DEFINE OFF
SET FEEDBACK OFF
SET TIMING OFF
SET LINESIZE 200
SET PAGESIZE 100
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD';
ALTER SESSION SET NLS_NUMERIC_CHARACTERS = '.,';

PROMPT === Dropping previous objects ===
BEGIN
  FOR t IN (SELECT table_name FROM user_tables
            WHERE table_name IN ('CURRENCIES','COUNTRIES','FX_RATES','BRANCHES','EMPLOYEES','CUSTOMERS',
                                 'CUSTOMER_ADDRESSES','KYC_DOCUMENTS','CREDIT_SCORES','ACCOUNT_PRODUCTS','ACCOUNTS',
                                 'ACCOUNT_HOLDERS','ACCOUNT_TRANSACTIONS','TRANSFERS','STANDING_ORDERS','CARDS',
                                 'MERCHANTS','CARD_TRANSACTIONS','ATMS','ATM_WITHDRAWALS','FRAUD_ALERTS',
                                 'LOAN_PRODUCTS','LOANS','LOAN_SCHEDULES','LOAN_PAYMENTS','COLLATERALS',
                                 'INSURANCE_PRODUCTS','AGENTS','POLICIES','POLICY_COVERAGES','BENEFICIARIES',
                                 'INSURED_VEHICLES','INSURED_PROPERTIES','PREMIUM_PAYMENTS','CLAIMS',
                                 'CLAIM_DOCUMENTS','CLAIM_PAYMENTS','REINSURERS','REINSURANCE_TREATIES','AUDIT_LOG')
               OR table_name LIKE 'GEN\_%' ESCAPE '\') LOOP
    EXECUTE IMMEDIATE 'DROP TABLE "' || t.table_name || '" CASCADE CONSTRAINTS PURGE';
  END LOOP;
  FOR o IN (SELECT object_name, object_type FROM user_objects
            WHERE object_name LIKE 'GEN\_%' ESCAPE '\' AND object_type IN ('FUNCTION','TYPE')
            ORDER BY CASE object_type WHEN 'FUNCTION' THEN 1 ELSE 2 END) LOOP
    EXECUTE IMMEDIATE 'DROP ' || o.object_type || ' "' || o.object_name || '"' ||
                      CASE o.object_type WHEN 'TYPE' THEN ' FORCE' END;
  END LOOP;
END;
/

-- -------------------------------------------------------------------------------------
-- Generator helpers (all named GEN_*, dropped at the end)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION gen_rows_for(p_base NUMBER) RETURN NUMBER DETERMINISTIC IS
  c_scale CONSTANT NUMBER := 1;          -- <<< SIZE KNOB: 0.01 smoke test, 1 default, 3 big
BEGIN
  RETURN GREATEST(1, ROUND(p_base * c_scale));
END;
/
CREATE OR REPLACE TYPE gen_num_tab AS TABLE OF NUMBER;
/
CREATE OR REPLACE FUNCTION gen_series(p_n NUMBER) RETURN gen_num_tab PIPELINED IS
BEGIN
  FOR i IN 1 .. p_n LOOP
    PIPE ROW (i);
  END LOOP;
  RETURN;
END;
/
CREATE OR REPLACE FUNCTION gen_rint(p_lo NUMBER, p_hi NUMBER) RETURN NUMBER IS
  PRAGMA UDF;
BEGIN
  RETURN p_lo + TRUNC(DBMS_RANDOM.VALUE * (p_hi - p_lo + 1));
END;
/
CREATE OR REPLACE FUNCTION gen_rdate(p_lo DATE, p_hi DATE) RETURN DATE IS
  PRAGMA UDF;
BEGIN
  RETURN TRUNC(p_lo) + TRUNC(DBMS_RANDOM.VALUE * (GREATEST(TRUNC(p_hi) - TRUNC(p_lo), 0) + 1));
END;
/
CREATE OR REPLACE FUNCTION gen_rts(p_lo DATE, p_hi DATE) RETURN DATE IS
  PRAGMA UDF;
BEGIN
  RETURN p_lo + DBMS_RANDOM.VALUE * GREATEST(p_hi - p_lo, 0);
END;
/
-- Dates skewed toward recent years: the customer base grows over time.
CREATE OR REPLACE FUNCTION gen_grow_date(p_lo DATE, p_hi DATE) RETURN DATE IS
  PRAGMA UDF;
BEGIN
  RETURN p_lo + TRUNC(POWER(DBMS_RANDOM.VALUE, 0.75) * (GREATEST(p_hi - p_lo, 0) + 1));
END;
/
CREATE OR REPLACE FUNCTION gen_pick(p_list VARCHAR2) RETURN VARCHAR2 IS
  PRAGMA UDF;
BEGIN
  RETURN REGEXP_SUBSTR(p_list, '[^,]+', 1, 1 + TRUNC(DBMS_RANDOM.VALUE * (REGEXP_COUNT(p_list, ',') + 1)));
END;
/
-- Maps 0..m-1 one-to-one onto pseudo-random values in [0, m) for m = 10^n or 16^n:
-- the multiplier ends in 3, so it is odd, not a multiple of 5 and coprime to m.
CREATE OR REPLACE FUNCTION gen_scramble(p_k NUMBER, p_m NUMBER) RETURN NUMBER DETERMINISTIC IS
  PRAGMA UDF;
BEGIN
  RETURN MOD(p_k * (TRUNC(p_m * 0.0618033988749) * 10 + 3), p_m);
END;
/
-- IBAN with ISO 13616 mod-97 check digits (numeric BBAN).
CREATE OR REPLACE FUNCTION gen_iban(p_iso VARCHAR2, p_bban VARCHAR2) RETURN VARCHAR2 DETERMINISTIC IS
  PRAGMA UDF;
BEGIN
  RETURN p_iso || LPAD(98 - MOD(TO_NUMBER(p_bban || (ASCII(SUBSTR(p_iso, 1, 1)) - 55)
                                                  || (ASCII(SUBSTR(p_iso, 2, 1)) - 55) || '00'), 97), 2, '0') || p_bban;
END;
/
CREATE OR REPLACE FUNCTION gen_first_name RETURN VARCHAR2 IS
BEGIN
  RETURN gen_pick('James,Mary,John,Patricia,Robert,Jennifer,Michael,Linda,David,Elizabeth,Yassine,Amira,Mohamed,Fatma,Ahmed,Leila,Karim,Sofia,Lucas,Emma,Louis,Chloe,Hugo,Ines,Mateo,Lucia,Luca,Giulia,Lukas,Hannah,Jan,Anna,Sven,Ingrid,Hiroshi,Yuki,Wei,Mei,Arjun,Priya,Chinedu,Amara,Joao,Ana,Diego,Valentina,Liam,Olivia,Omar,Nour,Sami,Rania,Ivan,Olga,Kenji,Aiko,Pablo,Carmen,Noah,Ava');
END;
/
CREATE OR REPLACE FUNCTION gen_last_name RETURN VARCHAR2 IS
BEGIN
  RETURN gen_pick('Smith,Johnson,Williams,Brown,Jones,Garcia,Miller,Davis,Martin,Bernard,Dubois,Moreau,Laurent,Muller,Schmidt,Schneider,Fischer,Weber,Rossi,Russo,Ferrari,Esposito,Fernandez,Lopez,Martinez,Gonzalez,Silva,Santos,Costa,Pereira,Jansen,DeVries,Peeters,Nielsen,Hansen,Johansson,Nowak,Kowalski,Ben Ali,Trabelsi,Gharbi,Haddad,Mansour,Khalil,Okafor,Mensah,Kamau,Patel,Sharma,Singh,Tanaka,Suzuki,Sato,Wang,Li,Zhang,Chen,Kim,Murphy,Kelly');
END;
/
BEGIN
  DBMS_RANDOM.SEED(1999);
END;
/

-- =====================================================================================
--  1-3  REFERENCE DATA
-- =====================================================================================
PROMPT === Reference data ===
CREATE TABLE currencies (
  currency_code   CHAR(3)       CONSTRAINT pk_currencies PRIMARY KEY,
  name            VARCHAR2(40)  NOT NULL CONSTRAINT uq_currencies_name UNIQUE,
  minor_units     NUMBER(1)     NOT NULL
);
INSERT INTO currencies
SELECT 'EUR','Euro',2 FROM dual UNION ALL SELECT 'USD','US Dollar',2 FROM dual UNION ALL
SELECT 'GBP','Pound Sterling',2 FROM dual UNION ALL SELECT 'CHF','Swiss Franc',2 FROM dual UNION ALL
SELECT 'PLN','Polish Zloty',2 FROM dual UNION ALL SELECT 'SEK','Swedish Krona',2 FROM dual UNION ALL
SELECT 'DKK','Danish Krone',2 FROM dual UNION ALL SELECT 'NOK','Norwegian Krone',2 FROM dual UNION ALL
SELECT 'TND','Tunisian Dinar',3 FROM dual UNION ALL SELECT 'MAD','Moroccan Dirham',2 FROM dual UNION ALL
SELECT 'AED','UAE Dirham',2 FROM dual UNION ALL SELECT 'SAR','Saudi Riyal',2 FROM dual UNION ALL
SELECT 'EGP','Egyptian Pound',2 FROM dual UNION ALL SELECT 'ZAR','South African Rand',2 FROM dual UNION ALL
SELECT 'NGN','Nigerian Naira',2 FROM dual UNION ALL SELECT 'KES','Kenyan Shilling',2 FROM dual UNION ALL
SELECT 'INR','Indian Rupee',2 FROM dual UNION ALL SELECT 'JPY','Japanese Yen',0 FROM dual UNION ALL
SELECT 'CNY','Chinese Yuan',2 FROM dual UNION ALL SELECT 'BRL','Brazilian Real',2 FROM dual UNION ALL
SELECT 'MXN','Mexican Peso',2 FROM dual UNION ALL SELECT 'AUD','Australian Dollar',2 FROM dual;

-- Countries 1-14 are the group's banking markets (all have numeric-BBAN IBANs).
CREATE TABLE countries (
  country_id      NUMBER(3)     CONSTRAINT pk_countries PRIMARY KEY,
  iso_code        CHAR(2)       NOT NULL CONSTRAINT uq_countries_iso UNIQUE,
  name            VARCHAR2(60)  NOT NULL CONSTRAINT uq_countries_name UNIQUE,
  region          VARCHAR2(20)  NOT NULL,
  currency_code   CHAR(3)       NOT NULL,
  iban_length     NUMBER(2),
  is_bank_market  CHAR(1)       NOT NULL CONSTRAINT ck_countries_market CHECK (is_bank_market IN ('Y','N'))
);
INSERT INTO countries
SELECT 1,'DE','Germany','Europe','EUR',22,'Y' FROM dual UNION ALL SELECT 2,'FR','France','Europe','EUR',27,'Y' FROM dual UNION ALL
SELECT 3,'ES','Spain','Europe','EUR',24,'Y' FROM dual UNION ALL SELECT 4,'BE','Belgium','Europe','EUR',16,'Y' FROM dual UNION ALL
SELECT 5,'PT','Portugal','Europe','EUR',25,'Y' FROM dual UNION ALL SELECT 6,'AT','Austria','Europe','EUR',20,'Y' FROM dual UNION ALL
SELECT 7,'CH','Switzerland','Europe','CHF',21,'Y' FROM dual UNION ALL SELECT 8,'PL','Poland','Europe','PLN',28,'Y' FROM dual UNION ALL
SELECT 9,'TN','Tunisia','Africa','TND',24,'Y' FROM dual UNION ALL SELECT 10,'MA','Morocco','Africa','MAD',28,'Y' FROM dual UNION ALL
SELECT 11,'SE','Sweden','Europe','SEK',24,'Y' FROM dual UNION ALL SELECT 12,'DK','Denmark','Europe','DKK',18,'Y' FROM dual UNION ALL
SELECT 13,'AE','United Arab Emirates','Middle East','AED',23,'Y' FROM dual UNION ALL SELECT 14,'SA','Saudi Arabia','Middle East','SAR',24,'Y' FROM dual UNION ALL
SELECT 15,'US','United States','North America','USD',NULL,'N' FROM dual UNION ALL SELECT 16,'GB','United Kingdom','Europe','GBP',22,'N' FROM dual UNION ALL
SELECT 17,'IT','Italy','Europe','EUR',27,'N' FROM dual UNION ALL SELECT 18,'NL','Netherlands','Europe','EUR',18,'N' FROM dual UNION ALL
SELECT 19,'IE','Ireland','Europe','EUR',22,'N' FROM dual UNION ALL SELECT 20,'NO','Norway','Europe','NOK',15,'N' FROM dual UNION ALL
SELECT 21,'EG','Egypt','Africa','EGP',29,'N' FROM dual UNION ALL SELECT 22,'ZA','South Africa','Africa','ZAR',NULL,'N' FROM dual UNION ALL
SELECT 23,'NG','Nigeria','Africa','NGN',NULL,'N' FROM dual UNION ALL SELECT 24,'KE','Kenya','Africa','KES',NULL,'N' FROM dual UNION ALL
SELECT 25,'IN','India','Asia','INR',NULL,'N' FROM dual UNION ALL SELECT 26,'JP','Japan','Asia','JPY',NULL,'N' FROM dual UNION ALL
SELECT 27,'CN','China','Asia','CNY',NULL,'N' FROM dual UNION ALL SELECT 28,'BR','Brazil','South America','BRL',29,'N' FROM dual UNION ALL
SELECT 29,'MX','Mexico','North America','MXN',NULL,'N' FROM dual UNION ALL SELECT 30,'AU','Australia','Oceania','AUD',NULL,'N' FROM dual;
COMMIT;

CREATE TABLE gen_cities AS
SELECT c.country_id, s.COLUMN_VALUE AS n, CAST(REGEXP_SUBSTR(v.names, '[^|]+', 1, s.COLUMN_VALUE) AS VARCHAR2(40)) AS city
FROM (SELECT 'DE' iso, 'Berlin|Hamburg|Munich|Cologne|Frankfurt' names FROM dual UNION ALL
      SELECT 'FR', 'Paris|Lyon|Marseille|Toulouse|Lille' FROM dual UNION ALL
      SELECT 'ES', 'Madrid|Barcelona|Valencia|Seville|Bilbao' FROM dual UNION ALL
      SELECT 'BE', 'Brussels|Antwerp|Ghent|Liege|Bruges' FROM dual UNION ALL
      SELECT 'PT', 'Lisbon|Porto|Braga|Coimbra|Faro' FROM dual UNION ALL
      SELECT 'AT', 'Vienna|Graz|Linz|Salzburg|Innsbruck' FROM dual UNION ALL
      SELECT 'CH', 'Zurich|Geneva|Basel|Bern|Lausanne' FROM dual UNION ALL
      SELECT 'PL', 'Warsaw|Krakow|Lodz|Wroclaw|Gdansk' FROM dual UNION ALL
      SELECT 'TN', 'Tunis|Sfax|Sousse|Kairouan|Bizerte' FROM dual UNION ALL
      SELECT 'MA', 'Casablanca|Rabat|Marrakesh|Fes|Tangier' FROM dual UNION ALL
      SELECT 'SE', 'Stockholm|Gothenburg|Malmo|Uppsala|Linkoping' FROM dual UNION ALL
      SELECT 'DK', 'Copenhagen|Aarhus|Odense|Aalborg|Esbjerg' FROM dual UNION ALL
      SELECT 'AE', 'Dubai|Abu Dhabi|Sharjah|Ajman|Al Ain' FROM dual UNION ALL
      SELECT 'SA', 'Riyadh|Jeddah|Mecca|Medina|Dammam' FROM dual UNION ALL
      SELECT 'US', 'New York|Los Angeles|Chicago|Houston|Miami' FROM dual UNION ALL
      SELECT 'GB', 'London|Manchester|Birmingham|Glasgow|Leeds' FROM dual UNION ALL
      SELECT 'IT', 'Rome|Milan|Naples|Turin|Bologna' FROM dual UNION ALL
      SELECT 'NL', 'Amsterdam|Rotterdam|The Hague|Utrecht|Eindhoven' FROM dual UNION ALL
      SELECT 'IE', 'Dublin|Cork|Limerick|Galway|Waterford' FROM dual UNION ALL
      SELECT 'NO', 'Oslo|Bergen|Trondheim|Stavanger|Tromso' FROM dual UNION ALL
      SELECT 'EG', 'Cairo|Alexandria|Giza|Luxor|Port Said' FROM dual UNION ALL
      SELECT 'ZA', 'Johannesburg|Cape Town|Durban|Pretoria|Gqeberha' FROM dual UNION ALL
      SELECT 'NG', 'Lagos|Abuja|Kano|Ibadan|Port Harcourt' FROM dual UNION ALL
      SELECT 'KE', 'Nairobi|Mombasa|Kisumu|Nakuru|Eldoret' FROM dual UNION ALL
      SELECT 'IN', 'Mumbai|Delhi|Bangalore|Chennai|Kolkata' FROM dual UNION ALL
      SELECT 'JP', 'Tokyo|Osaka|Yokohama|Nagoya|Sapporo' FROM dual UNION ALL
      SELECT 'CN', 'Shanghai|Beijing|Shenzhen|Guangzhou|Chengdu' FROM dual UNION ALL
      SELECT 'BR', 'Sao Paulo|Rio de Janeiro|Brasilia|Salvador|Fortaleza' FROM dual UNION ALL
      SELECT 'MX', 'Mexico City|Guadalajara|Monterrey|Puebla|Tijuana' FROM dual UNION ALL
      SELECT 'AU', 'Sydney|Melbourne|Brisbane|Perth|Adelaide' FROM dual) v
JOIN countries c ON c.iso_code = v.iso
CROSS JOIN TABLE(gen_series(5)) s;
ALTER TABLE gen_cities ADD CONSTRAINT pk_gen_cities PRIMARY KEY (country_id, n);

-- Daily (business days) FX history 1999 -> today, quoted as units per 1 EUR. Built from a
-- random walk per USD that drifts toward a realistic present-day level.
CREATE TABLE fx_rates (
  currency_code   CHAR(3)       NOT NULL,
  rate_date       DATE          NOT NULL,
  units_per_eur   NUMBER(18,6)  NOT NULL CONSTRAINT ck_fx_positive CHECK (units_per_eur > 0),
  CONSTRAINT pk_fx_rates PRIMARY KEY (currency_code, rate_date)
);
CREATE TABLE gen_fx_usd AS
SELECT code, d, r1999 * EXP(SUM(step) OVER (PARTITION BY code ORDER BY d)) AS per_usd
FROM (SELECT /*+ NO_MERGE */ c.code, c.r1999, d.d,
             LN(c.r_now / c.r1999) / ((TRUNC(SYSDATE) - DATE '1999-01-01') * 5 / 7)
               + (DBMS_RANDOM.VALUE - 0.5) * c.vol * 0.5 AS step
      FROM (SELECT 'USD' code, 1 r1999, 1 r_now, 0 vol FROM dual UNION ALL
            SELECT 'EUR', 0.86, 0.92, 0.012 FROM dual UNION ALL SELECT 'GBP', 0.61, 0.79, 0.012 FROM dual UNION ALL
            SELECT 'CHF', 1.38, 0.88, 0.012 FROM dual UNION ALL SELECT 'PLN', 3.9, 4.0, 0.016 FROM dual UNION ALL
            SELECT 'SEK', 8.1, 10.5, 0.014 FROM dual UNION ALL SELECT 'DKK', 6.4, 6.9, 0.012 FROM dual UNION ALL
            SELECT 'NOK', 7.6, 10.6, 0.014 FROM dual UNION ALL SELECT 'TND', 1.18, 3.1, 0.008 FROM dual UNION ALL
            SELECT 'MAD', 9.3, 10.0, 0.008 FROM dual UNION ALL SELECT 'AED', 3.6725, 3.6725, 0 FROM dual UNION ALL
            SELECT 'SAR', 3.75, 3.75, 0 FROM dual UNION ALL SELECT 'EGP', 3.4, 48.0, 0.010 FROM dual UNION ALL
            SELECT 'ZAR', 6.1, 18.2, 0.020 FROM dual UNION ALL SELECT 'NGN', 22.0, 1500.0, 0.012 FROM dual UNION ALL
            SELECT 'KES', 61.0, 129.0, 0.010 FROM dual UNION ALL SELECT 'INR', 42.5, 84.0, 0.008 FROM dual UNION ALL
            SELECT 'JPY', 113.0, 150.0, 0.012 FROM dual UNION ALL SELECT 'CNY', 8.28, 7.15, 0.004 FROM dual UNION ALL
            SELECT 'BRL', 1.2, 5.4, 0.020 FROM dual UNION ALL SELECT 'MXN', 9.5, 18.5, 0.016 FROM dual UNION ALL
            SELECT 'AUD', 1.55, 1.52, 0.014 FROM dual) c
      CROSS JOIN (SELECT DATE '1999-01-01' + s.COLUMN_VALUE - 1 AS d
                  FROM TABLE(gen_series(TRUNC(SYSDATE) - DATE '1999-01-01' + 1)) s
                  WHERE TO_CHAR(DATE '1999-01-01' + s.COLUMN_VALUE - 1, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') NOT IN ('SAT','SUN')) d);
INSERT /*+ APPEND */ INTO fx_rates (currency_code, rate_date, units_per_eur)
SELECT c.code, c.d, ROUND(c.per_usd / e.per_usd, 6)
FROM gen_fx_usd c JOIN gen_fx_usd e ON e.d = c.d AND e.code = 'EUR'
WHERE c.code <> 'EUR';
COMMIT;

-- Yearly average FX used to price local-currency amounts (helper).
CREATE TABLE gen_fx_year AS
SELECT currency_code, EXTRACT(YEAR FROM rate_date) AS yr, AVG(units_per_eur) AS rate
FROM fx_rates GROUP BY currency_code, EXTRACT(YEAR FROM rate_date)
UNION ALL
SELECT 'EUR', 1998 + s.COLUMN_VALUE, 1 FROM TABLE(gen_series(EXTRACT(YEAR FROM SYSDATE) - 1998)) s;
ALTER TABLE gen_fx_year ADD CONSTRAINT pk_gen_fx_year PRIMARY KEY (currency_code, yr);

-- =====================================================================================
--  4-5  BRANCHES & EMPLOYEES
-- =====================================================================================
PROMPT === Branches and employees ===
CREATE TABLE branches (
  branch_id       NUMBER(5)     CONSTRAINT pk_branches PRIMARY KEY,   -- country = 1 + MOD(id - 1, 14)
  branch_code     VARCHAR2(5)   NOT NULL CONSTRAINT uq_branches_code UNIQUE,
  name            VARCHAR2(80)  NOT NULL,
  country_id      NUMBER(3)     NOT NULL,
  city            VARCHAR2(40)  NOT NULL,
  branch_type     VARCHAR2(12)  NOT NULL CONSTRAINT ck_branches_type CHECK (branch_type IN ('flagship','retail','business','private')),
  opened_on       DATE          NOT NULL
);
INSERT /*+ APPEND */ INTO branches (branch_id, branch_code, name, country_id, city, branch_type, opened_on)
SELECT b.g, TO_CHAR(10000 + b.g), gc.city || ' ' || b.district, gc.country_id, gc.city,
       CASE WHEN b.g <= 14 THEN 'flagship' ELSE gen_pick('retail,retail,retail,business,private') END,
       CASE WHEN b.g <= 140 THEN DATE '1999-01-01' ELSE gen_rdate(DATE '1999-01-01', DATE '2016-12-31') END
FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g,
             gen_pick('Central,Old Town,Harbour,University,Airport,Business Park,Riverside,North,South,East,West,Station,Market') AS district
      FROM TABLE(gen_series(280)) s) b                                -- fixed size: 20 per market
JOIN gen_cities gc ON gc.country_id = 1 + MOD(b.g - 1, 14) AND gc.n = 1 + MOD(TRUNC((b.g - 1) / 14), 5);
COMMIT;

CREATE TABLE employees (
  employee_id     NUMBER(7)     CONSTRAINT pk_employees PRIMARY KEY,  -- 1..280 = branch managers
  first_name      VARCHAR2(40)  NOT NULL,
  last_name       VARCHAR2(40)  NOT NULL,
  email           VARCHAR2(120) NOT NULL CONSTRAINT uq_employees_email UNIQUE,
  branch_id       NUMBER(5)     NOT NULL,
  department      VARCHAR2(30)  NOT NULL,
  job_title       VARCHAR2(40)  NOT NULL,
  manager_id      NUMBER(7),
  hired_on        DATE          NOT NULL,
  terminated_on   DATE,
  salary_eur      NUMBER(10,2)  NOT NULL,
  CONSTRAINT ck_employees_dates CHECK (terminated_on IS NULL OR terminated_on >= hired_on)
);
INSERT /*+ APPEND */ INTO employees
  (employee_id, first_name, last_name, email, branch_id, department, job_title, manager_id, hired_on, terminated_on, salary_eur)
SELECT e.g, e.fn, e.ln, LOWER(REPLACE(e.fn || '.' || e.ln, ' ', '')) || '.' || e.g || '@bank.example.com',
       e.branch_id, CASE WHEN e.g <= 280 THEN 'Branch Management' ELSE e.dept END,
       CASE WHEN e.g <= 280 THEN 'Branch Manager' ELSE gen_pick('Advisor,Teller,Analyst,Officer,Specialist,Underwriter,Adjuster,Engineer') END,
       CASE WHEN e.g > 280 THEN e.branch_id END,
       e.hired_on,
       CASE WHEN e.r_leave < 0.2 THEN gen_rdate(e.hired_on, TRUNC(SYSDATE)) END,
       ROUND(CASE WHEN e.g <= 280 THEN 85000 ELSE 42000 END * (0.8 + DBMS_RANDOM.VALUE * 0.6), 2)
FROM (SELECT /*+ NO_MERGE */ x.g, x.fn, x.ln, x.dept, x.r_leave, x.branch_id,
             CASE WHEN x.g <= 280 THEN b.opened_on + gen_rint(0, 60)
                  ELSE GREATEST(b.opened_on, gen_grow_date(DATE '1999-01-01', TRUNC(SYSDATE) - 30)) END AS hired_on
      FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g, 1 + MOD(s.COLUMN_VALUE - 1, 280) AS branch_id,
                   gen_first_name() AS fn, gen_last_name() AS ln, DBMS_RANDOM.VALUE AS r_leave,
                   gen_pick('Retail Banking,Retail Banking,Lending,Insurance,Claims,Compliance,Operations,IT,Risk,Treasury') AS dept
            FROM TABLE(gen_series(GREATEST(300, gen_rows_for(3000)))) s) x
      JOIN branches b ON b.branch_id = x.branch_id) e;
COMMIT;

-- =====================================================================================
--  6-9  CUSTOMERS, ADDRESSES, KYC, CREDIT SCORES
-- =====================================================================================
PROMPT === Customers ===
CREATE TABLE customers (
  customer_id     NUMBER(10)    CONSTRAINT pk_customers PRIMARY KEY,  -- country = 1 + MOD(id - 1, 14)
  customer_type   VARCHAR2(10)  NOT NULL CONSTRAINT ck_customers_type CHECK (customer_type IN ('individual','corporate')),
  first_name      VARCHAR2(40)  NOT NULL,
  last_name       VARCHAR2(40)  NOT NULL,
  company_name    VARCHAR2(100),
  email           VARCHAR2(120) NOT NULL CONSTRAINT uq_customers_email UNIQUE,
  tax_id          VARCHAR2(20)  NOT NULL CONSTRAINT uq_customers_tax UNIQUE,
  birth_date      DATE,
  country_id      NUMBER(3)     NOT NULL,
  home_branch_id  NUMBER(5)     NOT NULL,
  segment         VARCHAR2(12)  NOT NULL,
  risk_rating     VARCHAR2(6)   NOT NULL CONSTRAINT ck_customers_risk CHECK (risk_rating IN ('low','medium','high')),
  customer_since  DATE          NOT NULL,
  closed_on       DATE,
  CONSTRAINT ck_customers_dates CHECK (closed_on IS NULL OR closed_on >= customer_since)
);
INSERT /*+ APPEND */ INTO customers
  (customer_id, customer_type, first_name, last_name, company_name, email, tax_id, birth_date,
   country_id, home_branch_id, segment, risk_rating, customer_since, closed_on)
SELECT /*+ ORDERED */ t.g, t.ctype, t.fn, t.ln,
       CASE WHEN t.ctype = 'corporate' THEN t.ln || ' ' || gen_pick('Holding,Trading,Industries,Consulting,Logistics,Foods,Partners,Systems,Pharma,Motors')
                                          || ' ' || gen_pick('SA,GmbH,SARL,AG,SL,AB,LLC,SpA') END,
       LOWER(REPLACE(t.fn || '.' || t.ln, ' ', '')) || '.' || t.g || '@' || gen_pick('example.com,example.net,example.org,mail.test'),
       c.iso_code || LPAD(gen_scramble(t.g, 1000000000), 9, '0'),
       CASE WHEN t.ctype = 'individual' THEN t.since - gen_rint(18 * 366, 80 * 365) END,
       c.country_id, b.branch_id,
       CASE WHEN t.ctype = 'individual' THEN gen_pick('mass,mass,mass,affluent,affluent,private')
            ELSE gen_pick('sme,sme,sme,corporate') END,
       gen_pick('low,low,low,medium,medium,high'),
       GREATEST(t.since, b.opened_on),
       CASE WHEN t.churn < 0.10 THEN gen_rdate(GREATEST(t.since, b.opened_on), TRUNC(SYSDATE)) END
FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g,
             CASE WHEN DBMS_RANDOM.VALUE < 0.88 THEN 'individual' ELSE 'corporate' END AS ctype,
             gen_first_name() AS fn, gen_last_name() AS ln,
             gen_grow_date(DATE '1999-01-01', TRUNC(SYSDATE)) AS since,
             (1 + MOD(s.COLUMN_VALUE - 1, 14)) + 14 * gen_rint(0, TRUNC((279 - MOD(s.COLUMN_VALUE - 1, 14)) / 14)) AS branch_id,
             DBMS_RANDOM.VALUE AS churn
      FROM TABLE(gen_series(gen_rows_for(150000))) s) t
JOIN countries c ON c.country_id = 1 + MOD(t.g - 1, 14)
JOIN branches b  ON b.branch_id = t.branch_id;
COMMIT;

CREATE TABLE customer_addresses (
  address_id      NUMBER(10)    CONSTRAINT pk_customer_addresses PRIMARY KEY,
  customer_id     NUMBER(10)    NOT NULL,
  address_type    VARCHAR2(10)  NOT NULL CONSTRAINT ck_addr_type CHECK (address_type IN ('residence','mailing','work')),
  street          VARCHAR2(120) NOT NULL,
  postal_code     VARCHAR2(10)  NOT NULL,
  city            VARCHAR2(40)  NOT NULL,
  country_id      NUMBER(3)     NOT NULL,
  valid_from      DATE          NOT NULL,
  valid_to        DATE
);
INSERT /*+ APPEND */ INTO customer_addresses
  (address_id, customer_id, address_type, street, postal_code, city, country_id, valid_from, valid_to)
SELECT /*+ ORDERED */ a.g, cu.customer_id,
       CASE a.k WHEN 0 THEN 'residence' WHEN 1 THEN 'mailing' ELSE 'work' END,
       gen_rint(1, 299) || ' ' || gen_pick('Main,Oak,Station,Harbour,Market,Garden,Park,Church,Mill,Lake,Olive,Palm,Cedar,Bridge')
         || ' ' || gen_pick('Street,Avenue,Road,Lane,Boulevard,Way'),
       LPAD(gen_rint(1000, 99999), 5, '0'), gc.city, cu.country_id,
       CASE WHEN a.k = 0 THEN cu.customer_since ELSE gen_rdate(cu.customer_since, NVL(cu.closed_on, TRUNC(SYSDATE))) END,
       cu.closed_on
FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g,
             1 + MOD(s.COLUMN_VALUE - 1, gen_rows_for(150000)) AS cid,
             TRUNC((s.COLUMN_VALUE - 1) / gen_rows_for(150000)) AS k, gen_rint(1, 5) AS city_n
      FROM TABLE(gen_series(gen_rows_for(190000))) s) a
JOIN customers cu  ON cu.customer_id = a.cid
JOIN gen_cities gc ON gc.country_id = cu.country_id AND gc.n = a.city_n;
COMMIT;

CREATE TABLE kyc_documents (
  document_id     NUMBER(10)    CONSTRAINT pk_kyc_documents PRIMARY KEY,
  customer_id     NUMBER(10)    NOT NULL,
  document_type   VARCHAR2(22)  NOT NULL,
  document_number VARCHAR2(20)  NOT NULL CONSTRAINT uq_kyc_number UNIQUE,
  issued_on       DATE          NOT NULL,
  expires_on      DATE,
  verified_by_employee_id NUMBER(7) NOT NULL,
  verified_on     DATE          NOT NULL,
  status          VARCHAR2(10)  NOT NULL CONSTRAINT ck_kyc_status CHECK (status IN ('verified','expired','rejected'))
);
INSERT /*+ APPEND */ INTO kyc_documents
  (document_id, customer_id, document_type, document_number, issued_on, expires_on, verified_by_employee_id, verified_on, status)
SELECT d.g, d.customer_id, d.doc_type,
       UPPER(SUBSTR(d.doc_type, 1, 2)) || LPAD(gen_scramble(d.g, 10000000000), 10, '0'),
       d.issued_on,
       CASE WHEN d.doc_type IN ('passport','national_id','driving_license','residence_permit') THEN ADD_MONTHS(d.issued_on, 120) END,
       gen_rint(1, GREATEST(300, gen_rows_for(3000))), d.verified_on,
       CASE WHEN d.rej < 0.02 THEN 'rejected'
            WHEN d.doc_type IN ('passport','national_id','driving_license','residence_permit')
                 AND ADD_MONTHS(d.issued_on, 120) < TRUNC(SYSDATE) THEN 'expired' ELSE 'verified' END
FROM (SELECT /*+ NO_MERGE */ x.g, cu.customer_id, x.rej,
             CASE WHEN x.k = 0 AND cu.customer_type = 'corporate' THEN 'company_registration'
                  WHEN x.k = 0 THEN gen_pick('passport,national_id,national_id')
                  ELSE gen_pick('utility_bill,passport,driving_license,proof_of_income,residence_permit') END AS doc_type,
             CASE WHEN x.k = 0 THEN gen_rdate(cu.customer_since - 3000, cu.customer_since)
                  ELSE gen_rdate(cu.customer_since, NVL(cu.closed_on, TRUNC(SYSDATE))) END AS issued_on,
             LEAST(CASE WHEN x.k = 0 THEN cu.customer_since ELSE gen_rdate(cu.customer_since, NVL(cu.closed_on, TRUNC(SYSDATE))) END
                   + gen_rint(0, 5), TRUNC(SYSDATE)) AS verified_on
      FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g,
                   1 + MOD(s.COLUMN_VALUE - 1, gen_rows_for(150000)) AS cid,
                   TRUNC((s.COLUMN_VALUE - 1) / gen_rows_for(150000)) AS k, DBMS_RANDOM.VALUE AS rej
            FROM TABLE(gen_series(gen_rows_for(250000))) s) x
      JOIN customers cu ON cu.customer_id = x.cid) d;
COMMIT;
UPDATE kyc_documents SET verified_on = issued_on WHERE verified_on < issued_on;
COMMIT;

CREATE TABLE credit_scores (
  score_id        NUMBER(10)    CONSTRAINT pk_credit_scores PRIMARY KEY,
  customer_id     NUMBER(10)    NOT NULL,
  bureau          VARCHAR2(20)  NOT NULL,
  score_date      DATE          NOT NULL,
  score           NUMBER(3)     NOT NULL CONSTRAINT ck_credit_score CHECK (score BETWEEN 300 AND 850),
  model_version   VARCHAR2(10)  NOT NULL
);
INSERT /*+ APPEND */ INTO credit_scores (score_id, customer_id, bureau, score_date, score, model_version)
SELECT c.g, c.customer_id, gen_pick('CrediCheck,ScoreLine,RiskBureau,FinScore'), c.score_date,
       LEAST(850, GREATEST(300, ROUND(640 + 90 * DBMS_RANDOM.NORMAL))),
       'v' || (1 + TRUNC((EXTRACT(YEAR FROM c.score_date) - 1999) / 5)) || '.0'
FROM (SELECT /*+ NO_MERGE ORDERED */ x.g, cu.customer_id,
             gen_rdate(cu.customer_since, NVL(cu.closed_on, TRUNC(SYSDATE))) AS score_date
      FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g, gen_rint(1, gen_rows_for(150000)) AS cid
            FROM TABLE(gen_series(gen_rows_for(400000))) s) x
      JOIN customers cu ON cu.customer_id = x.cid) c;
COMMIT;

-- =====================================================================================
--  10-15  ACCOUNTS, HOLDERS, LEDGER, TRANSFERS, STANDING ORDERS
-- =====================================================================================
PROMPT === Accounts and ledger ===
CREATE TABLE account_products (
  product_id      NUMBER(3)     CONSTRAINT pk_account_products PRIMARY KEY,
  product_code    VARCHAR2(12)  NOT NULL CONSTRAINT uq_account_products_code UNIQUE,
  name            VARCHAR2(60)  NOT NULL,
  product_type    VARCHAR2(12)  NOT NULL CONSTRAINT ck_acc_prod_type CHECK (product_type IN ('checking','savings','term_deposit','business')),
  interest_rate   NUMBER(5,3)   NOT NULL,
  monthly_fee_eur NUMBER(6,2)   NOT NULL,
  launched_on     DATE          NOT NULL,
  retired_on      DATE
);
INSERT INTO account_products (product_id, product_code, name, product_type, interest_rate, monthly_fee_eur, launched_on, retired_on)
SELECT k, UPPER(SUBSTR(t, 1, 3)) || '-' || LPAD(k, 3, '0'),
       INITCAP(REPLACE(t, '_', ' ')) || ' ' || gen_pick('Classic,Plus,Gold,Online,Flex,Premier,Easy,Smart') || ' ' || EXTRACT(YEAR FROM l),
       t,
       CASE t WHEN 'checking' THEN 0 WHEN 'savings' THEN ROUND(0.5 + DBMS_RANDOM.VALUE * 2, 3)
              WHEN 'term_deposit' THEN ROUND(1 + DBMS_RANDOM.VALUE * 3, 3) ELSE 0 END,
       CASE t WHEN 'checking' THEN gen_rint(0, 12) WHEN 'business' THEN gen_rint(10, 45) ELSE 0 END,
       l,
       CASE WHEN k <= 4 THEN DATE '2012-12-31' END
FROM (SELECT s.COLUMN_VALUE AS k,
             CASE MOD(s.COLUMN_VALUE - 1, 4) WHEN 0 THEN 'checking' WHEN 1 THEN 'savings' WHEN 2 THEN 'term_deposit' ELSE 'business' END AS t,
             DATE '1999-01-01' + (s.COLUMN_VALUE - 1) * 300 AS l
      FROM TABLE(gen_series(24)) s)   -- fixed size, one launch every ~10 months
;
COMMIT;

CREATE TABLE accounts (
  account_id      NUMBER(10)    CONSTRAINT pk_accounts PRIMARY KEY,
  iban            VARCHAR2(34)  NOT NULL CONSTRAINT uq_accounts_iban UNIQUE,
  customer_id     NUMBER(10)    NOT NULL,                             -- primary holder
  branch_id       NUMBER(5)     NOT NULL,
  product_id      NUMBER(3)     NOT NULL,
  currency_code   CHAR(3)       NOT NULL,
  opened_on       DATE          NOT NULL,
  closed_on       DATE,
  status          VARCHAR2(10)  NOT NULL CONSTRAINT ck_accounts_status CHECK (status IN ('active','dormant','frozen','closed')),
  overdraft_limit NUMBER(14,2)  NOT NULL,
  current_balance NUMBER(16,2)  DEFAULT 0 NOT NULL,
  CONSTRAINT ck_accounts_dates CHECK (closed_on IS NULL OR closed_on >= opened_on)
);
INSERT /*+ APPEND */ INTO accounts
  (account_id, iban, customer_id, branch_id, product_id, currency_code, opened_on, closed_on, status, overdraft_limit, current_balance)
SELECT /*+ ORDERED */ a.g,
       gen_iban(co.iso_code, br.branch_code || LPAD(gen_scramble(a.g, POWER(10, co.iban_length - 9)), co.iban_length - 9, '0')),
       a.customer_id, a.branch_id, ap.product_id, co.currency_code, a.opened_on, a.closed_on,
       CASE WHEN a.closed_on IS NOT NULL THEN 'closed' WHEN a.r < 0.05 THEN 'dormant' WHEN a.r < 0.06 THEN 'frozen' ELSE 'active' END,
       CASE WHEN ap.product_type IN ('checking','business') THEN ROUND(gen_rint(0, 20) * 100 * fx.rate, -1) ELSE 0 END,
       0
FROM (SELECT /*+ NO_MERGE */ b.*,
             CASE WHEN b.opened_on > DATE '2012-12-31' THEN gen_rint(5, b.kmax) ELSE gen_rint(1, b.kmax) END AS pid
      FROM (SELECT /*+ NO_MERGE */ o.*,
                   LEAST(24, TRUNC((o.opened_on - DATE '1999-01-01') / 300) + 1) AS kmax,
                   CASE WHEN o.cust_closed IS NOT NULL THEN o.cust_closed
                        WHEN o.r < 0.18 THEN gen_rdate(o.opened_on, TRUNC(SYSDATE)) END AS closed_on
            FROM (SELECT /*+ NO_MERGE ORDERED */ x.g, x.r, cu.customer_id, cu.home_branch_id AS branch_id, cu.country_id,
                         cu.closed_on AS cust_closed,
                         CASE WHEN x.g <= gen_rows_for(150000) THEN cu.customer_since
                              ELSE gen_rdate(cu.customer_since, LEAST(cu.customer_since + 1825, NVL(cu.closed_on, TRUNC(SYSDATE)))) END AS opened_on
                  FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g,
                               CASE WHEN s.COLUMN_VALUE <= gen_rows_for(150000) THEN s.COLUMN_VALUE
                                    ELSE gen_rint(1, gen_rows_for(150000)) END AS cid,   -- every customer gets one account
                               DBMS_RANDOM.VALUE AS r
                        FROM TABLE(gen_series(gen_rows_for(220000))) s) x
                  JOIN customers cu ON cu.customer_id = x.cid) o) b) a
JOIN account_products ap ON ap.product_id = a.pid
JOIN branches br         ON br.branch_id = a.branch_id
JOIN countries co        ON co.country_id = a.country_id
JOIN gen_fx_year fx      ON fx.currency_code = co.currency_code AND fx.yr = EXTRACT(YEAR FROM a.opened_on);
COMMIT;

CREATE TABLE account_holders (
  account_id      NUMBER(10)    NOT NULL,
  customer_id     NUMBER(10)    NOT NULL,
  holder_role     VARCHAR2(10)  NOT NULL CONSTRAINT ck_holder_role CHECK (holder_role IN ('primary','joint','proxy')),
  added_on        DATE          NOT NULL,
  CONSTRAINT pk_account_holders PRIMARY KEY (account_id, customer_id)
);
INSERT /*+ APPEND */ INTO account_holders (account_id, customer_id, holder_role, added_on)
SELECT account_id, customer_id, 'primary', opened_on FROM accounts;
COMMIT;
INSERT /*+ APPEND */ INTO account_holders (account_id, customer_id, holder_role, added_on)
SELECT j.account_id, j.customer_id, j.holder_role, j.added_on
FROM (SELECT /*+ NO_MERGE ORDERED */ x.account_id, cu.customer_id, x.holder_role, x.acc_customer, x.acc_end,
             GREATEST(x.opened_on, cu.customer_since) AS added_on
      FROM (SELECT /*+ NO_MERGE */ a.account_id, a.customer_id AS acc_customer, a.opened_on,
                   NVL(a.closed_on, TRUNC(SYSDATE)) AS acc_end,
                   CASE WHEN DBMS_RANDOM.VALUE < 0.85 THEN 'joint' ELSE 'proxy' END AS holder_role,
                   a.country_id + 14 * gen_rint(0, TRUNC((gen_rows_for(150000) - a.country_id) / 14)) AS other_cid
            FROM (SELECT /*+ NO_MERGE */ ac.*, 1 + MOD(ac.customer_id - 1, 14) AS country_id, DBMS_RANDOM.VALUE AS r
                  FROM accounts ac) a
            WHERE a.r < 0.16) x                                       -- same-country co-holder
      JOIN customers cu ON cu.customer_id = x.other_cid) j
WHERE j.customer_id <> j.acc_customer AND j.added_on <= j.acc_end;
COMMIT;

CREATE TABLE account_transactions (
  txn_id          NUMBER(12)    CONSTRAINT pk_account_transactions PRIMARY KEY,
  account_id      NUMBER(10)    NOT NULL,
  txn_at          DATE          NOT NULL,
  value_date      DATE          NOT NULL,
  txn_type        VARCHAR2(16)  NOT NULL,
  channel         VARCHAR2(12)  NOT NULL,
  amount          NUMBER(16,2)  NOT NULL,
  balance_after   NUMBER(16,2),
  description     VARCHAR2(100) NOT NULL
);
INSERT /*+ APPEND */ INTO account_transactions
  (txn_id, account_id, txn_at, value_date, txn_type, channel, amount, balance_after, description)
SELECT t.g, t.account_id, t.txn_at, TRUNC(t.txn_at) + CASE WHEN t.txn_type IN ('transfer_in','salary') THEN gen_rint(0, 2) ELSE 0 END,
       t.txn_type,
       CASE WHEN t.txn_type IN ('fee','interest') THEN 'system'
            WHEN t.txn_at < DATE '2003-01-01' THEN gen_pick('branch,branch,atm,phone')
            WHEN t.txn_at < DATE '2012-01-01' THEN gen_pick('branch,atm,online,online')
            ELSE gen_pick('online,mobile,mobile,mobile,atm,branch') END,
       ROUND(t.sign * t.eur * fx.rate, 2), NULL,
       CASE t.txn_type WHEN 'salary' THEN 'Salary ' || TO_CHAR(t.txn_at, 'MON YYYY', 'NLS_DATE_LANGUAGE=ENGLISH')
                       WHEN 'deposit' THEN 'Cash deposit'
                       WHEN 'card_settlement' THEN 'Card purchases settlement'
                       WHEN 'withdrawal' THEN 'Cash withdrawal'
                       WHEN 'transfer_out' THEN 'Transfer to ' || gen_last_name()
                       WHEN 'transfer_in' THEN 'Transfer from ' || gen_last_name()
                       WHEN 'fee' THEN 'Account maintenance fee'
                       ELSE 'Interest credit' END
FROM (SELECT /*+ NO_MERGE ORDERED */ x.g, a.account_id, a.currency_code, x.txn_type,
             gen_rts(a.opened_on, NVL(a.closed_on + 0.99999, SYSDATE)) AS txn_at,
             CASE WHEN x.txn_type IN ('salary','deposit','transfer_in','interest') THEN 1 ELSE -1 END AS sign,
             CASE x.txn_type WHEN 'salary' THEN 1500 + DBMS_RANDOM.VALUE * 3500
                             WHEN 'deposit' THEN 50 + DBMS_RANDOM.VALUE * 1950
                             WHEN 'card_settlement' THEN 5 + DBMS_RANDOM.VALUE * 295
                             WHEN 'withdrawal' THEN 20 + DBMS_RANDOM.VALUE * 380
                             WHEN 'transfer_out' THEN 50 + DBMS_RANDOM.VALUE * 1450
                             WHEN 'transfer_in' THEN 50 + DBMS_RANDOM.VALUE * 1450
                             WHEN 'fee' THEN 1 + DBMS_RANDOM.VALUE * 14
                             ELSE 0.01 + DBMS_RANDOM.VALUE * 50 END AS eur
      FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g, gen_rint(1, gen_rows_for(220000)) AS aid,
                   gen_pick('salary,deposit,card_settlement,card_settlement,card_settlement,withdrawal,withdrawal,transfer_out,transfer_in,fee,interest') AS txn_type
            FROM TABLE(gen_series(gen_rows_for(3000000))) s) x
      JOIN accounts a ON a.account_id = x.aid) t
JOIN gen_fx_year fx ON fx.currency_code = t.currency_code AND fx.yr = EXTRACT(YEAR FROM t.txn_at);
COMMIT;

-- Closed accounts are emptied by a final closing entry.
INSERT /*+ APPEND */ INTO account_transactions
  (txn_id, account_id, txn_at, value_date, txn_type, channel, amount, balance_after, description)
SELECT m.max_id + ROW_NUMBER() OVER (ORDER BY c.account_id), c.account_id, c.closed_on + 0.99998, c.closed_on,
       'closure', 'system', -c.bal, NULL, 'Account closure payout'
FROM (SELECT a.account_id, a.closed_on, SUM(t.amount) AS bal
      FROM accounts a JOIN account_transactions t ON t.account_id = a.account_id
      WHERE a.closed_on IS NOT NULL
      GROUP BY a.account_id, a.closed_on
      HAVING SUM(t.amount) <> 0) c
CROSS JOIN (SELECT MAX(txn_id) AS max_id FROM account_transactions) m;
COMMIT;

MERGE INTO account_transactions t
USING (SELECT txn_id, SUM(amount) OVER (PARTITION BY account_id ORDER BY txn_at, txn_id) AS bal
       FROM account_transactions) s
ON (t.txn_id = s.txn_id)
WHEN MATCHED THEN UPDATE SET t.balance_after = s.bal;
COMMIT;

MERGE INTO accounts a
USING (SELECT account_id, SUM(amount) AS bal FROM account_transactions GROUP BY account_id) s
ON (a.account_id = s.account_id)
WHEN MATCHED THEN UPDATE SET a.current_balance = s.bal;
COMMIT;

CREATE TABLE transfers (
  transfer_id     NUMBER(10)    CONSTRAINT pk_transfers PRIMARY KEY,
  transfer_ref    VARCHAR2(24)  NOT NULL CONSTRAINT uq_transfers_ref UNIQUE,
  from_account_id NUMBER(10)    NOT NULL,
  to_account_id   NUMBER(10),                                         -- set for internal transfers
  beneficiary_iban VARCHAR2(34) NOT NULL,
  beneficiary_name VARCHAR2(80) NOT NULL,
  amount          NUMBER(16,2)  NOT NULL CONSTRAINT ck_transfers_amount CHECK (amount > 0),
  currency_code   CHAR(3)       NOT NULL,
  transfer_type   VARCHAR2(10)  NOT NULL CONSTRAINT ck_transfers_type CHECK (transfer_type IN ('internal','domestic','sepa','instant','swift')),
  initiated_at    DATE          NOT NULL,
  executed_on     DATE,
  status          VARCHAR2(10)  NOT NULL CONSTRAINT ck_transfers_status CHECK (status IN ('executed','pending','rejected'))
);
INSERT /*+ APPEND */ INTO transfers
  (transfer_id, transfer_ref, from_account_id, to_account_id, beneficiary_iban, beneficiary_name, amount, currency_code,
   transfer_type, initiated_at, executed_on, status)
SELECT t.g, 'TRF' || TO_CHAR(t.initiated_at, 'YYYYMMDD') || LPAD(t.g, 10, '0'), t.account_id,
       CASE WHEN t.internal = 1 THEN t.to_account_id END,
       CASE WHEN t.internal = 1 THEN t.to_iban
            ELSE gen_iban(t.ext_iso, '9' || LPAD(gen_rint(0, 9999), 4, '0') || LPAD(gen_rint(0, POWER(10, t.ext_len - 9) - 1), t.ext_len - 9, '0')) END,
       CASE WHEN t.internal = 1 THEN t.to_name ELSE gen_first_name() || ' ' || gen_last_name() END,
       ROUND((20 + POWER(DBMS_RANDOM.VALUE, 2) * 9980) * fx.rate, 2), t.currency_code,
       CASE WHEN t.internal = 1 THEN 'internal'
            WHEN t.ext_iso <> t.own_iso AND t.initiated_at < DATE '2008-01-28' THEN 'swift'
            WHEN t.initiated_at >= DATE '2017-11-21' AND t.r < 0.4 THEN 'instant'
            WHEN t.ext_iso = t.own_iso THEN 'domestic' ELSE 'sepa' END,
       t.initiated_at,
       CASE WHEN t.r2 < 0.96 THEN LEAST(TRUNC(t.initiated_at) + gen_rint(0, 2), TRUNC(SYSDATE)) END,
       CASE WHEN t.r2 < 0.96 THEN 'executed' WHEN t.r2 < 0.99 THEN 'rejected' ELSE 'pending' END
FROM (SELECT /*+ NO_MERGE ORDERED */ x.g, x.internal, x.r, x.r2, a.account_id, a.currency_code, oc.iso_code AS own_iso,
             ec.iso_code AS ext_iso, ec.iban_length AS ext_len,
             b.account_id AS to_account_id, b.iban AS to_iban, bc.first_name || ' ' || bc.last_name AS to_name,
             gen_rts(CASE WHEN x.internal = 1 THEN GREATEST(a.opened_on, b.opened_on) ELSE a.opened_on END,
                     LEAST(NVL(a.closed_on + 0.99999, SYSDATE),
                           CASE WHEN x.internal = 1 THEN NVL(b.closed_on + 0.99999, SYSDATE) ELSE SYSDATE END)) AS initiated_at
      FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g, gen_rint(1, gen_rows_for(220000)) AS aid,
                   gen_rint(1, gen_rows_for(220000)) AS bid, gen_rint(1, 14) AS ext_country,
                   CASE WHEN DBMS_RANDOM.VALUE < 0.3 THEN 1 ELSE 0 END AS internal,
                   DBMS_RANDOM.VALUE AS r, DBMS_RANDOM.VALUE AS r2
            FROM TABLE(gen_series(gen_rows_for(400000))) s) x
      JOIN accounts a   ON a.account_id = x.aid
      JOIN accounts b   ON b.account_id = x.bid
      JOIN customers bc ON bc.customer_id = b.customer_id
      JOIN countries oc ON oc.country_id = 1 + MOD(a.branch_id - 1, 14)
      JOIN countries ec ON ec.country_id = x.ext_country
      WHERE x.aid <> x.bid
        AND (x.internal = 0 OR GREATEST(a.opened_on, b.opened_on)
                               <= LEAST(NVL(a.closed_on, TRUNC(SYSDATE)), NVL(b.closed_on, TRUNC(SYSDATE))))) t
JOIN gen_fx_year fx ON fx.currency_code = t.currency_code AND fx.yr = EXTRACT(YEAR FROM t.initiated_at);
COMMIT;

CREATE TABLE standing_orders (
  order_id        NUMBER(10)    CONSTRAINT pk_standing_orders PRIMARY KEY,
  account_id      NUMBER(10)    NOT NULL,
  beneficiary_iban VARCHAR2(34) NOT NULL,
  beneficiary_name VARCHAR2(80) NOT NULL,
  amount          NUMBER(14,2)  NOT NULL,
  frequency       VARCHAR2(10)  NOT NULL CONSTRAINT ck_so_frequency CHECK (frequency IN ('weekly','monthly','quarterly','yearly')),
  start_date      DATE          NOT NULL,
  end_date        DATE,
  status          VARCHAR2(10)  NOT NULL CONSTRAINT ck_so_status CHECK (status IN ('active','ended','cancelled'))
);
INSERT /*+ APPEND */ INTO standing_orders
  (order_id, account_id, beneficiary_iban, beneficiary_name, amount, frequency, start_date, end_date, status)
SELECT o.g, o.account_id,
       gen_iban(o.iso_code, '8' || LPAD(gen_rint(0, 9999), 4, '0') || LPAD(gen_scramble(o.g, POWER(10, o.iban_length - 9)), o.iban_length - 9, '0')),
       gen_pick('City Utilities,Housing Coop,Telecom Plus,Fitness Club,Insurance Premium,Savings Plan,School Fees,Landlord,Streaming Service,Water Board'),
       ROUND((10 + DBMS_RANDOM.VALUE * 990) * fx.rate, 2),
       gen_pick('weekly,monthly,monthly,monthly,quarterly,yearly'),
       o.start_date, o.end_date,
       CASE WHEN o.end_date IS NULL THEN 'active' WHEN o.r < 0.5 THEN 'cancelled' ELSE 'ended' END
FROM (SELECT /*+ NO_MERGE */ b.*,
             CASE WHEN b.closed_on IS NOT NULL THEN b.closed_on
                  WHEN b.r < 0.4 THEN gen_rdate(b.start_date, TRUNC(SYSDATE)) END AS end_date
      FROM (SELECT /*+ NO_MERGE ORDERED */ x.g, x.r, a.account_id, a.currency_code, a.closed_on, co.iso_code, co.iban_length,
                   gen_rdate(a.opened_on, NVL(a.closed_on, TRUNC(SYSDATE))) AS start_date
            FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g, gen_rint(1, gen_rows_for(220000)) AS aid, DBMS_RANDOM.VALUE AS r
                  FROM TABLE(gen_series(gen_rows_for(60000))) s) x
            JOIN accounts a   ON a.account_id = x.aid
            JOIN countries co ON co.country_id = 1 + MOD(a.branch_id - 1, 14)) b) o
JOIN gen_fx_year fx ON fx.currency_code = o.currency_code AND fx.yr = EXTRACT(YEAR FROM o.start_date);
COMMIT;

-- =====================================================================================
--  16-21  CARDS, MERCHANTS, CARD PAYMENTS, ATMS, FRAUD
-- =====================================================================================
PROMPT === Cards, merchants, ATMs ===
CREATE TABLE cards (
  card_id         NUMBER(10)    CONSTRAINT pk_cards PRIMARY KEY,
  card_token      VARCHAR2(20)  NOT NULL CONSTRAINT uq_cards_token UNIQUE,
  pan_masked      VARCHAR2(19)  NOT NULL,
  account_id      NUMBER(10)    NOT NULL,
  customer_id     NUMBER(10)    NOT NULL,
  card_type       VARCHAR2(8)   NOT NULL CONSTRAINT ck_cards_type CHECK (card_type IN ('debit','credit','prepaid')),
  scheme          VARCHAR2(10)  NOT NULL,
  issued_on       DATE          NOT NULL,
  expires_on      DATE          NOT NULL,
  closed_on       DATE,
  credit_limit    NUMBER(12,2),
  status          VARCHAR2(8)   NOT NULL CONSTRAINT ck_cards_status CHECK (status IN ('active','blocked','expired','closed')),
  CONSTRAINT ck_cards_dates CHECK (expires_on > issued_on)
);
CREATE TABLE gen_card_accounts AS
SELECT ROW_NUMBER() OVER (ORDER BY a.account_id) AS rn, a.account_id
FROM accounts a JOIN account_products p ON p.product_id = a.product_id
WHERE p.product_type IN ('checking','business');
ALTER TABLE gen_card_accounts ADD CONSTRAINT pk_gen_card_accounts PRIMARY KEY (rn);

INSERT /*+ APPEND */ INTO cards
  (card_id, card_token, pan_masked, account_id, customer_id, card_type, scheme, issued_on, expires_on, closed_on, credit_limit, status)
SELECT c.g, 'tok_' || LOWER(LPAD(TO_CHAR(gen_scramble(c.g, POWER(16, 12)), 'FMXXXXXXXXXXXX'), 12, '0')),
       CASE c.scheme WHEN 'VISA' THEN '4' ELSE '5' END || LPAD(gen_rint(10000, 99999), 5, '0') || '******' || LPAD(gen_rint(0, 9999), 4, '0'),
       c.account_id, c.customer_id, c.card_type, c.scheme, c.issued_on, c.expires_on, c.closed_on,
       CASE WHEN c.card_type = 'credit' THEN ROUND(gen_rint(5, 100) * 100 * fx.rate, -1) END,
       CASE WHEN c.closed_on IS NOT NULL THEN 'closed' WHEN c.expires_on < TRUNC(SYSDATE) THEN 'expired'
            WHEN c.r < 0.03 THEN 'blocked' ELSE 'active' END
FROM (SELECT /*+ NO_MERGE */ i.*, LAST_DAY(ADD_MONTHS(i.issued_on, 48)) AS expires_on,
             CASE WHEN i.acc_closed IS NOT NULL AND i.acc_closed < LAST_DAY(ADD_MONTHS(i.issued_on, 48)) THEN i.acc_closed END AS closed_on
      FROM (SELECT /*+ NO_MERGE ORDERED */ x.g, x.r, x.card_type, x.scheme, a.account_id, a.customer_id, a.currency_code,
                   a.closed_on AS acc_closed, gen_rdate(a.opened_on, NVL(a.closed_on, TRUNC(SYSDATE))) AS issued_on
            FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g, gen_rint(1, (SELECT COUNT(*) FROM gen_card_accounts)) AS rn,
                         gen_pick('debit,debit,debit,debit,debit,debit,debit,credit,credit,prepaid') AS card_type,
                         gen_pick('VISA,VISA,MASTERCARD') AS scheme, DBMS_RANDOM.VALUE AS r
                  FROM TABLE(gen_series(gen_rows_for(200000))) s) x
            JOIN gen_card_accounts ca ON ca.rn = x.rn
            JOIN accounts a           ON a.account_id = ca.account_id) i) c
JOIN gen_fx_year fx ON fx.currency_code = c.currency_code AND fx.yr = EXTRACT(YEAR FROM c.issued_on);
COMMIT;

CREATE TABLE merchants (
  merchant_id     NUMBER(8)     CONSTRAINT pk_merchants PRIMARY KEY,
  name            VARCHAR2(80)  NOT NULL,
  mcc             CHAR(4)       NOT NULL,
  category        VARCHAR2(20)  NOT NULL,
  country_id      NUMBER(3)     NOT NULL,
  city            VARCHAR2(40)  NOT NULL,
  onboarded_on    DATE          NOT NULL
);
INSERT /*+ APPEND */ INTO merchants (merchant_id, name, mcc, category, country_id, city, onboarded_on)
SELECT m.g,
       gen_pick('Golden,Blue,Green,Royal,City,Corner,Sunny,Urban,Happy,Prime,Star,Metro') || ' '
         || CASE m.k WHEN 1 THEN gen_pick('Market,Grocer,Fresh Foods') WHEN 2 THEN gen_pick('Bistro,Cafe,Grill,Pizzeria')
                     WHEN 3 THEN gen_pick('Fuel,Petrol Station') WHEN 4 THEN gen_pick('Department Store,Galleria')
                     WHEN 5 THEN gen_pick('Transit,Taxi,Rail') WHEN 6 THEN gen_pick('Hotel,Inn,Suites')
                     WHEN 7 THEN gen_pick('Pharmacy,Drugstore') WHEN 8 THEN gen_pick('Electronics,Tech Store')
                     WHEN 9 THEN gen_pick('Airways,Air') ELSE gen_pick('Boutique,Shop,Outlet') END,
       REGEXP_SUBSTR('5411,5812,5541,5311,4111,7011,5912,5732,4511,5999', '[^,]+', 1, m.k),
       REGEXP_SUBSTR('grocery,restaurant,fuel,department_store,transport,hotel,pharmacy,electronics,airline,other_retail', '[^,]+', 1, m.k),
       m.country_id, gc.city,
       CASE WHEN m.g <= gen_rows_for(20000) * 0.4 THEN DATE '1999-01-01' ELSE gen_rdate(DATE '1999-01-01', TRUNC(SYSDATE) - 60) END
FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g, gen_rint(1, 10) AS k, gen_rint(1, 5) AS city_n,
             CASE WHEN DBMS_RANDOM.VALUE < 0.8 THEN gen_rint(1, 14) ELSE gen_rint(15, 30) END AS country_id
      FROM TABLE(gen_series(gen_rows_for(20000))) s) m
JOIN gen_cities gc ON gc.country_id = m.country_id AND gc.n = m.city_n;
COMMIT;

CREATE TABLE card_transactions (
  card_txn_id     NUMBER(12)    CONSTRAINT pk_card_transactions PRIMARY KEY,
  card_id         NUMBER(10)    NOT NULL,
  merchant_id     NUMBER(8)     NOT NULL,
  txn_at          DATE          NOT NULL,
  amount          NUMBER(14,2)  NOT NULL,
  currency_code   CHAR(3)       NOT NULL,
  billing_amount  NUMBER(14,2)  NOT NULL,                             -- in the card account currency
  channel         VARCHAR2(14)  NOT NULL,
  status          VARCHAR2(10)  NOT NULL CONSTRAINT ck_card_txn_status CHECK (status IN ('approved','declined','reversed')),
  auth_code       CHAR(6)       NOT NULL
);
INSERT /*+ APPEND */ INTO card_transactions
  (card_txn_id, card_id, merchant_id, txn_at, amount, currency_code, billing_amount, channel, status, auth_code)
SELECT t.g, t.card_id, t.merchant_id, t.txn_at,
       ROUND(t.eur * fxm.rate, 2), t.merchant_ccy, ROUND(t.eur * fxa.rate, 2),
       CASE WHEN t.k IN (9) OR t.r < 0.2 THEN CASE WHEN t.txn_at < DATE '2015-01-01' THEN 'ecommerce' ELSE gen_pick('ecommerce,mobile_wallet') END
            WHEN t.txn_at < DATE '2005-01-01' THEN 'magstripe'
            WHEN t.txn_at < DATE '2012-01-01' THEN 'chip_pin'
            ELSE gen_pick('chip_pin,contactless,contactless,contactless') END,
       CASE WHEN t.r2 < 0.965 THEN 'approved' WHEN t.r2 < 0.99 THEN 'declined' ELSE 'reversed' END,
       UPPER(SUBSTR(DBMS_RANDOM.STRING('X', 6), 1, 6))
FROM (SELECT /*+ NO_MERGE ORDERED */ x.g, x.r, x.r2, c.card_id, m.merchant_id, m.k, a.currency_code,
             co.currency_code AS merchant_ccy,
             gen_rts(GREATEST(c.issued_on, m.onboarded_on), LEAST(LEAST(c.expires_on, NVL(c.closed_on, c.expires_on)) + 0.99999, SYSDATE)) AS txn_at,
             CASE m.k WHEN 6 THEN 60 + DBMS_RANDOM.VALUE * 400 WHEN 8 THEN 20 + DBMS_RANDOM.VALUE * 900
                      WHEN 9 THEN 80 + DBMS_RANDOM.VALUE * 900 ELSE 3 + POWER(DBMS_RANDOM.VALUE, 2) * 200 END AS eur
      FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g, gen_rint(1, gen_rows_for(200000)) AS cid,
                   gen_rint(1, gen_rows_for(20000)) AS mid, DBMS_RANDOM.VALUE AS r, DBMS_RANDOM.VALUE AS r2
            FROM TABLE(gen_series(gen_rows_for(2600000))) s) x
      JOIN cards c      ON c.card_id = x.cid
      JOIN accounts a   ON a.account_id = c.account_id
      JOIN (SELECT mm.*, CASE mm.mcc WHEN '5411' THEN 1 WHEN '5812' THEN 2 WHEN '5541' THEN 3 WHEN '5311' THEN 4 WHEN '4111' THEN 5
                                     WHEN '7011' THEN 6 WHEN '5912' THEN 7 WHEN '5732' THEN 8 WHEN '4511' THEN 9 ELSE 10 END AS k
            FROM merchants mm) m ON m.merchant_id = x.mid
      JOIN countries co ON co.country_id = m.country_id
      WHERE GREATEST(c.issued_on, m.onboarded_on) <= LEAST(c.expires_on, NVL(c.closed_on, c.expires_on), TRUNC(SYSDATE))) t
JOIN gen_fx_year fxm ON fxm.currency_code = t.merchant_ccy AND fxm.yr = EXTRACT(YEAR FROM t.txn_at)
JOIN gen_fx_year fxa ON fxa.currency_code = t.currency_code AND fxa.yr = EXTRACT(YEAR FROM t.txn_at);
COMMIT;

CREATE TABLE atms (
  atm_id          NUMBER(6)     CONSTRAINT pk_atms PRIMARY KEY,       -- country = 1 + MOD(id - 1, 14)
  atm_code        VARCHAR2(12)  NOT NULL CONSTRAINT uq_atms_code UNIQUE,
  branch_id       NUMBER(5)     NOT NULL,
  model_name      VARCHAR2(30)  NOT NULL,
  supports_deposit CHAR(1)      NOT NULL CONSTRAINT ck_atms_deposit CHECK (supports_deposit IN ('Y','N')),
  installed_on    DATE          NOT NULL,
  removed_on      DATE
);
INSERT /*+ APPEND */ INTO atms (atm_id, atm_code, branch_id, model_name, supports_deposit, installed_on, removed_on)
SELECT a.g, 'ATM-' || LPAD(a.g, 6, '0'), b.branch_id,
       gen_pick('CashMaster 2000,CashMaster 3000,TellerPro X,TellerPro XL,QuickCash 5'),
       CASE WHEN a.inst >= DATE '2008-01-01' AND DBMS_RANDOM.VALUE < 0.6 THEN 'Y' ELSE 'N' END,
       a.inst,
       CASE WHEN a.r < 0.15 THEN gen_rdate(a.inst + 1000, TRUNC(SYSDATE)) END
FROM (SELECT /*+ NO_MERGE ORDERED */ x.g, x.r, x.branch_id, gen_rdate(b0.opened_on, DATE '2020-12-31') AS inst
      FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g, 1 + MOD(s.COLUMN_VALUE - 1, 280) AS branch_id, DBMS_RANDOM.VALUE AS r
            FROM TABLE(gen_series(1500)) s) x                         -- fixed size
      JOIN branches b0 ON b0.branch_id = x.branch_id) a
JOIN branches b ON b.branch_id = a.branch_id;
COMMIT;

CREATE TABLE atm_withdrawals (
  withdrawal_id   NUMBER(10)    CONSTRAINT pk_atm_withdrawals PRIMARY KEY,
  card_id         NUMBER(10)    NOT NULL,
  atm_id          NUMBER(6)     NOT NULL,
  withdrawn_at    DATE          NOT NULL,
  amount          NUMBER(12,2)  NOT NULL,
  currency_code   CHAR(3)       NOT NULL,
  fee             NUMBER(8,2)   NOT NULL,
  status          VARCHAR2(10)  NOT NULL CONSTRAINT ck_atm_wd_status CHECK (status IN ('dispensed','declined','reversed'))
);
INSERT /*+ APPEND */ INTO atm_withdrawals (withdrawal_id, card_id, atm_id, withdrawn_at, amount, currency_code, fee, status)
SELECT w.g, w.card_id, w.atm_id, w.withdrawn_at,
       ROUND(w.notes * 10 * fx.rate, CASE WHEN fx.rate > 5 THEN -1 ELSE 0 END), w.currency_code,
       CASE WHEN w.r < 0.8 THEN 0 ELSE ROUND(2 * fx.rate, 2) END,
       CASE WHEN w.r2 < 0.95 THEN 'dispensed' WHEN w.r2 < 0.99 THEN 'declined' ELSE 'reversed' END
FROM (SELECT /*+ NO_MERGE ORDERED */ x.g, x.r, x.r2, x.notes, c.card_id, t.atm_id, co.currency_code,
             gen_rts(GREATEST(c.issued_on, t.installed_on),
                     LEAST(LEAST(c.expires_on, NVL(c.closed_on, c.expires_on), NVL(t.removed_on, c.expires_on)) + 0.99999, SYSDATE)) AS withdrawn_at
      FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g, gen_rint(1, gen_rows_for(200000)) AS cid, gen_rint(2, 40) AS notes,
                   gen_rint(0, 106) AS atm_slot, DBMS_RANDOM.VALUE AS r, DBMS_RANDOM.VALUE AS r2
            FROM TABLE(gen_series(gen_rows_for(650000))) s) x
      JOIN cards c      ON c.card_id = x.cid
      JOIN accounts a   ON a.account_id = c.account_id
      JOIN countries co ON co.country_id = 1 + MOD(a.branch_id - 1, 14)
      JOIN atms t       ON t.atm_id = co.country_id + 14 * x.atm_slot      -- ATM in the card's home country
      WHERE c.card_type <> 'credit'
        AND GREATEST(c.issued_on, t.installed_on)
            <= LEAST(c.expires_on, NVL(c.closed_on, c.expires_on), NVL(t.removed_on, c.expires_on), TRUNC(SYSDATE))) w
JOIN gen_fx_year fx ON fx.currency_code = w.currency_code AND fx.yr = EXTRACT(YEAR FROM w.withdrawn_at);
COMMIT;

CREATE TABLE fraud_alerts (
  alert_id        NUMBER(10)    CONSTRAINT pk_fraud_alerts PRIMARY KEY,
  card_txn_id     NUMBER(12)    NOT NULL,
  raised_at       DATE          NOT NULL,
  rule_code       VARCHAR2(30)  NOT NULL,
  risk_score      NUMBER(3)     NOT NULL CONSTRAINT ck_fraud_score CHECK (risk_score BETWEEN 0 AND 100),
  outcome         VARCHAR2(20)  NOT NULL,
  reviewed_by_employee_id NUMBER(7)
);
INSERT /*+ APPEND */ INTO fraud_alerts (alert_id, card_txn_id, raised_at, rule_code, risk_score, outcome, reviewed_by_employee_id)
SELECT f.g, ct.card_txn_id, ct.txn_at + gen_rint(1, 240) / 1440,
       gen_pick('VELOCITY_CHECK,GEO_MISMATCH,HIGH_AMOUNT,NEW_MERCHANT,CARD_NOT_PRESENT,NIGHT_ACTIVITY,MULTIPLE_DECLINES'),
       gen_rint(40, 100),
       gen_pick('false_positive,false_positive,false_positive,confirmed_fraud,customer_verified,pending'),
       CASE WHEN DBMS_RANDOM.VALUE < 0.85 THEN gen_rint(1, GREATEST(300, gen_rows_for(3000))) END
FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g, gen_rint(1, (SELECT MAX(card_txn_id) FROM card_transactions)) AS tid
      FROM TABLE(gen_series(gen_rows_for(30000))) s) f
JOIN card_transactions ct ON ct.card_txn_id = f.tid;
COMMIT;

-- =====================================================================================
--  22-26  LENDING
-- =====================================================================================
PROMPT === Loans ===
CREATE TABLE loan_products (
  loan_product_id NUMBER(3)     CONSTRAINT pk_loan_products PRIMARY KEY,
  name            VARCHAR2(60)  NOT NULL CONSTRAINT uq_loan_products_name UNIQUE,
  loan_type       VARCHAR2(10)  NOT NULL CONSTRAINT ck_loan_type CHECK (loan_type IN ('personal','auto','mortgage','business','student')),
  min_term_months NUMBER(3)     NOT NULL,
  max_term_months NUMBER(3)     NOT NULL,
  rate_spread     NUMBER(5,3)   NOT NULL
);
INSERT INTO loan_products (loan_product_id, name, loan_type, min_term_months, max_term_months, rate_spread)
SELECT 1,'Personal Loan Classic','personal',12,84,4.5 FROM dual UNION ALL SELECT 2,'Personal Loan Express','personal',6,48,6.0 FROM dual UNION ALL
SELECT 3,'Debt Consolidation','personal',24,96,3.8 FROM dual UNION ALL SELECT 4,'Green Home Improvement','personal',12,120,2.9 FROM dual UNION ALL
SELECT 5,'New Car Loan','auto',24,84,2.5 FROM dual UNION ALL SELECT 6,'Used Car Loan','auto',12,72,3.5 FROM dual UNION ALL
SELECT 7,'Electric Vehicle Loan','auto',24,96,1.5 FROM dual UNION ALL SELECT 8,'Motorbike Loan','auto',12,60,4.0 FROM dual UNION ALL
SELECT 9,'Fixed Rate Mortgage','mortgage',120,360,1.2 FROM dual UNION ALL SELECT 10,'Variable Rate Mortgage','mortgage',120,300,0.9 FROM dual UNION ALL
SELECT 11,'First Home Mortgage','mortgage',180,360,1.0 FROM dual UNION ALL SELECT 12,'Buy to Let Mortgage','mortgage',120,300,1.8 FROM dual UNION ALL
SELECT 13,'SME Working Capital','business',12,60,3.2 FROM dual UNION ALL SELECT 14,'Equipment Financing','business',24,120,2.8 FROM dual UNION ALL
SELECT 15,'Student Loan','student',60,120,1.0 FROM dual UNION ALL SELECT 16,'Graduate Loan','student',36,96,1.5 FROM dual;
COMMIT;

CREATE TABLE loans (
  loan_id         NUMBER(10)    CONSTRAINT pk_loans PRIMARY KEY,
  loan_number     VARCHAR2(20)  NOT NULL CONSTRAINT uq_loans_number UNIQUE,
  customer_id     NUMBER(10)    NOT NULL,
  account_id      NUMBER(10)    NOT NULL,                             -- disbursement / repayment account
  loan_product_id NUMBER(3)     NOT NULL,
  branch_id       NUMBER(5)     NOT NULL,
  officer_employee_id NUMBER(7) NOT NULL,
  currency_code   CHAR(3)       NOT NULL,
  principal       NUMBER(16,2)  NOT NULL CONSTRAINT ck_loans_principal CHECK (principal > 0),
  annual_rate     NUMBER(6,3)   NOT NULL,
  term_months     NUMBER(3)     NOT NULL,
  start_date      DATE          NOT NULL,
  maturity_date   DATE          NOT NULL,
  status          VARCHAR2(12)  NOT NULL CONSTRAINT ck_loans_status CHECK (status IN ('active','repaid','defaulted','written_off'))
);
INSERT /*+ APPEND */ INTO loans
  (loan_id, loan_number, customer_id, account_id, loan_product_id, branch_id, officer_employee_id, currency_code,
   principal, annual_rate, term_months, start_date, maturity_date, status)
SELECT l.g, 'LN' || TO_CHAR(l.start_date, 'YYYY') || LPAD(l.g, 9, '0'), l.customer_id, l.account_id, l.loan_product_id,
       l.branch_id, gen_rint(1, GREATEST(300, gen_rows_for(3000))), l.currency_code,
       ROUND(CASE l.loan_type WHEN 'personal' THEN 2000 + DBMS_RANDOM.VALUE * 38000 WHEN 'auto' THEN 8000 + DBMS_RANDOM.VALUE * 52000
                              WHEN 'mortgage' THEN 80000 + DBMS_RANDOM.VALUE * 820000 WHEN 'business' THEN 20000 + DBMS_RANDOM.VALUE * 480000
                              ELSE 5000 + DBMS_RANDOM.VALUE * 35000 END * fx.rate, -1),
       ROUND(CASE WHEN l.start_date < DATE '2009-01-01' THEN 4.2 WHEN l.start_date < DATE '2016-01-01' THEN 2.0
                  WHEN l.start_date < DATE '2022-07-01' THEN 0.6 ELSE 3.4 END + l.rate_spread + DBMS_RANDOM.VALUE * 1.5, 3),
       l.term_months, l.start_date, ADD_MONTHS(l.start_date, l.term_months),
       CASE WHEN ADD_MONTHS(l.start_date, l.term_months) <= TRUNC(SYSDATE) THEN CASE WHEN l.r < 0.98 THEN 'repaid' ELSE 'written_off' END
            WHEN l.r < 0.025 THEN 'defaulted' ELSE 'active' END
FROM (SELECT /*+ NO_MERGE ORDERED */ x.g, x.r, a.account_id, a.customer_id, a.branch_id, a.currency_code,
             lp.loan_product_id, lp.loan_type, lp.rate_spread,
             lp.min_term_months + 12 * gen_rint(0, TRUNC((lp.max_term_months - lp.min_term_months) / 12)) AS term_months,
             gen_rdate(a.opened_on, LEAST(a.opened_on + 3650, NVL(a.closed_on, TRUNC(SYSDATE)))) AS start_date
      FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g, gen_rint(1, (SELECT COUNT(*) FROM gen_card_accounts)) AS rn,
                   gen_pick('1,1,2,3,4,5,5,6,7,8,9,9,10,11,12,13,14,15,16') AS pid, DBMS_RANDOM.VALUE AS r
            FROM TABLE(gen_series(gen_rows_for(30000))) s) x
      JOIN gen_card_accounts ca ON ca.rn = x.rn                       -- loans run on current accounts
      JOIN accounts a           ON a.account_id = ca.account_id
      JOIN loan_products lp     ON lp.loan_product_id = TO_NUMBER(x.pid)) l
JOIN gen_fx_year fx ON fx.currency_code = l.currency_code AND fx.yr = EXTRACT(YEAR FROM l.start_date);
COMMIT;

CREATE TABLE loan_schedules (
  schedule_id     NUMBER(14)    CONSTRAINT pk_loan_schedules PRIMARY KEY,   -- loan_id * 1000 + installment_no
  loan_id         NUMBER(10)    NOT NULL,
  installment_no  NUMBER(3)     NOT NULL,
  due_date        DATE          NOT NULL,
  principal_due   NUMBER(16,2)  NOT NULL,
  interest_due    NUMBER(16,2)  NOT NULL,
  total_due       NUMBER(16,2)  NOT NULL,
  balance_after   NUMBER(16,2)  NOT NULL,
  CONSTRAINT uq_loan_schedules UNIQUE (loan_id, installment_no)
);
-- French amortisation (annuity): constant installment, interest on the outstanding balance.
INSERT /*+ APPEND */ INTO loan_schedules
  (schedule_id, loan_id, installment_no, due_date, principal_due, interest_due, total_due, balance_after)
SELECT q.loan_id * 1000 + q.k, q.loan_id, q.k, ADD_MONTHS(q.start_date, q.k),
       ROUND(q.pay - q.prev_bal * q.r, 2), ROUND(q.prev_bal * q.r, 2), ROUND(q.pay, 2),
       GREATEST(0, ROUND(q.principal * POWER(1 + q.r, q.k) - q.pay * (POWER(1 + q.r, q.k) - 1) / q.r, 2))
FROM (SELECT l.loan_id, l.start_date, l.principal, s.COLUMN_VALUE AS k, l.annual_rate / 1200 AS r,
             l.principal * (l.annual_rate / 1200) / (1 - POWER(1 + l.annual_rate / 1200, -l.term_months)) AS pay,
             l.principal * POWER(1 + l.annual_rate / 1200, s.COLUMN_VALUE - 1)
               - (l.principal * (l.annual_rate / 1200) / (1 - POWER(1 + l.annual_rate / 1200, -l.term_months)))
                 * (POWER(1 + l.annual_rate / 1200, s.COLUMN_VALUE - 1) - 1) / (l.annual_rate / 1200) AS prev_bal
      FROM loans l, TABLE(gen_series(l.term_months)) s) q;
COMMIT;

CREATE TABLE loan_payments (
  payment_id      NUMBER(14)    CONSTRAINT pk_loan_payments PRIMARY KEY,
  schedule_id     NUMBER(14)    NOT NULL CONSTRAINT uq_loan_payments_schedule UNIQUE,
  loan_id         NUMBER(10)    NOT NULL,
  paid_on         DATE          NOT NULL,
  amount          NUMBER(16,2)  NOT NULL,
  days_late       NUMBER(4)     NOT NULL,
  channel         VARCHAR2(12)  NOT NULL
);
INSERT /*+ APPEND */ INTO loan_payments (payment_id, schedule_id, loan_id, paid_on, amount, days_late, channel)
SELECT p.schedule_id, p.schedule_id, p.loan_id, p.paid_on, p.total_due, GREATEST(0, p.paid_on - p.due_date),
       gen_pick('direct_debit,direct_debit,direct_debit,transfer,branch')
FROM (SELECT /*+ NO_MERGE */ ls.schedule_id, ls.loan_id, ls.due_date, ls.total_due, DBMS_RANDOM.VALUE AS r,
             LEAST(ls.due_date + CASE WHEN DBMS_RANDOM.VALUE < 0.9 THEN 0 ELSE gen_rint(1, 45) END, TRUNC(SYSDATE)) AS paid_on
      FROM loan_schedules ls JOIN loans l ON l.loan_id = ls.loan_id
      WHERE ls.due_date <= TRUNC(SYSDATE)
        AND (l.status IN ('active','repaid') OR ls.installment_no <= l.term_months * 0.4)) p   -- defaults stop paying
WHERE p.r < 0.995;
COMMIT;

CREATE TABLE collaterals (
  collateral_id   NUMBER(10)    CONSTRAINT pk_collaterals PRIMARY KEY,
  loan_id         NUMBER(10)    NOT NULL,
  collateral_type VARCHAR2(16)  NOT NULL,
  description     VARCHAR2(120) NOT NULL,
  appraised_value NUMBER(16,2)  NOT NULL,
  appraised_on    DATE          NOT NULL
);
INSERT /*+ APPEND */ INTO collaterals (collateral_id, loan_id, collateral_type, description, appraised_value, appraised_on)
SELECT ROW_NUMBER() OVER (ORDER BY c.loan_id), c.loan_id, c.ctype,
       CASE c.ctype WHEN 'real_estate' THEN gen_pick('Apartment,Detached house,Townhouse,Villa,Office unit') || ' - ' || gen_rint(45, 400) || ' m2'
                    WHEN 'vehicle' THEN gen_pick('Sedan,SUV,Hatchback,Pickup,Motorbike,Van') || ' model year ' || EXTRACT(YEAR FROM c.start_date)
                    ELSE gen_pick('CNC machinery,Delivery fleet,Server farm,Production line,Inventory pledge') END,
       ROUND(c.principal * (1.1 + DBMS_RANDOM.VALUE * 0.6), -2), c.start_date - gen_rint(5, 60)
FROM (SELECT l.loan_id, l.principal, l.start_date,
             CASE lp.loan_type WHEN 'mortgage' THEN 'real_estate' WHEN 'auto' THEN 'vehicle' ELSE 'equipment' END AS ctype
      FROM loans l JOIN loan_products lp ON lp.loan_product_id = l.loan_product_id
      WHERE lp.loan_type IN ('mortgage','auto','business')) c;
COMMIT;

-- =====================================================================================
--  27-37  INSURANCE
-- =====================================================================================
PROMPT === Insurance ===
CREATE TABLE insurance_products (
  product_id      NUMBER(3)     CONSTRAINT pk_insurance_products PRIMARY KEY,
  product_code    VARCHAR2(12)  NOT NULL CONSTRAINT uq_ins_products_code UNIQUE,
  name            VARCHAR2(60)  NOT NULL,
  line_of_business VARCHAR2(10) NOT NULL CONSTRAINT ck_ins_line CHECK (line_of_business IN ('auto','home','life','health','travel','liability')),
  base_premium_eur NUMBER(10,2) NOT NULL,
  launched_on     DATE          NOT NULL
);
INSERT INTO insurance_products (product_id, product_code, name, line_of_business, base_premium_eur, launched_on)
SELECT 1,'AUT-TPL','Motor Third Party','auto',380,DATE '1999-01-01' FROM dual UNION ALL
SELECT 2,'AUT-COMP','Motor Comprehensive','auto',820,DATE '1999-01-01' FROM dual UNION ALL
SELECT 3,'AUT-FLEET','Fleet Motor','auto',2400,DATE '2002-03-01' FROM dual UNION ALL
SELECT 4,'AUT-EV','Electric Vehicle Cover','auto',690,DATE '2012-06-01' FROM dual UNION ALL
SELECT 5,'HOM-STD','Home Standard','home',260,DATE '1999-01-01' FROM dual UNION ALL
SELECT 6,'HOM-PREM','Home Premium','home',540,DATE '1999-01-01' FROM dual UNION ALL
SELECT 7,'HOM-RENT','Renters Contents','home',140,DATE '2005-01-01' FROM dual UNION ALL
SELECT 8,'HOM-NATCAT','Natural Catastrophe','home',310,DATE '2010-04-01' FROM dual UNION ALL
SELECT 9,'LIF-TERM','Term Life','life',420,DATE '1999-01-01' FROM dual UNION ALL
SELECT 10,'LIF-WHOLE','Whole Life','life',1650,DATE '1999-01-01' FROM dual UNION ALL
SELECT 11,'LIF-MORT','Mortgage Protection','life',360,DATE '1999-01-01' FROM dual UNION ALL
SELECT 12,'LIF-SAV','Savings Life','life',2400,DATE '2001-09-01' FROM dual UNION ALL
SELECT 13,'HLT-IND','Individual Health','health',1300,DATE '1999-01-01' FROM dual UNION ALL
SELECT 14,'HLT-FAM','Family Health','health',3100,DATE '1999-01-01' FROM dual UNION ALL
SELECT 15,'HLT-DENT','Dental Plan','health',290,DATE '2008-01-01' FROM dual UNION ALL
SELECT 16,'TRV-SINGLE','Single Trip Travel','travel',45,DATE '1999-01-01' FROM dual UNION ALL
SELECT 17,'TRV-ANNUAL','Annual Multi-Trip','travel',160,DATE '2003-05-01' FROM dual UNION ALL
SELECT 18,'LIA-GEN','General Liability','liability',900,DATE '1999-01-01' FROM dual UNION ALL
SELECT 19,'LIA-PROF','Professional Indemnity','liability',2200,DATE '1999-01-01' FROM dual UNION ALL
SELECT 20,'LIA-CYBER','Cyber Liability','liability',3500,DATE '2015-02-01' FROM dual;
COMMIT;

CREATE TABLE agents (
  agent_id        NUMBER(7)     CONSTRAINT pk_agents PRIMARY KEY,
  agent_code      VARCHAR2(10)  NOT NULL CONSTRAINT uq_agents_code UNIQUE,
  full_name       VARCHAR2(80)  NOT NULL,
  email           VARCHAR2(120) NOT NULL CONSTRAINT uq_agents_email UNIQUE,
  agent_type      VARCHAR2(14)  NOT NULL CONSTRAINT ck_agents_type CHECK (agent_type IN ('bancassurance','tied','broker')),
  branch_id       NUMBER(5),                                          -- set for bancassurance agents
  licensed_on     DATE          NOT NULL,
  commission_rate NUMBER(5,4)   NOT NULL
);
INSERT /*+ APPEND */ INTO agents (agent_id, agent_code, full_name, email, agent_type, branch_id, licensed_on, commission_rate)
SELECT a.g, 'AG' || LPAD(a.g, 6, '0'), a.fn || ' ' || a.ln,
       LOWER(REPLACE(a.fn || '.' || a.ln, ' ', '')) || '.' || a.g || '@agents.example.com',
       a.atype, CASE WHEN a.atype = 'bancassurance' THEN 1 + MOD(a.g - 1, 280) END,
       CASE WHEN a.g <= 200 THEN DATE '1999-01-01' ELSE gen_rdate(DATE '1999-01-01', TRUNC(SYSDATE) - 180) END,
       CASE a.atype WHEN 'broker' THEN 0.12 WHEN 'tied' THEN 0.08 ELSE 0.05 END + ROUND(DBMS_RANDOM.VALUE * 0.03, 4)
FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g, gen_first_name() AS fn, gen_last_name() AS ln,
             gen_pick('bancassurance,bancassurance,tied,tied,broker') AS atype
      FROM TABLE(gen_series(GREATEST(300, gen_rows_for(1200)))) s) a;
COMMIT;

CREATE TABLE policies (
  policy_id       NUMBER(10)    CONSTRAINT pk_policies PRIMARY KEY,
  policy_number   VARCHAR2(24)  NOT NULL CONSTRAINT uq_policies_number UNIQUE,
  customer_id     NUMBER(10)    NOT NULL,
  product_id      NUMBER(3)     NOT NULL,
  agent_id        NUMBER(7)     NOT NULL,
  start_date      DATE          NOT NULL,
  end_date        DATE          NOT NULL,
  status          VARCHAR2(10)  NOT NULL CONSTRAINT ck_policies_status CHECK (status IN ('active','expired','cancelled')),
  payment_frequency VARCHAR2(10) NOT NULL CONSTRAINT ck_policies_freq CHECK (payment_frequency IN ('single','annual','semiannual','quarterly','monthly')),
  annual_premium  NUMBER(14,2)  NOT NULL,
  sum_insured     NUMBER(16,2)  NOT NULL,
  currency_code   CHAR(3)       NOT NULL,
  CONSTRAINT ck_policies_dates CHECK (end_date > start_date)
);
INSERT /*+ APPEND */ INTO policies
  (policy_id, policy_number, customer_id, product_id, agent_id, start_date, end_date, status, payment_frequency,
   annual_premium, sum_insured, currency_code)
SELECT p.g,
       'P' || UPPER(SUBSTR(p.line, 1, 2)) || '-' || TO_CHAR(p.start_date, 'YYYY') || '-' || LPAD(p.g, 8, '0'),
       p.customer_id, p.product_id, p.agent_id, p.start_date,
       CASE WHEN p.cancel < 0.05 THEN GREATEST(p.start_date + 1, gen_rdate(p.start_date, LEAST(p.planned_end, TRUNC(SYSDATE)))) ELSE p.planned_end END,
       CASE WHEN p.cancel < 0.05 THEN 'cancelled' WHEN p.planned_end <= TRUNC(SYSDATE) THEN 'expired' ELSE 'active' END,
       CASE WHEN p.line = 'travel' THEN 'single' ELSE gen_pick('annual,annual,annual,semiannual,semiannual,quarterly,quarterly,monthly') END,
       ROUND(p.base_premium_eur * (0.6 + DBMS_RANDOM.VALUE * 0.9) * fx.rate, 2),
       ROUND(CASE p.line WHEN 'auto' THEN 5000 + DBMS_RANDOM.VALUE * 75000 WHEN 'home' THEN 100000 + DBMS_RANDOM.VALUE * 800000
                         WHEN 'life' THEN 50000 + DBMS_RANDOM.VALUE * 950000 WHEN 'health' THEN 50000 + DBMS_RANDOM.VALUE * 450000
                         WHEN 'travel' THEN 10000 + DBMS_RANDOM.VALUE * 90000 ELSE 100000 + DBMS_RANDOM.VALUE * 4900000 END * fx.rate, -2),
       p.currency_code
FROM (SELECT /*+ NO_MERGE */ b.*,
             CASE b.line WHEN 'travel' THEN CASE WHEN b.product_id = 16 THEN b.start_date + gen_rint(5, 45) ELSE ADD_MONTHS(b.start_date, 12) END
                         WHEN 'life' THEN ADD_MONTHS(b.start_date, 12 * gen_rint(10, 30))
                         WHEN 'health' THEN ADD_MONTHS(b.start_date, 12 * gen_rint(1, 8))
                         ELSE ADD_MONTHS(b.start_date, 12 * gen_rint(1, 10)) END AS planned_end
      FROM (SELECT /*+ NO_MERGE ORDERED */ x.g, x.cancel, cu.customer_id, ip.product_id, ip.line_of_business AS line,
                   ip.base_premium_eur, ag.agent_id, co.currency_code,
                   gen_rdate(GREATEST(cu.customer_since, ip.launched_on, ag.licensed_on),
                             LEAST(GREATEST(cu.customer_since, ip.launched_on, ag.licensed_on) + 3650, NVL(cu.closed_on, TRUNC(SYSDATE)))) AS start_date
            FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g, gen_rint(1, gen_rows_for(150000)) AS cid, gen_rint(1, 20) AS pid,
                         gen_rint(1, GREATEST(300, gen_rows_for(1200))) AS aid, DBMS_RANDOM.VALUE AS cancel
                  FROM TABLE(gen_series(gen_rows_for(120000))) s) x
            JOIN customers cu          ON cu.customer_id = x.cid
            JOIN insurance_products ip ON ip.product_id = x.pid
            JOIN agents ag             ON ag.agent_id = x.aid
            JOIN countries co          ON co.country_id = cu.country_id
            WHERE GREATEST(cu.customer_since, ip.launched_on, ag.licensed_on) <= NVL(cu.closed_on, TRUNC(SYSDATE))) b) p
JOIN gen_fx_year fx ON fx.currency_code = p.currency_code AND fx.yr = EXTRACT(YEAR FROM p.start_date);
COMMIT;

CREATE TABLE policy_coverages (
  coverage_id     NUMBER(12)    CONSTRAINT pk_policy_coverages PRIMARY KEY,   -- policy_id * 10 + n
  policy_id       NUMBER(10)    NOT NULL,
  coverage_code   VARCHAR2(20)  NOT NULL,
  coverage_limit  NUMBER(16,2)  NOT NULL,
  deductible      NUMBER(12,2)  NOT NULL,
  premium_share   NUMBER(5,4)   NOT NULL,
  CONSTRAINT uq_policy_coverages UNIQUE (policy_id, coverage_code)
);
INSERT /*+ APPEND */ INTO policy_coverages (coverage_id, policy_id, coverage_code, coverage_limit, deductible, premium_share)
SELECT p.policy_id * 10 + s.COLUMN_VALUE, p.policy_id,
       REGEXP_SUBSTR(CASE ip.line_of_business WHEN 'auto' THEN 'THIRD_PARTY,COLLISION,THEFT'
                                              WHEN 'home' THEN 'FIRE,WATER_DAMAGE,BURGLARY'
                                              WHEN 'life' THEN 'DEATH,DISABILITY,CRITICAL_ILLNESS'
                                              WHEN 'health' THEN 'INPATIENT,OUTPATIENT,DENTAL'
                                              WHEN 'travel' THEN 'MEDICAL,CANCELLATION,BAGGAGE'
                                              ELSE 'GENERAL,LEGAL_DEFENSE,PRODUCT' END, '[^,]+', 1, s.COLUMN_VALUE),
       ROUND(p.sum_insured * CASE s.COLUMN_VALUE WHEN 1 THEN 1 WHEN 2 THEN 0.5 ELSE 0.2 END, -2),
       ROUND(p.sum_insured * CASE WHEN ip.line_of_business IN ('life','travel') THEN 0 ELSE 0.002 END, -1),
       CASE s.COLUMN_VALUE WHEN 1 THEN 0.6 WHEN 2 THEN 0.3 ELSE 0.1 END
FROM policies p
JOIN insurance_products ip ON ip.product_id = p.product_id
CROSS JOIN TABLE(gen_series(3)) s
WHERE s.COLUMN_VALUE <= 1 + MOD(p.policy_id * 7, 3)   -- 1 to 3 coverages per policy
;
COMMIT;

CREATE TABLE beneficiaries (
  beneficiary_id  NUMBER(12)    CONSTRAINT pk_beneficiaries PRIMARY KEY,
  policy_id       NUMBER(10)    NOT NULL,
  full_name       VARCHAR2(80)  NOT NULL,
  relationship    VARCHAR2(12)  NOT NULL,
  birth_date      DATE          NOT NULL,
  share_pct       NUMBER(5,2)   NOT NULL CONSTRAINT ck_benef_share CHECK (share_pct > 0 AND share_pct <= 100)
);
INSERT /*+ APPEND */ INTO beneficiaries (beneficiary_id, policy_id, full_name, relationship, birth_date, share_pct)
SELECT p.policy_id * 10 + s.COLUMN_VALUE, p.policy_id, gen_first_name() || ' ' || gen_last_name(),
       gen_pick('spouse,child,child,parent,sibling,partner'),
       gen_rdate(DATE '1940-01-01', LEAST(p.start_date, DATE '2020-12-31')),
       100 / (1 + MOD(p.policy_id, 2))
FROM policies p
JOIN insurance_products ip ON ip.product_id = p.product_id
CROSS JOIN TABLE(gen_series(2)) s
WHERE ip.line_of_business = 'life' AND s.COLUMN_VALUE <= 1 + MOD(p.policy_id, 2);
COMMIT;

CREATE TABLE insured_vehicles (
  vehicle_id      NUMBER(10)    CONSTRAINT pk_insured_vehicles PRIMARY KEY,
  policy_id       NUMBER(10)    NOT NULL,
  vin             CHAR(17)      NOT NULL CONSTRAINT uq_vehicles_vin UNIQUE,
  plate_number    VARCHAR2(12)  NOT NULL CONSTRAINT uq_vehicles_plate UNIQUE,
  make            VARCHAR2(20)  NOT NULL,
  model_name      VARCHAR2(30)  NOT NULL,
  model_year      NUMBER(4)     NOT NULL,
  fuel_type       VARCHAR2(10)  NOT NULL,
  market_value    NUMBER(12,2)  NOT NULL
);
INSERT /*+ APPEND */ INTO insured_vehicles
  (vehicle_id, policy_id, vin, plate_number, make, model_name, model_year, fuel_type, market_value)
SELECT v.policy_id, v.policy_id,
       UPPER(SUBSTR(v.make, 1, 3)) || 'ZZZ' || SUBSTR('ABCDEFGHJKLMNPRSTVWXY123456789', MOD(v.model_year - 1980, 30) + 1, 1)
         || LPAD(gen_scramble(v.policy_id, 10000000000), 10, '0'),
       v.iso_code || '-' || LPAD(gen_scramble(v.policy_id, 10000000), 7, '0'),
       v.make, gen_pick('City,Sport,Family,Cross,Van,Coupe,Touring') || ' ' || gen_rint(1, 9) * 100, v.model_year,
       CASE WHEN v.product_id = 4 OR (v.model_year >= 2012 AND DBMS_RANDOM.VALUE < 0.12) THEN 'electric'
            WHEN v.model_year >= 2005 AND DBMS_RANDOM.VALUE < 0.15 THEN 'hybrid'
            ELSE gen_pick('petrol,petrol,diesel') END,
       ROUND(v.sum_insured * (0.5 + DBMS_RANDOM.VALUE * 0.5), -2)
FROM (SELECT /*+ NO_MERGE */ p.policy_id, p.product_id, p.sum_insured, co.iso_code,
             gen_pick('Voltra,Carrino,Autonova,Brisk,Montero,Kestrel,Solano,Velox') AS make,
             GREATEST(1990, EXTRACT(YEAR FROM p.start_date) - gen_rint(0, 12)) AS model_year
      FROM policies p
      JOIN insurance_products ip ON ip.product_id = p.product_id
      JOIN customers cu          ON cu.customer_id = p.customer_id
      JOIN countries co          ON co.country_id = cu.country_id
      WHERE ip.line_of_business = 'auto') v;
COMMIT;

CREATE TABLE insured_properties (
  property_id     NUMBER(10)    CONSTRAINT pk_insured_properties PRIMARY KEY,
  policy_id       NUMBER(10)    NOT NULL,
  property_type   VARCHAR2(14)  NOT NULL,
  street          VARCHAR2(120) NOT NULL,
  city            VARCHAR2(40)  NOT NULL,
  country_id      NUMBER(3)     NOT NULL,
  built_year      NUMBER(4)     NOT NULL,
  area_m2         NUMBER(6)     NOT NULL,
  rebuild_value   NUMBER(14,2)  NOT NULL
);
INSERT /*+ APPEND */ INTO insured_properties
  (property_id, policy_id, property_type, street, city, country_id, built_year, area_m2, rebuild_value)
SELECT h.policy_id, h.policy_id, gen_pick('apartment,apartment,house,townhouse,villa'),
       gen_rint(1, 299) || ' ' || gen_pick('Main,Oak,Station,Harbour,Market,Garden,Park,Church,Mill,Lake,Olive,Palm,Cedar,Bridge')
         || ' ' || gen_pick('Street,Avenue,Road,Lane,Boulevard,Way'),
       gc.city, h.country_id, gen_rint(1900, LEAST(EXTRACT(YEAR FROM h.start_date), 2024)), gen_rint(35, 450),
       ROUND(h.sum_insured * (0.7 + DBMS_RANDOM.VALUE * 0.3), -2)
FROM (SELECT /*+ NO_MERGE */ p.policy_id, p.start_date, p.sum_insured, cu.country_id, gen_rint(1, 5) AS city_n
      FROM policies p
      JOIN insurance_products ip ON ip.product_id = p.product_id
      JOIN customers cu          ON cu.customer_id = p.customer_id
      WHERE ip.line_of_business = 'home') h
JOIN gen_cities gc ON gc.country_id = h.country_id AND gc.n = h.city_n;
COMMIT;

CREATE TABLE premium_payments (
  premium_payment_id NUMBER(14) CONSTRAINT pk_premium_payments PRIMARY KEY,  -- policy_id * 1000 + n
  policy_id       NUMBER(10)    NOT NULL,
  due_date        DATE          NOT NULL,
  amount          NUMBER(14,2)  NOT NULL,
  paid_on         DATE,
  method          VARCHAR2(14),
  status          VARCHAR2(10)  NOT NULL CONSTRAINT ck_premium_status CHECK (status IN ('paid','overdue','pending','waived')),
  CONSTRAINT uq_premium_payments UNIQUE (policy_id, due_date)
);
INSERT /*+ APPEND */ INTO premium_payments (premium_payment_id, policy_id, due_date, amount, paid_on, method, status)
SELECT d.policy_id * 1000 + d.k, d.policy_id, d.due_date, d.amount,
       CASE WHEN d.r < 0.96 THEN LEAST(d.due_date + gen_rint(-10, 20), TRUNC(SYSDATE)) END,
       CASE WHEN d.r < 0.96 THEN CASE WHEN d.due_date < DATE '2006-01-01' THEN gen_pick('cheque,bank_transfer,direct_debit')
                                      ELSE gen_pick('direct_debit,direct_debit,card,bank_transfer') END END,
       CASE WHEN d.r < 0.96 THEN 'paid' WHEN d.r < 0.97 THEN 'waived'
            WHEN d.due_date < TRUNC(SYSDATE) - 15 THEN 'overdue' ELSE 'pending' END
FROM (SELECT /*+ NO_MERGE */ q.policy_id, s.COLUMN_VALUE AS k, ADD_MONTHS(q.start_date, (s.COLUMN_VALUE - 1) * q.mpp) AS due_date,
             ROUND(q.annual_premium * CASE WHEN q.mpp = 0 THEN 1 ELSE q.mpp / 12 END, 2) AS amount, DBMS_RANDOM.VALUE AS r
      FROM (SELECT p.*, CASE p.payment_frequency WHEN 'single' THEN 0 WHEN 'annual' THEN 12 WHEN 'semiannual' THEN 6
                                                 WHEN 'quarterly' THEN 3 ELSE 1 END AS mpp
            FROM policies p WHERE p.start_date <= TRUNC(SYSDATE)) q,
           TABLE(gen_series(CASE WHEN q.mpp = 0 THEN 1
                                 ELSE TRUNC(MONTHS_BETWEEN(LEAST(q.end_date - 1, TRUNC(SYSDATE)), q.start_date) / q.mpp) + 1 END)) s) d;
COMMIT;
UPDATE premium_payments SET paid_on = due_date WHERE paid_on < due_date - 10;
COMMIT;

CREATE TABLE claims (
  claim_id        NUMBER(10)    CONSTRAINT pk_claims PRIMARY KEY,
  claim_number    VARCHAR2(20)  NOT NULL CONSTRAINT uq_claims_number UNIQUE,
  policy_id       NUMBER(10)    NOT NULL,
  coverage_id     NUMBER(12)    NOT NULL,
  incident_date   DATE          NOT NULL,
  reported_on     DATE          NOT NULL,
  claimed_amount  NUMBER(16,2)  NOT NULL,
  approved_amount NUMBER(16,2),
  status          VARCHAR2(14)  NOT NULL CONSTRAINT ck_claims_status CHECK (status IN ('open','under_review','approved','settled','rejected','litigation')),
  adjuster_employee_id NUMBER(7) NOT NULL,
  description     VARCHAR2(200) NOT NULL,
  CONSTRAINT ck_claims_dates CHECK (reported_on >= incident_date)
);
INSERT /*+ APPEND */ INTO claims
  (claim_id, claim_number, policy_id, coverage_id, incident_date, reported_on, claimed_amount, approved_amount, status,
   adjuster_employee_id, description)
SELECT c.g, 'CLM-' || TO_CHAR(c.reported_on, 'YYYY') || '-' || LPAD(c.g, 8, '0'), c.policy_id, c.coverage_id,
       c.incident_date, c.reported_on, c.claimed,
       CASE WHEN c.status IN ('approved','settled') THEN ROUND(c.claimed * (0.6 + DBMS_RANDOM.VALUE * 0.4), 2) END,
       c.status, gen_rint(1, GREATEST(300, gen_rows_for(3000))),
       CASE c.coverage_code
         WHEN 'THIRD_PARTY' THEN 'Rear-end collision at traffic light' WHEN 'COLLISION' THEN 'Vehicle damaged in parking lot'
         WHEN 'THEFT' THEN 'Vehicle stolen overnight' WHEN 'FIRE' THEN 'Kitchen fire damage'
         WHEN 'WATER_DAMAGE' THEN 'Burst pipe flooded ground floor' WHEN 'BURGLARY' THEN 'Break-in, electronics stolen'
         WHEN 'DEATH' THEN 'Death benefit claim' WHEN 'DISABILITY' THEN 'Permanent disability after accident'
         WHEN 'CRITICAL_ILLNESS' THEN 'Critical illness diagnosis' WHEN 'INPATIENT' THEN 'Hospital admission'
         WHEN 'OUTPATIENT' THEN 'Specialist consultation and tests' WHEN 'DENTAL' THEN 'Dental treatment'
         WHEN 'MEDICAL' THEN 'Medical emergency abroad' WHEN 'CANCELLATION' THEN 'Trip cancelled due to illness'
         WHEN 'BAGGAGE' THEN 'Lost baggage' WHEN 'GENERAL' THEN 'Third-party injury on premises'
         WHEN 'LEGAL_DEFENSE' THEN 'Legal defence costs' ELSE 'Defective product claim' END
FROM (SELECT /*+ NO_MERGE */ i.*,
             LEAST(i.incident_date + gen_rint(0, 30), TRUNC(SYSDATE)) AS reported_on,
             ROUND(i.coverage_limit * POWER(DBMS_RANDOM.VALUE, 3) + 50, 2) AS claimed,
             CASE WHEN i.incident_date > TRUNC(SYSDATE) - 45 THEN gen_pick('open,under_review')
                  ELSE gen_pick('settled,settled,settled,settled,settled,settled,approved,rejected,rejected,litigation') END AS status
      FROM (SELECT /*+ NO_MERGE ORDERED */ x.g, p.policy_id, pc.coverage_id, pc.coverage_code, pc.coverage_limit,
                   gen_rdate(p.start_date, LEAST(p.end_date, TRUNC(SYSDATE))) AS incident_date
            FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g, gen_rint(1, gen_rows_for(120000)) AS pid, gen_rint(0, 2) AS cov_pick
                  FROM TABLE(gen_series(gen_rows_for(60000))) s) x
            JOIN policies p          ON p.policy_id = x.pid
            JOIN policy_coverages pc ON pc.coverage_id = p.policy_id * 10 + 1 + MOD(x.cov_pick, 1 + MOD(p.policy_id * 7, 3))
            WHERE p.start_date <= TRUNC(SYSDATE)) i) c;
COMMIT;

CREATE TABLE claim_documents (
  document_id     NUMBER(12)    CONSTRAINT pk_claim_documents PRIMARY KEY,
  claim_id        NUMBER(10)    NOT NULL,
  document_type   VARCHAR2(20)  NOT NULL,
  file_name       VARCHAR2(60)  NOT NULL CONSTRAINT uq_claim_docs_file UNIQUE,
  uploaded_at     DATE          NOT NULL,
  size_kb         NUMBER(8)     NOT NULL
);
INSERT /*+ APPEND */ INTO claim_documents (document_id, claim_id, document_type, file_name, uploaded_at, size_kb)
SELECT c.claim_id * 10 + s.COLUMN_VALUE, c.claim_id,
       CASE WHEN s.COLUMN_VALUE = 1 THEN 'claim_form' ELSE gen_pick('photo,photo,invoice,police_report,medical_report,expert_report') END,
       'CLM' || c.claim_id || '_' || s.COLUMN_VALUE || '.' || CASE WHEN s.COLUMN_VALUE = 1 THEN 'pdf' ELSE gen_pick('pdf,jpg,png') END,
       LEAST(c.reported_on + gen_rint(0, 20) + DBMS_RANDOM.VALUE, SYSDATE),
       gen_rint(40, 12000)
FROM claims c
CROSS JOIN TABLE(gen_series(4)) s
WHERE s.COLUMN_VALUE <= 1 + MOD(c.claim_id * 3, 4)   -- 1 to 4 documents per claim
;
COMMIT;

CREATE TABLE claim_payments (
  claim_payment_id NUMBER(12)   CONSTRAINT pk_claim_payments PRIMARY KEY,
  claim_id        NUMBER(10)    NOT NULL,
  payment_reference VARCHAR2(24) NOT NULL CONSTRAINT uq_claim_pay_ref UNIQUE,
  payee_type      VARCHAR2(14)  NOT NULL,
  paid_on         DATE          NOT NULL,
  amount          NUMBER(16,2)  NOT NULL
);
INSERT /*+ APPEND */ INTO claim_payments (claim_payment_id, claim_id, payment_reference, payee_type, paid_on, amount)
SELECT c.claim_id * 10 + s.COLUMN_VALUE, c.claim_id, 'CP' || LPAD(c.claim_id, 10, '0') || '-' || s.COLUMN_VALUE,
       gen_pick('policyholder,policyholder,repair_shop,hospital,third_party'),
       LEAST(c.reported_on + 10 * s.COLUMN_VALUE + gen_rint(0, 60), TRUNC(SYSDATE)),
       ROUND(c.approved_amount / (1 + MOD(c.claim_id, 2)), 2)
FROM claims c
CROSS JOIN TABLE(gen_series(2)) s
WHERE c.status = 'settled' AND s.COLUMN_VALUE <= 1 + MOD(c.claim_id, 2)   -- settled in 1 or 2 instalments
;
COMMIT;

-- =====================================================================================
--  38-40  REINSURANCE & AUDIT
-- =====================================================================================
PROMPT === Reinsurance and audit ===
CREATE TABLE reinsurers (
  reinsurer_id    NUMBER(4)     CONSTRAINT pk_reinsurers PRIMARY KEY,
  name            VARCHAR2(60)  NOT NULL CONSTRAINT uq_reinsurers_name UNIQUE,
  country_id      NUMBER(3)     NOT NULL,
  rating          VARCHAR2(4)   NOT NULL,
  partner_since   DATE          NOT NULL
);
INSERT INTO reinsurers (reinsurer_id, name, country_id, rating, partner_since)
SELECT s.COLUMN_VALUE,
       REGEXP_SUBSTR('Northstar Re,Meridian Reinsurance,Alpine Re,Orion Re,Baltic Re,Sahara Re,Pacific Rim Re,Granite Re,Aurora Re,Zenith Reinsurance,Harbor Re,Sterling Re,Crescent Re,Polaris Re,Summit Re,Equinox Re,Lighthouse Re,Evergreen Re,Monarch Re,Keystone Re,Trident Re,Bastion Re,Cobalt Re,Halcyon Re',
                     '[^,]+', 1, s.COLUMN_VALUE),
       gen_pick('1,2,7,15,16,26,30'), gen_pick('AAA,AA+,AA,AA-,A+,A'),
       gen_rdate(DATE '1985-01-01', DATE '1998-12-31')
FROM TABLE(gen_series(24)) s   -- fixed size
;
COMMIT;

CREATE TABLE reinsurance_treaties (
  treaty_id       NUMBER(6)     CONSTRAINT pk_reinsurance_treaties PRIMARY KEY,
  treaty_no       VARCHAR2(20)  NOT NULL CONSTRAINT uq_treaties_no UNIQUE,
  reinsurer_id    NUMBER(4)     NOT NULL,
  line_of_business VARCHAR2(10) NOT NULL,
  treaty_year     NUMBER(4)     NOT NULL,
  treaty_type     VARCHAR2(16)  NOT NULL CONSTRAINT ck_treaty_type CHECK (treaty_type IN ('quota_share','surplus','excess_of_loss','stop_loss')),
  cession_pct     NUMBER(5,2)   NOT NULL,
  retention_eur   NUMBER(14,2)  NOT NULL,
  CONSTRAINT uq_treaties_line_year UNIQUE (line_of_business, treaty_year)
);
INSERT INTO reinsurance_treaties
  (treaty_id, treaty_no, reinsurer_id, line_of_business, treaty_year, treaty_type, cession_pct, retention_eur)
SELECT ROW_NUMBER() OVER (ORDER BY y.yr, l.line), 'TR-' || y.yr || '-' || UPPER(SUBSTR(l.line, 1, 3)),
       gen_rint(1, 24), l.line, y.yr,
       gen_pick('quota_share,quota_share,surplus,excess_of_loss,excess_of_loss,stop_loss'),
       ROUND(10 + DBMS_RANDOM.VALUE * 50, 2), gen_rint(1, 50) * 100000
FROM (SELECT 1998 + s.COLUMN_VALUE AS yr FROM TABLE(gen_series(EXTRACT(YEAR FROM SYSDATE) - 1998)) s) y
CROSS JOIN (SELECT 'auto' line FROM dual UNION ALL SELECT 'home' FROM dual UNION ALL SELECT 'life' FROM dual UNION ALL
            SELECT 'health' FROM dual UNION ALL SELECT 'travel' FROM dual UNION ALL SELECT 'liability' FROM dual) l;
COMMIT;

CREATE TABLE audit_log (
  audit_id        NUMBER(12)    CONSTRAINT pk_audit_log PRIMARY KEY,
  logged_at       DATE          NOT NULL,
  employee_id     NUMBER(7)     NOT NULL,
  entity_type     VARCHAR2(20)  NOT NULL,
  entity_id       NUMBER(12)    NOT NULL,
  action          VARCHAR2(12)  NOT NULL,
  client_ip       VARCHAR2(15)  NOT NULL
);
INSERT /*+ APPEND */ INTO audit_log (audit_id, logged_at, employee_id, entity_type, entity_id, action, client_ip)
SELECT a.g, a.logged_at, a.employee_id, a.entity_type, gen_rint(1, gen_rows_for(150000)), a.action,
       '10.' || gen_rint(0, 255) || '.' || gen_rint(0, 255) || '.' || gen_rint(1, 254)
FROM (SELECT /*+ NO_MERGE ORDERED */ x.g, x.entity_type, x.action, e.employee_id,
             gen_rts(e.hired_on, NVL(e.terminated_on + 0.99999, SYSDATE)) AS logged_at
      FROM (SELECT /*+ NO_MERGE */ s.COLUMN_VALUE AS g, gen_rint(1, GREATEST(300, gen_rows_for(3000))) AS eid,
                   gen_pick('customer,account,card,loan,policy,claim,kyc_document') AS entity_type,
                   gen_pick('view,view,view,view,update,update,create,approve,export,delete') AS action
            FROM TABLE(gen_series(gen_rows_for(500000))) s) x
      JOIN employees e ON e.employee_id = x.eid) a;
COMMIT;

-- =====================================================================================
--  Foreign keys (validated now: proves referential integrity of the generated data)
-- =====================================================================================
PROMPT === Foreign keys and indexes ===
ALTER TABLE countries            ADD CONSTRAINT fk_countries_currency    FOREIGN KEY (currency_code) REFERENCES currencies;
ALTER TABLE fx_rates             ADD CONSTRAINT fk_fx_currency           FOREIGN KEY (currency_code) REFERENCES currencies;
ALTER TABLE branches             ADD CONSTRAINT fk_branches_country      FOREIGN KEY (country_id) REFERENCES countries;
ALTER TABLE employees            ADD CONSTRAINT fk_employees_branch      FOREIGN KEY (branch_id) REFERENCES branches;
ALTER TABLE employees            ADD CONSTRAINT fk_employees_manager     FOREIGN KEY (manager_id) REFERENCES employees;
ALTER TABLE customers            ADD CONSTRAINT fk_customers_country     FOREIGN KEY (country_id) REFERENCES countries;
ALTER TABLE customers            ADD CONSTRAINT fk_customers_branch      FOREIGN KEY (home_branch_id) REFERENCES branches;
ALTER TABLE customer_addresses   ADD CONSTRAINT fk_addresses_customer    FOREIGN KEY (customer_id) REFERENCES customers;
ALTER TABLE customer_addresses   ADD CONSTRAINT fk_addresses_country     FOREIGN KEY (country_id) REFERENCES countries;
ALTER TABLE kyc_documents        ADD CONSTRAINT fk_kyc_customer          FOREIGN KEY (customer_id) REFERENCES customers;
ALTER TABLE kyc_documents        ADD CONSTRAINT fk_kyc_employee          FOREIGN KEY (verified_by_employee_id) REFERENCES employees;
ALTER TABLE credit_scores        ADD CONSTRAINT fk_scores_customer       FOREIGN KEY (customer_id) REFERENCES customers;
ALTER TABLE accounts             ADD CONSTRAINT fk_accounts_customer     FOREIGN KEY (customer_id) REFERENCES customers;
ALTER TABLE accounts             ADD CONSTRAINT fk_accounts_branch       FOREIGN KEY (branch_id) REFERENCES branches;
ALTER TABLE accounts             ADD CONSTRAINT fk_accounts_product      FOREIGN KEY (product_id) REFERENCES account_products;
ALTER TABLE accounts             ADD CONSTRAINT fk_accounts_currency     FOREIGN KEY (currency_code) REFERENCES currencies;
ALTER TABLE account_holders      ADD CONSTRAINT fk_holders_account       FOREIGN KEY (account_id) REFERENCES accounts;
ALTER TABLE account_holders      ADD CONSTRAINT fk_holders_customer      FOREIGN KEY (customer_id) REFERENCES customers;
ALTER TABLE account_transactions ADD CONSTRAINT fk_acc_txn_account       FOREIGN KEY (account_id) REFERENCES accounts;
ALTER TABLE transfers            ADD CONSTRAINT fk_transfers_from        FOREIGN KEY (from_account_id) REFERENCES accounts;
ALTER TABLE transfers            ADD CONSTRAINT fk_transfers_to          FOREIGN KEY (to_account_id) REFERENCES accounts;
ALTER TABLE transfers            ADD CONSTRAINT fk_transfers_currency    FOREIGN KEY (currency_code) REFERENCES currencies;
ALTER TABLE standing_orders      ADD CONSTRAINT fk_so_account            FOREIGN KEY (account_id) REFERENCES accounts;
ALTER TABLE cards                ADD CONSTRAINT fk_cards_account         FOREIGN KEY (account_id) REFERENCES accounts;
ALTER TABLE cards                ADD CONSTRAINT fk_cards_customer        FOREIGN KEY (customer_id) REFERENCES customers;
ALTER TABLE merchants            ADD CONSTRAINT fk_merchants_country     FOREIGN KEY (country_id) REFERENCES countries;
ALTER TABLE card_transactions    ADD CONSTRAINT fk_card_txn_card         FOREIGN KEY (card_id) REFERENCES cards;
ALTER TABLE card_transactions    ADD CONSTRAINT fk_card_txn_merchant     FOREIGN KEY (merchant_id) REFERENCES merchants;
ALTER TABLE card_transactions    ADD CONSTRAINT fk_card_txn_currency     FOREIGN KEY (currency_code) REFERENCES currencies;
ALTER TABLE atms                 ADD CONSTRAINT fk_atms_branch           FOREIGN KEY (branch_id) REFERENCES branches;
ALTER TABLE atm_withdrawals      ADD CONSTRAINT fk_atm_wd_card           FOREIGN KEY (card_id) REFERENCES cards;
ALTER TABLE atm_withdrawals      ADD CONSTRAINT fk_atm_wd_atm            FOREIGN KEY (atm_id) REFERENCES atms;
ALTER TABLE fraud_alerts         ADD CONSTRAINT fk_fraud_card_txn        FOREIGN KEY (card_txn_id) REFERENCES card_transactions;
ALTER TABLE fraud_alerts         ADD CONSTRAINT fk_fraud_employee        FOREIGN KEY (reviewed_by_employee_id) REFERENCES employees;
ALTER TABLE loans                ADD CONSTRAINT fk_loans_customer        FOREIGN KEY (customer_id) REFERENCES customers;
ALTER TABLE loans                ADD CONSTRAINT fk_loans_account         FOREIGN KEY (account_id) REFERENCES accounts;
ALTER TABLE loans                ADD CONSTRAINT fk_loans_product         FOREIGN KEY (loan_product_id) REFERENCES loan_products;
ALTER TABLE loans                ADD CONSTRAINT fk_loans_branch          FOREIGN KEY (branch_id) REFERENCES branches;
ALTER TABLE loans                ADD CONSTRAINT fk_loans_officer         FOREIGN KEY (officer_employee_id) REFERENCES employees;
ALTER TABLE loan_schedules       ADD CONSTRAINT fk_schedules_loan        FOREIGN KEY (loan_id) REFERENCES loans;
ALTER TABLE loan_payments        ADD CONSTRAINT fk_loan_pay_schedule     FOREIGN KEY (schedule_id) REFERENCES loan_schedules;
ALTER TABLE loan_payments        ADD CONSTRAINT fk_loan_pay_loan         FOREIGN KEY (loan_id) REFERENCES loans;
ALTER TABLE collaterals          ADD CONSTRAINT fk_collaterals_loan      FOREIGN KEY (loan_id) REFERENCES loans;
ALTER TABLE agents               ADD CONSTRAINT fk_agents_branch         FOREIGN KEY (branch_id) REFERENCES branches;
ALTER TABLE policies             ADD CONSTRAINT fk_policies_customer     FOREIGN KEY (customer_id) REFERENCES customers;
ALTER TABLE policies             ADD CONSTRAINT fk_policies_product      FOREIGN KEY (product_id) REFERENCES insurance_products;
ALTER TABLE policies             ADD CONSTRAINT fk_policies_agent        FOREIGN KEY (agent_id) REFERENCES agents;
ALTER TABLE policies             ADD CONSTRAINT fk_policies_currency     FOREIGN KEY (currency_code) REFERENCES currencies;
ALTER TABLE policy_coverages     ADD CONSTRAINT fk_coverages_policy      FOREIGN KEY (policy_id) REFERENCES policies;
ALTER TABLE beneficiaries        ADD CONSTRAINT fk_beneficiaries_policy  FOREIGN KEY (policy_id) REFERENCES policies;
ALTER TABLE insured_vehicles     ADD CONSTRAINT fk_vehicles_policy       FOREIGN KEY (policy_id) REFERENCES policies;
ALTER TABLE insured_properties   ADD CONSTRAINT fk_properties_policy     FOREIGN KEY (policy_id) REFERENCES policies;
ALTER TABLE insured_properties   ADD CONSTRAINT fk_properties_country    FOREIGN KEY (country_id) REFERENCES countries;
ALTER TABLE premium_payments     ADD CONSTRAINT fk_premiums_policy       FOREIGN KEY (policy_id) REFERENCES policies;
ALTER TABLE claims               ADD CONSTRAINT fk_claims_policy         FOREIGN KEY (policy_id) REFERENCES policies;
ALTER TABLE claims               ADD CONSTRAINT fk_claims_coverage       FOREIGN KEY (coverage_id) REFERENCES policy_coverages;
ALTER TABLE claims               ADD CONSTRAINT fk_claims_adjuster       FOREIGN KEY (adjuster_employee_id) REFERENCES employees;
ALTER TABLE claim_documents      ADD CONSTRAINT fk_claim_docs_claim      FOREIGN KEY (claim_id) REFERENCES claims;
ALTER TABLE claim_payments       ADD CONSTRAINT fk_claim_pay_claim       FOREIGN KEY (claim_id) REFERENCES claims;
ALTER TABLE reinsurers           ADD CONSTRAINT fk_reinsurers_country    FOREIGN KEY (country_id) REFERENCES countries;
ALTER TABLE reinsurance_treaties ADD CONSTRAINT fk_treaties_reinsurer    FOREIGN KEY (reinsurer_id) REFERENCES reinsurers;
ALTER TABLE audit_log            ADD CONSTRAINT fk_audit_employee        FOREIGN KEY (employee_id) REFERENCES employees;

CREATE INDEX ix_employees_branch      ON employees (branch_id);
CREATE INDEX ix_customers_country     ON customers (country_id);
CREATE INDEX ix_customers_branch      ON customers (home_branch_id);
CREATE INDEX ix_customers_since       ON customers (customer_since);
CREATE INDEX ix_addresses_customer    ON customer_addresses (customer_id);
CREATE INDEX ix_kyc_customer          ON kyc_documents (customer_id);
CREATE INDEX ix_scores_customer       ON credit_scores (customer_id);
CREATE INDEX ix_accounts_customer     ON accounts (customer_id);
CREATE INDEX ix_accounts_branch       ON accounts (branch_id);
CREATE INDEX ix_accounts_product      ON accounts (product_id);
CREATE INDEX ix_holders_customer      ON account_holders (customer_id);
CREATE INDEX ix_acc_txn_account       ON account_transactions (account_id, txn_at);
CREATE INDEX ix_acc_txn_date          ON account_transactions (txn_at);
CREATE INDEX ix_transfers_from        ON transfers (from_account_id);
CREATE INDEX ix_transfers_to          ON transfers (to_account_id);
CREATE INDEX ix_transfers_date        ON transfers (initiated_at);
CREATE INDEX ix_so_account            ON standing_orders (account_id);
CREATE INDEX ix_cards_account         ON cards (account_id);
CREATE INDEX ix_cards_customer        ON cards (customer_id);
CREATE INDEX ix_card_txn_card         ON card_transactions (card_id);
CREATE INDEX ix_card_txn_merchant     ON card_transactions (merchant_id);
CREATE INDEX ix_card_txn_date         ON card_transactions (txn_at);
CREATE INDEX ix_atms_branch           ON atms (branch_id);
CREATE INDEX ix_atm_wd_card           ON atm_withdrawals (card_id);
CREATE INDEX ix_atm_wd_atm            ON atm_withdrawals (atm_id);
CREATE INDEX ix_fraud_card_txn        ON fraud_alerts (card_txn_id);
CREATE INDEX ix_loans_customer        ON loans (customer_id);
CREATE INDEX ix_loans_account         ON loans (account_id);
CREATE INDEX ix_loan_pay_loan         ON loan_payments (loan_id);
CREATE INDEX ix_collaterals_loan      ON collaterals (loan_id);
CREATE INDEX ix_policies_customer     ON policies (customer_id);
CREATE INDEX ix_policies_product      ON policies (product_id);
CREATE INDEX ix_policies_agent        ON policies (agent_id);
CREATE INDEX ix_beneficiaries_policy  ON beneficiaries (policy_id);
CREATE INDEX ix_vehicles_policy       ON insured_vehicles (policy_id);
CREATE INDEX ix_properties_policy     ON insured_properties (policy_id);
CREATE INDEX ix_claims_policy         ON claims (policy_id);
CREATE INDEX ix_claims_coverage       ON claims (coverage_id);
CREATE INDEX ix_claims_reported       ON claims (reported_on);
CREATE INDEX ix_claim_docs_claim      ON claim_documents (claim_id);
CREATE INDEX ix_claim_pay_claim       ON claim_payments (claim_id);
CREATE INDEX ix_audit_employee        ON audit_log (employee_id);
CREATE INDEX ix_audit_date            ON audit_log (logged_at);

-- =====================================================================================
--  Cleanup of generator helpers, statistics, summary
-- =====================================================================================
DROP TABLE gen_cities PURGE;
DROP TABLE gen_fx_usd PURGE;
DROP TABLE gen_fx_year PURGE;
DROP TABLE gen_card_accounts PURGE;
DROP FUNCTION gen_first_name;
DROP FUNCTION gen_last_name;
DROP FUNCTION gen_iban;
DROP FUNCTION gen_scramble;
DROP FUNCTION gen_pick;
DROP FUNCTION gen_grow_date;
DROP FUNCTION gen_rts;
DROP FUNCTION gen_rdate;
DROP FUNCTION gen_rint;
DROP FUNCTION gen_series;
DROP FUNCTION gen_rows_for;
DROP TYPE gen_num_tab;

BEGIN
  DBMS_STATS.GATHER_SCHEMA_STATS(ownname => USER, cascade => TRUE);
END;
/

PROMPT === Row counts ===
COLUMN table_name FORMAT A24
SELECT t.table_name, x.row_count
FROM user_tables t,
     XMLTABLE('/ROWSET/ROW' PASSING DBMS_XMLGEN.GETXMLTYPE('SELECT COUNT(*) AS C FROM "' || t.table_name || '"')
              COLUMNS row_count NUMBER PATH 'C') x
ORDER BY t.table_name;
