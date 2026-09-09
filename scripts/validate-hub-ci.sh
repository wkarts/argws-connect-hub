#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "HUB CI validation: $*" >&2
  exit 1
}

if [[ -x ./scripts/audit-hub.sh ]]; then
  bash ./scripts/audit-hub.sh
fi

if command -v ruby >/dev/null 2>&1; then
  echo "Validating Ruby syntax..."
  ruby ./scripts/check-ruby-syntax.rb app config lib db/migrate spec
fi

if command -v node >/dev/null 2>&1; then
  echo "Validating release scripts..."
  while IFS= read -r -d '' file; do
    node --check "$file" >/dev/null
  done < <(find .github/scripts scripts packages -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) -print0 2>/dev/null)
fi

echo "Validating shell scripts..."
while IFS= read -r -d '' file; do
  bash -n "$file"
done < <(find scripts docker deployment -type f -name '*.sh' -print0 2>/dev/null)

base_version="$(tr -d '[:space:]' < docker/base/VERSION)"
[[ "$base_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "docker/base/VERSION must be SemVer X.Y.Z"

grep -Fq "argws-connect-hub-deps-base:${base_version}" docker/Dockerfile \
  || fail "docker/Dockerfile does not reference dependency base ${base_version}"
grep -Fq "argws-connect-hub-runtime-base:${base_version}" docker/Dockerfile \
  || fail "docker/Dockerfile does not reference runtime base ${base_version}"


# HUB source policy: no operational dependency or runtime namespace may point back
# to the historical vendor project. Legal notices are intentionally not rewritten
# by this technical gate.
legacy_vendor='chat''woot'
legacy_namespace='c''w_|c''w-|C''W_'
if grep -RInI \
  --exclude-dir=.git \
  --exclude-dir=node_modules \
  --exclude-dir=vendor/bundle \
  --exclude=LICENSE \
  --exclude=THIRD_PARTY_NOTICES.md \
  -i "$legacy_vendor" Gemfile Gemfile.lock package.json yarn.lock app config lib packages docker deployment scripts .github 2>/dev/null; then
  fail "operational historical-vendor reference detected"
fi

if grep -RInI \
  --exclude-dir=.git \
  --exclude-dir=node_modules \
  --exclude-dir=vendor \
  -E "$legacy_namespace" app config lib packages docker deployment scripts .github spec 2>/dev/null; then
  fail "legacy runtime namespace detected; HUB uses hub_* / hub-* only"
fi

if grep -Eq 'git:|github\.com' Gemfile; then
  fail "Gemfile must not install gems directly from Git repositories"
fi

for package in packages/hub-utils packages/hub-editor packages/hub-command-palette; do
  [[ -f "$package/package.json" ]] || fail "missing local HUB package $package"
done

for json in package.json RELEASE-MANIFEST.json; do
  [[ -f "$json" ]] || continue
  if command -v ruby >/dev/null 2>&1; then
    ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' "$json"
  elif command -v node >/dev/null 2>&1; then
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$json"
  fi
done

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  echo "docker compose unavailable; Compose validation skipped."
  exit 0
fi

validate_stack() {
  local dir="$1"
  local channel="$2"
  local embedded="${3:-false}"
  local compose="$dir/compose.yaml"
  local env_example="$dir/.env.example"
  local env_file="$dir/.env"

  [[ -f "$compose" ]] || fail "missing $compose"
  [[ -f "$env_example" ]] || fail "missing $env_example"

  cp "$env_example" "$env_file"
  trap 'rm -f "$env_file"' RETURN

  docker compose --env-file "$env_file" -f "$compose" config --quiet
  docker compose --env-file "$env_file" --profile '*' -f "$compose" config --quiet

  local services
  services="$(docker compose --env-file "$env_file" --profile '*' -f "$compose" config --services)"

  local hub_suffix="-connec-hub"
  local connect_suffix="-connect-api-hub"
  if [[ "$channel" == development ]]; then
    hub_suffix="-connec-hub-develop"
    connect_suffix="-connect-api-hub-develop"
  fi

  for role in rails sidekiq migrate postgres redis; do
    grep -qx "${role}${hub_suffix}" <<<"$services" \
      || fail "$dir: required HUB service ${role}${hub_suffix} is missing"
  done

  if [[ "$embedded" == true ]]; then
    local connect_api="connect-api-hub"
    [[ "$channel" == development ]] && connect_api="connect-api-hub-develop"

    grep -qx "$connect_api" <<<"$services" \
      || fail "$dir: required Connect|API service $connect_api is missing"

    for role in docs postgres redis rabbitmq minio nats zookeeper kafka; do
      grep -qx "${role}${connect_suffix}" <<<"$services" \
        || fail "$dir: required embedded Connect|API service ${role}${connect_suffix} is missing"
    done

    for legacy in connect-api connect-docs connect-postgres connect-redis connect-rabbitmq connect-minio connect-nats connect-zookeeper connect-kafka; do
      if grep -qx "$legacy" <<<"$services"; then
        fail "$dir: legacy unnamespaced embedded service $legacy must not exist"
      fi
    done
  fi

  python3 - "$compose" "$env_file" "$channel" "$embedded" <<'PY'
import json
import subprocess
import sys

compose, env_file, channel, embedded = sys.argv[1:]
hub_suffix = '-connec-hub-develop' if channel == 'development' else '-connec-hub'
connect_suffix = '-connect-api-hub-develop' if channel == 'development' else '-connect-api-hub'
expected = {f'{role}{hub_suffix}' for role in ('rails', 'sidekiq', 'migrate', 'postgres', 'redis')}

if embedded == 'true':
    expected.add('connect-api-hub-develop' if channel == 'development' else 'connect-api-hub')
    expected.update({f'{role}{connect_suffix}' for role in ('docs', 'postgres', 'redis', 'rabbitmq', 'minio', 'nats', 'zookeeper', 'kafka')})

raw = subprocess.check_output(
    ['docker', 'compose', '--env-file', env_file, '--profile', '*', '-f', compose, 'config', '--format', 'json'],
    text=True,
)
cfg = json.loads(raw)
services = cfg.get('services', {})
for name in expected:
    if name not in services:
        raise SystemExit(f'{compose}: missing service {name}')
    actual = services[name].get('container_name')
    if actual != name:
        raise SystemExit(f'{compose}: container_name for {name} must be {name}, got {actual!r}')
PY

  rm -f "$env_file"
  trap - RETURN
}

validate_stack deployment/production/standalone production false
validate_stack deployment/production/embedded-connect-api production true
validate_stack deployment/development/standalone development false
validate_stack deployment/development/embedded-connect-api development true

echo "HUB CI validation: OK"
