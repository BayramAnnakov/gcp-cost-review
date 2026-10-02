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
| `schedule/` | **run it on a schedule** — a runner, a launchd plist, cron and systemd lines |
| `references/no-export-yet.md` | **no export yet?** enable it, and what you can measure meanwhile |
| `scripts/discover.py` | find the billing export and describe its shape |
| `scripts/bq.py` | run a parameterised query and print a readable table |
| `assets/queries/` | the canonical SQL, account-agnostic |

## Install

**Prerequisites**, neither of which the clone gives you — measured in a clean Debian container,
where `pip`, `pip3`, `python3 -m pip` and `ensurepip` were all absent, and so was `gcloud`:

- **Python 3.9+ with pip and venv.** On slim Debian/Ubuntu images `ensurepip` cannot fix this;
  install the distro packages as root first.
- **The Google Cloud CLI** (`gcloud`) if you authenticate that way — it is a separate install.
  (ADC does not *universally* require gcloud; an attached service identity or workload identity
  federation works too. gcloud is simply the usual route on a laptop.)

```bash
git clone https://github.com/BayramAnnakov/gcp-cost-review.git
ln -s "$PWD/gcp-cost-review" ~/.claude/skills/gcp-cost-review
cd gcp-cost-review

# only if pip/venv are missing (slim Linux images), as root:
apt-get update && apt-get install -y python3-pip python3-venv

python3 -m venv .venv && . .venv/bin/activate
python -m pip install -r requirements.txt

gcloud auth application-default login   # credentials for the BigQuery queries
gcloud auth login                       # ALSO needed for the gcloud resource sweeps —
                                        # ADC alone does not authenticate those
```

### What access you need

The `gcloud` login above grants **none** of this. All of it is read-only:

| to… | role | on |
|---|---|---|
| read the bill / invoices | `roles/billing.viewer` | the billing account |
| query the export | `roles/bigquery.dataViewer` (export dataset) **+** `roles/bigquery.jobUser` (the project running queries — often a different one) | BigQuery |
| sweep resources | `roles/viewer` **+** `roles/recommender.viewer` | each project |
| *enable* the export, if absent | `roles/billing.admin` | the billing account |

Those first three are a modest ask and usually land same-day. `billing.admin` is the one that
stalls — it typically sits with finance or a founder, so if the export does not exist yet, ask
for it on day one and work through `references/no-export-yet.md` meanwhile.

Check what you actually have with:

```bash
python scripts/discover.py                    # tries your ADC quota + default projects
python scripts/discover.py my-billing-project # or name it explicitly
```

Querying the export is **billed on bytes scanned**, so `scripts/bq.py` dry-runs every
query, prints the estimate, and refuses anything over `--max-gb` (default 20).

Then just ask: *"why did our GCP bill go up last month?"* or *"run the monthly cloud cost
review"*.

**To make it recurring**, see [`schedule/`](schedule/) — it pre-pulls the data on the 5th (the
month that just closed) and the 20th (a mid-month watch for new SKUs and reverted savings), so
the review starts with numbers. Run it by hand once before you schedule it; the README there
explains why that is not optional.

**Keep your outputs out of git.** The export table name contains your billing account id
and the reports contain real spend. `.gitignore` already excludes `cost-reviews/` and
`calibration.local.md`; keep the calibration note outside the repo if you can.

## The five ways the billing export will mislead you

These are the reason the skill exists. Each has produced a confident, wrong, expensive
answer:

1. **An unsettled day reads low** — and it reads low across every service at once, which
   looks exactly like a successful optimization. (And the gate against it is necessary,
   not sufficient — services export on their own schedules.)
2. **Credits come in several shapes** — free-tier pots, proportional discounts, promotions
   that expire and commitments that floor your bill all share one array. Where a discount
   already takes a SKU to $0.00 net there is no opportunity however large gross looks; where
   a commitment covers it, cutting usage may save nothing at all.
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

- It does not enable the billing export for you. The export collects forward from when it is
  switched on, with one exception: a first export into a US/EU multi-region dataset backfills
  from the start of the previous month. So "why did last quarter change" may be unanswerable
  — the skill says so rather than substituting a worse instrument. **No export at all? Start
  at `references/no-export-yet.md`** — the console does attribute by service, SKU, project and
  label, so there is a real degraded path.
- It does not make changes to your infrastructure. It reads, prices, and tells you what
  to verify.
- It is GCP-specific. The method generalises; the SQL does not.

## Licence

MIT — see [LICENSE](LICENSE).
