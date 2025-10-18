#!/usr/bin/env python3
"""
Inspect InfluxDB v1.x schema to understand the Telegraf kubernetes data structure
"""

import os
import sys
from influxdb import InfluxDBClient
import argparse
from datetime import datetime, timedelta
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


def parse_args():
    parser = argparse.ArgumentParser(
        description="Inspect InfluxDB v1.x schema for JupyterHub data"
    )
    parser.add_argument(
        "--namespace",
        type=str,
        default="jupyterhub",
        help="Kubernetes namespace (default: jupyterhub)",
    )
    parser.add_argument(
        "--hours", type=int, default=1, help="Hours to look back (default: 1)"
    )
    parser.add_argument(
        "--cluster",
        type=str,
        default="cori-prod",
        help="Cluster name to filter by (default: cori-prod)",
    )
    parser.add_argument(
        "--pod-filter",
        type=str,
        default="jupyter",
        help="Filter pods containing this string (default: jupyter)",
    )
    return parser.parse_args()


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


def list_measurements(client):
    """List all measurements in the database"""
    print("=== MEASUREMENTS ===\n")

    try:
        result = client.query("SHOW MEASUREMENTS")
        measurements = []

        if result:
            for point in result.get_points():
                measurement = point.get("name")
                if measurement:
                    measurements.append(measurement)

        # Filter to kubernetes-related measurements
        k8s_measurements = [m for m in measurements if "kubernetes" in m or "kube" in m]

        if k8s_measurements:
            print("Kubernetes-related measurements:")
            for m in sorted(k8s_measurements):
                print(f"  - {m}")
        else:
            print("No kubernetes-related measurements found")
            print("\nAll measurements found:")
            for m in sorted(measurements[:20]):
                print(f"  - {m}")
            if len(measurements) > 20:
                print(f"  ... and {len(measurements) - 20} more")

        print(f"\nTotal measurements: {len(measurements)}")
        return k8s_measurements if k8s_measurements else measurements[:5]

    except Exception as e:
        print(f"ERROR listing measurements: {e}")
        return []


def inspect_measurement(client, measurement: str):
    """Inspect schema of a specific measurement"""
    print(f"\n=== INSPECTING: {measurement} ===")

    # Get tag keys
    print("\nTag Keys:")
    try:
        result = client.query(f'SHOW TAG KEYS FROM "{measurement}"')
        if result:
            for point in result.get_points():
                print(f"  - {point.get('tagKey')}")
        else:
            print("  No tags found")
    except Exception as e:
        print(f"  ERROR: {e}")

    # Get field keys
    print("\nField Keys:")
    try:
        result = client.query(f'SHOW FIELD KEYS FROM "{measurement}"')
        if result:
            for point in result.get_points():
                field = point.get("fieldKey")
                field_type = point.get("fieldType")
                print(f"  - {field} ({field_type})")
        else:
            print("  No fields found")
    except Exception as e:
        print(f"  ERROR: {e}")

    # Get tag values for namespace (if exists)
    print("\nNamespace Tag Values (if available):")
    try:
        result = client.query(
            f'SHOW TAG VALUES FROM "{measurement}" WITH KEY = "namespace"'
        )
        if result:
            namespaces = []
            for point in result.get_points():
                ns = point.get("value")
                if ns:
                    namespaces.append(ns)
            for ns in sorted(set(namespaces)):
                print(f"  - {ns}")
        else:
            print("  No 'namespace' tag found")
    except Exception as e:
        print(f"  Tag 'namespace' not found or error: {e}")


