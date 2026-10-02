#!/usr/bin/env python3
"""Run a SQL file against the billing export and print a readable table.

Usage:
    python bq.py QUERY.sql [--project P] [--set KEY=VALUE ...]

Placeholders of the form <KEY> in the SQL are replaced by --set values, so the
canonical queries in assets/queries/ stay account-agnostic. Example:

    python bq.py assets/queries/settle-gate.sql \
        --set BILLING_EXPORT_TABLE=proj.ds.gcp_billing_export_v1_XXXX \
        --set START=2026-09-01 --set END=2026-09-30 \
        --set 'CONTROL_SKU_LIKE=%Redis Capacity%'      # quote it: it contains a space

Uses Application Default Credentials on purpose. A printed short-lived access
token is a frequent source of a command that fails through a pipe while exiting 0.
"""
import argparse
import re
import sys

try:
    import google.auth
    from google.cloud import bigquery
except ImportError:
    sys.exit("Install deps first:  pip install google-cloud-bigquery")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sql_file")
    ap.add_argument("--project", default=None)
    ap.add_argument("--set", action="append", default=[], metavar="KEY=VALUE")
    ap.add_argument("--max-gb", type=float, default=20.0,
                    help="refuse to run if the query would scan more than this (default 20)")
    ap.add_argument("--dry-run", action="store_true",
                    help="print the bytes this query would scan, and exit")
    args = ap.parse_args()

    sql = open(args.sql_file).read()
    for pair in args.set:
        if "=" not in pair:
            sys.exit(f"--set needs KEY=VALUE, got: {pair}")
        k, v = pair.split("=", 1)
        sql = sql.replace(f"<{k}>", v)

    missing = sorted(set(re.findall(r"<([A-Z_]+)>", sql)))
    if missing:
        sys.exit("Unsubstituted placeholders: " + ", ".join(missing))

    creds, default_project = google.auth.default()
    client = bigquery.Client(project=args.project or default_project, credentials=creds)

    # Querying the export costs money in proportion to bytes scanned, and a cost review
    # that runs up a BigQuery bill is a bad joke. Estimate first, then cap.
    dry = client.query(sql, job_config=bigquery.QueryJobConfig(dry_run=True,
                                                               use_query_cache=False))
    gb = dry.total_bytes_processed / 1e9
    if args.dry_run:
        print(f"would scan {gb:.3f} GB")
        return
    if gb > args.max_gb:
        sys.exit(f"refusing: this query would scan {gb:.2f} GB (cap {args.max_gb} GB). "
                 f"Narrow the date window, or raise --max-gb deliberately.")

    cfg = bigquery.QueryJobConfig(maximum_bytes_billed=int(args.max_gb * 1e9))
    rows = list(client.query(sql, job_config=cfg).result())
    if not rows:
        print("(0 rows)  <- an empty result is not a zero; check the window and the filters")
        return

    hdr = list(rows[0].keys())
    cells = [[("" if r[h] is None else str(r[h])) for h in hdr] for r in rows]
    w = [max(len(hdr[i]), max(len(c[i]) for c in cells)) for i in range(len(hdr))]
    print("  ".join(h.ljust(w[i]) for i, h in enumerate(hdr)))
    print("  ".join("-" * w[i] for i in range(len(hdr))))
    for c in cells:
        print("  ".join(c[i].ljust(w[i]) for i in range(len(hdr))))


if __name__ == "__main__":
    main()
