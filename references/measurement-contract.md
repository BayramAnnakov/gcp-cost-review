# The measurement contract

Establish this once per billing account, write the answers down, and do not re-derive
them. Re-deriving invites a different answer, and the whole point is that every later
number rests on the same footing.

## 1. The export is the only real instrument

The Cloud Console billing report is fine for a total. It cannot do attribution: which
SKU, which project, which day, which label, which credit. That needs the **BigQuery
billing export**, which the account owner enables in Billing → Billing export.

Two things to know before promising an answer:

- The export **only collects from the moment it is enabled**. If it was turned on last
  week, "why did last quarter change" is unanswerable from it. Say so rather than
  substituting a worse instrument.
- There are two exports. **Standard** gives service + SKU + project + labels, and is
  enough for almost all cost work. **Detailed** adds per-resource rows, which you need
  only when one SKU is shared by many resources and you must know which one. Detailed
  costs more to store.

## 2. Make your query match the console

Three conventions, and all three matter:

| Convention | Why |
|---|---|
| Group by day in the **billing account's timezone** | The console does. Grouping in UTC shifts spend across midnight and no two numbers ever agree. |
| Use **net** = `cost` + sum of the `credits` array | The console shows net. `cost` alone is gross and will read high. |
| Filter `cost_type = 'regular'` | Otherwise `tax`, `adjustment` and `rounding_error` rows mix into service totals. |

```sql
SELECT DATE(usage_start_time, '<ACCOUNT_TIMEZONE>') AS day,
       service.description AS service,
       SUM(cost) AS gross,
       SUM(cost + IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)) AS net
FROM `<BILLING_EXPORT_TABLE>`
WHERE cost_type = 'regular'
  AND DATE(usage_start_time, '<ACCOUNT_TIMEZONE>') BETWEEN '<START>' AND '<END>'
GROUP BY day, service
```

**Validate against the console before trusting anything downstream.** If a complete
month does not reconcile, the error is in your conventions, and it will silently
propagate into every finding.

## 3. The settle gate

Export rows arrive in batches. A partial day is not flagged; it simply reads low, and it
reads low *across every service at once*, which is exactly what a successful
optimization also looks like.

So gate on a **flat-rate control**: a SKU that bills the same amount every day
regardless of traffic. Good candidates, in rough order of reliability:

- a managed cache or database instance with fixed capacity
- a per-cluster or per-instance management fee
- a reserved/static IP address charge
- any committed-use or subscription line

Record its exact daily value. Then:

> **A day is settled when the control reads its known value. Not before.**

This is better than "wait N days" because lag varies, and better than a completeness
percentage because that is itself derived from the incomplete data.

Keep two or three controls if you can. One flat SKU can change for its own reasons - a
resize, a price change - and you want to notice that rather than mistake it for lag.

## 4. Normalise to a 30.44-day month

Months are 28-31 days. Comparing a 31-day month to a 30-day month shows a 3% "saving"
that is the calendar. Comparing a complete month to a 9-day sample is worse.

Normalise everything: `sum(window) / days(window) × 30.44`. State that you did.

## 5. Gross or net - decide per SKU, and say which

Neither is universally right.

- **Capped-pot credit** (a fixed monthly free allowance, e.g. a per-account cluster-fee
  allowance): the pot is a constant. Judging a change on net hides the change behind the
  pot. **Judge on gross.**
- **Proportional discount** (a credit that is a fixed percentage of the line, including
  100%): net is what you pay. A 100% discount means **net is $0.00 and there is nothing
  to save**, however large gross looks.
- **Tiered free allowance** (metrics, logs: first N units free each month): gross is
  *already* net of the allowance. Comparing partial months is meaningless because the
  allowance resets. Use **complete months**, or better, compare **usage units**.

Inspect the credit rows rather than assuming:

```sql
SELECT c.name, c.type, ROUND(SUM(c.amount),2) AS total
FROM `<BILLING_EXPORT_TABLE>`, UNNEST(credits) c
WHERE DATE(usage_start_time, '<ACCOUNT_TIMEZONE>') BETWEEN '<START>' AND '<END>'
GROUP BY 1,2 ORDER BY total
```

If a credit's total magnitude exactly tracks its SKU's gross, it is proportional. If it
plateaus at a round number and stops, it is a pot.

## 6. Credit shape, for projection

Run `assets/queries/credit-shape.sql`. A fixed pot is usually drawn down in the first
days of the month, so the daily credit is large early and small later.

Consequence: **a run rate computed on net from a late-month window overstates the month**,
because those days carry little credit. Project on **gross**, then subtract the pot as a
monthly constant.

## 7. Tax

Tax is typically stamped at the month boundary and exported later, so a just-closed
month can show tax incomplete for days. Record the historical tax as a percentage of net
and use that to estimate an invoice; do not assume the tax rows you can see are final.

## 8. Write it down

A calibration note with: export table id, account timezone, the control SKU(s) and their
exact daily values, the credit inventory with each one's shape, the tax rate, and the
date the export began. Every future session reads this first.