def get_sample_data(
    client,
    measurement: str,
    namespace: str,
    hours: int,
    cluster: str = None,
    pod_filter: str = None,
):
    """Get sample data from measurement"""
    filter_desc = f"namespace={namespace}"
    if cluster:
        filter_desc += f", cluster={cluster}"
    if pod_filter:
        filter_desc += f", pods matching '{pod_filter}'"
    print(f"\nSample Data (last {hours}h, {filter_desc}):")

    # Build WHERE clause
    where_clauses = [f"time > now() - {hours}h"]
    if namespace:
        where_clauses.append(f"\"namespace\" = '{namespace}'")
    if cluster:
        where_clauses.append(f"\"cluster\" = '{cluster}'")
    if pod_filter:
        where_clauses.append(f'"pod_name" =~ /{pod_filter}/')

    where_clause = " AND ".join(where_clauses)

    query = f'SELECT * FROM "{measurement}" WHERE {where_clause} LIMIT 5'

    try:
        result = client.query(query)

        if not result:
            # Try without filters
            query = (
                f'SELECT * FROM "{measurement}" WHERE time > now() - {hours}h LIMIT 5'
            )
            result = client.query(query)

        if result:
            points = list(result.get_points())
            if points:
                print(f"\nFound {len(points)} sample points:\n")
                for i, point in enumerate(points[:2], 1):
                    print(f"Sample {i}:")
                    print(f"  Time: {point.get('time')}")
                    print("  Tags:")
                    for key, value in sorted(point.items()):
                        if key != "time" and isinstance(value, str):
                            print(f"    {key}: {value}")
                    print("  Fields:")
                    for key, value in sorted(point.items()):
                        if key != "time" and not isinstance(value, str):
                            print(f"    {key}: {value}")
                    print()
            else:
                print("  No data found")
        else:
            print("  No results returned")

    except Exception as e:
        print(f"  ERROR: {e}")


def get_data_time_range(
    client, measurement: str, namespace: str = None, cluster: str = None
):
    """Get the earliest and latest timestamps for data in a measurement"""
    print(f"\n=== DATA TIME RANGE FOR: {measurement} ===")

    # First, get a field name to query (InfluxDB requires at least one field)
    try:
        field_result = client.query(f'SHOW FIELD KEYS FROM "{measurement}"')
        field_name = None
        if field_result:
            for point in field_result.get_points():
                field_name = point.get("fieldKey")
                if field_name:
                    break

        if not field_name:
            print("  Could not find any fields in this measurement")
            return None
    except Exception as e:
        print(f"  Error finding fields: {e}")
        return None

    # Build WHERE clause with namespace and cluster filters
    where_clauses = []
    if namespace:
        where_clauses.append(f"\"namespace\" = '{namespace}'")
    if cluster:
        where_clauses.append(f"\"cluster\" = '{cluster}'")

    where_clause = "WHERE " + " AND ".join(where_clauses) if where_clauses else ""

    queries = {
        "earliest": f'SELECT "{field_name}" FROM "{measurement}" {where_clause} ORDER BY time ASC LIMIT 1',
        "latest": f'SELECT "{field_name}" FROM "{measurement}" {where_clause} ORDER BY time DESC LIMIT 1',
    }

    results = {}

    for query_type, query in queries.items():
        try:
            result = client.query(query)
            if result:
                points = list(result.get_points())
                if points:
                    timestamp = points[0].get("time")
                    results[query_type] = timestamp
        except Exception as e:
            print(f"  Error getting {query_type} timestamp: {e}")
            # Try without filters if no results
            if namespace or cluster:
                try:
                    query_no_filter = f'SELECT "{field_name}" FROM "{measurement}" ORDER BY time {"ASC" if query_type == "earliest" else "DESC"} LIMIT 1'
                    result = client.query(query_no_filter)
                    if result:
                        points = list(result.get_points())
                        if points:
                            results[query_type] = points[0].get("time")
                except:
                    pass

    if results.get("earliest") and results.get("latest"):
        earliest = datetime.fromisoformat(results["earliest"].replace("Z", "+00:00"))
        latest = datetime.fromisoformat(results["latest"].replace("Z", "+00:00"))
        duration = latest - earliest

        print(f"\n  Earliest data: {earliest.strftime('%Y-%m-%d %H:%M:%S UTC')}")
        print(f"  Latest data:   {latest.strftime('%Y-%m-%d %H:%M:%S UTC')}")
        print(
            f"  Duration:      {duration.days} days, {duration.seconds // 3600} hours"
        )
        print(f"  Total hours:   {duration.total_seconds() / 3600:.1f} hours")

        # Calculate how far back from now
        from_now = datetime.now(earliest.tzinfo) - earliest
        print(f"  Data starts:   {from_now.days} days ago")

        return results
    else:
        print("  Could not determine time range")
        if namespace:
            print(f"  (tried with namespace='{namespace}' and without)")
        return None


