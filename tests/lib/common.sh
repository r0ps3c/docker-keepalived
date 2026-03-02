#!/bin/sh
# Common test utilities for docker-keepalived
# POSIX sh compatible (Alpine busybox)
# No color codes - CI/CD friendly output

# Global test status flag
TEST_FAILED=0

# Logging functions
log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*"
    TEST_FAILED=1
}

log_warn() {
    echo "[WARN] $*"
}

log_success() {
    echo "[OK] $*"
}

# Container cleanup function
cleanup_container() {
    local container_name="$1"
    if [ -n "$container_name" ]; then
        log_info "Cleaning up container: $container_name"
        docker rm -f "$container_name" 2>/dev/null || true
    fi
}

# Check if container is running
is_container_running() {
    local container_name="$1"
    docker ps --format '{{.Names}}' | grep -q "^${container_name}$"
}

# Wait for container to be stable (not restarting)
wait_container_stable() {
    local container_name="$1"
    local wait_seconds="${2:-10}"

    log_info "Waiting ${wait_seconds}s for container stability..."
    sleep "$wait_seconds"

    if is_container_running "$container_name"; then
        return 0
    else
        return 1
    fi
}

# Wait for a VIP to appear on a network interface inside a container
wait_for_vip() {
    local container_name="$1"
    local interface="$2"
    local vip="$3"
    local max_wait="${4:-60}"

    log_info "Waiting for VIP $vip on $interface (max ${max_wait}s)..."

    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if docker exec "$container_name" ip -o addr show dev "$interface" scope global to "$vip" 2>/dev/null | grep -q "$vip"; then
            log_info "VIP $vip is assigned"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    log_info "VIP $vip not assigned after ${max_wait}s"
    return 1
}

# Print test summary
print_summary() {
    local test_suite_name="$1"
    echo ""
    echo "========================================="
    echo "$test_suite_name Summary"
    echo "========================================="
    if [ "$TEST_FAILED" -eq 0 ]; then
        log_success "All tests passed"
    else
        log_error "Some tests failed"
    fi
    echo ""
}
