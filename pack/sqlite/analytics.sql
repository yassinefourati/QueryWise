-- outstanding_fines: What are unpaid fines by branch in cents?
WITH paid AS (SELECT fine_id, SUM(amount_cents) amount FROM fine_payments GROUP BY fine_id) SELECT b.name, SUM(f.assessed_cents-f.waived_cents-COALESCE(p.amount,0)) outstanding_cents FROM fines f JOIN loans l ON l.id=f.loan_id JOIN copies c ON c.id=l.copy_id JOIN branches b ON b.id=c.branch_id LEFT JOIN paid p ON p.fine_id=f.id GROUP BY b.name ORDER BY b.name;

-- circulation: Rank genres by loan count.
SELECT t.genre, COUNT(*) loans, DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) popularity_rank FROM loans l JOIN copies c ON c.id=l.copy_id JOIN titles t ON t.id=c.title_id GROUP BY t.genre ORDER BY loans DESC,t.genre;

-- upgrade_flags: Count records marked by overdue_flag after migration.
SELECT overdue_flag,COUNT(*) records FROM loans GROUP BY overdue_flag ORDER BY overdue_flag;
