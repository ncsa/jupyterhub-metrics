#!/usr/bin/env python3
"""
Import historical JupyterHub container data from InfluxDB to TimescaleDB
"""

import argparse
import os
import sys
import time
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List

import psycopg2
from influxdb_client import InfluxDBClient
from psycopg2.extras import execute_batch

# Configuration
INFLUX_URL = os.getenv("INFLUX_URL", "http://localhost:8086")
INFLUX_TOKEN = os.getenv("INFLUX_TOKEN", "")
INFLUX_ORG = os.getenv("INFLUX_ORG", "")
INFLUX_BUCKET = os.getenv("INFLUX_BUCKET", "telegraf")

PG_HOST = os.getenv("PG_HOST", "localhost")
PG_PORT = os.getenv("PG_PORT", "5432")
PG_DB = os.getenv("PG_DB", "jupyterhub_metrics")
PG_USER = os.getenv("PG_USER", "metrics_user")
PG_PASSWORD = os.getenv("PG_PASSWORD", "changeme_secure_password")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Import JupyterHub container data from InfluxDB to PostgreSQL"
    )
    parser.add_argument(
        "--start",
        type=str,
        required=True,
        help="Start time (RFC3339 format, e.g., 2024-01-01T00:00:00Z or relative like -30d)",
    )
    parser.add_argument(
        "--stop",
        type=str,
        default="now()",
        help="Stop time (RFC3339 format or relative, default: now())",
    )
    parser.add_argument(
        "--measurement",
        type=str,
        default="kubernetes_pod_container",
        help="InfluxDB measurement name (default: kubernetes_pod_container)",
    )
    parser.add_argument(
        "--namespace",
        type=str,
        default="jupyterhub",
        help="Kubernetes namespace (default: jupyterhub)",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=1000,
        help="Number of records to insert per batch (default: 1000)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print sample data without inserting into database",
    )
    parser.add_argument(
        "--sampling-interval",
        type=str,
        default="5m",
        help="Downsample data to this interval (e.g., 5m, 10m, 1h) to reduce rows",
    )
    parser.add_argument(
        "--pod-filter",
        type=str,
        default="jupyter",
        help="Filter pods containing this string (default: jupyter)",
    )
    parser.add_argument(
        "--time-window",
        type=str,
        default="2h",
        help="Time window size for each batch query (default: 2h, prevents overwhelming server)",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=1.0,
        help="Delay in seconds between batch queries (default: 1.0)",
    )
    return parser.parse_args()


def parse_duration_to_seconds(duration_str: str) -> int:
    """Convert duration string like '2h', '30m', '7d' to seconds"""
    unit = duration_str[-1]
    value = int(duration_str[:-1])

    multipliers = {"s": 1, "m": 60, "h": 3600, "d": 86400, "w": 604800, "y": 31536000}

    return value * multipliers.get(unit, 3600)


def parse_time_to_datetime(time_str: str) -> datetime:
    """Convert time argument to datetime object"""
    # Handle Flux format like "-30d" or "now()"
    if time_str == "now()" or time_str == "now":
        return datetime.now(timezone.utc)

    # Handle relative times like "-30d", "-7d", etc
    if time_str.startswith("-"):
        duration = time_str[1:]  # Remove the "-"
        seconds = parse_duration_to_seconds(duration)
        return datetime.now(timezone.utc) - timedelta(seconds=seconds)

    # Handle relative times without "-" like "30d", "7d" (interpret as past)
    if time_str[-1] in ["d", "h", "m", "y", "w"] and time_str[0].isdigit():
        seconds = parse_duration_to_seconds(time_str)
        return datetime.now(timezone.utc) - timedelta(seconds=seconds)

    # Otherwise treat as absolute timestamp (RFC3339)
    try:
        return datetime.fromisoformat(time_str.replace("Z", "+00:00"))
    except:
        raise ValueError(f"Invalid time format: {time_str}")


