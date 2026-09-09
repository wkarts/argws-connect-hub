#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-${ENV_FILE:-.env}}"
COMPOSE_FILE="${2:-${COMPOSE_FILE:-compose.yaml}}"

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
TOKEN="${GHCR_TOKEN:-${CR_PAT:-$(read_env_value GHCR_TOKEN)}}"
REGISTRY="${REGISTRY:-ghcr.io}"
USERNAME="${USERNAME:-wkarts}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker CLI não encontrado." >&2
  exit 127
fi

if [[ -z "$TOKEN" || "$TOKEN" == CHANGE_ME_* ]]; then
  cat >&2 <<EOF
GHCR_TOKEN não configurado em $ENV_FILE.

Configure no .env do deployment:
  GHCR_REGISTRY=ghcr.io
  GHCR_USERNAME=wkarts
  GHCR_TOKEN=SEU_TOKEN

O token precisa conseguir ler os pacotes privados necessários no GHCR.
Ele é usado somente pelo docker login do host e não é enviado aos containers.
EOF
  exit 2
fi

printf '%s' "$TOKEN" | docker login "$REGISTRY" --username "$USERNAME" --password-stdin >/dev/null
echo "GHCR autenticado em $REGISTRY como $USERNAME."

images=()
if [[ -f "$COMPOSE_FILE" ]] && docker compose version >/dev/null 2>&1; then
  mapfile -t images < <(
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config --images \
      | awk 'NF' | sort -u
  )
else
  image="${HUB_IMAGE:-$(read_env_value HUB_IMAGE)}"
  [[ -n "$image" ]] && images+=("$image")
fi

checked=0
for image in "${images[@]}"; do
  [[ "$image" == "$REGISTRY/"* ]] || continue
  if ! docker manifest inspect "$image" >/dev/null 2>&1; then
    echo "Login realizado, mas o pacote não pôde ser lido: $image" >&2
    echo "Confirme read:packages e o acesso deste token ao pacote." >&2
    exit 3
  fi
  echo "OK: $image"
  checked=$((checked + 1))
done

if (( checked == 0 )); then
  echo "Aviso: nenhuma imagem de $REGISTRY foi encontrada para validar." >&2
fi

echo "Autenticação GHCR validada para o deployment."
