#!/usr/bin/env bash
set -euo pipefail
# Read-only verification. Never recreate or move an old tag/release/image.
root="$(cd "$(dirname "$0")/.." && pwd)"
node "$root/scripts/canonical-releases.mjs" validate
while IFS=$'\t' read -r tag tag_object commit image digest release_id; do
  [[ "$(git rev-parse "refs/tags/$tag")" == "$tag_object" ]] || { echo "Canonical tag object changed: $tag" >&2; exit 1; }
  [[ "$(git rev-list -n1 "$tag")" == "$commit" ]] || { echo "Canonical commit changed: $tag" >&2; exit 1; }
  release="$(gh api "/repos/${GITHUB_REPOSITORY:?}/releases/tags/$tag")"
  [[ "$(jq -r .id <<<"$release")" == "$release_id" ]] || { echo "Canonical release missing/replaced: $tag" >&2; exit 1; }
  observed="$(docker buildx imagetools inspect "$image:${tag#v}" --format '{{json .Manifest}}' | jq -er .digest)"
  [[ "$observed" == "$digest" ]] || { echo "Canonical image missing/changed: $tag" >&2; exit 1; }
  echo "Canonical source/release/image retained: $tag $digest"
done < <(jq -r '.releases[] | [.git_tag, .git_tag_object, .git_commit, .image, .image_digest, .release_id] | @tsv' "$root/config/canonical-releases.json")
