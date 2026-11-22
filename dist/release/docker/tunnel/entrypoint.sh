#!/bin/sh
set -eu

TOKEN_FILE="${OCTELIUM_TOKEN_MOUNT:-/run/secrets/octelium_auth_token}"
SANDBOX_PORT="${OSCAR_SANDBOX_PORT:-8444}"

if [ -z "${OCTELIUM_DOMAIN:-}" ]; then
    echo "ERROR: OCTELIUM_DOMAIN is required." >&2
    exit 1
fi

if [ -z "${OCTELIUM_SERVICE:-}" ]; then
    echo "ERROR: OCTELIUM_SERVICE is required." >&2
    exit 1
fi

if [ ! -s "${TOKEN_FILE}" ]; then
    echo "ERROR: Octelium authentication token file is missing or empty at ${TOKEN_FILE}." >&2
    exit 1
fi

case "${SANDBOX_PORT}" in
    ''|*[!0-9]*) SANDBOX_PORT=8444 ;;
esac

mkdir -p \
    /tmp/octelium/home \
    /tmp/octelium/nginx/body \
    /tmp/octelium/nginx/proxy \
    /tmp/octelium/nginx/fastcgi \
    /tmp/octelium/nginx/uwsgi \
    /tmp/octelium/nginx/scgi \
    /tmp/octelium/nginx/html
chmod 0700 /tmp/octelium/home /tmp/octelium/nginx

LIVE_URL="https://${OCTELIUM_SERVICE}.${OCTELIUM_DOMAIN}"

cat >/tmp/octelium/nginx/html/__oscar_sandbox_offline.html <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Practice Sandbox Stopped | OSCAR</title>
  <style>
    :root { color-scheme: light; font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #f8fafc; color: #0f172a; padding: 24px; }
    main { max-width: 560px; background: #ffffff; border: 1px solid #f59e0b; border-radius: 12px; padding: 28px; box-shadow: 0 10px 25px rgba(15, 23, 42, 0.08); }
    .badge { display: inline-block; background: #fef3c7; color: #92400e; font-weight: 700; font-size: 0.78rem; padding: 4px 10px; border-radius: 999px; margin-bottom: 12px; }
    h1 { margin: 0 0 10px; font-size: 1.35rem; }
    p { margin: 0 0 14px; line-height: 1.5; color: #334155; font-size: 0.95rem; }
    .actions { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 18px; }
    a.primary, button.secondary { text-decoration: none; border-radius: 8px; padding: 10px 16px; font-weight: 700; font-size: 0.9rem; cursor: pointer; }
    a.primary { background: #d97706; color: #ffffff; border: none; }
    button.secondary { background: #ffffff; color: #1e293b; border: 1px solid #cbd5e1; }
  </style>
</head>
<body>
  <main>
    <span class="badge">TRAINING SANDBOX — STOPPED</span>
    <h1>Practice Sandbox is currently stopped</h1>
    <p>OSCAR's isolated Practice Sandbox automatically shuts down and wipes all disposable practice volumes after 120 minutes (or when stopped) so server memory is never held overnight.</p>
    <p>To start a fresh 120-minute practice session in 1 click, open the live OSCAR console, click <strong>Guided Walkthrough</strong> (or <strong>Help ?</strong>), and click <strong>Launch Practice Sandbox</strong>.</p>
    <div class="actions">
      <a class="primary" href="${LIVE_URL}">Open Live OSCAR Console (${OCTELIUM_SERVICE}.${OCTELIUM_DOMAIN})</a>
      <button type="button" class="secondary" onclick="window.location.reload()">Reload Page</button>
    </div>
  </main>
</body>
</html>
EOF

cat >/tmp/octelium/nginx/nginx.conf <<EOF
worker_processes 1;
pid /tmp/octelium/nginx/nginx.pid;
error_log /dev/stderr warn;

events {
    worker_connections 256;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log off;

    client_body_temp_path /tmp/octelium/nginx/body;
    proxy_temp_path /tmp/octelium/nginx/proxy;
    fastcgi_temp_path /tmp/octelium/nginx/fastcgi;
    uwsgi_temp_path /tmp/octelium/nginx/uwsgi;
    scgi_temp_path /tmp/octelium/nginx/scgi;

    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        '' "";
    }

    map \$http_host \$public_host {
        default \$http_host;
        '' \$host;
    }

    server {
        listen 127.0.0.1:18444;
        server_name _;
        client_max_body_size 2g;

        error_page 502 504 =503 /__oscar_sandbox_offline.html;

        location = /__oscar_sandbox_offline.html {
            internal;
            root /tmp/octelium/nginx/html;
            add_header Cache-Control "no-store" always;
        }

        location / {
            proxy_pass https://host.docker.internal:${SANDBOX_PORT};
            proxy_ssl_verify off;
            proxy_http_version 1.1;
            proxy_intercept_errors off;
            proxy_set_header Host \$public_host;
            proxy_set_header X-Forwarded-Host \$public_host;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_connect_timeout 3s;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
            proxy_buffering off;
            proxy_request_buffering off;
        }
    }
}
EOF

nginx -t -p /tmp/octelium/nginx -c /tmp/octelium/nginx/nginx.conf -e /dev/stderr >/dev/null 2>&1
nginx -p /tmp/octelium/nginx -c /tmp/octelium/nginx/nginx.conf -e /dev/stderr

export HOME=/tmp/octelium/home
export OCTELIUM_SKIP_MESSAGES=true
if [ "${OCTELIUM_INSECURE_TLS:-false}" = "true" ]; then
    export OCTELIUM_INSECURE_TLS=true
fi

# Strip surrounding whitespace/newlines into a private tmpfs copy so tokens saved with trailing newlines authenticate cleanly.
CLEAN_TOKEN="/tmp/octelium/home/auth.token"
tr -d '\r\n ' < "${TOKEN_FILE}" > "${CLEAN_TOKEN}"
chmod 0600 "${CLEAN_TOKEN}"

set -- /usr/local/bin/octelium connect \
    --domain "${OCTELIUM_DOMAIN}" \
    --homedir /tmp/octelium/home \
    --implementation "${OCTELIUM_IMPLEMENTATION:-gvisor}" \
    --ip-mode "${OCTELIUM_IP_MODE:-v4}" \
    --tunnel-mode "${OCTELIUM_TUNNEL_MODE:-wg}" \
    --no-dns \
    --serve-all \
    --auth-token-file "${CLEAN_TOKEN}" \
    --logout

if [ -n "${OCTELIUM_SCOPE:-}" ]; then
    set -- "$@" --scope "${OCTELIUM_SCOPE}"
fi

exec "$@"
