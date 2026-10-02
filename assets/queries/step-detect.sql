-- Daily series for one service (or SKU). Find the STEP DATE, then name the change.
-- A delta says something moved; only the step date tells you what.
--
-- Two deliberate choices:
--   * GROUP/ORDER BY the real DATE, never a formatted string. '01-05' sorts before
--     '12-31', so a string key silently misorders any window crossing a year boundary.
--   * LEFT JOIN a generated calendar, so a day the resource stopped billing shows as a
--     real 0 instead of disappearing. The disappearance IS the step you are looking for,
--     and a query that omits it hides the answer.
WITH cal AS (
  SELECT d FROM UNNEST(GENERATE_DATE_ARRAY(DATE '<START>', DATE '<END>')) AS d
), r AS (
  SELECT DATE(usage_start_time, 'America/Los_Angeles') AS pt,
         cost AS gross,
         cost + IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0) AS net,
         IFNULL(project.id, '(unassigned)') AS proj
  FROM `<BILLING_EXPORT_TABLE>`
  WHERE cost_type = 'regular'
    AND service.description = '<SERVICE>'
    AND sku.description LIKE '<SKU_LIKE>'
    AND DATE(usage_start_time, 'America/Los_Angeles') BETWEEN '<START>' AND '<END>'
)
SELECT cal.d AS day,
       FORMAT_DATE('%a', cal.d) AS dow,
       ROUND(IFNULL(SUM(r.gross), 0), 2) AS gross,
       ROUND(IFNULL(SUM(r.net), 0), 2) AS net,
       COUNT(r.pt) AS row_count,
       STRING_AGG(DISTINCT r.proj, ',') AS projects
FROM cal LEFT JOIN r ON r.pt = cal.d
GROUP BY cal.d ORDER BY cal.d
