FROM nginx/nginx-unprivileged:1.30.8-alpine

USER root

ARG OSCAR_VERSION=local
ARG OCTELIUM_VERSION=0.51.0
ARG TARGETARCH=amd64
ARG OCTELIUM_SHA256_AMD64=ed92147f3af25d2f5f5238bd20abd0414b771e887951ef628f95bd658fc8931d
ARG OCTELIUM_SHA256_ARM64=629c77d04c2a488f346ff5cffc9f93e1a67d126f6caf6faeffc569a991980d0f
ARG TUNNEL_UID=10002
ARG TUNNEL_GID=10002

LABEL org.opencontainers.image.title="OSCAR Remote Access Tunnel (Octelium)" \
      org.opencontainers.image.version="${OSCAR_VERSION}"

RUN apk add --no-cache ca-certificates curl tzdata \
    && case "${TARGETARCH}" in \
         amd64) arch="amd64"; expected_sha="${OCTELIUM_SHA256_AMD64}" ;; \
         arm64) arch="arm64"; expected_sha="${OCTELIUM_SHA256_ARM64}" ;; \
         *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
       esac \
    && curl -fsSL --retry 3 \
         "https://github.com/octelium/octelium/releases/download/v${OCTELIUM_VERSION}/octelium-linux-${arch}.tar.gz" \
         -o /tmp/octelium.tar.gz \
    && printf '%s  /tmp/octelium.tar.gz\n' "${expected_sha}" | sha256sum -c - \
    && tar -xzf /tmp/octelium.tar.gz -C /usr/local/bin octelium \
    && rm -f /tmp/octelium.tar.gz \
    && chmod 0555 /usr/local/bin/octelium \
    && addgroup -g "${TUNNEL_GID}" -S oscartunnel \
    && adduser -u "${TUNNEL_UID}" -G oscartunnel -H -D -s /sbin/nologin oscartunnel

COPY --chown=root:root docker/tunnel/entrypoint.sh /usr/local/bin/oscar-tunnel-entrypoint
RUN chmod 0555 /usr/local/bin/oscar-tunnel-entrypoint

USER oscartunnel:oscartunnel
WORKDIR /tmp/octelium

ENTRYPOINT ["/usr/local/bin/oscar-tunnel-entrypoint"]
