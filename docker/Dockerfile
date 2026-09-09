# HUB application image.
# OS/toolchain and dependency installation live in immutable HUB base images.
ARG HUB_DEPS_BASE_IMAGE=ghcr.io/wkarts/argws-connect-hub-deps-base:1.1.0
ARG HUB_RUNTIME_BASE_IMAGE=ghcr.io/wkarts/argws-connect-hub-runtime-base:1.1.0

FROM ${HUB_DEPS_BASE_IMAGE} AS pre-builder

ARG BUNDLE_WITHOUT="development:test"
ARG RAILS_SERVE_STATIC_FILES=true
ARG RAILS_ENV=production
ARG NODE_OPTIONS="--openssl-legacy-provider"
ARG GIT_SHA=release
ARG HUB_VERSION=0.0.0

ENV BUNDLE_WITHOUT=${BUNDLE_WITHOUT} \
    BUNDLER_VERSION=2.5.16 \
    RAILS_SERVE_STATIC_FILES=${RAILS_SERVE_STATIC_FILES} \
    RAILS_ENV=${RAILS_ENV} \
    NODE_OPTIONS=${NODE_OPTIONS} \
    BUNDLE_PATH=/gems \
    HUSKY=0

WORKDIR /app
COPY . /app
RUN mkdir -p /app/log

# The dependency base contains the superset required by develop and release.
# Production removes development/test gems only after copying the immutable layer.
RUN if [ "$RAILS_ENV" = "production" ]; then \
      bundle config set without 'development test'; \
      bundle clean --force; \
      SECRET_KEY_BASE=precompile_placeholder \
      RAILS_LOG_TO_STDOUT=enabled \
      bundle exec rake assets:precompile; \
      rm -rf spec node_modules tmp/cache; \
    fi

RUN printf '%s\n' "${GIT_SHA}" > /app/.git_sha \
 && printf '%s\n' "${HUB_VERSION}" > /app/.hub_version \
 && rm -rf /gems/ruby/3.3.0/cache/*.gem \
 && find /gems/ruby/3.3.0/gems/ \( -name "*.c" -o -name "*.o" \) -delete \
 && rm -rf .git \
 && rm -f .gitignore

FROM ${HUB_RUNTIME_BASE_IMAGE}

ARG BUNDLE_WITHOUT="development:test"
ARG EXECJS_RUNTIME="Disabled"
ARG RAILS_SERVE_STATIC_FILES=true
ARG BUNDLE_FORCE_RUBY_PLATFORM=1
ARG RAILS_ENV=production
ARG HUB_VERSION=0.0.0

ENV BUNDLE_WITHOUT=${BUNDLE_WITHOUT} \
    BUNDLER_VERSION=2.5.16 \
    EXECJS_RUNTIME=${EXECJS_RUNTIME} \
    RAILS_SERVE_STATIC_FILES=${RAILS_SERVE_STATIC_FILES} \
    BUNDLE_FORCE_RUBY_PLATFORM=${BUNDLE_FORCE_RUBY_PLATFORM} \
    RAILS_ENV=${RAILS_ENV} \
    HUB_BUILD_VERSION=${HUB_VERSION} \
    BUNDLE_PATH=/gems

COPY --from=pre-builder /gems/ /gems/
COPY --from=pre-builder /app /app
WORKDIR /app
RUN chmod -R 755 ./docker
EXPOSE 3000
