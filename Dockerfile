# syntax=docker/dockerfile:1
#
# Self-building Probo image for platforms without access to the prebuilt
# release binaries (e.g. Render building directly from a fork).
# Replicates `make build WITH_APPS=1` for the two server binaries:
#   - probod (API + embedded web console + compliance/employee portals)
#   - probod-bootstrap (renders /etc/probod/config.yml from PROBOD_* env vars)
#
# The original assemble-only Dockerfile (expects prebuilt bin/<platform>/
# binaries from the release pipeline) is kept at Dockerfile.release.

# ── Builder: Go 1.27 + Node 24 (npm 12) per README prerequisites ─────
FROM golang:1.27 AS builder

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl \
	&& curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
	&& apt-get install -y --no-install-recommends nodejs \
	&& npm install -g npm@12 \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Copy go.mod/go.mod-adjacent manifests first for layer caching.
COPY go.mod go.sum ./
COPY package.json package-lock.json .npmrc ./
COPY apps ./apps
COPY packages ./packages
COPY examples ./examples
RUN npm ci

COPY . .

# Build only the server binaries (skips prb/proboctl/probo-agent).
# WITH_APPS=1 runs codegen (gqlgen/mcpgen/relay) and production frontend
# builds (console, compliance-portal, employee-portal, emails) before
# compiling probod with the embedded dist assets.
RUN make bin/probod bin/probod-bootstrap WITH_APPS=1

# ── Runtime: same shape as Dockerfile.release ─────────────────────────
FROM ubuntu:24.04

RUN useradd -m probo \
	&& apt-get update \
	&& apt-get upgrade -y \
	&& apt-get install -y --no-install-recommends ca-certificates libcap2-bin \
	&& rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/bin/probod /usr/local/bin/probod
COPY --from=builder /src/bin/probod-bootstrap /usr/local/bin/probod-bootstrap
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/probod \
	&& chmod +x /usr/local/bin/probod-bootstrap \
	&& chmod +x /usr/local/bin/entrypoint.sh \
	&& setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/probod \
	&& mkdir -p /etc/probod \
	&& chown probo:probo /etc/probod

USER probo

EXPOSE 8080 8443 8081

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
