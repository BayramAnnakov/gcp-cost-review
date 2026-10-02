-- SKUs that are NEW or RESUMED: a line that was absent, or dormant, and now is not.
-- New lines are how costs start, and a service-level month-over-month view hides them
-- because they are small at first and sit inside a service that already had spend.
--
-- Detection works on the DAILY series, not on window totals. The naive version — "first
-- charge is at least N days into the window" — misses a SKU that billed on day 1, went
-- quiet, and resumed on day 20, which is the shape you most want to catch.
-- Here: for each SKU find its first billed day in the current window, then the most
-- recent billed day anywhere before that, and report the gap.
--
-- ⚠ Known limitation, stated so you do not over-trust it: a legitimately intermittent
-- SKU (a monthly job that always bills on the 10th) will show a ~30-day gap and be
-- flagged. `prev_days_billed` is in the output so you can see that it is a regular
-- visitor rather than something new. Judge, do not auto-file.
-- ⚠ "Zero cost" is not "no usage" — earlier usage may have been inside a free tier. If
-- the distinction matters, check usage.amount, not cost.
WITH r AS (
  SELECT DATE(usage_start_time, 'America/Los_Angeles') AS pt,
         service.description AS svc, sku.description AS sku, cost
  FROM `<BILLING_EXPORT_TABLE>`
  WHERE cost_type = 'regular'
    AND DATE(usage_start_time, 'America/Los_Angeles') BETWEEN '<LOOKBACK_START>' AND '<CURR_END>'
), daily AS (
  SELECT svc, sku, pt, SUM(cost) AS gross FROM r GROUP BY svc, sku, pt
), firsts AS (
  SELECT svc, sku,
         MIN(IF(pt >= DATE '<CURR_START>' AND gross > 0, pt, NULL)) AS first_curr_billed,
         SUM(IF(pt >= DATE '<CURR_START>', gross, 0)) AS curr_total,
         COUNT(DISTINCT IF(pt < DATE '<CURR_START>' AND gross > 0, pt, NULL)) AS prev_days_billed,
         SUM(IF(pt < DATE '<CURR_START>', gross, 0)) AS prev_total
  FROM daily GROUP BY svc, sku
), gaps AS (
  SELECT f.*,
         (SELECT MAX(d.pt) FROM daily d
           WHERE d.svc = f.svc AND d.sku = f.sku
             AND d.gross > 0 AND d.pt < f.first_curr_billed) AS last_billed_before
  FROM firsts f WHERE f.first_curr_billed IS NOT NULL
)
SELECT svc, sku,
       ROUND(prev_total, 2) AS prev_total,
       ROUND(curr_total, 2) AS curr_total,
       prev_days_billed,
       first_curr_billed,
       last_billed_before,
       DATE_DIFF(first_curr_billed, last_billed_before, DAY) - 1 AS gap_days,
       CASE WHEN last_billed_before IS NULL THEN 'NEW' ELSE 'RESUMED' END AS kind
FROM gaps
WHERE curr_total >= <MIN_NEW>
  AND (last_billed_before IS NULL
       OR DATE_DIFF(first_curr_billed, last_billed_before, DAY) - 1 >= <GAP_DAYS>)
ORDER BY curr_total DESC
