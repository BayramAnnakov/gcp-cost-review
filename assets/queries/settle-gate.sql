-- Which days are SETTLED? Gate on a flat-rate control SKU.
-- A day is complete only when CONTROL reads its known daily value.
-- An unsettled day reads low across EVERY service at once, which looks
-- exactly like a successful optimization.
WITH d AS (
  SELECT DATE(usage_start_time, '<ACCOUNT_TIMEZONE>') AS pt,
         sku.description AS sku,
         cost + IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0) AS net
  FROM `<BILLING_EXPORT_TABLE>`
  WHERE cost_type = 'regular'
    AND DATE(usage_start_time, '<ACCOUNT_TIMEZONE>') BETWEEN '<START>' AND '<END>'
)
SELECT FORMAT_DATE('%m-%d %a', pt) AS day,
       ROUND(SUM(IF(sku LIKE '<CONTROL_SKU_LIKE>', net, 0)), 3) AS control,
       ROUND(SUM(net), 2) AS net_total
FROM d GROUP BY pt ORDER BY pt
