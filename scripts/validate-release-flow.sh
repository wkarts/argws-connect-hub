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
  .github/scripts/apply-version.mjs \
  .github/workflows/auto-version-release.yml; do
  [[ ! -e "$obsolete" ]] || fail "obsolete automatic versioning artifact detected: $obsolete"
done

[[ ! -e docker/base/VERSION ]] \
  || fail "obsolete docker/base/VERSION detected; base identities must be content-addressed"
[[ -x scripts/resolve-hub-base-refs.sh ]] \
  || fail "missing content-addressed base identity resolver"

[[ -f .github/workflows/publish_hub_amd64.yml ]] \
  || fail "missing develop GHCR publisher"
[[ -f .github/workflows/publish_main_amd64.yml ]] \
  || fail "missing main GHCR publisher"
[[ -f .github/workflows/main-release-pr-policy.yml ]] \
  || fail "missing develop-to-main promotion policy"

pattern='force_bump|version:(major|minor|patch)|compute-next-version|apply-version|docker/base/VERSION|git push origin HEAD:main'
if grep -RInE --include='*.yml' --include='*.yaml' \
  --exclude='main-release-pr-policy.yml' \
  "$pattern" .github/workflows 2>/dev/null; then
  fail "automatic semantic-version mutation detected in workflow configuration"
fi

grep -Fq 'branches: [develop]' .github/workflows/publish_hub_amd64.yml \
  || fail "develop publisher must be bound to develop"
grep -Fq 'resolve-hub-base-refs.sh --github-output' .github/workflows/publish_hub_amd64.yml \
  || fail "develop publisher must resolve content-addressed bases"
grep -Fq 'ghcr.io/${{ github.repository_owner }}/argws-connect-hub:develop' .github/workflows/publish_hub_amd64.yml \
  || fail "develop publisher must publish the develop alias"

grep -Fq 'branches: [main]' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must be bound to main"
grep -Fq 'resolve-hub-base-refs.sh --github-output' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must resolve content-addressed bases"
grep -Fq 'head.ref == "develop"' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must require a merged develop -> main PR"
grep -Fq 'ghcr.io/${{ github.repository_owner }}/argws-connect-hub:main' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must publish the main alias"
grep -Fq 'ghcr.io/${{ github.repository_owner }}/argws-connect-hub:latest' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must publish the latest alias"

echo "HUB release-flow validation: branch/SHA publication without automatic SemVer mutation"

grep -Fq 'Content-Addressed Base Images' .github/workflows/hub-base-images.yml \
  || fail "base-image workflow must be content-addressed"
grep -Fq 'def-${' .github/workflows/hub-base-images.yml \
  || true
