# Dependencies and Setup

This document describes the setup requirements for building and testing the docker-keepalived image.

## Required Tools

- **Docker** 20.10+
- **Make** (GNU Make 4.0+)
- **Git** 2.0+

## Quick Start

```bash
# Build image
make build

# Run tests
make test-all
```

## GitHub Actions Setup

### Repository Permissions

Enable in repository settings:

1. **Actions** → Allow GitHub Actions
2. **Actions** → Workflow permissions → Read and write permissions
3. **Actions** → Allow GitHub Actions to create pull requests

### Required Workflow Permissions

| Workflow | Permissions needed |
|---|---|
| `build-and-tag.yml` | `packages:write`, `security-events:write` |
| `check-major-version-bump.yml` | `contents:write`, `pull-requests:write` |
| Renovate App | `contents:write`, `pull-requests:write`, `issues:write` |

### Branch Protection (Recommended)

For the `stable` branch:

- Require pull request reviews (1 approver)
- Require status checks to pass before merging
- Include administrators

This ensures major version promotions to stable receive a mandatory review before merging.

### Required GitHub Labels

Create the following labels in **repository settings → Labels**:

| Label | Used by |
|---|---|
| `stable-promotion` | `check-major-version-bump.yml` (PRs promoting master to stable) |
| `major-version-bump` | `check-major-version-bump.yml` (signals a breaking major version change) |
| `dependencies` | Renovate (all dependency update PRs) |

## Renovate Setup

[Renovate](https://docs.renovatebot.com/) manages dependencies with a 2-day stabilization period.

**Manages:**
- Alpine base image (`alpine:3.23`)
- keepalived APK package (`keepalived=2.3.4-r2`)
- GitHub Actions

**Setup:**

1. Install the [Renovate GitHub App](https://github.com/apps/renovate) on your repository from the GitHub Marketplace
2. Repository Settings → Actions → General
   - Workflow permissions: "Read and write permissions"
   - Enable "Allow GitHub Actions to create and approve pull requests"
3. Repository Settings → General → Pull Requests
   - Enable "Allow auto-merge" (required for Renovate auto-merge to function)
4. Merge the onboarding PR that Renovate creates automatically

**Auto-merge Behavior:**

- Minor/patch updates: Auto-merge after 2 days + tests pass
- Major updates: Manual review required (reviewer assigned to `r0ps3c`)

See `renovate.json` for the full configuration.

## Security Scanning

Trivy scans run automatically in `build-and-tag.yml`:

- On push to master and stable branches
- On pull requests
- Results uploaded to GitHub Security tab as SARIF

Fails the build on fixable CRITICAL or HIGH vulnerabilities.

## NET_ADMIN in CI

The standalone and integration test suites require `--cap-add NET_ADMIN` so keepalived can assign virtual IP addresses on network interfaces inside the container. This capability is available on standard GitHub Actions `ubuntu-latest` runners — no special runner configuration is needed.

Structure tests do not require NET_ADMIN because the container entrypoint is overridden and keepalived never starts.

## Troubleshooting

**Build fails — "Cannot connect to Docker daemon"**
- Check Docker service is running
- Add user to docker group: `sudo usermod -aG docker $USER`

**Tests fail — "Container is not stable"**
- Rebuild the image: `make build`
- Check logs: `docker logs <container-name>`
- Ensure the test config at `tests/configs/keepalived-test.conf` is valid

**Integration tests fail — VIP not assigned**
- Verify `--cap-add NET_ADMIN` is being passed (the Makefile includes this automatically)
- Check that the container interface is `eth0` (Docker default for bridge-attached containers)
- Increase `VIP_TIMEOUT` in `tests/integration.sh` if the environment is slow

## Platform Support

- **Linux**: Native Docker (recommended; NET_ADMIN works as expected)
- **macOS**: Docker Desktop (NET_ADMIN available within the Linux VM)
- **Windows**: Docker Desktop with WSL2

## Support

For issues:
1. Check troubleshooting above
2. Review [test documentation](tests/README.md)
3. Open an issue on GitHub
