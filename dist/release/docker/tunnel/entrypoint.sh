#!/bin/sh
set -eu

TOKEN_FILE="${OCTELIUM_TOKEN_MOUNT:-/run/secrets/octelium_auth_token}"

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

mkdir -p /tmp/octelium/home
chmod 0700 /tmp/octelium/home

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
    --serve "${OCTELIUM_SERVICE}" \
    --auth-token-file "${CLEAN_TOKEN}" \
    --logout

if [ -n "${OCTELIUM_SCOPE:-}" ]; then
    set -- "$@" --scope "${OCTELIUM_SCOPE}"
fi

exec "$@"
