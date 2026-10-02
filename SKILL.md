---
name: gcp-cost-review
description: Measure, explain and reduce Google Cloud spend from the BigQuery billing export, and run a repeatable monthly cost review. Use this whenever the user asks why their GCP bill changed, wants to cut cloud costs, mentions a billing export / cost dashboard / "our GCP bill", asks for a monthly or quarterly cloud spend review, wants to know whether a cost optimization actually worked, or asks you to find savings in Google Cloud - even when they just say "our cloud bill went up" or "can we spend less on infra" without naming a tool. Also use before claiming any cloud saving is real, because the billing export misleads in five specific ways this skill defends against.
---

# GCP cost review

Cloud cost work fails far more often on **measurement** than on ideas. The ideas are
cheap and mostly public: turn idle things off, right-size, delete orphans. What
actually goes wrong is that the billing data quietly supports a wrong conclusion, and
you ship a change, declare a saving, and move on - while the number came from
somewhere else.

So this skill front-loads a **measurement contract** and only then looks for money.
Work through it in order. A finding produced before the contract is established is not
a finding, it is a guess with a dollar sign on it.

## The five ways the billing export will mislead you

Internalise these before touching a query. Each one has produced a confident, wrong,
and expensive answer in real engagements.

1. **An unsettled day reads low.** The export arrives in batches; the most recent 1-2
   days are partial. Read them as-is and you will "discover" a saving that is export lag.
2. **Credits come in two different shapes.** A *capped pot* (a fixed monthly free
   allowance) and a *proportional 100% discount* are both in the same `credits` array.
   For the first, gross is the honest basis. For the second, **net is $0.00 and there is
   no opportunity at all**. Confusing them invents savings that do not exist.
3. **Tiered free allowances reset on the 1st.** A service that drops to near-zero on the
   first of the month did not improve - its allowance reset. The mirror image also bites:
   a $0.00 mid-month can be an allowance *not yet crossed*, which will start billing later.
4. **The credit draw is front-loaded.** A fixed monthly pot is typically consumed in the
   first days of the month. So a *late-month* window is credit-poor, and a net run rate
   taken from it **overstates** the month. Project on gross, then subtract the pot.
5. **The biggest mover may not be your change.** The largest line in a month-over-month
   diff is often somebody else's deploy, a different product, or demand. Take credit for
   it and you will both mislead the owner and stop looking for the real wins.

## Pick a mode

**Mode A - Monthly review** (recurring, ~30 min): has anything changed, did prior
savings hold, what is new. Read `references/monthly-review.md`.

**Mode B - Optimization engagement** (one-off, multi-session): find, price, ship and
verify savings. Continue below, then read `references/where-the-money-hides.md`.

Both modes require Step 0 first.

## Step 0 - Bootstrap the measurement contract

Do this once per account, then record the answers so later sessions skip it.

**0.1 Find the billing export.** Cost data lives in a BigQuery table the user must
already have enabled; there is no API that reconstructs it. Run
`scripts/discover.py` - it lists candidate datasets and tables and prints the table id,
its date range, and whether detailed (per-resource) export is on. If nothing is found,
say so plainly: without the export you can read totals in the console but you cannot do
attribution, and enabling it only starts collecting *from now*, so the answer to
"why did last month change" may simply not exist yet.

**0.2 Match the console.** Before trusting any query, reproduce a number the user can
see in the Cloud Console billing report. The conventions that make them agree:
- group days by the **billing account's own timezone** (often US/Pacific), not UTC
- use **net** cost (`cost` + the sum of the `credits` array) - the console shows net
- filter `cost_type = 'regular'` - otherwise tax, adjustments and rounding rows mix in

If your number and the console disagree, stop and resolve it. Every later conclusion
inherits this error.

**0.3 Choose a flat-rate control SKU.** This is the highest-leverage step and the one
most people skip. Find a SKU that bills an identical amount every single day - a managed
instance with fixed capacity, a reserved address, a cluster fee. Record its exact daily
value.

That SKU is now your **settle gate**: a day is complete when the control reads its known
value, and not before. This beats any lag heuristic because it is a direct observation
rather than a model of when data usually arrives.

It is also your **control group**. When you later claim a change saved money, the control
must *not* move. A saving that moves your control is a measurement artifact.

**0.4 Record the tax and credit shape.** Note the tax rate as a percentage of net (it is
usually stamped at month end and exported later, so a just-closed month may show tax
incomplete), and run `assets/queries/credit-shape.sql` to see whether the credit draw is
flat or front-loaded. You need this to project forward (trap 4).

Write all four answers into a short calibration note in the user's repo. Future sessions
should read it instead of re-deriving it - re-deriving invites a different answer.

