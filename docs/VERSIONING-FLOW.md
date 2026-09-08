# HUB — Branching, versioning and release flow

This repository follows the same release model used by Connect|API, adapted to HUB and kept AMD64-only.

## Branches

### `develop`

Integration and development branch.

- feature/fix branches should target `develop`.
- every push to `develop` runs the development image workflow.
- only the development channel is published:
  - `ghcr.io/wkarts/argws-connect-hub:develop`
  - `ghcr.io/wkarts/argws-connect-hub:sha-<commit>`
- `develop` never publishes `latest` and never creates a Git tag/release.

### `main`

Stable release branch.

- changes should reach `main` through a PR from `develop`.
- a successful push/merge to `main` runs the automatic release workflow.
- `main` validates the source, calculates the next SemVer, writes the version metadata, publishes the stable image, creates an immutable `vX.Y.Z` tag and creates a GitHub Release.

## Semantic version rules

The canonical format is:

```text
X.Y.Z
```

The HUB version line is independent and starts at `1.0.0`.

Automatic bump rules:

- label `version:major` -> major
- label `version:minor` -> minor
- label `version:patch` -> patch
- PR title with a breaking marker (`feat!:` / `fix!:` / `BREAKING CHANGE`) -> major
- PR title beginning with `feat:` or `feat(scope):` -> minor
- any other merge -> patch

Examples:

```text
fix(email): preserve IMAP flags
=> patch

feat(inbox): add new routing mode
=> minor

feat(api)!: change public conversation contract
=> major
```

A manual release can override the bump using the `force_bump` input of the release workflow.

## Stable GHCR tags

A stable `1.4.2` release publishes:

```text
ghcr.io/wkarts/argws-connect-hub:1.4.2
ghcr.io/wkarts/argws-connect-hub:1.4
ghcr.io/wkarts/argws-connect-hub:1
ghcr.io/wkarts/argws-connect-hub:latest
ghcr.io/wkarts/argws-connect-hub:sha-<release-commit>
```

All HUB images are `linux/amd64`.

## Version sources

The release workflow keeps these files synchronized:

```text
VERSION
package.json
RELEASE-MANIFEST.json
```

`VERSION` is the canonical human-readable application version.

## Recommended PR flow

```text
feature/* or fix/*
        ↓
     develop
        ↓
 PR develop → main
        ↓
 automated validation
        ↓
 automatic SemVer
        ↓
 GHCR stable image
        ↓
 vX.Y.Z
        ↓
 GitHub Release
```

After a release, synchronize `main` back into `develop` before starting work that depends on the generated release-version commit.

## Deployment channels

Development/test environment:

```env
HUB_IMAGE=ghcr.io/wkarts/argws-connect-hub:develop
```

Production environment:

```env
HUB_IMAGE=ghcr.io/wkarts/argws-connect-hub:latest
```

For an immutable production deployment, pin the exact version:

```env
HUB_IMAGE=ghcr.io/wkarts/argws-connect-hub:1.0.0
```

## Privacy and product audit

Both PR validation and release build run:

```bash
./scripts/audit-hub.sh
```

A release must not bypass the HUB privacy/product audit.
