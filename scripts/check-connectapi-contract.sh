#!/usr/bin/env sh
set -eu
ROOT="${1:-${CONNECT_API_SOURCE:-}}"
[ -n "$ROOT" ] || { echo "Uso: $0 /caminho/ARGWS-Connect-API" >&2; exit 2; }
fail=0
check() { file="$1"; pattern="$2"; label="$3"; if ! grep -qE "$pattern" "$ROOT/$file"; then echo "FALHA: $label" >&2; fail=1; else echo "OK: $label"; fi; }
check src/api/routes/index.router.ts "use\('/graph'" "Graph Meta-compatible /graph"
check src/api/routes/index.router.ts "use\('/compat/meta'" "Admin Meta-compatible /compat/meta"
check src/api/compat/meta-cloud/meta-cloud-graph.router.ts ":phoneNumberId/messages" "Envio Meta-compatible"
check src/api/compat/meta-cloud/meta-cloud-graph.router.ts ":phoneNumberId/media" "Upload de mídia"
check src/api/compat/meta-cloud/meta-cloud-graph.router.ts ":businessAccountId/message_templates" "Templates"
check src/api/compat/meta-cloud/meta-cloud.router.ts "put\(" "Configuração Meta-compatible"
check src/api/routes/instance.router.ts "routerPath\('connect'\)" "Conexão QR/pareamento"
check src/api/routes/instance.router.ts "routerPath\('connectionState'\)" "Status da instância"
check src/api/routes/instance.router.ts "routerPath\('logout'\)" "Logout da instância"
[ "$fail" -eq 0 ] || exit 1
echo "Connect|API contract: OK"
