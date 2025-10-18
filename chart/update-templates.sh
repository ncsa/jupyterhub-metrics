#!/bin/bash
# ============================================================================
# Update Helm Chart Templates from Source Files
# ============================================================================
# This script syncs the actual source files (init-db.sql, collector.sh, etc.)
# into the Helm chart's files/ directory so they can be embedded in ConfigMaps.
#
# Usage:
#   ./chart/update-templates.sh
#
# The script will:
# 1. Copy init-db.sql to chart/files/
# 2. Copy collector.sh to chart/files/
# 3. Copy grafana/provisioning/ to chart/files/grafana/provisioning/
# 4. Copy grafana/dashboards/ to chart/files/grafana/dashboards/
#
# After running this script, the Helm chart will have the latest versions
# of all source files embedded in its ConfigMaps.
# ============================================================================

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Project root (parent of chart directory)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Chart files directory
CHART_FILES_DIR="$SCRIPT_DIR/files"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Helm Chart Template Update${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Ensure files directory exists
mkdir -p "$CHART_FILES_DIR"
mkdir -p "$CHART_FILES_DIR/grafana/provisioning"
mkdir -p "$CHART_FILES_DIR/grafana/dashboards"

echo -e "${BLUE}Syncing source files to chart/files/...${NC}"
echo ""

# Function to copy file with status message
copy_file() {
    local source="$1"
    local dest="$2"
    local description="$3"

    if [[ ! -f "$source" ]]; then
        echo -e "${YELLOW}⚠ SKIPPING${NC}  $description"
        echo -e "            Source not found: $source"
        return 1
    fi

    mkdir -p "$(dirname "$dest")"
    cp "$source" "$dest"
    echo -e "${GREEN}✓ COPIED${NC}   $description"
    echo -e "            From: $source"
    echo -e "            To:   $dest"
    return 0
}

# Function to copy directory with status message
copy_directory() {
    local source="$1"
    local dest="$2"
    local description="$3"

    if [[ ! -d "$source" ]]; then
        echo -e "${YELLOW}⚠ SKIPPING${NC}  $description"
        echo -e "            Source directory not found: $source"
        return 1
    fi

    mkdir -p "$dest"
    cp -r "$source"/* "$dest/" 2>/dev/null || true
    echo -e "${GREEN}✓ COPIED${NC}   $description"
    echo -e "            From: $source"
    echo -e "            To:   $dest"
    return 0
}

# Track success/failure
declare -i TOTAL=0
declare -i SUCCEEDED=0
declare -i FAILED=0

# Copy init-db.sql
echo "1. Database Initialization Script"
if copy_file "$PROJECT_ROOT/init-db.sql" "$CHART_FILES_DIR/init-db.sql" "init-db.sql"; then
    ((SUCCEEDED++))
else
    ((FAILED++))
fi
((TOTAL++))
echo ""

# Copy collector.sh
echo "2. Metrics Collector Script"
if copy_file "$PROJECT_ROOT/collector.sh" "$CHART_FILES_DIR/collector.sh" "collector.sh"; then
    ((SUCCEEDED++))
else
    ((FAILED++))
fi
((TOTAL++))
echo ""

# Copy Grafana provisioning
echo "3. Grafana Provisioning Configuration"
if copy_directory "$PROJECT_ROOT/grafana/provisioning" "$CHART_FILES_DIR/grafana/provisioning" "grafana/provisioning/"; then
    ((SUCCEEDED++))
else
    ((FAILED++))
fi
((TOTAL++))
echo ""

# Copy Grafana dashboards
echo "4. Grafana Dashboards"
if copy_directory "$PROJECT_ROOT/grafana/dashboards" "$CHART_FILES_DIR/grafana/dashboards" "grafana/dashboards/"; then
    ((SUCCEEDED++))
else
    ((FAILED++))
fi
((TOTAL++))
echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Update Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Total items: $TOTAL"
echo -e "${GREEN}Succeeded: $SUCCEEDED${NC}"
if [[ $FAILED -gt 0 ]]; then
    echo -e "${YELLOW}Failed: $FAILED${NC}"
fi
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All source files successfully synced!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Review changes: git status"
    echo "2. Commit changes: git add chart/files/ && git commit -m 'chore: update helm chart templates'"
    echo "3. Deploy chart: helm install -f values.yaml <release-name> ./chart"
    echo ""
    exit 0
else
    echo -e "${YELLOW}⚠ Some source files were not found or could not be synced.${NC}"
    echo ""
    echo "Failed items:"
    echo "- Make sure you're running this script from the project root"
    echo "- Verify all source files exist in the project root"
    echo ""
    exit 1
fi
