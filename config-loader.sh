#!/bin/bash
# ============================================================================
# Configuration Loader for JupyterHub Metrics
# ============================================================================
# This script loads environment variables from .env file
# Source this file in other scripts to use: source ./config-loader.sh
#
# Usage:
#   source ./config-loader.sh
#   echo "Database host: $DB_HOST"
#   echo "Database password: $DB_PASSWORD"
#
# The script will:
# 1. Find the .env file in the project root
# 2. Load all variables from .env
# 3. Validate that required variables are set
# 4. Exit with error if required variables are missing
# ============================================================================

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Path to .env file - should be in the root of the project
ENV_FILE="${SCRIPT_DIR}/.env"

# ============================================================================
# Check if .env file exists
# ============================================================================
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: Configuration file not found: $ENV_FILE"
    echo ""
    echo "Please create a .env file by copying .env.example:"
    echo "  cp .env.example .env"
    echo ""
    echo "Then edit .env with your actual configuration values."
    exit 1
fi

# ============================================================================
# Load environment variables from .env file
# ============================================================================
# Source the .env file, allowing it to override any existing environment variables
set -a
source "$ENV_FILE"
set +a

# ============================================================================
# Validate required configuration variables
# ============================================================================
REQUIRED_VARS=(
    "DB_HOST"
    "DB_PORT"
    "DB_NAME"
    "DB_USER"
    "DB_PASSWORD"
    "GRAFANA_ADMIN_USER"
    "GRAFANA_ADMIN_PASSWORD"
    "COLLECTION_INTERVAL"
    "KUBECTL_CONTEXT"
    "NAMESPACE"
)

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        MISSING_VARS+=("$var")
    fi
done

if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
    echo "ERROR: The following required configuration variables are not set:"
    printf '  - %s\n' "${MISSING_VARS[@]}"
    echo ""
    echo "Please check your .env file at: $ENV_FILE"
    echo "Use .env.example as a template."
    exit 1
fi

# ============================================================================
# Validate port numbers are numeric
# ============================================================================
if ! [[ "$DB_PORT" =~ ^[0-9]+$ ]]; then
    echo "ERROR: DB_PORT must be a number, got: $DB_PORT"
    exit 1
fi

if ! [[ "$GRAFANA_PORT" =~ ^[0-9]+$ ]]; then
    echo "ERROR: GRAFANA_PORT must be a number, got: $GRAFANA_PORT"
    exit 1
fi

if ! [[ "$COLLECTION_INTERVAL" =~ ^[0-9]+$ ]]; then
    echo "ERROR: COLLECTION_INTERVAL must be a number, got: $COLLECTION_INTERVAL"
    exit 1
fi

# ============================================================================
# Export variables for use in child processes
# ============================================================================
export DB_HOST
export DB_PORT
export DB_NAME
export DB_USER
export DB_PASSWORD
export GRAFANA_ADMIN_USER
export GRAFANA_ADMIN_PASSWORD
export GRAFANA_PORT
export COLLECTION_INTERVAL
export KUBECTL_CONTEXT
export NAMESPACE
export K8S_NAMESPACE
export TIMESCALEDB_STORAGE_SIZE
export GRAFANA_STORAGE_SIZE
export INGRESS_HOST
export POD_LABEL_SELECTOR
export INFLUX_HOST
export INFLUX_PORT
export INFLUX_USER
export INFLUX_PASSWORD
export INFLUX_DATABASE
export INFLUX_SSL
export INFLUX_VERIFY_SSL

# ============================================================================
# Configuration loaded successfully
# ============================================================================
if [[ "${VERBOSE:-0}" == "1" ]]; then
    echo "Configuration loaded successfully from: $ENV_FILE"
    echo "  Database: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
    echo "  Grafana: $GRAFANA_ADMIN_USER on port $GRAFANA_PORT"
    echo "  Collection interval: ${COLLECTION_INTERVAL}s"
    echo "  Kubernetes namespace: $NAMESPACE"
fi
