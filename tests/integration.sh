#!/bin/sh
# Integration tests for keepalived VRRP VIP assignment
# Verifies keepalived assigns the virtual IP as MASTER

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

IMAGE_NAME="${1:-keepalived:main}"
CONTAINER_NAME="keepalived-test-integration-$$"

# Test configuration
TEST_VIP="192.168.200.1"
TEST_IFACE="eth0"
VIP_TIMEOUT=60

cleanup() {
    cleanup_container "$CONTAINER_NAME"
}

trap cleanup EXIT

log_info "========================================="
log_info "Integration Tests for $IMAGE_NAME"
log_info "========================================="
echo ""

# Start container with test config and required capabilities
log_info "Starting keepalived container for integration test..."
if docker run -d --name "$CONTAINER_NAME" \
    --cap-add NET_ADMIN \
    -v "$SCRIPT_DIR/configs/keepalived-test.conf:/etc/keepalived/keepalived.conf:ro" \
    "$IMAGE_NAME"; then
    log_success "Container started successfully"
else
    log_error "Container failed to start"
    exit 1
fi

# Test 1: Container starts and is running
log_info "Test 1: Container starts and is running"
sleep 3
if is_container_running "$CONTAINER_NAME"; then
    log_success "Container is running"
else
    log_error "Container is not running after start"
    docker logs "$CONTAINER_NAME" 2>&1 | tail -20
    exit 1
fi

# Test 2: Container stability check
log_info "Test 2: Container stability check"
if wait_container_stable "$CONTAINER_NAME" 5; then
    log_success "Container is stable"
else
    log_error "Container is not stable"
fi

# Test 3: keepalived process is running
log_info "Test 3: keepalived process is running"
if docker exec "$CONTAINER_NAME" sh -c 'ps aux | grep -v grep | grep -q keepalived'; then
    log_success "keepalived process is running"
else
    log_error "keepalived process not found"
    docker exec "$CONTAINER_NAME" ps aux || true
fi

# Test 4: No critical errors in logs
log_info "Test 4: No critical errors in logs"
if docker logs "$CONTAINER_NAME" 2>&1 | grep -qiE "FATAL|Aborting|Cannot open"; then
    log_error "Critical errors found in logs"
    docker logs "$CONTAINER_NAME" 2>&1 | grep -iE "FATAL|Abort|Cannot" | head -10
else
    log_success "No critical errors in logs"
fi

# Test 5: VIP assigned within timeout (core VRRP test)
log_info "Test 5: VIP $TEST_VIP assigned on $TEST_IFACE within ${VIP_TIMEOUT}s"
if wait_for_vip "$CONTAINER_NAME" "$TEST_IFACE" "$TEST_VIP" "$VIP_TIMEOUT"; then
    log_success "VIP $TEST_VIP successfully assigned"
else
    log_error "VIP $TEST_VIP was not assigned within ${VIP_TIMEOUT}s"
    docker logs "$CONTAINER_NAME" 2>&1 | tail -30
fi

# Test 6: VIP confirmed via ip addr show
log_info "Test 6: VIP confirmed via ip addr"
if docker exec "$CONTAINER_NAME" ip -o addr show dev "$TEST_IFACE" scope global to "$TEST_VIP" 2>/dev/null | grep -q "$TEST_VIP"; then
    log_success "VIP $TEST_VIP confirmed on $TEST_IFACE"
else
    log_error "VIP $TEST_VIP not found on $TEST_IFACE"
    docker exec "$CONTAINER_NAME" ip addr show dev "$TEST_IFACE" 2>/dev/null || true
fi

# Test 7: Log shows MASTER state
log_info "Test 7: Log shows MASTER state transition"
if docker logs "$CONTAINER_NAME" 2>&1 | grep -qiE "MASTER|Entering MASTER|transition.*MASTER"; then
    log_success "MASTER state confirmed in logs"
else
    log_warn "MASTER state not found in logs (may use different log format)"
    docker logs "$CONTAINER_NAME" 2>&1 | grep -iE "state|vrrp" | head -10 || true
fi

# Test 8: Container still running after VIP assignment
log_info "Test 8: Container still running after VIP assignment"
if is_container_running "$CONTAINER_NAME"; then
    log_success "Container still running"
else
    log_error "Container stopped after VIP assignment"
    docker logs "$CONTAINER_NAME" 2>&1 | tail -20
fi

# Print summary and exit
print_summary "Integration Tests"
exit $TEST_FAILED
