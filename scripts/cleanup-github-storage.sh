#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-all}"
REPOSITORY="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
OWNER="${GHCR_OWNER:-${REPOSITORY%%/*}}"
PACKAGE="${GHCR_PACKAGE:-argws-connect-hub}"
CACHE_RETENTION_HOURS="${CACHE_RETENTION_HOURS:-2}"

: "${GH_TOKEN:?GH_TOKEN is required}"

case "$MODE" in
  all|ghcr|cache) ;;
  *)
    echo "Usage: $0 [all|ghcr|cache]" >&2
    exit 2
    ;;
esac

cleanup_cache() {
  local cutoff page json count id timestamp epoch
  cutoff="$(date -u -d "${CACHE_RETENTION_HOURS} hours ago" +%s)"
  page=1

  echo "Cleaning GitHub Actions caches not accessed in the last ${CACHE_RETENTION_HOURS} hour(s)..."

  while :; do
    json="$(gh api -H 'Accept: application/vnd.github+json' \
      "/repos/${REPOSITORY}/actions/caches?per_page=100&page=${page}")"
    count="$(jq '.actions_caches | length' <<<"$json")"
    [[ "$count" -eq 0 ]] && break

    while IFS=$'\t' read -r id timestamp; do
      [[ -n "$id" && -n "$timestamp" ]] || continue
      epoch="$(date -u -d "$timestamp" +%s)"
      if (( epoch < cutoff )); then
        echo "Deleting Actions cache id=${id} last_accessed_at=${timestamp}"
        gh api --method DELETE -H 'Accept: application/vnd.github+json' \
          "/repos/${REPOSITORY}/actions/caches/${id}" >/dev/null
      fi
    done < <(jq -r '.actions_caches[] | [.id, (.last_accessed_at // .created_at)] | @tsv' <<<"$json")

    [[ "$count" -lt 100 ]] && break
    page=$((page + 1))
  done
}

cleanup_ghcr() {
  local tmp page json count current previous id tags digest protected version tag
  local script_dir registry canonical_tags canonical_digests
  local -a release_versions

  # Hard safety boundary: this cleanup is ONLY for the application package.
  # Content-addressed build/runtime/deps base packages must never be touched here.
  if [[ "$PACKAGE" != "argws-connect-hub" ]]; then
    echo "Refusing GHCR cleanup for package '$PACKAGE'; only argws-connect-hub is allowed." >&2
    return 1
  fi

  # Fail closed before listing/deleting images if the cumulative policy is
  # absent, malformed or no longer contains the immutable 1.1.8 floor.
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  registry="${script_dir}/../config/canonical-releases.json"
  node "${script_dir}/canonical-releases.mjs" validate || return 1
  canonical_tags="$(jq -er '.releases[] | .version, .git_tag' "$registry")" || return 1
  canonical_digests="$(jq -er '.releases[].image_digest' "$registry")" || return 1

  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN
  page=1

  echo "Resolving safe GHCR retention for ghcr.io/${OWNER}/${PACKAGE}..."

  while :; do
    json="$(gh api -H 'Accept: application/vnd.github+json' \
      "/users/${OWNER}/packages/container/${PACKAGE}/versions?per_page=100&page=${page}")"
    # Validate every page before considering any deletion. Never prune from
    # an incomplete/error response or an unexpected package-version shape.
    jq -e 'type == "array" and all(.[];
      (.id | type == "number" and . > 0 and . == floor) and
      (.name | type == "string" and test("^sha256:[a-f0-9]{64}$")) and
      (.metadata.container.tags | type == "array" and all(.[]; type == "string"))
    )' <<<"$json" >/dev/null || return 1
    count="$(jq 'length' <<<"$json")"
    [[ "$count" -eq 0 ]] && break
    jq -c '.[]' <<<"$json" >> "$tmp"
    [[ "$count" -lt 100 ]] && break
    page=$((page + 1))
  done

  if [[ ! -s "$tmp" ]]; then
    echo "No GHCR package versions found; nothing to clean."
    return
  fi

  mapfile -t release_versions < <(
    jq -r '.metadata.container.tags[]? | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' "$tmp" \
      | sort -Vu \
      | sort -Vr
  )

  current="${release_versions[0]:-}"
  previous="${release_versions[1]:-}"

  if [[ -z "$current" ]]; then
    echo "No exact X.Y.Z GHCR release tag was found; skipping image pruning as a safety guard."
    return
  fi

  echo "Protected application images: current=${current}, previous=${previous:-none}, all canonical tags/digests and active aliases."
  echo "Untagged OCI child/SBOM/provenance manifests are always preserved."

  while IFS= read -r version; do
    id="$(jq -r '.id' <<<"$version")"
    tags="$(jq -r '.metadata.container.tags[]?' <<<"$version")"

    # Buildx publishes OCI child/platform/SBOM/provenance manifests as untagged
    # package versions. Deleting them can make a tagged parent manifest unreadable.
    if [[ -z "$tags" ]]; then
      echo "Keeping GHCR version id=${id}: untagged OCI child/attestation manifest."
      continue
    fi

    digest="$(jq -r '.name' <<<"$version")"
    if grep -Fqx -- "$digest" <<<"$canonical_digests"; then
      echo "Keeping GHCR version id=${id}: canonical image digest."
      continue
    fi

    # A package version may have several tags. ANY protected tag protects the
    # entire version, even when an old SemVer happens to be its first tag.
    # Unknown/manual tags remain protected rather than being guessed obsolete.
    protected=false
    while IFS= read -r tag; do
      [[ -n "$tag" ]] || continue
      if grep -Fqx -- "$tag" <<<"$canonical_tags" ||
         [[ "$tag" == "$current" || "$tag" == "$previous" ||
            "$tag" == develop || "$tag" == latest || "$tag" == stable || "$tag" == canonical ]]; then
        protected=true
        break
      fi
      if [[ ! "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ &&
            ! "$tag" =~ ^develop-[0-9a-f]{7,64}$ && ! "$tag" =~ ^sha-[0-9a-f]{7,64}$ ]]; then
        protected=true
        break
      fi
    done <<<"$tags"

    if [[ "$protected" == false ]]; then
      echo "Deleting obsolete tagged application version id=${id}: $(tr '\n' ',' <<<"$tags" | sed 's/,$//')."
      gh api --method DELETE -H 'Accept: application/vnd.github+json' \
        "/users/${OWNER}/packages/container/${PACKAGE}/versions/${id}" >/dev/null
    else
      echo "Keeping GHCR version id=${id}: protected tags $(tr '\n' ',' <<<"$tags" | sed 's/,$//')."
    fi
  done < "$tmp"

  rm -f "$tmp"
  trap - RETURN
}

[[ "$MODE" == all || "$MODE" == cache ]] && cleanup_cache
[[ "$MODE" == all || "$MODE" == ghcr ]] && cleanup_ghcr

echo "GitHub storage retention cleanup: OK"
