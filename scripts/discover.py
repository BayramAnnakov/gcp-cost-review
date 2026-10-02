#!/usr/bin/env python3
"""Locate the BigQuery billing export and describe its shape.

Usage:
    python discover.py [PROJECT_ID ...]

With no arguments it tries the Application Default Credentials' quota project.
Read-only. Prints no cost values, only table metadata.
"""
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


def describe(client, table_ref):
    """Return (rows, first_day, last_day) without scanning cost columns."""
    q = f"""
        SELECT COUNT(*) AS rows_,
               MIN(DATE(usage_start_time)) AS first_day,
               MAX(DATE(usage_start_time)) AS last_day
        FROM `{table_ref}`
    """
    r = list(client.query(q).result())[0]
    return r["rows_"], r["first_day"], r["last_day"]


def main():
    creds, default_project = google.auth.default()
    projects = sys.argv[1:] or ([default_project] if default_project else [])
    if not projects:
        sys.exit("No project. Pass one explicitly:  python discover.py my-project-id")

    found = False
    for project in projects:
        client = bigquery.Client(project=project, credentials=creds)
        print(f"\n=== project: {project} ===")
        try:
            datasets = list(client.list_datasets())
        except Exception as e:
            print(f"  cannot list datasets: {type(e).__name__}")
            continue
        if not datasets:
            print("  (no datasets)")
        for ds in datasets:
            for tbl in client.list_tables(ds.reference):
                if not tbl.table_id.startswith(EXPORT_PREFIXES):
                    continue
                found = True
                ref = f"{project}.{ds.dataset_id}.{tbl.table_id}"
                kind = ("DETAILED (per-resource)"
                        if tbl.table_id.startswith("gcp_billing_export_resource_v1_")
                        else "STANDARD")
                try:
                    rows, first, last = describe(client, ref)
                    print(f"  {kind}\n    table : {ref}\n    span  : {first} .. {last}  ({rows:,} rows)")
                except Exception as e:
                    print(f"  {kind}\n    table : {ref}\n    (could not read span: {type(e).__name__})")

    if not found:
        print("""
No billing export table found.

The export is not on by default. Someone with billing admin must enable it:
  Billing -> Billing export -> BigQuery export -> Standard usage cost

Two things to be clear about with the user before promising an answer:
  * it only collects from the moment it is enabled - historical months are NOT
    backfilled, so "why did last quarter change" may be unanswerable
  * without it you can read totals in the console, but not attribute them to a
    SKU, project, label or day
""")
    else:
        print("""
Next: establish the measurement contract (references/measurement-contract.md).
  1. confirm the billing account timezone and reproduce a console figure
  2. pick a flat-rate control SKU and record its exact daily value
  3. inventory the credits and classify each as pot / proportional / tiered
""")


if __name__ == "__main__":
    main()
