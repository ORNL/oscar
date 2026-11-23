#!/usr/bin/env bash
# Deterministic unit & lifecycle integration test for oscar-update.sh (zero-login GitHub
# release discovery, SHA-256 verification, sibling-directory state preservation, and
# automatic fail-safe rollback).
set -Eeuo pipefail

repo_root=$(CDPATH= cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
bash -n "$repo_root/dist/release/oscar-update.sh"
bash -n "$repo_root/dist/release/oscar-setup.sh"
bash -n "$repo_root/dist/release/oscar.sh"

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/oscar-system-update-test.XXXXXX")
server_pid=""
cleanup() {
    [[ -z $server_pid ]] || kill "$server_pid" 2>/dev/null || true
    rm -rf -- "$tmp_root"
}
trap cleanup EXIT

# 1. Build a mock v3.11.9 release zip and mock v3.11.8 active installation
pkg_stage="$tmp_root/pkg-build/oscar-3.11.9"
mkdir -p "$pkg_stage"
cp -f "$repo_root/dist/release/oscar-update.sh" "$pkg_stage/oscar-update.sh"
chmod +x "$pkg_stage/oscar-update.sh"
cat >"$pkg_stage/.env.example" <<'EOF'
OSCAR_VERSION=3.11.9
OSCAR_BACKUP_MODE=disabled
EOF
cat >"$pkg_stage/compose.yaml" <<'EOF'
services:
  oscar:
    image: oscar:3.11.9
EOF
cat >"$pkg_stage/oscar-setup.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
dir=$(CDPATH= cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
if [[ ${1:-} == simulated-upgrade ]]; then
    if [[ -f "$dir/.force-fail" ]]; then
        echo "Simulated container healthcheck failure" >&2
        exit 1
    fi
    sed -i.bak 's/^OSCAR_VERSION=.*/OSCAR_VERSION=3.11.9/' "$dir/.env" && rm -f "$dir/.env.bak"
    echo "Upgrade simulated cleanly"
    exit 0
fi
exit 0
EOF
chmod +x "$pkg_stage/oscar-setup.sh"

serve_dir="$tmp_root/http/ORNL/oscar/releases/download/v3.11.9"
mkdir -p "$serve_dir"
(cd "$tmp_root/pkg-build" && zip -qr "$serve_dir/oscar-3.11.9.zip" oscar-3.11.9)
good_sha=$(sha256sum "$serve_dir/oscar-3.11.9.zip" | awk '{print $1}')
printf '%s *oscar-3.11.9.zip\n' "$good_sha" >"$serve_dir/oscar-3.11.9.zip.sha256"

# Also build a failing v3.11.10 zip to prove automatic rollback
fail_stage="$tmp_root/pkg-fail/oscar-3.11.10"
mkdir -p "$fail_stage"
cp -rf "$pkg_stage/"* "$pkg_stage/.env.example" "$fail_stage/"
sed -i.bak 's/3\.11\.9/3.11.10/g' "$fail_stage/.env.example" "$fail_stage/compose.yaml" && rm -f "$fail_stage"/*.bak
touch "$fail_stage/.force-fail"
serve_fail_dir="$tmp_root/http/ORNL/oscar/releases/download/v3.11.10"
mkdir -p "$serve_fail_dir"
(cd "$tmp_root/pkg-fail" && zip -qr "$serve_fail_dir/oscar-3.11.10.zip" oscar-3.11.10)
fail_sha=$(sha256sum "$serve_fail_dir/oscar-3.11.10.zip" | awk '{print $1}')
printf '%s *oscar-3.11.10.zip\n' "$fail_sha" >"$serve_fail_dir/oscar-3.11.10.zip.sha256"

port_file="$tmp_root/port.txt"
python3 - "$tmp_root/http" "$port_file" <<'PY' &
import http.server, os, socketserver, sys

root_dir, port_path = sys.argv[1], sys.argv[2]
os.chdir(root_dir)

class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass
    def do_GET(self):
        if "Authorization" in self.headers:
            self.send_error(400, "Unexpected Authorization header in zero-login request")
            return
        if self.path == "/ORNL/oscar/releases/latest":
            self.send_response(302)
            self.send_header("Location", f"http://127.0.0.1:{self.server.server_address[1]}/ORNL/oscar/releases/tag/v3.11.9")
            self.end_headers()
            return
        super().do_GET()

with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    with open(port_path, "w", encoding="utf-8") as fh:
        fh.write(str(httpd.server_address[1]))
    httpd.serve_forever()
PY
server_pid=$!
for _ in $(seq 1 30); do [[ -s $port_file ]] && break; sleep 0.1; done
port=$(cat "$port_file")

active_dir="$tmp_root/deploy/oscar-3.11.8"
ctrl_dir="$tmp_root/control"
mkdir -p "$active_dir/secrets" "$active_dir/tls" "$ctrl_dir/staged"
cp -f "$repo_root/dist/release/oscar-update.sh" "$active_dir/oscar-update.sh"
chmod +x "$active_dir/oscar-update.sh"
cat >"$active_dir/.env" <<'EOF'
OSCAR_VERSION=3.11.8
OSCAR_BACKUP_MODE=disabled
EOF
printf 'secret-db-pw\n' >"$active_dir/secrets/oscar-db-password.txt"
printf 'cert-pem\n' >"$active_dir/tls/server.crt"
printf 'adopted=true\n' >"$active_dir/.oscar-volume-adoption"
cat >"$active_dir/oscar-setup.sh" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == simulated-rollback ]]; then
    touch "$(dirname -- "${BASH_SOURCE[0]}")/.rollback-invoked"
    exit 0
fi
exit 0
EOF
chmod +x "$active_dir/oscar-setup.sh"

export OSCAR_UPDATE_ALLOW_NONROOT=1
export OSCAR_UPDATE_ALLOW_CUSTOM_BASE_URL=1
export OSCAR_UPDATE_GITHUB_BASE_URL="http://127.0.0.1:${port}/ORNL/oscar"
export OSCAR_UPDATE_CONTROL_DIR="$ctrl_dir"
export OSCAR_UPDATE_FORCE_BRIDGE_ACTIVE=1
export OSCAR_UPDATE_DRY_RUN_UPGRADE=1
export OSCAR_UPDATE_MIN_DISK_GIB=1

# 2. Verify anonymous zero-login check --json
check_out=$(bash "$active_dir/oscar-update.sh" check --json)
[[ $check_out == *'"currentVersion":"3.11.8"'* ]] || { echo "Bad currentVersion: $check_out" >&2; exit 1; }
[[ $check_out == *'"latestVersion":"3.11.9"'* ]] || { echo "Bad latestVersion: $check_out" >&2; exit 1; }
[[ $check_out == *'"updateAvailable":true'* ]] || { echo "Expected updateAvailable=true: $check_out" >&2; exit 1; }
[[ $check_out == *'"requiresGitHubLogin":false'* ]] || { echo "Expected requiresGitHubLogin=false: $check_out" >&2; exit 1; }
[[ $check_out == *"\"expectedSha256\":\"${good_sha}\""* ]] || { echo "Bad expectedSha256: $check_out" >&2; exit 1; }

# 3. Verify tampered SHA-256 is rejected before extracting
cat >"$ctrl_dir/request.json" <<'EOF'
{"requestId":"req-bad-sha","action":"upgrade-github","targetVersion":"3.11.9","expectedSha256":"0000000000000000000000000000000000000000000000000000000000000000","createBackupFirst":false}
EOF
bash "$active_dir/oscar-update.sh" poll-bridge
grep -Fq '"state": "FAILED"' "$ctrl_dir/status.json"
[[ ! -d "$tmp_root/deploy/oscar-3.11.9" ]]

# 4. Verify GUI poll-bridge upgrade-github extracts to clean sibling dir, preserves secrets/tls/receipts, and marks COMPLETED
cat >"$ctrl_dir/request.json" <<EOF
{"requestId":"req-good-3119","action":"upgrade-github","targetVersion":"3.11.9","expectedSha256":"${good_sha}","createBackupFirst":false}
EOF
bash "$active_dir/oscar-update.sh" poll-bridge
grep -Fq '"state": "COMPLETED"' "$ctrl_dir/status.json"
grep -Fq '"currentVersion": "3.11.9"' "$ctrl_dir/status.json"
[[ -f "$tmp_root/deploy/oscar-3.11.9/secrets/oscar-db-password.txt" ]]
[[ -f "$tmp_root/deploy/oscar-3.11.9/tls/server.crt" ]]
[[ -f "$tmp_root/deploy/oscar-3.11.9/.oscar-volume-adoption" ]]

# 5. Verify automatic fail-safe rollback when target upgrade fails
cat >"$ctrl_dir/request.json" <<EOF
{"requestId":"req-fail-31110","action":"upgrade-github","targetVersion":"3.11.10","expectedSha256":"${fail_sha}","createBackupFirst":false}
EOF
bash "$active_dir/oscar-update.sh" poll-bridge
grep -Fq '"state": "ROLLED_BACK"' "$ctrl_dir/status.json"
[[ -f "$active_dir/.rollback-invoked" ]]
[[ ! -d "$tmp_root/deploy/oscar-3.11.10" ]]

printf 'PASS: oscar-update.sh zero-login discovery, SHA-256 verification, sibling upgrade, and fail-safe rollback verified.\n'
