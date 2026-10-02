# The measurement contract

Establish this once per billing account, write the answers down, and do not re-derive
them. Re-deriving invites a different answer, and the whole point is that every later
number rests on the same footing.

## 1. The export is the only real instrument

The Cloud Console billing reports do more than a total — they break down by service, SKU,
project and label, and export CSV. What they cannot give you is **SQL over arbitrary windows,
per-row credit detail, and reproducibility**: a figure someone else can re-run and check. That
is what the **BigQuery billing export** adds, and the account owner enables it in
Billing → Billing export.

Two things to know before promising an answer:

- The export **essentially only collects from the moment it is enabled**. One exception
  worth knowing: a *first* export — standard **or** detailed — into a **US or EU
  multi-region** dataset backfills from the start of the previous month. That is the only
  backfill on offer, so if it was turned on last week, "why did last quarter change" is still
  unanswerable from it. Say so rather than substituting a worse instrument.
- There are two exports. **Standard** gives service + SKU + project + labels, and is
  enough for almost all cost work. **Detailed** adds per-resource rows, which you need
  only when one SKU is shared by many resources and you must know which one. Detailed
  costs more to store.
- **Querying the export costs money**, in proportion to bytes scanned. A cost review that
  runs up a BigQuery bill is a bad joke, so `scripts/bq.py` estimates with a dry run and
  refuses anything over a cap. Keep windows narrow.

## 2. Make your query match the console

Three conventions, and all three matter:

| Convention | Why |
|---|---|
| Group by day in **US Pacific** (`America/Los_Angeles`) | That is what Cloud Billing reports use, with daylight saving. Not UTC, and not the account owner's local zone — either shifts spend across day and month boundaries. |
| Use **net** = `cost` + sum of the `credits` array | The console shows net. `cost` alone is gross and will read high. |
| Filter `cost_type = 'regular'` | Otherwise `tax`, `adjustment` and `rounding_error` rows mix into service totals. |

```sql
SELECT DATE(usage_start_time, 'America/Los_Angeles') AS day,
       service.description AS service,
       SUM(cost) AS gross,
       SUM(cost + IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)) AS net
FROM `<BILLING_EXPORT_TABLE>`
WHERE cost_type = 'regular'
  AND DATE(usage_start_time, 'America/Los_Angeles') BETWEEN '<START>' AND '<END>'
GROUP BY day, service
```

Those three conventions are for **analysis** — "what did we consume, and when". They are
the wrong key for **"what were we charged"**: an invoice is keyed on `invoice.month`, and
it includes tax and adjustments that `cost_type='regular'` drops. Reconcile a bill with
`assets/queries/invoice-reconcile.sql`, and expect the two totals to differ slightly.

**Say which console view you are matching.** "Charge period" **excludes** taxes and
adjustments; "Billing period" **includes** them. Comparing your `cost_type='regular'` sum
to the wrong one produces a mismatch you will waste an afternoon on.

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
- a flat per-day storage or licence line

(Deliberately **not** a committed-use or subscription line: those carry a
`FEE_UTILIZATION_OFFSET` or similar by construction, which is exactly what rules a control
out — see the warning below.)

⚠ **A control must carry no credit.** Check it with `credit-inventory.sql` first. The
obvious candidate — a per-cluster or per-instance management fee — is often exactly the
SKU a capped free-tier pot is applied to: measured on a real account, a cluster-fee SKU
had a perfectly flat *gross* and a *net* that swung from 0× to 1× of it across the month
as the pot drained. Gate on **gross**, and prefer a control with no credit at all.

Record its exact daily **gross** value. Then:

> **Until the control reads its known value, the day is certainly incomplete.**

Note the direction: this tells you when to *stop* trusting a day, not when to start. A
historical p95 is a distribution with a tail, and Google publishes no delivery-time guarantee,
so past punctuality never certifies today's missing rows.

This is better than "wait N days" because lag varies, and better than a completeness
percentage because that is itself derived from the incomplete data.

**Measure your own account's lag once, with `export_time`.** The export carries an
`export_time` column recording when each row was appended. Per service, compare
`export_time` to the usage day it describes:

