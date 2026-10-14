CREATE ROLE 'qw_reader';
GRANT SELECT ON qw_complex_retail.customers TO 'qw_reader';
GRANT SELECT ON qw_complex_retail.products TO 'qw_reader';
GRANT SELECT ON qw_complex_retail.warehouses TO 'qw_reader';
GRANT SELECT ON qw_complex_retail.inventory TO 'qw_reader';
GRANT SELECT ON qw_complex_retail.orders TO 'qw_reader';
GRANT SELECT ON qw_complex_retail.order_lines TO 'qw_reader';
GRANT SELECT ON qw_complex_retail.returns TO 'qw_reader';
GRANT SELECT ON qw_complex_retail.payments TO 'qw_reader';
-- Attach role to your separately provisioned reader; review other inherited grants.
