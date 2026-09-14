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
  || fail "missing stable main publisher"
[[ -f .github/workflows/main-release-pr-policy.yml ]] \
  || fail "missing develop-to-main promotion policy"

pattern='force_bump|version:(major|minor|patch)|compute-next-version|apply-version|docker/base/VERSION|git push origin HEAD:main'
if grep -RInE --include='*.yml' --include='*.yaml' "$pattern" .github/workflows 2>/dev/null; then
  fail "automatic semantic-version mutation detected in workflow configuration"
fi

# develop is mutable by branch alias, immutable by SHA alias, and never deletes
# application package versions as part of ordinary development publication.
grep -Fq 'branches: [develop]' .github/workflows/publish_hub_amd64.yml \
  || fail "develop publisher must be bound to develop"
grep -Fq 'resolve-hub-base-refs.sh --github-output' .github/workflows/publish_hub_amd64.yml \
  || fail "develop publisher must resolve content-addressed bases"
grep -Fq 'ghcr.io/${{ github.repository_owner }}/argws-connect-hub:develop' .github/workflows/publish_hub_amd64.yml \
  || fail "develop publisher must keep ghcr.io/.../argws-connect-hub:develop"
grep -Fq 'develop-${{ steps.versions.outputs.short_sha }}' .github/workflows/publish_hub_amd64.yml \
  || fail "develop publisher must keep an immutable develop-<sha> alias"
grep -Fq 'sha-${{ github.sha }}' .github/workflows/publish_hub_amd64.yml \
  || fail "develop publisher must keep the full SHA alias"
grep -Fq "CACHE_RETENTION_HOURS: '2'" .github/workflows/publish_hub_amd64.yml \
  || fail "develop publisher must prune build caches older than two hours"
grep -Fq 'cleanup-github-storage.sh cache' .github/workflows/publish_hub_amd64.yml \
  || fail "develop publisher may clean only Actions/Buildx cache"
if grep -Fq 'cleanup-github-storage.sh all' .github/workflows/publish_hub_amd64.yml || \
   grep -Fq 'cleanup-github-storage.sh ghcr' .github/workflows/publish_hub_amd64.yml; then
  fail "develop publisher must never delete GHCR image versions"
fi

grep -Fq 'Verify final develop image after maintenance' .github/workflows/publish_hub_amd64.yml \
  || fail "develop image must be verified after cache maintenance"

# main promotion is deliberately independent from semantic release tags. VERSION,
# package.json and RELEASE-MANIFEST.json remain synchronized source metadata, while
# publication identity is the exact main commit SHA. Re-running the same SHA must
# converge aliases instead of failing because a historical vX.Y.Z tag exists.
grep -Fq 'branches: [main]' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must be bound to main"
grep -Fq 'contents: read' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must not require repository write permission for version tags"
grep -Fq 'packages: write' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher needs packages: write"
grep -Fq 'actions: write' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher needs actions: write for cache retention"
grep -Fq 'pull-requests: read' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher needs pull-request read access for develop -> main provenance"
grep -Fq 'resolve-hub-base-refs.sh --github-output' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must resolve content-addressed bases"
grep -Fq 'head.ref == "develop"' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must require a merged develop -> main PR"
grep -Fq 'bash ./scripts/validate-version-sync.sh' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must validate synchronized VERSION source metadata"
grep -Fq 'ghcr.io/${{ github.repository_owner }}/argws-connect-hub:main' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must keep the stable main alias"
grep -Fq 'ghcr.io/${{ github.repository_owner }}/argws-connect-hub:latest' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must keep latest"
grep -Fq 'main-${{ steps.identity.outputs.short_sha }}' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must keep an immutable main-<sha> alias"
grep -Fq 'sha-${{ github.sha }}' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must keep the full SHA alias"
grep -Fq 'Resolve existing stable SHA image' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must detect an already-published immutable main SHA"
grep -Fq 'steps.existing.outputs.exists' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must branch idempotently when the immutable SHA already exists"
grep -Fq 'docker buildx imagetools create' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must reapply moving aliases without rebuilding an existing stable SHA"
grep -Fq 'EXPECTED_VERSION: ${{ steps.identity.outputs.main_version }}' .github/workflows/publish_main_amd64.yml \
  || fail "main verification must use the SHA-derived stable build identity"
grep -Fq 'EXPECTED_CHANNEL: stable' .github/workflows/publish_main_amd64.yml \
  || fail "main image must be verified as stable"
grep -Fq "CACHE_RETENTION_HOURS: '2'" .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must prune old caches"
grep -Fq 'cleanup-github-storage.sh all' .github/workflows/publish_main_amd64.yml \
  || fail "main publisher must enforce safe application GHCR retention"

if grep -Eq 'gh release create|git tag -a|refs/tags/|Release tag .*already exists|must be greater than latest release' .github/workflows/publish_main_amd64.yml; then
  fail "main publisher must not create or gate promotion on semantic Git tags/GitHub Releases"
fi

if grep -Fq 'Require a new declared SemVer release' .github/workflows/main-release-pr-policy.yml; then
  fail "develop -> main policy must not require a new semantic version for every promotion"
fi
grep -Fq 'Validate source metadata for idempotent promotion' .github/workflows/main-release-pr-policy.yml \
  || fail "promotion policy must validate synchronized metadata without semantic-tag conflicts"
grep -Fq 'Existing SemVer tags do not block develop -> main promotion.' .github/workflows/main-release-pr-policy.yml \
  || fail "promotion policy must explicitly preserve idempotent behavior with existing release tags"

# Storage cleanup remains constrained to the HUB package and preserves OCI children.
grep -Fq 'PACKAGE" != "argws-connect-hub"' scripts/cleanup-github-storage.sh \
  || fail "GHCR cleanup must refuse every package except argws-connect-hub"
grep -Fq 'untagged OCI child/attestation manifest' scripts/cleanup-github-storage.sh \
  || fail "GHCR cleanup must preserve untagged OCI child and attestation manifests"

grep -Fq 'Content-Addressed Base Images' .github/workflows/hub-base-images.yml \
  || fail "base-image workflow must be content-addressed"

echo "HUB release-flow validation: develop=:develop/develop-<sha>/sha-<sha>; main=:main/:latest/main-<sha>/sha-<sha>; VERSION is synchronized source metadata; develop -> main promotion is idempotent and does not create semantic release tags"
