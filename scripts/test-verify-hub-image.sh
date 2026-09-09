#!/usr/bin/env bash
# Offline regression tests: Docker is replaced by a deterministic local stub.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/auth/cli-plugins"
printf '{"auths":{"ghcr.io":{"auth":"test-only"}}}\n' > "$work/auth/config.json"
printf '#!/bin/sh\nexit 0\n' > "$work/auth/cli-plugins/docker-buildx"
chmod +x "$work/auth/cli-plugins/docker-buildx"
cat > "$work/bin/docker" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
anonymous=false
if [[ "${DOCKER_CONFIG:-}" != "$TEST_AUTH_CONFIG" ]]; then
  anonymous=true
  [[ "$(cat "$DOCKER_CONFIG/config.json")" == '{"auths":{}}' ]] || exit 91
  [[ -x "$DOCKER_CONFIG/cli-plugins/docker-buildx" ]] || exit 92
fi
printf '%s|%s|%s\n' "$anonymous" "$*" "${DOCKER_CONFIG:-}" >> "$TEST_CALLS"
case "$1 $2" in
  'buildx imagetools')
    # Match the documented Buildx JSON interface; never bless an invented template.
    [[ "$3" == inspect && "$5" == --format && "$6" == '{{json .Manifest}}' ]] || exit 93
    if [[ "$TEST_CASE" == private && "$anonymous" == true ]]; then
      echo 'unauthorized: anonymous access denied' >&2; exit 1
    fi
    if [[ "$TEST_CASE" == inspect-failure ]]; then
      echo 'registry unavailable' >&2; exit 1
    fi
    if [[ "$TEST_CASE" == retry && ! -f "$TEST_RETRIED" ]]; then
      touch "$TEST_RETRIED"; echo 'temporary registry error' >&2; exit 1
    fi
    digest="$EXPECTED_DIGEST"
    [[ "$TEST_CASE" != stale ]] || digest="sha256:$(printf '%064d' 0)"
    case "$TEST_CASE" in
      malformed-json) echo 'not JSON' ;;
      missing-digest) echo '{"schemaVersion":2,"manifests":[]}' ;;
      null-digest) echo '{"digest":null}' ;;
      object-digest) echo '{"digest":{"unexpected":true}}' ;;
      child-only) printf '{"manifests":[{"digest":"%s"}]}\n' "$digest" ;;
      single-manifest)
        printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"%s","config":{"digest":"sha256:%064d"},"layers":[]}\n' "$digest" 3 ;;
      *)
        # Index digest differs from platform and attestation digests.
        printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","digest":"%s","manifests":[{"digest":"sha256:%064d","platform":{"os":"linux","architecture":"amd64"}},{"digest":"sha256:%064d","platform":{"os":"unknown","architecture":"unknown"}}]}\n' "$digest" 3 4 ;;
    esac
    ;;
  'pull --platform')
    [[ "$3" == linux/amd64 && "$4" == "$IMAGE_REPOSITORY@$EXPECTED_DIGEST" ]] || exit 94
    [[ "$TEST_CASE" != pull-failure ]] || exit 1
    ;;
  'image inspect')
    [[ "$3" == "$IMAGE_REPOSITORY@$EXPECTED_DIGEST" ]] || exit 95
    if [[ "$TEST_CASE" == bad-identity ]]; then
      echo 'wrong-version|wrong-sha|stable|linux/arm64'
    else
      echo "$EXPECTED_VERSION|$EXPECTED_REVISION|$EXPECTED_CHANNEL|linux/amd64"
    fi
    ;;
  'run --rm')
    [[ "$TEST_CASE" != missing-assets ]] || exit 1
    # Syntax-check the exact shell program that would run in the container.
    while [[ "$1" != -ec ]]; do shift; done
    printf '%s\n' "$2" | /bin/sh -n
    [[ "$3" == hub-image-check && "$4" == "$EXPECTED_VERSION" && "$5" == "$EXPECTED_REVISION" ]] || exit 96
    ;;
  *) echo "Unexpected Docker invocation: $*" >&2; exit 99 ;;
