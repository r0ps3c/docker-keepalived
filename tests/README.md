# Test Suite Documentation

Comprehensive testing framework for docker-keepalived with three test suites validating image structure, runtime behavior, and VRRP VIP assignment.

## Test Configuration

Tests use a custom keepalived configuration (`tests/configs/keepalived-test.conf`) that defines a VRRP instance (`VI_1`) targeting virtual IP `192.168.200.1` on interface `eth0`. This configuration allows the container to become MASTER and assign the VIP during integration testing.

## Test Suites

### Structure Tests (`structure.sh`)

Validates Docker image structure without running keepalived. The container entrypoint is overridden so no `NET_ADMIN` capability is required.

**Tests (10 total):**
- keepalived binary exists at `/usr/sbin/keepalived`
- keepalived binary is executable
- keepalived package installed (verified via `apk info`)
- bash installed
- Version extractable and valid semver format
- No APK cache files in `/var/cache/apk`
- Image size < 25 MB
- Base image is Alpine Linux
- No temp files in `/tmp`
- `ip` command available (iproute2 required for VIP management)

**Usage:**
```bash
make test-structure
./tests/structure.sh keepalived:main
```

### Standalone Tests (`standalone.sh`)

Tests container runtime startup and keepalived daemon behavior. Requires `--cap-add NET_ADMIN`. Does NOT test VIP assignment — this suite only verifies the daemon starts and runs correctly.

**Tests (7 total):**
- Container starts and remains stable
- keepalived process is running
- Startup messages present in logs
- No fatal errors in logs
- VRRP instance initialized in logs
- keepalived running with expected flags (`-n` for foreground)
- Container still running after all checks

**Usage:**
```bash
make test-standalone
./tests/standalone.sh keepalived:main
```

### Integration Tests (`integration.sh`)

Full VRRP VIP assignment test. Requires `--cap-add NET_ADMIN`. Waits up to 60 seconds for keepalived to assign VIP `192.168.200.1` on interface `eth0` after becoming MASTER.

**Tests (8 total):**
- Container starts and is running
- Container stability check
- keepalived process running
- No critical errors in logs
- VIP `192.168.200.1` assigned on `eth0` within 60s (core VRRP test)
- VIP confirmed via `ip addr show`
- MASTER state transition confirmed in logs
- Container still running after VIP assignment

**Usage:**
```bash
make test-integration
./tests/integration.sh keepalived:main
```

## Running Tests

### All Tests

```bash
make test-all
```

### Individual Suites

```bash
make test-structure
make test-standalone
make test-integration
```

### Cleanup

```bash
make clean-test
```

## Test Library

Shared test utilities in `tests/lib/common.sh`:

**Logging Functions:**
- `log_info(message)` - Informational messages
- `log_error(message)` - Errors (sets `TEST_FAILED=1`)
- `log_warn(message)` - Warnings (does not fail the suite)
- `log_success(message)` - Success messages

**Container Functions:**
- `cleanup_container(name)` - Safe container removal
- `is_container_running(name)` - Check if container is currently running
- `wait_container_stable(name, seconds)` - Wait for container to be stable

**VRRP Functions:**
- `wait_for_vip(container, interface, vip, max_wait)` - Poll for VIP assignment on a container interface

**Utilities:**
- `print_summary(suite_name)` - Print pass/fail summary and overall result

## Writing New Tests

```bash
#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

IMAGE_NAME="${1:-keepalived:main}"
CONTAINER_NAME="keepalived-test-mytest-$$"

cleanup() {
    cleanup_container "$CONTAINER_NAME"
}

trap cleanup EXIT

# Start container (add --cap-add NET_ADMIN if testing runtime behavior)
docker run -d --name "$CONTAINER_NAME" \
    --cap-add NET_ADMIN \
    -v "$SCRIPT_DIR/configs/keepalived-test.conf:/etc/keepalived/keepalived.conf:ro" \
    "$IMAGE_NAME"

# Run tests
log_info "Test 1: Description"
if [ condition ]; then
    log_success "Test passed"
else
    log_error "Test failed"
fi

# Print summary
print_summary "My Test Suite"
exit $TEST_FAILED
```

### Best Practices

1. **Use unique container names**: Append `$$` (PID) to avoid conflicts
2. **Always cleanup**: Use `trap cleanup EXIT` to ensure removal on exit
3. **Set errexit**: Use `set -e` for early exit on errors
4. **Log clearly**: Use the appropriate log level for each outcome
5. **Test one thing**: Each numbered test should validate a single aspect
6. **Handle timing**: Use `wait_container_stable` or `wait_for_vip` for async operations
7. **POSIX sh only**: Use POSIX sh syntax for Alpine/busybox compatibility — no bashisms

## Capability Requirements

| Suite | NET_ADMIN required | Reason |
|---|---|---|
| Structure | No | Entrypoint is overridden; keepalived never starts |
| Standalone | Yes | keepalived must start to manage network state |
| Integration | Yes | keepalived must assign VIP on a network interface |

Both standalone and integration tests pass `--cap-add NET_ADMIN` when starting the container. This capability is available on standard GitHub Actions `ubuntu-latest` runners.

## Troubleshooting

### Tests Fail Locally

1. **Check Docker daemon**: `docker ps`
2. **Rebuild image**: `make build`
3. **Clean test resources**: `make clean-test`
4. **Check logs**: Add `-x` to the test script shebang for tracing

### VIP Not Assigned

1. **Check NET_ADMIN**: Ensure `--cap-add NET_ADMIN` is passed — keepalived will fail silently without it
2. **Check interface name**: The test config targets `eth0`; verify the container interface matches
3. **Increase timeout**: The integration suite waits 60 seconds by default; increase `VIP_TIMEOUT` if needed
4. **Check logs**: `docker logs <container>` for VRRP state machine output

### Container Exits Immediately

1. **Check configuration**: Verify the mounted `keepalived.conf` is syntactically valid
2. **Check logs**: `docker logs <container>` for fatal errors
3. **Check entrypoint**: keepalived must run with `-n` (foreground) — the image entrypoint includes this flag

## CI/CD Integration

Tests run automatically in GitHub Actions:

```yaml
- name: Run tests
  run: make test-all
```

All three suites must pass for builds to succeed.

## Performance

Typical execution times:
- Structure tests: ~5 seconds
- Standalone tests: ~15 seconds
- Integration tests: ~70 seconds (includes up to 60s VIP wait)
- Total: ~90 seconds
