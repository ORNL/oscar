#!/usr/bin/env bash
set -Eeuo pipefail

script_path=${BASH_SOURCE[0]}
case $script_path in */*) script_parent=${script_path%/*} ;; *) script_parent=. ;; esac
script_dir=$(CDPATH= cd -- "$script_parent" && pwd -P)

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

get_env_value() {
    local name=$1 env_file="$script_dir/.env"
    [[ -f $env_file ]] || return 0
    awk -F= -v name="$name" '$1 == name { print substr($0, index($0, "=") + 1); exit }' "$env_file"
}

resolve_remote_access_dir() {
    local archive_dir storage_root parent
    archive_dir=$(get_env_value OSCAR_ARCHIVE_DIR)
    if [[ -n $archive_dir && $archive_dir == /* ]]; then
        storage_root=$(dirname "$archive_dir")
    else
        parent=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
        storage_root="$parent/oscar-storage"
    fi
    printf '%s/remote-access' "$storage_root"
}

valid_dns_name() {
    local value=$1
    [[ $value =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$ ]]
}

valid_service_slug() {
    local value=$1
    [[ $value =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]
}

read_kv_file() {
    local file=$1 key=$2
    [[ -f $file ]] || return 0
    awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$file"
}

run_tunnel_compose() {
    local ra_dir config_file oscar_version oscar_tz domain service token_file insecure_tls tunnel_mode impl ip_mode scope
    ra_dir=$(resolve_remote_access_dir)
    config_file="$ra_dir/octelium.env"
    [[ -f $config_file ]] || fail "Remote access is not configured ($config_file not found)."

    oscar_version=$(get_env_value OSCAR_VERSION)
    oscar_tz=$(get_env_value OSCAR_TIMEZONE)
    domain=$(read_kv_file "$config_file" OCTELIUM_DOMAIN)
    service=$(read_kv_file "$config_file" OCTELIUM_SERVICE)
    token_file=$(read_kv_file "$config_file" OCTELIUM_TOKEN_FILE)
    insecure_tls=$(read_kv_file "$config_file" OCTELIUM_INSECURE_TLS)
    tunnel_mode=$(read_kv_file "$config_file" OCTELIUM_TUNNEL_MODE)
    impl=$(read_kv_file "$config_file" OCTELIUM_IMPLEMENTATION)
    ip_mode=$(read_kv_file "$config_file" OCTELIUM_IP_MODE)
    scope=$(read_kv_file "$config_file" OCTELIUM_SCOPE)

    (
        cd "$script_dir"
        env -u COMPOSE_FILE -u COMPOSE_PROJECT_NAME -u COMPOSE_ENV_FILES -u COMPOSE_PROFILES \
            OSCAR_VERSION="${oscar_version:-local}" \
            OSCAR_TIMEZONE="${oscar_tz:-UTC}" \
            OCTELIUM_DOMAIN="$domain" \
            OCTELIUM_SERVICE="$service" \
            OCTELIUM_TOKEN_FILE="$token_file" \
            OCTELIUM_INSECURE_TLS="${insecure_tls:-false}" \
            OCTELIUM_TUNNEL_MODE="${tunnel_mode:-wg}" \
            OCTELIUM_IMPLEMENTATION="${impl:-gvisor}" \
            OCTELIUM_IP_MODE="${ip_mode:-v4}" \
            OCTELIUM_SCOPE="${scope:-}" \
            docker compose --project-name oscar \
                --env-file "$script_dir/.env" \
                --file "$script_dir/compose.yaml" \
                --file "$script_dir/compose.octelium.yaml" \
                "$@"
    )
}

ensure_tunnel_image() {
    local force_rebuild=${1:-false} oscar_version image_tag had_existing=false
    oscar_version=$(get_env_value OSCAR_VERSION)
    oscar_version=${oscar_version:-local}
    image_tag="oscar-tunnel:${oscar_version}"
    if docker image inspect "$image_tag" >/dev/null 2>&1; then
        had_existing=true
    fi
    if [[ $force_rebuild == true || $had_existing == false ]]; then
        printf 'Building %s...\n' "$image_tag"
        if ! (
            cd "$script_dir"
            docker build \
                --build-arg "OSCAR_VERSION=${oscar_version}" \
                --tag "$image_tag" \
                --file docker/tunnel/Dockerfile \
                .
        ); then
            if $had_existing; then
                printf 'WARNING: Could not rebuild %s (offline or registry unreachable); retaining existing local tunnel image.\n' "$image_tag" >&2
            else
                fail "Failed to build $image_tag and no preloaded local image is available."
            fi
        fi
    fi
}

print_usage() {
    cat <<'EOF'
OSCAR Remote Access Administration (Octelium Zero Trust Sidecar)

  sudo ./oscar.sh remote-access enable --domain <CLUSTER_DOMAIN> --service <SERVICE_NAME> --token-file <PATH>
      [--insecure-tls] [--tunnel-mode wg|quicv0] [--scope <SCOPE>]
  sudo ./oscar.sh remote-access status
  sudo ./oscar.sh remote-access logs [--tail 200] [--follow]
  sudo ./oscar.sh remote-access rotate-token --token-file <PATH>
  sudo ./oscar.sh remote-access disable [--purge-token]
  ./oscar.sh remote-access hub-manifest --domain <CLUSTER_DOMAIN> --service <SERVICE_NAME>
      [--workload-user <USER>] [--display-name <NAME>] [--output <FILE>]
EOF
}

subcommand=${1:-help}
shift || true

case "$subcommand" in
    help|--help|-h)
        print_usage
        ;;
    enable)
        domain=""
        service=""
        src_token_file=""
        insecure_tls="false"
        tunnel_mode="wg"
        scope=""
        while (($# > 0)); do
            case "$1" in
                --domain) domain=${2:?missing --domain value}; shift 2 ;;
                --service) service=${2:?missing --service value}; shift 2 ;;
                --token-file) src_token_file=${2:?missing --token-file path}; shift 2 ;;
                --insecure-tls) insecure_tls="true"; shift ;;
                --tunnel-mode) tunnel_mode=${2:?missing --tunnel-mode value}; shift 2 ;;
                --scope) scope=${2:?missing --scope value}; shift 2 ;;
                *) fail "Unknown option for remote-access enable: $1" ;;
            esac
        done
        [[ -n $domain ]] || fail "--domain is required."
        [[ -n $service ]] || fail "--service is required."
        [[ -n $src_token_file ]] || fail "--token-file is required."
        valid_dns_name "$domain" || fail "Invalid Octelium cluster domain: $domain"
        valid_service_slug "$service" || fail "Service name must be 1-63 lowercase letters, digits, or hyphens: $service"
        [[ $tunnel_mode == wg || $tunnel_mode == wireguard || $tunnel_mode == quicv0 ]] ||
            fail "--tunnel-mode must be wg or quicv0."
        [[ -f $src_token_file && ! -L $src_token_file && -s $src_token_file ]] ||
            fail "Token file must be a non-empty regular file: $src_token_file"

        ra_dir=$(resolve_remote_access_dir)
        install -d -m 0700 "$ra_dir"
        token_dest="$ra_dir/octelium-token.txt"
        config_dest="$ra_dir/octelium.env"

        umask 0077
        tr -d '\r\n ' <"$src_token_file" >"$token_dest.tmp"
        [[ -s $token_dest.tmp ]] || { rm -f "$token_dest.tmp"; fail "Token file contained only whitespace."; }
        chown 10002:10002 "$token_dest.tmp" 2>/dev/null || chmod 0644 "$token_dest.tmp"
        chmod 0400 "$token_dest.tmp" 2>/dev/null || true
        mv -f "$token_dest.tmp" "$token_dest"

        cat >"$config_dest.tmp" <<EOF
OCTELIUM_ENABLED=true
OCTELIUM_DOMAIN=$domain
OCTELIUM_SERVICE=$service
OCTELIUM_TOKEN_FILE=$token_dest
OCTELIUM_INSECURE_TLS=$insecure_tls
OCTELIUM_TUNNEL_MODE=$tunnel_mode
OCTELIUM_IMPLEMENTATION=gvisor
OCTELIUM_IP_MODE=v4
OCTELIUM_SCOPE=$scope
EOF
        chmod 0600 "$config_dest.tmp"
        mv -f "$config_dest.tmp" "$config_dest"

        ensure_tunnel_image
        run_tunnel_compose up --detach --no-build tunnel
        printf 'OSCAR Octelium tunnel enabled: https://%s.%s\n' "$service" "$domain"
        ;;
    rotate-token)
        src_token_file=""
        while (($# > 0)); do
            case "$1" in
                --token-file) src_token_file=${2:?missing --token-file path}; shift 2 ;;
                *) fail "Unknown option for remote-access rotate-token: $1" ;;
            esac
        done
        [[ -n $src_token_file && -f $src_token_file && ! -L $src_token_file && -s $src_token_file ]] ||
            fail "--token-file must point to a non-empty regular file."
        ra_dir=$(resolve_remote_access_dir)
        config_file="$ra_dir/octelium.env"
        [[ -f $config_file ]] || fail "Remote access is not configured yet. Run remote-access enable first."
        token_dest=$(read_kv_file "$config_file" OCTELIUM_TOKEN_FILE)
        [[ -n $token_dest ]] || token_dest="$ra_dir/octelium-token.txt"
        umask 0077
        tr -d '\r\n ' <"$src_token_file" >"$token_dest.tmp"
        chown 10002:10002 "$token_dest.tmp" 2>/dev/null || chmod 0644 "$token_dest.tmp"
        chmod 0400 "$token_dest.tmp" 2>/dev/null || true
        mv -f "$token_dest.tmp" "$token_dest"
        if [[ $(read_kv_file "$config_file" OCTELIUM_ENABLED) == true ]]; then
            run_tunnel_compose up --detach --force-recreate --no-build tunnel
        fi
        printf 'Rotated Octelium authentication token and restarted tunnel.\n'
        ;;
    disable)
        purge_token=false
        while (($# > 0)); do
            case "$1" in
                --purge-token) purge_token=true; shift ;;
                *) fail "Unknown option for remote-access disable: $1" ;;
            esac
        done
        ra_dir=$(resolve_remote_access_dir)
        config_file="$ra_dir/octelium.env"
        if [[ -f $config_file ]]; then
            run_tunnel_compose rm --force --stop tunnel >/dev/null 2>&1 || docker rm -f oscar-tunnel-1 >/dev/null 2>&1 || true
            sed -i.bak 's/^OCTELIUM_ENABLED=.*/OCTELIUM_ENABLED=false/' "$config_file" && rm -f "$config_file.bak"
            if $purge_token; then
                rm -f "$ra_dir/octelium-token.txt"
            fi
        else
            docker rm -f oscar-tunnel-1 >/dev/null 2>&1 || true
        fi
        printf 'OSCAR Octelium remote-access tunnel disabled.\n'
        ;;
    status)
        ra_dir=$(resolve_remote_access_dir)
        config_file="$ra_dir/octelium.env"
        if [[ ! -f $config_file ]]; then
            printf 'Remote Access (Octelium): disabled (not configured)\n'
            exit 0
        fi
        enabled=$(read_kv_file "$config_file" OCTELIUM_ENABLED)
        domain=$(read_kv_file "$config_file" OCTELIUM_DOMAIN)
        service=$(read_kv_file "$config_file" OCTELIUM_SERVICE)
        printf 'Remote Access (Octelium): %s\n' "${enabled:-false}"
        printf 'Public Service URL:       https://%s.%s\n' "$service" "$domain"
        docker ps --filter "name=^/oscar-tunnel-1$" --format "Tunnel Container:         {{.Names}} ({{.Status}})"
        ;;
    logs)
        tail_lines=200
        follow=false
        while (($# > 0)); do
            case "$1" in
                --tail) tail_lines=${2:?missing --tail count}; shift 2 ;;
                --follow|-f) follow=true; shift ;;
                *) fail "Unknown option for remote-access logs: $1" ;;
            esac
        done
        args=(logs --tail "$tail_lines")
        $follow && args+=(--follow)
        args+=(tunnel)
        run_tunnel_compose "${args[@]}"
        ;;
    sync)
        rebuild_tunnel=false
        while (($# > 0)); do
            case "$1" in
                --rebuild) rebuild_tunnel=true; shift ;;
                *) fail "Unknown option for remote-access sync: $1" ;;
            esac
        done
        ra_dir=$(resolve_remote_access_dir)
        config_file="$ra_dir/octelium.env"
        if [[ -f $config_file && $(read_kv_file "$config_file" OCTELIUM_ENABLED) == true ]]; then
            ensure_tunnel_image "$rebuild_tunnel"
            run_tunnel_compose up --detach --force-recreate --no-build tunnel
        fi
        ;;
    stop-if-enabled)
        if docker ps -q --filter "name=^/oscar-tunnel-1$" | grep -q .; then
            docker stop oscar-tunnel-1 >/dev/null
        fi
        ;;
    hub-manifest)
        domain=""
        service=""
        workload_user=""
        display_name=""
        output_file=""
        while (($# > 0)); do
            case "$1" in
                --domain) domain=${2:?missing --domain}; shift 2 ;;
                --service) service=${2:?missing --service}; shift 2 ;;
                --workload-user) workload_user=${2:?missing --workload-user}; shift 2 ;;
                --display-name) display_name=${2:?missing --display-name}; shift 2 ;;
                --output) output_file=${2:?missing --output}; shift 2 ;;
                *) fail "Unknown option for remote-access hub-manifest: $1" ;;
            esac
        done
        [[ -n $domain ]] || fail "--domain is required."
        [[ -n $service ]] || fail "--service is required."
        valid_dns_name "$domain" || fail "Invalid domain: $domain"
        valid_service_slug "$service" || fail "Invalid service name: $service"
        workload_user=${workload_user:-"oscar-node-${service}"}
        display_name=${display_name:-"OSCAR Site (${service})"}

        manifest=$(cat <<EOF
# Apply on your Octelium Cluster Hub with:
#   octeliumctl apply -
# Then mint a scoped node connector token with:
#   octeliumctl create credential --user ${workload_user} --expire-in 90days > ${service}.token
kind: Policy
metadata:
  name: oscar-${service}-operator-policy
  displayName: ${display_name} Operator Policy
spec:
  rules:
    - name: deny-sensorhub-admin-by-default
      effect: DENY
      condition:
        match: 'ctx.http.path.startsWith("/sensorhub/admin")'
    - name: allow-oscar-viewer-and-apis
      effect: ALLOW
      condition:
        match: 'ctx.service.metadata.name in ["${service}", "${service}.default"]'
---
kind: Group
metadata:
  name: oscar-${service}-operators
  displayName: ${display_name} Operators
spec:
  authorization:
    policies:
      - oscar-${service}-operator-policy
---
kind: User
metadata:
  name: ${workload_user}
  displayName: ${display_name} Outbound Connector
spec:
  type: WORKLOAD
---
kind: Service
metadata:
  name: ${service}
  displayName: ${display_name}
spec:
  mode: WEB
  isPublic: true
  config:
    tls:
      insecureSkipVerify: true
    http:
      header:
        authorizationMode: PASS
        host:
          preserve: true
    upstream:
      user: ${workload_user}
      url: https://gateway:8443
EOF
)
        if [[ -n $output_file ]]; then
            printf '%s\n' "$manifest" >"$output_file"
            printf 'Wrote Octelium Hub manifest to %s\n' "$output_file"
        else
            printf '%s\n' "$manifest"
        fi
        ;;
    *)
        fail "Unknown remote-access subcommand: $subcommand"
        ;;
esac
