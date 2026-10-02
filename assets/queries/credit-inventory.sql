-- Classify the credit on each SKU, to decide gross-vs-net and whether an
-- "opportunity" is real.
--
-- ⚠ The obvious way to write this is WRONG. `FROM <table>, UNNEST(credits)` inner-joins,
-- so it drops every row of that SKU that carries NO credit — and then compares the credit
-- against only the credited rows' cost. A SKU with one credited $5 row and one uncredited
-- $95 row reads as 100% discounted while actually costing $95 net.
-- So: aggregate the SKU's FULL gross first, and pull credits out per row.
--
-- Reading `pct_of_gross_offset`:
--   ~100  the credit tracks the charge -> net ~ $0. There is NO saving in removing it.
--   0<x<100, and the credit stops at a round number -> a capped POT. Judge on GROSS.
--   0     no credit at all. Gross = net. (Uncredited SKUs ARE listed - that is the point.)
--
-- ⚠ The percentage lumps EVERY credit type on that SKU together and describes only the window
-- you selected. It is not a per-type discount rate and not a marginal saving. A capped
-- allowance can also read 100% inside a window it happens to cover.
--
-- ⚠ This classifies ARITHMETIC, not economics. A credit that looks proportional may be a
-- time-limited promotion that expires, and a committed-use discount can make REDUCING
-- usage increase your net bill. Check the credit's name and expiry before acting.
WITH r AS (
  SELECT service.description AS svc,
         sku.description AS sku,
         cost,
         IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0) AS cred,
         (SELECT STRING_AGG(DISTINCT c.type, ',') FROM UNNEST(credits) c) AS cred_types,
         (SELECT STRING_AGG(DISTINCT c.name, ' | ') FROM UNNEST(credits) c) AS cred_names
  FROM `<BILLING_EXPORT_TABLE>`
  WHERE cost_type = 'regular'
    AND DATE(usage_start_time, 'America/Los_Angeles') BETWEEN '<START>' AND '<END>'
)
SELECT svc, sku,
       ROUND(SUM(cost), 2) AS gross_all_rows,
       ROUND(SUM(cred), 2) AS credits,
       ROUND(SUM(cost) + SUM(cred), 2) AS net,
       ROUND(SAFE_DIVIDE(-SUM(cred), NULLIF(SUM(cost), 0)) * 100, 1) AS pct_of_gross_offset,
       STRING_AGG(DISTINCT cred_types, ',') AS credit_types,
       SUBSTR(STRING_AGG(DISTINCT cred_names, ' | '), 1, 90) AS credit_names
FROM r
GROUP BY svc, sku
HAVING gross_all_rows >= <MIN_GROSS>   -- uncredited SKUs included on purpose: 0% is a result
ORDER BY gross_all_rows DESC
