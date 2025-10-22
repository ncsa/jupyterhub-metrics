#!/bin/bash
# TimescaleDB Restore Script - Simplified
# Uses TimescaleDB best practices from official documentation

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config-loader.sh"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}TimescaleDB Restore${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if backup file is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: No backup file specified${NC}"
    echo ""
    echo "Usage: $0 <backup_file.dump>"
    echo ""
    echo "Available backups:"
    ls -lh backups/*.dump 2>/dev/null || ls -lh backups/*.sql.gz 2>/dev/null || echo "  No backups found"
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
    echo -e "${RED}Error: Backup file not found: $BACKUP_FILE${NC}"
    exit 1
fi

BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)

echo -e "${BLUE}Backup file: ${GREEN}$BACKUP_FILE${NC}"
echo -e "${BLUE}File size: ${GREEN}$BACKUP_SIZE${NC}"
echo -e "${BLUE}Target database: ${GREEN}$DB_NAME${NC}"
echo ""

# Warning
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}WARNING: This will DROP the database!${NC}"
echo -e "${YELLOW}All existing data will be LOST!${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

read -p "Type 'yes' to proceed: " confirmation

if [ "$confirmation" != "yes" ]; then
    echo -e "${RED}Restore cancelled.${NC}"
    exit 1
fi

echo ""
export PGPASSWORD="$DB_PASSWORD"

# Step 1: Terminate connections
echo -e "${BLUE}[1/5] Terminating existing connections...${NC}"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres \
     -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" \
     > /dev/null 2>&1 || true

# Step 2: Drop database
echo -e "${BLUE}[2/5] Dropping existing database...${NC}"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres \
     -c "DROP DATABASE IF EXISTS $DB_NAME;" > /dev/null 2>&1

# Step 3: Create database
echo -e "${BLUE}[3/5] Creating new database...${NC}"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres \
     -c "CREATE DATABASE $DB_NAME;" > /dev/null 2>&1

# Step 4: Restore using pg_restore
echo -e "${BLUE}[4/5] Restoring backup...${NC}"
echo -e "${YELLOW}This may take several minutes...${NC}"
echo -e "${YELLOW}Note: Showing errors and warnings only${NC}"
echo ""

# IMPORTANT: Do NOT use -j (parallel jobs) - it breaks TimescaleDB catalogs
# Do NOT use --single-transaction - TimescaleDB restore may have expected errors
# Use --exit-on-error to stop on critical failures
pg_restore -h "$DB_HOST" \
           -p "$DB_PORT" \
           -U "$DB_USER" \
           -d "$DB_NAME" \
           --no-owner \
           --no-acl \
           --verbose \
           "$BACKUP_FILE" 2>&1 | grep -E "^pg_restore: error:|ERROR:|WARNING:|FATAL:" || true

RESTORE_EXIT=${PIPESTATUS[0]}

if [ $RESTORE_EXIT -ne 0 ]; then
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Restore failed!${NC}"
    echo -e "${RED}========================================${NC}"
    unset PGPASSWORD
    exit 1
fi

# Step 5: Fix continuous aggregates (recreate replication slots)
echo -e "${BLUE}[5/6] Fixing continuous aggregates...${NC}"
# Replication slots don't get restored by pg_dump, causing "replication slot does not exist" errors
# We need to manually refresh each continuous aggregate to recreate them
CAGG_COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
     -tAc "SELECT COUNT(*) FROM timescaledb_information.continuous_aggregates;" 2>/dev/null || echo "0")

if [ "$CAGG_COUNT" -gt 0 ]; then
    echo -e "${BLUE}Found $CAGG_COUNT continuous aggregates, refreshing to recreate replication slots...${NC}"

    # Refresh each continuous aggregate
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<'EOSQL' 2>&1 | grep -E "NOTICE|ERROR" || true
DO $$
DECLARE
    cagg RECORD;
BEGIN
    FOR cagg IN
        SELECT view_name
        FROM timescaledb_information.continuous_aggregates
    LOOP
        BEGIN
            RAISE NOTICE 'Refreshing continuous aggregate: %', cagg.view_name;
            EXECUTE format('CALL refresh_continuous_aggregate(%L, NULL, NULL)', cagg.view_name);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Failed to refresh %: %', cagg.view_name, SQLERRM;
        END;
    END LOOP;
END $$;
EOSQL

    echo -e "${GREEN}✓ Continuous aggregates refreshed${NC}"
else
    echo -e "${YELLOW}No continuous aggregates found${NC}"
fi

# Step 6: Refresh regular materialized views
echo -e "${BLUE}[6/6] Refreshing materialized views...${NC}"
VIEW_EXISTS=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
     -tAc "SELECT COUNT(*) FROM pg_matviews WHERE matviewname = 'user_sessions';" 2>/dev/null || echo "0")

if [ "$VIEW_EXISTS" = "1" ]; then
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
         -c "REFRESH MATERIALIZED VIEW CONCURRENTLY user_sessions;" \
         > /dev/null 2>&1 && echo -e "${GREEN}✓ Materialized view refreshed${NC}" || echo -e "${YELLOW}Note: Could not refresh view${NC}"
else
    echo -e "${YELLOW}Note: Materialized view not found (may not exist in this backup)${NC}"
fi

unset PGPASSWORD

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Restore completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${BLUE}Database: ${GREEN}$DB_NAME${NC}"
echo -e "${BLUE}Restored from: ${GREEN}$BACKUP_FILE${NC}"
echo ""
echo -e "${BLUE}Verifying TimescaleDB jobs...${NC}"
export PGPASSWORD="$DB_PASSWORD"
JOB_COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
     -tAc "SELECT COUNT(*) FROM timescaledb_information.jobs;" 2>/dev/null || echo "0")
unset PGPASSWORD

echo -e "${GREEN}✓ Found $JOB_COUNT TimescaleDB background jobs${NC}"
echo ""
