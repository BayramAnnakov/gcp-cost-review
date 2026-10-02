# Where the money actually hides

Ordered roughly by how much is usually there and how safely it comes out. For each:
what to look for, how to price it, and the specific thing that makes the naive estimate
wrong.

A hypothesis to test early, not a fact to assume: idle capacity is often a bigger share
of a bill than busy capacity. It is worth checking first because it is cheap to check and
safe to fix — but **establish your own account's distribution before believing it**. Run
`sku-run-rate.sql` and look. An account dominated by egress, model APIs or storage has a
different shape, and starting from the wrong prior wastes the whole engagement.

---

## 1. Non-production environments running 24/7

Staging, test, dev, QA, preview and demo environments usually cost the same as
production and are used during working hours at best.

**Check:** every environment's replica count / instance count, and the actual request or
message volume it served in the last 30 days.
**Price:** full cost if it can be deleted; the idle fraction if it becomes on-demand.
**Trap:** the realisable number is much lower than the gross. An environment used two
hours a day does not save 92% - you still pay for the storage, the addresses, the cold
starts and the hours somebody forgets to turn it off.

**⚠ On Kubernetes, know which billing model you are on before pricing anything.** They
behave oppositely:
- **Autopilot** generally bills *pod resource requests*, so scaling a workload to zero removes
  the charge directly. Not universally: Autopilot pods that select particular hardware are
  billed on a node basis instead.
- **Standard** bills *nodes*. Deleting pods changes nothing by itself — you keep paying for the
  VMs until the cluster autoscaler removes them, and it can only scale down to the pool's
  minimum. Pods that cannot be rescheduled elsewhere will also hold a node up.

The label on the cluster is not the answer: a Standard cluster can host Autopilot workloads,
so **determine the billing mode of the workload**, not of the cluster. Either way, on a
node-billed workload the saving is "can a node be removed", not "can a pod be stopped" —
verify against the node count after the change.

**If you make it on-demand, you need three things or it will cost more than it saves:**
a one-command way to bring it up, a **lease with an automatic reaper** so a forgotten
session cannot bill a month, and documentation at the point of confusion - because the
failure mode is silent. A developer whose environment is off usually sees a hang, not an
error, and will spend an hour debugging the wrong end.

Measure the cold start against whatever startup-probe or health-check budget exists
before declaring it usable.

## 2. Always-on serverless instances

Serverless platforms bill very differently depending on whether CPU is allocated continuously
or only during requests. The "CPU always allocated" / "no CPU throttling" setting is what
switches a service to instance-based billing. A minimum-instance setting is a *separate*
control — it keeps instances warm and they accrue idle charges, but it does not by itself
change the billing mode.

**Check:** minimum instances *and*, separately, the CPU-allocation / billing setting. They are
two different things and conflating them produces wrong prices. A **request-billed** service
can still have minimum instances, and those idle instances still bill — at a lower idle rate,
on their own SKU. Cloud Run **jobs** are always instance-billed regardless.
**Price:** the instance-based SKU lines, split by region — **and** the request-billed idle
lines, which a search for "instance-based" alone will miss.

**Trap 1:** a service that is genuinely never idle saves ~nothing from `min-instances=0`,
because it would hold the instance anyway. Measure the real gap between requests first.

**⚠ Trap 2, and this one can break production.** Turning CPU throttling back *on* is
sometimes a large one-line win — and sometimes an outage. CPU-always-allocated exists so a
container can do work **outside** a request: background goroutines, async flushes, queue
consumers, retries and telemetry after the response is sent. Throttled, that work is
suspended between requests and may never finish.

Before changing it, establish that the service does nothing outside the request lifecycle
— from its code and its traces, not from its name. "Batch-style" is a guess about a
service; it is not a property you can read off the billing export. If you cannot establish
it, leave the flag alone and take the saving elsewhere.

## 3. Cluster and control-plane fees

Every cluster carries a fixed fee whether or not anything runs on it. Accounts
accumulate clusters - one per team, one for a migration, one from a marketplace install.

**Check:** the cluster count against the workload. Could two clusters hold everything?
**Price:** fee per cluster per month, plus the node pool for any cluster you can empty.
**Trap:** a free-tier allowance may cover one cluster's fee, which disguises the cost of
the others. Judge on gross (see the capped-pot rule).

