#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Uso:
  ./migrate-named-volumes-to-bind.sh <variante> [diretorio-da-stack]

Variantes:
  production-standalone
  production-embedded
  development-standalone
  development-embedded

O script copia os dados dos volumes Docker nomeados usados pelos deployments
anteriores para os bind mounts ./volumes/... usados pelos deployments atuais.
Os volumes antigos NÃO são removidos.

Antes de executar, pare a stack sem usar "-v":
  docker compose down
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 2
fi

variant="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$variant" in
  production-standalone)
    relative_stack_dir="production/standalone"
    default_project="connec-hub"
    default_storage_volume="storage-connec-hub"
    default_postgres_volume="postgres-data-connec-hub"
    default_redis_volume="redis-data-connec-hub"
    embedded=false
    ;;
  production-embedded)
    relative_stack_dir="production/embedded-connect-api"
    default_project="connec-hub"
    default_storage_volume="storage-connec-hub"
    default_postgres_volume="postgres-data-connec-hub"
    default_redis_volume="redis-data-connec-hub"
    embedded=true
    ;;
  development-standalone)
    relative_stack_dir="development/standalone"
    default_project="connec-hub-develop"
    default_storage_volume="storage-connec-hub-develop"
    default_postgres_volume="postgres-data-connec-hub-develop"
    default_redis_volume="redis-data-connec-hub-develop"
    embedded=false
    ;;
  development-embedded)
    relative_stack_dir="development/embedded-connect-api"
    default_project="connec-hub-develop"
    default_storage_volume="storage-connec-hub-develop"
    default_postgres_volume="postgres-data-connec-hub-develop"
    default_redis_volume="redis-data-connec-hub-develop"
    embedded=true
    ;;
  *)
    echo "ERRO: variante inválida: $variant" >&2
    usage
    exit 2
    ;;
esac

stack_dir="${2:-${script_dir}/${relative_stack_dir}}"
if [[ ! -d "$stack_dir" ]]; then
  echo "ERRO: diretório da stack não encontrado: $stack_dir" >&2
  exit 1
fi
stack_dir="$(cd "$stack_dir" && pwd)"

env_file="${stack_dir}/.env"
helper_image="${MIGRATION_HELPER_IMAGE:-alpine:3.20}"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERRO: docker não está disponível no PATH." >&2
  exit 1
fi

read_env_var() {
  local key="$1"
  [[ -f "$env_file" ]] || return 1

  awk -v key="$key" '
    index($0, key "=") == 1 {
      sub("^[^=]*=", "", $0)
      sub("\\r$", "", $0)
      print $0
      found=1
    }
    END { if (!found) exit 1 }
  ' "$env_file" | tail -n 1
}

value_or_default() {
  local key="$1"
  local fallback="$2"
  local value=""

  value="$(read_env_var "$key" 2>/dev/null || true)"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$fallback"
  fi
}

