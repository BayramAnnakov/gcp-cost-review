#!/usr/bin/env python3
"""Locate the BigQuery billing export and describe its shape.

Usage:
    python discover.py [PROJECT_ID ...] [--span] [--max-gb N]

Read-only. Prints table metadata only - never cost values.

By default this reads table METADATA, which is free. `--span` additionally runs a
query per table to show the date range; that query scans a column and therefore
costs money on a large export, so it is opt-in and capped.
"""
import argparse
import sys

try:
    import google.auth
    from google.cloud import bigquery
except ImportError:
    sys.exit("Install deps first:  pip install google-cloud-bigquery")

EXPORT_PREFIXES = (
    "gcp_billing_export_v1_",            # standard
    "gcp_billing_export_resource_v1_",   # detailed (per-resource)
)


def candidate_projects(explicit):
    """Explicit args win. Otherwise try BOTH the ADC quota project and the default -
    they are frequently different, and the export lives in neither by default."""
    if explicit:
        return explicit
    creds, default_project = google.auth.default()
    out = []
    for p in (getattr(creds, "quota_project_id", None), default_project):
        if p and p not in out:
            out.append(p)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("projects", nargs="*")
    ap.add_argument("--span", action="store_true",
                    help="also query each table's date range (costs money; capped)")
    ap.add_argument("--max-gb", type=float, default=5.0,
                    help="cap for --span queries, in GB scanned (default 5)")
    args = ap.parse_args()

    creds, _ = google.auth.default()
    projects = candidate_projects(args.projects)
    if not projects:
        sys.exit("No project. Pass one explicitly:  python discover.py my-project-id")

    print(f"Searching: {', '.join(projects)}")
    found, denied = [], []

    for project in projects:
        try:
            client = bigquery.Client(project=project, credentials=creds)
            datasets = list(client.list_datasets())
        except Exception as e:
            denied.append((project, "<list datasets>", type(e).__name__))
            continue

        for ds in datasets:
            # A dataset you cannot read must not abort the whole search.
            try:
                tables = list(client.list_tables(ds.reference))
            except Exception as e:
                denied.append((project, ds.dataset_id, type(e).__name__))
                continue

            for tbl in tables:
                if not tbl.table_id.startswith(EXPORT_PREFIXES):
                    continue
                ref = f"{project}.{ds.dataset_id}.{tbl.table_id}"
                kind = ("DETAILED (per-resource)"
                        if tbl.table_id.startswith("gcp_billing_export_resource_v1_")
                        else "STANDARD")
                meta = client.get_table(ref)
                line = (f"  {kind}\n    table : {ref}\n"
                        f"    rows  : {meta.num_rows:,}   size: {meta.num_bytes/1e9:.2f} GB")
                if args.span:
                    try:
                        cfg = bigquery.QueryJobConfig(
                            maximum_bytes_billed=int(args.max_gb * 1e9))
                        q = (f"SELECT MIN(DATE(usage_start_time)) a, "
                             f"MAX(DATE(usage_start_time)) b FROM `{ref}`")
                        r = list(client.query(q, job_config=cfg).result())[0]
                        line += f"\n    span  : {r['a']} .. {r['b']}"
                    except Exception as e:
                        line += f"\n    span  : not read ({type(e).__name__})"
                print(line)
                found.append(ref)

    if denied:
        print("\nCould not inspect (permissions or API disabled) - the export may be here:")
        for p, d, e in denied:
            print(f"  {p}.{d}: {e}")

    if not found:
        print(f"""
No billing export table found in: {', '.join(projects)}

That is NOT the same as "the export is off". Check, in order:
  1. Wrong project. The export usually lives in a dedicated billing/admin project,
     which is often not your ADC default. Pass it explicitly:
         python discover.py my-billing-project
  2. Permissions. You need bigquery.datasets.get / tables.list on it. Anything in the
     "could not inspect" list above is a candidate.
  3. Genuinely not enabled. Someone with billing admin turns it on at
     Billing -> Billing export -> BigQuery export.

If it has to be enabled now: a first STANDARD export to a US or EU multi-region dataset
can backfill from the start of the previous month, but that is the only backfill you get
- older history will not appear. Meanwhile the Cloud Console billing reports DO break
down by service, SKU, project and label, so they are a real fallback for attribution;
what you lose is SQL, custom windows, and the credit detail.
""")
    else:
        print("""
Next: establish the measurement contract (references/measurement-contract.md).
  1. reproduce a console figure (note the console reports in US Pacific time)
  2. pick a flat-rate control SKU and record its exact daily GROSS value
  3. inventory the credits and classify each as pot / proportional / tiered,
     and check each one's expiry - an expiring promotion is not a discount
""")


if __name__ == "__main__":
    main()
