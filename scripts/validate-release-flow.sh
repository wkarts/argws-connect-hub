#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { echo "HUB release-flow validation: $*" >&2; exit 1; }

[[ ! -e docker/base/VERSION ]] || fail "obsolete docker/base/VERSION detected"
[[ -x scripts/resolve-hub-base-refs.sh ]] || fail "missing content-addressed base resolver"
[[ -x scripts/cleanup-github-storage.sh ]] || fail "missing GitHub storage cleanup"
[[ -f .github/scripts/compute-next-version.mjs ]] || fail "missing automatic semantic version planner"
[[ ! -e .github/scripts/apply-version.mjs ]] || fail "release must not mutate source version files on main"
[[ -f .github/workflows/publish_hub_amd64.yml ]] || fail "missing develop publisher"
[[ -f .github/workflows/publish_main_amd64.yml ]] || fail "missing main semantic release publisher"
[[ -f .github/workflows/main-release-pr-policy.yml ]] || fail "missing main release PR policy"

if grep -RInE --include='*.yml' --include='*.yaml' 'git push origin HEAD:(main|develop)' .github/workflows 2>/dev/null; then
  fail "release workflow must not create version commits on main/develop"
fi

grep -Fq 'branches: [develop]' .github/workflows/publish_hub_amd64.yml || fail "develop publisher must be bound to develop"
grep -Fq 'ghcr.io/${{ github.repository_owner }}/argws-connect-hub:develop' .github/workflows/publish_hub_amd64.yml || fail "develop package must remain argws-connect-hub"

grep -Fq 'branches: [main]' .github/workflows/publish_main_amd64.yml || fail "main publisher must be bound to main"
grep -Fq 'contents: write' .github/workflows/publish_main_amd64.yml || fail "main release needs contents: write"
grep -Fq 'packages: write' .github/workflows/publish_main_amd64.yml || fail "main release needs packages: write"
grep -Fq 'head.ref == "develop"' .github/workflows/publish_main_amd64.yml || fail "main release must require develop -> main"
grep -Fq 'compute-next-version.mjs' .github/workflows/publish_main_amd64.yml || fail "main release must compute SemVer automatically"
grep -Fq 'options: [auto, patch, minor, major]' .github/workflows/publish_main_amd64.yml || fail "release must support auto/patch/minor/major"
grep -Fq 'image="ghcr.io/${{ github.repository_owner }}/argws-connect-hub"' .github/workflows/publish_main_amd64.yml || fail "canonical release package must be argws-connect-hub"
grep -Fq 'echo "${image}:${VERSION}"' .github/workflows/publish_main_amd64.yml || fail "release must publish X.Y.Z"
grep -Fq 'echo "${image}:${MAJOR}.${MINOR}"' .github/workflows/publish_main_amd64.yml || fail "release must publish X.Y"
grep -Fq 'echo "${image}:${MAJOR}"' .github/workflows/publish_main_amd64.yml || fail "release must publish X"
grep -Fq 'echo "${image}:latest"' .github/workflows/publish_main_amd64.yml || fail "release must publish latest"
grep -Fq 'echo "${image}:main"' .github/workflows/publish_main_amd64.yml || fail "release must publish main"
grep -Fq 'echo "${image}:main-${short_sha}"' .github/workflows/publish_main_amd64.yml || fail "release must publish main-<sha>"
grep -Fq 'echo "${image}:sha-${GITHUB_SHA}"' .github/workflows/publish_main_amd64.yml || fail "release must publish sha-<sha>"
grep -Fq 'git tag -a "$TAG"' .github/workflows/publish_main_amd64.yml || fail "release must create semantic Git tag"
grep -Fq 'gh release create "$TAG"' .github/workflows/publish_main_amd64.yml || fail "release must create GitHub Release"
grep -Fq 'Canonical GHCR package locked to' .github/workflows/publish_main_amd64.yml || fail "canonical package guard missing"
if grep -Fq 'ghcr.io/${{ github.repository_owner }}/mains' .github/workflows/publish_main_amd64.yml; then fail "invalid GHCR package mains detected"; fi

grep -Fq 'GHCR_PACKAGE: argws-connect-hub' .github/workflows/publish_main_amd64.yml || fail "cleanup must target argws-connect-hub"
grep -Fq 'cleanup-github-storage.sh all' .github/workflows/publish_main_amd64.yml || fail "main cleanup missing"
grep -Fq 'PACKAGE" != "argws-connect-hub"' scripts/cleanup-github-storage.sh || fail "cleanup guard must refuse other packages"
grep -Fq 'Content-Addressed Base Images' .github/workflows/hub-base-images.yml || fail "base images must remain content-addressed"

if command -v node >/dev/null 2>&1; then
  node ./scripts/test-release-versioning.mjs
fi

echo "HUB release-flow validation: auto/patch/minor/major SemVer restored; canonical package=argws-connect-hub; tags=X.Y.Z/X.Y/X/latest/main/main-<sha>/sha-<sha>; same-SHA reruns are idempotent"
