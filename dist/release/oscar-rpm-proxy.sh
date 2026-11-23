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

read_kv_file() {
    local file=$1 key=$2
    [[ -f $file ]] || return 0
    awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$file"
}

resolve_rpm_proxy_dir() {
    local archive_dir storage_root parent
    if [[ -n ${OSCAR_RPM_PROXY_STATE_DIR:-} ]]; then
        printf '%s' "$OSCAR_RPM_PROXY_STATE_DIR"
        return 0
    fi
    archive_dir=$(get_env_value OSCAR_ARCHIVE_DIR)
    if [[ -n $archive_dir && $archive_dir == /* ]]; then
        storage_root=$(dirname "$archive_dir")
    else
        parent=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
        storage_root="$parent/oscar-storage"
    fi
    printf '%s/rpm-proxy' "$storage_root"
}

resolve_oscar_version() {
    local ver
    ver=$(get_env_value OSCAR_VERSION)
    if [[ -z $ver && -f $script_dir/.env.example ]]; then
        ver=$(awk -F= '$1 == "OSCAR_VERSION" { print substr($0, index($0, "=") + 1); exit }' "$script_dir/.env.example")
    fi
    printf '%s' "${ver:-local}"
}

ensure_proxy_image() {
    local force_rebuild=${1:-false} oscar_version image_tag had_existing=false
    oscar_version=$(resolve_oscar_version)
    image_tag="oscar-rpm-proxy:${oscar_version}"
    if docker image inspect "$image_tag" >/dev/null 2>&1; then
        had_existing=true
    fi
    if [[ $force_rebuild == true || $had_existing == false ]]; then
        if [[ -f $script_dir/offline-images.tar ]] && ! $had_existing; then
            printf 'Importing %s from offline-images.tar...\n' "$image_tag"
            docker load --input "$script_dir/offline-images.tar" >/dev/null
            if docker image inspect "$image_tag" >/dev/null 2>&1; then
                return 0
            fi
        fi
        printf 'Building %s...\n' "$image_tag"
        if ! (
            cd "$script_dir"
            docker build \
                --build-arg "OSCAR_VERSION=${oscar_version}" \
                --tag "$image_tag" \
                --file docker/rpm-proxy/Dockerfile \
                .
        ); then
            if $had_existing; then
                printf 'WARNING: Could not rebuild %s (offline or registry unreachable); retaining existing local image.\n' "$image_tag" >&2
            else
                fail "Failed to build $image_tag and no preloaded local image is available."
            fi
        fi
    fi
}

write_network_override() {
    local rp_dir=$1 config_file=$2 override_file="$1/compose.network.yaml"
    local needs_net_raw=false
    if command -v python3 >/dev/null 2>&1 && [[ -f $config_file ]]; then
        if python3 - "$config_file" <<'PY'
import json, pathlib, sys
cfg = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
has_if = any(
    isinstance(svc, dict) and isinstance(svc.get("upstream"), dict) and bool(svc["upstream"].get("interface"))
    for svc in cfg.get("services", [])
)
raise SystemExit(0 if has_if else 1)
PY
        then
            needs_net_raw=true
        fi
    fi

    if [[ "$(uname -s)" == "Linux" ]]; then
        {
            printf 'services:\n'
            printf '  rpm-proxy:\n'
            printf '    network_mode: host\n'
            if $needs_net_raw; then
                printf '    cap_add:\n'
                printf '      - NET_RAW\n'
            fi
        } > "$override_file"
    else
        python3 - "$config_file" "$override_file" <<'PY'
import json, pathlib, sys
cfg = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
ports = []
seen = set()
for svc in cfg.get("services", []):
    if not svc.get("enabled", True):
        continue
    listen = svc.get("listen", [])
    if isinstance(listen, str):
        listen = [listen]
    for ep in listen:
        host, port = ep.rsplit(":", 1)
        mapping = f"{host}:{port}:{port}/tcp" if host not in ("0.0.0.0", "::") else f"{port}:{port}/tcp"
        if mapping not in seen:
            seen.add(mapping)
            ports.append(mapping)
st = cfg.get("status_listen")
if st:
    shost, sport = st.rsplit(":", 1)
    smapping = f"{shost}:{sport}:{sport}/tcp" if shost not in ("0.0.0.0", "::") else f"{sport}:{sport}/tcp"
    if smapping not in seen:
        ports.append(smapping)
lines = ["services:", "  rpm-proxy:", "    ports:"]
for p in ports:
    lines.append(f'      - "{p}"')
pathlib.Path(sys.argv[2]).write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
    fi
}

parse_status_endpoint() {
    local config_file=$1
    if command -v python3 >/dev/null 2>&1 && [[ -f $config_file ]]; then
        python3 - "$config_file" <<'PY'
import json, pathlib, sys
cfg = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
st = cfg.get("status_listen") or "127.0.0.1:9090"
host, port = st.rsplit(":", 1)
check_host = "127.0.0.1" if host in ("0.0.0.0", "::", "[::]") else host
print(f"{check_host} {port}")
PY
    else
        printf '127.0.0.1 9090\n'
    fi
}

run_proxy_compose() {
    local rp_dir config_file override_file oscar_version oscar_tz check_host status_port env_arg=()
    rp_dir=$(resolve_rpm_proxy_dir)
    config_file="$rp_dir/config.json"
    override_file="$rp_dir/compose.network.yaml"
    [[ -f $config_file ]] || fail "RPM Edge Proxy is not configured ($config_file not found). Run './oscar.sh rpm-proxy configure --from-csv <config.csv>' first."
    [[ -f $override_file ]] || write_network_override "$rp_dir" "$config_file"

    oscar_version=$(resolve_oscar_version)
    oscar_tz=$(get_env_value OSCAR_TIMEZONE)
    read -r check_host status_port < <(parse_status_endpoint "$config_file")
    [[ -f $script_dir/.env ]] && env_arg=(--env-file "$script_dir/.env")

    (
        cd "$script_dir"
        env -u COMPOSE_FILE -u COMPOSE_PROJECT_NAME -u COMPOSE_ENV_FILES -u COMPOSE_PROFILES \
            OSCAR_VERSION="${oscar_version}" \
            OSCAR_TIMEZONE="${oscar_tz:-UTC}" \
            OSCAR_RPM_PROXY_CONFIG_FILE="$config_file" \
            OSCAR_RPM_PROXY_STATUS_CHECK_HOST="${check_host:-127.0.0.1}" \
            OSCAR_RPM_PROXY_STATUS_PORT="${status_port:-9090}" \
            docker compose --project-name oscar-rpm-proxy \
                "${env_arg[@]}" \
                --file "$script_dir/compose.rpm-proxy.yaml" \
                --file "$override_file" \
                "$@"
    )
}

apply_linux_vips() {
    local nic=$1 prefix=$2 vip_list_file=$3
    [[ "$(uname -s)" == "Linux" ]] || fail "--apply-vip-interface is supported only on Ubuntu / Linux hosts."
    [[ ${EUID:-$(id -u)} -eq 0 ]] || fail "--apply-vip-interface requires root privileges (run via sudo)."
    ip link show dev "$nic" >/dev/null 2>&1 || fail "Network interface '$nic' does not exist."
    [[ -f $vip_list_file ]] || fail "VIP list file not found: $vip_list_file"

    # Prevent ARP flux when hosting 1..50 virtual IPs on the same subnet
    cat > /etc/sysctl.d/91-oscar-rpm-proxy-arp.conf <<'EOF'
# Managed by oscar-rpm-proxy: prevent multi-VIP ARP flux on CAS/sensor VLANs
net.ipv4.conf.all.arp_announce = 2
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.default.arp_ignore = 1
EOF
    sysctl --system >/dev/null 2>&1 || true

    local idx=1 vip
    while IFS= read -r vip; do
        vip=${vip//$'\r'/}
        [[ -n $vip ]] || continue
        if ! ip -4 addr show dev "$nic" | grep -Fq "inet ${vip}/"; then
            if command -v arping >/dev/null 2>&1; then
                if ! arping -D -I "$nic" -c 1 -w 1 "$vip" >/dev/null 2>&1; then
                    fail "ARP conflict detected on $nic for virtual IP $vip! Choose an unused --vip-start-ip range."
                fi
            fi
            ip addr replace "${vip}/${prefix}" dev "$nic"
        fi
        ((idx += 1))
    done < "$vip_list_file"

    # Persist secondary VIP assignment across reboots via systemd oneshot unit
    local unit_script="/usr/local/libexec/oscar-rpm-proxy-apply-vips.sh"
    install -d -m 0755 /usr/local/libexec
    cat > "$unit_script" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
nic=${nic@Q}
prefix=${prefix@Q}
vip_file=${vip_list_file@Q}
[[ -f \$vip_file ]] || exit 0
while IFS= read -r vip; do
    vip=\${vip//\$'\r'/}
    [[ -n \$vip ]] || continue
    ip addr replace "\${vip}/\${prefix}" dev "\$nic" || true
done < "\$vip_file"
EOF
    chmod 0755 "$unit_script"

    if [[ -d /etc/systemd/system ]]; then
        cat > /etc/systemd/system/oscar-rpm-proxy-vips.service <<EOF
[Unit]
Description=OSCAR Rapiscan RPM Edge Proxy Virtual IP Aliases
After=network-online.target
Wants=network-online.target
Before=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${unit_script}

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl enable oscar-rpm-proxy-vips.service >/dev/null 2>&1 || true
    fi
    printf 'Applied and persisted %d virtual IP alias(es) on %s (/%s).\n' "$((idx - 1))" "$nic" "$prefix"
}

remove_linux_vips() {
    local nic=$1 prefix=$2 vip_list_file=$3
    [[ "$(uname -s)" == "Linux" ]] || return 0
    [[ -n $nic && -f $vip_list_file ]] || return 0
    while IFS= read -r vip; do
        vip=${vip//$'\r'/}
        [[ -n $vip ]] || continue
        ip addr del "${vip}/${prefix}" dev "$nic" 2>/dev/null || true
    done < "$vip_list_file"
    if [[ -f /etc/systemd/system/oscar-rpm-proxy-vips.service ]]; then
        systemctl disable oscar-rpm-proxy-vips.service >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/oscar-rpm-proxy-vips.service /usr/local/libexec/oscar-rpm-proxy-apply-vips.sh
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
}

print_usage() {
    cat <<'EOF'
OSCAR Side-by-Side CAS Rapiscan RPM Real-Time Edge Proxy (oscar-rpm-proxy)

Maintains a single upstream TCP connection per Rapiscan RPM (1..50+ lanes) and
fans out real-time radiation telemetry simultaneously to both an existing
Central Alarm Station (CAS) and OSCAR, with cached SG1..SG3 / SN1..SN2 setup
replay and <= 4.0s upstream-gated disconnect propagation.

Runs in an isolated Docker Compose project (oscar-rpm-proxy) so 'oscar restart'
and 'oscar upgrade' never drop the live CAS TCP stream.

Usage:
  sudo ./oscar.sh rpm-proxy configure --from-csv <LANES_CSV> [options]
      --mode port-map|virtual-ip          Listener topology (default: port-map)
      --listen-host <IP>                  Port-map listen IP (default: 0.0.0.0)
      --base-port <PORT>                  First lane port (default: 11601 -> 11601..11650)
      --vip-start-ip <IP>                 First virtual IP for --mode virtual-ip (:1600 per lane)
      --vip-port <PORT>                   Virtual IP TCP port (default: 1600)
      --vip-prefix <CIDR_BITS>            Subnet prefix for --apply-vip-interface (default: 24)
      --apply-vip-interface <NIC>         Bind & persist virtual IPs on Ubuntu NIC (with ARP check)
      --oscar-target-host <IP_OR_HOST>    Host written to generated OSCAR CSV (default: 127.0.0.1)
      --upstream-interface <NIC>          Bind upstream RPM sockets to Linux NIC (SO_BINDTODEVICE)
      --source-ip <IP>                    Bind upstream RPM sockets to specific host source IP
      --allowed-client <CIDR>             Restrict downstream consumers (repeatable; e.g. CAS + 127.0.0.1/32)
      --client-writes discard|allow_primary|forward
                                          Consumer-to-RPM write policy (default: discard)
      --primary-write-client <CIDR>       Allowed writer CIDR when --client-writes allow_primary
      --idle-timeout-seconds <SEC>        Silent cable-pull / freeze timeout (default: 4.0)
      --first-line-timeout-seconds <SEC>  Require live RPM line before opening listener (default: 4.0)
      --status-listen <IP:PORT>           Local health/metrics HTTP endpoint (default: 127.0.0.1:9090)
      --emit-oscar-csv <PATH>             Output 20-col OSCAR CSV pointed at proxy (default: <storage>/rpm-proxy/oscar-proxied-lanes.csv)
      --start                             Immediately build/load and start oscar-rpm-proxy

  sudo ./oscar.sh rpm-proxy configure --config-file <CUSTOM_CONFIG_JSON> [--start]
  sudo ./oscar.sh rpm-proxy validate
  sudo ./oscar.sh rpm-proxy start
  sudo ./oscar.sh rpm-proxy stop
  sudo ./oscar.sh rpm-proxy restart
  sudo ./oscar.sh rpm-proxy upgrade
  ./oscar.sh rpm-proxy status
  sudo ./oscar.sh rpm-proxy logs [--tail 200] [--follow]
  sudo ./oscar.sh rpm-proxy disable [--remove-vips]
EOF
}

subcommand=${1:-help}
shift || true

if [[ ${OSCAR_STORAGE_TEST_MODE:-0} == 1 && ${OSCAR_RPM_PROXY_TEST_ALLOW:-0} != 1 ]]; then
    case "$subcommand" in
        build-image-only|sync|stop-if-enabled|support-snapshot)
            exit 0
            ;;
    esac
fi

case "$subcommand" in
    help|--help|-h)
        print_usage
        ;;
    configure)
        from_csv=""
        custom_config=""
        mode="port-map"
        listen_host="0.0.0.0"
        base_port="11601"
        vip_start_ip=""
        vip_port="1600"
        vip_prefix="24"
        apply_vip_nic=""
        oscar_target_host="127.0.0.1"
        upstream_interface=""
        source_ip=""
        client_writes="discard"
        idle_timeout="4.0"
        first_line_timeout="4.0"
        status_listen="127.0.0.1:9090"
        emit_oscar_csv=""
        start_now=false
        allowed_clients=()
        primary_writers=()

        while (($# > 0)); do
            case "$1" in
                --from-csv) from_csv=${2:?missing --from-csv path}; shift 2 ;;
                --config-file) custom_config=${2:?missing --config-file path}; shift 2 ;;
                --mode) mode=${2:?missing --mode}; shift 2 ;;
                --listen-host) listen_host=${2:?missing --listen-host}; shift 2 ;;
                --base-port) base_port=${2:?missing --base-port}; shift 2 ;;
                --vip-start-ip) vip_start_ip=${2:?missing --vip-start-ip}; shift 2 ;;
                --vip-port) vip_port=${2:?missing --vip-port}; shift 2 ;;
                --vip-prefix) vip_prefix=${2:?missing --vip-prefix}; shift 2 ;;
                --apply-vip-interface) apply_vip_nic=${2:?missing --apply-vip-interface}; shift 2 ;;
                --oscar-target-host) oscar_target_host=${2:?missing --oscar-target-host}; shift 2 ;;
                --upstream-interface) upstream_interface=${2:?missing --upstream-interface}; shift 2 ;;
                --source-ip) source_ip=${2:?missing --source-ip}; shift 2 ;;
                --allowed-client) allowed_clients+=("${2:?missing --allowed-client}"); shift 2 ;;
                --client-writes) client_writes=${2:?missing --client-writes}; shift 2 ;;
                --primary-write-client) primary_writers+=("${2:?missing --primary-write-client}"); shift 2 ;;
                --idle-timeout-seconds) idle_timeout=${2:?missing --idle-timeout-seconds}; shift 2 ;;
                --first-line-timeout-seconds) first_line_timeout=${2:?missing --first-line-timeout-seconds}; shift 2 ;;
                --status-listen) status_listen=${2:?missing --status-listen}; shift 2 ;;
                --emit-oscar-csv) emit_oscar_csv=${2:?missing --emit-oscar-csv}; shift 2 ;;
                --start) start_now=true; shift ;;
                *) fail "Unknown option for rpm-proxy configure: $1" ;;
            esac
        done

        [[ -n $from_csv || -n $custom_config ]] || fail "Specify either --from-csv <LANES_CSV> or --config-file <JSON>."
        [[ -z $from_csv || -z $custom_config ]] || fail "Specify either --from-csv or --config-file, not both."

        rp_dir=$(resolve_rpm_proxy_dir)
        install -d -m 0755 "$rp_dir"
        config_out="$rp_dir/config.json"
        vip_list_out="$rp_dir/vips.txt"
        [[ -n $emit_oscar_csv ]] || emit_oscar_csv="$rp_dir/oscar-proxied-lanes.csv"

        if [[ -n $custom_config ]]; then
            [[ -f $custom_config ]] || fail "Custom config file not found: $custom_config"
            cp -f "$custom_config" "$config_out"
            chmod 0644 "$config_out"
            if command -v python3 >/dev/null 2>&1; then
                PYTHONPATH="$script_dir/docker/rpm-proxy" python3 -m oscar_rpm_proxy --config "$config_out" --validate
            fi
        else
            [[ -f $from_csv ]] || fail "Input lane CSV file not found: $from_csv"
            py_args=(
                -m oscar_rpm_proxy
                --generate-from-csv "$from_csv"
                --config "$config_out"
                --mode "$mode"
                --listen-host "$listen_host"
                --base-port "$base_port"
                --vip-port "$vip_port"
                --oscar-target-host "$oscar_target_host"
                --client-writes "$client_writes"
                --idle-timeout-seconds "$idle_timeout"
                --first-line-timeout-seconds "$first_line_timeout"
                --status-listen "$status_listen"
                --emit-oscar-csv "$emit_oscar_csv"
            )
            [[ -n $vip_start_ip ]] && py_args+=(--vip-start-ip "$vip_start_ip" --emit-vip-list "$vip_list_out")
            [[ -n $upstream_interface ]] && py_args+=(--upstream-interface "$upstream_interface")
            [[ -n $source_ip ]] && py_args+=(--source-ip "$source_ip")
            for cidr in "${allowed_clients[@]}"; do py_args+=(--allowed-client "$cidr"); done
            for cidr in "${primary_writers[@]}"; do py_args+=(--primary-write-client "$cidr"); done

            if command -v python3 >/dev/null 2>&1; then
                PYTHONPATH="$script_dir/docker/rpm-proxy" python3 "${py_args[@]}"
            else
                ensure_proxy_image false
                oscar_version=$(resolve_oscar_version)
                csv_abs=$(realpath "$from_csv")
                out_csv_abs=$(realpath -m "$emit_oscar_csv")
                install -d -m 0755 "$(dirname "$out_csv_abs")"
                docker run --rm \
                    -v "$csv_abs:/in/lanes.csv:ro" \
                    -v "$rp_dir:/out" \
                    -v "$(dirname "$out_csv_abs"):/oscar_csv_out" \
                    "oscar-rpm-proxy:${oscar_version}" \
                    --generate-from-csv /in/lanes.csv \
                    --config /out/config.json \
                    --mode "$mode" \
                    --listen-host "$listen_host" \
                    --base-port "$base_port" \
                    ${vip_start_ip:+--vip-start-ip "$vip_start_ip" --emit-vip-list /out/vips.txt} \
                    --vip-port "$vip_port" \
                    --oscar-target-host "$oscar_target_host" \
                    ${upstream_interface:+--upstream-interface "$upstream_interface"} \
                    ${source_ip:+--source-ip "$source_ip"} \
                    --client-writes "$client_writes" \
                    --idle-timeout-seconds "$idle_timeout" \
                    --first-line-timeout-seconds "$first_line_timeout" \
                    --status-listen "$status_listen" \
                    --emit-oscar-csv "/oscar_csv_out/$(basename "$out_csv_abs")"
            fi
            chmod 0644 "$config_out"
            printf 'Generated proxy configuration: %s\n' "$config_out"
            printf 'Generated 20-column OSCAR import CSV: %s\n' "$emit_oscar_csv"
        fi

        if [[ -n $apply_vip_nic ]]; then
            [[ $mode == "virtual-ip" ]] || fail "--apply-vip-interface requires --mode virtual-ip."
            apply_linux_vips "$apply_vip_nic" "$vip_prefix" "$vip_list_out"
        fi

        write_network_override "$rp_dir" "$config_out"
        read -r check_host status_port < <(parse_status_endpoint "$config_out")
        existing_enabled=$(read_kv_file "$rp_dir/rpm-proxy.env" RPM_PROXY_ENABLED)
        cat > "$rp_dir/rpm-proxy.env" <<EOF
RPM_PROXY_ENABLED=${existing_enabled:-false}
RPM_PROXY_MODE=${mode}
RPM_PROXY_STATUS_HOST=${check_host}
RPM_PROXY_STATUS_PORT=${status_port}
RPM_PROXY_VIP_INTERFACE=${apply_vip_nic}
RPM_PROXY_VIP_PREFIX=${vip_prefix}
EOF
        chmod 0644 "$rp_dir/rpm-proxy.env"

        if $start_now; then
            bash "$0" start
        else
            printf "Run 'sudo ./oscar.sh rpm-proxy start' to launch the side-by-side RPM fan-out proxy.\n"
        fi
        ;;
    validate)
        rp_dir=$(resolve_rpm_proxy_dir)
        config_file="$rp_dir/config.json"
        [[ -f $config_file ]] || fail "RPM Edge Proxy config not found: $config_file"
        if command -v python3 >/dev/null 2>&1; then
            PYTHONPATH="$script_dir/docker/rpm-proxy" python3 -m oscar_rpm_proxy --config "$config_file" --validate
        else
            ensure_proxy_image false
            oscar_version=$(resolve_oscar_version)
            docker run --rm -v "$config_file:/config/config.json:ro" "oscar-rpm-proxy:${oscar_version}" --config /config/config.json --validate
        fi
        ;;
    start|enable)
        rp_dir=$(resolve_rpm_proxy_dir)
        config_file="$rp_dir/config.json"
        [[ -f $config_file ]] || fail "RPM Edge Proxy is not configured ($config_file not found). Run 'sudo ./oscar.sh rpm-proxy configure --from-csv <CSV>' first."
        write_network_override "$rp_dir" "$config_file"
        ensure_proxy_image false
        if [[ -f $rp_dir/rpm-proxy.env ]]; then
            sed -i 's/^RPM_PROXY_ENABLED=.*/RPM_PROXY_ENABLED=true/' "$rp_dir/rpm-proxy.env"
        else
            printf 'RPM_PROXY_ENABLED=true\n' > "$rp_dir/rpm-proxy.env"
        fi
        run_proxy_compose up -d
        printf 'OSCAR RPM Edge Proxy started (isolated project: oscar-rpm-proxy).\n'
        ;;
    stop)
        rp_dir=$(resolve_rpm_proxy_dir)
        if [[ -f $rp_dir/config.json ]]; then
            run_proxy_compose stop
            printf 'OSCAR RPM Edge Proxy stopped.\n'
        else
            printf 'OSCAR RPM Edge Proxy is not configured.\n'
        fi
        ;;
    restart)
        rp_dir=$(resolve_rpm_proxy_dir)
        [[ -f $rp_dir/config.json ]] || fail "RPM Edge Proxy is not configured."
        write_network_override "$rp_dir" "$rp_dir/config.json"
        ensure_proxy_image false
        run_proxy_compose up -d --force-recreate
        printf 'OSCAR RPM Edge Proxy restarted.\n'
        ;;
    upgrade)
        rp_dir=$(resolve_rpm_proxy_dir)
        [[ -f $rp_dir/config.json ]] || fail "RPM Edge Proxy is not configured."
        write_network_override "$rp_dir" "$rp_dir/config.json"
        if [[ -f $script_dir/offline-images.tar ]]; then
            ensure_proxy_image false
        else
            ensure_proxy_image true
        fi
        run_proxy_compose up -d --force-recreate
        printf 'OSCAR RPM Edge Proxy upgraded to version %s.\n' "$(resolve_oscar_version)"
        ;;
    build-image-only)
        # Called during 'oscar upgrade': pre-stages the new oscar-rpm-proxy:<version>
        # image WITHOUT restarting the running container so active CAS TCP feeds never drop!
        rp_dir=$(resolve_rpm_proxy_dir)
        enabled=$(read_kv_file "$rp_dir/rpm-proxy.env" RPM_PROXY_ENABLED)
        if [[ $enabled == "true" && -f $rp_dir/config.json ]]; then
            if [[ -f $script_dir/offline-images.tar ]]; then
                ensure_proxy_image false
            else
                ensure_proxy_image true
            fi
            printf "OSCAR RPM Edge Proxy kept running uninterrupted for active CAS feeds (run 'sudo ./oscar.sh rpm-proxy upgrade' during a maintenance window to switch container image).\n"
        fi
        ;;
    status)
        rp_dir=$(resolve_rpm_proxy_dir)
        config_file="$rp_dir/config.json"
        if [[ ! -f $config_file ]]; then
            printf 'RPM Edge Proxy: disabled (not configured)\n'
            exit 0
        fi
        enabled=$(read_kv_file "$rp_dir/rpm-proxy.env" RPM_PROXY_ENABLED)
        mode=$(read_kv_file "$rp_dir/rpm-proxy.env" RPM_PROXY_MODE)
        printf 'RPM Edge Proxy: enabled=%s mode=%s config=%s\n' "${enabled:-false}" "${mode:-custom}" "$config_file"
        if command -v docker >/dev/null 2>&1; then
            run_proxy_compose ps || true
        fi
        read -r check_host status_port < <(parse_status_endpoint "$config_file")
        if command -v curl >/dev/null 2>&1; then
            if status_json=$(curl -fsS --max-time 2 "http://${check_host}:${status_port}/status" 2>/dev/null); then
                if command -v python3 >/dev/null 2>&1; then
                    python3 - "$status_json" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
