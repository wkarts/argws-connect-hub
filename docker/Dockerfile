# HUB build/runtime base. GHCR-only and AMD64 at workflow level.
# Alpine 3.20 provides the Ruby 3.3 line used by HUB.
ARG HUB_RUBY_BASE_IMAGE=ghcr.io/linuxcontainers/alpine:3.20
FROM ${HUB_RUBY_BASE_IMAGE} AS pre-builder

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

RUN apk update && apk add --no-cache \
  ruby ruby-dev openssl tar build-base tzdata postgresql-dev postgresql-client \
  nodejs yarn git musl gcc make musl-dev openssl-dev g++ linux-headers xz vips-dev \
  && ruby --version \
  && mkdir -p /var/app \
  && gem install bundler -v "$BUNDLER_VERSION"

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local force_ruby_platform true
# Resolve the protobuf patch release explicitly so Alpine/musl never falls back to 3.25.3.
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

# Compile the actual production bundle. This is a required CI gate, never bypassed.
RUN if [ "$RAILS_ENV" = "production" ]; then \
      SECRET_KEY_BASE=precompile_placeholder \
      RAILS_LOG_TO_STDOUT=enabled \
      bundle exec rake assets:precompile \
      && rm -rf spec node_modules tmp/cache; \
    fi

# Build metadata must work from source ZIPs where .git is intentionally absent.
ARG GIT_SHA=release
RUN printf '%s\n' "${GIT_SHA}" > /app/.git_sha

RUN apk del --no-cache build-base musl gcc musl-dev openssl-dev g++ linux-headers xz vips-dev \
  && rm -rf /var/cache/apk/* \
  && rm -rf /gems/ruby/3.3.0/cache/*.gem \
  && find /gems/ruby/3.3.0/gems/ \( -name "*.c" -o -name "*.o" \) -delete \
  && rm -rf .git \
  && rm -f .gitignore

FROM ${HUB_RUBY_BASE_IMAGE}

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

RUN apk update && apk add --no-cache \
  ruby openssl tzdata postgresql-client imagemagick git vips \
  && ruby --version \
  && gem install bundler -v "$BUNDLER_VERSION"

RUN if [ "$RAILS_ENV" != "production" ]; then apk add --no-cache nodejs yarn; fi

COPY --from=pre-builder /gems/ /gems/
COPY --from=pre-builder /app /app
WORKDIR /app
RUN chmod -R 755 ./docker
EXPOSE 3000