```sql
SELECT service.description AS svc,
       APPROX_QUANTILES(TIMESTAMP_DIFF(export_time, usage_end_time, HOUR),
                        100)[OFFSET(95)] AS p95_hours_after_usage
FROM `<BILLING_EXPORT_TABLE>`
WHERE cost_type='regular'
  AND DATE(usage_start_time,'America/Los_Angeles') BETWEEN '<START>' AND '<END>'
GROUP BY svc ORDER BY p95_hours_after_usage DESC
```

⚠️ Compare `export_time` against **`usage_end_time`** — the clean "how long after the usage did
this row arrive" question. The tempting alternative,
`TIMESTAMP(DATE(usage_start_time,'America/Los_Angeles'))`, is **a bug**: `DATE()` returns a
Pacific calendar date and `TIMESTAMP()` then reads it as **UTC** midnight, inflating every figure
by the UTC offset. Measured: exactly +7 h on all 15 services. If you do want "age since the usage
day began", pass the zone explicitly —
`TIMESTAMP(DATE(...,'America/Los_Angeles'), 'America/Los_Angeles')` — and label it as the
different measurement it is.

**The spread is large enough to matter.** Measured over a complete month on one account, p95
arrival after `usage_end_time` ran from **low tens of hours for most services to roughly ten
days for the slowest**. So a gate built on a fast-arriving control passes while a slow
service's rows for that same day are still days out — quote that service and you are quoting a
partial. **Measure your own**; these are an order of magnitude, not a constant.

Weight the alarm by money: on that account every service had fully landed within five days
except the slowest, and the slowest billed **$0.00**. A service that arrives late and costs
nothing does not threaten a conclusion. Sort your lag table next to the spend table before
deciding which days you can use.

That tells you which services are slow enough to distrust, in your account rather than in
general. Do it once in Step 0 and record it. It does not make the gate sufficient — nothing
does — but it stops you quoting a service whose rows are known to arrive days late.

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
- **Tiered free allowance** (Cloud Monitoring metrics, Cloud Logging: first N units free
  each month): gross is *already* net of the allowance. Comparing partial months is
  meaningless because the allowance resets. Use **complete months**, or better, compare
  **usage units** — pair `usage.amount` with `usage.unit`, or `usage.amount_in_pricing_units` with `usage.pricing_unit`. Those are the only two correct pairings; crossing them compares raw units to priced ones and can be wrong by orders of magnitude.
  ⚠ Not every observability SKU works this way — Managed Service for Prometheus is priced
  per sample with **no free allotment**. Check the SKU's pricing unit rather than assuming
  a free tier exists.

**Read `credits.type` rather than guessing from shape.** It is documented as a string with a
listed set of values, not a closed schema enum — so handle an unexpected value rather than
assuming the list is exhaustive. The documented values are
`FREE_TIER`, `PROMOTION`, `DISCOUNT`, `COMMITTED_USAGE_DISCOUNT`,
`COMMITTED_USAGE_DISCOUNT_DOLLAR_BASE`, `SUSTAINED_USAGE_DISCOUNT`,
`FEE_UTILIZATION_OFFSET`, `RESELLER_MARGIN` and `SUBSCRIPTION_BENEFIT`. What each means
for your arithmetic:

| type | shape | what to do |
|---|---|---|
| `FREE_TIER` | an allowance — sometimes dollars, often **units** (free instance-hours) | judge on gross; subtract once, never below eligible spend. It does **not** always drain early: a unit allowance consumed by something always-on spreads across the month. ⚠ Note a free tier does not always carry this `type` — one measured account books its GKE pot as plain `DISCOUNT` — so classify by behaviour too |
| `PROMOTION` | trial, milestone or marketing credits; a balance that runs out | a strong candidate when a bill jumps for no structural reason — check the remaining balance and expiry before forecasting |
| `DISCOUNT` | contractual, e.g. spend-threshold based | the daily shape tells you how it *behaved*, not what the contract says — find the contract before relying on it |
| `SUSTAINED_USAGE_DISCOUNT` | proportional, up to ~30%; booked unevenly across rows | read it against the SKU's **full gross over a whole month**. Against credited rows alone the ratio exceeds 1 and is meaningless |
| `COMMITTED_USAGE_DISCOUNT*`, `FEE_UTILIZATION_OFFSET` | tied to a commitment | the commitment is payable either way, so **a cut to covered usage can save ~nothing** — never price one without checking commitments |
| `RESELLER_MARGIN`, `SUBSCRIPTION_BENEFIT` | you are billed through a reseller, or hold a support/subscription plan | your effective price is not list price. Do not price any change off public rates without checking the reseller agreement |