def generate_time_windows(
    start: datetime, stop: datetime, window_size_seconds: int
) -> List[tuple]:
    """Generate time windows for batched queries"""
    windows = []
    current = start

    while current < stop:
        window_end = min(current + timedelta(seconds=window_size_seconds), stop)
        windows.append((current, window_end))
        current = window_end

    return windows


def get_influx_client():
    """Create InfluxDB client"""
    if not INFLUX_TOKEN:
        print("ERROR: INFLUX_TOKEN environment variable not set")
        sys.exit(1)

    return InfluxDBClient(url=INFLUX_URL, token=INFLUX_TOKEN, org=INFLUX_ORG)


def get_pg_connection():
    """Create PostgreSQL connection"""
    return psycopg2.connect(
        host=PG_HOST, port=PG_PORT, database=PG_DB, user=PG_USER, password=PG_PASSWORD
    )


def build_flux_query(
    start: str,
    stop: str,
    measurement: str,
    namespace: str,
    pod_filter: str,
    interval: str,
) -> str:
    """
    Build Flux query to extract JupyterHub pod data from Telegraf kubernetes input

    We're looking for pods with the right tags (namespace, pod_name, etc.)
    The specific field doesn't matter much - we just need one field per pod to track it exists
    """

    flux_query = f"""
from(bucket: "{INFLUX_BUCKET}")
  |> range(start: {start}, stop: {stop})
  |> filter(fn: (r) => r["_measurement"] == "{measurement}")
  |> filter(fn: (r) => r["namespace"] == "{namespace}")
  |> filter(fn: (r) => r["pod_name"] =~ /{pod_filter}/)
  |> filter(fn: (r) => r["_field"] == "resource_requests_cpu_cores" or r["_field"] == "resource_requests_memory_bytes")
  |> aggregateWindow(every: {interval}, fn: last, createEmpty: false)
  |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
  |> keep(columns: ["_time", "pod_name", "container_name", "node_name", "namespace", "state", "phase", "image", "version"])
"""

    return flux_query


def extract_user_info_from_pod_name(pod_name: str) -> Dict[str, str]:
    """
    Extract user information from JupyterHub pod name
    JupyterHub typically names pods like: jupyter-<username>-<hash>

    This is a heuristic - adjust based on your naming convention
    """
    # Remove 'jupyter-' prefix if present
    if pod_name.startswith("jupyter-"):
        username_part = pod_name[8:]  # Remove 'jupyter-'
        # Split by last dash to separate username from hash
        parts = username_part.rsplit("-", 1)
        username = parts[0] if len(parts) > 0 else "unknown"

        # Create a pseudo-email (you may want to look this up from your user database)
        email = f"{username}@ilinois.edu"

        return {"email": email, "name": username.replace("-", " ").title()}

    return {"email": "unknown@ilinois.edu", "name": "Unknown User"}


def extract_container_info(container_name: str) -> Dict[str, str]:
    """
    Extract container image base and version
    Adjust based on your actual container naming/tagging
    """
    if ":" in container_name:
        base, version = container_name.rsplit(":", 1)
    else:
        base = container_name
        version = "latest"

    # Get just the image name without registry
    if "/" in base:
        base = base.split("/")[-1]

    return {"base": base, "version": version}


def calculate_age_seconds(timestamp: datetime, created_timestamp: float) -> int:
    """
    Calculate container age in seconds

    Since we may not have creation timestamp from this data format,
    we'll estimate age from the first time we saw this pod in the dataset
    """
    # For now, we can't accurately calculate age from this data
    # The age will need to be computed from the MIN(timestamp) per pod
    # This is a limitation of the historical import
    return 0  # Will be updated in transform_records


