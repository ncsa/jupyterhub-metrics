#!/usr/bin/env python3
"""
Inspect InfluxDB schema to understand the Telegraf kubernetes data structure
"""

import os
import sys
from influxdb_client import InfluxDBClient
import argparse

INFLUX_URL = os.getenv('INFLUX_URL', 'http://localhost:8086')
INFLUX_TOKEN = os.getenv('INFLUX_TOKEN', '')
INFLUX_ORG = os.getenv('INFLUX_ORG', '')
INFLUX_BUCKET = os.getenv('INFLUX_BUCKET', 'telegraf')


def parse_args():
    parser = argparse.ArgumentParser(
        description='Inspect InfluxDB schema for JupyterHub data'
    )
    parser.add_argument(
        '--namespace',
        type=str,
        default='jupyterhub',
        help='Kubernetes namespace (default: jupyterhub)'
    )
    parser.add_argument(
        '--time-range',
        type=str,
        default='-1h',
        help='Time range to inspect (default: -1h)'
    )
    return parser.parse_args()


def get_influx_client():
    """Create InfluxDB client"""
    if not INFLUX_TOKEN:
        print("ERROR: INFLUX_TOKEN environment variable not set")
        sys.exit(1)
    
    return InfluxDBClient(
        url=INFLUX_URL,
        token=INFLUX_TOKEN,
        org=INFLUX_ORG
    )


def list_measurements(client):
    """List all measurements in the bucket"""
    query = f'''
import "influxdata/influxdb/schema"

schema.measurements(bucket: "{INFLUX_BUCKET}")
'''
    
    print("=== MEASUREMENTS ===")
    query_api = client.query_api()
    
    try:
        tables = query_api.query(query, org=INFLUX_ORG)
        measurements = []
        for table in tables:
            for record in table.records:
                measurement = record.values.get('_value')
                if measurement:
                    measurements.append(measurement)
        
        if measurements:
            # Filter to kubernetes-related measurements
            k8s_measurements = [m for m in measurements if 'kubernetes' in m or 'kube' in m]
            
            print("\nKubernetes-related measurements:")
            for m in sorted(k8s_measurements):
                print(f"  - {m}")
            
            print(f"\nAll measurements: {len(measurements)}")
            print("(Showing only kubernetes-related above)")
            
            return k8s_measurements
        else:
            print("No measurements found")
            return []
            
    except Exception as e:
        print(f"ERROR listing measurements: {e}")
        return []


def inspect_measurement_schema(client, measurement: str, namespace: str, time_range: str):
    """Inspect schema of a specific measurement"""
    print(f"\n=== INSPECTING: {measurement} ===")
    
    # Get tag keys
    tag_query = f'''
import "influxdata/influxdb/schema"

schema.tagKeys(
    bucket: "{INFLUX_BUCKET}",
    predicate: (r) => r._measurement == "{measurement}",
    start: {time_range}
)
'''
    
    print("\nTag Keys:")
    query_api = client.query_api()
    
    try:
        tables = query_api.query(tag_query, org=INFLUX_ORG)
        tags = []
        for table in tables:
            for record in table.records:
                tag = record.values.get('_value')
                if tag:
                    tags.append(tag)
        
        for tag in sorted(tags):
            print(f"  - {tag}")
            
    except Exception as e:
        print(f"  ERROR: {e}")
    
    # Get field keys
    field_query = f'''
import "influxdata/influxdb/schema"

schema.fieldKeys(
    bucket: "{INFLUX_BUCKET}",
    predicate: (r) => r._measurement == "{measurement}",
    start: {time_range}
)
'''
    
    print("\nField Keys:")
    
    try:
        tables = query_api.query(field_query, org=INFLUX_ORG)
        fields = []
        for table in tables:
            for record in table.records:
                field = record.values.get('_value')
                if field:
                    fields.append(field)
        
        for field in sorted(fields):
            print(f"  - {field}")
            
    except Exception as e:
        print(f"  ERROR: {e}")
    
    # Get sample data
    sample_query = f'''
from(bucket: "{INFLUX_BUCKET}")
  |> range(start: {time_range})
  |> filter(fn: (r) => r["_measurement"] == "{measurement}")
  |> filter(fn: (r) => r["namespace"] == "{namespace}")
  |> limit(n: 5)
'''
    
    print("\nSample Data:")
    
    try:
        tables = query_api.query(sample_query, org=INFLUX_ORG)
        sample_count = 0
        for table in tables:
            for record in table.records:
                if sample_count == 0:
                    print("\nFirst record:")
                sample_count += 1
                if sample_count <= 2:
                    print(f"  Time: {record.get_time()}")
                    print(f"  Measurement: {record.get_measurement()}")
                    print(f"  Field: {record.get_field()}")
                    print(f"  Value: {record.get_value()}")
                    print("  Tags:")
                    for key, value in record.values.items():
                        if not key.startswith('_') and key not in ['result', 'table']:
                            print(f"    {key}: {value}")
                    print()
        
        if sample_count == 0:
            print("  No data found in this time range")
        else:
            print(f"  Total samples: {sample_count}")
            
    except Exception as e:
        print(f"  ERROR: {e}")