def find_jupyterhub_pods(
    client, namespace: str, hours: int, cluster: str = None, pod_filter: str = None
):
    """Search for JupyterHub-related pods"""
    print(f"\n=== SEARCHING FOR JUPYTERHUB PODS ===")

    # Try different common measurement names
    measurements_to_try = [
        "kubernetes_pod_container",
        "kubernetes_pod",
        "kube_pod_container_status_running",
        "kube_pod_info",
    ]

    for measurement in measurements_to_try:
        # Build WHERE clause
        where_clauses = [f"time > now() - {hours}h"]
        if namespace:
            where_clauses.append(f"\"namespace\" = '{namespace}'")
        if cluster:
            where_clauses.append(f"\"cluster\" = '{cluster}'")
        if pod_filter:
            where_clauses.append(f'"pod_name" =~ /{pod_filter}/')

        where_clause = " AND ".join(where_clauses)

        query = f'SELECT * FROM "{measurement}" WHERE {where_clause} LIMIT 10'

        try:
            result = client.query(query)

            if result:
                points = list(result.get_points())
                if points:
                    # Check if any pod names contain 'jupyter'
                    jupyter_points = [
                        p
                        for p in points
                        if any("jupyter" in str(v).lower() for v in p.values())
                    ]

                    if jupyter_points:
                        print(
                            f"\n✓ Found JupyterHub pods in measurement: {measurement}"
                        )
                        print(f"\nSample pod data:")

                        for point in jupyter_points[:3]:
                            print(
                                f"\n  Pod: {point.get('pod_name', point.get('pod', 'unknown'))}"
                            )
                            print(f"  Time: {point.get('time')}")
                            print("  Available fields:")
                            for key, value in sorted(point.items()):
                                if key != "time":
                                    print(f"    {key}: {value}")

                        return measurement

        except Exception as e:
            continue

    # Try a broader search
    print("\nTrying broader search across all kubernetes measurements...")

    query = f"""
    SHOW MEASUREMENTS WHERE "name" =~ /kubernetes/
    """

    try:
        result = client.query(query)
        if result:
            for point in result.get_points():
                meas = point.get("name")
                # Try to find jupyter pods in each measurement
                test_query = (
                    f'SELECT * FROM "{meas}" WHERE time > now() - {hours}h LIMIT 5'
                )
                try:
                    test_result = client.query(test_query)
                    if test_result:
                        test_points = list(test_result.get_points())
                        jupyter_found = any(
                            "jupyter" in str(p).get("pod_name", "")
                            for p in test_points
                            if "pod_name" in p
                        )
                        if jupyter_found:
                            print(f"✓ Found data in: {meas}")
                            return meas
                except:
                    continue
    except Exception as e:
        pass

    print("✗ No JupyterHub pods found")
    print("\nTroubleshooting tips:")
    print("1. Verify the namespace is correct")
    print("2. Try increasing --hours to search further back")
    print("3. Check if Telegraf kubernetes input is properly configured")
    print("4. Verify pods are named with 'jupyter' prefix")

    return None


