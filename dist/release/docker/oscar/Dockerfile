FROM bluenviron/mediamtx:1.21.4@sha256:c730bccdbc8739f8f0c13cefe9bea8b61926f599b88fa4d0d229baa91846c7bc AS mediamtx-bin

FROM eclipse-temurin:25.0.5.1_2-jre-noble@sha256:2ec98aa522c472deadfd2b7c5b39bca680e33ef522a53a72f10789bdf89a6bb5 AS app-tree

COPY --chown=root:root osh-node-oscar/ /opt/oscar/
RUN find /opt/oscar -type d -exec chmod 0555 {} + \
    && find /opt/oscar -type f -exec chmod 0444 {} +

FROM eclipse-temurin:25.0.5.1_2-jre-noble@sha256:2ec98aa522c472deadfd2b7c5b39bca680e33ef522a53a72f10789bdf89a6bb5

ARG OSCAR_VERSION=local
ARG OSCAR_UID=10001
ARG OSCAR_GID=10001

LABEL org.opencontainers.image.title="OSCAR" \
      org.opencontainers.image.version="${OSCAR_VERSION}"

ENV OSCAR_VERSION="${OSCAR_VERSION}"

COPY --chown=root:root docker/oscar/atomic-publish.c /tmp/oscar-atomic-publish.c

RUN apt-get update \
    && apt-get install --yes --no-install-recommends curl ca-certificates tzdata gcc libc6-dev \
    && gcc -O2 -Wall -Wextra -Werror -o /usr/local/bin/oscar-atomic-publish /tmp/oscar-atomic-publish.c \
    && sha256sum /tmp/oscar-atomic-publish.c | awk '{print $1}' > /usr/local/share/oscar-atomic-publish.source.sha256 \
    && chmod 0555 /usr/local/bin/oscar-atomic-publish \
    && chmod 0444 /usr/local/share/oscar-atomic-publish.source.sha256 \
    && rm -f /tmp/oscar-atomic-publish.c \
    && apt-get purge --yes --auto-remove gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid "${OSCAR_GID}" oscar \
    && useradd --uid "${OSCAR_UID}" --gid "${OSCAR_GID}" --home-dir /var/lib/oscar --shell /usr/sbin/nologin oscar

COPY --from=app-tree --chown=root:root /opt/oscar/ /opt/oscar/
COPY --from=mediamtx-bin --chown=root:root /mediamtx /usr/local/bin/mediamtx
COPY --chown=root:root docker/oscar/entrypoint.sh /usr/local/bin/oscar-entrypoint
COPY --chown=root:root docker/oscar/archive-object-helper.sh /usr/local/bin/oscar-archive-object

RUN chmod 0555 /usr/local/bin/mediamtx /usr/local/bin/oscar-entrypoint /usr/local/bin/oscar-archive-object \
    && install --directory --owner=oscar --group=oscar --mode=0700 \
        /var/lib/oscar /run/oscar-native

USER oscar:oscar
WORKDIR /var/lib/oscar

EXPOSE 8282
ENTRYPOINT ["/usr/local/bin/oscar-entrypoint"]
