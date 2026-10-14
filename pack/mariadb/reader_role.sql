CREATE ROLE 'qw_reader';
GRANT SELECT ON qw_complex_freight.depots TO 'qw_reader';
GRANT SELECT ON qw_complex_freight.vehicles TO 'qw_reader';
GRANT SELECT ON qw_complex_freight.drivers TO 'qw_reader';
GRANT SELECT ON qw_complex_freight.shipments TO 'qw_reader';
GRANT SELECT ON qw_complex_freight.legs TO 'qw_reader';
GRANT SELECT ON qw_complex_freight.temperature_scans TO 'qw_reader';
GRANT SELECT ON qw_complex_freight.invoices TO 'qw_reader';
-- Attach role to your separately provisioned reader; review other inherited grants.
