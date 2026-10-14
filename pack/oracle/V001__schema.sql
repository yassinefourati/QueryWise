-- Generated for oracle. Single-operator lab only. See README before execution.
CREATE TABLE aircraft (
	id INTEGER NOT NULL, 
	tail_number VARCHAR2(32 CHAR) NOT NULL, 
	seats INTEGER NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_aircraft_0 CHECK (seats > 0), 
	CONSTRAINT uq_aircraft_0 UNIQUE (tail_number)
);

CREATE TABLE airports (
	id INTEGER NOT NULL, 
	iata VARCHAR2(32 CHAR) NOT NULL, 
	latitude NUMERIC(14, 3) NOT NULL, 
	longitude NUMERIC(14, 3) NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_airports_0 UNIQUE (iata)
);

CREATE TABLE gates (
	id INTEGER NOT NULL, 
	airport_id INTEGER NOT NULL, 
	gate_code VARCHAR2(32 CHAR) NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_gates_0 UNIQUE (airport_id, gate_code), 
	FOREIGN KEY(airport_id) REFERENCES airports (id)
);

CREATE TABLE routes (
	id INTEGER NOT NULL, 
	origin_id INTEGER NOT NULL, 
	destination_id INTEGER NOT NULL, 
	distance_km INTEGER NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_routes_0 CHECK (origin_id <> destination_id), 
	CONSTRAINT ck_routes_1 CHECK (distance_km > 0), 
	FOREIGN KEY(origin_id) REFERENCES airports (id), 
	FOREIGN KEY(destination_id) REFERENCES airports (id)
);

CREATE TABLE flights (
	id INTEGER NOT NULL, 
	route_id INTEGER NOT NULL, 
	aircraft_id INTEGER NOT NULL, 
	departed_on DATE NOT NULL, 
	status VARCHAR2(32 CHAR) NOT NULL, 
	passengers INTEGER NOT NULL, 
	delay_minutes INTEGER, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_flights_0 CHECK (passengers >= 0), 
	CONSTRAINT ck_flights_1 CHECK (status IN ('departed','cancelled')), 
	FOREIGN KEY(route_id) REFERENCES routes (id), 
	FOREIGN KEY(aircraft_id) REFERENCES aircraft (id)
);

CREATE TABLE crew_assignments (
	id INTEGER NOT NULL, 
	flight_id INTEGER NOT NULL, 
	crew_code VARCHAR2(32 CHAR) NOT NULL, 
	role_code VARCHAR2(32 CHAR) NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_crew_assignm_0 UNIQUE (flight_id, crew_code), 
	FOREIGN KEY(flight_id) REFERENCES flights (id)
);

CREATE TABLE disruptions (
	id INTEGER NOT NULL, 
	flight_id INTEGER NOT NULL, 
	reason VARCHAR2(32 CHAR) NOT NULL, 
	cost_cents NUMBER(19) NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_disruptions_0 CHECK (cost_cents >= 0), 
	FOREIGN KEY(flight_id) REFERENCES flights (id)
);

CREATE TABLE turnarounds (
	id INTEGER NOT NULL, 
	flight_id INTEGER NOT NULL, 
	gate_id INTEGER NOT NULL, 
	ground_minutes INTEGER NOT NULL, 
	target_minutes INTEGER NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_turnarounds_0 CHECK (ground_minutes >= 0), 
	CONSTRAINT ck_turnarounds_1 CHECK (target_minutes > 0), 
	CONSTRAINT uq_turnarounds_0 UNIQUE (flight_id), 
	FOREIGN KEY(flight_id) REFERENCES flights (id), 
	FOREIGN KEY(gate_id) REFERENCES gates (id)
);

CREATE INDEX ix_gates_airport_id ON gates (airport_id);

CREATE INDEX ix_routes_destination_ ON routes (destination_id);

CREATE INDEX ix_routes_origin_id ON routes (origin_id);

CREATE INDEX ix_flights_aircraft_id ON flights (aircraft_id);

CREATE INDEX ix_flights_route_id ON flights (route_id);

CREATE INDEX ix_crew_assignm_flight_id ON crew_assignments (flight_id);

CREATE INDEX ix_disruptions_flight_id ON disruptions (flight_id);

CREATE INDEX ix_turnarounds_gate_id ON turnarounds (gate_id);
