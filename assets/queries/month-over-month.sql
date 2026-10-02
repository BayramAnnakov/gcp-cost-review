-- Service-level month over month, day-normalised to 30.44 so unequal months compare.
-- Both bases are shown on purpose: use GROSS where a capped-pot credit applies.
WITH d AS (
  SELECT DATE(usage_start_time, '<ACCOUNT_TIMEZONE>') AS pt,
         service.description AS svc, cost AS gross,
         cost + IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0) AS net
  FROM `<BILLING_EXPORT_TABLE>`
  WHERE cost_type = 'regular'
    AND DATE(usage_start_time, '<ACCOUNT_TIMEZONE>') BETWEEN '<PREV_START>' AND '<CURR_END>'
), n AS (
  SELECT DATE_DIFF(DATE '<PREV_END>',  DATE '<PREV_START>', DAY) + 1 AS prev_days,
         DATE_DIFF(DATE '<CURR_END>',  DATE '<CURR_START>', DAY) + 1 AS curr_days
)
SELECT svc,
  ROUND(SUM(IF(pt <= '<PREV_END>', gross, 0)) / ANY_VALUE(n.prev_days) * 30.44, 2) AS prev_gross_mo,
  ROUND(SUM(IF(pt >= '<CURR_START>', gross, 0)) / ANY_VALUE(n.curr_days) * 30.44, 2) AS curr_gross_mo,
  ROUND(SUM(IF(pt >= '<CURR_START>', gross, 0)) / ANY_VALUE(n.curr_days) * 30.44
      - SUM(IF(pt <= '<PREV_END>', gross, 0)) / ANY_VALUE(n.prev_days) * 30.44, 2) AS delta_gross_mo,
  ROUND(SUM(IF(pt >= '<CURR_START>', net, 0)) / ANY_VALUE(n.curr_days) * 30.44, 2) AS curr_net_mo
FROM d CROSS JOIN n
GROUP BY svc
HAVING prev_gross_mo > 1 OR curr_gross_mo > 1
ORDER BY delta_gross_mo
