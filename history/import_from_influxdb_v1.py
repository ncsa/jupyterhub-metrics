#!/usr/bin/env python3
"""
Import historical JupyterHub container data from InfluxDB v1.x to TimescaleDB
"""

import os
import sys
import time
import curses
from datetime import datetime, timezone, timedelta
from influxdb import InfluxDBClient
import psycopg2
from psycopg2.extras import execute_batch
import argparse
from typing import List, Dict, Any
from urllib.parse import urlparse

# InfluxDB v1.x Configuration
# Parse INFLUX_URL to extract host, port, and SSL settings
INFLUX_URL = os.getenv("INFLUX_URL", "http://localhost:8086")
parsed = urlparse(INFLUX_URL)

INFLUX_HOST = parsed.hostname or "localhost"
INFLUX_PORT = str(parsed.port) if parsed.port else "8086"
INFLUX_SSL = parsed.scheme == "https"
INFLUX_VERIFY_SSL = os.getenv("INFLUX_VERIFY_SSL", "true").lower() in (
    "true",
    "1",
    "yes",
)

INFLUX_USER = os.getenv("INFLUX_USER", "admin")
INFLUX_PASSWORD = os.getenv("INFLUX_PASSWORD", "")
INFLUX_DATABASE = os.getenv("INFLUX_DATABASE", "telegraf")

# PostgreSQL Configuration
PG_HOST = os.getenv("PG_HOST", "localhost")
PG_PORT = os.getenv("PG_PORT", "5432")
PG_DB = os.getenv("PG_DB", "jupyterhub_metrics")
PG_USER = os.getenv("PG_USER", "metrics_user")
PG_PASSWORD = os.getenv("PG_PASSWORD", "changeme_secure_password")


def is_in_blocked_time_window(minutes_before: int = 1, minutes_after: int = 2) -> bool:
    """
    Check if current time is within the blocked window around the top of the hour.

    Args:
        minutes_before: Minutes before the hour to block (default: 1)
        minutes_after: Minutes after the hour to block (default: 2)

    Returns:
        True if we are in the blocked window, False otherwise
    """
    now = datetime.now(timezone.utc)
    current_minute = now.minute

    # Check if we're in the blocked window
    # e.g., if minutes_before=1 and minutes_after=2:
    # Block from :59 to :02 (minutes 59, 0, 1, 2)
    if current_minute >= (60 - minutes_before) or current_minute <= minutes_after:
        return True

    return False


