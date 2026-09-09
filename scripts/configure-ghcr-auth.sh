#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${GHCR_REGISTRY:-ghcr.io}"
USERNAME="${GHCR_USERNAME:-wkarts}"
TOKEN="${GHCR_TOKEN:-}"
DOCKGE_CONTAINER="${DOCKGE_CONTAINER:-dockge}"

if [[ -z "$TOKEN" ]]; then
  if [[ -t 0 ]]; then
    printf 'GHCR token (entrada oculta): ' >&2
    IFS= read -r -s TOKEN
    printf '\n' >&2
  else
    echo 'GHCR_TOKEN não definido e stdin não é interativo.' >&2
    exit 2
  fi
fi

if [[ -z "$TOKEN" || "$TOKEN" == CHANGE_ME_* ]]; then
  echo 'GHCR_TOKEN inválido.' >&2
  exit 2
fi

upsert_env() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp)"
  if grep -q "^${key}=" "$file"; then
    awk -v key="$key" -v value="$value" '
      index($0, key "=") == 1 { print key "=" value; next }
      { print }
    ' "$file" > "$tmp"
  else
    cat "$file" > "$tmp"
    printf '\n%s=%s\n' "$key" "$value" >> "$tmp"
  fi
  cat "$tmp" > "$file"
  rm -f "$tmp"
  chmod 600 "$file" 2>/dev/null || true
}

deployments=(
  deployment/production/standalone
  deployment/production/embedded-connect-api
  deployment/development/standalone
  deployment/development/embedded-connect-api
)

configured=()
for relative in "${deployments[@]}"; do
  dir="$ROOT/$relative"
  example="$dir/.env.example"
  env_file="$dir/.env"
  compose="$dir/compose.yaml"

  [[ -f "$example" ]] || { echo "Ausente: $example" >&2; exit 3; }
  [[ -f "$compose" ]] || { echo "Ausente: $compose" >&2; exit 3; }

  if [[ ! -f "$env_file" ]]; then
    cp "$example" "$env_file"
    chmod 600 "$env_file" 2>/dev/null || true
    echo "Criado: $relative/.env"
  fi

  upsert_env "$env_file" GHCR_REGISTRY "$REGISTRY"
  upsert_env "$env_file" GHCR_USERNAME "$USERNAME"
  upsert_env "$env_file" GHCR_TOKEN "$TOKEN"
  configured+=("$env_file")
  echo "Configurado: $relative/.env"
done

# Uma autenticação no daemon do host vale para todos os pulls ghcr.io realizados
# por esse cliente Docker. O token nunca é injetado nos containers da aplicação.
printf '%s' "$TOKEN" | docker login "$REGISTRY" --username "$USERNAME" --password-stdin >/dev/null
echo "Docker do host autenticado em $REGISTRY como $USERNAME."

# Valida cada variante exatamente com as imagens resolvidas por seu Compose.
for relative in "${deployments[@]}"; do
  dir="$ROOT/$relative"
  bash "$ROOT/scripts/ghcr-login.sh" "$dir/.env" "$dir/compose.yaml"
done

# Se Dockge estiver presente, autentica também o cliente Docker usado por ele.
if docker inspect "$DOCKGE_CONTAINER" >/dev/null 2>&1; then
  bash "$ROOT/scripts/ghcr-login-dockge.sh" \
    "$ROOT/deployment/production/standalone/.env" "$DOCKGE_CONTAINER"
else
  echo "Dockge não detectado como '$DOCKGE_CONTAINER'; autenticação do host concluída."
fi

echo 'Autenticação GHCR configurada em todos os deployments locais.'