def main():
    args = parse_args()

    print("=== InfluxDB v1.x Schema Inspector for JupyterHub ===")
    print(f"Host: {INFLUX_HOST}:{INFLUX_PORT}")
    print(f"SSL: {INFLUX_SSL}")
    print(f"Verify SSL: {INFLUX_VERIFY_SSL}")
    print(f"Database: {INFLUX_DATABASE}")
    print(f"Namespace: {args.namespace}")
    print(f"Cluster: {args.cluster}")
    print(f"Pod filter: {args.pod_filter}")
    print(f"Time Range: Last {args.hours} hours")
    print()

    client = get_influx_client()

    try:
        # Test connection
        version = client.ping()
        print(f"✓ Connected to InfluxDB (version: {version})\n")

        # List all measurements
        measurements = list_measurements(client)

        # Search for JupyterHub pods
        jupyterhub_measurement = find_jupyterhub_pods(
            client, args.namespace, args.hours, args.cluster, args.pod_filter
        )

        # If we found JupyterHub data, inspect it in detail
        time_range = None
        if jupyterhub_measurement:
            # Show the full time range of available data
            time_range = get_data_time_range(
                client, jupyterhub_measurement, args.namespace, args.cluster
            )
            inspect_measurement(client, jupyterhub_measurement)
            get_sample_data(
                client,
                jupyterhub_measurement,
                args.namespace,
                args.hours,
                args.cluster,
                args.pod_filter,
            )

        # Inspect other kubernetes measurements
        if measurements:
            print("\n=== INSPECTING OTHER KUBERNETES MEASUREMENTS ===")
            for measurement in measurements[:3]:
                if measurement != jupyterhub_measurement:
                    get_data_time_range(
                        client, measurement, args.namespace, args.cluster
                    )
                    inspect_measurement(client, measurement)
                    get_sample_data(
                        client,
                        measurement,
                        args.namespace,
                        args.hours,
                        args.cluster,
                        args.pod_filter,
                    )

        print("\n=== RECOMMENDATIONS ===")
        if jupyterhub_measurement:
            print(f"✓ Found JupyterHub data in measurement: {jupyterhub_measurement}")
            print(f"\nTo import data, use:")

            # Build the import command with all non-default parameters
            import_cmd = f"  python import_from_influxdb_v1.py --measurement {jupyterhub_measurement}"

            # Add namespace if non-default
            if args.namespace != "jupyterhub":
                import_cmd += f" --namespace {args.namespace}"

            # Add cluster if non-default
            if args.cluster != "cori-prod":
                import_cmd += f" --cluster {args.cluster}"

            # Add pod-filter if non-default
            if args.pod_filter != "jupyter":
                import_cmd += f" --pod-filter {args.pod_filter}"

            if time_range and time_range.get("earliest"):
                # Calculate days back from earliest timestamp and round up to ensure we get all data
                from datetime import datetime, timezone
                import math

                earliest = datetime.fromisoformat(
                    time_range["earliest"].replace("Z", "+00:00")
                )
                now = datetime.now(timezone.utc)
                days_back = math.ceil((now - earliest).total_seconds() / 86400)

                print(f"\n  # Import all available data ({days_back} days):")
                full_import_cmd = import_cmd + f" --start={days_back}d"
                print(full_import_cmd)

                # Show additional useful examples
                print(f"\n  # Or import recent data only:")
                print(import_cmd + " --start=7d")
                print(import_cmd + " --start=30d")
            else:
                print(import_cmd + " --start=7d")
        else:
            print("✗ Could not find JupyterHub pod data")
            print("\nNext steps:")
            print("1. Verify Telegraf is collecting kubernetes metrics")
            print("2. Check if the namespace is correct")
            print("3. Try: --hours=24 for a longer search window")
            print("4. Review Telegraf kubernetes input configuration")

    except Exception as e:
        print(f"ERROR connecting to InfluxDB: {e}")
        print("\nCheck your environment variables:")
        print(f"  INFLUX_HOST={INFLUX_HOST}")
        print(f"  INFLUX_PORT={INFLUX_PORT}")
        print(f"  INFLUX_DATABASE={INFLUX_DATABASE}")
        print(f"  INFLUX_USER={INFLUX_USER}")
        print(f"  INFLUX_SSL={INFLUX_SSL}")
        print(f"  INFLUX_VERIFY_SSL={INFLUX_VERIFY_SSL}")
        print("\nFor HTTPS connections, set:")
        print("  export INFLUX_SSL=true")
        print("  export INFLUX_VERIFY_SSL=false  # if using self-signed cert")
        sys.exit(1)

    finally:
        client.close()


if __name__ == "__main__":
    main()
