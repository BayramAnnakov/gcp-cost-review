# Where the money actually hides

Ordered roughly by how much is usually there and how safely it comes out. For each:
what to look for, how to price it, and the specific thing that makes the naive estimate
wrong.

A useful prior before you start: in most small-to-mid accounts the bill is dominated by
**things that are always on but rarely used**, not by things that are busy. Idle
capacity, not traffic, is the target.

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

**If you make it on-demand, you need three things or it will cost more than it saves:**
a one-command way to bring it up, a **lease with an automatic reaper** so a forgotten
session cannot bill a month, and documentation at the point of confusion - because the
failure mode is silent. A developer whose environment is off usually sees a hang, not an
error, and will spend an hour debugging the wrong end.

Measure the cold start against whatever startup-probe or health-check budget exists
before declaring it usable.

## 2. Always-on serverless instances

Serverless platforms bill very differently depending on whether CPU is allocated
continuously or only during requests. A minimum-instance setting, or a
"CPU always allocated" / "no CPU throttling" flag, converts a pay-per-request service
into a pay-per-hour one.

**Check:** minimum instances and the CPU-allocation flag on every service.
**Price:** the instance-based SKU lines, split by region.
**Trap:** a service that is genuinely never idle saves ~nothing from min-instances=0,
because it would hold the instance anyway. Measure the actual gap between requests before
pricing it. Conversely, flipping CPU throttling back on for a batch-style service can be
one of the largest single wins available, and it is a one-line config change.

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
**Trap:** these are **tiered** services, so dollars mislead (traps A3, A4). Measure in
usage units. Also confirm what reads the data *before* disabling: the answer is often
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

In AI-heavy accounts the model API quickly becomes the largest line, and infrastructure
optimization has a floor. Once the infra lever is spent, the remaining levers are
**model tier**, **prompt caching**, **output-token discipline**, and **not making the
call at all**.

Treat this as demand-side work and measure it per unit of useful output (per request,
per job, per customer), not per month - a monthly total conflates price and volume and
will tell you a cheaper model "did nothing" in a month when usage grew.
