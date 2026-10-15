# Querywise databases: what's inside and what to ask

This guide covers the 14 data sources you can query in Querywise: the built-in **Northstar sample**, the **11 business databases** from the migration pack (`pack/`), and **2 large history databases** (`sample-databases/`) with 40 tables each and data from 1999 to today. Each section says what the business is, how to open it, what the tables hold, which rules matter, and gives example questions graded by difficulty.

All data is **synthetic**. Unless a section says otherwise, dates are in 2026 and **money is stored as integer CAD cents** (`amount_cents = 12345` means $123.45). The two large databases (sections 13 and 14) are different: dates run from **1999-01-01 to today** and money is stored as **decimal amounts** in a stated currency.

---

## Contents

1. [How to use this guide](#how-to-use-this-guide)
2. [Databases at a glance](#databases-at-a-glance)
3. [Writing questions that work](#writing-questions-that-work)
4. Databases
   - [Northstar Retail — SQLite sample](#1-northstar-retail--sqlite-built-in-sample)
   - [Public library — SQLite](#2-public-library-lending--sqlite)
   - [Renewable energy — PostgreSQL](#3-renewable-energy-operations--postgresql)
   - [Omnichannel retail — MySQL](#4-omnichannel-retail--mysql)
   - [Cold-chain freight — MariaDB](#5-cold-chain-freight--mariadb)
   - [Outpatient billing — SQL Server](#6-outpatient-billing--sql-server)
   - [Airport operations — Oracle](#7-airport-operations--oracle)
   - [Property insurance — Db2](#8-property-insurance--db2)
   - [Online learning — MongoDB](#9-online-learning--mongodb)
   - [Service reliability — Elasticsearch](#10-service-reliability--elasticsearch)
   - [Nonprofit grants — Excel / CSV](#11-nonprofit-grants--excel--csv)
   - [Environmental sensors — Parquet](#12-environmental-sensors--parquet)
   - [Telecom & supply chain — PostgreSQL (large)](#13-telecom--supply-chain--postgresql-large)
   - [Banking & insurance — Oracle (large)](#14-banking--insurance--oracle-large)
5. [Troubleshooting](#troubleshooting)

---

## How to use this guide

**Start everything** (all databases, the backend and the frontend) from PowerShell in the repository root:

```powershell
.\scripts\run_live_tests.ps1 -AcceptLicenses
```

Then open **http://localhost:8080**. Stop and delete the stack with `.\scripts\run_live_tests.ps1 -Down`.

**Switch to a database:** **Settings** (gear icon) → **Data sources** → **Connect** next to the source. Querywise tests the connection, discovers the tables, and the page switches to that source. The suggested-question chips under the box change with it.

**Ask a question:** type it in **"What would you like to know?"** and click **Analyze data**. Claude writes SQL for the active database, Querywise checks it and runs it read-only, and you get:

- **Visualization:** choose Bars, Columns, Line, Area, Share, Stacked, Heatmap, Scatter or Value. Only the types that fit the result are shown.
- **Results:** the actual rows, which you can export to CSV.
- **SQL query:** the exact SQL that ran. You can edit it and run it again.

> AI questions need a provider in **Settings → AI provider** (Anthropic or Ollama). Without one, the suggested-question chips and your own SQL still work.

**Difficulty levels used below**

| Level | Meaning | Typical SQL |
|---|---|---|
| 🟢 Easy | One table, a filter or a count | `SELECT … WHERE … GROUP BY` |
| 🟡 Medium | Two or three tables joined, grouped, sorted | `JOIN` + `GROUP BY` + `ORDER BY` |
| 🔴 Hard | Several tables, pre-aggregated child data, ratios, rankings, business rules | CTEs, `CASE`, window functions |

---

## Databases at a glance

| # | Database | Engine | Source id | Tables | Rows | Complexity |
|---|---|---|---|---|---|---|
| 1 | Northstar Retail | SQLite (built in) | `sample` | 4 | 2,671 | ★★☆☆☆ |
| 2 | Public library lending | SQLite | `live_sqlite` | 7 | 394 | ★★★☆☆ |
| 3 | Renewable energy operations | PostgreSQL 16 | `live_postgres` | 8 | 196 | ★★★☆☆ |
| 4 | Omnichannel retail | MySQL 8.4 | `live_mysql` | 8 | 687 | ★★★★☆ |
| 5 | Cold-chain freight | MariaDB 11.4 | `live_mariadb` | 7 | 1,228 | ★★★★☆ |
| 6 | Outpatient billing | SQL Server 2022 | `live_sqlserver` | 7 | 378 | ★★★★☆ |
| 7 | Airport operations | Oracle Free 23 | `live_oracle` | 8 | 510 | ★★★★☆ |
| 8 | Property insurance | Db2 11.5 | `live_db2` | 7 | 549 | ★★★★★ |
| 9 | Online learning | MongoDB 8.0 | `live_mongodb` | 4 collections | 396 | ★★☆☆☆ (limited SQL) |
| 10 | Service reliability | Elasticsearch 9.1 | `live_elasticsearch` | 3 indices + 1 alias | 144 | ★★☆☆☆ (one index per query) |
| 11 | Nonprofit grants | Excel / CSV | `live_excel` | 5 sheets | 478 | ★★★☆☆ |
| 12 | Environmental sensors | Parquet | `live_parquet` | 5 files | 2,428 | ★★★☆☆ |
| 13 | Telecom & supply chain | PostgreSQL 12+ | you add it (schema `telecom`) | 40 | 11,193,936 | ★★★★★ |
| 14 | Banking & insurance | Oracle 19c / 23ai | you add it (your schema) | 40 | 15,295,763 | ★★★★★ |

The pack sizes are **scale 1**. The pack can generate 10× or 100× more data (`--scale`), which multiplies the main fact table (loans, readings, orders…).

Databases 13 and 14 are not part of the live test stack. Each is one SQL script that you run against your own server; it generates the data inside the database. Their sizes are also **scale 1**, and a setting at the top of each script changes them (0.01 for a quick test, 5 for about five times more rows).

---

## Writing questions that work

- **Name the measure, the grouping and the filter.** "Total *refund cents* *by product category* *for completed orders*" beats "how are returns?"
- **Use the database's own words.** Statuses and categories are lowercase codes (`completed`, `no_show`, `in_transit`). This guide lists them per database.
- **Say the unit when money is involved.** "…in dollars" makes Claude divide cents by 100; otherwise results stay in cents.
- **Expect a clarification for missing data.** Asking for profit where no costs exist, or for a date outside 2026, returns a short clarification instead of a made-up number. That is intentional.
- **Every question is independent.** "Now split that by month" does not remember the previous question; ask the full question again.
- **Check the SQL tab.** The numbers come from the database, but the interpretation comes from the model. Confirm the filters are the ones you meant.

---

## 1. Northstar Retail — SQLite (built-in sample)

**What it is:** a small online store selling electronics, home & office, outdoor gear and apparel to Canadian customers, January–September 2026. It is available without Docker and in the browser-only demo.

**Open it:** Settings → Data sources → **Northstar sample** → Connect. It is active by default.

**Tables**

| Table | Rows | Key columns | Links to |
|---|---|---|---|
| `customers` | 80 | `name`, `province`, `segment` | — |
| `products` | 16 | `name`, `category`, `price` | — |
| `orders` | 720 | `order_date` (YYYY-MM-DD text), `status` | `customer_id → customers` |
| `order_items` | 1,855 | `quantity`, `unit_price` | `order_id → orders`, `product_id → products` |

**Values:** `status` ∈ completed, pending, cancelled · `segment` ∈ Consumer, Business, Enterprise · `category` ∈ Electronics, Home & Office, Outdoors, Apparel · 5 provinces.

**Business rules:** revenue = `SUM(quantity × unit_price)` for **completed** orders only, CAD before tax. Average order value divides revenue by **distinct** completed orders. There are no costs, profit, discounts, refunds or tax. Unlike the pack databases, money here is in **dollars** (floating point).

**Example questions**

| # | Level | Question |
|---|---|---|
| 1 | 🟢 | How many orders have each status? |
| 2 | 🟢 | How many customers are in each province? |
| 3 | 🟢 | What are the five most expensive products? |
| 4 | 🟡 | How is completed-order revenue trending by month? |
| 5 | 🟡 | Which product categories bring in the most revenue? |
| 6 | 🟡 | Who are our top 10 customers by revenue? |
| 7 | 🟡 | Compare revenue across customer segments. |
| 8 | 🔴 | What is the average order value by province, for completed orders? |
| 9 | 🔴 | What percentage of all orders were cancelled in each month? |
| 10 | 🔴 | Show monthly revenue by category. *(Try the **Stacked** and **Heatmap** charts.)* |

Try also: *"What is our profit?"* The expected answer is a clarification, because costs don't exist in this data.

---

## 2. Public library lending — SQLite

**What it is:** a four-branch public library: members borrow physical copies of titles, late returns create fines, and fines are paid in part or in full.

**Open it:** source **Public library (SQLite)**. The file is `pack/output/library.sqlite`.

**Tables**

| Table | Rows | Key columns | Links to |
|---|---|---|---|
| `branches` | 4 | `name`, `city`, `latitude`, `longitude` | — |
| `members` | 40 | `member_code`, `joined_on` | `branch_id → branches` |
| `titles` | 40 | `isbn`, `title`, `genre` | — |
| `copies` | 120 | `barcode` | `title_id → titles`, `branch_id → branches` |
| `loans` | 120 | `borrowed_on`, `due_on`, `returned_on` (NULL = still out), `overdue_flag` | `copy_id → copies`, `member_id → members` |
| `fines` | 40 | `assessed_cents`, `waived_cents` | `loan_id → loans` |
| `fine_payments` | 30 | `paid_on`, `amount_cents` | `fine_id → fines` |

**Values:** `genre` ∈ fiction, history, science · loans from 2026-01-02 to 2026-05-01.

**Business rules:** a fine's outstanding amount = `assessed_cents − waived_cents − payments`. `overdue_flag = 1` means not returned and due before 2026-10-01; it's a snapshot taken at migration time. Pre-aggregate payments per fine before joining, otherwise fines double-count.

**Example questions**

| # | Level | Question |
|---|---|---|
| 1 | 🟢 | How many loans are still not returned? |
| 2 | 🟢 | How many titles are there in each genre? |
| 3 | 🟢 | How many loans are flagged overdue? |
| 4 | 🟡 | Rank genres by number of loans. |
| 5 | 🟡 | How many copies does each branch hold? |
| 6 | 🟡 | Which members borrowed the most items? |
| 7 | 🟡 | What is the average loan length in days for returned items, by genre? |
| 8 | 🔴 | What are unpaid fines by branch, in dollars, after waivers and payments? |
| 9 | 🔴 | Which branch has the highest share of its loans returned late? |
| 10 | 🔴 | For each genre, what percentage of assessed fines has been collected? |

---

## 3. Renewable energy operations — PostgreSQL

**What it is:** a wind-farm operator. Turbines at four sites produce energy readings. Outages create maintenance work orders for crews, and power-purchase contracts produce monthly settlements.

**Open it:** source **Renewable energy (PostgreSQL)**. Schema `public`, read-only role `qw_app`.

**Tables**

| Table | Rows | Key columns | Links to |
|---|---|---|---|
| `sites` | 4 | `name`, `region`, `latitude`, `longitude` | — |
| `turbines` | 20 | `serial`, `capacity_kw` | `site_id → sites` |
| `contracts` | 4 | `starts_on`, `ends_on`, `rate_micros` | `site_id → sites` |
| `readings` | 120 | `observed_on`, `energy_wh`, `quality`, `review_flag` | `turbine_id → turbines` |
| `outages` | 20 | `started_on`, `duration_minutes`, `reason` | `turbine_id → turbines` |
| `crews` | 4 | `name`, `specialty` | — |
| `work_orders` | 20 | `cost_cents`, `status` | `outage_id → outages`, `crew_id → crews` |
| `settlements` | 4 | `period_on`, `paid_cents` | `contract_id → contracts` |

**Values:** `region` ∈ R1–R4 · `quality` ∈ valid, invalid · work order `status` ∈ open, closed · outage `reason` = gearbox.

**Business rules:** only `quality = 'valid'` readings count as produced energy. `review_flag = 1` marks readings that are invalid or have zero energy. Energy is in **watt-hours**.

**Example questions**

| # | Level | Question |
|---|---|---|
| 1 | 🟢 | How many turbines does each site have? |
| 2 | 🟢 | How many readings are invalid? |
| 3 | 🟢 | What is the total installed capacity in kW? |
| 4 | 🟡 | What is the total valid energy in Wh per region? |
| 5 | 🟡 | Which wind farms have the highest maintenance cost, in dollars? |
| 6 | 🟡 | How many outage minutes did each site have? |
| 7 | 🟡 | How many open versus closed work orders does each crew have? |
| 8 | 🔴 | What is the valid energy per kW of installed capacity, by site? |
| 9 | 🔴 | Which turbines have outages but no valid readings? |
| 10 | 🔴 | Rank sites by maintenance cost per outage minute. |

---

## 4. Omnichannel retail — MySQL

**What it is:** a retailer with warehouses, inventory, orders with discounted line items, returns with refunds, and card or wallet payments. It is the richest money model in the pack.

**Open it:** source **Omnichannel retail (MySQL)**.

**Tables**

| Table | Rows | Key columns | Links to |
|---|---|---|---|
| `customers` | 20 | `customer_code`, `segment`, `province` | — |
| `products` | 20 | `sku`, `category`, `price_cents`, `cost_cents` | — |
| `warehouses` | 4 | `name`, `latitude`, `longitude` | — |
| `inventory` | 80 | `on_hand`, `reserved` | `warehouse_id → warehouses`, `product_id → products` |
| `orders` | 120 | `ordered_on`, `status`, `review_flag` | `customer_id → customers` |
| `order_lines` | 240 | `quantity`, `unit_cents`, `discount_cents` | `order_id → orders`, `product_id → products` |
| `returns` | 11 | `returned_on`, `quantity`, `refund_cents` | `line_id → order_lines` |
| `payments` | 192 | `paid_on`, `amount_cents`, `method` | `order_id → orders` |

**Values:** `status` ∈ completed, pending, cancelled · `segment` ∈ business, consumer · `province` ∈ BC, ON, QC · `category` ∈ electronics, home, outdoors · `method` ∈ card, wallet.

**Business rules:** line revenue = `quantity × unit_cents − discount_cents`. Net sales subtract refunds. Only completed orders are paid. Cost exists here (`cost_cents`), so margin questions work. Lines, returns and payments are independent child tables, so pre-aggregate each one before joining.

**Example questions**

| # | Level | Question |
|---|---|---|
| 1 | 🟢 | How many orders are in each status? |
| 2 | 🟢 | How much was paid by card versus wallet, in dollars? |
| 3 | 🟢 | Which products have fewer than 10 units on hand in any warehouse? |
| 4 | 🟡 | What is net completed sales by product category, after discounts and refunds? |
| 5 | 🟡 | Which province generates the most completed-order revenue? |
| 6 | 🟡 | How many units are available (on hand minus reserved) per warehouse? |
| 7 | 🟡 | Which products were returned most often? |
| 8 | 🔴 | Which completed orders have charges that don't match their payments? |
| 9 | 🔴 | What is the gross margin by category: net sales minus quantity × cost? |
| 10 | 🔴 | What is the refund rate (refunds ÷ sales) by customer segment? |

---

## 5. Cold-chain freight — MariaDB

**What it is:** a refrigerated freight carrier. Shipments travel between depots in legs, each leg has a vehicle, a driver and temperature scans, and each shipment is invoiced with a fuel surcharge.

**Open it:** source **Cold-chain freight (MariaDB)**.

**Tables**

| Table | Rows | Key columns | Links to |
|---|---|---|---|
| `depots` | 4 | `name`, `latitude`, `longitude` | — |
| `vehicles` | 12 | `registration`, `capacity_kg` | — |
| `drivers` | 12 | `driver_code` | `home_depot_id → depots` |
| `shipments` | 120 | `promised_on`, `delivered_on`, `weight_kg`, `status`, `late_flag` | `origin_id`, `destination_id → depots` |
| `legs` | 240 | `distance_km` | `shipment_id → shipments`, `vehicle_id → vehicles`, `driver_id → drivers` |
| `temperature_scans` | 720 | `observed_on`, `temperature_c` | `leg_id → legs` |
| `invoices` | 120 | `billed_cents`, `fuel_cents` | `shipment_id → shipments` |

**Values:** `status` ∈ delivered, in_transit · shipments from 2026-01-02 to 2026-05-01.

**Business rules:** a delivery is **late** when `delivered_on > promised_on`. `late_flag` is that rule frozen at migration. A **cold-chain breach** is any scan above **8 °C**. Shipments have two legs, and each leg has three scans, so pre-aggregate before joining.

**Example questions**

| # | Level | Question |
|---|---|---|
| 1 | 🟢 | How many shipments are delivered versus in transit? |
| 2 | 🟢 | What is the highest temperature ever recorded? |
| 3 | 🟢 | How many shipments are flagged late? |
| 4 | 🟡 | How many deliveries were late, by origin depot? |
| 5 | 🟡 | What is the total distance driven by each driver? |
| 6 | 🟡 | What is the average invoice, in dollars, per destination depot? |
| 7 | 🟡 | Which vehicles covered the most kilometres? |
| 8 | 🔴 | Which shipments had a temperature above 8 °C on any leg? |
| 9 | 🔴 | What share of each depot's shipments had a cold-chain breach? |
| 10 | 🔴 | What is revenue per kilometre (billed + fuel) by origin–destination lane? |

---

## 6. Outpatient billing — SQL Server

**What it is:** outpatient clinics. Patients book appointments with clinicians, attended visits produce claim lines for procedures, and payers remit payments or recoup them.

**Open it:** source **Outpatient billing (SQL Server)**. Schema `dbo`. SQL Server has no read-only transaction mode, so the reader account only has `SELECT` rights.

**Tables**

| Table | Rows | Key columns | Links to |
|---|---|---|---|
| `clinics` | 4 | `name`, `region` | — |
| `patients` | 20 | `patient_token`, `birth_year` | — |
| `clinicians` | 20 | `specialty` | `clinic_id → clinics` |
| `procedures` | 5 | `procedure_code`, `fee_cents` | — |
| `appointments` | 120 | `scheduled_on`, `status`, `no_show_flag` | `patient_id → patients`, `clinician_id → clinicians` |
| `claim_lines` | 99 | `billed_cents`, `allowed_cents` | `appointment_id → appointments`, `procedure_id → procedures` |
| `remittances` | 110 | `paid_on`, `amount_cents`, `reason` | `claim_line_id → claim_lines` |

**Values:** `status` ∈ attended, cancelled, no_show · `specialty` ∈ general, physio · `reason` ∈ payment, recoupment · `region` ∈ R1–R4.

**Business rules:** **receivable** = allowed − remitted payments, where recoupments are negative amounts. Billed is what the clinic asked for; allowed is what the payer accepts. Patients are anonymized tokens and there are no names.

**Example questions**

| # | Level | Question |
|---|---|---|
| 1 | 🟢 | How many appointments are in each status? |
| 2 | 🟢 | How many clinicians work in each specialty? |
| 3 | 🟢 | What is the fee of each procedure, in dollars? |
| 4 | 🟡 | How many no-shows were there by clinician specialty? |
| 5 | 🟡 | What is the total billed versus allowed amount by procedure? |
| 6 | 🟡 | Which clinic had the most attended appointments? |
| 7 | 🟡 | How much was recouped in total, in dollars? |
| 8 | 🔴 | What are allowed receivables after payments and recoupments, by clinic? |
| 9 | 🔴 | What is the no-show rate per clinic as a percentage of scheduled appointments? |
| 10 | 🔴 | Which procedures have the largest gap between billed and allowed, as a percentage? |

---

## 7. Airport operations — Oracle

**What it is:** an airline's operations across four Canadian airports (YUL, YYZ, YVR, YQB): routes, flights with passengers and delays, gate turnarounds, disruptions and crew assignments.

**Open it:** source **Airport operations (Oracle)**. Schema `QW_COMPLEX`, reader `QW_READER`.

**Tables**

| Table | Rows | Key columns | Links to |
|---|---|---|---|
| `airports` | 4 | `iata`, `latitude`, `longitude` | — |
| `aircraft` | 10 | `tail_number`, `seats` | — |
| `routes` | 4 | `distance_km` | `origin_id`, `destination_id → airports` |
| `gates` | 4 | `gate_code` | `airport_id → airports` |
| `flights` | 120 | `departed_on`, `status`, `passengers`, `delay_minutes`, `delay_flag` | `route_id → routes`, `aircraft_id → aircraft` |
| `turnarounds` | 111 | `ground_minutes`, `target_minutes` | `flight_id → flights`, `gate_id → gates` |
| `disruptions` | 17 | `reason`, `cost_cents` | `flight_id → flights` |
| `crew_assignments` | 240 | `crew_code`, `role_code` | `flight_id → flights` |

**Values:** `status` ∈ departed, cancelled · `role_code` ∈ pilot, copilot · disruption `reason` = weather.

**Business rules:** a flight is **delayed** at **15 minutes or more** (`delay_flag`). Load factor = passengers ÷ aircraft seats. A turnaround **misses target** when `ground_minutes > target_minutes`. Every flight has two crew assignments, so count flights with `DISTINCT`.

**Example questions**

| # | Level | Question |
|---|---|---|
| 1 | 🟢 | How many flights departed versus were cancelled? |
| 2 | 🟢 | Which aircraft has the most seats? |
| 3 | 🟢 | How many flights were delayed 15 minutes or more? |
| 4 | 🟡 | Which routes carried the most passengers? |
| 5 | 🟡 | What is the average ground time and number of missed targets per origin airport? |
| 6 | 🟡 | What is the total disruption cost, in dollars, by reason? |
| 7 | 🟡 | Which aircraft flew the most flights? |
| 8 | 🔴 | What is the average load factor (passengers ÷ seats) by route, for departed flights? |
| 9 | 🔴 | What share of flights were delayed 15+ minutes, by origin airport? |
| 10 | 🔴 | Rank routes by passenger-kilometres (passengers × distance). |

---

## 8. Property insurance — Db2

**What it is:** a property insurer. Policyholders have policies with fire and water coverages. Claims carry **reserve changes** (deltas), payments and recoveries. This is the hardest model in the pack.

**Open it:** source **Property insurance (Db2)**. Schema `DB2INST1`, reader OS account `qwreader`. Db2 uses the generic SQL dialect and has **no 3-second timeout**.

**Tables**

| Table | Rows | Key columns | Links to |
|---|---|---|---|
| `policyholders` | 20 | `holder_code`, `region` | — |
| `policies` | 20 | `policy_number`, `starts_on`, `ends_on`, `premium_cents` | `holder_id → policyholders` |
| `coverages` | 40 | `peril`, `limit_cents`, `deductible_cents` | `policy_id → policies` |
| `claims` | 120 | `loss_on`, `status`, `reported_cents`, `large_loss_flag` | `coverage_id → coverages` |
| `reserve_changes` | 220 | `posted_on`, `delta_cents` | `claim_id → claims` |
| `claim_payments` | 110 | `posted_on`, `amount_cents` | `claim_id → claims` |
| `recoveries` | 19 | `posted_on`, `amount_cents` | `claim_id → claims` |

**Values:** `peril` ∈ fire, water · `status` ∈ open, closed, denied · `region` ∈ east, west.

**Business rules:**
- `reserve_changes` stores **deltas**. The current reserve is `SUM(delta_cents)` per claim. Never sum reserve snapshots.
- **Net incurred** = paid + remaining reserve − recoveries.
- A large loss is `reported_cents ≥ 210,000` ($2,100).
- A closed claim should have a zero reserve.
- Each child table (reserves, payments, recoveries) must be aggregated per claim **before** joining.

**Example questions**

| # | Level | Question |
|---|---|---|
| 1 | 🟢 | How many claims are open, closed and denied? |
| 2 | 🟢 | How many claims are flagged as large losses? |
| 3 | 🟢 | What is the total premium, in dollars, by region? |
| 4 | 🟡 | How many claims were reported per peril? |
| 5 | 🟡 | What is the total paid on claims, in dollars, by peril? |
| 6 | 🟡 | Which policyholders have the most claims? |
| 7 | 🟡 | What is the average deductible per peril? |
| 8 | 🔴 | What is net incurred loss by peril: paid + remaining reserve − recoveries? |
| 9 | 🔴 | Which closed claims still carry a non-zero reserve? *(Expected answer: none.)* |
| 10 | 🔴 | What is the loss ratio (net incurred ÷ premium) by region? |

---

## 9. Online learning — MongoDB

**What it is:** an online course platform. Learners enroll in courses (which embed their lessons) and submit graded attempts.

**Open it:** source **Online learning (MongoDB)**. Database `qw_complex_learning`, reader `qw_app`.

**Collections**

| Collection | Docs | Fields |
|---|---|---|
| `courses` | 6 | `_id`, `title`, `category`, `lessons` (array: lesson_id, title, duration_minutes) |
| `learners` | 30 | `_id`, `learner_code`, `profile` (object: country, language) |
| `enrollments` | 120 | `_id`, `learner_id`, `course_id`, `cohort`, `status`, `duration_seconds`, `learning_minutes`, `schema_version` |
| `attempts` | 240 | `_id`, `enrollment_id`, `lesson_id`, `score` (may be null), `submitted_on` |

**Values:** `status` ∈ active, cancelled · `category` ∈ data, cloud, backend.

**How Querywise handles MongoDB (read this first):** your question is turned into SQL, then **translated into a MongoDB aggregation** on **one collection**. What works and what doesn't:

- **Works:** WHERE filters, GROUP BY, COUNT/SUM/AVG/MIN/MAX, ROUND, ORDER BY and LIMIT, on top-level fields.
- **Doesn't work:** joins between collections, subqueries, HAVING, and reaching into the `lessons` array or the `profile` object.

A question that needs two collections, such as "course titles with their average score", is refused with a clear message.

**Business rules:** `learning_minutes = duration_seconds / 60`. A null `score` means "not graded", not zero.

**Example questions**

| # | Level | Question |
|---|---|---|
| 1 | 🟢 | How many enrollments are active versus cancelled? |
| 2 | 🟢 | How many courses are in each category? |
| 3 | 🟢 | How many attempts have no score? |
| 4 | 🟡 | What are the total learning minutes per course, for active enrollments? |
| 5 | 🟡 | What is the average score per lesson, ignoring missing scores? |
| 6 | 🟡 | Which cohorts have the most enrollments? |

Not possible here (a join is needed): *"Which course titles have the best average score?"* Ask per `course_id` or per `lesson_id` instead.

---

## 10. Service reliability — Elasticsearch

**What it is:** observability data for three services (api, worker, gateway): request logs, deployments and incidents. The requests index went through a v1 → v2 upgrade that added `latency_seconds`.

**Open it:** source **Service reliability (Elasticsearch)**. The reader `qw_reader` only sees the four indices below.

**Indices**

| Index / alias | Docs | Fields |
|---|---|---|
| `qw-complex-reliability-requests` (alias → v2) | 120 | `event_id`, `service`, `environment`, `observed_at`, `duration_ms`, `latency_seconds`, `status_code`, `trace_id`, `deployment_id`, `location.lat/lon` |
| `qw-complex-reliability-requests-v2` | 120 | same as above |
| `qw-complex-reliability-deployments-v1` | 12 | `deployment_id`, `service`, `version`, `observed_at`, `result` |
| `qw-complex-reliability-incidents-v1` | 12 | `incident_id`, `service`, `severity`, `observed_at`, `recovery_minutes` (may be null) |

**Values:** `service` ∈ api, worker, gateway · `environment` ∈ production, staging · `status_code` ∈ 200, 500 · `result` ∈ successful, failed · `severity` ∈ sev1, sev2 · September 2026.

**How Querywise handles Elasticsearch:** queries run through the **Elasticsearch SQL API**, one index or alias per query. There are no joins, nested fields or percentiles. Index names contain dashes and must be double-quoted in SQL; Claude does this for you.

**Example questions**

| # | Level | Question |
|---|---|---|
| 1 | 🟢 | How many requests did each service handle? |
| 2 | 🟢 | How many incidents are sev1 versus sev2? |
| 3 | 🟢 | How many deployments failed? |
| 4 | 🟡 | How many 500 errors did each service return in production? |
| 5 | 🟡 | What is the average and maximum latency in seconds per service? |
| 6 | 🟡 | What is the average recovery time in minutes per service, for incidents that recovered? |

Not possible here (needs two indices): *"Which deployments were followed by errors?"*

---

## 11. Nonprofit grants — Excel / CSV

**What it is:** a grant-making nonprofit. Donors fund awards to programs, awards are paid out as disbursements, and grantees report milestones.

**Open it:** source **Nonprofit grants (CSV fixtures)**, folder `pack/excel/fixtures`. Each CSV file (or each Excel sheet) is one table, and the first row holds the column names.

**Tables**

| Table | Rows | Key columns | Links to (by convention, not enforced) |
|---|---|---|---|
| `donors` | 12 | `name`, `country` | — |
| `programs` | 4 | `name`, `region` | — |
| `awards` | 120 | `awarded_on`, `committed_cents`, `status` | `donor_id → donors`, `program_id → programs` |
| `disbursements` | 222 | `posted_on`, `amount_cents`, `category` | `award_id → awards` |
| `milestones` | 120 | `label`, `due_on`, `completed_on` (empty = outstanding) | `award_id → awards` |

**Values:** programs are Literacy, Food access, Water and Youth · `region` ∈ East, West · `status` ∈ approved, cancelled · `category` ∈ equipment, training · `country` ∈ CA, TN, FR.

**Business rules:** remaining commitment = committed − disbursed for approved awards, and zero for cancelled ones. An empty `completed_on` means the milestone is outstanding. Spreadsheets declare no foreign keys, so Claude joins on the `_id` columns by name.

**Example questions**

| # | Level | Question |
|---|---|---|
| 1 | 🟢 | How many awards are approved versus cancelled? |
| 2 | 🟢 | How many milestones are still outstanding? |
| 3 | 🟢 | What is the total disbursed, in dollars, by category? |
| 4 | 🟡 | What is the total committed funding per program? |
| 5 | 🟡 | Which donors committed the most, in dollars? |
| 6 | 🟡 | How much was disbursed per program region? |
| 7 | 🔴 | What is the remaining approved funding per program (committed minus disbursed)? |
| 8 | 🔴 | Which approved awards have no disbursements yet? |

---

## 12. Environmental sensors — Parquet

**What it is:** temperature sensors at four sites, with daily readings, sensor calibration offsets, and a v2 upgrade that adds a quality classification and a flattened analytics file.

**Open it:** source **Environmental sensors (Parquet)**, folder `pack/output/sensors/v2`. Each `.parquet` file is loaded as a table.

**Tables**

| Table | Rows | Key columns |
|---|---|---|
| `analytics_readings` | 1,200 | `observed_on`, `temperature_c`, `quality`, `calibrated_c`, `sensor_id`, `site_id`, `region`, `latitude`, `longitude` *(all joins already done)* |
| `readings` | 1,200 | `sensor_id`, `observed_on`, `temperature_c`, `quality` |
| `sensors` | 12 | `site_id`, `serial`, `unit` |
| `sites` | 4 | `region`, `latitude`, `longitude` |
| `calibrations` | 12 | `sensor_id`, `calibrated_on`, `offset_c` |

**Values:** `quality` ∈ valid, outlier, missing · `region` ∈ north, south · readings from January to April 2026.

**Business rules:**
- `quality`: **missing** when there is no value, **outlier** below −5 °C or above 30 °C, otherwise **valid**.
- `calibrated_c = temperature_c + offset_c`.
- Missing readings are NULL, not zero.

`analytics_readings` is the easiest table to query because nothing needs joining.

**Example questions**

| # | Level | Question |
|---|---|---|
| 1 | 🟢 | How many readings are valid, outlier and missing? |
| 2 | 🟢 | How many sensors does each site have? |
| 3 | 🟢 | What is the lowest and highest temperature recorded? |
| 4 | 🟡 | What is the average calibrated temperature by region and month? *(Try **Line** with two regions, or **Heatmap**.)* |
| 5 | 🟡 | What fraction of readings are missing per sensor? |
| 6 | 🟡 | Where are outliers concentrated, by site? |
| 7 | 🔴 | What is the daily average valid temperature per region, and how many days exceeded 25 °C? |
| 8 | 🔴 | Which sensors have the largest gap between raw and calibrated averages? |

---

## Large history databases (13 and 14): before you start

These two databases are built to test Querywise on long history and real volume: 40 tables each, millions of rows, every date between 1999-01-01 and the day you run the script. Values are random but consistent: a child row never predates its parent (no call before the subscription starts, no claim outside the policy period), and natural keys such as phone numbers, IBANs, ICCIDs, IMEIs, VINs, e-mails and document numbers are unique and enforced. A fixed random seed means a re-run produces nearly the same data.

**Querywise limits that matter here:** every query has a **3-second** timeout, returns at most **500 rows**, and may use at most **6 joins**. Totals over a whole fact table usually fit. If a question times out, narrow it to a date range ("…in 2024", "…since 2020"), a country or a segment, or group at a coarser level (year rather than day).

**Fastest way to run them: Docker.** `scripts/bigdb.ps1` starts Querywise with both databases already registered as sources. The app image includes the Oracle driver, and each database fills itself on first start.

```powershell
.\scripts\bigdb.ps1 up                                   # build if needed and start; open http://localhost:8000
.\scripts\bigdb.ps1 push -Registry docker.io/<user>      # push the 3 images to your registry (docker login first)
.\scripts\bigdb.ps1 up -Pull -Registry docker.io/<user>  # run the pushed images on another machine
.\scripts\bigdb.ps1 down                                 # stop; data is kept (-Purge deletes it)
```

The first start generates the data: about 7 minutes for PostgreSQL and 20 for Oracle. Follow progress with `docker logs -f bigdb-oracle`. Add `-Scale 0.05` for a quick small copy. Passwords are created in `sample-databases/.env.bigdb`, which git ignores and which is never copied into an image. Port 8000 must be free, so stop the live test stack first.

**Money is not in cents here, and it is in more than one currency.** Each section says which columns are in which currency. Don't add amounts in different currencies together. Ask per currency, or convert with the exchange-rate table.

---

## 13. Telecom & supply chain — PostgreSQL (large)

**What it is:** a mobile operator in 30 countries and its procurement side. Customers hold subscriptions on phone numbers with SIM cards and devices. They make calls, send SMS, use mobile data and roam abroad. They're billed monthly in their local currency, pay invoices, open support tickets and port numbers between carriers. Meanwhile, procurement buys from suppliers under contracts, receives goods into warehouses and pays supplier invoices.

**Load it:** the script is `sample-databases/postgres_telecom_supply.sql`. Create an empty database and run it with psql; it creates everything in schema `telecom` and replaces that schema if it exists. At scale 1 it takes about 7 minutes and 2.1 GB.

```powershell
createdb telecom_db
psql -v ON_ERROR_STOP=1 -d telecom_db -f sample-databases\postgres_telecom_supply.sql
```

To change the size, edit `SET telecom.scale = '1';` at the top of the script.

**Open it:** **Settings → Data sources → Add**, kind **PostgreSQL**, your connection details, schema **`telecom`**. Use a login that can only `SELECT`.

**Tables** (row counts at scale 1)

| Area | Table | Rows | Key columns | Links to |
|---|---|---|---|---|
| Reference | `currencies` | 22 | `currency_code`, `minor_units` | — |
| | `countries` | 30 | `iso_code`, `dial_code`, `region`, `vat_rate` | `currency_code → currencies` |
| | `cities` | 150 | `name`, `population` | `country_id → countries` |
| | `exchange_rates` | 152,229 | `rate_date`, `units_per_usd` (business days only) | `currency_code → currencies` |
| Staff | `employees` | 2,500 | `department`, `job_title`, `hired_on`, `terminated_on`, `salary_usd` | `manager_id → employees`, `country_id → countries` |
| Network | `carriers` | 20 | `name`, `mcc_mnc`, `carrier_type` | `home_country_id → countries` |
| | `cell_towers` | 3,000 | `technology`, `installed_on`, `decommissioned_on`, `capacity_mbps` | `city_id → cities`, `carrier_id → carriers` |
| | `number_ranges` | 210 | `prefix`, `number_type`, `allocated_on` | `country_id → countries`, `carrier_id → carriers` |
| | `phone_numbers` | 400,000 | `e164` (unique), `status`, `is_golden` | `range_id → number_ranges` |
| | `device_models` | 108 | `brand`, `model_name`, `operating_system`, `network_gen`, `released_on` | — |
| Customers | `customers` | 120,000 | `customer_type`, `segment`, `email`, `national_id`, `created_on`, `closed_on` | `country_id → countries` |
| | `customer_addresses` | 160,000 | `address_type`, `valid_from`, `valid_to` | `customer_id → customers`, `city_id → cities` |
| | `tariff_plans` | 48 | `plan_type`, `monthly_fee_usd`, included minutes / SMS / data, `launched_on`, `retired_on` | — |
| | `subscriptions` | 199,627 | `start_date`, `end_date` (NULL = still active), `status`, `sales_channel` | `customer_id → customers`, `phone_number_id → phone_numbers`, `plan_id → tariff_plans` |
| | `sim_cards` | 229,569 | `iccid`, `imsi` (unique), `sim_type`, `activated_on` | `subscription_id → subscriptions` |
| | `devices` | 180,000 | `imei` (unique), `purchased_on`, `purchase_price_usd`, `status` | `customer_id → customers`, `model_id → device_models` |
| Usage | `call_records` | 2,495,429 | `started_at`, `duration_sec`, `direction`, `call_type`, `charge_usd` | `subscription_id → subscriptions`, `tower_id → cell_towers` |
| | `sms_records` | 1,197,687 | `sent_at`, `direction`, `segments`, `delivery_status`, `charge_usd` | `subscription_id → subscriptions` |
| | `data_sessions` | 1,197,430 | `started_at`, `technology`, `mb_used`, `charge_usd` | `subscription_id → subscriptions`, `tower_id → cell_towers` |
| Billing | `invoices` | 670,852 | `invoice_no`, `billing_period`, `issued_on`, `due_on`, `currency_code`, `subtotal`, `tax_amount`, `total_amount`, `status` | `subscription_id → subscriptions` |
| | `invoice_lines` | 1,732,820 | `line_type`, `quantity`, `unit_price`, `amount` | `invoice_id → invoices` |
| | `payments` | 630,757 | `paid_on`, `amount`, `method`, `reference` | `invoice_id → invoices` |
| Care | `support_tickets` | 90,000 | `channel`, `category`, `priority`, `opened_at`, `closed_at`, `status`, `satisfaction` | `customer_id → customers`, `assigned_employee_id → employees` |
| | `ticket_events` | 300,000 | `event_seq`, `event_at`, `event_type` | `ticket_id → support_tickets`, `employee_id → employees` |
| | `port_requests` | 25,000 | `port_ref`, `direction`, `requested_on`, `completed_on`, `status` | `phone_number_id → phone_numbers`, `from_carrier_id` / `to_carrier_id → carriers` |
| Roaming | `roaming_partners` | 150 | agreement dates, `rate_per_min_usd`, `rate_per_mb_usd` | `home_carrier_id` / `visited_carrier_id → carriers` |
| | `roaming_events` | 249,536 | `event_date`, `minutes_used`, `sms_sent`, `mb_used`, `charge_usd` | `subscription_id → subscriptions`, `partner_id → roaming_partners` |
| Suppliers | `suppliers` | 1,500 | `name`, `vat_number`, `category`, `onboarded_on`, `offboarded_on`, `rating`, `payment_terms_days` | `country_id → countries`, `city_id → cities` |
| | `supplier_contacts` | 4,500 | `full_name`, `role`, `email`, `is_primary` | `supplier_id → suppliers` |
| | `supplier_contracts` | 6,000 | `contract_no`, `contract_type`, `start_date`, `end_date`, `annual_value_usd`, `status` | `supplier_id → suppliers`, `signed_by_employee_id → employees` |
| | `product_categories` | 24 | `name` (6 parents, 18 leaf categories) | `parent_id → product_categories` |
| | `products` | 4,000 | `sku`, `name`, `unit_of_measure`, `standard_cost_usd`, `introduced_on` | `category_id → product_categories` |
| | `supplier_products` | 15,000 | `supplier_sku`, `unit_price_usd`, `lead_time_days`, `min_order_qty` | `supplier_id → suppliers`, `product_id → products` |
| Procurement | `warehouses` | 30 | `code`, `capacity_m3`, `opened_on` | `city_id → cities` |
| | `purchase_orders` | 80,000 | `po_number`, `order_date`, `expected_date`, `status`, `total_amount` | `supplier_id → suppliers`, `warehouse_id → warehouses`, `buyer_employee_id → employees` |
| | `purchase_order_lines` | 320,000 | `line_no`, `quantity`, `unit_price_usd`, `line_amount` | `po_id → purchase_orders`, `product_id → products` |
| | `goods_receipts` | 76,037 | `receipt_no`, `received_on`, `condition` | `po_id → purchase_orders`, `warehouse_id → warehouses`, `received_by_employee_id → employees` |
| | `supplier_invoices` | 76,037 | `invoice_ref`, `invoice_date`, `due_date`, `amount_usd`, `status` | `supplier_id → suppliers`, `po_id → purchase_orders` |
| | `supplier_payments` | 73,634 | `paid_on`, `amount_usd`, `method`, `bank_reference` | `supplier_invoice_id → supplier_invoices` |
| | `inventory_movements` | 500,000 | `movement_type`, `quantity` (negative = out), `unit_cost_usd`, `moved_at` | `product_id → products`, `warehouse_id → warehouses`, `receipt_id → goods_receipts` |

**Values:**
- `customer_type` ∈ consumer, business · `segment` ∈ prepaid, postpaid, sme, enterprise.
- Subscription `status` ∈ active, suspended, terminated · `sales_channel` ∈ retail_store, online, call_center, partner, door_to_door.
- `call_type` ∈ local, national, international, voicemail · `direction` ∈ outgoing, incoming · `technology` ∈ 2G, 3G, 4G, 5G.
- Invoice `status` ∈ paid, open, overdue, written_off · invoice `line_type` ∈ plan_fee, voice_usage, data_usage, roaming, device_installment, value_added_service.
- Payment `method` ∈ cheque, cash, bank_transfer, card, direct_debit, mobile_wallet.
- Ticket `category` ∈ billing, network_coverage, device, sim_activation, porting, roaming, plan_change, complaint · `priority` ∈ low, medium, high, critical.
- Purchase order `status` ∈ draft, approved, sent, received, closed, cancelled · `movement_type` ∈ receipt, issue, transfer_in, transfer_out, adjustment, return.

**Business rules:**
- **Currencies:** usage charges (`charge_usd`), plan fees, device prices and the whole procurement side are in **USD**. Invoices, invoice lines and customer payments are in the **customer's local currency** (`invoices.currency_code`, e.g. EUR, JPY, NGN). To convert, divide a local amount by `exchange_rates.units_per_usd` for that currency and date. Rates exist for business days only; USD has no rows because its rate is 1.
- A subscription is **active** when `end_date IS NULL`. A subscription's country is its customer's country, which is also its phone number's country.
- Each invoice is one subscription's one billing month (unique `subscription_id` + `billing_period`). `total_amount = subtotal + tax_amount`, and tax uses `countries.vat_rate`. An unpaid invoice is `written_off` two years after its due date.
- Incoming calls and voicemail are free (`charge_usd = 0`). Per-minute prices fall over the years and data volumes grow, so compare like with like across years.
- Mobile data starts in 2002, number porting in 2003. Technology follows the calendar: 2G until 2003, 3G until 2010, 4G from 2011, 5G from mid-2019.
- A NULL `satisfaction` means the customer didn't rate the ticket, not a score of zero.
- `inventory_movements.quantity` is signed: issues and transfers out are negative, so stock on hand = `SUM(quantity)`.
- Each received purchase order has exactly one goods receipt and one supplier invoice, and the invoice equals the order total.
- **Pre-aggregate** `invoice_lines` and `payments` per invoice, and `purchase_order_lines` per order, before joining them to anything else.

**Example questions**

| # | Level | Question |
|---|---|---|
| 1 | 🟢 | How many subscriptions are active, suspended and terminated? |
| 2 | 🟢 | How many customers joined each year since 1999? *(Try **Line**.)* |
| 3 | 🟢 | How many phone numbers are assigned, available, in quarantine or reserved? |
| 4 | 🟢 | How many cell towers of each technology were installed per year? |
| 5 | 🟡 | What is the total call revenue in USD by call type for 2025? |
| 6 | 🟡 | Which 10 countries have the most active subscriptions? |
| 7 | 🟡 | What is the average data used per session, in MB, by year? *(Shows usage growth from 2002 to now.)* |
| 8 | 🟡 | How many support tickets per category were opened in 2024, and what was their average satisfaction? |
| 9 | 🟡 | Which suppliers received the highest purchase-order value in USD over the last five years? |
| 10 | 🟡 | What share of invoices is overdue or written off, by country? |
| 11 | 🔴 | What is the monthly churn rate in 2024: subscriptions ended in the month ÷ subscriptions active at the start of the month? |
| 12 | 🔴 | Convert 2025 invoice totals to USD with the exchange rates and rank countries by billed revenue. |
| 13 | 🔴 | Which carriers lost more numbers than they gained through completed port requests, by year since 2003? |
| 14 | 🔴 | For each product category, what is the current stock on hand per warehouse, and which warehouses hold negative stock? |
| 15 | 🔴 | What is the average number of days between a goods receipt and the supplier payment, by supplier country? |

---

## 14. Banking & insurance — Oracle (large)

**What it is:** a bancassurance group: a bank in 14 countries (Europe, North Africa, the Gulf) that also sells insurance through its branches and agents. Banking covers branches, customers, KYC documents, credit scores, IBAN accounts with a full transaction ledger, transfers, standing orders, cards, card payments at merchants, ATM withdrawals, fraud alerts, and loans with amortization schedules and repayments. Insurance covers products, agents, policies with coverages, beneficiaries, insured vehicles and properties, premium payments, claims with documents and payments, reinsurance treaties and an audit log.

**Load it:** the script is `sample-databases/oracle_bank_insurance.sql`. Run it as the schema owner of a dedicated schema; it drops and recreates its 40 tables. At scale 1 it takes about 15 minutes and 2 GB; allow 3 GB of tablespace. Oracle Database Free's 12 GB user-data limit is enough.

```powershell
sqlplus bank/<password>@//localhost:1521/FREEPDB1 "@sample-databases\oracle_bank_insurance.sql"
```

To change the size, edit `c_scale CONSTANT NUMBER := 1;` near the top of the script. SQLcl and SQL Developer's **Run Script** (F5) also work.

**Open it:** **Settings → Data sources → Add**, kind **Oracle**, your connection details, schema = the user you loaded it into. A separate reader account with `SELECT` grants is safer than the owner.

**Tables** (row counts at scale 1)

| Area | Table | Rows | Key columns | Links to |
|---|---|---|---|---|
| Reference | `currencies` | 22 | `currency_code`, `minor_units` | — |
| | `countries` | 30 | `iso_code`, `region`, `iban_length`, `is_bank_market` (Y for 1–14) | `currency_code → currencies` |
| | `fx_rates` | 152,229 | `rate_date`, `units_per_eur` (business days only) | `currency_code → currencies` |
| Organization | `branches` | 280 | `branch_code`, `city`, `branch_type`, `opened_on` | `country_id → countries` |
| | `employees` | 3,000 | `department`, `job_title`, `hired_on`, `terminated_on`, `salary_eur` | `branch_id → branches`, `manager_id → employees` |
| Customers | `customers` | 150,000 | `customer_type`, `segment`, `risk_rating`, `tax_id`, `email`, `customer_since`, `closed_on` | `country_id → countries`, `home_branch_id → branches` |
| | `customer_addresses` | 190,000 | `address_type`, `city`, `valid_from`, `valid_to` | `customer_id → customers`, `country_id → countries` |
| | `kyc_documents` | 250,000 | `document_type`, `document_number`, `issued_on`, `expires_on`, `status` | `customer_id → customers`, `verified_by_employee_id → employees` |
| | `credit_scores` | 400,000 | `bureau`, `score_date`, `score` (300–850) | `customer_id → customers` |
| Accounts | `account_products` | 24 | `product_type`, `interest_rate`, `monthly_fee_eur`, `launched_on` | — |
| | `accounts` | 220,000 | `iban` (valid check digits), `currency_code`, `opened_on`, `closed_on`, `status`, `overdraft_limit`, `current_balance` | `customer_id → customers`, `branch_id → branches`, `product_id → account_products` |
| | `account_holders` | 253,181 | `holder_role`, `added_on` | `account_id → accounts`, `customer_id → customers` |
| | `account_transactions` | 3,057,748 | `txn_at`, `value_date`, `txn_type`, `channel`, `amount` (signed), `balance_after` | `account_id → accounts` |
| | `transfers` | 382,487 | `transfer_ref`, `beneficiary_iban`, `amount`, `transfer_type`, `initiated_at`, `executed_on`, `status` | `from_account_id` / `to_account_id → accounts` |
| | `standing_orders` | 60,000 | `amount`, `frequency`, `start_date`, `end_date`, `status` | `account_id → accounts` |
| Cards | `cards` | 200,000 | `card_token`, `pan_masked`, `card_type`, `scheme`, `issued_on`, `expires_on`, `credit_limit`, `status` | `account_id → accounts`, `customer_id → customers` |
| | `merchants` | 20,000 | `name`, `mcc`, `category`, `city`, `onboarded_on` | `country_id → countries` |
| | `card_transactions` | 2,413,700 | `txn_at`, `amount` + `currency_code` (merchant currency), `billing_amount` (account currency), `channel`, `status` | `card_id → cards`, `merchant_id → merchants` |
| | `atms` | 1,500 | `atm_code`, `model_name`, `supports_deposit`, `installed_on`, `removed_on` | `branch_id → branches` |
| | `atm_withdrawals` | 438,621 | `withdrawn_at`, `amount`, `fee`, `status` | `card_id → cards`, `atm_id → atms` |
| | `fraud_alerts` | 27,856 | `raised_at`, `rule_code`, `risk_score`, `outcome` | `card_txn_id → card_transactions`, `reviewed_by_employee_id → employees` |
| Lending | `loan_products` | 16 | `loan_type`, `min_term_months`, `max_term_months`, `rate_spread` | — |
| | `loans` | 30,000 | `loan_number`, `principal`, `annual_rate`, `term_months`, `start_date`, `maturity_date`, `status` | `customer_id`, `account_id`, `loan_product_id`, `branch_id`, `officer_employee_id` |
| | `loan_schedules` | 3,072,156 | `installment_no`, `due_date`, `principal_due`, `interest_due`, `total_due`, `balance_after` | `loan_id → loans` |
| | `loan_payments` | 1,473,836 | `paid_on`, `amount`, `days_late`, `channel` | `schedule_id → loan_schedules`, `loan_id → loans` |
| | `collaterals` | 18,921 | `collateral_type`, `appraised_value`, `appraised_on` | `loan_id → loans` |
| Insurance | `insurance_products` | 20 | `product_code`, `line_of_business`, `base_premium_eur`, `launched_on` | — |
| | `agents` | 1,200 | `agent_code`, `agent_type`, `licensed_on`, `commission_rate` | `branch_id → branches` (bancassurance agents) |
| | `policies` | 118,015 | `policy_number`, `start_date`, `end_date`, `status`, `payment_frequency`, `annual_premium`, `sum_insured`, `currency_code` | `customer_id → customers`, `product_id → insurance_products`, `agent_id → agents` |
| | `policy_coverages` | 236,032 | `coverage_code`, `coverage_limit`, `deductible`, `premium_share` | `policy_id → policies` |
| | `beneficiaries` | 35,053 | `relationship`, `share_pct` | `policy_id → policies` (life only) |
| | `insured_vehicles` | 23,496 | `vin`, `plate_number` (unique), `make`, `model_year`, `fuel_type`, `market_value` | `policy_id → policies` (auto only) |
| | `insured_properties` | 23,575 | `property_type`, `built_year`, `area_m2`, `rebuild_value` | `policy_id → policies` (home only) |
| | `premium_payments` | 1,288,304 | `due_date`, `amount`, `paid_on`, `method`, `status` | `policy_id → policies` |
| | `claims` | 59,025 | `claim_number`, `incident_date`, `reported_on`, `claimed_amount`, `approved_amount`, `status` | `policy_id → policies`, `coverage_id → policy_coverages`, `adjuster_employee_id → employees` |
| | `claim_documents` | 147,540 | `document_type`, `file_name`, `uploaded_at` | `claim_id → claims` |
| | `claim_payments` | 47,704 | `payment_reference`, `payee_type`, `paid_on`, `amount` | `claim_id → claims` |
| Reinsurance | `reinsurers` | 24 | `name`, `rating`, `partner_since` | `country_id → countries` |
| | `reinsurance_treaties` | 168 | `treaty_year`, `line_of_business`, `treaty_type`, `cession_pct`, `retention_eur` | `reinsurer_id → reinsurers` |
| Audit | `audit_log` | 500,000 | `logged_at`, `entity_type`, `entity_id`, `action` | `employee_id → employees` |

**Values:**
- `customer_type` ∈ individual, corporate · `segment` ∈ mass, affluent, private, sme, corporate · `risk_rating` ∈ low, medium, high.
- Account `product_type` ∈ checking, savings, term_deposit, business · account `status` ∈ active, dormant, frozen, closed · `holder_role` ∈ primary, joint, proxy.
- `txn_type` ∈ salary, deposit, card_settlement, withdrawal, transfer_out, transfer_in, fee, interest, closure · `transfer_type` ∈ internal, domestic, sepa, instant, swift.
- Card `card_type` ∈ debit, credit, prepaid · card `status` ∈ active, blocked, expired, closed · card transaction `status` ∈ approved, declined, reversed · `channel` ∈ magstripe, chip_pin, contactless, ecommerce, mobile_wallet.
- `loan_type` ∈ personal, auto, mortgage, business, student · loan `status` ∈ active, repaid, defaulted, written_off.
- `line_of_business` ∈ auto, home, life, health, travel, liability · policy `status` ∈ active, expired, cancelled · `payment_frequency` ∈ single, annual, semiannual, quarterly, monthly.
- Claim `status` ∈ open, under_review, approved, settled, rejected, litigation · premium `status` ∈ paid, overdue, pending, waived.

**Business rules:**
- **Currencies:** every account, loan and policy is in the **local currency of its country** (EUR, CHF, PLN, SEK, DKK, TND, MAD, AED, SAR). `fx_rates.units_per_eur` converts to euros: EUR amount = local amount ÷ rate on that date. EUR has no rows because its rate is 1. `*_eur` columns are already in euros.
- **Balances:** `accounts.current_balance = SUM(account_transactions.amount)` for that account. `balance_after` is the running balance after each entry. A closed account ends with a `closure` entry that brings it to exactly 0.
- `account_holders` lists every holder, including the primary one, which is also `accounts.customer_id`. Count customers with `DISTINCT` when joining through holders.
- Card spend means **approved** card transactions only. `amount` is in the merchant's currency and `billing_amount` is in the card account's currency, so sum `billing_amount` per account currency.
- **Loans** use annuity schedules (constant `total_due`). The outstanding principal of a loan is the `balance_after` of its last installment due on or before today. An installment due in the past with no `loan_payments` row is **in arrears**. Defaulted and written-off loans stop paying partway through.
- **Insurance:** loss ratio = claims paid ÷ premiums paid, per line and currency. Only `settled` claims have `claim_payments`, paid in one or two instalments. A claim always points to a coverage of its own policy and happens within the policy period.
- Banking interest rates follow history: high before 2009, low 2009–2015, near zero 2016 to mid-2022, higher after that.
- **Oracle SQL:** use `FETCH FIRST n ROWS ONLY` (not `LIMIT`). `DATE` columns include a time of day; use `TRUNC(txn_at)` or `EXTRACT(YEAR FROM …)` to group by day or year.

**Example questions**

| # | Level | Question |
|---|---|---|
| 1 | 🟢 | How many accounts are active, dormant, frozen and closed? |
| 2 | 🟢 | How many customers joined the bank each year since 1999? *(Try **Line**.)* |
| 3 | 🟢 | How many policies are there per line of business? |
| 4 | 🟢 | How many fraud alerts were confirmed fraud versus false positives? |
| 5 | 🟡 | What is the total current balance per currency and account product type? |
| 6 | 🟡 | How did card payments split by channel each year? *(Contactless appears in 2012.)* |
| 7 | 🟡 | Which 10 merchant categories had the most approved card transactions in 2025? |
| 8 | 🟡 | What is the average loan interest rate by start year and loan type? |
| 9 | 🟡 | How many claims were reported per coverage code in 2024, and how many were rejected? |
| 10 | 🟡 | Which branches sold the most policies through bancassurance agents? |
| 11 | 🔴 | Convert 2025 card spend to euros with the daily FX rates and rank countries by spend. |
| 12 | 🔴 | Which active loans have at least one installment due in the past with no payment, and how much is in arrears? |
| 13 | 🔴 | What is the loss ratio (claim payments ÷ paid premiums) by line of business and year since 2015, in EUR policies only? |
| 14 | 🔴 | For each customer segment, what share of customers hold both a loan and an insurance policy? |
| 15 | 🔴 | Rank branches within each country by the number of new accounts opened in 2024. |

---

## Troubleshooting

| You see | Meaning | What to do |
|---|---|---|
| "Could not switch: … connection failed" | The database is down or the credentials are wrong | Check the containers (`docker ps`), then Settings → Data sources → **Test** |
| "Query references a table outside the allowed schema" | The SQL used a table from another source | Make sure the right source is active (the strip above the question box shows it) |
| A clarification instead of a result | The question asks for data that doesn't exist, or is ambiguous | Rephrase it with a measure, a grouping and a filter from this guide |
| "Query exceeded the 3-second limit" | The query was too heavy | Add filters or group at a coarser level. On databases 13 and 14, add a date range ("in 2025") or a country |
| "A join cannot be translated for MongoDB" | The question needs two collections | Ask about one collection (see section 9) |
| "Anthropic API error (400): … workspace …" | The API key isn't scoped to a workspace | Paste your workspace ID in Settings → AI provider |
| Only the suggested chips work | No AI provider is configured | Settings → AI provider → Anthropic or Ollama |
