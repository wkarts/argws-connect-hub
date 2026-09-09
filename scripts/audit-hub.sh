#!/usr/bin/env sh
set -eu
fail=0
say_fail() { echo "HUB AUDIT: $1" >&2; fail=1; }

# No third-party runtime analytics/telemetry/APM is allowed in shipped application code.
# -I prevents binary payloads (Chromium/Qt/assets) from being interpreted as source text.
if grep -RniIE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=chromium \
  'posthog|@june-so|@sentry|sentry-ruby|Sentry\.|datadog|ddtrace|newrelic|elastic[-_]?apm|scout_apm|appsignal|honeybadger|rollbar-ruby|Rollbar\.|bugsnag|mixpanel|amplitude|google[-_ ]analytics|googletagmanager|gtag\(|facebook[-_ ]pixel|analytics-next|statsd-ruby|(^|[^[:alnum:]_])barnes([^[:alnum:]_]|$)' \
  app config lib package.json Gemfile Gemfile.lock .env.example 2>/dev/null; then
  say_fail 'telemetria/analytics/APM de terceiros encontrada no runtime ou dependências diretas'
fi

# Lockfiles may not reintroduce runtime analytics SDKs transitively.
# Storybook is dev-only and its own telemetry package is tolerated only because
# the HUB forces Storybook telemetry off in both config and runner.
if grep -niIE \
  'posthog|@june-so|@sentry|datadog|ddtrace|newrelic|elastic[-_]?apm|scout_apm|appsignal|honeybadger|rollbar|bugsnag|mixpanel|amplitude|analytics-next|statsd-ruby|(^|[^[:alnum:]_])barnes([^[:alnum:]_]|$)' \
  yarn.lock Gemfile.lock 2>/dev/null; then
  say_fail 'SDK de telemetria/APM de runtime encontrado em lockfile'
fi

# Storybook is part of the local component-development environment, not product telemetry.
# If it is present, its telemetry must remain forcibly disabled.
if grep -q '"@storybook/' package.json 2>/dev/null; then
  [ -f .storybook/main.js ] || say_fail 'Storybook habilitado sem configuração local'
  [ -f scripts/storybook-runner.js ] || say_fail 'Storybook habilitado sem runner privacy-safe'
  grep -q 'disableTelemetry: true' .storybook/main.js || say_fail 'Storybook telemetry não está desabilitada em main.js'
  grep -q 'STORYBOOK_DISABLE_TELEMETRY' .storybook/main.js || say_fail 'Storybook não define a flag de privacidade no config'
  grep -q 'STORYBOOK_DISABLE_TELEMETRY' scripts/storybook-runner.js || say_fail 'runner do Storybook não força telemetria desabilitada'
fi

# Legacy product analytics plumbing must not survive as no-op shims.
if grep -RniIE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=i18n --exclude-dir=chromium \
  'AnalyticsHelper|AnalyticsPlugin|ANALYTICS_IDENTITY|ANALYTICS_RESET|\$track([.(]|$)|useTrack|analyticsHelper|analytics_plugin' \
  app config lib 2>/dev/null; then
  say_fail 'infraestrutura legada de analytics ainda presente'
fi

# HUB has no vendor registration/usage endpoint. Platform metadata remains local-only.
if grep -RniIE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=chromium \
  'HUB_PLATFORM_URL|(^|[^A-Z_])DISABLE_TELEMETRY([^A-Z_]|$)|register_installation|send_telemetry|usage_report' \
  app config lib .env.example 2>/dev/null; then
  say_fail 'registro remoto/telemetria de plataforma encontrado'
fi

# Product-owned runtime/UI/docs must not expose the former product brand.
legacy_brand="$(printf '%s%s%s' 'cha' 'two' 'ot')"
legacy_short="$(printf '%s%s' 'wo' 'ot')"
if grep -RniIE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=spec --exclude-dir=test --exclude-dir=chromium \
  --exclude='Gemfile' --exclude='Gemfile.lock' --exclude='yarn.lock' --exclude='package.json' --exclude='LICENSE' --exclude='THIRD_PARTY_NOTICES.md' --exclude='audit-hub.sh' --exclude='validate-hub-ci.sh' \
  "${legacy_brand}|${legacy_short}[_-]|[^[:alnum:]_]${legacy_short}[^[:alnum:]_]" app config lib docs public scripts swagger theme stories 2>/dev/null; then
  say_fail 'marca legada encontrada em código/UI/documentação do HUB'
fi


# Shipped HUB runtime must not depend on placeholder HUB domains or old product short-links.
if grep -RniIE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=spec --exclude-dir=specs --exclude-dir=test --exclude-dir=stories --exclude-dir=chromium \
  --exclude='Gemfile.lock' --exclude='yarn.lock' --exclude='LICENSE' --exclude='THIRD_PARTY_NOTICES.md' --exclude='audit-hub.sh' \
  'https?://([^/]*\.)?hub\.com|https?://chwt\.app' app config lib public scripts 2>/dev/null; then
  say_fail 'URL remota legada/fictícia encontrada no runtime do HUB'
fi

# Published/runtime images are GHCR and AMD64 only.
if grep -RniIE 'docker\.io|dockerhub|hub/hub|linux/arm64|platforms:.*arm64|^[[:space:]]*image:[[:space:]]*(postgres|redis|mailhog)/?' \
  .github docker-compose*.y*ml docker .devcontainer 2>/dev/null; then
  say_fail 'DockerHub/imagem não-GHCR ou ARM64 encontrado na superfície de build/deploy'
fi

# Proprietary enterprise tree must not ship.
[ ! -d enterprise ] || say_fail 'diretório enterprise presente no pacote redistribuível'

[ "$fail" -eq 0 ] || exit 1
echo 'HUB AUDIT: OK'
