#!/usr/bin/env bash
# Verify the final application, not its bases. Never changes GHCR visibility.
# Public deployments are checked with an empty Docker config by default.
# Set HUB_IMAGE_REQUIRE_ANONYMOUS_PULL=false only for intentionally private deployments.
set -euo pipefail

fail() { echo "HUB image verification: $*" >&2; exit 1; }
: "${IMAGE_REPOSITORY:?IMAGE_REPOSITORY is required}"
: "${IMAGE_TAGS:?IMAGE_TAGS is required}"
: "${EXPECTED_DIGEST:?EXPECTED_DIGEST is required}"
: "${EXPECTED_VERSION:?EXPECTED_VERSION is required}"
: "${EXPECTED_REVISION:?EXPECTED_REVISION is required}"
: "${EXPECTED_CHANNEL:?EXPECTED_CHANNEL is required}"
[[ "$EXPECTED_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || fail 'Invalid build digest.'
[[ "$EXPECTED_REVISION" =~ ^[0-9a-f]{40}$ ]] || fail 'Invalid source revision.'
[[ "$EXPECTED_CHANNEL" == stable || "$EXPECTED_CHANNEL" == develop ]] || fail 'Invalid channel.'
require_anonymous="${HUB_IMAGE_REQUIRE_ANONYMOUS_PULL:-true}"
[[ "$require_anonymous" == true || "$require_anonymous" == false ]] || fail 'HUB_IMAGE_REQUIRE_ANONYMOUS_PULL must be true or false.'
attempts="${HUB_IMAGE_VERIFY_ATTEMPTS:-6}"
delay="${HUB_IMAGE_VERIFY_DELAY:-5}"
[[ "$attempts" =~ ^[1-9][0-9]*$ ]] || fail 'Invalid retry count.'
[[ "$delay" =~ ^[0-9]+$ ]] || fail 'Invalid retry delay.'
for tool in docker timeout mktemp jq; do
  command -v "$tool" >/dev/null || fail "Missing command: $tool"
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
original_config="${DOCKER_CONFIG:-$HOME/.docker}"
mkdir -p "$work/anonymous/cli-plugins"
printf '{"auths":{}}\n' > "$work/anonymous/config.json"
# setup-buildx-action may install the CLI plugin inside the original config.
# Share only that binary, never auth, credential helpers or Docker contexts.
if [[ -x "$original_config/cli-plugins/docker-buildx" ]]; then
  ln -s "$original_config/cli-plugins/docker-buildx" "$work/anonymous/cli-plugins/docker-buildx"
fi

verify_tag() {
  local tag="$1" actual='' attempt
  for ((attempt=1; attempt<=attempts; attempt++)); do
    # Manifest is a Buildx template wrapper, not a Go struct with a Digest field.
    # Its documented JSON representation exposes the top-level registry digest.
    if actual="$(timeout 45s docker buildx imagetools inspect "$tag" --format '{{json .Manifest}}' 2>"$work/inspect-error")"; then
      if actual="$(jq -er '.digest | select(type == "string")' <<<"$actual" 2>"$work/inspect-error")"; then
        [[ "$actual" == "$EXPECTED_DIGEST" ]] && return 0
        printf 'Unexpected digest for %s: %s (expected %s)\n' "$tag" "$actual" "$EXPECTED_DIGEST" > "$work/inspect-error"
      else
        printf 'Invalid manifest JSON or missing top-level digest for %s\n' "$tag" >> "$work/inspect-error"
      fi
    fi
    (( attempt == attempts )) || sleep "$delay"
  done
  cat "$work/inspect-error" >&2
  return 1
}

mapfile -t tags < <(printf '%s\n' "$IMAGE_TAGS" | sed '/^[[:space:]]*$/d')
(( ${#tags[@]} > 0 )) || fail 'No tags to verify.'
for tag in "${tags[@]}"; do
  [[ "$tag" == "$IMAGE_REPOSITORY":* ]] || fail "Unexpected image repository: $tag"
  verify_tag "$tag" || fail "Registry tag does not resolve to this build: $tag"
done

if [[ "$require_anonymous" == true ]]; then
  export DOCKER_CONFIG="$work/anonymous"
  for tag in "${tags[@]}"; do
    verify_tag "$tag" || fail "Authenticated verification passed, but anonymous access failed for $tag. Check package visibility/access and the registry response above. No visibility was changed."
  done
fi

# Pull the immutable digest so a concurrent moving-tag update cannot change
# the image inspected or executed below. Pull actually downloads image layers.
image="$IMAGE_REPOSITORY@$EXPECTED_DIGEST"
pulled=false
for ((attempt=1; attempt<=3; attempt++)); do
  if timeout 180s docker pull --platform linux/amd64 "$image"; then
    pulled=true
    break
  fi
  (( attempt == 3 )) || sleep "$delay"
done
[[ "$pulled" == true ]] || fail "Cannot download final application image: $image"

metadata="$(docker image inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.version"}}|{{index .Config.Labels "org.opencontainers.image.revision"}}|{{index .Config.Labels "org.argws.hub.channel"}}|{{.Os}}/{{.Architecture}}')"
[[ "$metadata" == "$EXPECTED_VERSION|$EXPECTED_REVISION|$EXPECTED_CHANNEL|linux/amd64" ]] \
  || fail "Downloaded image identity mismatch: $metadata"

# No database, secrets, ports or host volumes. This checks packaged files only;
# it is deliberately not a claim of a complete Rails/application smoke test.
timeout 60s docker run --rm --network none --read-only --cap-drop ALL \
  --security-opt no-new-privileges --entrypoint /bin/sh "$image" -ec '
    test "$(cat /app/.hub_version)" = "$1"
    test "$(cat /app/.git_sha)" = "$2"
    test -s /app/config/application.rb
    test -s /app/Gemfile.lock
    test -d /gems
    test -s /app/public/packs/manifest.json
    ruby -rjson -e '\''
      manifest = JSON.parse(File.read("/app/public/packs/manifest.json"))
      %w[application.js application.css].each do |key|
        path = manifest.fetch(key)
        abort "Invalid asset path: #{key}" unless path.is_a?(String) && path.start_with?("/packs/")
        full = File.expand_path(path.delete_prefix("/"), "/app/public")
        abort "Missing packaged asset: #{key}" unless full.start_with?("/app/public/packs/") && File.file?(full) && File.size?(full)
      end
    '\''
  ' hub-image-check "$EXPECTED_VERSION" "$EXPECTED_REVISION" \
  || fail 'Final image is missing the expected version, revision or compiled assets.'

{
  echo '### HUB application image verified'
  printf 'Version: `%s` | Channel: `%s`\n\n' "$EXPECTED_VERSION" "$EXPECTED_CHANNEL"
  printf 'Digest: `%s`\n\n' "$EXPECTED_DIGEST"
  printf 'Anonymous pull required: `%s`\n\n' "$require_anonymous"
  printf 'Verified tag: `%s`\n' "${tags[@]}"
  echo 'Final image downloaded; identity and compiled application assets verified.'
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
