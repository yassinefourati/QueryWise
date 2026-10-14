-- Generated for db2. Single-operator lab only. See README before execution.
ALTER TABLE claims ADD COLUMN large_loss_flag INTEGER DEFAULT 0 NOT NULL;

UPDATE claims SET large_loss_flag=CASE WHEN reported_cents >= 210000 THEN 1 ELSE 0 END;

CREATE INDEX ix_claims_flag ON claims (large_loss_flag);
