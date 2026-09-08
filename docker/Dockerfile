# HUB application image.
# Build/runtime operating-system dependencies live in immutable, independently versioned HUB base images.
ARG HUB_BUILD_BASE_IMAGE=ghcr.io/wkarts/argws-connect-hub-build-base:1.0.0
ARG HUB_RUNTIME_BASE_IMAGE=ghcr.io/wkarts/argws-connect-hub-runtime-base:1.0.0

FROM ${HUB_BUILD_BASE_IMAGE} AS pre-builder

ARG BUNDLE_WITHOUT="development:test"
ENV BUNDLE_WITHOUT=${BUNDLE_WITHOUT}
ENV BUNDLER_VERSION=2.5.16

ARG RAILS_SERVE_STATIC_FILES=true
ENV RAILS_SERVE_STATIC_FILES=${RAILS_SERVE_STATIC_FILES}

ARG RAILS_ENV=production
ENV RAILS_ENV=${RAILS_ENV}

ARG NODE_OPTIONS="--openssl-legacy-provider"
ENV NODE_OPTIONS=${NODE_OPTIONS}
ENV BUNDLE_PATH="/gems"

WORKDIR /app

# Dependency layers are intentionally isolated from application source changes.
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local force_ruby_platform true
# Preserve the existing HUB protobuf compatibility rule.
RUN bundle lock --update google-protobuf
RUN if [ "$RAILS_ENV" = "production" ]; then \
      bundle config set without 'development test'; bundle install -j "$(nproc)" -r 3; \
    else \
      bundle install -j "$(nproc)" -r 3; \
    fi

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile --network-concurrency 1 --network-timeout 600000

COPY . /app
RUN mkdir -p /app/log

# Production assets are compiled only for the image that will actually be distributed.
RUN if [ "$RAILS_ENV" = "production" ]; then \
      SECRET_KEY_BASE=precompile_placeholder \
      RAILS_LOG_TO_STDOUT=enabled \
      bundle exec rake assets:precompile \
      && rm -rf spec node_modules tmp/cache; \
    fi

# Build metadata must work from source ZIPs where .git is intentionally absent.
ARG GIT_SHA=release
RUN printf '%s\n' "${GIT_SHA}" > /app/.git_sha

# Clean only artifacts copied into the runtime image. Build packages stay in the immutable build base.
RUN rm -rf /gems/ruby/3.3.0/cache/*.gem \
  && find /gems/ruby/3.3.0/gems/ \( -name "*.c" -o -name "*.o" \) -delete \
  && rm -rf .git \
  && rm -f .gitignore

FROM ${HUB_RUNTIME_BASE_IMAGE}

ARG BUNDLE_WITHOUT="development:test"
ENV BUNDLE_WITHOUT=${BUNDLE_WITHOUT}
ENV BUNDLER_VERSION=2.5.16
ARG EXECJS_RUNTIME="Disabled"
ENV EXECJS_RUNTIME=${EXECJS_RUNTIME}
ARG RAILS_SERVE_STATIC_FILES=true
ENV RAILS_SERVE_STATIC_FILES=${RAILS_SERVE_STATIC_FILES}
ARG BUNDLE_FORCE_RUBY_PLATFORM=1
ENV BUNDLE_FORCE_RUBY_PLATFORM=${BUNDLE_FORCE_RUBY_PLATFORM}
ARG RAILS_ENV=production
ENV RAILS_ENV=${RAILS_ENV}
ENV BUNDLE_PATH="/gems"

COPY --from=pre-builder /gems/ /gems/
COPY --from=pre-builder /app /app
WORKDIR /app
RUN chmod -R 755 ./docker
EXPOSE 3000