def draw_waiting_screen(stdscr, minutes_before: int, minutes_after: int):
    """Draw a centered waiting screen for blocked time window"""
    try:
        stdscr.clear()
        height, width = stdscr.getmaxyx()

        now = datetime.now(timezone.utc)
        current_minute = now.minute

        # Calculate time until safe window
        if current_minute <= minutes_after:
            wait_minutes = minutes_after - current_minute + 1
            seconds_until_safe = (wait_minutes * 60) - now.second
        else:  # current_minute >= (60 - minutes_before)
            wait_minutes = (60 - current_minute) + minutes_after + 1
            seconds_until_safe = (wait_minutes * 60) - now.second

        # Format countdown
        minutes_left = seconds_until_safe // 60
        seconds_left = seconds_until_safe % 60

        # Prepare text lines
        lines = [
            "",
            "═" * min(70, width - 4),
            "  ⚠️  BLOCKED TIME WINDOW",
            "═" * min(70, width - 4),
            "",
            f"  Import is paused to avoid conflicts with scheduled tasks",
            f"  Blocked window: :{60 - minutes_before:02d} to :{minutes_after:02d}",
            "",
            f"  Current time:   {now.strftime('%H:%M:%S UTC')}",
            f"  Current minute: :{current_minute:02d}",
            "",
            f"  Time until safe window: {minutes_left}m {seconds_left}s",
            "",
            "  Checking every 5 seconds...",
            "",
            "═" * min(70, width - 4),
        ]

        # Center and draw each line
        start_y = max(2, (height - len(lines)) // 2)
        for idx, line in enumerate(lines):
            y = start_y + idx
            if y < height - 1:
                x = max(0, (width - len(line)) // 2)
                try:
                    stdscr.addstr(y, x, line[: width - 1])
                except:
                    pass

        stdscr.refresh()
    except:
        # If curses fails, silently continue
        pass


def parse_args():
    parser = argparse.ArgumentParser(
        description="Import JupyterHub container data from InfluxDB v1.x to PostgreSQL"
    )
    parser.add_argument(
        "--start",
        type=str,
        required=True,
        help='Start time (e.g., "2024-01-01 00:00:00", "7d" for 7 days ago, "30d", "1y")',
    )
    parser.add_argument(
        "--stop", type=str, default="now", help="Stop time (default: now)"
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
        "--cluster",
        type=str,
        default="cori-prod",
        help="Cluster name to filter by (default: cori-prod)",
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
        "--group-by-time",
        type=str,
        default="5m",
        dest="sampling_interval",
        help="Group data by time interval to reduce rows (e.g., 5m, 10m, 1h)",
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
    parser.add_argument(
        "--skip-time-check",
        action="store_true",
        help="Skip the blocked time window check (use with caution)",
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
    if time_str == "now":
        return datetime.now(timezone.utc)

    # Check if it's a relative time (e.g., "7d", "30d", "1y")
    if time_str[-1] in ["d", "h", "m", "y", "w"]:
        seconds = parse_duration_to_seconds(time_str)
        return datetime.now(timezone.utc) - timedelta(seconds=seconds)

    # Otherwise treat as absolute timestamp
    try:
        return datetime.fromisoformat(time_str.replace("Z", "+00:00"))
    except:
        # Try parsing as simple date
        try:
            dt = datetime.strptime(time_str, "%Y-%m-%d")
            return dt.replace(tzinfo=timezone.utc)
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
    """Create InfluxDB v1.x client"""
    return InfluxDBClient(
        host=INFLUX_HOST,
        port=int(INFLUX_PORT),
        username=INFLUX_USER,
        password=INFLUX_PASSWORD,
        database=INFLUX_DATABASE,
        ssl=INFLUX_SSL,
        verify_ssl=INFLUX_VERIFY_SSL,
    )


def get_pg_connection():
    """Create PostgreSQL connection"""
    return psycopg2.connect(
        host=PG_HOST, port=PG_PORT, database=PG_DB, user=PG_USER, password=PG_PASSWORD
    )


def build_influxql_query(
    measurement: str,
    start: str,
    stop: str,
    namespace: str,
    pod_filter: str,
    group_by_time: str,
    cluster: str = None,
) -> str:
    """
    Build InfluxQL query to extract JupyterHub pod data
    """

    # Build the WHERE clause
    where_clauses = [
        f"time >= {start}",
        f"time < {stop}",
        f"\"namespace\" = '{namespace}'",
    ]

    if cluster:
        where_clauses.append(f"\"cluster\" = '{cluster}'")

    if pod_filter:
        where_clauses.append(f'"pod_name" =~ /{pod_filter}/')

    where_clause = " AND ".join(where_clauses)

    # Query to get pod data with time-based aggregation
    # Only select the fields we actually need to reduce data volume
    # Note: Fields in GROUP BY (pod_name, node_name, etc.) are available as tags
    query = f'''
    SELECT
        MAX("ready") AS "ready",
        MAX("status_condition") AS "status_condition"
    FROM "{measurement}"
    WHERE {where_clause}
    GROUP BY TIME({group_by_time}), "pod_name", "node_name", "container_name", "namespace", "image", "version"
    '''

    return query


def extract_user_info_from_pod_name(pod_name: str) -> Dict[str, str]:
    """
    Extract user information from JupyterHub pod name
    JupyterHub typically names pods like: jupyter-<username>-<hash>
    """
    if not pod_name:
        return {"email": "unknown@illinois.edu", "name": "Unknown User"}

    if pod_name.startswith("jupyter-"):
        username_part = pod_name[8:]
        parts = username_part.rsplit("-", 1)
        username = parts[0] if len(parts) > 0 else "unknown"

        # Create email (adjust this to match your user database)
        email = f"{username}@illinois.edu"

        return {"email": email, "name": username.replace("-", " ").title()}

    return {"email": "unknown@illinois.edu", "name": "Unknown User"}


def extract_container_info(container_name: str) -> Dict[str, str]:
    """Extract container image base and version"""
    if ":" in container_name:
        base, version = container_name.rsplit(":", 1)
    else:
        base = container_name
        version = "latest"

    if "/" in base:
        base = base.split("/")[-1]

    return {"base": base, "version": version}


def query_influxdb(client, query: str) -> List[Dict[str, Any]]:
    """Execute InfluxQL query and return results as list of dicts"""
    try:
        result = client.query(query)

        records = []
        # Access raw result to get tags from GROUP BY
        if hasattr(result, "raw") and result.raw and "series" in result.raw:
            # Iterate through each series (each has different tag combinations)
            for series in result.raw["series"]:
                # Each series has a tags dict from GROUP BY
                tags = series.get("tags", {})
                columns = series.get("columns", [])

                # Get points for this series (values, not points)
                for point in series.get("values", []):
                    # Reconstruct the record with both fields and tags
                    record = {}
                    for i, col in enumerate(columns):
                        record[col] = point[i]

                    # Merge in the tags (pod_name, node_name, container_name, namespace)
                    record.update(tags)

                    # Include containers that appear to be running
                    # Check multiple possible status fields - handle None values safely
                    is_running = (
                        (record.get("status_running") or 0) > 0  # Traditional field
                        or record.get("status") is True  # Boolean status field
                        or (record.get("status_condition") or 0)
                        > 0  # Status condition field
                        or (record.get("ready") or 0) > 0  # Ready field
                        or record.get("state") == "running"  # State field
                    )

                    if is_running:
                        records.append(record)

        return records

    except Exception as e:
        print(f"ERROR querying InfluxDB: {e}")
        raise


def estimate_pod_age(timestamp: str, pod_name: str, all_records: List[Dict]) -> int:
    """
    Estimate pod age by finding first occurrence in dataset
    This is a fallback when creation timestamp is not available
    """
    # Convert timestamp to datetime
    current_time = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))

    # Find earliest time for this pod
    pod_records = [r for r in all_records if r.get("pod_name") == pod_name]

    if pod_records:
        earliest_time = min(
            datetime.fromisoformat(r["time"].replace("Z", "+00:00"))
            for r in pod_records
        )
        age = current_time - earliest_time
        return int(age.total_seconds())

    return 0


def transform_records(records: List[Dict[str, Any]]) -> List[tuple]:
    """Transform InfluxDB records to PostgreSQL format"""
    transformed = []
    skipped_no_pod_name = 0
    skipped_not_jupyter = 0
    seen_keys = set()  # Track unique (pod, timestamp) to avoid duplicates within batch

    for record in records:
        timestamp_str = record.get("time")
        if not timestamp_str:
            continue

        # Parse timestamp
        timestamp = datetime.fromisoformat(timestamp_str.replace("Z", "+00:00"))

        pod_name = record.get("pod_name") or "unknown"
        container_name = record.get("container_name") or "unknown"
        node_name = record.get("node_name") or "unknown"
        image = record.get("image") or "unknown"
        version_from_tag = record.get("version")

        # Skip records without essential pod information
        if pod_name == "unknown":
            skipped_no_pod_name += 1
            continue

        # Skip non-jupyter pods (hub, proxy, etc.)
        if not pod_name.startswith("jupyter-"):
            skipped_not_jupyter += 1
            continue

        # Skip duplicate records within this batch
        record_key = (pod_name, timestamp_str)
        if record_key in seen_keys:
            continue
        seen_keys.add(record_key)

        # Extract user info
        user_info = extract_user_info_from_pod_name(pod_name)

        # Extract container info
        container_info = extract_container_info(image)

        # Prioritize version from tag if available
        final_version = version_from_tag or container_info["version"]

        # Estimate age (since we may not have creation time from Telegraf)
        # This will be 0 for now, but you can enhance this by tracking first seen time
        age_seconds = estimate_pod_age(timestamp_str, pod_name, records)

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

    # Return both transformed records and statistics
    stats = {
        "transformed": len(transformed),
        "skipped_no_pod_name": skipped_no_pod_name,
        "skipped_not_jupyter": skipped_not_jupyter,
        "duplicates_in_batch": len(records)
        - len(transformed)
        - skipped_no_pod_name
        - skipped_not_jupyter,
    }
    return transformed, stats


def extract_users_from_batch(transformed: List[tuple]) -> Dict[str, Dict]:
    """
    Extract unique users from transformed observation records.
    Returns dict: {email: {user_id, first_seen, last_seen}}
    """
    users = {}

    for record in transformed:
        timestamp = record[0]  # timestamp
        user_email = record[1]  # user_email
        pod_name = record[8]  # pod_name

        # Extract user_id from pod_name
        if pod_name.startswith("jupyter-"):
            user_id = pod_name[8:].rsplit("-", 1)[0]  # Remove hash suffix
        else:
            user_id = "unknown"

        if user_email not in users:
            users[user_email] = {
                "user_id": user_id,
                "first_seen": timestamp,
                "last_seen": timestamp,
            }
        else:
            # Update timestamps
            users[user_email]["first_seen"] = min(
                users[user_email]["first_seen"], timestamp
            )
            users[user_email]["last_seen"] = max(
                users[user_email]["last_seen"], timestamp
            )

    return users


def upsert_users(conn, users: Dict[str, Dict], silent: bool = False):
    """
    Upsert users, only updating timestamps for existing users.
    Preserves existing user_id and full_name from collector.
    """
    if not users:
        return 0

    cursor = conn.cursor()

    # Get count before
    cursor.execute("SELECT COUNT(*) FROM users")
    users_before = cursor.fetchone()[0]

    # Prepare data as list of tuples
    user_data = [
        (email, data["user_id"], email, data["first_seen"], data["last_seen"])
        for email, data in users.items()
    ]

    upsert_sql = """
    INSERT INTO users (email, user_id, full_name, first_seen, last_seen)
    VALUES (%s, %s, split_part(%s, '@', 1), %s, %s)
    ON CONFLICT (email) DO UPDATE SET
        first_seen = LEAST(users.first_seen, EXCLUDED.first_seen),
        last_seen = GREATEST(users.last_seen, EXCLUDED.last_seen)
    """

    try:
        execute_batch(cursor, upsert_sql, user_data, page_size=1000)
        conn.commit()

        # Get count after
        cursor.execute("SELECT COUNT(*) FROM users")
        users_after = cursor.fetchone()[0]

        users_inserted = users_after - users_before

        if not silent:
            print(f"✓ Upserted {len(users)} unique users ({users_inserted} new)")

        return users_inserted
    except Exception as e:
        conn.rollback()
        if not silent:
            print(f"ERROR upserting users: {e}")
        raise
    finally:
        cursor.close()


def insert_records(conn, records: List[tuple], batch_size: int, silent: bool = False):
    """Insert records into PostgreSQL in batches"""
    if not records:
        return 0

    insert_sql = """
    INSERT INTO container_observations
    (timestamp, user_email, user_name, node_name, container_image,
     container_base, container_version, age_seconds, pod_name)
    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
    ON CONFLICT (user_email, pod_name, timestamp) DO NOTHING
    """

    cursor = conn.cursor()

    if not silent:
        print(f"Inserting {len(records)} records in batches of {batch_size}...")

    # Get row count before insert
    cursor.execute("SELECT COUNT(*) FROM container_observations")
    rows_before = cursor.fetchone()[0]

    try:
        execute_batch(cursor, insert_sql, records, page_size=batch_size)
        conn.commit()

        # Get count after insert
        cursor.execute("SELECT COUNT(*) FROM container_observations")
        rows_after = cursor.fetchone()[0]

        rows_inserted = rows_after - rows_before
        rows_skipped = len(records) - rows_inserted

        if not silent:
            print(f"✓ Insert complete.")
            print(f"  Rows inserted: {rows_inserted:,}")
            print(f"  Rows skipped (duplicates): {rows_skipped:,}")
            print(f"  Total rows in database: {rows_after:,}")

        return rows_inserted

    except Exception as e:
        conn.rollback()
        if not silent:
            print(f"ERROR inserting records: {e}")
        raise
    finally:
        cursor.close()


def refresh_materialized_views(conn):
    """
    Refresh the user_sessions materialized view after data import.
    Uses CONCURRENTLY to allow concurrent reads during refresh.
    """
    print("\n=== Refreshing Materialized Views ===")

    cursor = conn.cursor()

    try:
        print("Refreshing user_sessions view (this may take a few minutes)...")
        start_time = time.time()

        # Use CONCURRENTLY to avoid blocking reads
        cursor.execute("REFRESH MATERIALIZED VIEW CONCURRENTLY user_sessions")
        conn.commit()

        elapsed = time.time() - start_time

        # Get row count
        cursor.execute("SELECT COUNT(*) FROM user_sessions")
        session_count = cursor.fetchone()[0]

        print(f"✓ user_sessions view refreshed in {elapsed:.1f}s")
        print(f"  Total sessions: {session_count:,}")

    except Exception as e:
        conn.rollback()
        print(f"ERROR refreshing materialized views: {e}")
        raise
    finally:
        cursor.close()


def refresh_continuous_aggregates(conn, start_time: datetime, end_time: datetime):
    """
    Manually refresh continuous aggregates for the imported time range.
    This ensures hourly stats are immediately available without waiting for the schedule.
    """
    print("\n=== Refreshing Continuous Aggregates ===")

    # Save original autocommit state
    old_autocommit = conn.autocommit

    try:
        # Commit any pending transaction before changing autocommit mode
        # This prevents "set_session cannot be used inside a transaction" error
        if not old_autocommit:
            conn.commit()

        # Enable autocommit - refresh_continuous_aggregate() cannot run inside a transaction block
        conn.autocommit = True

        cursor = conn.cursor()

        try:
            # Refresh hourly_node_stats
            print("Refreshing hourly_node_stats...")
            cursor.execute(
                "CALL refresh_continuous_aggregate('hourly_node_stats', %s, %s)",
                (start_time, end_time),
            )
            print("✓ hourly_node_stats refreshed")

            # Refresh hourly_image_stats
            print("Refreshing hourly_image_stats...")
            cursor.execute(
                "CALL refresh_continuous_aggregate('hourly_image_stats', %s, %s)",
                (start_time, end_time),
            )
            print("✓ hourly_image_stats refreshed")

        finally:
            cursor.close()

    except Exception as e:
        print(f"WARNING: Could not refresh continuous aggregates: {e}")
        print("  Note: Continuous aggregates will be updated automatically on schedule")
        # Don't raise - this is not critical
    finally:
        # Restore original autocommit state
        conn.autocommit = old_autocommit


def draw_progress(
    stdscr,
    i,
    total_windows,
    records_count,
    inserted_count,
    users_count,
    window_start,
    window_end,
    start_time,
):
    """Draw a centered progress display using curses"""
    try:
        stdscr.clear()
        height, width = stdscr.getmaxyx()

        # Check if we're in a blocked time window
        now = datetime.now(timezone.utc)
        in_blocked_window = is_in_blocked_time_window()
        current_minute = now.minute

        # Calculate progress
        progress_pct = (i / total_windows) * 100
        elapsed = time.time() - start_time
        avg_time_per_window = elapsed / i if i > 0 else 0
        remaining_windows = total_windows - i

        # Calculate ETA or blocked window time
        if in_blocked_window:
            # Calculate time until safe window
            if current_minute <= 2:  # minutes_after
                wait_minutes = 2 - current_minute + 1
                seconds_until_safe = (wait_minutes * 60) - now.second
            else:  # current_minute >= 59 (60 - minutes_before)
                wait_minutes = (60 - current_minute) + 2 + 1
                seconds_until_safe = (wait_minutes * 60) - now.second

            minutes_left = seconds_until_safe // 60
            seconds_left = seconds_until_safe % 60
            eta_str = f"Paused - blocked until :{(current_minute + wait_minutes) % 60:02d} ({minutes_left}m {seconds_left}s)"
            status_icon = "⏸"
            status_text = "PAUSED - Blocked Time Window"
        else:
            eta_seconds = avg_time_per_window * remaining_windows
            # Format ETA
            if eta_seconds < 60:
                eta_str = f"{int(eta_seconds)}s"
            elif eta_seconds < 3600:
                eta_str = f"{int(eta_seconds / 60)}m {int(eta_seconds % 60)}s"
            else:
                hours = int(eta_seconds / 3600)
                minutes = int((eta_seconds % 3600) / 60)
                eta_str = f"{hours}h {minutes}m"
            status_icon = "▶"
            status_text = "Importing"

        # Create progress bar
        bar_width = min(60, width - 10)
        filled = int(bar_width * i / total_windows)
        bar = "█" * filled + "░" * (bar_width - filled)

        # Prepare text lines
        lines = [
            "",
            "═" * min(70, width - 4),
            f"  {status_icon} JupyterHub Metrics Import - {status_text}",
            "═" * min(70, width - 4),
            "",
            f"  Progress: {progress_pct:5.1f}%",
            f"  [{bar}]",
            "",
            f"  Window:     {i:,} / {total_windows:,}",
            f"  Retrieved:  {records_count:,} records",
            f"  Inserted:   {inserted_count:,} containers, {users_count:,} users",
            "",
        ]

        # Add current window or blocked message
        if in_blocked_window:
            lines.extend(
                [
                    f"  Status:     ⚠️  Waiting for safe window (:59-:02 blocked)",
                    f"  Current:    {now.strftime('%Y-%m-%d %H:%M:%S UTC')} (minute :{current_minute:02d})",
                    f"  ETA:        {eta_str}",
                ]
            )
        else:
            lines.extend(
                [
                    f"  Current:    {window_start.strftime('%Y-%m-%d %H:%M')} - {window_end.strftime('%H:%M')}",
                    f"  ETA:        {eta_str}",
                ]
            )

        lines.extend(
            [
                "",
                "═" * min(70, width - 4),
            ]
        )

        # Center and draw each line
        start_y = max(2, (height - len(lines)) // 2)
        for idx, line in enumerate(lines):
            y = start_y + idx
            if y < height - 1:
                x = max(0, (width - len(line)) // 2)
                try:
                    stdscr.addstr(y, x, line[: width - 1])
                except:
                    pass

        stdscr.refresh()
    except:
        # If curses fails, silently continue
        pass


def print_sample_records(records: List[tuple], num_samples: int = 5):
    """Print sample records for dry-run"""
    print("\n=== SAMPLE RECORDS (DRY RUN) ===")
    print(f"Total records to import: {len(records)}\n")

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

    print("=== JupyterHub InfluxDB v1.x to PostgreSQL Importer ===")

    # Check if we're in a blocked time window (unless explicitly skipped)
    if not args.skip_time_check:
        now = datetime.now(timezone.utc)
        if is_in_blocked_time_window():
            print(f"⚠️  Currently in blocked time window (minute :{now.minute:02d})")
            print("   Import will pause during blocked windows (:59-:02)")
            print("   to avoid conflicts with scheduled tasks.\n")
        else:
            print(
                f"✓ Time window check passed (current time: {now.strftime('%H:%M UTC')})"
            )
            print("  Import will auto-pause during blocked windows (:59-:02).\n")
    else:
        print("⚠️  Skipping time window check (--skip-time-check flag enabled)\n")

    print(f"InfluxDB: {INFLUX_HOST}:{INFLUX_PORT} / {INFLUX_DATABASE}")
    print(f"SSL: {INFLUX_SSL}, Verify SSL: {INFLUX_VERIFY_SSL}")
    print(f"Measurement: {args.measurement}")
    print(f"Time range: {args.start} to {args.stop}")
    print(f"Namespace: {args.namespace}")
    print(f"Cluster: {args.cluster}")
    print(f"Sampling interval: {args.sampling_interval}")
    print(f"Time window per batch: {args.time_window}")
    print(f"Delay between batches: {args.delay}s")
    print(f"Pod filter: {args.pod_filter}")
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

    try:
        # Test connection
        version = influx_client.ping()
        print(f"✓ Connected to InfluxDB v1.x (version: {version})\n")
    except Exception as e:
        print(f"ERROR connecting to InfluxDB: {e}")
        sys.exit(1)

    # Query data in batches (time windows)
    all_records = []
    start_time = time.time()
    total_containers_inserted = 0
    total_users_inserted = 0
    total_stats = {
        "skipped_no_pod_name": 0,
        "skipped_not_jupyter": 0,
        "duplicates_in_batch": 0,
    }

    # Connect to PostgreSQL for incremental inserts
    if not args.dry_run:
        pg_conn = get_pg_connection()

    # Wrapper function for the import loop that uses curses
    def run_import_loop(stdscr=None):
        nonlocal total_containers_inserted, total_users_inserted, total_stats

        # Initialize curses if available
        if stdscr:
            curses.curs_set(0)  # Hide cursor
            stdscr.nodelay(True)  # Non-blocking input

        try:
            for i, (window_start, window_end) in enumerate(windows, 1):
                # Check if we're in blocked time window and wait if needed
                if not args.skip_time_check:
                    while is_in_blocked_time_window():
                        # Update display to show we're waiting
                        if stdscr:
                            draw_progress(
                                stdscr,
                                i,
                                len(windows),
                                len(all_records),
                                total_containers_inserted,
                                total_users_inserted,
                                window_start,
                                window_end,
                                start_time,
                            )
                        # Wait 5 seconds before checking again
                        time.sleep(5)

                # Convert datetime back to InfluxQL format for this window
                start_influx = f"'{window_start.strftime('%Y-%m-%dT%H:%M:%SZ')}'"
                stop_influx = f"'{window_end.strftime('%Y-%m-%dT%H:%M:%SZ')}'"

                # Build and execute query for this window
                query = build_influxql_query(
                    args.measurement,
                    start_influx,
                    stop_influx,
                    args.namespace,
                    args.pod_filter,
                    args.sampling_interval,
                    args.cluster,
                )

                window_records = query_influxdb(influx_client, query)
                all_records.extend(window_records)

                # Transform and insert records from this window immediately
                if window_records and not args.dry_run:
                    transformed, stats = transform_records(window_records)
                    # Track statistics
                    total_stats["skipped_no_pod_name"] += stats["skipped_no_pod_name"]
                    total_stats["skipped_not_jupyter"] += stats["skipped_not_jupyter"]
                    total_stats["duplicates_in_batch"] += stats["duplicates_in_batch"]

                    if transformed:
                        # Insert container observations
                        containers_inserted = insert_records(
                            pg_conn, transformed, args.batch_size, silent=True
                        )
                        total_containers_inserted += containers_inserted

                        # Extract and upsert users from this batch
                        users = extract_users_from_batch(transformed)
                        users_inserted = upsert_users(pg_conn, users, silent=True)
                        total_users_inserted += users_inserted

                # Update progress display
                if stdscr:
                    draw_progress(
                        stdscr,
                        i,
                        len(windows),
                        len(all_records),
                        total_containers_inserted,
                        total_users_inserted,
                        window_start,
                        window_end,
                        start_time,
                    )

                # Delay before next batch (except for last batch)
                if i < len(windows):
                    time.sleep(args.delay)
        except KeyboardInterrupt:
            if stdscr:
                stdscr.clear()
                stdscr.refresh()
            raise

    # Run the import loop with curses
    try:
        curses.wrapper(run_import_loop)
    except KeyboardInterrupt:
        print("\n\nImport interrupted by user")
        if not args.dry_run:
            pg_conn.close()
        influx_client.close()
        sys.exit(1)
    except Exception as e:
        # If curses fails, fall back to simple progress
        print("Curses not available, using simple progress display...")
        run_import_loop(None)

    except Exception as e:
        print(f"\nERROR querying InfluxDB: {e}")
        print(f"\nNote: Make sure the measurement name is correct.")
        print(f"Run: python inspect_influxdb_v1_schema.py --namespace {args.namespace}")
        if not args.dry_run:
            pg_conn.close()
        influx_client.close()
        sys.exit(1)
    finally:
        influx_client.close()
        # Note: Don't close pg_conn here - we need it for post-import processing

    if not all_records:
        print("\nNo records found in InfluxDB for the specified criteria")
        print("\nTroubleshooting:")
        print("1. Check the measurement name with inspect_influxdb_v1_schema.py")
        print("2. Verify the namespace is correct")
        print("3. Try a longer time range")
        print(f"4. Check pod filter: --pod-filter='{args.pod_filter}'")
        if not args.dry_run:
            pg_conn.close()
        return

    print(f"\n\n✓ Retrieved total of {len(all_records):,} records from InfluxDB")

    if args.dry_run:
        # For dry run, transform all records at the end to show samples
        transformed, stats = transform_records(all_records)
        print_sample_records(transformed)
        print(f"\nDry run complete. Would have inserted {len(transformed):,} records.")
        print(f"\nFiltering summary:")
        print(f"  Records without pod_name: {stats['skipped_no_pod_name']:,}")
        print(
            f"  Non-jupyter pods (hub, proxy, etc.): {stats['skipped_not_jupyter']:,}"
        )
        print(f"  Duplicate records in batch: {stats['duplicates_in_batch']:,}")
        print("\nTo actually import, run without --dry-run flag")
        return

    print("\n=== Import Complete ===")
    print(f"\nFiltering breakdown:")
    print(f"  Records from InfluxDB:        {len(all_records):,}")
    print(f"  - Without pod_name:           {total_stats['skipped_no_pod_name']:,}")
    print(f"  - Non-jupyter pods:           {total_stats['skipped_not_jupyter']:,}")
    print(f"  - Duplicates within batch:    {total_stats['duplicates_in_batch']:,}")

    transformed_count = (
        len(all_records)
        - total_stats["skipped_no_pod_name"]
        - total_stats["skipped_not_jupyter"]
        - total_stats["duplicates_in_batch"]
    )
    print(f"  = Ready to insert:            {transformed_count:,}")

    if transformed_count > total_containers_inserted:
        db_duplicates = transformed_count - total_containers_inserted
        print(f"  - Already in database:        {db_duplicates:,}")

    print(f"  = Containers inserted:        {total_containers_inserted:,}")
    print(f"  = Users inserted:             {total_users_inserted:,}")

    # Post-import processing: refresh views
    if total_containers_inserted > 0:
        try:
            # Refresh materialized views
            refresh_materialized_views(pg_conn)

            # Refresh continuous aggregates for imported time range
            refresh_continuous_aggregates(pg_conn, start_dt, stop_dt)

        except Exception as e:
            print(f"\n⚠️  WARNING: Post-import processing had errors: {e}")
            print(
                "   Data was imported successfully, but views may need manual refresh"
            )

    print("\n=== All Processing Complete ===")
    print("\nVerify in PostgreSQL:")
    print(f'  docker exec jupyterhub-timescaledb psql -U {PG_USER} -d {PG_DB} -c "')
    print(f"    SELECT COUNT(*) as total_rows, ")
    print(f"           COUNT(DISTINCT user_email) as unique_users,")
    print(f"           MIN(timestamp) as earliest,")
    print(f"           MAX(timestamp) as latest")
    print(f'    FROM container_observations;"')
    print()
    print(f'  docker exec jupyterhub-timescaledb psql -U {PG_USER} -d {PG_DB} -c "')
    print(f"    SELECT COUNT(*) as total_users,")
    print(f"           MIN(first_seen) as earliest_user,")
    print(f"           MAX(last_seen) as latest_activity")
    print(f'    FROM users;"')
    print()
    print(f'  docker exec jupyterhub-timescaledb psql -U {PG_USER} -d {PG_DB} -c "')
    print(f"    SELECT COUNT(*) as total_sessions,")
    print(f"           SUM(runtime_hours) as total_runtime_hours")
    print(f'    FROM user_sessions;"')

    # Close PostgreSQL connection
    if not args.dry_run:
        pg_conn.close()


if __name__ == "__main__":
    main()
