# gcp-cost-review

A Claude Code skill for reading, explaining and reducing Google Cloud spend from the
BigQuery billing export — and for running a repeatable monthly cost review.

Most cloud-cost advice is about ideas: turn idle things off, right-size, delete orphans.
Those are cheap and mostly public. What actually goes wrong is **measurement**: the
billing export quietly supports a wrong conclusion, and you ship a change, declare a
saving, and move on while the number came from somewhere else.

So this skill front-loads a measurement contract and only then looks for money. It comes
out of a real multi-week engagement, including the mistakes — several findings in it
exist because a confident estimate turned out to be wrong in a way that was expensive to
discover.

## What's inside

| | |
|---|---|
| `SKILL.md` | the workflow — bootstrap, baseline, attribute, price, ship, verify |
| `references/measurement-contract.md` | how to make your numbers match the console, and the settle gate |
| `references/traps.md` | the catalogue of expensive mistakes, each with its tell |
| `references/where-the-money-hides.md` | where GCP spend actually accumulates, by service |
| `references/monthly-review.md` | the recurring review loop and its report template |
| `scripts/discover.py` | find the billing export and describe its shape |
| `scripts/bq.py` | run a parameterised query and print a readable table |
| `assets/queries/` | the canonical SQL, account-agnostic |

## Install

```bash
git clone https://github.com/bayramannakov/gcp-cost-review.git
ln -s "$PWD/gcp-cost-review" ~/.claude/skills/gcp-cost-review
pip install google-cloud-bigquery
gcloud auth application-default login
```

**You also need BigQuery access, which the login above does not grant.** On the project
that holds the billing export you need to read the data (`roles/bigquery.dataViewer`, or
`bigquery.tables.getData` + `tables.get`), and on whichever project runs the queries you
need `bigquery.jobs.create` (`roles/bigquery.jobUser`). They are often different projects.
Check with:

```bash
python scripts/discover.py                    # tries your ADC quota + default projects
python scripts/discover.py my-billing-project # or name it explicitly
```

Querying the export is **billed on bytes scanned**, so `scripts/bq.py` dry-runs every
query, prints the estimate, and refuses anything over `--max-gb` (default 20).

Then just ask: *"why did our GCP bill go up last month?"* or *"run the monthly cloud cost
review"*.

**Keep your outputs out of git.** The export table name contains your billing account id
and the reports contain real spend. `.gitignore` already excludes `cost-reviews/` and
`calibration.local.md`; keep the calibration note outside the repo if you can.

## The five ways the billing export will mislead you

These are the reason the skill exists. Each has produced a confident, wrong, expensive
answer:

1. **An unsettled day reads low** — and it reads low across every service at once, which
   looks exactly like a successful optimization. (And the gate against it is necessary,
   not sufficient — services export on their own schedules.)
2. **Credits come in two shapes** — a capped pot and a proportional discount share one
   array. For the second, net is $0.00 and there is no opportunity however large gross
   looks.
3. **Tiered allowances reset monthly** — a drop on the 1st is the calendar, not your work.
4. **The credit draw is front-loaded** — so a late-month net run rate overstates the month.
5. **The biggest mover may not be your change** — take credit for it and you will mislead
   the owner and stop looking for the real win.

The defence against all five is the same: establish the measurement contract before you
look for money, find the **step date** rather than splitting a delta, and keep MEASURED
and INFERRED apart in your own words.

## Two techniques worth stealing even if you don't use the skill

**The settle gate.** Pick a SKU that bills an identical amount every day — a fixed-capacity
managed instance, a cluster fee, a reserved address. A day is complete when that SKU reads
its known value, and not before. This beats "wait N days" because lag varies, and beats a
completeness percentage because that is derived from the incomplete data you're trying to
judge.

**Zero versus a fraction.** When you claim a change worked, show the controls. A partial
export yields a *fraction* of something; a change to zero yields *zero*. "It went to zero"
is weak; "it went to zero while ten unrelated workloads all sat at 83–84% of yesterday" is
strong. Check the **row count** too — zero dollars across a normal number of rows is a real
zero, while zero dollars across zero rows is missing data wearing the same costume.

## What this skill does not do

- It does not enable the billing export, and the export does not backfill. If it was
  turned on last week, "why did last quarter change" may be unanswerable — the skill will
  tell you that rather than substituting a worse instrument.
- It does not make changes to your infrastructure. It reads, prices, and tells you what
  to verify.
- It is GCP-specific. The method generalises; the SQL does not.

## Licence

MIT — see [LICENSE](LICENSE).
