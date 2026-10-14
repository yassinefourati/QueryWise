-- Generated for sqlite. Single-operator lab only. See README before execution.
ALTER TABLE loans ADD COLUMN overdue_flag INTEGER DEFAULT 0 NOT NULL;

UPDATE loans SET overdue_flag=CASE WHEN returned_on IS NULL AND due_on < '2026-10-01' THEN 1 ELSE 0 END;

CREATE INDEX ix_loans_flag ON loans (overdue_flag);
