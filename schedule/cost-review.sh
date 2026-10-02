#!/bin/bash
# Scheduled cost review: pre-pulls the data so the review starts with numbers instead
# of with a query. It does NOT write the review - a human (or an agent running the
# skill) still does step 5 and 6, which are the parts that need judgement.
#
# Config lives in ~/.config/gcp-cost-review.env, deliberately OUTSIDE any repo,
# because it names the billing export table - which embeds your billing account id.
#
#   BILLING_EXPORT_TABLE="proj.dataset.gcp_billing_export_v1_XXXXXX"
#   CONTROL_SKU_LIKE="%Your Flat SKU%"
#   SKILL_DIR="$HOME/path/to/gcp-cost-review"
#   PYTHON="$SKILL_DIR/.venv/bin/python"
#   OUT_DIR="$HOME/cost-reviews"          # keep OUT of a public repo: real spend
#
# Two modes, by day of month:
#   the 5th  - review the month that just closed (it has had time to settle)
#   the 20th - mid-month watch: new/resumed SKUs and regressions, no new month yet
set -uo pipefail
source "$HOME/.config/gcp-cost-review.env"
Q="$SKILL_DIR/assets/queries"; BQ="$PYTHON $SKILL_DIR/scripts/bq.py"
TODAY=$(date +%Y-%m-%d); DAY=$(date +%d)

# GNU vs BSD date differ on relative dates; detect once rather than guess.
if date -v-1m +%Y-%m-01 >/dev/null 2>&1; then          # BSD / macOS
  mstart(){ date -v-"$1"m +%Y-%m-01; }
  daybefore(){ date -j -v-1d -f %Y-%m-%d "$1" +%Y-%m-%d; }
  yesterday(){ date -v-1d +%Y-%m-%d; }
else                                                    # GNU / Linux
  mstart(){ date -d "-$1 month" +%Y-%m-01; }
  daybefore(){ date -d "$1 -1 day" +%Y-%m-%d; }
  yesterday(){ date -d "yesterday" +%Y-%m-%d; }
fi

if [ "$DAY" = "05" ]; then
  MODE="month close"; CURR_START=$(mstart 1); CURR_END=$(daybefore "$(date +%Y-%m-01)")
  PREV_START=$(mstart 2); PREV_END=$(daybefore "$CURR_START")
else
  MODE="mid-month watch"; CURR_START=$(date +%Y-%m-01); CURR_END=$(yesterday)
  PREV_START=$(mstart 1); PREV_END=$(daybefore "$CURR_START")
fi

mkdir -p "$OUT_DIR"; OUT="$OUT_DIR/${TODAY}_cost-review.md"
{
  echo "# Cloud cost review - $TODAY ($MODE)"
  echo
  echo "Data only. **Run the \`gcp-cost-review\` skill to finish it** - the regression sweep,"
  echo "the attribution and the one priced opportunity are the parts that need judgement."
  echo "Windows: current $CURR_START..$CURR_END, previous $PREV_START..$PREV_END."
  echo
  echo "## 1. Settle gate - the control must read its known daily GROSS value"; echo '```'
  $BQ "$Q/settle-gate.sql" --set BILLING_EXPORT_TABLE="$BILLING_EXPORT_TABLE" \
     --set START="$CURR_START" --set END="$CURR_END" --set CONTROL_SKU_LIKE="$CONTROL_SKU_LIKE" 2>&1
  echo '```'
  echo "## 2. Invoice - keyed on invoice.month, NOT a usage-date sum"; echo '```'
  $BQ "$Q/invoice-reconcile.sql" --set BILLING_EXPORT_TABLE="$BILLING_EXPORT_TABLE" \
     --set FIRST_INVOICE_MONTH="$(echo "$PREV_START" | tr -d - | cut -c1-6)" \
     --set LAST_INVOICE_MONTH="$(echo "$CURR_START" | tr -d - | cut -c1-6)" 2>&1
  echo
  echo "NOTE: never reconcile the export's FIRST invoice month - it holds only the days after"
  echo "the export was switched on PLUS a full month's tax row, so it looks plausible and is"
  echo "badly wrong. The current month's tax row is absent until it is stamped."
  echo '```'
  echo "## 3. Month over month by service (gross, 30.44-normalised)"; echo '```'
  $BQ "$Q/month-over-month.sql" --set BILLING_EXPORT_TABLE="$BILLING_EXPORT_TABLE" \
     --set PREV_START="$PREV_START" --set PREV_END="$PREV_END" \
     --set CURR_START="$CURR_START" --set CURR_END="$CURR_END" 2>&1
  echo '```'
  echo "## 4. The same, by project - run this before attributing anything"; echo '```'
  $BQ "$Q/by-project.sql" --set BILLING_EXPORT_TABLE="$BILLING_EXPORT_TABLE" \
     --set PREV_START="$PREV_START" --set PREV_END="$PREV_END" \
     --set CURR_START="$CURR_START" --set CURR_END="$CURR_END" 2>&1
  echo '```'
  echo "## 5. New or resumed SKUs - how costs start"; echo '```'
  $BQ "$Q/new-skus.sql" --set BILLING_EXPORT_TABLE="$BILLING_EXPORT_TABLE" \
     --set LOOKBACK_START="$PREV_START" --set CURR_START="$CURR_START" \
     --set CURR_END="$CURR_END" --set MIN_NEW=1 --set GAP_DAYS=7 2>&1
  echo '```'
  echo "## 6. Credit shape per credit - front-loaded? then a late-month NET run rate overstates"; echo '```'
  $BQ "$Q/credit-shape.sql" --set BILLING_EXPORT_TABLE="$BILLING_EXPORT_TABLE" \
     --set START="$CURR_START" --set END="$CURR_END" 2>&1
  echo '```'
  echo "## Still to do by hand"
  echo "- regression sweep: are prior savings still live? read the LIVE config, not the repo"
  echo "- attribute every material step to a named change, or mark it unattributed"
  echo "- pick ONE opportunity, priced, with its risk"
} > "$OUT" 2>&1

echo "$(date) wrote $OUT"
# Optional: notify. Set NOTIFY_CMD in the env file, e.g. a curl to a chat webhook.
[ -n "${NOTIFY_CMD:-}" ] && printf '%s\n' "Cloud cost review ready ($MODE): $OUT" | eval "$NOTIFY_CMD" || true
