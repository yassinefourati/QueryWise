-- Generated for mysql. Single-operator lab only. See README before execution.
ALTER TABLE orders ADD review_flag INTEGER NOT NULL DEFAULT 0;

UPDATE orders SET review_flag=CASE WHEN status = 'pending' THEN 1 ELSE 0 END;

CREATE INDEX ix_orders_flag ON orders (review_flag);
