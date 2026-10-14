-- One-time role template. Run as owner/DBA in the dedicated lab schema.
CREATE ROLE qw_reader;
GRANT USAGE ON SCHEMA public TO qw_reader;
GRANT SELECT ON sites TO qw_reader;
GRANT SELECT ON turbines TO qw_reader;
GRANT SELECT ON contracts TO qw_reader;
GRANT SELECT ON readings TO qw_reader;
GRANT SELECT ON outages TO qw_reader;
GRANT SELECT ON crews TO qw_reader;
GRANT SELECT ON work_orders TO qw_reader;
GRANT SELECT ON settlements TO qw_reader;
-- Attach role to your separately provisioned reader; review other inherited grants.
