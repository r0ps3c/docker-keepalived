# Automated Updates & Testing Design

**Date:** 2026-03-02
**Status:** Approved

## Overview

Port the managed automated update and testing system from `docker-unbound` to `docker-keepalived`, adapting it for keepalived's VRRP-specific requirements.

---

## Section 1: Branch Model & Release Strategy

The current `master` branch stays as the primary integration branch. A new `stable` branch is created from current HEAD as a one-time setup step.

**Branch roles:**
- `master` — continuous updates flow here via Renovate PRs; every push builds, tests, and publishes versioned image tags
- `stable` — the "production" branch; only receives changes via a reviewed PR triggered automatically when a keepalived major version bump is detected

**Image tags per branch:**

| Branch | Tags applied |
|---|---|
| `master` | `main`, `latest`, `<full-version>` (e.g. `2.3.1`), `<major>` (e.g. `2`), `stable` if major matches existing stable |
| `stable` | `stable` |

**Retired:** the existing `v*` git-tag release mechanism (`package.yml`) is removed entirely. Version identity is derived from the keepalived package inside the image, not git tags.

**Version extraction command:**
```sh
apk info keepalived 2>/dev/null | grep "^keepalived-" | head -1 | cut -d- -f2 | cut -dr -f1
```
Extracts `2.3.1` from `keepalived-2.3.1-r0`.

---

## Section 2: Dependency Management

Dependabot is removed and replaced with Renovate. Three dependency types tracked:

| Dependency | Manager | Minor/Patch | Major |
|---|---|---|---|
| Alpine base image | docker | Auto-merge after 2-day stabilization + tests pass | Manual review (reviewer: r0ps3c) |
| keepalived APK | regex + repology | Auto-merge after 2-day stabilization + tests pass | Manual review (reviewer: r0ps3c) |
| GitHub Actions | github-actions | Auto-merge after 2-day stabilization, pin digests | Manual review |

### Dockerfile version pinning

```dockerfile
FROM alpine:3.23

RUN \
    apk --no-cache add keepalived=<current-version>-r0 bash && \
    rm -rf /var/cache/apk/*

ENTRYPOINT ["/usr/sbin/keepalived", "-l", "-n"]
```

- Alpine pinned with version tag (required for Renovate Docker manager)
- keepalived pinned with explicit version (required for Renovate regex manager currentValue capture)
- bash stays unpinned (test dependency only)
- After initial Renovate setup, Alpine will also be pinned to a digest

### Renovate custom regex manager

Multiline regex captures Alpine major/minor from the `FROM` line, enabling a dynamic repology lookup that self-updates when Alpine is bumped:

```
FROM alpine:(?<alpineMajor>[0-9]+)\.(?<alpineMinor>[0-9]+)[\s\S]*?apk[^\n]*keepalived=(?<currentValue>[0-9][0-9.]*)-r[0-9]+
```

- `lookupNameTemplate`: `alpine_{{alpineMajor}}_{{alpineMinor}}/keepalived`
- `currentValue` captures upstream version only (e.g. `2.3.1`), stripping the `-r0` suffix for correct repology comparison

### Alpine digest pinning

`pinDigests: true` + `"digest"` in `matchUpdateTypes` for the Alpine rule. The Dockerfile will be pinned to `FROM alpine:3.23@sha256:<digest>`. Alpine security rebuilds (same tag, new digest) trigger a Renovate PR explicitly rather than being silently missed.

---

## Section 3: CI/CD Workflows

### build-and-tag.yml (replaces build.yml + package.yml)

**Triggers:** push/PR to `master` or `stable`, manual dispatch

**Steps:**
1. Checkout
2. Build image (`make build`) — local tag `keepalived:main`
3. Trivy security scan — SARIF upload to GitHub Security tab; fail on fixable CRITICAL/HIGH
4. Trivy table summary (CRITICAL/HIGH/MEDIUM, non-failing)
5. `make test-structure`
6. `make test-standalone`
7. `make test-integration`
8. Extract keepalived version from built image
9. Log in to ghcr.io (non-PR only)
10. Check stable tag compatibility — compare major version of built image vs existing `stable` image
11. Apply image tags via `docker/metadata-action`
12. Build and push to ghcr.io (non-PR only, with GHA cache)
13. Generate step summary

**Permissions:** `contents: read`, `packages: write`, `security-events: write`

### check-major-version-bump.yml (new)

**Trigger:** `workflow_run` on `build-and-tag` completing successfully on `master`

**Logic:**
1. Pull `ghcr.io/<repo>:main` → extract keepalived major version
2. Pull `ghcr.io/<repo>:stable` → extract keepalived major version (if exists)
3. If major versions differ (or no stable exists): create PR from `update-stable-v<major>` → `stable`
4. PR body includes testing checklist; labels: `stable-promotion`, `major-version-bump`
5. If major versions match: no PR, stable tag handled by build-and-tag

---

## Section 4: Makefile

