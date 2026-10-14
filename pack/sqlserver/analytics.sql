-- receivables: Allowed receivables after payments and recoupments by clinic.
WITH paid AS (SELECT claim_line_id,SUM(amount_cents) cents FROM remittances GROUP BY claim_line_id) SELECT c.name,SUM(l.allowed_cents-COALESCE(p.cents,0)) outstanding_cents FROM claim_lines l JOIN appointments a ON a.id=l.appointment_id JOIN clinicians d ON d.id=a.clinician_id JOIN clinics c ON c.id=d.clinic_id LEFT JOIN paid p ON p.claim_line_id=l.id GROUP BY c.name ORDER BY c.name;

-- no_shows: No-show appointments by specialty.
SELECT c.specialty,COUNT(*) appointments,SUM(CASE WHEN a.status='no_show' THEN 1 ELSE 0 END) no_shows FROM appointments a JOIN clinicians c ON c.id=a.clinician_id GROUP BY c.specialty ORDER BY c.specialty;

-- upgrade_flags: Count records marked by no_show_flag after migration.
SELECT no_show_flag,COUNT(*) records FROM appointments GROUP BY no_show_flag ORDER BY no_show_flag;