def query_influxdb(client, query: str) -> List[Dict[str, Any]]:
    """Execute Flux query and return results as list of dicts"""
    query_api = client.query_api()

    print("Querying InfluxDB...")
    print(f"Query: {query[:200]}..." if len(query) > 200 else f"Query: {query}")

    tables = query_api.query(query, org=INFLUX_ORG)

    records = []
    for table in tables:
        for record in table.records:
            # Include all records - we're just tracking that the pod existed
            records.append(
                {
                    "time": record.get_time(),
                    "pod_name": record.values.get("pod_name", "unknown"),
                    "container_name": record.values.get("container_name", "unknown"),
                    "node_name": record.values.get("node_name", "unknown"),
                    "namespace": record.values.get("namespace", "unknown"),
                    "state": record.values.get("state", "unknown"),
                    "phase": record.values.get("phase", "unknown"),
                    "image": record.values.get("image", "unknown"),
                    "version": record.values.get("version", "unknown"),
                }
            )

    print(f"Retrieved {len(records)} records from InfluxDB")
    return records


def transform_records(records: List[Dict[str, Any]]) -> List[tuple]:
    """Transform InfluxDB records to PostgreSQL format"""
    transformed = []

    # First pass: find the earliest timestamp for each pod (to calculate age)
    pod_first_seen = {}
    for record in records:
        pod_name = record["pod_name"]
        timestamp = record["time"]
        if pod_name not in pod_first_seen:
            pod_first_seen[pod_name] = timestamp
        else:
            if timestamp < pod_first_seen[pod_name]:
                pod_first_seen[pod_name] = timestamp

    print(f"Found {len(pod_first_seen)} unique pods")

    # Second pass: transform records
    for record in records:
        timestamp = record["time"]
        pod_name = record["pod_name"]
        container_name = record.get("container_name", "unknown")
        node_name = record["node_name"]
        image = record.get("image", container_name)
        version_from_tag = record.get("version")

        # Only process running pods
        state = record.get("state", "").lower()
        phase = record.get("phase", "").lower()
        if state != "running" and phase != "running":
            continue

        # Extract user info from pod name
        user_info = extract_user_info_from_pod_name(pod_name)

        # Extract container info from image
        container_info = extract_container_info(image)

        final_version = (
            version_from_tag
            if version_from_tag and version_from_tag != "unknown"
            else container_info["version"]
        )

        # Calculate age from first time we saw this pod
        first_seen = pod_first_seen.get(pod_name, timestamp)
        age = timestamp - first_seen
        age_seconds = int(age.total_seconds())

        # Build tuple for PostgreSQL insert
        transformed.append(
            (
                timestamp,  # timestamp
                user_info["email"],  # user_email
                user_info["name"],  # user_name
                node_name,  # node_name
                image,  # container_image
                container_info["base"],  # container_base
                final_version,  # container_version
                age_seconds,  # age_seconds
                pod_name,  # pod_name
            )
        )

    print(f"Transformed {len(transformed)} records for import")
    return transformed


def insert_records(conn, records: List[tuple], batch_size: int):
    """Insert records into PostgreSQL in batches"""
    if not records:
        print("No records to insert")
        return

    insert_sql = """
    INSERT INTO container_observations
    (timestamp, user_email, user_name, node_name, container_image,
     container_base, container_version, age_seconds, pod_name)
    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
    ON CONFLICT (user_email, pod_name, timestamp) DO NOTHING
    """

    cursor = conn.cursor()

    print(f"Inserting {len(records)} records in batches of {batch_size}...")

    try:
        execute_batch(cursor, insert_sql, records, page_size=batch_size)
        conn.commit()
        print(f"Successfully inserted {len(records)} records")
    except Exception as e:
        conn.rollback()
        print(f"ERROR inserting records: {e}")
        raise
    finally:
        cursor.close()


