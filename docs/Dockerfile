# syntax = docker/dockerfile:1
#
# The docs app depends on the gem via `gem "sidekiq-unique-jobs", path: ".."`, so the build
# context is the REPO ROOT (not docs/): the gem lives at /app and the docs app at
# /app/docs. Build with `docker build -f docs/Dockerfile .` from the repo root,
# or via Kamal's builder `context: ..` + `dockerfile: docs/Dockerfile`.

ARG RUBY_VERSION=4.0.5
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

ARG BUN_VERSION=1.3.2
ENV BUN_INSTALL="/usr/local/bun"
ENV PATH="/usr/local/bun/bin:$PATH"

WORKDIR /app/docs

ENV BUNDLE_DEPLOYMENT="0" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_GEMFILE="/app/docs/Gemfile" \
    RAILS_ENV="production"

RUN gem update --system --no-document && gem install -N bundler


# --- Build stage --------------------------------------------------------------
FROM base AS build

# build-essential + libyaml-dev to compile native gems (nokogiri arrives via the
# icons gem) when a precompiled variant isn't used; git so the gem's gemspec
# (`git ls-files`) resolves the path dependency; unzip for the Bun installer.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential curl git libyaml-dev pkg-config unzip

# Bun runs the Tailwind CSS v4 CLI (bun run build:css).
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"

# Copy the WHOLE repo first (gem at /app, docs app at /app/docs). The gem is a
# path dependency whose gemspec prefers `git ls-files`, so the full checkout
# (incl. .git) must be present before bundle install resolves it — the repo-root
# .dockerignore deliberately keeps .git in the context.
COPY . /app/

# Frozen off: the path-gem's git-ls-files gemspec digest can't be pinned across
# commits; the lockfile still pins every other gem. Prune the bundler cache +
# any git-sourced gem checkouts so they don't bloat the layer the final stage
# copies.
RUN bundle config set frozen false && bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# JS deps (Tailwind CLI + daisyUI), then assets:precompile — enhanced by the
# css:build rake task so it runs `bun run build:css` before propshaft fingerprints.
# Drop node_modules + the bun/asset caches afterwards — only the built CSS is
# kept, so the final stage's COPY of /app never carries the JS deps.
RUN bun install --frozen-lockfile
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    rm -rf node_modules /usr/local/bun tmp/cache


# --- Final stage --------------------------------------------------------------
FROM base

# Kamal verifies this `service` label on deploy; it MUST equal `service:` in
# config/deploy.yml. Kept here so a plain `docker build` also produces a
# Kamal-deployable image.
LABEL service="sidekiq-unique-jobs"

# curl for the healthcheck. git is kept for RUNTIME too: Bundler re-evaluates the
# path-gem's gemspec on boot; sidekiq-unique-jobs.gemspec prefers `git ls-files`
# (it has a Dir glob fallback, but the git-backed list is the accurate one).
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl git && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /app /app

# Non-root runtime user; owns the writable dirs.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R 1000:1000 /app/docs/log /app/docs/tmp
USER 1000:1000

EXPOSE 3000
# Thruster fronts Puma (HTTP caching + compression + X-Sendfile). It listens on
# HTTP_PORT and proxies to Puma on TARGET_PORT (it sets PORT for the child, which
# config/puma.rb reads). HTTP_PORT MUST be the port traffic is routed to (Kamal's
# `app_port: 3000` in config/deploy.yml, the EXPOSE above).
ENV HTTP_PORT="3000" \
    TARGET_PORT="3001"
CMD ["./bin/thrust", "./bin/rails", "server"]
