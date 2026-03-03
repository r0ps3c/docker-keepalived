#!/bin/sh
# Standalone runtime tests for keepalived container
# Verifies daemon startup without testing VRRP VIP assignment

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

IMAGE_NAME="${1:-keepalived:main}"
CONTAINER_NAME="keepalived-test-standalone-$$"

cleanup() {
    cleanup_container "$CONTAINER_NAME"
}

trap cleanup EXIT

log_info "========================================="
log_info "Standalone Tests for $IMAGE_NAME"
log_info "========================================="
echo ""

# Start container with test config and required capabilities
log_info "Starting keepalived container in standalone mode..."
if docker run -d --name "$CONTAINER_NAME" \
    --cap-add NET_ADMIN \
    -v "$SCRIPT_DIR/configs/keepalived-test.conf:/etc/keepalived/keepalived.conf:ro" \
    "$IMAGE_NAME"; then
    log_success "Container started successfully"
else
    log_error "Container failed to start"
    exit 1
fi

# Test 1: Container stays running (stability check)
log_info "Test 1: Container stability check"
if wait_container_stable "$CONTAINER_NAME" 10; then
    log_success "Container is stable and running"
else
    log_error "Container is not stable (crashed on startup)"
    docker logs "$CONTAINER_NAME" 2>&1 | tail -20
fi

# Test 2: keepalived process is running
log_info "Test 2: keepalived process is running"
if docker exec "$CONTAINER_NAME" sh -c 'ps aux | grep -v grep | grep -q keepalived'; then
    log_success "keepalived process is running"
else
    log_error "keepalived process not found"
    docker exec "$CONTAINER_NAME" ps aux || true
fi

# Test 3: Startup messages present in logs
log_info "Test 3: Startup messages present in logs"
if docker logs "$CONTAINER_NAME" 2>&1 | grep -qiE "Starting|VRRP|vrrp_instance|Entering|Opening"; then
    log_success "Startup messages detected in logs"
else
    log_warn "Could not confirm startup from logs"
    docker logs "$CONTAINER_NAME" 2>&1 | head -20
fi

# Test 4: No fatal errors in logs
log_info "Test 4: No fatal errors in logs"
if docker logs "$CONTAINER_NAME" 2>&1 | grep -qiE "FATAL|Aborting|Cannot open|permission denied"; then
    log_error "Fatal errors found in logs"
    docker logs "$CONTAINER_NAME" 2>&1 | grep -iE "FATAL|Abort|Cannot|permission" | head -10
else
    log_success "No fatal errors in logs"
fi

# Test 5: VRRP instance configured
log_info "Test 5: VRRP instance initialized in logs"
if docker logs "$CONTAINER_NAME" 2>&1 | grep -qiE "VI_1|vrrp_instance|VRRP_Instance"; then
    log_success "VRRP instance VI_1 initialized"
else
    log_warn "VRRP instance not confirmed in logs (may still be initializing)"
    docker logs "$CONTAINER_NAME" 2>&1 | head -30
fi

# Test 6: keepalived running with correct flags
log_info "Test 6: keepalived running with expected flags"
if docker exec "$CONTAINER_NAME" sh -c 'ps aux | grep -v grep | grep keepalived | grep -q "\-n"'; then
    log_success "keepalived running with -n flag (no-daemon)"
else
    log_warn "keepalived flags may differ from expected"
    docker exec "$CONTAINER_NAME" sh -c 'ps aux | grep keepalived | grep -v grep' || true
fi

# Test 7: Container still running after all checks
log_info "Test 7: Container still running after all tests"
if is_container_running "$CONTAINER_NAME"; then
    log_success "Container still running"
else
    log_error "Container stopped during tests"
    docker logs "$CONTAINER_NAME" 2>&1 | tail -20
fi

# Print summary and exit
print_summary "Standalone Tests"
exit $TEST_FAILED
