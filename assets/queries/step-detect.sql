-- Daily series for ONE service (or SKU). Find the STEP DATE, then name the change.
-- A delta says something moved; only the step date tells you what.
SELECT FORMAT_DATE('%m-%d %a', DATE(usage_start_time, '<ACCOUNT_TIMEZONE>')) AS day,
       ROUND(SUM(cost), 2) AS gross,
       ROUND(SUM(cost + IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS net
FROM `<BILLING_EXPORT_TABLE>`
WHERE cost_type = 'regular'
  AND service.description = '<SERVICE>'
  AND sku.description LIKE '<SKU_LIKE>'
  AND DATE(usage_start_time, '<ACCOUNT_TIMEZONE>') BETWEEN '<START>' AND '<END>'
GROUP BY 1 ORDER BY 1
