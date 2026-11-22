#!/usr/bin/env bash
# OSCAR Ephemeral Hands-On Training Sandbox & Guided Academy Manager (Ubuntu 24.04 LTS)
# Launches an isolated :8444 training stack reusing the installed oscar:<version> and
# oscar-postgis:<version> images with archive.enabled=false, disposable volumes, zero
# writes to production PostgreSQL/Parquet/config.json, automatic TTL shutdown, and
# instant < 2 s complete wipe on stop or reset.
set -Eeuo pipefail

script_path=${BASH_SOURCE[0]}
[[ ! -L $script_path ]] || { printf 'ERROR: Refusing to execute symlinked script: %s\n' "$script_path" >&2; exit 1; }
case $script_path in */*) script_parent=${script_path%/*} ;; *) script_parent=. ;; esac
script_dir=$(CDPATH= cd -P -- "$script_parent" && pwd -P)

sandbox_project=${OSCAR_SANDBOX_PROJECT_NAME:-oscar-sandbox}
runtime_dir=${OSCAR_SANDBOX_RUNTIME_DIR:-/run/oscar-sandbox}
prod_state_volume=${OSCAR_STATE_VOLUME:-oscar_oscar_state}
systemd_dir=${OSCAR_SANDBOX_SYSTEMD_DIR:-/etc/systemd/system}
min_avail_ram_mib=${OSCAR_SANDBOX_MIN_RAM_MIB:-3584}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_root() {
    if [[ ${OSCAR_SANDBOX_ALLOW_NONROOT:-0} == 1 ]]; then
        return 0
    fi
    [[ ${EUID:-$(id -u)} -eq 0 ]] || fail 'Run this command with sudo (root privileges required).'
}

env_value() {
    local name=$1 default=${2:-} file=${3:-"$script_dir/.env"}
    [[ -f $file ]] || { printf '%s' "$default"; return 0; }
    local val
    val=$(awk -F= -v k="$name" '$1 == k { print substr($0, index($0, "=") + 1) }' "$file" | tail -n 1 | tr -d '\r')
    if [[ -n $val ]]; then printf '%s' "$val"; else printf '%s' "$default"; fi
}

oscar_version() {
    local v
    v=$(env_value OSCAR_VERSION '')
    [[ -n $v ]] || v=$(env_value OSCAR_VERSION 'local' "$script_dir/.env.example")
    printf '%s' "$v"
}

json_escape() {
    local s=${1:-}
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/ }
    s=${s//$'\r'/}
    s=${s//$'\t'/ }
    printf '%s' "$s"
}

available_ram_mib() {
    if [[ -r /proc/meminfo ]]; then
        awk '/^MemAvailable:/ { printf "%d", int($2 / 1024) }' /proc/meminfo
    else
        printf '8192'
    fi
}

resolve_control_dir() {
    if [[ -n ${OSCAR_SANDBOX_CONTROL_DIR:-} ]]; then
        printf '%s' "$OSCAR_SANDBOX_CONTROL_DIR"
        return 0
    fi
    if command -v docker >/dev/null 2>&1 && docker volume inspect "$prod_state_volume" >/dev/null 2>&1; then
        local mp
        mp=$(docker volume inspect --format '{{.Mountpoint}}' "$prod_state_volume" 2>/dev/null || true)
        if [[ -n $mp && -d $mp ]]; then
            printf '%s/.moduledata/sandbox-control' "$mp"
            return 0
        fi
    fi
    return 1
}

is_sandbox_running() {
    command -v docker >/dev/null 2>&1 || return 1
    local running
    running=$(docker ps --filter "label=com.docker.compose.project=${sandbox_project}" --filter "label=com.docker.compose.service=gateway" --format '{{.ID}}' 2>/dev/null || true)
    [[ -n $running ]]
}

is_bridge_enabled() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --no-ask-password is-active --quiet oscar-sandbox-agent.path 2>/dev/null || \
            systemctl --no-ask-password is-active --quiet oscar-sandbox-agent.timer 2>/dev/null
        return $?
    fi
    return 1
}

resolve_octelium_env() {
    local archive_dir storage_root parent
    archive_dir=$(env_value OSCAR_ARCHIVE_DIR '')
    if [[ -n $archive_dir && $archive_dir == /* ]]; then
        storage_root=$(dirname "$archive_dir")
    else
        parent=$(CDPATH= cd -P -- "$script_dir/.." && pwd -P)
        storage_root="$parent/oscar-storage"
    fi
    printf '%s/remote-access/octelium.env' "$storage_root"
}

resolve_remote_sandbox_info() {
    oct_domain=""
    oct_sandbox_url=""
    local oct_env oct_enabled oct_service
    oct_env=$(resolve_octelium_env)
    [[ -f $oct_env ]] || return 0
    oct_enabled=$(env_value OCTELIUM_ENABLED 'false' "$oct_env")
    [[ ${oct_enabled,,} == "true" ]] || return 0
    oct_domain=$(env_value OCTELIUM_DOMAIN '' "$oct_env")
    oct_service=$(env_value OCTELIUM_SERVICE '' "$oct_env")
    if [[ -n $oct_domain && -n $oct_service ]]; then
        oct_sandbox_url="https://${oct_service}-sandbox.${oct_domain}"
    fi
}

write_bridge_status() {
    local job_id=${1:-} job_action=${2:-} job_state=${3:-} job_msg=${4:-}
    local ctrl_dir
    ctrl_dir=$(resolve_control_dir || true)
    [[ -n $ctrl_dir ]] || return 0
    install -d -m 0700 -o 10001 -g 10001 "$ctrl_dir" 2>/dev/null || install -d -m 0700 "$ctrl_dir"

    local agent_active=false running=false port=8444 ttl=120 expires="" ram_mib oct_domain="" oct_sandbox_url=""
    is_bridge_enabled && agent_active=true
    is_sandbox_running && running=true
    if [[ -f "$runtime_dir/sandbox.meta" ]]; then
        port=$(env_value HTTPS_PORT 8444 "$runtime_dir/sandbox.meta")
        ttl=$(env_value TTL_MINUTES 120 "$runtime_dir/sandbox.meta")
        expires=$(env_value EXPIRES_AT '' "$runtime_dir/sandbox.meta")
    fi
    ram_mib=$(available_ram_mib)
    resolve_remote_sandbox_info

    local tmp="$ctrl_dir/status.json.tmp.$$"
    {
        printf '{\n'
        printf '  "agentActive": %s,\n' "$agent_active"
        printf '  "sandboxRunning": %s,\n' "$running"
        printf '  "httpsPort": %s,\n' "$port"
        printf '  "ttlMinutes": %s,\n' "$ttl"
        printf '  "availableRamMib": %s' "$ram_mib"
        if [[ -n $oct_domain ]]; then
            printf ',\n  "remoteDomain": "%s"' "$(json_escape "$oct_domain")"
        fi
        if [[ -n $oct_sandbox_url ]]; then
            printf ',\n  "remoteSandboxUrl": "%s"' "$(json_escape "$oct_sandbox_url")"
        fi
        if [[ -n $expires ]]; then
            printf ',\n  "expiresAt": "%s"' "$(json_escape "$expires")"
        fi
        if [[ -n $job_id ]]; then
            printf ',\n  "activeJob": {"requestId": "%s", "action": "%s", "state": "%s", "message": "%s"}' \
                "$(json_escape "$job_id")" "$(json_escape "$job_action")" "$(json_escape "$job_state")" "$(json_escape "$job_msg")"
        fi
        printf '\n}\n'
    } >"$tmp"
    chown 10001:10001 "$tmp" 2>/dev/null || true
    chmod 0600 "$tmp"
    mv -f -- "$tmp" "$ctrl_dir/status.json"
}

sandbox_compose() {
    local ver tz oct_domain="" oct_sandbox_url=""
    ver=$(oscar_version)
    tz=$(env_value OSCAR_TIMEZONE 'UTC')
    resolve_remote_sandbox_info
    OSCAR_VERSION="$ver" \
    OSCAR_TIMEZONE="$tz" \
    OSCAR_SANDBOX_RUNTIME_DIR="$runtime_dir" \
    OSCAR_WEBAUTHN_RP_ID="${OSCAR_WEBAUTHN_RP_ID:-$oct_domain}" \
    docker compose --project-name "$sandbox_project" --project-directory "$script_dir" \
        --file "$script_dir/compose.sandbox.yaml" "$@"
}

cancel_expiry_timer() {
    if [[ ${EUID:-$(id -u)} -eq 0 ]] && command -v systemctl >/dev/null 2>&1; then
        systemctl --no-ask-password stop oscar-sandbox-expiry.timer oscar-sandbox-expiry.service >/dev/null 2>&1 || true
        systemctl --no-ask-password reset-failed oscar-sandbox-expiry.timer oscar-sandbox-expiry.service >/dev/null 2>&1 || true
    fi
}

schedule_expiry_timer() {
    local ttl_minutes=$1
    cancel_expiry_timer
    if [[ ${EUID:-$(id -u)} -eq 0 ]] && command -v systemd-run >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        systemd-run --no-ask-password --quiet --unit=oscar-sandbox-expiry \
            --on-active="${ttl_minutes}m" \
            /bin/bash "$script_dir/oscar-sandbox.sh" stop >/dev/null 2>&1 || true
    fi
}

prepare_sandbox_secrets_and_tls() {
    local explicit_password=${1:-}
    install -d -m 0700 "$runtime_dir" "$runtime_dir/secrets" "$runtime_dir/tls"

    openssl rand -hex 24 >"$runtime_dir/secrets/oscar-db-password.txt"
    openssl rand -hex 24 >"$runtime_dir/secrets/postgres-bootstrap-password.txt"
    chmod 0400 "$runtime_dir/secrets/oscar-db-password.txt" "$runtime_dir/secrets/postgres-bootstrap-password.txt"

    printed_sandbox_password=""
    if [[ -n $explicit_password ]]; then
        printf '%s\n' "$explicit_password" >"$runtime_dir/secrets/oscar-admin-password.txt"
        printed_sandbox_password="(custom --admin-password supplied)"
    else
        local extracted_hash="" ver_probe
        ver_probe=$(oscar_version)
        if docker volume inspect "$prod_state_volume" >/dev/null 2>&1; then
            extracted_hash=$(docker run --rm -v "${prod_state_volume}:/prod:ro" --user root --entrypoint /bin/sh "oscar:${ver_probe}" \
                -c 'if [ -f /prod/config.json ]; then awk '\''/\042objClass\042:[ \t]*\042org\.sensorhub\.impl\.security\.BasicSecurityRealmConfig\042/ { f=1 } f && /\042password\042:[ \t]*\042/ { sub(/^.*\042password\042:[ \t]*\042/, ""); sub(/\042.*$/, ""); if ($0 != "" && $0 != "__INITIAL_ADMIN_PASSWORD__") { print; exit } }'\'' /prod/config.json; fi' 2>/dev/null || true)
        fi
        if [[ -n $extracted_hash ]]; then
            printf '# PBKDF2_PREENCODED:%s\n' "$extracted_hash" >"$runtime_dir/secrets/oscar-admin-password.txt"
            printed_sandbox_password="(same credentials & Passkeys as your operational OSCAR site)"
        else
            local gen_pw
            gen_pw="Sandbox-$(openssl rand -hex 6)"
            printf '%s\n' "$gen_pw" >"$runtime_dir/secrets/oscar-admin-password.txt"
            printed_sandbox_password="admin / ${gen_pw}"
        fi
    fi
    chmod 0444 "$runtime_dir/secrets/oscar-admin-password.txt" "$runtime_dir/secrets/oscar-db-password.txt" "$runtime_dir/secrets/postgres-bootstrap-password.txt"

    if [[ -f "$script_dir/tls/server.crt" && -f "$script_dir/tls/server.key" ]]; then
        cp -f -- "$script_dir/tls/server.crt" "$runtime_dir/tls/certificate.pem"
        cp -f -- "$script_dir/tls/server.key" "$runtime_dir/tls/private-key.pem"
    elif [[ -f "$script_dir/tls/certificate.pem" && -f "$script_dir/tls/private-key.pem" ]]; then
        cp -f -- "$script_dir/tls/certificate.pem" "$runtime_dir/tls/certificate.pem"
        cp -f -- "$script_dir/tls/private-key.pem" "$runtime_dir/tls/private-key.pem"
    else
        local host_cn
        host_cn=$(env_value OSCAR_HOSTNAME "$(hostname -f 2>/dev/null || hostname || echo localhost)")
        openssl req -x509 -newkey rsa:2048 -sha256 -days 7 -nodes \
            -subj "/CN=${host_cn}" \
            -addext "subjectAltName=DNS:${host_cn},DNS:oscar.local,DNS:localhost,IP:127.0.0.1" \
            -keyout "$runtime_dir/tls/private-key.pem" \
            -out "$runtime_dir/tls/certificate.pem" >/dev/null 2>&1
    fi
    chmod 0444 "$runtime_dir/tls/certificate.pem" "$runtime_dir/tls/private-key.pem"
}

seed_identities_one_way() {
    local ver
    ver=$(oscar_version)
    docker run --rm -v oscar_sandbox_state:/sb --user root --entrypoint /bin/sh "oscar:${ver}" \
        -c 'chown 10001:10001 /sb && chmod 0700 /sb' >/dev/null
    if ! docker volume inspect "$prod_state_volume" >/dev/null 2>&1; then
        return 0
    fi
    docker run --rm -v "${prod_state_volume}:/prod:ro" -v oscar_sandbox_state:/sb --user root --entrypoint /bin/sh "oscar:${ver}" \
        -c 'chown 10001:10001 /sb && chmod 0700 /sb && install -d -m 0700 -o 10001 -g 10001 /sb/.moduledata && if [ -f /prod/.moduledata/oscar-identity.json ]; then cp -f /prod/.moduledata/oscar-identity.json /sb/.moduledata/oscar-identity.json && chown 10001:10001 /sb/.moduledata/oscar-identity.json && chmod 0600 /sb/.moduledata/oscar-identity.json; fi && if [ -f /prod/config.json ]; then java -classpath "/opt/oscar/lib/*" com.botts.impl.service.oscar.sandbox.SandboxAuthConfigSeeder extract /prod/config.json /sb/.moduledata/sandbox-auth-seed.json >/dev/null 2>&1 || true; if [ -f /sb/.moduledata/sandbox-auth-seed.json ]; then chown 10001:10001 /sb/.moduledata/sandbox-auth-seed.json && chmod 0600 /sb/.moduledata/sandbox-auth-seed.json; fi; fi' >/dev/null
}

do_stop() {
    cancel_expiry_timer
    if [[ -d $runtime_dir ]] && command -v docker >/dev/null 2>&1; then
        sandbox_compose down -v --remove-orphans >/dev/null 2>&1 || true
    elif command -v docker >/dev/null 2>&1; then
        docker ps -aq --filter "label=com.docker.compose.project=${sandbox_project}" | xargs -r docker rm -f >/dev/null 2>&1 || true
    fi
    if command -v docker >/dev/null 2>&1; then
        docker volume rm -f oscar_sandbox_state oscar_sandbox_pg >/dev/null 2>&1 || true
        docker network rm "${sandbox_project}_sandbox_frontend" "${sandbox_project}_sandbox_database" >/dev/null 2>&1 || true
    fi
    chmod -R u+w "$runtime_dir" 2>/dev/null || true
    rm -rf -- "$runtime_dir"
    write_bridge_status "" "stop" "COMPLETED" "Training Sandbox stopped and ephemeral volumes flushed."
}

do_start() {
    local port=8444 ttl=120 track="operator" admin_pw="" allow_low_mem=false
    while (($#)); do
        case "$1" in
            --port) port=${2:?Missing value for --port}; shift 2 ;;
            --ttl-minutes) ttl=${2:?Missing value for --ttl-minutes}; shift 2 ;;
            --track) track=${2:?Missing value for --track}; shift 2 ;;
            --admin-password) admin_pw=${2:?Missing value for --admin-password}; shift 2 ;;
            --allow-low-memory) allow_low_mem=true; shift ;;
            *) fail "Unknown sandbox start option: $1" ;;
        esac
    done

    [[ $port =~ ^[0-9]+$ ]] && ((port >= 1024 && port <= 65535 && port != 8443 && port != 443)) || \
        fail "Sandbox HTTPS port must be between 1024 and 65535 (excluding 443 and 8443)."
    [[ $ttl =~ ^[0-9]+$ ]] && ((ttl >= 5 && ttl <= 1440)) || \
        fail "Sandbox --ttl-minutes must be between 5 and 1440."

    local prod_port
    prod_port=$(env_value OSCAR_HTTPS_PORT '443')
    [[ $port != "$prod_port" ]] || fail "Sandbox port ($port) must not match operational OSCAR_HTTPS_PORT ($prod_port)."

    local avail_mib
    avail_mib=$(available_ram_mib)
    if ! $allow_low_mem && ((avail_mib < min_avail_ram_mib)); then
        fail "Insufficient free memory for Training Sandbox (${avail_mib} MiB available; >= ${min_avail_ram_mib} MiB required so operational OSCAR is never starved). Pass --allow-low-memory on lab VMs to override."
    fi

    local ver
    ver=$(oscar_version)
    docker image inspect "oscar:${ver}" >/dev/null 2>&1 || \
        fail "Docker image oscar:${ver} is not loaded yet. Run 'sudo bash oscar.sh init' or load offline images first."
    docker image inspect "oscar-postgis:${ver}" >/dev/null 2>&1 || \
        fail "Docker image oscar-postgis:${ver} is not loaded yet."

    do_stop >/dev/null 2>&1 || true
    prepare_sandbox_secrets_and_tls "$admin_pw"

    local now_epoch exp_iso
    now_epoch=$(date +%s)
    exp_iso=$(date -u -d "@$((now_epoch + ttl * 60))" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf '')
    cat >"$runtime_dir/sandbox.meta" <<EOF
HTTPS_PORT=$port
TTL_MINUTES=$ttl
STARTED_EPOCH=$now_epoch
EXPIRES_AT=$exp_iso
INITIAL_TRACK=$track
EOF
    chmod 0600 "$runtime_dir/sandbox.meta"

    docker volume create oscar_sandbox_state >/dev/null
    docker volume create oscar_sandbox_pg >/dev/null
    docker run --rm -v oscar_sandbox_state:/sb --user root --entrypoint /bin/sh "oscar:${ver}" \
        -c 'chown 10001:10001 /sb && chmod 0700 /sb' >/dev/null
    if [[ -z $admin_pw ]]; then
        seed_identities_one_way
    fi

    OSCAR_SANDBOX_PORT="$port" \
    OSCAR_SANDBOX_TTL_MINUTES="$ttl" \
    OSCAR_SANDBOX_STARTED_EPOCH_SEC="$now_epoch" \
    OSCAR_SANDBOX_INITIAL_TRACK="$track" \
    sandbox_compose up --detach --no-build --pull never --wait --wait-timeout 180

    schedule_expiry_timer "$ttl"
    write_bridge_status "" "start" "COMPLETED" "Training Sandbox active on port ${port}"

    local host_display oct_domain="" oct_sandbox_url="" remote_line=""
    host_display=$(env_value OSCAR_HOSTNAME "$(hostname -I 2>/dev/null | awk '{print $1}' || echo localhost)")
    [[ -n $host_display ]] || host_display="localhost"
    resolve_remote_sandbox_info
    if [[ -n $oct_sandbox_url ]]; then
        remote_line=$'\n'"  Remote Tunnel:    ${oct_sandbox_url} (Let's Encrypt + Passkeys)"
    fi
    cat <<EOF

========================================================================
OSCAR ${ver} — Hands-On Training Sandbox & Guided Academy ACTIVE
========================================================================
  Sandbox URL:      https://${host_display}:${port}${remote_line}
  Credentials:      ${printed_sandbox_password}
  Initial Track:    ${track} (switchable in-UI: Operator / Supervisor / Admin)
  Auto-Flush TTL:   ${ttl} minutes (${exp_iso:-auto})
  Isolation:        ZERO mounts to oscar_postgres_data, oscar_oscar_state,
                    or Parquet archive (archive.enabled = false)
  Stop & Flush:     sudo bash oscar.sh sandbox stop
========================================================================
EOF
}

do_status() {
    local json_mode=false
    [[ ${1:-} == "--json" ]] && json_mode=true
    local running=false port=8444 ttl=120 expires="" oct_domain="" oct_sandbox_url=""
    is_sandbox_running && running=true
    if [[ -f "$runtime_dir/sandbox.meta" ]]; then
        port=$(env_value HTTPS_PORT 8444 "$runtime_dir/sandbox.meta")
        ttl=$(env_value TTL_MINUTES 120 "$runtime_dir/sandbox.meta")
        expires=$(env_value EXPIRES_AT '' "$runtime_dir/sandbox.meta")
    fi
    resolve_remote_sandbox_info
    if $json_mode; then
        printf '{"sandboxRunning":%s,"httpsPort":%s,"ttlMinutes":%s,"expiresAt":"%s","availableRamMib":%s,"remoteSandboxUrl":"%s"}\n' \
            "$running" "$port" "$ttl" "$(json_escape "$expires")" "$(available_ram_mib)" "$(json_escape "$oct_sandbox_url")"
        return 0
    fi
    if $running; then
        printf 'Training Sandbox: RUNNING on HTTPS port %s (TTL: %sm, expires: %s)\n' "$port" "$ttl" "${expires:-n/a}"
        if [[ -n $oct_sandbox_url ]]; then
            printf 'Remote Sandbox URL: %s\n' "$oct_sandbox_url"
        fi
        docker ps --filter "label=com.docker.compose.project=${sandbox_project}" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    else
        printf 'Training Sandbox: STOPPED (0 sandbox containers, 0 sandbox volumes)\n'
    fi
}

enable_ui_bridge() {
    require_root
    command -v systemctl >/dev/null 2>&1 || fail 'systemd is required for enable-ui-bridge.'
    rm -f -- /etc/oscar-sandbox-bridge.disabled
    local ctrl_dir
    ctrl_dir=$(resolve_control_dir || true)
    if [[ -n $ctrl_dir ]]; then
        install -d -m 0700 -o 10001 -g 10001 "$ctrl_dir" 2>/dev/null || install -d -m 0700 "$ctrl_dir"
    fi
    cat >"$systemd_dir/oscar-sandbox-agent.service" <<EOF
[Unit]
Description=OSCAR Training Sandbox Host Control Bridge
After=docker.service

[Service]
Type=oneshot
ExecStart=/bin/bash "$script_dir/oscar-sandbox.sh" poll-bridge
EOF
    if [[ -n $ctrl_dir ]]; then
        cat >"$systemd_dir/oscar-sandbox-agent.path" <<EOF
[Unit]
Description=Watch OSCAR Training Sandbox UI Launch Queue

[Path]
PathExists=$ctrl_dir/request.json
PathChanged=$ctrl_dir/request.json
Unit=oscar-sandbox-agent.service

[Install]
WantedBy=multi-user.target
EOF
    fi
    cat >"$systemd_dir/oscar-sandbox-agent.timer" <<EOF
[Unit]
Description=Refresh OSCAR Training Sandbox UI Host Status

[Timer]
OnBootSec=15s
OnUnitActiveSec=30s
AccuracySec=2s

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    if [[ -n $ctrl_dir ]]; then
        systemctl enable --now oscar-sandbox-agent.path >/dev/null 2>&1 || true
    fi
    systemctl enable --now oscar-sandbox-agent.timer
    write_bridge_status "" "enable-ui-bridge" "COMPLETED" "1-click Guided Walkthrough & Help (?) browser launch enabled."
    printf 'Enabled 1-click Training Sandbox launch in Guided Walkthrough & Help (?).\n'
}

install_agent() {
    require_root
    local bridge_pref
    bridge_pref=$(env_value OSCAR_SANDBOX_UI_BRIDGE 'enabled')
    if [[ -f /etc/oscar-sandbox-bridge.disabled || ${bridge_pref,,} == "disabled" || ${OSCAR_SANDBOX_SKIP_SYSTEMD:-0} == "1" ]]; then
        write_bridge_status || true
        return 0
    fi
    if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
        enable_ui_bridge >/dev/null 2>&1 || true
    else
        write_bridge_status || true
    fi
}

disable_ui_bridge() {
    require_root
    touch /etc/oscar-sandbox-bridge.disabled 2>/dev/null || true
    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now oscar-sandbox-agent.path oscar-sandbox-agent.timer oscar-sandbox-agent.service >/dev/null 2>&1 || true
        rm -f -- "$systemd_dir/oscar-sandbox-agent.path" "$systemd_dir/oscar-sandbox-agent.timer" "$systemd_dir/oscar-sandbox-agent.service"
        systemctl daemon-reload || true
    fi
    write_bridge_status "" "disable-ui-bridge" "COMPLETED" "Browser UI bridge disabled."
    printf 'Disabled Training Sandbox browser UI bridge.\n'
}

poll_bridge() {
    local ctrl_dir
    ctrl_dir=$(resolve_control_dir || true)
    [[ -n $ctrl_dir ]] || return 0
    local req_file="$ctrl_dir/request.json"
    if [[ ! -f $req_file ]]; then
        write_bridge_status
        return 0
    fi
    local processing="$ctrl_dir/request.processing.$$"
    mv -f -- "$req_file" "$processing" 2>/dev/null || return 0

    local raw req_id action port ttl
    raw=$(cat "$processing")
    rm -f -- "$processing"
    req_id=$(printf '%s' "$raw" | sed -n 's/.*"requestId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    action=$(printf '%s' "$raw" | sed -n 's/.*"action"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    port=$(printf '%s' "$raw" | sed -n 's/.*"httpsPort"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -n 1)
    ttl=$(printf '%s' "$raw" | sed -n 's/.*"ttlMinutes"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -n 1)
    [[ -n $port ]] || port=8444
    [[ -n $ttl ]] || ttl=120

    write_bridge_status "$req_id" "$action" "RUNNING" "Executing sandbox '${action}'..."
    case "$action" in
        start)
            if is_sandbox_running; then
                write_bridge_status "$req_id" "start" "COMPLETED" "Training Sandbox already running on port ${port}."
            elif do_start --port "$port" --ttl-minutes "$ttl" >/dev/null 2>&1; then
                write_bridge_status "$req_id" "start" "COMPLETED" "Training Sandbox ready on port ${port}."
            else
                write_bridge_status "$req_id" "start" "FAILED" "Sandbox start failed; check host RAM or run sudo bash oscar.sh sandbox start."
            fi
            ;;
        reset)
            if do_start --port "$port" --ttl-minutes "$ttl" >/dev/null 2>&1; then
                write_bridge_status "$req_id" "reset" "COMPLETED" "Training Sandbox reset and ready on port ${port}."
            else
                write_bridge_status "$req_id" "reset" "FAILED" "Sandbox reset failed; check host RAM or run sudo bash oscar.sh sandbox reset."
            fi
            ;;
        stop)
            do_stop >/dev/null 2>&1 || true
            write_bridge_status "$req_id" "stop" "COMPLETED" "Training Sandbox stopped and flushed."
            ;;
        *)
            write_bridge_status "$req_id" "$action" "COMPLETED" "Refreshed status."
            ;;
    esac
}

usage() {
    cat <<'EOF'
Usage:
  sudo bash oscar.sh sandbox start [--port 8444] [--ttl-minutes 120] [--track operator|supervisor|administrator] [--admin-password PASS]
  sudo bash oscar.sh sandbox stop
  sudo bash oscar.sh sandbox reset [--port 8444] [--ttl-minutes 120] [--track operator|supervisor|administrator]
  sudo bash oscar.sh sandbox status [--json]
  sudo bash oscar.sh sandbox enable-ui-bridge | disable-ui-bridge
EOF
}

subcmd=${1:-help}
if (($#)); then shift; fi

case "$subcmd" in
    start)
        require_root
        do_start "$@"
        ;;
    stop)
        require_root
        do_stop
        printf 'OSCAR Training Sandbox stopped and all ephemeral practice volumes were completely flushed.\n'
        ;;
    reset)
        require_root
        do_start "$@"
        ;;
    status)
        do_status "$@"
        ;;
    enable-ui-bridge)
        enable_ui_bridge
        ;;
    install-agent)
        install_agent
        ;;
    disable-ui-bridge)
        disable_ui_bridge
        ;;
    poll-bridge)
        require_root
        poll_bridge
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        usage >&2
        fail "Unknown sandbox subcommand: $subcmd"
        ;;
esac
