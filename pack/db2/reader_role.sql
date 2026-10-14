-- One-time role template. Run as owner/DBA in the dedicated lab schema.
CREATE ROLE qw_reader;
GRANT SELECT ON policyholders TO ROLE qw_reader;
GRANT SELECT ON policies TO ROLE qw_reader;
GRANT SELECT ON coverages TO ROLE qw_reader;
GRANT SELECT ON claims TO ROLE qw_reader;
GRANT SELECT ON reserve_changes TO ROLE qw_reader;
GRANT SELECT ON claim_payments TO ROLE qw_reader;
GRANT SELECT ON recoveries TO ROLE qw_reader;
-- Attach role to your separately provisioned reader; review other inherited grants.
