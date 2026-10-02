-- Reconcile what the INVOICE says. Use this, not a usage-date sum, whenever you
-- quote a monthly bill.
--
-- Two differences from every other query in this folder, and both matter:
--   1. Group on `invoice.month` (YYYYMM), NOT on a date derived from
--      usage_start_time. A usage row can land on a different invoice than its
--      usage date implies - late-arriving usage is billed on the next invoice.
--   2. Do NOT filter cost_type. An invoice includes tax and adjustments, and
--      `cost_type = 'regular'` silently drops both.
--
-- Everywhere else in cost ANALYSIS you do want 'regular' and a usage date, because
-- you are asking "what did we consume, and when". Here you are asking "what were we
-- charged", which is a different question with a different key.
SELECT invoice.month AS invoice_month,
       ROUND(SUM(IF(cost_type = 'regular', cost, 0)), 2) AS regular_gross,
       ROUND(SUM(IF(cost_type = 'tax', cost, 0)), 2) AS tax,
       ROUND(SUM(IF(cost_type NOT IN ('regular','tax'), cost, 0)), 2) AS adjustments_other,
       ROUND(SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS credits,
       ROUND(SUM(cost)
             + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS invoice_total
FROM `<BILLING_EXPORT_TABLE>`
WHERE invoice.month BETWEEN '<FIRST_INVOICE_MONTH>' AND '<LAST_INVOICE_MONTH>'
GROUP BY invoice_month
ORDER BY invoice_month
