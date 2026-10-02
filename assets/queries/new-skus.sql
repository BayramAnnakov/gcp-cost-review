-- SKUs that are NEW or RESUMED: a line that was ~zero, or dormant, and now is not.
-- New lines are how costs start, and a service-level month-over-month view hides them
-- because they are small at first and buried inside a service that already had spend.
--
-- Two cases, both worth catching:
--   NEW      - essentially absent in the previous window
--   RESUMED  - present before, then quiet, and it started billing mid-window
-- Checking only the first case misses a SKU that went to zero and came back, which is
-- the more common shape for something that was switched off and switched back on.
--
-- Treat the output as "this was reliably zero until <first_billed_day>".
-- Do NOT annualise: a series with no settled baseline is not a run rate.
WITH d AS (
  SELECT DATE(usage_start_time, '<ACCOUNT_TIMEZONE>') AS pt,
         service.description AS svc, sku.description AS sku, cost AS gross
  FROM `<BILLING_EXPORT_TABLE>`
  WHERE cost_type = 'regular'
    AND DATE(usage_start_time, '<ACCOUNT_TIMEZONE>') BETWEEN '<PREV_START>' AND '<CURR_END>'
), agg AS (
  SELECT svc, sku,
    ROUND(SUM(IF(pt <= '<PREV_END>', gross, 0)), 2) AS prev_total,
    ROUND(SUM(IF(pt >= '<CURR_START>', gross, 0)), 2) AS curr_total,
    MIN(IF(pt >= '<CURR_START>' AND gross > 0, pt, NULL)) AS first_billed_day,
    COUNT(DISTINCT IF(pt >= '<CURR_START>' AND gross > 0, pt, NULL)) AS days_billed,
    DATE_DIFF(DATE '<CURR_END>', DATE '<CURR_START>', DAY) + 1 AS window_days
  FROM d GROUP BY svc, sku
)
SELECT svc, sku, prev_total, curr_total, first_billed_day, days_billed, window_days,
  CASE WHEN prev_total < 0.50 THEN 'NEW' ELSE 'RESUMED' END AS kind
FROM agg
WHERE curr_total >= <MIN_NEW>
  AND (prev_total < 0.50
       OR DATE_DIFF(first_billed_day, DATE '<CURR_START>', DAY) >= 7)
ORDER BY curr_total DESC
