# Everything builds inside Docker: no Node, Yarn or node_modules on the host.
# Based on https://backstage.io/docs/deployment/docker#multi-stage-build

# Stage 1: only the package.json files, so the install layer caches.
FROM node:24-trixie-slim AS packages
WORKDIR /app
COPY backstage.json package.json yarn.lock .yarnrc.yml ./
COPY .yarn ./.yarn
COPY packages packages
RUN find packages \! -name "package.json" -mindepth 2 -maxdepth 2 -exec rm -rf {} \+

# Stage 2: install, type-check, build the backend bundle (serves the app too).
FROM node:24-trixie-slim AS build
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends python3 g++ build-essential libsqlite3-dev
USER node
WORKDIR /app
COPY --from=packages --chown=node:node /app .
RUN --mount=type=cache,target=/home/node/.cache/yarn,sharing=locked,uid=1000,gid=1000 \
    yarn install --immutable
COPY --chown=node:node . .
ENV NODE_OPTIONS=--max-old-space-size=4096
RUN yarn tsc && yarn --cwd packages/backend build
RUN mkdir packages/backend/dist/skeleton packages/backend/dist/bundle \
    && tar xzf packages/backend/dist/skeleton.tar.gz -C packages/backend/dist/skeleton \
    && tar xzf packages/backend/dist/bundle.tar.gz -C packages/backend/dist/bundle

# Stage 3: runtime.
FROM node:24-trixie-slim
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends libsqlite3-dev && \
    rm -rf /var/lib/apt/lists/*
USER node
WORKDIR /app
ENV NODE_ENV=production
# Only the Yarn binary: the build stage's .yarn/install-state.gz would make
# `focus` believe it has already installed and leave node_modules empty.
COPY --from=build --chown=node:node /app/.yarn/releases ./.yarn/releases
COPY --from=build --chown=node:node /app/.yarnrc.yml /app/backstage.json /app/yarn.lock /app/package.json ./
COPY --from=build --chown=node:node /app/packages/backend/dist/skeleton/ ./
RUN --mount=type=cache,target=/home/node/.cache/yarn,sharing=locked,uid=1000,gid=1000 \
    yarn workspaces focus --all --production
COPY --from=build --chown=node:node /app/packages/backend/dist/bundle/ ./
COPY --chown=node:node app-config*.yaml ./
# ENTRA_ENABLED=true also loads app-config.entra.yaml (the backend reads the
# same variable to load the Entra plugins).
CMD ["sh", "-c", "exec node packages/backend --config app-config.yaml --config app-config.production.yaml --config app-config.docker.yaml $([ \"$ENTRA_ENABLED\" = true ] && echo --config app-config.entra.yaml)"]