def find_jupyterhub_pods(client, namespace: str, time_range: str):
    """Search for JupyterHub-related pods"""
    print(f"\n=== SEARCHING FOR JUPYTERHUB PODS ===")
    
    # Try different common measurement names
    measurements_to_try = [
        'kubernetes_pod_container',
        'kubernetes_pod',
        'kube_pod_container',
        'kube_pod_info'
    ]
    
    for measurement in measurements_to_try:
        query = f'''
from(bucket: "{INFLUX_BUCKET}")
  |> range(start: {time_range})
  |> filter(fn: (r) => r["_measurement"] == "{measurement}")
  |> filter(fn: (r) => r["namespace"] == "{namespace}")
  |> filter(fn: (r) => r["pod_name"] =~ /jupyter/)
  |> keep(columns: ["_time", "pod_name", "namespace", "_field", "_value"])
  |> limit(n: 10)
'''
        
        query_api = client.query_api()
        
        try:
            tables = query_api.query(query, org=INFLUX_ORG)
            found = False
            
            for table in tables:
                for record in table.records:
                    if not found:
                        print(f"\n✓ Found JupyterHub pods in measurement: {measurement}")
                        found = True
                    
                    print(f"  Pod: {record.values.get('pod_name')}")
                    print(f"  Time: {record.get_time()}")
                    print(f"  Field: {record.get_field()} = {record.get_value()}")
                    
                    # Show all available tags
                    print("  Available tags:")
                    for key, value in record.values.items():
                        if not key.startswith('_') and key not in ['result', 'table']:
                            print(f"    {key}: {value}")
                    print()
            
            if found:
                return measurement
                
        except Exception as e:
            continue
    
    print("✗ No JupyterHub pods found in common measurements")
    return None


def main():
    args = parse_args()
    
    print("=== InfluxDB Schema Inspector for JupyterHub ===")
    print(f"URL: {INFLUX_URL}")
    print(f"Org: {INFLUX_ORG}")
    print(f"Bucket: {INFLUX_BUCKET}")
    print(f"Namespace: {args.namespace}")
    print(f"Time Range: {args.time_range}")
    print()
    
    client = get_influx_client()
    
    try:
        # List all measurements
        measurements = list_measurements(client)
        
        # Search for JupyterHub pods
        jupyterhub_measurement = find_jupyterhub_pods(
            client, 
            args.namespace, 
            args.time_range
        )
        
        # If we found JupyterHub data, inspect it in detail
        if jupyterhub_measurement:
            inspect_measurement_schema(
                client,
                jupyterhub_measurement,
                args.namespace,
                args.time_range
            )
        
        # Inspect other kubernetes measurements
        print("\n=== INSPECTING OTHER KUBERNETES MEASUREMENTS ===")
        for measurement in measurements[:3]:  # Inspect first 3
            if measurement != jupyterhub_measurement:
                inspect_measurement_schema(
                    client,
                    measurement,
                    args.namespace,
                    args.time_range
                )
        
        print("\n=== RECOMMENDATIONS ===")
        if jupyterhub_measurement:
            print(f"✓ Found JupyterHub data in measurement: {jupyterhub_measurement}")
            print(f"\nTo import data, update the import script's flux query to use:")
            print(f'  _measurement == "{jupyterhub_measurement}"')
            print("\nAnd adjust the field filters based on the available fields shown above.")
        else:
            print("✗ Could not find JupyterHub pod data")
            print("\nTroubleshooting:")
            print("1. Check that Telegraf is configured to collect kubernetes metrics")
            print("2. Verify the namespace is correct")
            print("3. Try a longer time range (e.g., --time-range=-24h)")
            print("4. Check if pods use a different naming pattern")
        
    finally:
        client.close()


if __name__ == '__main__':
    main()