esac
STUB
chmod +x "$work/bin/docker"
export PATH="$work/bin:$PATH" TEST_AUTH_CONFIG="$work/auth"
export IMAGE_REPOSITORY=ghcr.io/example/hub
export IMAGE_TAGS=$'ghcr.io/example/hub:1.0.3\nghcr.io/example/hub:latest'
export EXPECTED_DIGEST="sha256:$(printf '%064d' 1)"
export EXPECTED_REVISION="$(printf '%040d' 2)"
export EXPECTED_VERSION=1.0.3 EXPECTED_CHANNEL=stable
export HUB_IMAGE_VERIFY_ATTEMPTS=1 HUB_IMAGE_VERIFY_DELAY=0
count=0
run_case() {
  local scenario="$1" expected_status="$2" anonymous="${3:-true}" status=0
  export TEST_CASE="$scenario" TEST_CALLS="$work/calls" TEST_RETRIED="$work/retried"
  rm -f "$TEST_CALLS" "$TEST_RETRIED"
  DOCKER_CONFIG="$TEST_AUTH_CONFIG" HUB_IMAGE_REQUIRE_ANONYMOUS_PULL="$anonymous" \
    GITHUB_STEP_SUMMARY="$work/summary" bash "$root/verify-hub-image.sh" > "$work/output" 2>&1 || status=$?
  if [[ "$expected_status" == success && "$status" != 0 ]] || [[ "$expected_status" == failure && "$status" == 0 ]]; then
    cat "$work/output" >&2
    echo "FAIL: $scenario ($anonymous), exit $status" >&2
    exit 1
  fi
  if [[ "$expected_status" == success ]]; then
    grep -Fq 'Final image downloaded;' "$work/output"
    if [[ "$anonymous" == true ]]; then
      grep -Fq 'true|pull --platform' "$TEST_CALLS"
      temporary_config="$(awk -F'|' '/true\|pull/{print $3}' "$TEST_CALLS")"
      [[ ! -d "$temporary_config" ]] || { echo 'Temporary config was not removed' >&2; exit 1; }
    else
      grep -Fq 'false|pull --platform' "$TEST_CALLS"
      ! grep -q '^true|' "$TEST_CALLS"
    fi
  else
    ! grep -Fq 'Final image downloaded;' "$work/output"
  fi
  ((count+=1))
  echo "PASS: $scenario (anonymous=$anonymous, expected=$expected_status)"
}
run_case public success
run_case private failure
! grep -Fq '|pull ' "$TEST_CALLS"
run_case private success false
run_case stale failure
! grep -Fq '|pull ' "$TEST_CALLS"
for scenario in inspect-failure malformed-json missing-digest null-digest object-digest child-only; do
  run_case "$scenario" failure
  ! grep -Fq '|pull ' "$TEST_CALLS"
done
run_case single-manifest success
run_case pull-failure failure
! grep -Fq '|run ' "$TEST_CALLS"
run_case bad-identity failure
! grep -Fq '|run ' "$TEST_CALLS"
run_case missing-assets failure
HUB_IMAGE_VERIFY_ATTEMPTS=2 run_case retry success
run_case public failure invalid
EXPECTED_DIGEST=invalid run_case public failure
EXPECTED_CHANNEL=invalid run_case public failure
IMAGE_TAGS='ghcr.io/example/not-hub:latest' run_case public failure
EXPECTED_VERSION=1.0.3-develop.abcdef123456 EXPECTED_CHANNEL=develop \
  IMAGE_TAGS=$'ghcr.io/example/hub:develop\nghcr.io/example/hub:develop-abcdef123456' run_case public success
[[ "$(cat "$work/auth/config.json")" == '{"auths":{"ghcr.io":{"auth":"test-only"}}}' ]]
echo "HUB image verification tests: $count passed. Original credentials untouched."
