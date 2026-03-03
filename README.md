# docker-keepalived

[![Build and Tag](https://github.com/r0ps3c/docker-keepalived/actions/workflows/build-and-tag.yml/badge.svg)](https://github.com/r0ps3c/docker-keepalived/actions/workflows/build-and-tag.yml)

Minimal Alpine-based Docker image for [keepalived](https://keepalived.org/) (VRRP).

## Features

- **Minimal footprint**: Alpine-based image (~15MB)
- **VRRP support**: Assigns virtual IPs (VIPs) via VRRP as MASTER node
- **Security scanning**: Automated Trivy vulnerability scanning
- **Auto-updates**: Renovate dependency management with 2-day stabilization period
- **Comprehensive testing**: Structure, standalone, and integration test suites (25 tests)
- **Multi-tag strategy**: Flexible image versioning
- **Automated workflows**: CI/CD with GitHub Actions

## Quick Start

```bash
# Run keepalived with a custom configuration
docker run -d \
  --name keepalived \
  --cap-add NET_ADMIN \
  -v /path/to/keepalived.conf:/etc/keepalived/keepalived.conf:ro \
  ghcr.io/r0ps3c/docker-keepalived:stable
```

**Note**: `--cap-add NET_ADMIN` is required for keepalived to assign virtual IP addresses via VRRP.

## Image Tags

- **`main`** - Latest build from master branch (same as `latest`)
- **`latest`** - Latest build from master branch (same as `main`)
- **`stable`** - Production-ready stable release; updated automatically for minor/patch versions; requires PR approval for major versions
- **`<major>.<minor>.<patch>`** (full version) - Immutable version tag (e.g. `2.3.4`)
- **`<major>`** (major version) - Latest within major version (e.g. `2`)

## Configuration

keepalived is configured via `/etc/keepalived/keepalived.conf`. Mount your configuration file at this path:

```bash
docker run -d \
  --name keepalived \
  --cap-add NET_ADMIN \
  -v /path/to/keepalived.conf:/etc/keepalived/keepalived.conf:ro \
  ghcr.io/r0ps3c/docker-keepalived:stable
```

**Minimal VRRP configuration example:**
```
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    virtual_ipaddress {
        192.168.1.100
    }
}
```

See the [upstream keepalived documentation](https://keepalived.readthedocs.io/en/latest/configuration_synopsis.html) for the full configuration reference.

## Runtime Requirements

- **`--cap-add NET_ADMIN`**: Required for VRRP VIP assignment (adding/removing IP addresses on network interfaces)
- A valid `keepalived.conf` mounted at `/etc/keepalived/keepalived.conf`

## Testing

The image includes comprehensive test suites:

```bash
# Run all tests
make test-all

# Run individual test suites
make test-structure    # Image structure validation (no NET_ADMIN needed)
make test-standalone   # Runtime startup checks (requires NET_ADMIN)
make test-integration  # VRRP VIP assignment test (requires NET_ADMIN)
```

See [tests/README.md](tests/README.md) for detailed testing documentation.

## Development

### Building Locally

```bash
# Build image
make build

# Extract version
make show-version

# Clean test resources
make clean-test
```

### Prerequisites

See [DEPENDENCIES.md](DEPENDENCIES.md) for setup requirements.

## License

MIT License - see [LICENSE](LICENSE)
