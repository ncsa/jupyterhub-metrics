#!/bin/bash
# Migration script wrapper to import historical data from InfluxDB
# This script sources the centralized .env configuration

set -euo pipefail

# Load configuration from centralized .env file (one level up)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: Configuration file not found: $ENV_FILE"
    echo ""
    echo "Please create a .env file in the project root by copying .env.example:"
    echo "  cp .env.example .env"
    echo ""
    echo "Then edit .env with your actual configuration values."
    exit 1
fi

# Load the configuration
set -a
source "$ENV_FILE"
set +a

# Activate Python virtual environment
if [[ -d "venv/bin" ]]; then
    source venv/bin/activate
elif [[ -d ".venv/bin" ]]; then
    source .venv/bin/activate
else
    echo "WARNING: No Python virtual environment found"
fi

# Export PostgreSQL configuration for Python script
export PG_HOST="$DB_HOST"
export PG_PORT="$DB_PORT"
export PG_DB="$DB_NAME"
export PG_USER="$DB_USER"
export PG_PASSWORD="$DB_PASSWORD"

# Export InfluxDB configuration
export INFLUX_URL="${INFLUX_URL:-http://localhost:8086}"
export INFLUX_USER="${INFLUX_USER:-admin}"
export INFLUX_PASSWORD="${INFLUX_PASSWORD:-}"
export INFLUX_DATABASE="${INFLUX_DATABASE:-telegraf}"
export INFLUX_VERIFY_SSL="${INFLUX_VERIFY_SSL:-true}"

# Run the import script with provided arguments
echo "Importing historical data from InfluxDB v1.x..."
echo "Configuration:"
echo "  PostgreSQL: $PG_USER@$PG_HOST:$PG_PORT/$PG_DB"
echo "  InfluxDB: $INFLUX_USER@$INFLUX_URL/$INFLUX_DATABASE"
echo ""

python import_from_influxdb_v1.py "$@"