resolve_target_path() {
  local configured="$1"

  if [[ "$configured" = /* ]]; then
    printf '%s' "$configured"
  else
    configured="${configured#./}"
    printf '%s/%s' "$stack_dir" "$configured"
  fi
}

resolve_volume() {
  local candidate
  for candidate in "$@"; do
    [[ -n "$candidate" ]] || continue
    if docker volume inspect "$candidate" >/dev/null 2>&1; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

ensure_stack_stopped() {
  local running
  running="$(docker ps -q --filter "label=com.docker.compose.project=${project_name}")"
  if [[ -n "$running" ]]; then
    echo "ERRO: há containers em execução no projeto '${project_name}'." >&2
    echo "Pare a stack primeiro com 'docker compose down' e NÃO use '-v'." >&2
    exit 1
  fi
}

migrate_volume() {
  local label="$1"
  local target_configured="$2"
  shift 2

  local source_volume=""
  local target_path=""

  source_volume="$(resolve_volume "$@" || true)"
  if [[ -z "$source_volume" ]]; then
    echo "[SKIP] ${label}: nenhum volume antigo encontrado (${*})."
    return 0
  fi

  target_path="$(resolve_target_path "$target_configured")"
  mkdir -p "$target_path"

  if find "$target_path" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    echo "ERRO: destino de '${label}' já contém dados: ${target_path}" >&2
    echo "Nenhum arquivo foi sobrescrito. Verifique o destino manualmente." >&2
    exit 1
  fi

  echo "[COPY] ${label}: ${source_volume} -> ${target_path}"
  docker run --rm \
    -v "${source_volume}:/from:ro" \
    -v "${target_path}:/to" \
    "$helper_image" \
    sh -ec 'cd /from && tar cpf - . | (cd /to && tar xpf -)'

  if ! find "$target_path" -mindepth 1 -print -quit | grep -q .; then
    echo "ERRO: a cópia de '${label}' terminou sem arquivos no destino." >&2
    exit 1
  fi

  echo "[OK]   ${label} migrado. Volume antigo preservado: ${source_volume}"
}

project_name="$(value_or_default COMPOSE_PROJECT_NAME "$default_project")"
ensure_stack_stopped

hub_storage_volume="$(value_or_default HUB_STORAGE_VOLUME_NAME "$default_storage_volume")"
hub_postgres_volume="$(value_or_default HUB_POSTGRES_VOLUME_NAME "$default_postgres_volume")"
hub_redis_volume="$(value_or_default HUB_REDIS_VOLUME_NAME "$default_redis_volume")"

hub_storage_path="$(value_or_default HUB_STORAGE_DATA_PATH './volumes/storage')"
hub_postgres_path="$(value_or_default HUB_POSTGRES_DATA_PATH './volumes/postgres')"
hub_redis_path="$(value_or_default HUB_REDIS_DATA_PATH './volumes/redis')"

migrate_volume "HUB storage" "$hub_storage_path" "$hub_storage_volume"
migrate_volume "HUB PostgreSQL" "$hub_postgres_path" "$hub_postgres_volume"
migrate_volume "HUB Redis" "$hub_redis_path" "$hub_redis_volume"

if [[ "$embedded" == true ]]; then
  migrate_volume \
    "Connect|API instances" \
    "$(value_or_default ARGWS_CONNECT_INSTANCES_DATA_PATH './volumes/connect-api/instances')" \
    "${project_name}_connect_instances" \
    "connect_instances"

  migrate_volume \
    "Connect|API PostgreSQL" \
    "$(value_or_default ARGWS_CONNECT_POSTGRES_DATA_PATH './volumes/connect-api/postgres')" \
    "${project_name}_connect_postgres" \
    "connect_postgres"

  migrate_volume \
    "Connect|API Redis" \
    "$(value_or_default ARGWS_CONNECT_REDIS_DATA_PATH './volumes/connect-api/redis')" \
    "${project_name}_connect_redis" \
    "connect_redis"

  migrate_volume \
    "Connect|API RabbitMQ" \
    "$(value_or_default ARGWS_CONNECT_RABBITMQ_DATA_PATH './volumes/connect-api/rabbitmq')" \
    "${project_name}_connect_rabbitmq" \
    "connect_rabbitmq"

  migrate_volume \
    "Connect|API MinIO" \
    "$(value_or_default ARGWS_CONNECT_MINIO_DATA_PATH './volumes/connect-api/minio')" \
    "${project_name}_connect_minio" \
    "connect_minio"

  migrate_volume \
    "Connect|API NATS" \
    "$(value_or_default ARGWS_CONNECT_NATS_DATA_PATH './volumes/connect-api/nats')" \
    "${project_name}_connect_nats" \
    "connect_nats"

  migrate_volume \
    "Connect|API Zookeeper data" \
    "$(value_or_default ARGWS_CONNECT_ZOOKEEPER_DATA_PATH './volumes/connect-api/zookeeper/data')" \
    "${project_name}_connect_zookeeper_data" \
    "connect_zookeeper_data"

  migrate_volume \
    "Connect|API Zookeeper log" \
    "$(value_or_default ARGWS_CONNECT_ZOOKEEPER_LOG_PATH './volumes/connect-api/zookeeper/log')" \
    "${project_name}_connect_zookeeper_log" \
    "connect_zookeeper_log"

  migrate_volume \
    "Connect|API Kafka" \
    "$(value_or_default ARGWS_CONNECT_KAFKA_DATA_PATH './volumes/connect-api/kafka')" \
    "${project_name}_connect_kafka" \
    "connect_kafka"
fi

cat <<EOF

Migração concluída para: ${variant}
Diretório da stack: ${stack_dir}

Os volumes Docker antigos foram mantidos e podem ser usados como rollback.
Valide a nova stack antes de removê-los manualmente.
EOF