## Step 1 - Establish the baseline, honestly

Compare **complete months**, normalised to a 30.44-day month so a 31-day month, a
28-day month and a 9-day sample are all comparable. Never compare a complete month to a
partial window raw.

Prefer **gross** for anything touching a capped-pot credit, and say which basis you used
every time you quote a number. "Down 20%" means nothing without it.

For tiered services (metrics, logs), compare **usage units** (MiB, GiB) rather than
dollars, because dollars there are a function of the allowance, not of your change.

## Step 2 - Find the step, not the delta

A month-over-month delta tells you something changed. It does not tell you what, and
splitting the delta across plausible causes is how people end up crediting the wrong
work.

Instead, for each service that moved materially, pull the **daily series** and find the
**step date** (`assets/queries/step-detect.sql`). Then match that date against an actual
event: a deploy, a merged PR, a config change, an audit log entry. 

**If you cannot name the change that produced the step, you do not own the saving.**
Write it down as unattributed. In one engagement the single largest line in the diff
turned out to be a different product's deploy on an unrelated day; the honest
attributable number was roughly a third of the headline. Reporting the headline would
have been wrong and would have hidden that the real work was elsewhere.

Split by project before celebrating - a billing account often spans more than one.

## Step 3 - Price candidates, and check for a credit first

For each candidate, state the **current spend on that item** and, separately, the
**realisable saving**, which is usually smaller:
- an item removed outright saves its full cost
- an item time-sliced (non-prod running only on demand) saves only the idle fraction
- an item migrated saves nothing until the **old side is deleted** - until then you pay twice

Before pricing anything, check the `credits` array for that SKU. If a proportional
discount already takes it to $0.00 net, the opportunity is zero no matter how large the
gross looks (trap 2).

Then read `references/where-the-money-hides.md` for the catalogue of what to check, and
`references/traps.md` for the per-item gotchas that make a confident estimate wrong.

## Step 4 - Before you turn anything off

Three checks, each of which has saved a real outage:

- **Grep the repo and the issue tracker for the prior attempt.** Something that looks
  obviously wasteful is sometimes the fix for an incident nobody wrote on the resource.
- **Ask who consumes it** - and verify from logs or metrics, not from reasoning. A
  negative grep is a hypothesis, not proof of absence.
- **Know the rollback** and confirm it is real before the change, not after.

Prefer the cheapest and most reversible items first, and do free prerequisites (security
fixes, probes, pinned addresses) before anything that banks money. They make later steps
safer and they cost nothing to sequence first.

## Step 5 - Predict, then verify on settled data

Write the expected number **before** you look: "SKU X falls from A/day to B/day; control
stays at C." A prediction made after seeing the data is not a test.

Then verify only on days the settle gate passes, and look for the signature that
distinguishes a real change from missing data:

> **A partial export yields a fraction of something. A change to zero yields zero.**
> If the target reads a hard 0.000 while every control sits at the same fraction of its
> previous day, the zero is structural, not lag.

Quote the controls alongside the result. "It went to zero" is weak; "it went to zero
while ten unrelated workloads all sat at 83.4-83.5% of yesterday" is conclusive.

Then confirm the change is **still live** by reading it back from the running system. A
reading taken after something silently reverted means nothing, and reverts happen - a
declarative apply, a redeploy, or a teammate can put it back.

## Step 6 - Report

Keep MEASURED and INFERRED separate, in your own words, every time. A number you
computed and a number you reasoned to are different objects, and the reader cannot tell
them apart unless you say so.

State what you did **not** check. A cost report that reads as complete when it sampled
three services will stop anyone else from looking.

## Automated guards must be executed, never just reviewed

If the work adds a safety net - a scheduler that scales idle things down, a budget alert,
a cleanup job - **run it end to end and watch it act**, including its failure path.

A guard that fails silently is worse than no guard, because it buys false confidence. In
one engagement a scale-down job was deployed in an image that did not contain the CLI it
called; every run errored, the error was swallowed, and the job looked healthy while
doing nothing. A design review had already approved it - a reading gate cannot catch a
missing binary. Only running it can.

## Reference files

- `references/measurement-contract.md` - the full calibration procedure and the SQL conventions
- `references/traps.md` - the catalogue of expensive mistakes, each with its tell
- `references/where-the-money-hides.md` - where GCP money actually accumulates, by service
- `references/monthly-review.md` - Mode A: the recurring loop and its report template
- `scripts/discover.py` - locate the billing export and summarise its shape
- `scripts/bq.py` - run a query file against the export and print a readable table
- `assets/queries/` - the canonical queries, parameterised
