-- Which days are SETTLED? Gate on a flat-rate control SKU.
--
-- The timezone is hardcoded to America/Los_Angeles on purpose and is NOT a setting.
-- Cloud Billing reports always start a day at midnight US/Canadian Pacific and observe
-- US daylight saving; it is not configurable per account. Grouping in UTC or in your own
-- local zone shifts charges across day AND month boundaries, so your figures stop
-- matching the console and nothing downstream can be reconciled.
--
-- Measured on GROSS on purpose: credits (free tiers, CUDs) move a net control for
-- reasons that have nothing to do with completeness.
--
-- A LEFT JOIN against a generated calendar is also on purpose: a day with no rows at
-- all must appear as a 0, not vanish from the output. A missing row is the single most
-- important thing this query has to show you.
--
-- ⚠ What this gate does and does NOT prove.
--   It proves: the control SKU's data for that day has landed.
--   It does NOT prove the whole day is complete. Services export on their own schedules,
--   so the control can be settled while the SKU you actually care about has delivered
--   no rows yet. Treat a passing gate as necessary, not sufficient: before trusting a
--   per-service number, check that THAT service's own daily series looks complete too
--   (step-detect.sql), and prefer a control in the same service family where one exists.
-- ⚠ On daylight-saving transition days an hourly resource bills 23 or 25 hours, so the
--   control legitimately differs by ~1/24 twice a year. Allow a tolerance; do not read
--   it as lag.
WITH cal AS (
  SELECT d FROM UNNEST(GENERATE_DATE_ARRAY(DATE '<START>', DATE '<END>')) AS d
), r AS (
  SELECT DATE(usage_start_time, 'America/Los_Angeles') AS pt,
         sku.description AS sku, cost
  FROM `<BILLING_EXPORT_TABLE>`
  WHERE cost_type = 'regular'
    AND DATE(usage_start_time, 'America/Los_Angeles') BETWEEN '<START>' AND '<END>'
)
SELECT FORMAT_DATE('%m-%d %a', cal.d) AS day,
       ROUND(SUM(IF(r.sku LIKE '<CONTROL_SKU_LIKE>', r.cost, 0)), 3) AS control_gross,
       ROUND(SUM(r.cost), 2) AS gross_total,
       COUNT(r.pt) AS row_count
FROM cal LEFT JOIN r ON r.pt = cal.d
GROUP BY cal.d ORDER BY cal.d
