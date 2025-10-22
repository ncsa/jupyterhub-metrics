#!/bin/bash
# TimescaleDB Backup Script - Simplified
# Uses TimescaleDB best practices: custom format (-Fc) with pg_dump

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config-loader.sh"

# Backup configuration
BACKUP_DIR="./backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/jupyterhub_metrics_${TIMESTAMP}.dump"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}TimescaleDB Backup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

mkdir -p "$BACKUP_DIR"
export PGPASSWORD="$DB_PASSWORD"

echo -e "${BLUE}Starting backup...${NC}"
echo -e "${BLUE}  Database: ${GREEN}$DB_NAME${NC}"
echo -e "${BLUE}  Output: ${GREEN}$BACKUP_FILE${NC}"
echo ""

# Use custom format (-Fc) - TimescaleDB recommended
pg_dump -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -Fc \
        --verbose \
        -f "$BACKUP_FILE"

unset PGPASSWORD

if [ $? -eq 0 ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Backup completed!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${BLUE}File: ${GREEN}$BACKUP_FILE${NC}"
    echo -e "${BLUE}Size: ${GREEN}$BACKUP_SIZE${NC}"
    echo ""
    echo -e "${BLUE}To restore:${NC}"
    echo -e "${GREEN}  ./restore-database-simple.sh $BACKUP_FILE${NC}"
    echo ""
else
    echo -e "${RED}Backup failed!${NC}"
    exit 1
fi
