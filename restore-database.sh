#!/bin/bash
# TimescaleDB Restore Script for jupyterhub_metrics
# This script restores a complete backup including schema, data, and views

set -e

# Load configuration from centralized .env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config-loader.sh"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}TimescaleDB Restore Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if backup file is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: No backup file specified${NC}"
    echo ""
    echo "Usage: $0 <backup_file.sql.gz>"
    echo ""
    echo "Available backups:"
    ls -lh backups/*.sql.gz 2>/dev/null || echo "  No backups found in ./backups/"
    echo ""
    exit 1
fi

BACKUP_FILE="$1"

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo -e "${RED}Error: Backup file not found: $BACKUP_FILE${NC}"
    exit 1
fi

# Detect if file is gzipped
IS_GZIPPED=false
if [[ "$BACKUP_FILE" == *.gz ]]; then
    IS_GZIPPED=true
fi

BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)

echo -e "${BLUE}Backup file: ${GREEN}$BACKUP_FILE${NC}"
echo -e "${BLUE}File size: ${GREEN}$BACKUP_SIZE${NC}"
echo -e "${BLUE}Target database: ${GREEN}$DB_NAME${NC}"
echo ""

# Warning message
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}WARNING: This will DROP and recreate${NC}"
echo -e "${YELLOW}the database '$DB_NAME'!${NC}"
echo -e "${YELLOW}All existing data will be LOST!${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Ask for confirmation
read -p "Are you sure you want to continue? (type 'yes' to proceed): " confirmation

if [ "$confirmation" != "yes" ]; then
    echo -e "${RED}Restore cancelled.${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Starting restore process...${NC}"
echo ""

# Export password for psql commands
export PGPASSWORD="$DB_PASSWORD"

# Step 1: Terminate existing connections to the database
echo -e "${BLUE}[1/4] Terminating existing connections...${NC}"
psql -h "$DB_HOST" \
     -p "$DB_PORT" \
     -U "$DB_USER" \
     -d postgres \
     -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" \
     > /dev/null 2>&1 || true

# Step 2: Drop the database
echo -e "${BLUE}[2/4] Dropping existing database...${NC}"
psql -h "$DB_HOST" \
     -p "$DB_PORT" \
     -U "$DB_USER" \
     -d postgres \
     -c "DROP DATABASE IF EXISTS $DB_NAME;" \
     > /dev/null 2>&1

# Step 3: Create the database
echo -e "${BLUE}[3/4] Creating new database...${NC}"
psql -h "$DB_HOST" \
     -p "$DB_PORT" \
     -U "$DB_USER" \
     -d postgres \
     -c "CREATE DATABASE $DB_NAME;" \
     > /dev/null 2>&1

# Step 4: Restore the backup
echo -e "${BLUE}[4/4] Restoring backup...${NC}"
if [ "$IS_GZIPPED" = true ]; then
    # Decompress and restore
    gunzip -c "$BACKUP_FILE" | psql -h "$DB_HOST" \
         -p "$DB_PORT" \
         -U "$DB_USER" \
         -d "$DB_NAME" \
         --quiet
else
    # Restore uncompressed file
    psql -h "$DB_HOST" \
         -p "$DB_PORT" \
         -U "$DB_USER" \
         -d "$DB_NAME" \
         -f "$BACKUP_FILE" \
         --quiet
fi

# Unset password
unset PGPASSWORD

# Check if restore was successful
if [ $? -eq 0 ]; then
    # Refresh materialized views
    echo -e "${BLUE}[5/5] Refreshing materialized views...${NC}"
    export PGPASSWORD="$DB_PASSWORD"
    psql -h "$DB_HOST" \
         -p "$DB_PORT" \
         -U "$DB_USER" \
         -d "$DB_NAME" \
         -c "REFRESH MATERIALIZED VIEW user_sessions;" \
         > /dev/null 2>&1 || echo -e "${YELLOW}Note: Materialized view refresh skipped (may not exist in older backups)${NC}"
    unset PGPASSWORD

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Restore completed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${BLUE}Database: ${GREEN}$DB_NAME${NC}"
    echo -e "${BLUE}Restored from: ${GREEN}$BACKUP_FILE${NC}"
    echo ""
else
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Restore failed!${NC}"
    echo -e "${RED}========================================${NC}"
    echo -e "${YELLOW}The database may be in an inconsistent state.${NC}"
    echo ""
    exit 1
fi
