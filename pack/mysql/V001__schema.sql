-- Generated for mysql. Single-operator lab only. See README before execution.
CREATE TABLE customers (
	id INTEGER NOT NULL, 
	customer_code VARCHAR(32) NOT NULL, 
	segment VARCHAR(32) NOT NULL, 
	province VARCHAR(32) NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_customers_0 UNIQUE (customer_code)
);

CREATE TABLE products (
	id INTEGER NOT NULL, 
	sku VARCHAR(32) NOT NULL, 
	category VARCHAR(32) NOT NULL, 
	price_cents BIGINT NOT NULL, 
	cost_cents BIGINT NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_products_0 CHECK (price_cents >= 0), 
	CONSTRAINT ck_products_1 CHECK (cost_cents >= 0), 
	CONSTRAINT uq_products_0 UNIQUE (sku)
);

CREATE TABLE warehouses (
	id INTEGER NOT NULL, 
	name VARCHAR(120) NOT NULL, 
	latitude NUMERIC(14, 3) NOT NULL, 
	longitude NUMERIC(14, 3) NOT NULL, 
	PRIMARY KEY (id)
);

CREATE TABLE inventory (
	id INTEGER NOT NULL, 
	warehouse_id INTEGER NOT NULL, 
	product_id INTEGER NOT NULL, 
	on_hand INTEGER NOT NULL, 
	reserved INTEGER NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_inventory_0 CHECK (on_hand >= 0), 
	CONSTRAINT ck_inventory_1 CHECK (reserved >= 0 AND reserved <= on_hand), 
	CONSTRAINT uq_inventory_0 UNIQUE (warehouse_id, product_id), 
	FOREIGN KEY(warehouse_id) REFERENCES warehouses (id), 
	FOREIGN KEY(product_id) REFERENCES products (id)
);

CREATE TABLE orders (
	id INTEGER NOT NULL, 
	customer_id INTEGER NOT NULL, 
	ordered_on DATE NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_orders_0 CHECK (status IN ('completed','cancelled','pending')), 
	FOREIGN KEY(customer_id) REFERENCES customers (id)
);

CREATE TABLE order_lines (
	id INTEGER NOT NULL, 
	order_id INTEGER NOT NULL, 
	product_id INTEGER NOT NULL, 
	quantity INTEGER NOT NULL, 
	unit_cents BIGINT NOT NULL, 
	discount_cents BIGINT NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_order_lines_0 CHECK (quantity > 0), 
	CONSTRAINT ck_order_lines_1 CHECK (unit_cents >= 0), 
	CONSTRAINT ck_order_lines_2 CHECK (discount_cents >= 0 AND discount_cents <= quantity * unit_cents), 
	FOREIGN KEY(order_id) REFERENCES orders (id), 
	FOREIGN KEY(product_id) REFERENCES products (id)
);

CREATE TABLE payments (
	id INTEGER NOT NULL, 
	order_id INTEGER NOT NULL, 
	paid_on DATE NOT NULL, 
	amount_cents BIGINT NOT NULL, 
	method VARCHAR(32) NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_payments_0 CHECK (amount_cents > 0), 
	FOREIGN KEY(order_id) REFERENCES orders (id)
);

CREATE TABLE returns (
	id INTEGER NOT NULL, 
	line_id INTEGER NOT NULL, 
	returned_on DATE NOT NULL, 
	quantity INTEGER NOT NULL, 
	refund_cents BIGINT NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_returns_0 CHECK (quantity > 0), 
	CONSTRAINT ck_returns_1 CHECK (refund_cents >= 0), 
	FOREIGN KEY(line_id) REFERENCES order_lines (id)
);

CREATE INDEX ix_inventory_product_id ON inventory (product_id);

CREATE INDEX ix_inventory_warehouse_id ON inventory (warehouse_id);

CREATE INDEX ix_orders_customer_id ON orders (customer_id);

CREATE INDEX ix_order_lines_order_id ON order_lines (order_id);

CREATE INDEX ix_order_lines_product_id ON order_lines (product_id);

CREATE INDEX ix_payments_order_id ON payments (order_id);

CREATE INDEX ix_returns_line_id ON returns (line_id);
