-- Generated for sqlserver. Single-operator lab only. See README before execution.
CREATE TABLE clinics (
	id INTEGER NOT NULL, 
	name VARCHAR(120) NOT NULL, 
	region VARCHAR(32) NOT NULL, 
	PRIMARY KEY (id)
);

CREATE TABLE patients (
	id INTEGER NOT NULL, 
	patient_token VARCHAR(32) NOT NULL, 
	birth_year INTEGER NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_patients_0 CHECK (birth_year BETWEEN 1900 AND 2026), 
	CONSTRAINT uq_patients_0 UNIQUE (patient_token)
);

CREATE TABLE procedures (
	id INTEGER NOT NULL, 
	procedure_code VARCHAR(32) NOT NULL, 
	fee_cents BIGINT NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_procedures_0 CHECK (fee_cents >= 0), 
	CONSTRAINT uq_procedures_0 UNIQUE (procedure_code)
);

CREATE TABLE clinicians (
	id INTEGER NOT NULL, 
	clinic_id INTEGER NOT NULL, 
	specialty VARCHAR(32) NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(clinic_id) REFERENCES clinics (id)
);

CREATE TABLE appointments (
	id INTEGER NOT NULL, 
	patient_id INTEGER NOT NULL, 
	clinician_id INTEGER NOT NULL, 
	scheduled_on DATETIME NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_appointments_0 CHECK (status IN ('attended','cancelled','no_show')), 
	FOREIGN KEY(patient_id) REFERENCES patients (id), 
	FOREIGN KEY(clinician_id) REFERENCES clinicians (id)
);

CREATE TABLE claim_lines (
	id INTEGER NOT NULL, 
	appointment_id INTEGER NOT NULL, 
	procedure_id INTEGER NOT NULL, 
	billed_cents BIGINT NOT NULL, 
	allowed_cents BIGINT NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_claim_lines_0 CHECK (billed_cents >= 0), 
	CONSTRAINT ck_claim_lines_1 CHECK (allowed_cents >= 0 AND allowed_cents <= billed_cents), 
	FOREIGN KEY(appointment_id) REFERENCES appointments (id), 
	FOREIGN KEY(procedure_id) REFERENCES procedures (id)
);

CREATE TABLE remittances (
	id INTEGER NOT NULL, 
	claim_line_id INTEGER NOT NULL, 
	paid_on DATETIME NOT NULL, 
	amount_cents BIGINT NOT NULL, 
	reason VARCHAR(32) NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(claim_line_id) REFERENCES claim_lines (id)
);

CREATE INDEX ix_clinicians_clinic_id ON clinicians (clinic_id);

CREATE INDEX ix_appointments_clinician_id ON appointments (clinician_id);

CREATE INDEX ix_appointments_patient_id ON appointments (patient_id);

CREATE INDEX ix_claim_lines_appointment_ ON claim_lines (appointment_id);

CREATE INDEX ix_claim_lines_procedure_id ON claim_lines (procedure_id);

CREATE INDEX ix_remittances_claim_line_i ON remittances (claim_line_id);
