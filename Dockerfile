# syntax=docker/dockerfile:1
# ----------------------------------------------------------------------------
# LUMECraft first-person-shooter — single-container deploy for Render.
# Builds the Meteor 3 app and bundles MongoDB into the same image so no
# external database is required (data is ephemeral — fine for a demo).
# ----------------------------------------------------------------------------

############################
# Stage 1: build the app   #
############################
FROM node:20-bookworm AS build

# Build toolchain Meteor + native npm modules need
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates python3 g++ make git procps bash \
    && rm -rf /var/lib/apt/lists/*

# Install the exact Meteor release this project pins (.meteor/release)
ENV METEOR_ALLOW_SUPERUSER=true
RUN curl -fsSL "https://install.meteor.com/?release=3.0.3" | sh
ENV PATH="/root/.meteor:${PATH}"

WORKDIR /app

# Install dependencies first (better layer caching)
COPY package.json ./
RUN meteor npm install

# Bring in the rest of the source and compile (src/ -> dist/ via @lume/cli)
COPY . .
RUN meteor npm run build

# Produce a self-contained, server-only production bundle
RUN meteor build --directory /output --server-only --allow-superuser

############################
# Stage 2: runtime image   #
############################
FROM node:20-bookworm-slim AS run

# Install MongoDB server (embedded DB) + tini for clean signal handling
RUN apt-get update && apt-get install -y --no-install-recommends \
      gnupg curl ca-certificates tini \
    && curl -fsSL https://pgp.mongodb.com/server-7.0.asc \
       | gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor \
    && echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] http://repo.mongodb.org/apt/debian bookworm/mongodb-org/7.0 main" \
       > /etc/apt/sources.list.d/mongodb-org-7.0.list \
    && apt-get update && apt-get install -y --no-install-recommends mongodb-org-server \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the built Meteor bundle and install its server deps
COPY --from=build /output/bundle /app
RUN cd /app/programs/server && npm install --omit=dev

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENV NODE_ENV=production
# Render injects PORT at runtime (defaults to 10000 for Docker web services)
EXPOSE 10000

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
