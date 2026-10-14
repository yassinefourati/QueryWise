-- net_sales: Net completed sales by category after discounts and refunds, in cents.
WITH refunds AS (SELECT line_id,SUM(refund_cents) cents FROM returns GROUP BY line_id) SELECT p.category,SUM(l.quantity*l.unit_cents-l.discount_cents-COALESCE(r.cents,0)) net_cents FROM order_lines l JOIN orders o ON o.id=l.order_id JOIN products p ON p.id=l.product_id LEFT JOIN refunds r ON r.line_id=l.id WHERE o.status='completed' GROUP BY p.category ORDER BY p.category;

-- payment_reconciliation: Which completed orders have mismatched charges and payments?
WITH charges AS (SELECT order_id,SUM(quantity*unit_cents-discount_cents) cents FROM order_lines GROUP BY order_id), paid AS (SELECT order_id,SUM(amount_cents) cents FROM payments GROUP BY order_id) SELECT o.id,c.cents charged,COALESCE(p.cents,0) paid FROM orders o JOIN charges c ON c.order_id=o.id LEFT JOIN paid p ON p.order_id=o.id WHERE o.status='completed' AND c.cents<>COALESCE(p.cents,0) ORDER BY o.id;

-- upgrade_flags: Count records marked by review_flag after migration.
SELECT review_flag,COUNT(*) records FROM orders GROUP BY review_flag ORDER BY review_flag;
