# Scheduling the review

The review is only useful if it happens. This pre-pulls the data on a schedule so the
review starts with numbers rather than with a query — then you (or an agent running the
skill) do the parts that need judgement: the regression sweep, the attribution, and the
one priced opportunity.

**Cadence: the 5th and the 20th.** The 5th reviews the month that just closed, by which
time it has had time to settle. The 20th is a mid-month watch — no new month has closed,
so it is there to catch new or resumed SKUs and savings that have quietly reverted.

## Setup

```bash
cp schedule/cost-review.env.example ~/.config/gcp-cost-review.env
chmod 600 ~/.config/gcp-cost-review.env     # it names your billing export table
$EDITOR ~/.config/gcp-cost-review.env
bash schedule/cost-review.sh                # RUN IT BY HAND FIRST
```

**Run it by hand before you schedule it, and open the file it produced.** A scheduled job
you have never executed is a job you are hoping works, and cost tooling fails quietly: an
unquoted config value, a missing binary, a query whose placeholders you renamed. Every one
of those has happened to this script. If a section of the output is empty, fix it now —
on the 5th nobody is watching.

### macOS (launchd)

```bash
cp schedule/com.example.gcp-cost-review.plist ~/Library/LaunchAgents/
$EDITOR ~/Library/LaunchAgents/com.example.gcp-cost-review.plist    # set the path
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.gcp-cost-review.plist
launchctl kickstart -k gui/$(id -u)/com.example.gcp-cost-review      # prove it fires
```

Remove with `launchctl bootout gui/$(id -u)/com.example.gcp-cost-review`.

### Linux (cron)

```cron
0 9 5,20 * * /bin/bash $HOME/gcp-cost-review/schedule/cost-review.sh >> /tmp/gcp-cost-review.log 2>&1
```

### Linux (systemd timer)

`OnCalendar=*-*-05,20 09:00:00`, with a `Type=oneshot` service running the script.

## Notification

Set `NOTIFY_CMD` in the env file and it receives the one-line summary on stdin — a desktop
alert, a chat webhook, whatever you read. Leave it unset and the script just writes the file.

## Don't commit the output

Reports contain real spend and the export table name embeds your billing account id. Point
`OUT_DIR` somewhere outside the repo; the root `.gitignore` already excludes `cost-reviews/`
and `*.local.env` in case you don't.

## Why not a cloud scheduler

Because the queries run as *you*. A hosted agent has no access to your local
application-default credentials, so it cannot read your billing export without a separate
service account and key — which is a bigger security decision than a cost review warrants.
Run it where your credentials already are.
