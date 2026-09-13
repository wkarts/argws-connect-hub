#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "HUB release-flow validation: $*" >&2
  exit 1
}

for obsolete in \
  .github/scripts/compute-next-version.mjs \
  .github/scripts/apply-version.mjs; do
  [[ ! -e "$obsolete" ]] || fail "obsolete automatic version mutation artifact detected: $obsolete"
done

[[ ! -e docker/base/VERSION ]] \
  || fail "obsolete docker/base/VERSION detected; base identities must be content-addressed"
[[ -x scripts/resolve-hub-base-refs.sh ]] \
  || fail "missing content-addressed base identity resolver"
[[ -x scripts/cleanup-github-storage.sh ]] \
  || fail "missing GitHub storage retention cleanup"

[[ -f .github/workflows/publish_hub_amd64.yml ]] \
  || fail "missing develop GHCR publisher"
[[ -f .github/workflows/publish_main_amd64.yml ]] \
  || fail "missing versioned main release publisher"
[[ -f .github/workflows/main-release-pr-policy.yml ]] \
  || fail "missing develop-to-main release policy"

pattern='force_bump|version:(major|minor|patch)|compute-next-version|apply-version|docker/base/VERSION|git push origin HEAD:main'
if grep -RInE --include='*.yml' --include='*.yaml' "$pattern" .github/workflows 2>/dev/null; then
  fail "automatic semantic-version mutation detected in workflow configuration"
fi

grep -Fq 'branches: [develop]' .github/workflows/publish_hub_amd64.yml \
  || fail "develop publisher must be bound to develop"
grep -Fq 'resolve-hub-base-refs.sh --github-output' .github/workflows/publish_hub_amd64.yml \
  || fail "develop publisher must resolve content-addressed bases"
grep -Fq 'ghcr.io/${{ github.repository_owner }}/argws-connect-hub:develop' .github/workflows/publish_hub_amd64.yml \
  || fail "develop publisher must keep ghcr.io/.../argws-connect-hub:develop"
grep -Fq "CACHE_RETENTION_HOURS: '2'" .github/workflows/publish_hub_amd64.yml \
  || fail "develop publisher must prune build caches older than two hours"
grep -Fq 'cleanup-github-storage.sh all' .github/workflows/publish_hub_amd64.yml \
  || fail "develop publisher must prune old GHCR versions after a successful build"

grep -Fq 'branches: [main]' .github/workflows/publish_main_amd64.yml \
  || fail "main release publisher must be bound to main"
grep -Fq 'contents: write' .github/workflows/publish_main_amd64.yml \
  || fail "main release publisher needs contents: write for tag and GitHub Release"
grep -Fq 'actions: write' .github/workflows/publish_main_amd64.yml \
  || fail "main release publisher needs actions: write for cache retention"
grep -Fq 'resolve-hub-base-refs.sh --github-output' .github/workflows/publish_main_amd64.yml \
  || fail "main release publisher must resolve content-addressed bases"
grep -Fq 'head.ref == "develop"' .github/workflows/publish_main_amd64.yml \
  || fail "main release publisher must require a merged develop -> main PR"
grep -Fq 'bash ./scripts/validate-version-sync.sh' .github/workflows/publish_main_amd64.yml \
  || fail "main release publisher must validate canonical VERSION metadata"
grep -Fq 'echo "ghcr.io/${{ github.repository_owner }}/argws-connect-hub:${v}"' .github/workflows/publish_main_amd64.yml \
  || fail "main release must publish the exact X.Y.Z image tag"
grep -Fq 'echo "ghcr.io/${{ github.repository_owner }}/argws-connect-hub:${major}.${minor}"' .github/workflows/publish_main_amd64.yml \
  || fail "main release must publish the X.Y image tag"
grep -Fq 'echo "ghcr.io/${{ github.repository_owner }}/argws-connect-hub:${major}"' .github/workflows/publish_main_amd64.yml \
  || fail "main release must publish the X image tag"
grep -Fq 'ghcr.io/${{ github.repository_owner }}/argws-connect-hub:latest' .github/workflows/publish_main_amd64.yml \
  || fail "main release must publish latest"
grep -Fq 'git tag -a "$TAG"' .github/workflows/publish_main_amd64.yml \
  || fail "main release must create an annotated vX.Y.Z Git tag"
grep -Fq 'gh release create "$TAG"' .github/workflows/publish_main_amd64.yml \
  || fail "main release must create a GitHub Release"
grep -Fq "CACHE_RETENTION_HOURS: '2'" .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must prune build caches older than two hours"
grep -Fq 'cleanup-github-storage.sh all' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must enforce GHCR retention after a successful build"

if grep -Fq 'argws-connect-hub:main-' .github/workflows/publish_main_amd64.yml; then
  fail "main-<sha> must not replace the canonical SemVer release aliases"
fi

grep -Fq 'Require a new declared SemVer release' .github/workflows/main-release-pr-policy.yml \
  || fail "release PR policy must validate the declared next SemVer before merge"

echo "HUB release-flow validation: develop=:develop; main=SemVer X.Y.Z/X.Y/X + latest + vX.Y.Z + GitHub Release; GHCR keeps current+previous+develop; caches keep <=2h; bases=def-<sha256>"

grep -Fq 'Content-Addressed Base Images' .github/workflows/hub-base-images.yml \
  || fail "base-image workflow must be content-addressed"
