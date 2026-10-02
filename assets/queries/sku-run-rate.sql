-- Current run rate by SKU over the last SETTLED window. Gate the window first.
-- This is the shortlist of what to attack, largest first.
WITH d AS (
  SELECT service.description AS svc, sku.description AS sku, cost AS gross,
         cost + IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0) AS net
  FROM `<BILLING_EXPORT_TABLE>`
  WHERE cost_type = 'regular'
    AND DATE(usage_start_time, 'America/Los_Angeles') BETWEEN '<START>' AND '<END>'
), n AS (SELECT DATE_DIFF(DATE '<END>', DATE '<START>', DAY) + 1 AS days)
SELECT svc, sku,
       ROUND(SUM(gross) / ANY_VALUE(n.days) * 30.44, 2) AS gross_mo,
       ROUND(SUM(net)   / ANY_VALUE(n.days) * 30.44, 2) AS net_mo
FROM d CROSS JOIN n
GROUP BY svc, sku
HAVING gross_mo >= <MIN_MO>
ORDER BY gross_mo DESC