print(
    f"Live Telemetry: status={data.get('status')} "
    f"connected_lanes={data.get('connected_lanes')}/{data.get('configured_lanes')} "
    f"uptime={data.get('uptime_seconds')}s"
)
for svc in data.get("services", []):
    print(
        f"  - {svc.get('name')}: state={svc.get('state')} upstream={svc.get('upstream')} "
        f"listener_open={svc.get('listener_open')} consumers={svc.get('active_clients')} "
        f"lines={svc.get('lines_from_upstream')} setup_cached={svc.get('cached_setup_keys')} "
        f"idle_timeouts={svc.get('idle_timeouts')}"
    )
PY
                else
                    printf '%s\n' "$status_json"
                fi
            fi
        fi
        ;;
    logs)
        tail_lines="200"
        follow_flag=()
        while (($# > 0)); do
            case "$1" in
                --tail) tail_lines=${2:?missing --tail count}; shift 2 ;;
                --follow|-f) follow_flag=(--follow); shift ;;
                *) fail "Unknown option for rpm-proxy logs: $1" ;;
            esac
        done
        run_proxy_compose logs --tail "$tail_lines" "${follow_flag[@]}"
        ;;
    support-snapshot)
        dest_dir=${1:?missing destination directory}
        rp_dir=$(resolve_rpm_proxy_dir)
        [[ -f $rp_dir/config.json ]] || exit 0
        install -d -m 0755 "$dest_dir"
        cp -f "$rp_dir/config.json" "$dest_dir/config.json" 2>/dev/null || true
        cp -f "$rp_dir/rpm-proxy.env" "$dest_dir/rpm-proxy.env" 2>/dev/null || true
        cp -f "$rp_dir/vips.txt" "$dest_dir/vips.txt" 2>/dev/null || true
        read -r check_host status_port < <(parse_status_endpoint "$rp_dir/config.json")
        if command -v curl >/dev/null 2>&1; then
            curl -fsS --max-time 2 "http://${check_host}:${status_port}/status" > "$dest_dir/status.json" 2>/dev/null || true
            curl -fsS --max-time 2 "http://${check_host}:${status_port}/metrics" > "$dest_dir/metrics.prom" 2>/dev/null || true
        fi
        run_proxy_compose logs --no-color --tail 500 > "$dest_dir/rpm-proxy.log" 2>&1 || true
        ;;
    disable)
        remove_vips=false
        while (($# > 0)); do
            case "$1" in
                --remove-vips) remove_vips=true; shift ;;
                *) fail "Unknown option for rpm-proxy disable: $1" ;;
            esac
        done
        rp_dir=$(resolve_rpm_proxy_dir)
        if [[ -f $rp_dir/config.json ]]; then
            run_proxy_compose down --remove-orphans || true
        fi
        if [[ -f $rp_dir/rpm-proxy.env ]]; then
            vip_nic=$(read_kv_file "$rp_dir/rpm-proxy.env" RPM_PROXY_VIP_INTERFACE)
            vip_prefix=$(read_kv_file "$rp_dir/rpm-proxy.env" RPM_PROXY_VIP_PREFIX)
            sed -i 's/^RPM_PROXY_ENABLED=.*/RPM_PROXY_ENABLED=false/' "$rp_dir/rpm-proxy.env"
            if $remove_vips && [[ -n $vip_nic ]]; then
                remove_linux_vips "$vip_nic" "${vip_prefix:-24}" "$rp_dir/vips.txt"
            fi
        fi
        printf 'OSCAR RPM Edge Proxy disabled.\n'
        ;;
    *)
        fail "Unknown rpm-proxy subcommand: $subcommand (run './oscar.sh rpm-proxy help' for usage)."
        ;;
esac
