# When there is no billing export yet

This is the most common starting state, and it is where most cost work dies: the method says
"query the export", the reader doesn't have one, and they stop.

You do not have to stop. Do two things in this order.

---

## 1. Turn the export on now — before you do anything else

It only collects **forward**. Every day you wait is a day you can never analyse. Even if you
use the whole workaround below and never run a query this month, enabling it today is what
makes next month answerable.

**Billing → Billing export → BigQuery export → Standard usage cost.**

Two decisions matter and both are easy to get wrong:

| decision | pick | why |
|---|---|---|
| dataset **location** | **US or EU multi-region** | a *first* standard export into a multi-region dataset backfills from the start of the previous month. A region-specific dataset gets nothing retroactive. This is the only backfill on offer and it is one dropdown. |
| **standard** vs **detailed** | start with standard | standard gives service, SKU, project, labels and credits — enough for almost all cost work. Detailed adds per-resource rows and costs more to store; add it later if one SKU turns out to be shared by many resources. |

Backfill can take up to ~5 days to appear. Set it up, then carry on with the rest of this file.

⚠️ Note who can do this: it needs Billing Account Administrator, which is frequently *not* the
person doing the cost review. If that is you, the honest move is to raise a ticket today rather
than discover the blocker in three weeks.

---

## 2. What you can actually do today, without it

Three real instruments. None of them needs the export.

### 2a. The console's own billing reports — attribution, just not SQL

Cloud Billing **Reports** groups by **service, SKU, project and label**, over any date range,
and exports CSV. That is most of what the month-over-month and run-rate steps need.

Work in the CSV: it gives you a table you can sort, which is enough to find your biggest lines
and your biggest movers.

**What you lose, and you should say so out loud in any report you write:**
- per-row **credit detail** — so you cannot tell a capped pot from a 100% discount, which is
  the single most expensive confusion in this whole method (trap A2). Treat every "saving" as
  unconfirmed until you can see the credit.
- arbitrary windows and joins, so no settle gate, no step detection by day, no export-lag
  measurement
- **reproducibility** — a number from a console view that someone else cannot re-run is not
  evidence in the way a query is

Set the report's time range deliberately, and note which view you used: **"Billing period"
includes tax and adjustments; "Charge period" excludes them.**

### 2b. The Recommender API — free, and it is the one thing that finds waste for you

```bash
gcloud recommender recommendations list \
  --project=<PROJECT> --location=<ZONE_OR_REGION> \
  --recommender=google.compute.instance.IdleResourceRecommender \
  --format="table(description,primaryImpact.costProjection.cost.units)"
```

Useful recommender ids:

| recommender | finds |
|---|---|
| `google.compute.instance.IdleResourceRecommender` | VMs doing nothing |
| `google.compute.disk.IdleResourceRecommender` | unattached / unused disks |
| `google.compute.address.IdleResourceRecommender` | reserved external IPs not in use |
| `google.compute.instance.MachineTypeRecommender` | oversized VMs |
| `google.cloudsql.instance.IdleRecommender`, `…OverprovisionedRecommender` | idle / oversized Cloud SQL |
| `google.compute.commitment.UsageCommitmentRecommender` | commitment opportunities |

These carry Google's **own** cost projection, so you get a priced list without any billing data.
Two cautions: `--location` is per zone or region, so you must iterate over the ones you use; and
an empty result means "nothing recommended **here**", not "nothing to find".

### 2c. A structural sweep — find the waste from the resource APIs, price it after

Everything in `where-the-money-hides.md` is *findable* without billing data. You locate it from
the resource APIs and price it from the public price list afterwards. Most of the engagement that
produced this skill was this kind of work; the export told us how much, not what.

```bash
# clusters (each carries a fixed fee) and their node counts
gcloud container clusters list --format="table(name,location,currentNodeCount,autopilot.enabled)"

# reserved addresses not attached to anything
gcloud compute addresses list --filter="status!=IN_USE" \
  --format="table(name,address,region,status,addressType)"

# disks, snapshots, images that nothing uses
gcloud compute disks list --filter="-users:*" --format="table(name,sizeGb,zone)"
gcloud compute snapshots list --format="table(name,diskSizeGb,creationTimestamp)"

# serverless services pinned always-on
gcloud run services list --format="table(name,region)"
# then per service: minimum instances and the CPU-allocation annotation
```

⚠️ **Open the bucket before you name it** — a list is not a finding. Measured while writing this
file: a sweep returned three "unattached" addresses, which looks like free money. All three were
**internal** addresses, and internal addresses are not billed. Only a reserved **external** IP
bills while unattached — and, separately, an external IP attached to a *stopped* instance bills
too. Check the `addressType` column before you count anything.

---

## 3. What you genuinely cannot do, and should not pretend to

Say these out loud rather than producing a number with false precision:

- **reconcile an invoice** — needs `invoice.month` and the non-`regular` rows
- **settle-gate a day**, or know your per-service export lag
- **find a step date**, which is what separates "something changed" from "we changed it"
- **classify credits**, so no capped-pot-vs-proportional call, so no safe pricing of anything
  that carries a credit
- **a defensible run rate**, because you cannot tell a complete day from a partial one

A cost review built on 2a–2c is a **structural audit with estimated prices**. That is genuinely
useful and worth doing this week. It is not the measured review, and labelling it as one is the
failure this whole skill exists to prevent.

---

## 4. The degraded monthly review

Until the export has two complete months in it, run Mode A like this:

| step | with export | without |
|---|---|---|
| 0. settle gate | `settle-gate.sql` | **skip — and say the figures are unsettled** |
| 1. invoice | `invoice-reconcile.sql` | the console invoice page, verbatim |
| 2. run rate | last 7 settled days, gross | last complete month only; no run rate |
| 3. step detection | `step-detect.sql` | month-over-month CSV diff; no step dates |
| 4. new/resumed SKUs | `new-skus.sql` | diff the two CSVs on SKU name |
| 5. regression sweep | — | **unchanged, and it is the most valuable step you still have** |
| 6. one opportunity | — | **unchanged**, priced from the Recommender or the price list |

Steps 5 and 6 need no billing data at all. If you only ever do those two, you are still ahead of
an account nobody looks at.
