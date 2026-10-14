-- One-time role template. Run as owner/DBA in the dedicated lab schema.
CREATE ROLE qw_reader;
GRANT SELECT ON airports TO qw_reader;
GRANT SELECT ON aircraft TO qw_reader;
GRANT SELECT ON routes TO qw_reader;
GRANT SELECT ON gates TO qw_reader;
GRANT SELECT ON flights TO qw_reader;
GRANT SELECT ON turnarounds TO qw_reader;
GRANT SELECT ON disruptions TO qw_reader;
GRANT SELECT ON crew_assignments TO qw_reader;
-- Attach role to your separately provisioned reader; review other inherited grants.
