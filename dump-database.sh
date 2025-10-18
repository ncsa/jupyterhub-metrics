#!/bin/bash
# TimescaleDB Backup Script for jupyterhub_metrics
# This script creates a complete backup including schema, data, and views

set -e

# Load configuration from centralized .env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config-loader.sh"

# Backup directory and filename
BACKUP_DIR="./backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/jupyterhub_metrics_${TIMESTAMP}.sql.gz"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}TimescaleDB Backup Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Export password for pg_dump
export PGPASSWORD="$DB_PASSWORD"

echo -e "${BLUE}Starting backup of database: ${GREEN}$DB_NAME${NC}"
echo -e "${BLUE}Backup file: ${GREEN}$BACKUP_FILE${NC}"
echo ""

# Perform the backup
# Options:
#   -h: host
#   -p: port
#   -U: user
#   -d: database
#   -F p: plain text format (SQL script)
#   --no-owner: don't include ownership commands
#   --no-acl: don't include access privileges
#   --verbose: show detailed output
#   -E UTF8: encoding
# Output is piped to gzip for compression

pg_dump -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -F p \
        --no-owner \
        --no-acl \
        --verbose \
        -E UTF8 | gzip > "$BACKUP_FILE"

# Unset password
unset PGPASSWORD

# Check if backup was successful
if [ $? -eq 0 ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Backup completed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${BLUE}File: ${GREEN}$BACKUP_FILE${NC}"
    echo -e "${BLUE}Size: ${GREEN}$BACKUP_SIZE${NC}"
    echo ""
    echo -e "${BLUE}To restore this backup, run:${NC}"
    echo -e "${GREEN}  ./restore-database.sh $BACKUP_FILE${NC}"
    echo ""
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Backup failed!${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi
