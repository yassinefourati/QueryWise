-- Generated for oracle. Single-operator lab only. See README before execution.
ALTER TABLE flights ADD (delay_flag INTEGER DEFAULT 0 NOT NULL);

UPDATE flights SET delay_flag=CASE WHEN delay_minutes >= 15 THEN 1 ELSE 0 END;

CREATE INDEX ix_flights_flag ON flights (delay_flag);
