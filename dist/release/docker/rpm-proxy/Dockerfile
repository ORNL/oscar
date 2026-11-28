FROM python:3.14-alpine@sha256:5862d971d1f0ae26b258cefa4e893556b1d3aba81bd2ff30888704ad378bab67

ARG OSCAR_VERSION=local
LABEL org.opencontainers.image.title="OSCAR RPM Edge Proxy" \
      org.opencontainers.image.description="Real-time TCP fan-out proxy for side-by-side CAS and OSCAR Rapiscan RPM deployments" \
      org.opencontainers.image.version="${OSCAR_VERSION}"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/opt/oscar-rpm-proxy

RUN addgroup -g 10003 -S oscarproxy \
    && adduser -u 10003 -G oscarproxy -H -D -s /sbin/nologin oscarproxy \
    && mkdir -p /opt/oscar-rpm-proxy /config \
    && chmod 0555 /opt/oscar-rpm-proxy /config

COPY --chown=root:root docker/rpm-proxy/oscar_rpm_proxy /opt/oscar-rpm-proxy/oscar_rpm_proxy
RUN find /opt/oscar-rpm-proxy -type d -exec chmod 0555 {} \; \
    && find /opt/oscar-rpm-proxy -type f -exec chmod 0444 {} \;

USER 10003:10003
WORKDIR /opt/oscar-rpm-proxy

HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python3", "-m", "oscar_rpm_proxy", "--check", "http://127.0.0.1:9090/healthz"]

ENTRYPOINT ["python3", "-m", "oscar_rpm_proxy"]
CMD ["--config", "/config/config.json"]