## 4. Self-inflicted observability volume

Frequently the fastest safe win, because nothing reads most of it.

**Check:** which metric sources are enabled on your clusters, and which metric families
actually appear in dashboards or alerts. Per-container and per-node metric collectors can
produce an enormous sample volume for data nobody queries. Same for log sinks that
duplicate what another system already stores.
**Price:** samples or GiB ingested, converted at the published rate.
**Trap:** pricing models differ *within* observability, so one rule does not cover it.
Cloud Monitoring metrics are byte-priced with a monthly free allotment, so dollars
mislead and you should measure usage units (traps A3, A4). **Managed Service for
Prometheus is priced per sample ingested and has no free allotment**, so its dollars track
volume directly from the first sample. Check which one you are looking at before applying
either rule, and read `usage.amount` and `usage.pricing_unit` rather than assuming. Also confirm what reads the data *before* disabling: the answer is often
"one dashboard nobody opens", but occasionally it is an alert that matters.
**Identify the source precisely.** Group ingested samples by metric family before
blaming a component; it is easy to accuse the wrong collector and disable something
useful while the real volume continues.

## 5. Oversized managed databases and caches

**Check:** CPU and memory utilisation over 30 days against the provisioned tier; and
whether a managed cache could be an in-cluster pod.
**Price:** the tier delta.
**Trap:** managed services include failover, auth, TLS and backups. Moving a cache
in-cluster trades real money for real operational risk - a cold cache after any eviction
or upgrade, and a stampede onto the database behind it. Price the risk, do not just
price the instance.

## 6. Orphans

The purest wins: nothing breaks, because nothing is using them.

**Check:** unattached persistent disks; static/reserved IP addresses not bound to a
running resource (an address attached to a *stopped* instance still bills); old
snapshots and images; load balancers with no healthy backend; idle NAT gateways.
**Price:** full cost.
**Trap:** an address may be referenced by configuration even while unattached, and
releasing it means it cannot be reclaimed. Check for the address as a literal across the
codebase and secrets before releasing. The safe move for an address that must keep its
value is to **reserve** it, not release it.

## 7. Artifact and image storage

Registries accumulate every image ever built and are rarely pruned.

**Check:** storage per repository and whether any cleanup policy exists.
**Price:** GB-month over the free allowance.
**Trap:** run the cleanup policy in **dry-run** first and read what it would delete.
Keeping "recent tags" is not enough - a rollback target may be old, and a digest pinned
in a manifest may not carry a tag at all.

## 8. Network: egress, connectors, inter-region

**Check:** egress by destination; serverless VPC connectors (they run minimum instances
of their own); cross-region and cross-zone traffic between chatty services.
**Price:** per-GB egress; per-instance connector cost.
**Trap:** connectors can be partly cancelled by a free-tier discount on their instance
type, so the realisable saving is uneven across them and removing one may shift the
discount rather than bank it. Price each one individually.

## 9. Scheduled jobs nobody reviews

**Check:** every cron/scheduler entry, its frequency, and whether its twin in another
environment is paused. A job running every minute in staging against a paid API is a
common silent cost.
**Price:** invocation count × downstream cost - usually the API calls dominate, not the
scheduler.

## 10. The model bill, once infrastructure is tidy

⚠ **Know which side of the line each model bill sits on.** Models you consume *through Google*
— Vertex AI, the Gemini API, and partner models such as Claude purchased via Vertex — are
Google-billed and **do** appear in this export under their own SKUs. Models you buy *directly
from the vendor* do not appear at all. So a "total AI spend" from the export alone can both
**understate** (missing direct vendor invoices) and, if you then add those invoices without
checking, **double-count** the partner models already in it. Enumerate the SKUs first, then
add only what is genuinely absent, and say that you combined sources.


In AI-heavy accounts the model API quickly becomes the largest line, and infrastructure
optimization has a floor. Once the infra lever is spent, the remaining levers are
**model tier**, **prompt caching**, **output-token discipline**, and **not making the
call at all**.

Treat this as demand-side work and measure it per unit of useful output (per request,
per job, per customer), not per month - a monthly total conflates price and volume and
will tell you a cheaper model "did nothing" in a month when usage grew.
