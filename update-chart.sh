#!/bin/bash
# ============================================================================
# JupyterHub Metrics - Chart and Collector Update Script
# ============================================================================
# This script performs updates to the Helm chart:
#
# 1. Builds and pushes the collector Docker image to ncsa/jupyterhub-metrics-collector
# 2. Bumps the patch version in Chart.yaml if requested
# 3. Collector image version automatically matches Chart version
#
# Note: All configuration files (init-db.sql, grafana configs) are managed
# directly in chart/files/. There is no syncing from root directory.
#
# Usage:
#   ./update-chart.sh                  # Use current Chart.yaml version
#   ./update-chart.sh next             # Bump to next patch version before building
#   PUSH_TO_REGISTRY=false ./update-chart.sh  # Build only, don't push
#
# Arguments:
#   next  - Immediately bump to next patch version (e.g., 1.0.0 -> 1.0.1)
#           (default) Use current Chart.yaml version
#
# The collector image version will automatically match the Chart.yaml version.
#
# ============================================================================

set -euo pipefail

# Configuration
REGISTRY="ncsa"
IMAGE_NAME="jupyterhub-metrics-collector"
DOCKERFILE_DIR="collector"
VERSION_STRATEGY="${1:-current}"  # 'next' or 'current' (default)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$*${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Project root
PROJECT_ROOT="$SCRIPT_DIR"

# Chart files directory
CHART_FILES_DIR="$SCRIPT_DIR/chart/files"
CHART_YAML="$SCRIPT_DIR/chart/Chart.yaml"

cd "$PROJECT_ROOT"

# Read current Chart version early (we'll use this for the collector image)
CURRENT_VERSION=$(grep "^version:" "$CHART_YAML" | awk '{print $2}')

section "Collector Image Build"
log "Current Chart version: $CURRENT_VERSION"

# Handle version strategy
if [[ "$VERSION_STRATEGY" == "next" ]]; then
    log "Version strategy: next (bumping version before build)"

    # Parse semantic version
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

    # Bump patch version
    PATCH=$((PATCH + 1))
    NEXT_VERSION="${MAJOR}.${MINOR}.${PATCH}"

    log "Bumping Chart version from $CURRENT_VERSION to $NEXT_VERSION"

    # Update Chart.yaml immediately
    sed -i.bak "s/^version: .*/version: $NEXT_VERSION/" "$CHART_YAML"
    rm -f "$CHART_YAML.bak"

    # Use the new version for collector image
    CURRENT_VERSION="$NEXT_VERSION"
    SKIP_VERSION_BUMP_ON_CHANGES=true

    log "Chart.yaml updated to version $NEXT_VERSION"
elif [[ "$VERSION_STRATEGY" == "current" ]]; then
    log "Version strategy: current"
    SKIP_VERSION_BUMP_ON_CHANGES=false
else
    error "Invalid version strategy: $VERSION_STRATEGY. Use 'next' or 'current'"
fi

# ============================================================================
# Build and push collector Docker image
# ============================================================================

section "Building Collector Docker Image"

# Use current Chart version for collector image
COLLECTOR_VERSION="$CURRENT_VERSION"
log "Building collector image with version: $COLLECTOR_VERSION"

# Verify Dockerfile exists
if [[ ! -f "${DOCKERFILE_DIR}/Dockerfile" ]]; then
    error "Dockerfile not found at ${DOCKERFILE_DIR}/Dockerfile"
fi

if [[ ! -f "${DOCKERFILE_DIR}/collector.sh" ]]; then
    error "collector.sh not found at ${DOCKERFILE_DIR}/collector.sh"
fi

log "Building multi-architecture Docker image: ${REGISTRY}/${IMAGE_NAME}:${COLLECTOR_VERSION}"
log "Architectures: linux/amd64 (x86), linux/arm64 (ARM)"

# Check if buildx is available
if ! docker buildx ls >/dev/null 2>&1; then
    warn "docker buildx not found. Attempting single-architecture build only."
    warn "To build multi-arch images, install docker buildx: https://docs.docker.com/build/architecture/"

    # Fall back to single arch build
    if docker build \
        -t "${REGISTRY}/${IMAGE_NAME}:${COLLECTOR_VERSION}" \
        -f "${DOCKERFILE_DIR}/Dockerfile" \
        "${DOCKERFILE_DIR}"; then
        log "Successfully built single-arch image: ${REGISTRY}/${IMAGE_NAME}:${COLLECTOR_VERSION}"
    else
        error "Failed to build Docker image"
    fi
