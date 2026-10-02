# Mode A - the monthly review

A recurring ~30-minute pass. Its job is **not** to find savings - that is Mode B. Its job
is to answer four questions honestly and quickly:

1. What did we actually bill, and did it move?
2. Did anything we previously fixed come back?
3. Did anything new appear?
4. Is there one thing worth doing this month?

Run it after the month is **fully settled** - usually a few days in. Running it on the 1st
produces a confident wrong answer (trap A1).

## The loop

### 0. Settle gate — `settle-gate.sql`

Check the flat-rate control reads its known **gross** value for every day of the month being
reviewed, and note the first day where it does not. Exclude that day and everything after it.
If the month is not settled, stop and come back — do not "adjust for lag".

**Then do the half people skip.** A passing control says the day is *not obviously* partial;
it does not certify it, because services export on their own schedules. Put the per-service
`export_lag_p95` from your calibration note next to this month's spend by service, and for any
service that is both **slow and material**, check its own daily series before quoting it. A
service that arrives late and bills ~nothing can be ignored; one that arrives late and is a top
line cannot.

### 1. Invoice reconciliation — `invoice-reconcile.sql`

Last complete month vs the one before, as the user will see it on the invoice. Use
`assets/queries/invoice-reconcile.sql`, which differs from every other query here on
purpose:

- it groups on **`invoice.month`**, not on a usage date — a row can land on a different
  invoice than its usage date implies, because late-arriving usage is billed on the next one
- it does **not** filter `cost_type`, because tax and adjustments are on the invoice

`regular gross` → `tax` → `adjustments` → `credits` → **invoice total**

Quote the invoice figure, not a usage-date sum. People reconcile against the invoice, and
a report that does not match it gets discarded — and the two genuinely differ.

Note if tax looks incomplete (it is exported late) and say so rather than quietly
under-reporting.

### 2. Run rate — `sku-run-rate.sql`, `credit-shape.sql`

The last settled 7 days, **on gross**, normalised ×30.44. This is what next month looks
like if nothing changes - more useful than the month just closed, because mid-month
changes are only partly reflected in a monthly total.

Then re-apply credits deliberately rather than by one subtraction, because a flat
"minus the pot" quietly contradicts the rules above:
- **capped pot** → subtract it once, and never below the eligible spend. If projected
  gross for that SKU is 50 and the allowance is 70, the answer is 0, not −20.
- **proportional discount** → scale with the projection, do not subtract a constant.
- **tiered allowance** → if the 7-day window sat inside the free allowance, extrapolating
  it projects $0 for a service that will start billing mid-month. Project the month's
  **usage** against the allowance, then price it.
- **fixed monthly fees** (cluster fees, subscriptions) → carry them as monthly constants
  rather than ×30.44 of a daily slice.

A single number is still fine to publish. Just build it from those four, and say which
input is doing the work.

Split **demand-driven** lines (model APIs, egress, anything that scales with usage) from
**structural** lines (instances, fees, storage). They behave differently and mixing them
makes both unreadable.

### 3. Step detection — `month-over-month.sql`, then `by-project.sql`, then `step-detect.sql`

For every service that moved more than ~10% or more than a material absolute amount,
pull the daily series and find the step date. Then name the cause. Three outcomes, all
acceptable, but say which:

- **named** - matched to a deploy, PR, config change or audit entry
- **demand** - no config change; volume moved
- **unattributed** - you could not name it. Write it down as unattributed rather than
  guessing; an unexplained step is itself a finding worth carrying forward.

### 4. New-or-resumed SKU check — `new-skus.sql`

The highest-value five minutes in the whole review, and the one most people skip.

List every SKU that was **~zero last month and is not now**. New lines are how costs
start, and they are invisible in a service-level month-over-month view because they are
small at first and buried inside a service that already had spend.

Report them as "this was reliably zero until date D" and resist annualising a lumpy new
series (trap A8).

### 5. Regression sweep

Re-verify that previous savings are still in force, by reading the **live
configuration**, not the repo:

- things set to zero replicas - still zero?
- disabled components - still disabled?
- deleted resources - still absent?
- minimum instances / CPU-allocation flags - unchanged?

Declarative tooling re-applies committed state, and a change made by hand is one deploy
away from being undone. This check is why the monthly review earns its place: savings
decay silently.

### 6. One opportunity

Pick **one** item, priced, with its realisable saving and its risk. Not a list of twelve.
A single item with a number and an owner gets done; a list gets archived.

## Report template

Keep it short enough to read in full. If it runs past a page, the detail belongs in an
appendix.

```markdown
# Cloud cost review - <MONTH>

**Settled through <DATE>** (control SKU at its known gross value; later days excluded).
Slow-but-material services checked individually: <LIST, or "none">.

## Invoice
Reconciled on `invoice.month` (see step 1) — not on a usage-date sum.

| `invoice.month` | <PREV> | <CURR> |
|---|---:|---:|
| regular gross | | |
| tax | | |
| adjustments / rounding | | |
| credits | | |
| **invoice total** | | |

**<DELTA>, <PCT>.**

## Run rate (last 7 settled days, gross, ×30.44)
| Line | Last month | Run rate | Δ |
|---|---:|---:|---:|
| structural | | | |
| demand-driven | | | |

Next month lands near **<ESTIMATE>** if nothing changes. The band is driven by
<THE VOLATILE INPUT>, which ran <P10>-<P90> per day this month.

## What moved, and why
| Service | Δ | Step date | Cause | Basis |
|---|---:|---|---|---|
| | | | named / demand / unattributed | MEASURED / INFERRED |

## New this month
Lines that were ~zero last month:
- <SKU> - zero until <DATE>, now <RANGE>/day. Not yet a run rate.

## Regressions
Previously banked savings, re-verified against the live system:
- <ITEM> - still in force / **reverted on <DATE>**

## This month's one thing
<ITEM>: costs <CURRENT>/mo today, realisable saving <SAVING>/mo, risk <RISK>.

## Not checked
<WHAT YOU DID NOT LOOK AT>
```

That last section is not padding. A review that reads as exhaustive when it sampled three
services will stop anyone else from looking, and the thing you skipped is where the next
surprise comes from.

## Making it stick

- Keep the calibration note and the prior reviews where the next session will find them,
  so each month starts from the last one instead of from scratch — but **not in a public
  repo**. The export table id embeds your billing account id and the reports carry real
  spend. Use a private directory and a `.gitignore` entry; publish only redacted or
  synthetic versions.
- Record a **prediction** each month ("next month lands near X") and check it next time.
  A review that never commits to a number cannot be wrong, and therefore never improves.
- Carry unattributed steps forward until they are explained or go away.
