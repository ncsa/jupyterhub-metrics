#!/bin/bash

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# If .env file exists, load it
if [[ -f "$ENV_FILE" ]]; then
    source "${SCRIPT_DIR}/config-loader.sh"
fi

# Set defaults
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-jupyterhub_metrics}"
DB_USER="${DB_USER:-metrics_user}"
DB_PASSWORD="${DB_PASSWORD:-}"

# Validate required variables
if [[ -z "$DB_PASSWORD" ]]; then
    echo "ERROR: DB_PASSWORD is not set"
    echo "Create .env file: cp .env.example .env"
    exit 1
fi

# Export password for psql
export PGPASSWORD="$DB_PASSWORD"

log() {
    echo "[$(date -u +"%Y-%m-%d %H:%M:%S UTC")] $*"
}

# Check if database is accessible
check_db() {
    if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c '\q' 2>/dev/null; then
        log "ERROR: Cannot connect to database"
        exit 1
    fi
}

# Synchronize users table from container_observations
sync_users() {
    log "Synchronizing users table from container_observations..."

    # Get counts before
    local users_before=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM users;" | xargs)

    # Upsert users from container_observations
    # Extract user_id from pod_name, use email prefix as fallback for full_name
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<'EOF'
INSERT INTO users (email, user_id, full_name, first_seen, last_seen)
SELECT
    user_email,
    CASE
        WHEN pod_name LIKE 'jupyter-%' THEN
            regexp_replace(substring(pod_name from 9), '-[^-]+$', '')
        ELSE 'unknown'
    END AS user_id,
    COALESCE(
        NULLIF(MAX(user_name), 'unknown'),
        NULLIF(MAX(user_name), ''),
        split_part(user_email, '@', 1)
    ) AS full_name,
    MIN(timestamp) AS first_seen,
    MAX(timestamp) AS last_seen
FROM container_observations
GROUP BY user_email, pod_name
ON CONFLICT (email) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    full_name = COALESCE(
        NULLIF(users.full_name, ''),
        NULLIF(EXCLUDED.full_name, ''),
        split_part(EXCLUDED.email, '@', 1)
    ),
    first_seen = LEAST(users.first_seen, EXCLUDED.first_seen),
    last_seen = GREATEST(users.last_seen, EXCLUDED.last_seen);
EOF

    if [ $? -eq 0 ]; then
        local users_after=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM users;" | xargs)
        local new_users=$((users_after - users_before))
        log "✓ Users table synchronized"
        log "  Users before: $users_before"
        log "  Users after: $users_after"
        log "  New users: $new_users"
    else
        log "ERROR: Failed to synchronize users table"
        exit 1
    fi
}

# Refresh user_sessions materialized view
refresh_sessions_view() {
    log "Refreshing user_sessions materialized view..."

    local start_time=$(date +%s)

    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "REFRESH MATERIALIZED VIEW CONCURRENTLY user_sessions;" > /dev/null 2>&1; then
        local elapsed=$(($(date +%s) - start_time))
        local session_count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM user_sessions;" | xargs)
        log "✓ user_sessions view refreshed in ${elapsed}s"
        log "  Total sessions: $session_count"
    else
        log "ERROR: Failed to refresh user_sessions materialized view"
        exit 1
    fi
}

# Refresh continuous aggregates (optional - they update automatically on schedule)
refresh_continuous_aggregates() {
    log "Refreshing continuous aggregates..."

    # Get time range from container_observations
    local time_range=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT MIN(timestamp), MAX(timestamp) FROM container_observations;" | xargs)

    if [[ -z "$time_range" || "$time_range" == "|" ]]; then
        log "  No data in container_observations, skipping continuous aggregates"
        return
    fi

    local start_time=$(echo "$time_range" | cut -d'|' -f1 | xargs)
    local end_time=$(echo "$time_range" | cut -d'|' -f2 | xargs)

    log "  Time range: $start_time to $end_time"

    # Refresh hourly_node_stats
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "CALL refresh_continuous_aggregate('hourly_node_stats', '$start_time', '$end_time');" > /dev/null 2>&1; then
        log "  ✓ hourly_node_stats refreshed"
    else
        log "  WARNING: Failed to refresh hourly_node_stats (may update on schedule)"
    fi

    # Refresh hourly_image_stats
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "CALL refresh_continuous_aggregate('hourly_image_stats', '$start_time', '$end_time');" > /dev/null 2>&1; then
        log "  ✓ hourly_image_stats refreshed"
    else
        log "  WARNING: Failed to refresh hourly_image_stats (may update on schedule)"
    fi
}

# Print summary
print_summary() {
    log "Database summary:"

    echo ""
    echo "=== Container Observations ==="
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT
            COUNT(*) as total_rows,
            COUNT(DISTINCT user_email) as unique_users,
            MIN(timestamp) as earliest,
            MAX(timestamp) as latest
        FROM container_observations;
    "

    echo ""
    echo "=== Users Table ==="
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT
            COUNT(*) as total_users,
            MIN(first_seen) as earliest_user,
            MAX(last_seen) as latest_activity
        FROM users;
    "

    echo ""
    echo "=== User Sessions ==="
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT
            COUNT(*) as total_sessions,
            ROUND(SUM(runtime_hours)::numeric, 2) as total_runtime_hours,
            ROUND(AVG(runtime_hours)::numeric, 2) as avg_session_hours
        FROM user_sessions;
    "
}

# Main
main() {
    log "=== JupyterHub Metrics - Sync Users and Refresh Views ==="
    log "Configuration:"
    log "  DB_HOST: $DB_HOST"
    log "  DB_NAME: $DB_NAME"
    log "  DB_USER: $DB_USER"
    echo ""

    check_db

    sync_users
    echo ""

    refresh_sessions_view
    echo ""

    refresh_continuous_aggregates
    echo ""

    print_summary

    log "=== All operations completed successfully ==="
}

main
