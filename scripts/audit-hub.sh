#!/usr/bin/env sh
set -eu
fail=0
say_fail() { echo "HUB AUDIT: $1" >&2; fail=1; }

# No third-party analytics/telemetry/APM is allowed anywhere in the shipped source.
# Lockfiles are included so transitive SDKs cannot silently return.
if grep -RniaE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor \
  'posthog|@june-so|@sentry|sentry-ruby|Sentry\.|datadog|ddtrace|newrelic|elastic[-_]?apm|scout_apm|appsignal|honeybadger|rollbar-ruby|Rollbar\.|bugsnag|mixpanel|amplitude|google[-_ ]analytics|googletagmanager|gtag\(|facebook[-_ ]pixel|analytics-next|statsd-ruby|(^|[^[:alnum:]_])barnes([^[:alnum:]_]|$)|@storybook/telemetry' \
  app config lib package.json yarn.lock Gemfile Gemfile.lock .env.example 2>/dev/null; then
  say_fail 'telemetria/analytics/APM de terceiros encontrada no código ou dependências'
fi

# Legacy analytics plumbing must not survive as no-op shims.
if grep -RniaE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=i18n \
  'AnalyticsHelper|AnalyticsPlugin|ANALYTICS_IDENTITY|ANALYTICS_RESET|\$track([.(]|$)|useTrack|analyticsHelper|analytics_plugin' \
  app config lib 2>/dev/null; then
  say_fail 'infraestrutura legada de analytics ainda presente'
fi

# HUB has no vendor registration/telemetry endpoint. Platform metadata must remain local-only.
if grep -RniaE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor \
  'HUB_PLATFORM_URL|DISABLE_TELEMETRY|register_instance|register_installation|emit_event|send_telemetry|usage_report' \
  app config lib .env.example 2>/dev/null; then
  say_fail 'registro remoto/telemetria de plataforma encontrado'
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


# Proprietary enterprise tree must not ship.
[ ! -d enterprise ] || say_fail 'diretório enterprise presente no pacote redistribuível'

[ "$fail" -eq 0 ] || exit 1
echo 'HUB AUDIT: OK'
