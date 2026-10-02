-- SKUs that are NEW or RESUMED: a line that was absent, or dormant, and now is not.
-- New lines are how costs start, and a service-level month-over-month view hides them.
--
-- Detection walks the DAILY series with LAG and reports EVERY transition that lands in the
-- current window. Two weaker designs were tried and both miss real cases:
--   * "window totals" misses a SKU that billed before and billed more after
--   * "first billed day is >= N days into the window" collapses the SKU to its first charge,
--     so a SKU that billed on day 1, went quiet, and resumed on day 20 is invisible.
--     (Fixture: charges on Aug 31, Sep 1 and Sep 20 returned nothing.)
--
-- ⚠ Limitations, stated so you do not over-trust the output:
--   * a legitimately intermittent SKU (a monthly job) shows a ~30-day gap every month.
--     `prev_days_billed` is in the output so you can see it is a regular visitor.
--   * `NEW` here means "no billing day since <LOOKBACK_START>", not "never existed".
--     Widen the lookback if that distinction matters.
--   * zero COST is not zero USAGE — earlier usage may have sat inside a free tier. If that
--     matters, look at usage.amount with usage.unit, not at cost.
--   * this export is ingestion-time partitioned, so a usage-date predicate does NOT prune
--     partitions. Add a `_PARTITIONTIME` bound if the table is large.
WITH r AS (
  SELECT DATE(usage_start_time, 'America/Los_Angeles') AS pt,
         service.description AS svc, sku.description AS sku, cost
  FROM `<BILLING_EXPORT_TABLE>`
  WHERE cost_type = 'regular'
    AND DATE(usage_start_time, 'America/Los_Angeles') BETWEEN '<LOOKBACK_START>' AND '<CURR_END>'
), billed AS (                       -- days this SKU actually billed
  SELECT svc, sku, pt, SUM(cost) AS gross
  FROM r GROUP BY svc, sku, pt
  HAVING SUM(cost) > 0
), lagged AS (
  SELECT svc, sku, pt, gross,
         LAG(pt) OVER (PARTITION BY svc, sku ORDER BY pt) AS prev_billed
  FROM billed
), transitions AS (
  SELECT svc, sku, pt AS resumed_on, prev_billed,
         DATE_DIFF(pt, prev_billed, DAY) - 1 AS gap_days
  FROM lagged
  WHERE pt >= DATE '<CURR_START>'
    AND (prev_billed IS NULL
         OR DATE_DIFF(pt, prev_billed, DAY) - 1 >= <GAP_DAYS>)
), totals AS (
  SELECT svc, sku,
         SUM(IF(pt >= DATE '<CURR_START>', gross, 0)) AS curr_total,
         SUM(IF(pt <  DATE '<CURR_START>', gross, 0)) AS prev_total,
         COUNT(DISTINCT IF(pt < DATE '<CURR_START>', pt, NULL)) AS prev_days_billed
  FROM billed GROUP BY svc, sku
)
SELECT t.svc, t.sku,
       ROUND(o.prev_total, 2) AS prev_total,
       ROUND(o.curr_total, 2) AS curr_total,
       o.prev_days_billed,
       t.resumed_on, t.prev_billed, t.gap_days,
       CASE WHEN t.prev_billed IS NULL THEN 'NEW(since lookback)' ELSE 'RESUMED' END AS kind
FROM transitions t JOIN totals o USING (svc, sku)
WHERE o.curr_total >= <MIN_NEW>
ORDER BY o.curr_total DESC, t.resumed_on
