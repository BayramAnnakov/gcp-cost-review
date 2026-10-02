# When there is no billing export yet

This is the most common starting state, and it is where most cost work dies: the method says
"query the export", the reader doesn't have one, and they stop.

You do not have to stop. Do two things in this order.

---

## 1. Turn the export on now — before you do anything else

It collects **forward**, with one exception worth planning around: a first export into a US or
EU multi-region dataset backfills from the start of the *previous* month. Beyond that, history
you did not export is gone — and re-enabling it or switching destination later does not
recreate it. So enabling it today is what makes next month answerable, and it costs nothing to
do while you work through the rest of this file.

**Billing → Billing export → BigQuery export → Standard usage cost.**

Two decisions matter and both are easy to get wrong:

| decision | pick | why |
|---|---|---|
| dataset **location** | **US or EU multi-region** | a *first* standard export into a multi-region dataset backfills from the start of the previous month. A region-specific dataset gets nothing retroactive. This is the only backfill on offer and it is one dropdown. |
| **standard** vs **detailed** | start with standard | standard gives service, SKU, project, labels and credits — enough for almost all cost work. Detailed adds per-resource rows and costs more to store; add it later if one SKU turns out to be shared by many resources. |

A third thing is easy to miss: the setup also requires the **BigQuery Data Transfer Service
API** to be enabled on the destination project. Backfill then takes up to ~5 days to appear.
Set it up, then carry on with the rest of this file.

**There is no CLI for this.** `gcloud billing` has no export subcommand — checked, not assumed.
So if you have an agent with browser control, enabling the export is a legitimate and
well-scoped use of it: a one-time, console-only action where a human is sitting there to
approve each step. Have it drive the console with you watching, and make it stop at the
dataset-location dropdown so you consciously choose US or EU multi-region.

**Do not extend that to reading the numbers.** It is tempting — the console has all the data —
but scripted clicking is the wrong instrument for a measurement:

- **the console's own "Download CSV" is strictly better.** One human click gives you a file you
  can analyse, re-analyse and hand to someone else. A click path encoded in a skill rots the
  next time the UI moves, and it rots *silently* — it clicks something adjacent and returns a
  confident wrong number.
- **a figure read off a rendered page is not reproducible**, which is the exact property this
  whole method exists to provide. If you do obtain a number that way, label it as unreproducible
  in the report.
- **absence of evidence is especially unsafe here.** Some agent browser integrations redact tool
  output containing query strings or cookies — and billing console URLs are query-string heavy —
  so "the automation didn't see it" can mean the output was filtered rather than absent. Check
  whether yours does this before trusting a negative. Either way, compute what you need in the
  page and return derived values (counts, booleans, a total) rather than screenshots of tables.

So: **browser for the one-time setup, CSV for the data.**

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

**Use the Cost table, not just Reports.** Reports is for shape; the **Cost table** is expressly
built for invoice reconciliation, exports CSV, and carries **credit type, name and id** per
row. So two things this file used to call impossible are not: you *can* reconcile an invoice,
and you *can* classify credits by type. What the Cost table will not tell you is a credit's
contractual cap or expiry — for that you still need the agreement.

Reports also supports **custom charge-date ranges** and **daily rows** in the CSV, so per-day
movement and an observed change date are available too. Keep the distinction the export makes
easy: an observed change *date* is not causal attribution.

**What you genuinely lose:**
- **export-delivery timestamps** (`export_time`), so no settle gate and no per-service lag
- **arbitrary SQL and joins** across SKU, project, label and credit in one pass
- **reproducibility** — a console view someone else cannot re-run is weaker evidence than a
  query. Mitigate it: archive the report URL (it encodes the configuration), the explicit
  dates, the filters, the download time, and the CSV itself.

Set the report's time range deliberately, and note which view you used: **"Billing period"
includes tax and adjustments; "Charge period" excludes them.**

### 2b. The Recommender API — free, and it is the one thing that finds waste for you

Enable the Recommender API first — a read-only grant cannot do it for you.

```bash
gcloud recommender recommendations list \
  --project=<PROJECT> --location=<ZONE_OR_REGION> \
  --recommender=google.compute.instance.IdleResourceRecommender \
  --format=json        # keep the full JSON - see the warning below
```

Useful recommender ids:

| recommender | finds | `--location` |
|---|---|---|
| `google.compute.instance.IdleResourceRecommender` | VMs doing nothing | zone |
| `google.compute.instance.MachineTypeRecommender` | oversized VMs | zone |
| `google.compute.disk.IdleResourceRecommender` | unattached / unused disks | zone or region, matching the disk |
| `google.compute.address.IdleResourceRecommender` | reserved external IPs not in use | region, or `global` |
| `google.cloudsql.instance.IdleRecommender` | idle Cloud SQL | region |
| `google.cloudsql.instance.OverprovisionedRecommender` | oversized Cloud SQL | region |
| `google.compute.commitment.UsageCommitmentRecommender` | Compute **resource-based** commitment opportunities (not commitments generally) | project **or billing-account** scope depending on CUD sharing — check before assuming |

