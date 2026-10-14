-- cold_chain: Which shipments have a temperature above 8 C?
SELECT s.id,MAX(t.temperature_c) peak_c FROM shipments s JOIN legs l ON l.shipment_id=s.id JOIN temperature_scans t ON t.leg_id=l.id GROUP BY s.id HAVING MAX(t.temperature_c)>8 ORDER BY s.id;

-- delivery_sla: Delivered and late counts by origin depot.
SELECT d.name,COUNT(*) delivered,SUM(CASE WHEN s.delivered_on>s.promised_on THEN 1 ELSE 0 END) late FROM shipments s JOIN depots d ON d.id=s.origin_id WHERE s.delivered_on IS NOT NULL GROUP BY d.name ORDER BY d.name;

-- upgrade_flags: Count records marked by late_flag after migration.
SELECT late_flag,COUNT(*) records FROM shipments GROUP BY late_flag ORDER BY late_flag;
