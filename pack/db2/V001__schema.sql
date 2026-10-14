-- Generated for db2. Single-operator lab only. See README before execution.
CREATE TABLE policyholders (
	id INT NOT NULL, 
	holder_code VARCHAR(32) NOT NULL, 
	region VARCHAR(32) NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_policyholder_0 UNIQUE (holder_code)
);

CREATE TABLE policies (
	id INT NOT NULL, 
	holder_id INT NOT NULL, 
	policy_number VARCHAR(32) NOT NULL, 
	starts_on DATE NOT NULL, 
	ends_on DATE NOT NULL, 
	premium_cents BIGINT NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_policies_0 CHECK (ends_on >= starts_on), 
	CONSTRAINT ck_policies_1 CHECK (premium_cents >= 0), 
	CONSTRAINT uq_policies_0 UNIQUE (policy_number), 
	FOREIGN KEY(holder_id) REFERENCES policyholders (id)
);

CREATE TABLE coverages (
	id INT NOT NULL, 
	policy_id INT NOT NULL, 
	peril VARCHAR(32) NOT NULL, 
	limit_cents BIGINT NOT NULL, 
	deductible_cents BIGINT NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_coverages_0 CHECK (limit_cents > 0), 
	CONSTRAINT ck_coverages_1 CHECK (deductible_cents >= 0), 
	CONSTRAINT uq_coverages_0 UNIQUE (policy_id, peril), 
	FOREIGN KEY(policy_id) REFERENCES policies (id)
);

CREATE TABLE claims (
	id INT NOT NULL, 
	coverage_id INT NOT NULL, 
	loss_on DATE NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	reported_cents BIGINT NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_claims_0 CHECK (reported_cents >= 0), 
	CONSTRAINT ck_claims_1 CHECK (status IN ('open','closed','denied')), 
	FOREIGN KEY(coverage_id) REFERENCES coverages (id)
);

CREATE TABLE claim_payments (
	id INT NOT NULL, 
	claim_id INT NOT NULL, 
	posted_on DATE NOT NULL, 
	amount_cents BIGINT NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_claim_paymen_0 CHECK (amount_cents > 0), 
	FOREIGN KEY(claim_id) REFERENCES claims (id)
);

CREATE TABLE recoveries (
	id INT NOT NULL, 
	claim_id INT NOT NULL, 
	posted_on DATE NOT NULL, 
	amount_cents BIGINT NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_recoveries_0 CHECK (amount_cents > 0), 
	FOREIGN KEY(claim_id) REFERENCES claims (id)
);

CREATE TABLE reserve_changes (
	id INT NOT NULL, 
	claim_id INT NOT NULL, 
	posted_on DATE NOT NULL, 
	delta_cents BIGINT NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(claim_id) REFERENCES claims (id)
);

CREATE INDEX ix_policies_holder_id ON policies (holder_id);

CREATE INDEX ix_coverages_policy_id ON coverages (policy_id);

CREATE INDEX ix_claims_coverage_id ON claims (coverage_id);

CREATE INDEX ix_claim_paymen_claim_id ON claim_payments (claim_id);

CREATE INDEX ix_recoveries_claim_id ON recoveries (claim_id);

CREATE INDEX ix_reserve_chan_claim_id ON reserve_changes (claim_id);
