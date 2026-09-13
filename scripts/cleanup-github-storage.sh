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
  local tmp page json count current previous id tags protected tag
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN
  page=1

  echo "Resolving GHCR retention for ghcr.io/${OWNER}/${PACKAGE}..."

  while :; do
    json="$(gh api -H 'Accept: application/vnd.github+json' \
      "/users/${OWNER}/packages/container/${PACKAGE}/versions?per_page=100&page=${page}")"
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

  echo "Protected release images: current=${current}, previous=${previous:-none}, plus develop"

  while IFS= read -r version; do
    id="$(jq -r '.id' <<<"$version")"
    tags="$(jq -r '.metadata.container.tags[]?' <<<"$version")"
    protected=false

    while IFS= read -r tag; do
      [[ -n "$tag" ]] || continue
      if [[ "$tag" == "develop" || "$tag" == "$current" || ( -n "$previous" && "$tag" == "$previous" ) ]]; then
        protected=true
        break
      fi
    done <<<"$tags"

    if [[ "$protected" == true ]]; then
      echo "Keeping GHCR version id=${id}: $(tr '\n' ',' <<<"$tags" | sed 's/,$//')"
      continue
    fi

    echo "Deleting old GHCR version id=${id}: $(tr '\n' ',' <<<"$tags" | sed 's/,$//')"
    gh api --method DELETE -H 'Accept: application/vnd.github+json' \
      "/users/${OWNER}/packages/container/${PACKAGE}/versions/${id}" >/dev/null
  done < "$tmp"

  rm -f "$tmp"
  trap - RETURN
}

[[ "$MODE" == all || "$MODE" == cache ]] && cleanup_cache
[[ "$MODE" == all || "$MODE" == ghcr ]] && cleanup_ghcr

echo "GitHub storage retention cleanup: OK"
