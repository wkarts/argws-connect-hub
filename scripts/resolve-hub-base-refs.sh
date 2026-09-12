#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

registry="${HUB_GHCR_REGISTRY:-ghcr.io}"
owner="${HUB_GHCR_OWNER:-wkarts}"
output=""
if [[ "${1:-}" == "--github-output" ]]; then
  : "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required with --github-output}"
  output="$GITHUB_OUTPUT"
fi

hash_file() {
  sha256sum "$1" | awk '{print $1}'
}

build_definition_sha="$(hash_file docker/base/build/Dockerfile)"
runtime_definition_sha="$(hash_file docker/base/runtime/Dockerfile)"

package_deps="$(node -e 'const fs=require("fs"); const p=JSON.parse(fs.readFileSync("package.json","utf8")); process.stdout.write(JSON.stringify({dependencies:p.dependencies||{},devDependencies:p.devDependencies||{},resolutions:p.resolutions||{},engines:p.engines||{}}));')"
deps_definition_sha="$({
  printf 'build-definition=%s\n' "$build_definition_sha"
  cat docker/base/deps/Dockerfile Gemfile Gemfile.lock yarn.lock
  printf '%s' "$package_deps"
  find packages -type f -print0 | sort -z | xargs -0 sha256sum
} | sha256sum | awk '{print $1}')"

build_tag="def-${build_definition_sha}"
runtime_tag="def-${runtime_definition_sha}"
deps_tag="def-${deps_definition_sha}"

build_image="${registry}/${owner}/argws-connect-hub-build-base:${build_tag}"
runtime_image="${registry}/${owner}/argws-connect-hub-runtime-base:${runtime_tag}"
deps_image="${registry}/${owner}/argws-connect-hub-deps-base:${deps_tag}"

emit() {
  local key="$1"
  local value="$2"
  if [[ -n "$output" ]]; then
    printf '%s=%s\n' "$key" "$value" >> "$output"
  else
    printf '%s=%s\n' "$key" "$value"
  fi
}

emit build_definition_sha "$build_definition_sha"
emit runtime_definition_sha "$runtime_definition_sha"
emit deps_definition_sha "$deps_definition_sha"
emit build_tag "$build_tag"
emit runtime_tag "$runtime_tag"
emit deps_tag "$deps_tag"
emit build_image "$build_image"
emit runtime_image "$runtime_image"
emit deps_image "$deps_image"
emit build_latest "${registry}/${owner}/argws-connect-hub-build-base:latest"
emit runtime_latest "${registry}/${owner}/argws-connect-hub-runtime-base:latest"
emit deps_latest "${registry}/${owner}/argws-connect-hub-deps-base:latest"
