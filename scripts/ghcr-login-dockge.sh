#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env}"
DOCKGE_CONTAINER="${2:-${DOCKGE_CONTAINER:-dockge}}"

read_env_value() {
  local key="$1" value=''
  [[ -f "$ENV_FILE" ]] || return 0
  value="$(awk -v key="$key" '
    index($0, key "=") == 1 {
      sub("^[^=]*=", "")
      sub("\\r$", "")
      print
      exit
    }
  ' "$ENV_FILE")"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

REGISTRY="${GHCR_REGISTRY:-$(read_env_value GHCR_REGISTRY)}"
USERNAME="${GHCR_USERNAME:-$(read_env_value GHCR_USERNAME)}"
TOKEN="${GHCR_TOKEN:-$(read_env_value GHCR_TOKEN)}"
IMAGE="${HUB_IMAGE:-$(read_env_value HUB_IMAGE)}"
REGISTRY="${REGISTRY:-ghcr.io}"
USERNAME="${USERNAME:-wkarts}"

if [[ -z "$TOKEN" || "$TOKEN" == CHANGE_ME_* ]]; then
  echo "GHCR_TOKEN não configurado em $ENV_FILE." >&2
  exit 2
fi

if ! docker inspect "$DOCKGE_CONTAINER" >/dev/null 2>&1; then
  echo "Container Dockge não encontrado: $DOCKGE_CONTAINER" >&2
  exit 3
fi

if ! docker exec "$DOCKGE_CONTAINER" docker version >/dev/null 2>&1; then
  echo "Docker CLI não está disponível dentro de $DOCKGE_CONTAINER." >&2
  exit 4
fi

printf '%s' "$TOKEN" | docker exec -i "$DOCKGE_CONTAINER" \
  docker login "$REGISTRY" --username "$USERNAME" --password-stdin >/dev/null

echo "Dockge autenticado em $REGISTRY como $USERNAME."

if [[ -n "$IMAGE" ]]; then
  docker exec "$DOCKGE_CONTAINER" docker manifest inspect "$IMAGE" >/dev/null
  echo "Dockge consegue ler: $IMAGE"
fi

echo "Agora o Dockge pode executar pull/update das imagens privadas do GHCR."
