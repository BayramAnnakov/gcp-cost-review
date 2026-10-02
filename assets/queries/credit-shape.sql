-- Is the credit draw flat or FRONT-LOADED?
-- If it steps down sharply after the first days, a late-month NET run rate
-- overstates the month. Project on gross and subtract the pot separately.
WITH d AS (
  SELECT DATE(usage_start_time, '<ACCOUNT_TIMEZONE>') AS pt,
         IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0) AS cr
  FROM `<BILLING_EXPORT_TABLE>`
  WHERE cost_type = 'regular'
    AND DATE(usage_start_time, '<ACCOUNT_TIMEZONE>') BETWEEN '<START>' AND '<END>'
)
SELECT FORMAT_DATE('%m-%d', pt) AS day, ROUND(SUM(cr), 2) AS credits_that_day
FROM d GROUP BY pt ORDER BY pt
