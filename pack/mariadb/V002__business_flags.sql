-- Generated for mariadb. Single-operator lab only. See README before execution.
ALTER TABLE shipments ADD late_flag INTEGER NOT NULL DEFAULT 0;

UPDATE shipments SET late_flag=CASE WHEN delivered_on > promised_on THEN 1 ELSE 0 END;

CREATE INDEX ix_shipments_flag ON shipments (late_flag);
