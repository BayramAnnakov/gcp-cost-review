-- Month over month BY PROJECT and service. Run this before attributing anything.
--
-- An account-wide, service-only view cancels out the thing you are looking for: a
-- 100-unit fall in one project and a 100-unit rise in another nets to zero and the
-- diff shows nothing changed. Project identity is also what tells you whether a step
-- was your team's work or somebody else's.
WITH d AS (
  SELECT DATE(usage_start_time, 'America/Los_Angeles') AS pt,
         IFNULL(project.id, '(unassigned)') AS proj,
         service.description AS svc, cost AS gross
  FROM `<BILLING_EXPORT_TABLE>`
  WHERE cost_type = 'regular'
    AND DATE(usage_start_time, 'America/Los_Angeles') BETWEEN '<PREV_START>' AND '<CURR_END>'
), n AS (
  SELECT DATE_DIFF(DATE '<PREV_END>', DATE '<PREV_START>', DAY) + 1 AS prev_days,
         DATE_DIFF(DATE '<CURR_END>', DATE '<CURR_START>', DAY) + 1 AS curr_days
)
SELECT proj, svc,
  ROUND(SUM(IF(pt <= '<PREV_END>', gross, 0)) / ANY_VALUE(n.prev_days) * 30.44, 2) AS prev_mo,
  ROUND(SUM(IF(pt >= '<CURR_START>', gross, 0)) / ANY_VALUE(n.curr_days) * 30.44, 2) AS curr_mo,
  ROUND(SUM(IF(pt >= '<CURR_START>', gross, 0)) / ANY_VALUE(n.curr_days) * 30.44
      - SUM(IF(pt <= '<PREV_END>', gross, 0)) / ANY_VALUE(n.prev_days) * 30.44, 2) AS delta_mo
FROM d CROSS JOIN n
GROUP BY proj, svc
HAVING prev_mo > 1 OR curr_mo > 1
ORDER BY delta_mo
