-- Is the credit draw flat or FRONT-LOADED?
-- If it steps down sharply after the first days, a late-month NET run rate
-- overstates the month. Project on gross and subtract the pot separately.
-- Broken out PER CREDIT NAME, because an account-wide total hides the shape: a pot that
-- drains and a proportional discount that tracks usage sum to something that looks like
-- neither. A pot is flat-then-abruptly-zero; a proportional credit follows its SKU's volume.
WITH d AS (
  SELECT DATE(usage_start_time, 'America/Los_Angeles') AS pt, c.name AS credit_name, c.amount AS amt
  FROM `<BILLING_EXPORT_TABLE>`, UNNEST(credits) c
  WHERE cost_type = 'regular'
    AND DATE(usage_start_time, 'America/Los_Angeles') BETWEEN '<START>' AND '<END>'
)
SELECT pt AS day, SUBSTR(credit_name, 1, 60) AS credit_name, ROUND(SUM(amt), 2) AS credit_that_day
FROM d GROUP BY pt, credit_name ORDER BY credit_name, pt
