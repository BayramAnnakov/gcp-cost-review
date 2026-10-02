# Traps

Each of these produced a confident wrong answer in a real engagement. They are ordered
by how often they bite, and each has a **tell** you can check cheaply.

---

## A. Measurement traps

### A1. Reading an unsettled day

**Looks like:** yesterday's spend is down 15%. Something worked.
**Actually:** the export is partial. It is down 15% across *every* service, including
ones you did not touch.
**Tell:** your flat-rate control is below its known daily value.
**Rule:** gate every day on the control. Never quote a number from an ungated day.

### A2. Two credit mechanisms in one array

**Looks like:** a SKU shows meaningful gross spend, so it is an opportunity.
**Actually:** it carries a matching 100% discount credit and nets to $0.00. Turning it
off saves nothing and may break something.
**Tell:** sum the `credits` array for that SKU. If it equals `-gross`, the opportunity is
zero.
**Paid for:** a service was written up as a four-figure annual saving, scheduled for
removal, and was $0.00 net the whole time. It was caught only because an external source
contradicted the claim. Afterwards, sweeping *every* SKU above a threshold for matching
credits found a second one in the same state.
**Rule:** check the credit shape before pricing anything. The habit of "judge on gross"
is correct for a capped pot and actively wrong for a proportional discount.

### A3. Attributing an allowance reset to your change

**Looks like:** metrics or logging spend collapsed on the 1st. Our cleanup worked.
**Actually:** the monthly free allowance reset.
**Tell:** the drop lands exactly on a month boundary; usage units did not move.
**Rule:** for tiered services compare complete months, or compare usage units (MiB, GiB)
rather than dollars.

### A4. The inverse: a $0.00 that is about to start billing

**Looks like:** logging now costs nothing.
**Actually:** the allowance has not been crossed *yet* this month. It will cross around
day 20-25 and start billing.
**Tell:** cumulative usage is tracking toward the allowance, not below it.
**Rule:** project the full month's usage before declaring a tiered SKU free.

### A5. A late-month run rate, taken on net

**Looks like:** the last settled week implies a monthly cost of X.
**Actually:** the fixed credit pot was consumed in the first days of the month, so those
late days carry almost no credit and X is too high.
**Tell:** daily credit totals step down sharply after the first week.
**Rule:** project on gross and subtract the pot as a monthly constant.

### A6. Crediting your own work for someone else's change

**Looks like:** the biggest line in the month-over-month diff fell dramatically right
when you were working.
**Actually:** a different team, a different product in the same billing account, or a
demand shift.
**Tell:** find the **step date** and try to name the change. Split by project. If you
cannot name it, you do not own it.
**Paid for:** in one engagement the largest single line was another product's config
flip on an unrelated day. The honest attributable figure was roughly a third of the
headline.

### A7. Treating a lumpy new line as a run rate

**Looks like:** a new SKU appeared and a 7-day extrapolation says it is material.
**Actually:** the daily values span two orders of magnitude and there is no baseline.
**Tell:** the series is zero for weeks, then erratic.
**Rule:** report "this was reliably zero and is now not, starting on date D" - which is
the actionable fact - and refuse to annualise it until it stabilises.

### A8. A command that fails through a pipe and still exits 0

**Looks like:** `<cmd> | wc -l` returns a plausible count.
**Actually:** the command errored and you counted the lines of the error message. Expired
credentials and disabled APIs both do this.
**Tell:** run the command bare before piping it. Check that the output looks like data.
**Rule:** prefer application-default credentials over short-lived printed tokens for
anything scripted, and never let a pipeline be the first place a command runs.

---

## B. Pricing traps

### B1. Confusing current spend with realisable saving

Current spend is what the item costs today. The saving depends on what you do:
- removed outright → full cost
- time-sliced (non-prod on demand) → only the idle fraction, and usually less than hoped
- migrated → **zero until the old side is deleted**
- resized → the delta between tiers, not the whole line

Report the two numbers separately and label them. A list of "current spend" summed and
presented as "savings available" is the most common way cost work loses credibility.

### B2. Forgetting that a migration pays twice

During a dual-run you pay for both sides. The saving banks **on deletion**, which is the
step people defer because it is the scary one. A migration left dual-running
indefinitely is a cost *increase*.

**Rule:** make the deletion an explicit, scheduled, owned step with a rollback window,
or do not start.

### B3. Right-sizing requests on a bursting platform

**Looks like:** pods request far more CPU than they use; cutting requests saves money.
**Actually:** on GKE Autopilot you are billed for requests, but you also **burst into the
sum of requests on the node**. Cutting requests shrinks the pool you burst into, so the
workload can get slower while saving less than modelled.
**Tell:** actual usage is spiky, and the headroom is doing real work.
**Rule:** treat request right-sizing as a performance change that happens to affect cost.
Prove it with a load test, not a spreadsheet.

### B4. Summing items that are not additive

Two savings can overlap (deleting a cluster removes the nodes *and* the fee *and* some
network charges counted separately), or be mutually exclusive, or be ordered (A is only
available after B). Say which, and give the ordering constraint.

---

## C. Execution traps

### C1. Turning off something that was turned on for a reason

**Rule:** before disabling anything, grep the repo, the incident log and the issue
tracker for the prior attempt. Resources rarely carry the reason they exist. In more
than one case the "obviously idle" thing was the fix for a past outage.

### C2. Reasoning about consumers instead of checking

A negative grep in one directory is a hypothesis. Verify from logs, metrics, or the
running system before concluding nothing uses a thing. Where a control is available, run
the same query shape against something you *know* is live, to prove the query can return
a non-zero answer at all.

### C3. Shipping a safety net without running it

A guard that fails silently is worse than no guard. Execute it end to end, including its
failure path, and watch it act.

**Paid for:** a scale-down job was deployed in a container image that did not include the
CLI it invoked. Every run errored; the error was being discarded; the job looked healthy
and did nothing. A design review had approved it - a reading gate cannot detect a missing
binary.

### C4. Assuming the change is still live when you read the result

Declarative tooling re-applies the committed state. A deploy, a sync, or a teammate can
revert your change without telling you, and your verification will then measure the old
world.

**Rule:** read the live configuration back from the running system as the first step of
any verification, and say that you did.

### C5. Scripts that only ran on your machine

Portability bugs show up in cost tooling constantly because it is written quickly and
run rarely: shell builtins that differ between versions, `sed`/`date` flags that differ
between GNU and BSD, a binary present locally and absent in the container.

**Rule:** run the thing in the environment it will actually run in, once, before trusting
it.