def print_sample_records(records: List[tuple], num_samples: int = 5):
    """Print sample records for dry-run"""
    print("\n=== SAMPLE RECORDS (DRY RUN) ===")
    print(f"Total records: {len(records)}\n")

    for i, record in enumerate(records[:num_samples]):
        print(f"Record {i + 1}:")
        print(f"  Timestamp: {record[0]}")
        print(f"  User Email: {record[1]}")
        print(f"  User Name: {record[2]}")
        print(f"  Node: {record[3]}")
        print(f"  Container Image: {record[4]}")
        print(f"  Container Base: {record[5]}")
        print(f"  Container Version: {record[6]}")
        print(f"  Age (seconds): {record[7]}")
        print(f"  Pod Name: {record[8]}")
        print()


def main():
    args = parse_args()

    print("=== JupyterHub InfluxDB v2 to PostgreSQL Importer ===")
    print(f"InfluxDB: {INFLUX_URL}")
    print(f"Organization: {INFLUX_ORG}")
    print(f"Bucket: {INFLUX_BUCKET}")
    print(f"Measurement: {args.measurement}")
    print(f"Time range: {args.start} to {args.stop}")
    print(f"Namespace: {args.namespace}")
    print(f"Pod filter: {args.pod_filter}")
    print(f"Sampling interval: {args.sampling_interval}")
    print(f"Time window per batch: {args.time_window}")
    print(f"Delay between batches: {args.delay}s")
    print(f"Batch size: {args.batch_size}")
    print(f"Dry run: {args.dry_run}")
    print()

    # Parse time arguments to datetime objects
    try:
        start_dt = parse_time_to_datetime(args.start)
        stop_dt = parse_time_to_datetime(args.stop)
        window_seconds = parse_duration_to_seconds(args.time_window)
    except ValueError as e:
        print(f"ERROR: {e}")
        sys.exit(1)

    # Generate time windows for batched queries
    windows = generate_time_windows(start_dt, stop_dt, window_seconds)
    print(
        f"Will query data in {len(windows)} time window(s) to avoid overwhelming server"
    )
    print(f"Total time range: {start_dt} to {stop_dt}")
    print()

    # Connect to InfluxDB
    influx_client = get_influx_client()

    # Query data in batches (time windows)
    all_records = []

    try:
        for i, (window_start, window_end) in enumerate(windows, 1):
            print(
                f"[{i}/{len(windows)}] Querying window: {window_start} to {window_end}"
            )

            # Convert datetime back to Flux format for this window
            start_flux = window_start.strftime("%Y-%m-%dT%H:%M:%SZ")
            stop_flux = window_end.strftime("%Y-%m-%dT%H:%M:%SZ")

            # Build and execute query for this window
            flux_query = build_flux_query(
                start_flux,
                stop_flux,
                args.measurement,
                args.namespace,
                args.pod_filter,
                args.sampling_interval,
            )

            window_records = query_influxdb(influx_client, flux_query)
            all_records.extend(window_records)

            print(
                f"  Retrieved {len(window_records)} records (total so far: {len(all_records)})"
            )

            # Delay before next batch (except for last batch)
            if i < len(windows):
                print(f"  Waiting {args.delay}s before next batch...")
                time.sleep(args.delay)

    except Exception as e:
        print(f"\nERROR querying InfluxDB: {e}")
        print("\nNote: The default query assumes Telegraf kubernetes input format.")
        print("You may need to adjust the query based on your InfluxDB schema.")
        influx_client.close()
        sys.exit(1)
    finally:
        influx_client.close()

    if not all_records:
        print("No records found in InfluxDB for the specified time range")
        return

    print(f"\n✓ Retrieved total of {len(all_records)} records from InfluxDB")

    # Transform records
    transformed = transform_records(all_records)

    if args.dry_run:
        print_sample_records(transformed)
        print(f"\nDry run complete. Would have inserted {len(transformed)} records.")
        return

    # Insert into PostgreSQL
    pg_conn = get_pg_connection()
    try:
        insert_records(pg_conn, transformed, args.batch_size)
    finally:
        pg_conn.close()

    print("\n=== Import Complete ===")


if __name__ == "__main__":
    main()
