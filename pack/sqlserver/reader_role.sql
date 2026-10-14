-- One-time role template. Run as owner/DBA in the dedicated lab schema.
CREATE ROLE qw_reader;
GRANT SELECT ON OBJECT::dbo.clinics TO qw_reader;
GRANT SELECT ON OBJECT::dbo.patients TO qw_reader;
GRANT SELECT ON OBJECT::dbo.clinicians TO qw_reader;
GRANT SELECT ON OBJECT::dbo.procedures TO qw_reader;
GRANT SELECT ON OBJECT::dbo.appointments TO qw_reader;
GRANT SELECT ON OBJECT::dbo.claim_lines TO qw_reader;
GRANT SELECT ON OBJECT::dbo.remittances TO qw_reader;
-- Attach role to your separately provisioned reader; review other inherited grants.
