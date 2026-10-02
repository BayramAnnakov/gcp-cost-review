-- Classify every credit. This decides whether to judge a SKU on gross or net.
--   pot          : plateaus at a round number, then stops  -> judge on GROSS
--   proportional : magnitude tracks the SKU's gross        -> net may be $0, no opportunity
-- Compare `credit_total` against `gross_of_those_rows`: equal and opposite = proportional.
SELECT c.name AS credit_name, c.type AS credit_type,
       COUNT(DISTINCT sku.description) AS skus,
       ROUND(SUM(c.amount), 2) AS credit_total,
       ROUND(SUM(cost), 2) AS gross_of_those_rows
FROM `<BILLING_EXPORT_TABLE>`, UNNEST(credits) c
WHERE cost_type = 'regular'
  AND DATE(usage_start_time, '<ACCOUNT_TIMEZONE>') BETWEEN '<START>' AND '<END>'
GROUP BY credit_name, credit_type
ORDER BY credit_total
