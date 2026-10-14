-- valid_energy: Valid energy in Wh per region; exclude estimated and invalid readings.
SELECT s.region, SUM(r.energy_wh) energy_wh FROM readings r JOIN turbines t ON t.id=r.turbine_id JOIN sites s ON s.id=t.site_id WHERE r.quality='valid' GROUP BY s.region ORDER BY s.region;

-- maintenance: Which farms have the greatest maintenance cost?
SELECT s.name,SUM(w.cost_cents) cost_cents,COUNT(*) jobs FROM work_orders w JOIN outages o ON o.id=w.outage_id JOIN turbines t ON t.id=o.turbine_id JOIN sites s ON s.id=t.site_id GROUP BY s.name ORDER BY cost_cents DESC,s.name;

-- upgrade_flags: Count records marked by review_flag after migration.
SELECT review_flag,COUNT(*) records FROM readings GROUP BY review_flag ORDER BY review_flag;
