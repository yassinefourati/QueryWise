# Nonprofit grant administration — Excel

Five related sheets: donors, programs, awards, disbursements and milestones. V2 adds calculated remaining_cents to awards. Cancelled awards contribute zero remaining commitment; approved awards subtract actual disbursements. CAD integer cents avoid floating money ambiguity. Empty completion dates mean outstanding milestones.

The migration script uses native Windows Excel COM, so Microsoft desktop Excel must be installed. Docker/Linux and Excel Online cannot run this script. Fixtures are CSV files with an explicit header row; the script loads IDs/money as numbers, dates as native date values, and labels as text.

```powershell
pwsh -File .\excel\migrate.ps1 -Action seed
pwsh -File .\excel\migrate.ps1 -Action migrate
pwsh -File .\excel\migrate.ps1 -Action verify
```

Outputs are output/grants/grants-v1.xlsx and grants-v2.xlsx, with SHA256 sidecars. Migration saves a new file and keeps v1 untouched. Native Excel calculates formulas before saving, so Querywise can read cached results. Recalculate/save in Excel after editing inputs; Querywise does not evaluate Excel formulas. Verification opens v2 read-only and checks each source cell, counts and calculated award balances against fixtures.

Close workbooks before migration. Do not bypass a checksum mismatch: choose a separate reviewed input workflow for edited business data. This script is intentionally limited to these controlled fixtures and their documented column positions, not arbitrary spreadsheets. Rollback means selecting the retained v1 file; no automatic replacement occurs.
