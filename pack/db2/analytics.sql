-- incurred: Net incurred loss in cents by peril: paid + remaining reserve - recoveries.
WITH r AS (SELECT claim_id,SUM(delta_cents) cents FROM reserve_changes GROUP BY claim_id), p AS (SELECT claim_id,SUM(amount_cents) cents FROM claim_payments GROUP BY claim_id), x AS (SELECT claim_id,SUM(amount_cents) cents FROM recoveries GROUP BY claim_id) SELECT v.peril,SUM(COALESCE(p.cents,0)+COALESCE(r.cents,0)-COALESCE(x.cents,0)) incurred_cents FROM claims c JOIN coverages v ON v.id=c.coverage_id LEFT JOIN r ON r.claim_id=c.id LEFT JOIN p ON p.claim_id=c.id LEFT JOIN x ON x.claim_id=c.id WHERE c.status<>'denied' GROUP BY v.peril ORDER BY v.peril;

-- closed_reserves: Closed claims incorrectly retaining a reserve (expected empty).
SELECT c.id,SUM(r.delta_cents) remaining_cents FROM claims c JOIN reserve_changes r ON r.claim_id=c.id WHERE c.status='closed' GROUP BY c.id HAVING SUM(r.delta_cents)<>0 ORDER BY c.id;

-- upgrade_flags: Count records marked by large_loss_flag after migration.
SELECT large_loss_flag,COUNT(*) records FROM claims GROUP BY large_loss_flag ORDER BY large_loss_flag;
