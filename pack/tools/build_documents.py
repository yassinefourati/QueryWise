import json,csv
from pathlib import Path
from tools.document_fixtures import fixtures
from tools.mongo_runner import validators
from tools.elastic_runner import mapping
from tools.models import TOPICS
from tools.build_pack import write,dump,ROOT
def build():
    for kind in ['mongodb','elasticsearch','excel','parquet']:
        data=fixtures(kind)
        dump(f'{kind}/fixture.json',data)
        dump(f'{kind}/expected_counts.json',{k:len(v) for k,v in data.items()})
    for v in [1,2]:dump(f'mongodb/V{v:03}__validators.json',validators(v))
    for name in fixtures('elasticsearch'):
        dump(f'elasticsearch/{name}-v1.mapping.json',mapping(name))
    dump('elasticsearch/requests-v2.mapping.json',mapping('requests',2))
    dump('mongodb/analytics.json',{'active_minutes_by_course':[{'$match':{'status':'active'}},{'$group':{'_id':'$course_id','minutes':{'$sum':'$learning_minutes'}}},{'$sort':{'_id':1}}], 'scores_by_course':[{'$lookup':{'from':'enrollments','localField':'enrollment_id','foreignField':'_id','as':'enrollment'}},{'$unwind':'$enrollment'},{'$match':{'score':{'$ne':None}}},{'$group':{'_id':'$enrollment.course_id','average_score':{'$avg':'$score'}}}]})
    dump('elasticsearch/analytics.json',{'size':0,'query':{'term':{'environment':'production'}},'aggs':{'services':{'terms':{'field':'service','size':20},'aggs':{'p95_latency_seconds':{'percentiles':{'field':'latency_seconds','percents':[95]}},'errors':{'filter':{'range':{'status_code':{'gte':500}}}}}}}})
    for name,rows in fixtures('excel').items():
        path=ROOT/'excel/fixtures'/f'{name}.csv';path.parent.mkdir(parents=True,exist_ok=True)
        with path.open('w',newline='',encoding='utf-8-sig') as f:
            w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    for kind,module in [('mongodb','mongo_runner'),('elasticsearch','elastic_runner'),('parquet','parquet_runner')]:
        for action in ['migrate','seed','verify']:
            write(f'{kind}/{action}.py',f"import sys\nfrom pathlib import Path\nsys.path.insert(0,str(Path(__file__).resolve().parents[1]))\nfrom tools.{module} import main\nif __name__=='__main__':\n    sys.argv.insert(1,'{action}')\n    try: main()\n    except Exception as error:\n        print('FAIL ('+type(error).__name__+'); inspect locally, connection details redacted',file=sys.stderr)\n        sys.exit(1)\n")
    write('parquet/analytics.sql',"""-- Run with DuckDB, from the pack root after seed and migrate.
SELECT region,quality,COUNT(*) readings,AVG(calibrated_c) average_c
FROM read_parquet('output/sensors/v2/analytics_readings.parquet')
GROUP BY region,quality ORDER BY region,quality;

-- Daily trend. NULL temperatures stay NULL; never substitute zero degrees.
SELECT observed_on,AVG(calibrated_c) average_c,COUNT(calibrated_c) measured,
       COUNT(*) total FROM read_parquet('output/sensors/v2/analytics_readings.parquet')
GROUP BY observed_on ORDER BY observed_on;
""")
    write('mongodb/README.md', '''# Online learning — MongoDB

Four collections: courses with embedded lessons, learners with nested profiles, enrollments, and assessment attempts. Missing scores are different from a zero score. Repeated course enrollments use distinct cohorts. All learners are synthetic.

Set PACK_MONGODB_URL to a local/authenticated server URI. The scripts use only the dedicated `qw_complex_learning` database. The migrator needs collection creation, collMod, index, read and write privileges. Use a separate read-only Querywise user.

```sh
python -m tools.mongo_runner migrate --target 1 --allow-write
python -m tools.mongo_runner seed --scale 1 --allow-write
python -m tools.mongo_runner migrate --target 2 --allow-write
python -m tools.mongo_runner verify --scale 1
```

V1 creates validators and indexes. V2 adds learning_minutes, derived from duration_seconds, and moves schema_version to 2. The backfill is additive and resumable. Validators accept both versions during backfill and require v2 afterward. A persistent unique lock prevents concurrent migration jobs; inspect a stale lock after a crashed process before manually removing it. Stop application writes during this lab upgrade.

Seed uses stable IDs and setOnInsert, so an interrupted seed can resume without duplicates. Verification compares every expected document and computes active learning minutes independently. Native aggregation examples in analytics.json include lookup/unwind; Querywise v5 does NOT expose arbitrary Mongo pipelines, nested lesson arrays or cross-collection joins. Register scalar fields or build a separate flattened collection for those questions.

Forward-only. Back up before migration. Restore the dedicated database to roll back; no automatic destructive cleanup is supplied. Changing fixture scale requires a fresh database.
''')
    write('elasticsearch/README.md','''# Service reliability — Elasticsearch

Three strict-mapped indices: requests, deployments, incidents. Includes staging/production, errors, latency, trace IDs, deployment correlation, coordinates and unresolved incidents. Percentile results are approximate; use tolerances, not exact equality, for percentile tests.

Set PACK_ELASTICSEARCH_URL; optionally PACK_ELASTICSEARCH_API_KEY and PACK_ELASTICSEARCH_CA_CERT. TLS verification remains enabled. All resources use the `qw-complex-reliability-` prefix.

```sh
python -m tools.elastic_runner migrate --target 1 --allow-write
python -m tools.elastic_runner seed --scale 1 --allow-write
python -m tools.elastic_runner migrate --target 2 --allow-write
python -m tools.elastic_runner verify --scale 1
```

Pause all writers and run one migration operator. V2 creates a new requests index, synchronously reindexes with latency_seconds conversion, checks reindex errors, counts and every migrated document, then switches the read alias in one aliases request. The old index is preserved. Deployments/incidents remain v1. A failed v2 destination is deliberately not overwritten on retry. Inspect the reindex task/state, repair or remove only the dedicated failed destination, and retry after review. There is no live dual-write or CDC catch-up.

The verification scans all documents, compares exact fixtures and verifies alias ownership. This is deliberately a small lab validation, not an efficient billion-document reconciliation. Replica count 0 and one shard are local-lab settings, not production recommendations.

Rollback: pause writers, validate old index, atomically remove the requests alias from v2 and add it to v1. New v2-only writes would be lost from the read view; reconcile first. No index is deleted automatically.

analytics.json can be used as a search request against the requests alias. Querywise v5 uses restricted ES|QL plans and concrete index registration. Native percentile/full-text/nested/cross-index requests here exceed its current UI capabilities. Map latitude/longitude into scalar serving fields if your Querywise mapping discovery cannot expose geo_point fields.
''')
    write('excel/README.md',r'''# Nonprofit grant administration — Excel

Five related sheets: donors, programs, awards, disbursements and milestones. V2 adds calculated remaining_cents to awards. Cancelled awards contribute zero remaining commitment; approved awards subtract actual disbursements. CAD integer cents avoid floating money ambiguity. Empty completion dates mean outstanding milestones.

The migration script uses native Windows Excel COM, so Microsoft desktop Excel must be installed. Docker/Linux and Excel Online cannot run this script. Fixtures are CSV files with an explicit header row; the script loads IDs/money as numbers, dates as native date values, and labels as text.

```powershell
pwsh -File .\excel\migrate.ps1 -Action seed
pwsh -File .\excel\migrate.ps1 -Action migrate
pwsh -File .\excel\migrate.ps1 -Action verify
```

Outputs are output/grants/grants-v1.xlsx and grants-v2.xlsx, with SHA256 sidecars. Migration saves a new file and keeps v1 untouched. Native Excel calculates formulas before saving, so Querywise can read cached results. Recalculate/save in Excel after editing inputs; Querywise does not evaluate Excel formulas. Verification opens v2 read-only and checks each source cell, counts and calculated award balances against fixtures.

Close workbooks before migration. Do not bypass a checksum mismatch: choose a separate reviewed input workflow for edited business data. This script is intentionally limited to these controlled fixtures and their documented column positions, not arbitrary spreadsheets. Rollback means selecting the retained v1 file; no automatic replacement occurs.
''')
    write('parquet/README.md','''# Environmental sensors — Parquet

Four typed datasets: sites, sensors, readings, calibrations. Negative temperatures, zero degrees, missing samples and outliers are represented separately. Base volume is 1,200 readings; --scale 100 yields 120,000 readings.

```sh
python -m tools.parquet_runner seed --scale 1
python -m tools.parquet_runner migrate --scale 1
python -m tools.parquet_runner verify --scale 1
```

V1 writes typed, ZSTD-compressed Parquet. V2 renames value_c to temperature_c, derives quality, and builds a flattened analytics_readings.parquet with location and calibrated temperature. A missing value remains NULL; calibration is applied once. One calibration per sensor is guaranteed by these fixtures; time-varying calibrations would need effective-dated joins.

Each version contains a checksum manifest. Writes stage in the destination filesystem, then rename the completed directory. Single-writer local-filesystem workflow only; object-store atomicity is not assumed. Existing versions are never overwritten. Consumers explicitly select v1 or v2; rollback is a configuration change. No automatic pointer or schema evolution for arbitrary inputs is implied.

Verification checks source row values, version checksums, conversion, join cardinality and calibrated values. Run analytics.sql with DuckDB for daily trends and quality counts. Register the single v2 analytics file in Querywise; the app does not scan a whole data lake.
''')
if __name__=='__main__':build()
