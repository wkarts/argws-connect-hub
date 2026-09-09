#!/usr/bin/env bash
set -euo pipefail

REGISTRY="${GHCR_REGISTRY:-ghcr.io}"
USERNAME="${GHCR_USERNAME:-wkarts}"
TOKEN="${GHCR_TOKEN:-${CR_PAT:-}}"
IMAGE="${HUB_IMAGE:-ghcr.io/wkarts/argws-connect-hub:develop}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker CLI não encontrado." >&2
  exit 127
fi

if [[ -z "$TOKEN" ]]; then
  cat >&2 <<'EOF'
GHCR_TOKEN não definido.

A imagem do HUB no GHCR é privada e o Docker precisa autenticar antes do pull.
Use um token GitHub com permissão read:packages (e acesso ao repositório/pacote privado):

  export GHCR_USERNAME=wkarts
  export GHCR_TOKEN='SEU_TOKEN'
  ./scripts/ghcr-login.sh

O token nunca deve ser gravado no compose ou commitado no repositório.
EOF
  exit 2
fi

printf '%s' "$TOKEN" | docker login "$REGISTRY" --username "$USERNAME" --password-stdin

if ! docker manifest inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Login realizado, mas a imagem não pôde ser lida: $IMAGE" >&2
  echo "Confirme se o token possui read:packages e acesso ao pacote privado." >&2
  exit 3
fi

echo "GHCR autenticado e imagem acessível: $IMAGE"