You must iterate over the zones and regions you actually use. An empty result means "nothing
recommended **here**" — **or that you asked at the wrong granularity**, which is the trap:
measured, asking a zone-scoped recommender at a region (or a region-scoped one at a zone)
returns an empty list with **exit code 0 and no warning**. Only a bogus recommender id errors.
Match the granularity in the table above before concluding there is nothing to find.

⚠️ **Do not read `costProjection.cost.units` on its own.** It is only the whole-number part:
it drops `nanos`, the currency, and the projection's duration — so a fractional saving prints
as `0`, and an unlabelled number gets mistaken for monthly when it is not. Keep the JSON and
compute `units + nanos/1e9`; a **negative** cost is the saving.

⚠️ **These projections exclude credits and additional discounts**, and fall back to list price
unless your permissions expose contract pricing. They are good for **prioritising**, and they
are not a realisable saving — which is exactly the distinction Mode B's Step 3 is about.

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

# serverless services, with the two settings that drive cost, in one pass
# cpu-throttling=false means instance-based billing; minScale>0 keeps instances warm
gcloud run services list --format="table(
  metadata.name,
  metadata.labels['cloud.googleapis.com/location'],
  spec.template.metadata.annotations['autoscaling.knative.dev/minScale'],
  spec.template.metadata.annotations['run.googleapis.com/cpu-throttling'])"
```

⚠️ **Open the bucket before you name it** — a list is not a finding. Measured while writing this
file: a sweep returned three "unattached" addresses, which looks like free money. All three were
**internal**, and internal addresses — static or ephemeral — carry no address charge.

Three qualifiers before you count an address as waste, because `status != IN_USE` is both
over- and under-inclusive:
- **external does not mean billable.** The charge is on IPv4; external **IPv6** has documented
  no-charge cases, including static regional IPv6. Check `ipVersion`, not just `addressType`.
- **a static external IPv4 on a *stopped* VM still bills** — and Google reports it as
  `IN_USE`, so this filter misses it entirely. Look at VM state separately.
- an *ephemeral* external IPv4 is released when the VM stops, so it is not the same case.

And note the direction people usually get wrong: an external IPv4 **in use on a running VM
still bills**, just at a lower hourly rate than an idle reserved one. Forwarding-rule IPs are
free. So "unattached" is where the easy money is, but it is not the whole bill.

---

## 3. What you genuinely cannot do, and should not pretend to

The list is shorter than you would expect, and shorter than an earlier draft of this file
claimed. These four are the real losses:

- **`export_time`**, so no measured per-service export lag. You can still run a settle gate —
  a flat control SKU read off a Date > SKU CSV is the same instrument — but you cannot know
  which *other* services are still arriving.
- **per-row and per-day credit amounts.** The Cost table tells you a credit's *type and name*
  per SKU, so trap A2 is detectable; what you cannot see is the daily shape that distinguishes
  a draining pot from a proportional discount at the row level.
- **arbitrary SQL** — joins across SKU, project, label and credit in one pass, and windows that
  are not a date range.
- **reproducibility by query.** Archive the report URL, the explicit dates, the filters, the
  download time and the CSV, and a reader can at least re-create the view.

A cost review built on 2a–2c is a **structural audit with console-grade measurement**. That is
genuinely useful and worth doing this week. What it is not is a *verified realisable* saving:
the Recommender's projections exclude credits and discounts, and without `export_time` you
cannot say a day is complete. Label it accordingly — that is the failure this whole skill
exists to prevent.

## 4. The degraded monthly review

Until the export has two complete months in it, run Mode A like this:

| step | with export | without |
|---|---|---|
| 0. settle gate | `settle-gate.sql` | **works** — read a flat control SKU off a Date > SKU CSV. What you lose is the per-service lag check, so say which services are unverified |
| 1. invoice | `invoice-reconcile.sql` | **Cost table CSV, unfiltered, unrounded**, against the invoice |
| 2. run rate | last 7 settled days, gross | possible from daily CSV rows, but with no settle gate — quote it only with that caveat |
| 3. step detection | `step-detect.sql` | daily Reports CSV gives the observed change **date**; attribution is still yours to establish |
| 4. new/resumed SKUs | `new-skus.sql` | diff two CSVs on **SKU id**, not name — names change |
| 5. regression sweep | — | **unchanged, and the most valuable step you still have** |
| 6. one opportunity | — | an **estimated** saving with its pricing assumptions stated. Not the verified realisable saving Mode B asks for |

Steps 5 and 6 need no billing data at all. If you only ever do those two, you are still ahead of
an account nobody looks at.

Note what moved in that table versus the pessimistic version: the console reconciles invoices
and classifies credits perfectly well. The irreducible losses are **`export_time`** and
**arbitrary SQL** — not attribution.
