-- Generated for sqlserver. Single-operator lab only. See README before execution.
ALTER TABLE appointments ADD no_show_flag INTEGER NOT NULL DEFAULT 0;

UPDATE appointments SET no_show_flag=CASE WHEN status = 'no_show' THEN 1 ELSE 0 END;

CREATE INDEX ix_appointments_flag ON appointments (no_show_flag);
