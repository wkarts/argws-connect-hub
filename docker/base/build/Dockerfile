# HUB immutable build base.
# This image has its own lifecycle and must only change when docker/base/VERSION is bumped.
ARG HUB_UPSTREAM_BASE_IMAGE=ghcr.io/linuxcontainers/alpine:3.20
FROM ${HUB_UPSTREAM_BASE_IMAGE}

ARG BUNDLER_VERSION=2.5.16
ARG BASE_DEFINITION_SHA=unknown

LABEL org.opencontainers.image.title="HUB Build Base" \
      org.opencontainers.image.description="Immutable build toolchain for ARGWS Connect HUB" \
      org.argws.hub.base.kind="build" \
      org.argws.hub.base.definition-sha="${BASE_DEFINITION_SHA}"

ENV BUNDLER_VERSION=${BUNDLER_VERSION}
ENV BUNDLE_PATH=/gems

RUN apk update && apk add --no-cache \
      ruby ruby-dev openssl tar build-base tzdata postgresql-dev postgresql-client \
      nodejs yarn git musl gcc make musl-dev openssl-dev g++ linux-headers xz vips-dev \
    && ruby --version \
    && gem install bundler -v "${BUNDLER_VERSION}" --no-document \
    && mkdir -p /app /gems \
    && rm -rf /var/cache/apk/*

WORKDIR /app
