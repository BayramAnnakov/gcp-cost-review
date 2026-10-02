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

*(The full catalogue, with the tell for each, is `references/traps.md`. The trap ids below
— A1, A2 and so on — are that file's numbering; this list is the short version.)*

Internalise these before touching a query. Each one has produced a confident, wrong,
and expensive answer in real engagements.

1. **An unsettled day reads low (A1).** The export arrives in batches; the most recent 1-2
   days are partial. Read them as-is and you will "discover" a saving that is export lag.
2. **Credits come in several shapes (A2, B4).** A *capped pot* (a fixed monthly free
   allowance) and a *proportional 100% discount* are both in the same `credits` array.
   For the first, gross is the honest basis. For the second, **net is $0.00 and there is
   no opportunity at all**. Confusing them invents savings that do not exist.
3. **Tiered free allowances reset on the 1st (A3, A4).** A service that drops to near-zero on the
   first of the month did not improve - its allowance reset. The mirror image also bites:
   a $0.00 mid-month can be an allowance *not yet crossed*, which will start billing later.
4. **The credit draw is front-loaded (A5).** A fixed monthly pot is typically consumed in the
   first days of the month. So a *late-month* window is credit-poor, and a net run rate
   taken from it **overstates** the month. Project on gross, then subtract the pot.
5. **The biggest mover may not be your change (A7).** The largest line in a month-over-month
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

**0.0 Check you have the access, before anything else.** Three different capabilities are
involved and they usually sit with **three different people** — knowing that on day one is
worth more than any query here.

| to… | you need | on |
|---|---|---|
| **read the bill** (console reports, invoices) | `roles/billing.viewer` — or `roles/billing.costsManager` | the **billing account** |
| **query the export** | `roles/bigquery.dataViewer` on the export dataset **and** `roles/bigquery.jobUser` on whichever project runs the queries (often a different project) | BigQuery |
| **sweep resources** for the structural audit | `roles/viewer`, plus `roles/recommender.viewer` for the Recommender API | each project |
| **enable the export**, if it does not exist | `roles/billing.admin` | the billing account |
| **act on a finding** | admin/editor for that specific service | the owning project |

**Everything this skill does to analyse is read-only**, and the first three rows are a modest,
easy-to-justify ask — you can usually get them same-day. The last two are the ones that
stall: `billing.admin` is often held by finance or a founder, and acting needs whoever owns
the service. If you can only get read access, you can still do the entire measurement and
hand someone else a priced, evidenced list — say so when you ask, because "I need read-only
on billing" gets approved far faster than "I need access to GCP".

If you are missing something, find out now rather than three steps in. A denied API call
late in an engagement looks like a technical problem and is actually a scheduling one.

> **No billing export?** That is the most common starting state — the method does not
> stop there. Read `references/no-export-yet.md`: how to enable it (and the one dropdown
> that decides whether you get a month of backfill), what you can do *today* without it
> via the console, the Recommender API and a resource-level sweep, and — importantly —
> which conclusions you must not claim until the export exists.

**0.1 Find the billing export.** Cost data lives in a BigQuery table the user must
already have enabled; there is no API that reconstructs it. Run
`scripts/discover.py` - it lists candidate datasets and tables and prints the table id,
its date range, and whether detailed (per-resource) export is on. If nothing is found,
say so plainly: without the export you can read totals in the console but you cannot do
attribution, and enabling it only starts collecting *from now*, so the answer to
"why did last month change" may simply not exist yet.

**0.2 Match the console.** Before trusting any query, reproduce a number the user can
see in the Cloud Console billing report. The conventions that make them agree:
- group days by **US Pacific time** (`America/Los_Angeles`), which is what the Cloud
  Console billing reports use, observing daylight saving — *not* UTC and not the account
  owner's local timezone. Using the wrong one shifts charges across day and month
  boundaries. Also match the console's time-range mode and any savings/credit filters it
  has applied, or you will be comparing two different questions.
- use **net** cost (`cost` + the sum of the `credits` array) - the console shows net
- filter `cost_type = 'regular'` - otherwise tax, adjustments and rounding rows mix in

If your number and the console disagree, stop and resolve it. Every later conclusion
inherits this error.

**Quoting the bill is a different question from analysing spend, and needs a different
key.** To analyse consumption, group by usage date and filter `cost_type='regular'` as
above. To state what was *charged*, group by **`invoice.month`** with **no** `cost_type`
filter, because tax and adjustments are on the invoice and a usage row can land on a
different invoice than its usage date implies. Use
`assets/queries/invoice-reconcile.sql`.

**0.3 Choose a flat-rate control SKU.** This is the highest-leverage step and the one
most people skip. Find a SKU that bills an identical amount every single day - a managed
instance with fixed capacity, a reserved address, a cluster fee. Record its exact daily
value.

That SKU is now your **settle gate**: until the control reads its known value, the day is
certainly incomplete. Record the value on **gross** — credits move a net control for
reasons that have nothing to do with completeness.

**Be precise about what this proves.** The gate is *necessary, not sufficient*. Services
export on their own schedules, so the control can have landed while the service you care
about has delivered no rows yet. A passing gate means "stop treating this day as
obviously partial"; it does not certify the day. Before trusting a per-service number,
look at that service's own daily series and row counts too, and prefer a control in the
same service family when one exists. Twice a year, daylight-saving days bill 23 or 25
hours, so allow a small tolerance rather than reading it as lag.

The control is also your **control group**. When you later claim a change saved money, the
control must *not* move. A saving that moves your control is a measurement artifact.

**0.4 Record the tax and credit shape.** Note the tax rate as a percentage of net (it is
usually stamped at month end and exported later, so a just-closed month may show tax
incomplete), and run `assets/queries/credit-shape.sql` to see whether the credit draw is
flat or front-loaded. You need this to project forward (trap A5).

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

Before pricing anything, check the `credits` array for that SKU with
`assets/queries/credit-inventory.sql`. If a discount already takes it to $0.00 net, the
opportunity is zero no matter how large the gross looks (trap A2).

**But credit arithmetic is not the economics of removing a resource**, and this is where
confident estimates go wrong:
- a credit that looks proportional may be a **time-limited promotion**. When it expires
  the charge appears in full, so "net is $0" can mean "not yet".
- **committed-use discounts invert the logic**: under a spend-based commitment, reducing
  usage can *raise* your net bill, because the commitment fee stays and its utilisation
  offset shrinks. Check for commitments before recommending any reduction.
- allowances shared across projects mean a saving in one project can be absorbed by
  another rather than banked.

Read the credit's **name and expiry**, not just its magnitude, and sanity-check the claim
as an account-level before/after rather than a per-SKU subtraction.

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

**First check your instrument can see it.** This is cheap, it takes one query, and skipping
it is how people spend a week proving nothing.

Pull the SKU's daily series over a stable period and look at its day-to-day spread. If the
saving you expect is smaller than the normal daily variation, **the billing data cannot
confirm it** — not with more patience, not with a longer window, because you are reading a
signal below the noise. A SKU that swings ±$3/day will never testify to a $2/day saving.

When that happens you have three honest options, and "wait and see" is not among them:
- **change instrument** — measure the *usage units* (requests, GiB, samples, node-hours),
  which are usually far less noisy than the dollars derived from them
- **measure structure instead of spend** — "the resource exists / does not exist", "the node
  count went 4 → 3". A binary has no noise floor.
- **say it is unverifiable** and take the change on reasoning, labelled as such

Decide which one *before* you ship, and write it next to the prediction. Finding out
afterwards that the measurement could never have shown the win is the expensive way round.

Then verify only on days the settle gate passes, and look for the signature that
distinguishes a real change from missing data:

> **A partial export yields a fraction of something. A change to zero yields zero.**
> If the target reads a hard 0.000 while unrelated workloads all sit at the same fraction
> of their previous day, that pattern is evidence of a structural change rather than lag.

Quote the controls alongside the result. "It went to zero" is weak; "it went to zero while
ten unrelated workloads all sat at 83-84% of yesterday" is strong. It is still not proof:
a service that has exported *nothing* for that day also reads zero. So check the **row
count**, not only the dollar value — `step-detect.sql` returns it for this reason. Zero
dollars across a normal number of rows is a real zero; zero dollars across zero rows is
missing data wearing the same costume.

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

## The queries, and what each one is for

Run them with `scripts/bq.py <file> --set KEY=VALUE ...`. Every query needs
`BILLING_EXPORT_TABLE`; the timezone is fixed (US Pacific) and is not a parameter. `bq.py`
refuses a query with any placeholder left unsubstituted, and dry-runs for cost first.

| Query | Use it for | Extra placeholders |
|---|---|---|
| `settle-gate.sql` | **always first** — which days are usable | `START`, `END`, `CONTROL_SKU_LIKE` (quote it: it contains spaces) |
| `invoice-reconcile.sql` | what you were actually charged | `FIRST_INVOICE_MONTH`, `LAST_INVOICE_MONTH` (`YYYYMM`) |
| `credit-inventory.sql` | classify credits before pricing anything | `START`, `END`, `MIN_GROSS` (try 5) |
| `credit-shape.sql` | is the credit draw flat or front-loaded | `START`, `END` |
| `month-over-month.sql` | service-level movement, day-normalised | `PREV_START/END`, `CURR_START/END` |
| `by-project.sql` | the same split by project — run before attributing | `PREV_START/END`, `CURR_START/END` |
| `sku-run-rate.sql` | the shortlist of what to attack | `START`, `END`, `MIN_MO` (try 15) |
| `step-detect.sql` | find the step date for one service/SKU | `SERVICE`, `SKU_LIKE` (`%` for the whole service), `START`, `END` |
| `new-skus.sql` | new or resumed lines — how costs start | `LOOKBACK_START`, `CURR_START/END`, `MIN_NEW` (try 1), `GAP_DAYS` (try 7) |

## Reference files

- `references/measurement-contract.md` - the full calibration procedure and the SQL conventions
- `references/traps.md` - the catalogue of expensive mistakes, each with its tell
- `references/where-the-money-hides.md` - where GCP money actually accumulates, by service
- `references/monthly-review.md` - Mode A: the recurring loop and its report template
- `references/no-export-yet.md` - no export, or a brand-new one: enable it, and what to do meanwhile
- `scripts/discover.py` - locate the billing export and summarise its shape
- `scripts/bq.py` - run a query file against the export and print a readable table
- `assets/queries/` - the canonical queries, parameterised
