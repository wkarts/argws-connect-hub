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
  find app config lib db/migrate spec -type f -name '*.rb' -print0 2>/dev/null \
    | xargs -0 -r -n1 ruby -c >/dev/null
fi

if command -v node >/dev/null 2>&1; then
  echo "Validating release scripts..."
  while IFS= read -r -d '' file; do
    node --check "$file" >/dev/null
  done < <(find .github/scripts scripts -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) -print0 2>/dev/null)
fi

echo "Validating shell scripts..."
while IFS= read -r -d '' file; do
  bash -n "$file"
done < <(find scripts docker deployment -type f -name '*.sh' -print0 2>/dev/null)

base_version="$(tr -d '[:space:]' < docker/base/VERSION)"
[[ "$base_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "docker/base/VERSION must be SemVer X.Y.Z"

grep -Fq "argws-connect-hub-build-base:${base_version}" docker/Dockerfile \
  || fail "docker/Dockerfile does not reference build base ${base_version}"
grep -Fq "argws-connect-hub-runtime-base:${base_version}" docker/Dockerfile \
  || fail "docker/Dockerfile does not reference runtime base ${base_version}"

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

  local suffix="-connec-hub"
  [[ "$channel" == development ]] && suffix="-connec-hub-develop"

  for role in rails sidekiq migrate postgres redis; do
    grep -qx "${role}${suffix}" <<<"$services" \
      || fail "$dir: required HUB service ${role}${suffix} is missing"
  done

  python3 - "$compose" "$env_file" "$channel" <<'PY'
import json
import subprocess
import sys

compose, env_file, channel = sys.argv[1:]
suffix = '-connec-hub-develop' if channel == 'development' else '-connec-hub'
expected = {f'{role}{suffix}' for role in ('rails', 'sidekiq', 'migrate', 'postgres', 'redis')}
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

validate_stack deployment/production/standalone production
validate_stack deployment/production/embedded-connect-api production
validate_stack deployment/development/standalone development
validate_stack deployment/development/embedded-connect-api development

echo "HUB CI validation: OK"
