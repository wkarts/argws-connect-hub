# HUB immutable runtime base.
# Keep this image smaller than the build base and version it independently from HUB releases.
ARG HUB_UPSTREAM_BASE_IMAGE=ghcr.io/linuxcontainers/alpine:3.20
FROM ${HUB_UPSTREAM_BASE_IMAGE}

ARG BUNDLER_VERSION=2.5.16
ARG BASE_DEFINITION_SHA=unknown

LABEL org.opencontainers.image.title="HUB Runtime Base" \
      org.opencontainers.image.description="Immutable runtime dependencies for ARGWS Connect HUB" \
      org.opencontainers.image.source="https://github.com/wkarts/argws-connect-hub" \
      org.argws.hub.base.kind="runtime" \
      org.argws.hub.base.definition-sha="${BASE_DEFINITION_SHA}"

ENV BUNDLER_VERSION=${BUNDLER_VERSION}
ENV BUNDLE_PATH=/gems

RUN apk update && apk add --no-cache \
      ruby openssl tzdata postgresql-client imagemagick vips \
    && ruby --version \
    && gem install bundler -v "${BUNDLER_VERSION}" --no-document \
    && mkdir -p /app /gems \
    && rm -rf /var/cache/apk/*

WORKDIR /app
