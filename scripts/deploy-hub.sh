#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-deployment/production/standalone}"
ACTION="${2:-up}"

if [[ "$TARGET" != /* ]]; then
  TARGET="$ROOT/$TARGET"
fi

ENV_FILE="$TARGET/.env"
COMPOSE_FILE="$TARGET/compose.yaml"

[[ -f "$ENV_FILE" ]] || { echo "Arquivo não encontrado: $ENV_FILE" >&2; exit 2; }
[[ -f "$COMPOSE_FILE" ]] || { echo "Arquivo não encontrado: $COMPOSE_FILE" >&2; exit 2; }

bash "$ROOT/scripts/ghcr-login.sh" "$ENV_FILE" "$COMPOSE_FILE"

compose=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

case "$ACTION" in
  pull)
    "${compose[@]}" pull
    ;;
  up|update)
    "${compose[@]}" pull
    "${compose[@]}" up -d
    ;;
  config)
    "${compose[@]}" config
    ;;
  *)
    echo "Ação inválida: $ACTION" >&2
    echo "Use: up | update | pull | config" >&2
    exit 2
    ;;
esac
