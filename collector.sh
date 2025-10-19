#!/bin/bash

set -euo pipefail

# Load configuration - works in both Docker Compose and Kubernetes environments
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# If .env file exists (Docker Compose), load it
# If running in Kubernetes, environment variables are already set via Secrets/ConfigMaps
if [[ -f "$ENV_FILE" ]]; then
    source "${SCRIPT_DIR}/config-loader.sh"
fi

# Set defaults if not already set (for Kubernetes environment where env vars come from Secrets)
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-jupyterhub_metrics}"
DB_USER="${DB_USER:-metrics_user}"
DB_PASSWORD="${DB_PASSWORD:-}"
COLLECTION_INTERVAL="${COLLECTION_INTERVAL:-300}"
NAMESPACE="${NAMESPACE:-jupyterhub}"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-}"

# Validate required variables are set
if [[ -z "$DB_PASSWORD" ]]; then
    echo "ERROR: DB_PASSWORD is not set"
    echo "For Docker Compose: Create .env file (cp .env.example .env)"
    echo "For Kubernetes: Verify secrets are properly configured"
    exit 1
fi

# Export password for psql
export PGPASSWORD="$DB_PASSWORD"

log() {
    echo "[$(date -u +"%Y-%m-%d %H:%M:%S UTC")] $*"
}

wait_for_db() {
    log "Waiting for database to be ready..."
    until psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c '\q' 2>/dev/null; do
        log "Database not ready, waiting..."
        sleep 5
    done
    log "Database is ready"
}

collect_metrics() {
    local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S")
    local now=$(date +%s)

    log "Collecting metrics at $timestamp"

    # Create temporary files for batch insert
    local temp_file=$(mktemp)
    local users_file=$(mktemp)

    # Fetch pod data using kubectl
    # Use --context flag if KUBECTL_CONTEXT is set (for local development)
    # Otherwise use in-cluster authentication (service account token)
    local kubectl_cmd="kubectl"
    if [[ -n "$KUBECTL_CONTEXT" ]]; then
        kubectl_cmd="kubectl --context=$KUBECTL_CONTEXT"
    fi

    $kubectl_cmd get po -o json -n "$NAMESPACE" \
        -l component=singleuser-server 2>/dev/null | \
    jq -r --arg now "$now" --arg ts "$timestamp" '
        [.items[] |
        select(.status.phase == "Running") |
        (($now | tonumber) - (.metadata.creationTimestamp | fromdateiso8601)) as $age_seconds |
        (.spec.containers[0].image | split(":")) as $img_parts |
        ($img_parts[0] | split("/")[-1]) as $base_image |
        ($img_parts[1] // "latest") as $version |
        (.metadata.name | if startswith("jupyter-") then .[8:] else "unknown" end) as $user_id |
        {
            timestamp: $ts,
            email: ((.spec.containers[0].env[]? | select(.name == "GIT_AUTHOR_EMAIL") | .value) // "unknown"),
            name: ((.spec.containers[0].env[]? | select(.name == "GIT_AUTHOR_NAME") | .value) // "unknown"),
            node: .spec.nodeName,
            image: .spec.containers[0].image,
            base_image: $base_image,
            version: $version,
            age_seconds: $age_seconds,
            pod_name: .metadata.name,
            user_id: $user_id
        }] as $pods |
        ($pods[] | [.timestamp, .email, .name, .node, .image, .base_image, .version, .age_seconds, .pod_name] | @tsv),
        ($pods | map(select(.user_id != "unknown" and .email != "unknown")) | sort_by(.email) | unique_by(.email) | .[] | [.user_id, .email, .name, .timestamp] | @tsv)
    ' > "$temp_file"

    # Split combined output into observations and users files
    # Use POSIX character classes [[:digit:]] instead of \d for compatibility
    grep -E "^[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}" "$temp_file" > "${temp_file}.obs" || true
    grep -v -E "^[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}" "$temp_file" > "$users_file" || true
    mv "${temp_file}.obs" "$temp_file"

    local count=$(wc -l < "$temp_file")
    local user_count=$(wc -l < "$users_file")

    if [ "$count" -eq 0 ]; then
        log "No running containers found"
        rm "$temp_file"
        rm "$users_file"
        return
    fi

    log "Found $count running containers, inserting into database..."

    # First, upsert users data
    if [ "$user_count" -gt 0 ]; then
        log "Upserting $user_count user mappings..."
        psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" <<EOF > /dev/null
CREATE TEMP TABLE temp_users (user_id TEXT, email TEXT, full_name TEXT, ts TIMESTAMPTZ);
COPY temp_users (user_id, email, full_name, ts) FROM STDIN WITH (FORMAT text, DELIMITER E'\t', NULL 'null');
$(cat "$users_file")
\.

INSERT INTO users (email, user_id, full_name, first_seen, last_seen)
SELECT email, user_id, full_name, ts, ts
FROM temp_users
ON CONFLICT (email) DO UPDATE
SET
    user_id = EXCLUDED.user_id,
    full_name = EXCLUDED.full_name,
    last_seen = EXCLUDED.last_seen;

DROP TABLE temp_users;
EOF

        if [ $? -eq 0 ]; then
            log "Successfully upserted $user_count user mappings"
        else
            log "WARNING: Failed to upsert user mappings"
        fi
    fi

    # Batch insert observations using COPY for better performance
    psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" <<EOF
COPY container_observations (timestamp, user_email, user_name, node_name, container_image, container_base, container_version, age_seconds, pod_name)
FROM STDIN
WITH (FORMAT text, DELIMITER E'\t', NULL 'null');
$(cat "$temp_file")
\.
EOF

    local insert_status=$?

    if [ $insert_status -eq 0 ]; then
        log "Successfully inserted $count observations"

        # Refresh sessions materialized view (uses CONCURRENTLY to avoid blocking reads)
        # This keeps dashboard queries fast by pre-computing session data
        log "Refreshing sessions materialized view..."
        if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "REFRESH MATERIALIZED VIEW CONCURRENTLY user_sessions;" > /dev/null 2>&1; then
            log "Materialized view refresh completed successfully"
        else
            log "WARNING: Failed to refresh materialized view"
        fi
    else
        log "ERROR: Failed to insert observations (exit code: $insert_status)"
    fi

    rm "$temp_file"
    rm "$users_file"
}

# Main loop
main() {
    log "Starting JupyterHub metrics collector"
    log "Configuration:"
    log "  DB_HOST: $DB_HOST"
    log "  DB_NAME: $DB_NAME"
    log "  DB_USER: $DB_USER"
    log "  NAMESPACE: $NAMESPACE"
    log "  COLLECTION_INTERVAL: ${COLLECTION_INTERVAL}s"
    if [[ -n "$KUBECTL_CONTEXT" ]]; then
        log "  KUBECTL_CONTEXT: $KUBECTL_CONTEXT"
    else
        log "  Using in-cluster Kubernetes authentication"
    fi

    wait_for_db

    # Initial collection
    collect_metrics

    # Continuous collection loop
    while true; do
        sleep "$COLLECTION_INTERVAL"
        collect_metrics
    done
}

# Handle signals gracefully
trap 'log "Received shutdown signal, exiting..."; exit 0' SIGTERM SIGINT

main
