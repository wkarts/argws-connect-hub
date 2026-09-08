#!/usr/bin/env sh
set -eu
fail=0
say_fail() { echo "HUB AUDIT: $1" >&2; fail=1; }

# Active runtime/build must not contain private analytics/APM SDKs.
if grep -RniaE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=spec --exclude-dir=test --exclude='Gemfile.lock' --exclude='yarn.lock' \
  'posthog|@june-so|@sentry|Sentry\.|datadog|ddtrace|newrelic|elastic.?apm|scout_apm|mixpanel|amplitude|google.?analytics|googletagmanager|gtag\(|facebook.?pixel|analytics-next' \
  app config lib package.json Gemfile .env.example 2>/dev/null; then
  say_fail 'telemetria/analytics de terceiros encontrada no runtime/build'
fi


# Product-owned runtime/UI/docs must not expose the former product brand.
legacy_brand="$(printf '%s%s%s' 'cha' 'two' 'ot')"
legacy_short="$(printf '%s%s' 'wo' 'ot')"
if grep -RniaE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=spec --exclude-dir=test \
  --exclude='Gemfile' --exclude='Gemfile.lock' --exclude='yarn.lock' --exclude='package.json' --exclude='LICENSE' --exclude='THIRD_PARTY_NOTICES.md' --exclude='audit-hub.sh' \
  "${legacy_brand}|${legacy_short}[_-]|[^[:alnum:]_]${legacy_short}[^[:alnum:]_]" app config lib docs public scripts swagger theme stories 2>/dev/null; then
  say_fail 'marca legada encontrada em código/UI/documentação do HUB'
fi

# Published/runtime images are GHCR and AMD64 only.
if grep -RniE 'docker\.io|dockerhub|hub/hub|linux/arm64|platforms:.*arm64' .github docker-compose*.y*ml docker .devcontainer 2>/dev/null; then
  say_fail 'DockerHub ou ARM64 encontrado na superfície de build/deploy'
fi

# No active UnoAPI provider; historical migration is explicitly allowed.
if grep -RniE --exclude='20260908000000_migrate_unoapi_channels_to_connectapi.rb' 'unoapi|Unoapi|UNOAPI' app config lib 2>/dev/null; then
  say_fail 'UnoAPI ativo encontrado; HUB deve expor somente Connect|API para WhatsApp'
fi

# Proprietary enterprise tree must not ship.
[ ! -d enterprise ] || say_fail 'diretório enterprise presente no pacote redistribuível'

[ "$fail" -eq 0 ] || exit 1
echo 'HUB AUDIT: OK'
