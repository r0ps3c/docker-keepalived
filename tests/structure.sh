#!/bin/sh
# Structure tests for keepalived Docker image
# Pure POSIX sh - no external dependencies
# Tests: binary existence, packages, base image, image hygiene

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

IMAGE_NAME="${1:-keepalived:main}"
CONTAINER_NAME="keepalived-test-structure-$$"

cleanup() {
    cleanup_container "$CONTAINER_NAME"
}

trap cleanup EXIT

log_info "========================================="
log_info "Structure Tests for $IMAGE_NAME"
log_info "========================================="
echo ""

# Start container for inspection (override entrypoint)
log_info "Starting container for structure inspection..."
docker run -d --name "$CONTAINER_NAME" --entrypoint sleep "$IMAGE_NAME" 3600 >/dev/null 2>&1

# Test 1: keepalived binary exists
log_info "Test 1: keepalived binary exists at /usr/sbin/keepalived"
if docker exec "$CONTAINER_NAME" test -f /usr/sbin/keepalived; then
    log_success "keepalived binary exists"
else
    log_error "keepalived binary not found at /usr/sbin/keepalived"
fi

# Test 2: keepalived binary is executable
log_info "Test 2: keepalived binary is executable"
if docker exec "$CONTAINER_NAME" test -x /usr/sbin/keepalived; then
    log_success "keepalived binary is executable"
else
    log_error "keepalived binary is not executable"
fi

# Test 3: keepalived package installed
log_info "Test 3: keepalived package installed"
if docker exec "$CONTAINER_NAME" apk info keepalived 2>/dev/null | grep -q "^keepalived-"; then
    log_success "keepalived package is installed"
else
    log_error "keepalived package is not installed"
fi

# Test 4: bash is installed (required for tests)
log_info "Test 4: bash is installed"
if docker exec "$CONTAINER_NAME" test -f /bin/bash; then
    log_success "bash is installed"
else
    log_error "bash is not installed"
fi

# Test 5: Version extractable and valid semver format
log_info "Test 5: keepalived version extractable and valid semver format"
VERSION=$(docker exec "$CONTAINER_NAME" sh -c "apk info keepalived 2>/dev/null | grep '^keepalived-' | head -1 | cut -d- -f2 | cut -dr -f1")
if echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'; then
    log_success "Version is extractable and valid: $VERSION"
else
    log_error "Version format invalid or not extractable: '$VERSION'"
fi

# Test 6: No APK cache files left behind
log_info "Test 6: No APK cache files in /var/cache/apk"
CACHE_COUNT=$(docker exec "$CONTAINER_NAME" sh -c 'ls /var/cache/apk 2>/dev/null | wc -l')
if [ "$CACHE_COUNT" = "0" ]; then
    log_success "No APK cache files"
else
    log_warn "Found $CACHE_COUNT items in /var/cache/apk"
fi

# Test 7: Image size is reasonable (< 25MB)
log_info "Test 7: Image size is reasonable (< 25MB)"
IMAGE_SIZE=$(docker inspect "$IMAGE_NAME" --format='{{.Size}}' 2>/dev/null || echo "0")
IMAGE_SIZE_MB=$((IMAGE_SIZE / 1024 / 1024))
if [ "$IMAGE_SIZE_MB" -lt 25 ]; then
    log_success "Image size is ${IMAGE_SIZE_MB}MB (< 25MB)"
else
    log_warn "Image size is ${IMAGE_SIZE_MB}MB (larger than expected)"
fi

# Test 8: Base image is Alpine
log_info "Test 8: Base image is Alpine Linux"
if docker exec "$CONTAINER_NAME" cat /etc/os-release 2>/dev/null | grep -q "Alpine"; then
    log_success "Base image is Alpine Linux"
else
    log_error "Base image is not Alpine Linux"
fi

# Test 9: No temp files in /tmp
log_info "Test 9: No temp files in /tmp"
TMP_COUNT=$(docker exec "$CONTAINER_NAME" sh -c 'ls /tmp 2>/dev/null | wc -l')
if [ "$TMP_COUNT" = "0" ]; then
    log_success "No temp files in /tmp"
else
    log_warn "Found $TMP_COUNT items in /tmp"
fi

# Test 10: iproute2 available (required for VIP management)
log_info "Test 10: ip command available (iproute2)"
if docker exec "$CONTAINER_NAME" which ip >/dev/null 2>&1; then
    log_success "ip command is available"
else
    log_error "ip command not found (iproute2 missing)"
fi

# Print summary and exit
print_summary "Structure Tests"
exit $TEST_FAILED