```makefile
PKGNAME:=keepalived
TAG:=main
DOCKERFILE:=Dockerfile

.PHONY: build test-structure test-standalone test-integration test-all clean-test version show-version

build:
    docker build --pull -t $(PKGNAME):$(TAG) -f $(DOCKERFILE) .

test-structure: build
    ./tests/structure.sh $(PKGNAME):$(TAG)

test-standalone: build
    ./tests/standalone.sh $(PKGNAME):$(TAG)

test-integration: build
    ./tests/integration.sh $(PKGNAME):$(TAG)

test-all: test-structure test-standalone test-integration

clean-test:
    docker rm -f keepalived-test-* 2>/dev/null || true
    docker volume rm -f keepalived-test-* 2>/dev/null || true
    docker network rm keepalived-test-* 2>/dev/null || true

version: build
    @docker run --rm --entrypoint sh $(PKGNAME):$(TAG) -c 'apk info keepalived 2>/dev/null | grep "^keepalived-" | head -1 | cut -d- -f2 | cut -dr -f1'

show-version: build
    @FULL_VER=$$(docker run --rm --entrypoint sh $(PKGNAME):$(TAG) -c 'apk info keepalived 2>/dev/null | grep "^keepalived-" | head -1 | cut -d- -f2 | cut -dr -f1'); \
    MAJOR_VER=$$(echo $$FULL_VER | cut -d. -f1); \
    echo "Full version: $$FULL_VER"; \
    echo "Major version: $$MAJOR_VER"
```

---

## Section 5: Test Suite

### Structure

```
tests/
├── lib/
│   └── common.sh              # shared logging, container management
├── structure.sh               # static image inspection (~10 tests)
├── standalone.sh              # single container runtime (~8 tests)
├── integration.sh             # VRRP VIP assignment, promoted from test.sh (~8 tests)
├── configs/
│   └── keepalived-test.conf   # moved from tests/keepalived.conf
└── README.md
```

### tests/lib/common.sh

Same utilities as docker-unbound but without DNS-specific helpers: logging functions, container cleanup, `is_container_running`, `wait_container_stable`, `print_summary`.

### tests/structure.sh (~10 tests)

Static image inspection — runs with `sleep` entrypoint, no NET_ADMIN required:

1. keepalived binary exists at `/usr/sbin/keepalived`
2. keepalived binary is executable
3. bash is installed
4. keepalived package installed (`apk info keepalived`)
5. Version extractable and valid semver
6. No APK cache files in `/var/cache/apk`
7. Image size reasonable (< 25MB)
8. Base image is Alpine
9. No temp files in `/tmp`
10. No unexpected setuid binaries

### tests/standalone.sh (~8 tests)

Single container, with NET_ADMIN + test config, checks startup without waiting for VIP:

1. Container starts with `--cap-add NET_ADMIN`
2. Container stability (stays running after 10s)
3. keepalived process is running
4. Startup messages present in logs (VRRP initialization)
5. No critical errors in logs (`fatal`, `error:`)
6. keepalived running with correct flags (`-l -n`)
7. Container still running after all checks
8. Log shows VRRP instance configured

### tests/integration.sh (~8 tests)

Single container with NET_ADMIN + test config, promoted from `tests/test.sh` — verifies full VRRP VIP assignment:

1. Container starts with `--cap-add NET_ADMIN`
2. Container stability
3. keepalived process running
4. No critical errors in logs
5. VIP (192.168.200.1) assigned on `eth0` within 60s timeout
6. VIP confirmed via `ip addr show eth0`
7. Log shows MASTER state transition
8. Container still running after VIP assignment

### tests/configs/keepalived-test.conf

Moved from `tests/keepalived.conf` unchanged — existing VRRP config is appropriate for integration testing.

---

## Section 6: Documentation

- `README.md` — quick start, features, tagging strategy, configuration, testing commands
- `spec.md` — full specification of image, CI/CD, testing, branch strategy
- `tests/README.md` — test structure, how to run, how to write new tests
- `DEPENDENCIES.md` — setup prerequisites (Renovate app, GitHub Actions permissions, branch protection)

---

## Section 7: File Change Summary

### Add
- `renovate.json`
- `.github/workflows/build-and-tag.yml`
- `.github/workflows/check-major-version-bump.yml`
- `Makefile`
- `tests/lib/common.sh`
- `tests/structure.sh`
- `tests/standalone.sh`
- `tests/integration.sh`
- `tests/configs/keepalived-test.conf`
- `tests/README.md`
- `README.md`
- `spec.md`
- `DEPENDENCIES.md`
- `.dockerignore`
- `docs/plans/2026-03-02-automated-updates-design.md` (this file)

### Modify
- `Dockerfile` — pin Alpine version and keepalived version

### Remove
- `.github/dependabot.yml`
- `.github/workflows/build.yml`
- `.github/workflows/package.yml`
- `tests/test.sh` (content promoted to `tests/integration.sh`)
- `tests/keepalived.conf` (moved to `tests/configs/keepalived-test.conf`)
