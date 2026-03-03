# Project Specification: docker-keepalived

## Overview

Minimal Docker image for [keepalived](https://keepalived.org/) VRRP built on Alpine Linux, with automated CI/CD, dependency management, and comprehensive testing.

## Docker Image

### Build

- Base: `alpine:3.23` (pinned for Renovate tracking; digest-pinned by Renovate after first run)
- Packages: `keepalived=2.3.4-r2` (version-pinned for Renovate tracking), `bash` (APK cache cleared after install)
- No additional directories or users created; runs as root (required for NET_ADMIN operations)
- Target image size: < 25 MB

### Runtime

- User: root (required for network interface management via NET_ADMIN)
- Capability required: `NET_ADMIN` (for VRRP VIP assignment)
- Entrypoint: `/usr/sbin/keepalived -l -n`
  - `-l`: log messages to stderr (for Docker log capture)
  - `-n`: run in foreground (no daemon, required for container use)
- Config: mount at `/etc/keepalived/keepalived.conf`

## Testing

Three POSIX sh test suites share a common library (`tests/lib/common.sh`). Test config at `tests/configs/keepalived-test.conf` defines a VRRP instance targeting VIP `192.168.200.1` on `eth0`.

### Structure Tests (`tests/structure.sh`) — 10 tests

Static image inspection (container runs with overridden entrypoint, no NET_ADMIN needed):

- keepalived binary exists at `/usr/sbin/keepalived`
- keepalived binary is executable
- keepalived package installed (verified via `apk info`)
- bash installed at `/bin/bash`
- Version extractable and valid semver format
- No APK cache files in `/var/cache/apk`
- Image size < 25 MB
- Base image is Alpine Linux
- No temp files in `/tmp`
- `ip` command available (iproute2, required for VIP management)

### Standalone Tests (`tests/standalone.sh`) — 7 tests

Single-container runtime startup checks; requires `--cap-add NET_ADMIN`; does NOT test VIP assignment:

- Container starts and stays stable
- keepalived process running
- Startup messages present in logs
- No fatal errors in logs
- VRRP instance initialized in logs
- keepalived running with expected flags (`-n`)
- Container still running after all checks

### Integration Tests (`tests/integration.sh`) — 8 tests

Full VRRP VIP assignment test; requires `--cap-add NET_ADMIN`; waits for VIP `192.168.200.1` on `eth0`:

- Container starts and is running
- Container stability check
- keepalived process running
- No critical errors in logs
- VIP `192.168.200.1` assigned on `eth0` within timeout (60s)
- VIP confirmed via `ip addr show`
- Log shows MASTER state transition
- Container still running after VIP assignment

### Makefile Targets

| Target | Description |
|---|---|
| `build` | Build image as `keepalived:main` (with `--pull`) |
| `test-structure` | Run structure tests |
| `test-standalone` | Run standalone tests |
| `test-integration` | Run integration tests |
| `test-all` | Run all three suites |
| `clean-test` | Remove all `keepalived-test-*` containers, volumes, and networks |
| `version` / `show-version` | Extract keepalived version from built image |

Version extraction: `apk info keepalived 2>/dev/null | grep "^keepalived-" | head -1 | cut -d- -f2 | cut -dr -f1`

## Dependency Management (Renovate)

`renovate.json` configuration:

- Extends `config:recommended`; dependency dashboard disabled; timezone UTC
- Global minimum release age: 2 days; PR labels: `dependencies`; concurrent PR limit: 5; hourly limit: 2
- Vulnerability alerts enabled

| Dependency | Manager/Datasource | Minor/Patch/Digest | Major |
|---|---|---|---|
| Alpine base image | docker | Auto-merge (squash, 2-day wait, tests required, digest-pinned) | Manual review; reviewer: `r0ps3c` |
| GitHub Actions | github-actions | Auto-merge (squash, 2-day wait, pin digests) | Manual review |
| keepalived APK | regex / repology (`alpine_{{major}}_{{minor}}/keepalived`) | Auto-merge (squash, 2-day wait) | Manual review; reviewer: `r0ps3c` |

Custom regex manager tracks keepalived version in `Dockerfile` via a multiline pattern that captures the Alpine version from the `FROM` line and the keepalived version from the `apk add` line. The `lookupNameTemplate` is constructed dynamically (`alpine_{{alpineMajor}}_{{alpineMinor}}/keepalived`), so it stays in sync with the pinned Alpine version automatically when Renovate bumps it. The regex captures only the upstream version (e.g. `2.3.4`), excluding the Alpine revision suffix (`-r2`), so repology version comparisons work correctly.

## CI/CD

### Workflows

- `build-and-tag.yml` — Build, scan, test, and publish
- `check-major-version-bump.yml` — Stable promotion automation

Renovate runs via the [Renovate GitHub App](https://github.com/apps/renovate) (no workflow required).

### Build Triggers

Push or PR to `master`/`stable`; manual dispatch.

### Pipeline Steps

1. Build image (`docker build --pull`)
2. Trivy security scan (CRITICAL/HIGH/MEDIUM; fails build on fixable CRITICAL/HIGH; uploads SARIF to GitHub Security tab)
3. Run all three test suites (structure, standalone, integration — all with `--cap-add NET_ADMIN` where required)
4. Extract keepalived version from built image
5. Apply tags and push to `ghcr.io`

## Branch Strategy and Tagging

### Master Branch Tags

| Tag | Condition |
|---|---|
| `main`, `latest` | Always |
| `<major>.<minor>.<patch>` | Always (immutable) |
| `<major>` | Always |
| `stable` | Only if major version matches current stable |

### Stable Branch Tags

| Tag | Condition |
|---|---|
| `stable` | Always |

### Stable Promotion

After a successful master build, `check-major-version-bump.yml` opens a PR if the keepalived major version on master differs from stable (or stable branch doesn't exist):

- PR: `master` → `stable`, branch `update-stable-v<major>`
- Labels: `stable-promotion`, `major-version-bump`
- Requires manual review and approval

## Permissions

| Workflow | Required Permissions |
|---|---|
| Build | `contents:read`, `packages:write`, `security-events:write` |
| Promotion check | `contents:write`, `pull-requests:write` |
| Renovate | `contents:write`, `pull-requests:write`, `issues:write` |

## Repository Setup

1. GitHub Actions: read/write permissions + allow creating PRs
2. `stable` branch protection: require 1 PR review; require status checks to pass; include administrators
3. Install [Renovate GitHub App](https://github.com/apps/renovate); merge onboarding PR
4. Enable "Allow auto-merge" on the repository for Renovate auto-merge to function
