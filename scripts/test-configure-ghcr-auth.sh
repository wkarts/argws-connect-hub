#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/configure-ghcr-auth.sh"

[[ -f "$script" ]]
bash -n "$script"
grep -Fq 'deployment/production/standalone' "$script"
grep -Fq 'deployment/production/embedded-connect-api' "$script"
grep -Fq 'deployment/development/standalone' "$script"
grep -Fq 'deployment/development/embedded-connect-api' "$script"
grep -Fq 'docker login "$REGISTRY" --username "$USERNAME" --password-stdin' "$script"
grep -Fq 'ghcr-login-dockge.sh' "$script"
! grep -Eq 'ghp_[A-Za-z0-9]+' "$script"

echo 'GHCR deployment configuration test: OK'