else
    # Multi-arch build using buildx
    BUILD_ARGS="--platform linux/amd64,linux/arm64"

    # Check if we need to create a multi-arch builder (for environments like OrbStack)
    # The docker driver doesn't support multi-platform builds
    BUILDER_FLAG=""
    if ! docker buildx build --platform linux/amd64,linux/arm64 --dry-run -f "${DOCKERFILE_DIR}/Dockerfile" "${DOCKERFILE_DIR}" >/dev/null 2>&1; then
        log "Creating docker-container builder for multi-arch support..."
        docker buildx create --name multiarch --driver docker-container 2>/dev/null || true
        BUILDER_FLAG="--builder multiarch"
        log "Using multiarch builder"
    fi

    # Attempt multi-arch build
    BUILDX_SUCCESS=false

    if [[ "${PUSH_TO_REGISTRY:-true}" == "true" ]]; then
        # Build and push multi-arch image
        if docker buildx build \
            $BUILDER_FLAG \
            $BUILD_ARGS \
            --push \
            -t "${REGISTRY}/${IMAGE_NAME}:${COLLECTOR_VERSION}" \
            -f "${DOCKERFILE_DIR}/Dockerfile" \
            "${DOCKERFILE_DIR}" 2>&1 | tee /tmp/buildx_output.log; then
            log "Successfully built and pushed multi-arch image: ${REGISTRY}/${IMAGE_NAME}:${COLLECTOR_VERSION}"
            log "  - Pushed linux/amd64 (x86)"
            log "  - Pushed linux/arm64 (ARM)"
            BUILDX_SUCCESS=true

            # Also tag as latest if not already latest
            if [[ "${COLLECTOR_VERSION}" != "latest" ]]; then
                log "Tagging as latest..."
                docker buildx build \
                    $BUILDER_FLAG \
                    $BUILD_ARGS \
                    --push \
                    -t "${REGISTRY}/${IMAGE_NAME}:latest" \
                    -f "${DOCKERFILE_DIR}/Dockerfile" \
                    "${DOCKERFILE_DIR}" >/dev/null 2>&1
                log "Also pushed as latest"
            fi
        else
            # Check if error is about multi-platform support (OrbStack, etc.)
            if grep -q "Multi-platform build is not supported" /tmp/buildx_output.log 2>/dev/null; then
                warn "Multi-platform build not supported by current docker driver"
                warn "Detected OrbStack or similar environment - falling back to single-arch build"
                warn "For OrbStack with multi-arch support, enable containerd image store in OrbStack settings"
                BUILDX_SUCCESS=false
            else
                error "Failed to build multi-arch Docker image"
            fi
        fi
    else
        # Build only (no push)
        log "Building multi-arch image without pushing (PUSH_TO_REGISTRY=false)"
        if docker buildx build \
            $BUILD_ARGS \
            --load \
            -t "${REGISTRY}/${IMAGE_NAME}:${COLLECTOR_VERSION}" \
            -f "${DOCKERFILE_DIR}/Dockerfile" \
            "${DOCKERFILE_DIR}"; then
            log "Successfully built multi-arch image (loaded): ${REGISTRY}/${IMAGE_NAME}:${COLLECTOR_VERSION}"
            BUILDX_SUCCESS=true
        else
            warn "Multi-platform build requires push (--load not supported for multi-arch)"
            warn "Will build for current architecture only"
            BUILDX_SUCCESS=false
        fi
    fi

    # Fall back to single-arch build when multi-arch is not supported
    if [[ "$BUILDX_SUCCESS" == "false" ]]; then
        log "Falling back to single-architecture build for current platform..."

        if [[ "${PUSH_TO_REGISTRY:-true}" == "true" ]]; then
            log "Building and pushing image..."

            # Build for current platform only and push (no --platform flag)
            if ! docker buildx build \
                $BUILDER_FLAG \
                --push \
                -t "${REGISTRY}/${IMAGE_NAME}:${COLLECTOR_VERSION}" \
                -f "${DOCKERFILE_DIR}/Dockerfile" \
                "${DOCKERFILE_DIR}"; then
                error "Failed to build image"
            fi
            log "Successfully built and pushed image: ${REGISTRY}/${IMAGE_NAME}:${COLLECTOR_VERSION}"

            # Also tag as latest if not already latest
            if [[ "${COLLECTOR_VERSION}" != "latest" ]]; then
                log "Tagging as latest..."
                docker buildx build \
                    $BUILDER_FLAG \
                    --push \
                    -t "${REGISTRY}/${IMAGE_NAME}:latest" \
                    -f "${DOCKERFILE_DIR}/Dockerfile" \
                    "${DOCKERFILE_DIR}" >/dev/null 2>&1
                log "Also pushed as latest"
            fi
        else
            log "Building image locally..."
            if ! docker buildx build \
                $BUILDER_FLAG \
                --load \
                -t "${REGISTRY}/${IMAGE_NAME}:${COLLECTOR_VERSION}" \
                -f "${DOCKERFILE_DIR}/Dockerfile" \
                "${DOCKERFILE_DIR}"; then
                error "Failed to build image"
            fi
            log "Successfully built image: ${REGISTRY}/${IMAGE_NAME}:${COLLECTOR_VERSION}"
        fi
    fi
fi

# ============================================================================
# Summary
# ============================================================================

section "Update Complete"

echo "Summary:"
echo "  Collector Image: ${REGISTRY}/${IMAGE_NAME}:${COLLECTOR_VERSION}"
echo "  Chart Version: $CURRENT_VERSION"
if [[ "${SKIP_VERSION_BUMP_ON_CHANGES:-false}" == "true" ]]; then
    echo "  Version Strategy: next (bumped)"
else
    echo "  Version Strategy: current"
fi
echo ""

echo "Next steps:"
echo "  1. Review changes: git status"
if [[ "${SKIP_VERSION_BUMP_ON_CHANGES:-false}" == "true" ]]; then
    echo "  2. Commit changes: git add chart/ && git commit -m 'chore: bump chart to v$CURRENT_VERSION'"
    echo "  3. Tag release: git tag v$CURRENT_VERSION"
else
    echo "  2. Update chart/files/ directly for configuration changes"
fi
echo "  3. Deploy: helm install jupyterhub-metrics ./chart \\"
echo "       --set timescaledb.database.password=\$(openssl rand -base64 32) \\"
echo "       --set grafana.adminPassword=\$(openssl rand -base64 32)"
echo ""
