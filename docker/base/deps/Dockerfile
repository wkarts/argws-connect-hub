# HUB immutable dependency base.
# Rebuild only when dependency locks, Gemfile semantics, local HUB packages, or docker/base/VERSION change.
ARG HUB_BUILD_BASE_IMAGE=ghcr.io/wkarts/argws-connect-hub-build-base:1.1.0
FROM ${HUB_BUILD_BASE_IMAGE}

ARG BASE_DEFINITION_SHA=unknown
ARG BUNDLER_VERSION=2.5.16

LABEL org.opencontainers.image.title="HUB Dependency Base" \
      org.opencontainers.image.description="Immutable Ruby and JavaScript dependency layer for HUB" \
      org.opencontainers.image.source="https://github.com/wkarts/argws-connect-hub" \
      org.argws.hub.base.kind="deps" \
      org.argws.hub.base.definition-sha="${BASE_DEFINITION_SHA}"

ENV BUNDLER_VERSION=${BUNDLER_VERSION} \
    BUNDLE_PATH=/gems \
    HUSKY=0 \
    NODE_ENV=development

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local force_ruby_platform true \
 && bundle install -j "$(nproc)" -r 3 \
 && rm -rf /gems/ruby/3.3.0/cache/*.gem

# Only dependency-related package.json fields are kept in this image. This prevents
# an application SemVer bump from changing the dependency base.
COPY package.json /tmp/hub-package.json
COPY yarn.lock ./
COPY packages ./packages
RUN node - <<'NODE'
const fs = require('fs');
const source = JSON.parse(fs.readFileSync('/tmp/hub-package.json', 'utf8'));
const normalized = {
  name: '@hub/dependency-base',
  private: true,
  dependencies: source.dependencies || {},
  devDependencies: source.devDependencies || {},
  resolutions: source.resolutions || {},
  engines: source.engines || {},
};
fs.writeFileSync('/app/package.json', `${JSON.stringify(normalized, null, 2)}\n`);
NODE
RUN yarn install --frozen-lockfile --ignore-scripts --network-concurrency 1 --network-timeout 600000 \
 && yarn cache clean \
 && rm -f /tmp/hub-package.json

RUN mkdir -p /app/log
