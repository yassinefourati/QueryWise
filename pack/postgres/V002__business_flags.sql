-- Generated for postgres. Single-operator lab only. See README before execution.
ALTER TABLE readings ADD COLUMN review_flag INTEGER DEFAULT 0 NOT NULL;

UPDATE readings SET review_flag=CASE WHEN quality = 'invalid' OR energy_wh = 0 THEN 1 ELSE 0 END;

CREATE INDEX ix_readings_flag ON readings (review_flag);