⚠ **Take the ratio against the SKU's FULL gross, never against the credited rows alone** — and
be careful what you conclude if you got it wrong. An earlier draft of this file declared the
ratio heuristic unreliable and cited a sustained-use discount at −5.2 and a "pot" at −0.50,
−0.86 and −0.93. Every one of those numbers came out of the **broken inner-join query** that
trap A10 is about: it compared each credit against only the rows carrying it. Re-measured with
the corrected query, the same sustained-use discount reads a clean **30% of full SKU gross** —
exactly its documented maximum — and the −0.50/−0.86/−0.93 figures turn out to belong to
unrelated allocation-time and introductory discounts, not to a pot at all.

So the heuristic is *usable* once the join is right. The lesson is narrower and more
uncomfortable: **guidance derived from a buggy query inherits the bug**, and it reads as a
finding about the world rather than about your SQL. Still confirm the shape against the daily
series (`credit-shape.sql`, per credit name) and against `credits.type` before acting — a ratio
tells you what happened inside your window, not what the contract says. **Classify from the daily series** (`credit-shape.sql`
per credit name: a pot is flat then abruptly zero) and from `credits.type`, and use the
ratio only as a hint.

Inspect the credit rows rather than assuming:

```sql
SELECT c.name, c.type, ROUND(SUM(c.amount),2) AS total
FROM `<BILLING_EXPORT_TABLE>`, UNNEST(credits) c
WHERE DATE(usage_start_time, 'America/Los_Angeles') BETWEEN '<START>' AND '<END>'
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

## 8. Write it down — and keep it out of a public repo

Use a deterministic path so a later session, or a student's agent, knows where to look.
**`calibration.local.md` at the repo root** (already in `.gitignore`), or
`~/.config/gcp-cost-review/calibration.md` if the repo is public:

```markdown
# Cost review calibration — <ACCOUNT NAME>
export_table:   <project>.<dataset>.gcp_billing_export_v1_XXXXXX
export_began:   YYYY-MM-DD        # nothing before this is answerable
timezone:       America/Los_Angeles   # fixed by Cloud Billing, not a choice
console_view:   Billing period    # or "Charge period" (excludes tax/adjustments)
control_sku:    "<sku LIKE pattern>"  -> <N.NNN>/day GROSS, carries no credit
second_control: "<sku LIKE pattern>"  -> <N.NNN>/day GROSS
export_lag_p95: <svc>: <N>h, <svc>: <N>h   # measured once, with export_time
credits:
  - name: "<credit name>"  type: FREE_TIER   shape: pot, ~$X/mo, drains by day ~N
  - name: "<credit name>"  type: PROMOTION   balance: $X remaining, expires YYYY-MM-DD
tax_rate:       ~N.N% of net
commitments:    none | <describe - a cut to covered usage may save ~nothing>
```


A calibration note with: export table id, the control SKU(s) and their exact daily gross
values, the credit inventory with each one's shape **and expiry**, the tax rate, and the
date the export began. Every future session reads this first.

⚠ **This note is sensitive, and so is every report you generate from it.** The export
table name embeds your **billing account id**; the reports contain your spend. If the
repo is public — or is a course repo that will become public — put both somewhere that
cannot be committed by accident:

```gitignore
# cost review outputs - contain billing account ids and real spend
cost-reviews/
calibration.local.md
*.costreview.md
```

Better: keep the calibration note outside the repo entirely (`~/.config/`), and have
scheduled jobs write reports to a private directory. When you want to publish or teach
from a review, publish a **redacted or synthetic** copy — ratios and shapes carry the
lesson; absolute spend and resource names do not.
