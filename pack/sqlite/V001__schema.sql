-- Generated for sqlite. Single-operator lab only. See README before execution.
CREATE TABLE branches (
	id INTEGER NOT NULL, 
	name VARCHAR(120) NOT NULL, 
	city VARCHAR(120) NOT NULL, 
	latitude NUMERIC(14, 3) NOT NULL, 
	longitude NUMERIC(14, 3) NOT NULL, 
	PRIMARY KEY (id)
);

CREATE TABLE titles (
	id INTEGER NOT NULL, 
	isbn VARCHAR(32) NOT NULL, 
	title VARCHAR(120) NOT NULL, 
	genre VARCHAR(32) NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_titles_0 UNIQUE (isbn)
);

CREATE TABLE copies (
	id INTEGER NOT NULL, 
	title_id INTEGER NOT NULL, 
	branch_id INTEGER NOT NULL, 
	barcode VARCHAR(32) NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_copies_0 UNIQUE (barcode), 
	FOREIGN KEY(title_id) REFERENCES titles (id), 
	FOREIGN KEY(branch_id) REFERENCES branches (id)
);

CREATE TABLE members (
	id INTEGER NOT NULL, 
	branch_id INTEGER NOT NULL, 
	member_code VARCHAR(32) NOT NULL, 
	joined_on DATE NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_members_0 UNIQUE (member_code), 
	FOREIGN KEY(branch_id) REFERENCES branches (id)
);

CREATE TABLE loans (
	id INTEGER NOT NULL, 
	copy_id INTEGER NOT NULL, 
	member_id INTEGER NOT NULL, 
	borrowed_on DATE NOT NULL, 
	due_on DATE NOT NULL, 
	returned_on DATE, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_loans_0 CHECK (due_on >= borrowed_on), 
	CONSTRAINT ck_loans_1 CHECK (returned_on IS NULL OR returned_on >= borrowed_on), 
	FOREIGN KEY(copy_id) REFERENCES copies (id), 
	FOREIGN KEY(member_id) REFERENCES members (id)
);

CREATE TABLE fines (
	id INTEGER NOT NULL, 
	loan_id INTEGER NOT NULL, 
	assessed_cents BIGINT NOT NULL, 
	waived_cents BIGINT NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_fines_0 CHECK (assessed_cents >= 0), 
	CONSTRAINT ck_fines_1 CHECK (waived_cents >= 0 AND waived_cents <= assessed_cents), 
	FOREIGN KEY(loan_id) REFERENCES loans (id)
);

CREATE TABLE fine_payments (
	id INTEGER NOT NULL, 
	fine_id INTEGER NOT NULL, 
	paid_on DATE NOT NULL, 
	amount_cents BIGINT NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT ck_fine_payment_0 CHECK (amount_cents > 0), 
	FOREIGN KEY(fine_id) REFERENCES fines (id)
);

CREATE INDEX ix_copies_branch_id ON copies (branch_id);

CREATE INDEX ix_copies_title_id ON copies (title_id);

CREATE INDEX ix_members_branch_id ON members (branch_id);

CREATE INDEX ix_loans_copy_id ON loans (copy_id);

CREATE INDEX ix_loans_member_id ON loans (member_id);

CREATE INDEX ix_fines_loan_id ON fines (loan_id);

CREATE INDEX ix_fine_payment_fine_id ON fine_payments (fine_id);
