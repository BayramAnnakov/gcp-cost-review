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

### 0. Settle gate

Check the flat-rate control reads its known value for every day of the month being
reviewed, and note the first unsettled day. Exclude that day and everything after it from
every figure. If the month is not settled, stop and come back - do not "adjust for lag".

### 1. Invoice reconciliation

Last complete month vs the one before, as the user will see it on the invoice:

`regular gross` → `credits` → `net` → `tax` → `adjustments` → **invoice**

Quote the invoice figure, not just the usage figure. People reconcile against the
invoice, and a report that does not match it gets discarded.

Note if tax looks incomplete (it is exported late) and say so rather than quietly
under-reporting.

### 2. Run rate

The last settled 7 days, **on gross**, normalised ×30.44. This is what next month looks
like if nothing changes - more useful than the month just closed, because mid-month
changes are only partly reflected in a monthly total.

Subtract the credit pot separately (trap A5).

Split **demand-driven** lines (model APIs, egress, anything that scales with usage) from
**structural** lines (instances, fees, storage). They behave differently and mixing them
makes both unreadable.

### 3. Step detection

For every service that moved more than ~10% or more than a material absolute amount,
pull the daily series and find the step date. Then name the cause. Three outcomes, all
acceptable, but say which:

- **named** - matched to a deploy, PR, config change or audit entry
- **demand** - no config change; volume moved
- **unattributed** - you could not name it. Write it down as unattributed rather than
  guessing; an unexplained step is itself a finding worth carrying forward.

### 4. New-SKU check

The highest-value five minutes in the whole review, and the one most people skip.

List every SKU that was **~zero last month and is not now**. New lines are how costs
start, and they are invisible in a service-level month-over-month view because they are
small at first and buried inside a service that already had spend.

Report them as "this was reliably zero until date D" and resist annualising a lumpy new
series (trap A7).

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

**Settled through <DATE>** (control SKU at its known value; later days excluded).

## Invoice
| | <PREV MONTH> | <MONTH> |
|---|---:|---:|
| regular gross | | |
| credits | | |
| net | | |
| tax | | |
| **invoice** | | |

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

- Keep the calibration note and the prior reviews in the repo, so each month starts from
  the last one instead of from scratch.
- Record a **prediction** each month ("next month lands near X") and check it next time.
  A review that never commits to a number cannot be wrong, and therefore never improves.
- Carry unattributed steps forward until they are explained or go away.
