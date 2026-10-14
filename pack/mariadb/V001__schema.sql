-- Generated for mariadb. Single-operator lab only. See README before execution.
CREATE TABLE depots (
	id INTEGER NOT NULL, 
	name VARCHAR(120) NOT NULL, 
	latitude NUMERIC(14, 3) NOT NULL, 
	longitude NUMERIC(14, 3) NOT NULL, 
	PRIMARY KEY (id)
);

CREATE TABLE vehicles (
	id INTEGER NOT NULL, 
	registration VARCHAR(32) NOT NULL, 
	capacity_kg INTEGER NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_vehicles_0 CHECK (capacity_kg > 0), 
	CONSTRAINT uq_vehicles_0 UNIQUE (registration)
);

CREATE TABLE drivers (
	id INTEGER NOT NULL, 
	driver_code VARCHAR(32) NOT NULL, 
	home_depot_id INTEGER NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_drivers_0 UNIQUE (driver_code), 
	FOREIGN KEY(home_depot_id) REFERENCES depots (id)
);

CREATE TABLE shipments (
	id INTEGER NOT NULL, 
	origin_id INTEGER NOT NULL, 
	destination_id INTEGER NOT NULL, 
	promised_on DATE NOT NULL, 
	delivered_on DATE, 
	weight_kg INTEGER NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_shipments_0 CHECK (origin_id <> destination_id), 
	CONSTRAINT ck_shipments_1 CHECK (weight_kg > 0), 
	FOREIGN KEY(origin_id) REFERENCES depots (id), 
	FOREIGN KEY(destination_id) REFERENCES depots (id)
);

CREATE TABLE invoices (
	id INTEGER NOT NULL, 
	shipment_id INTEGER NOT NULL, 
	billed_cents BIGINT NOT NULL, 
	fuel_cents BIGINT NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_invoices_0 CHECK (billed_cents >= 0), 
	CONSTRAINT ck_invoices_1 CHECK (fuel_cents >= 0), 
	CONSTRAINT uq_invoices_0 UNIQUE (shipment_id), 
	FOREIGN KEY(shipment_id) REFERENCES shipments (id)
);

CREATE TABLE legs (
	id INTEGER NOT NULL, 
	shipment_id INTEGER NOT NULL, 
	vehicle_id INTEGER NOT NULL, 
	driver_id INTEGER NOT NULL, 
	distance_km INTEGER NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_legs_0 CHECK (distance_km > 0), 
	FOREIGN KEY(shipment_id) REFERENCES shipments (id), 
	FOREIGN KEY(vehicle_id) REFERENCES vehicles (id), 
	FOREIGN KEY(driver_id) REFERENCES drivers (id)
);

CREATE TABLE temperature_scans (
	id INTEGER NOT NULL, 
	leg_id INTEGER NOT NULL, 
	observed_on DATE NOT NULL, 
	temperature_c NUMERIC(14, 3), 
	PRIMARY KEY (id), 
	FOREIGN KEY(leg_id) REFERENCES legs (id)
);

CREATE INDEX ix_drivers_home_depot_i ON drivers (home_depot_id);

CREATE INDEX ix_shipments_destination_ ON shipments (destination_id);

CREATE INDEX ix_shipments_origin_id ON shipments (origin_id);

CREATE INDEX ix_invoices_shipment_id ON invoices (shipment_id);

CREATE INDEX ix_legs_driver_id ON legs (driver_id);

CREATE INDEX ix_legs_shipment_id ON legs (shipment_id);

CREATE INDEX ix_legs_vehicle_id ON legs (vehicle_id);

CREATE INDEX ix_temperature__leg_id ON temperature_scans (leg_id);
