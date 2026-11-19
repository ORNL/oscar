#!/usr/bin/env bash
# OSCAR Ubuntu 24.04 LTS Host Readiness, Hotel-to-Site Network Staging & Device Discovery
# Supports:
#   host-check          Audit Ubuntu 24.04 power, LVM, Docker, sysctl, time, and NIC readiness
#   prepare-host        Converge Ubuntu 24.04 host settings (online APT or offline bundled .debs)
#   identify-nics       List physical NICs, blink RJ45 LEDs, or watch live cable plug/unplug events
#   stage-site-network  Pre-stage on-site static IP Netplan YAML (interactive or file) without dropping hotel DHCP/Wi-Fi
#   apply-site-network  Back up current Netplan, activate staged static site IPs, and refresh OSCAR TLS SANs
#   rollback-network    Restore the previous Netplan configuration backup and re-apply
#   discover-devices    Scan an attached or factory-default sensor subnet for RPMs and RTSP cameras

set -Eeuo pipefail

script_path=${BASH_SOURCE[0]}
case $script_path in */*) script_parent=${script_path%/*} ;; *) script_parent=. ;; esac
script_dir=$(CDPATH= cd -- "$script_parent" && pwd -P)

# Test-isolation override so automated tests never touch the host's /etc.
host_root=${OSCAR_UBUNTU_HOST_TEST_ROOT:-}
etc_dir="${host_root}/etc"
oscar_etc_dir="${etc_dir}/oscar"
staged_netplan_dir="${oscar_etc_dir}/staged-netplan"
staged_netplan_file="${staged_netplan_dir}/90-oscar-site.yaml"
staged_summary_file="${staged_netplan_dir}/site-summary.env"
netplan_backup_root="${oscar_etc_dir}/netplan-backups"
live_netplan_dir="${etc_dir}/netplan"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

info() {
    printf '==> %s\n' "$*"
}

require_root() {
    [[ -n $host_root || ${EUID:-$(id -u)} -eq 0 ]] || fail "Run this command with sudo: sudo bash oscar.sh ${subcommand:-prepare-host}"
}

require_linux() {
    [[ -n $host_root || $(uname -s) == Linux ]] || fail "Ubuntu host tools are only supported on Linux (detected: $(uname -s))."
}

json_escape() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

is_ipv4() {
    local ip=$1 octet
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -r -a octets <<<"$ip"
    for octet in "${octets[@]}"; do
        ((10#$octet >= 0 && 10#$octet <= 255)) || return 1
    done
    return 0
}

netmask_to_prefix() {
    local mask=$1 octet bits=0 seen_zero=false
    is_ipv4 "$mask" || return 1
    IFS=. read -r -a octets <<<"$mask"
    for octet in "${octets[@]}"; do
        case $((10#$octet)) in
            255) $seen_zero && return 1; ((bits += 8)) ;;
            254) $seen_zero && return 1; ((bits += 7)); seen_zero=true ;;
            252) $seen_zero && return 1; ((bits += 6)); seen_zero=true ;;
            248) $seen_zero && return 1; ((bits += 5)); seen_zero=true ;;
            240) $seen_zero && return 1; ((bits += 4)); seen_zero=true ;;
            224) $seen_zero && return 1; ((bits += 3)); seen_zero=true ;;
            192) $seen_zero && return 1; ((bits += 2)); seen_zero=true ;;
            128) $seen_zero && return 1; ((bits += 1)); seen_zero=true ;;
            0)   seen_zero=true ;;
            *)   return 1 ;;
        esac
    done
    ((bits >= 8 && bits <= 32)) || return 1
    printf '%s' "$bits"
}

normalize_ipv4_cidr() {
    local raw=${1//[[:space:]]/} ip mask prefix
    if [[ $raw == */* ]]; then
        ip=${raw%%/*}
        mask=${raw#*/}
        is_ipv4 "$ip" || return 1
        if [[ $mask =~ ^[0-9]{1,2}$ ]]; then
            ((10#$mask >= 8 && 10#$mask <= 32)) || return 1
            prefix=$((10#$mask))
        else
            prefix=$(netmask_to_prefix "$mask") || return 1
        fi
        printf '%s/%s' "$ip" "$prefix"
        return 0
    fi
    return 1
}

valid_iface_name() {
    [[ $1 =~ ^[A-Za-z0-9._-]{1,15}$ ]] && [[ $1 != lo ]]
}

list_physical_nics() {
    local sys_net="/sys/class/net" dev name
    [[ -d $sys_net ]] || return 0
    for dev in "$sys_net"/*; do
        [[ -e $dev ]] || continue
        name=${dev##*/}
        case "$name" in
            lo|docker*|br-*|veth*|vnet*|virbr*|cni*|flannel*|cali*|tun*|tap*|wg*|tailscale*|octelium*|sit*|ip6tnl*|gre*|erspan*|bond_masters)
                continue
                ;;
        esac
        printf '%s\n' "$name"
    done | LC_ALL=C sort
}

nic_type() {
    local name=$1
    if [[ -d "/sys/class/net/$name/wireless" || -d "/sys/class/net/$name/phy80211" ]]; then
        printf 'wifi'
    else
        printf 'ethernet'
    fi
}

nic_carrier_label() {
    local name=$1 carrier operstate
    carrier=$(cat "/sys/class/net/$name/carrier" 2>/dev/null || echo 0)
    operstate=$(cat "/sys/class/net/$name/operstate" 2>/dev/null || echo unknown)
    if [[ $carrier == 1 || $operstate == up ]]; then
        printf 'PLUGGED_IN'
    else
        printf 'unplugged'
    fi
}

nic_speed_label() {
    local name=$1 speed
    speed=$(cat "/sys/class/net/$name/speed" 2>/dev/null || true)
    if [[ -n $speed && $speed =~ ^[0-9]+$ && $speed -gt 0 ]]; then
        printf '%sMb/s' "$speed"
    else
        printf '-'
    fi
}

nic_mac() {
    cat "/sys/class/net/$1/address" 2>/dev/null || printf '-'
}

nic_ipv4_summary() {
    local name=$1 addrs
    addrs=$(ip -4 -o addr show dev "$name" 2>/dev/null | awk '{print $4}' | paste -sd ',' - || true)
    printf '%s' "${addrs:--}"
}

nic_ipv4_origin() {
    local name=$1 line
    line=$(ip -4 -o addr show dev "$name" 2>/dev/null | head -n1 || true)
    if [[ -z $line ]]; then
        printf 'none'
    elif [[ $line == *' dynamic '* ]]; then
        printf 'dhcp'
    else
        printf 'static'
    fi
}

nic_hw_desc() {
    local name=$1 dev_path pci_slot desc=''
    if [[ -L "/sys/class/net/$name/device" ]]; then
        dev_path=$(readlink -f "/sys/class/net/$name/device" 2>/dev/null || true)
        pci_slot=${dev_path##*/}
        if command -v lspci >/dev/null 2>&1 && [[ $pci_slot =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9]$ ]]; then
            desc=$(lspci -s "${pci_slot#0000:}" 2>/dev/null | sed -E 's/^[^:]+: [^:]+: //' | head -c 44 || true)
        fi
        [[ -n $desc ]] || desc=$pci_slot
    fi
    printf '%s' "${desc:-virtual/onboard}"
}

detect_netplan_renderer() {
    if [[ -n ${OSCAR_NETPLAN_RENDERER:-} ]]; then
        printf '%s' "$OSCAR_NETPLAN_RENDERER"
        return
    fi
    if [[ -d $live_netplan_dir ]] && grep -Rqs 'renderer:[[:space:]]*NetworkManager' "$live_netplan_dir" 2>/dev/null; then
        printf 'NetworkManager'
        return
    fi
    if [[ -z $host_root ]] && command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet NetworkManager 2>/dev/null && ! systemctl is-active --quiet systemd-networkd 2>/dev/null; then
        printf 'NetworkManager'
        return
    fi
    printf 'networkd'
}

extract_staged_ips() {
    local file=${1:-$staged_netplan_file}
    [[ -f $file ]] || return 0
    sed -nE 's/^[[:space:]]*-[[:space:]]*([0-9]{1,3}(\.[0-9]{1,3}){3})\/[0-9]{1,2}[[:space:]]*$/\1/p' "$file" | awk '!seen[$0]++'
}

# ---------------------------------------------------------------------------
# 1. HOST-CHECK
# ---------------------------------------------------------------------------
check_ids=()
check_statuses=()
check_details=()

record_check() {
    check_ids+=("$1")
    check_statuses+=("$2")
    check_details+=("$3")
}

detect_lvm_unallocated_gib() {
    [[ -z $host_root ]] || { printf '0'; return; }
    command -v vgs >/dev/null 2>&1 || { printf '0'; return; }
    local root_src vg_name free_bytes
    root_src=$(findmnt -n -o SOURCE / 2>/dev/null || true)
    [[ $root_src == /dev/mapper/* || $root_src == /dev/*/* ]] || { printf '0'; return; }
    if command -v lvs >/dev/null 2>&1; then
        vg_name=$(lvs --noheadings -o vg_name "$root_src" 2>/dev/null | tr -d '[:space:]' || true)
        if [[ -n $vg_name ]]; then
            free_bytes=$(vgs --noheadings --nosuffix --units b -o vg_free "$vg_name" 2>/dev/null | tr -d '[:space:]' || echo 0)
            if [[ $free_bytes =~ ^[0-9]+$ ]]; then
                printf '%s' $((free_bytes / 1073741824))
                return
            fi
        fi
    fi
    printf '0'
}

run_host_check() {
    local strict=false json_out=false allow_dhcp=false
    while (($# > 0)); do
        case "$1" in
            --strict) strict=true; shift ;;
            --json) json_out=true; shift ;;
            --allow-dhcp) allow_dhcp=true; shift ;;
            -h|--help)
                cat <<'EOF'
Usage: sudo bash oscar.sh host-check [--strict] [--json] [--allow-dhcp]

Audits Ubuntu 24.04 LTS readiness for 24/7 OSCAR operation, hotel-room staging,
and air-gapped field cutover.
EOF
                return 0
                ;;
            *) fail "Unknown host-check option: $1" ;;
        esac
    done

    check_ids=()
    check_statuses=()
    check_details=()

    # 1. OS Version
    local os_id='' os_ver='' os_arch
    if [[ -f "${etc_dir}/os-release" ]]; then
        # shellcheck disable=SC1090
        source "${etc_dir}/os-release"
        os_id=${ID:-}
        os_ver=${VERSION_ID:-}
    fi
    os_arch=$(uname -m)
    if [[ $os_id == ubuntu && $os_ver == 24.04 && $os_arch == x86_64 ]]; then
        record_check "os-version" "PASS" "Ubuntu 24.04 LTS x86_64 detected."
    elif [[ $os_id == ubuntu && $os_arch == x86_64 ]]; then
        record_check "os-version" "WARN" "Ubuntu ${os_ver:-unknown} x86_64 detected (Ubuntu 24.04 LTS is the certified release target)."
    else
        record_check "os-version" "WARN" "Detected ${os_id:-unknown} ${os_ver:-unknown} (${os_arch}); Ubuntu 24.04 LTS x86_64 is recommended."
    fi

    # 2. Snap Docker absence
    if [[ -z $host_root ]] && command -v snap >/dev/null 2>&1 && snap list docker >/dev/null 2>&1; then
        record_check "snap-docker" "FAIL" "Snap-confined Docker is installed ('snap list docker'). Snap Docker breaks bind-mount paths and triggers background container restarts. Run 'sudo bash oscar.sh prepare-host' to replace with APT docker-ce."
    else
        record_check "snap-docker" "PASS" "Snap Docker is not installed."
    fi

    # 3. Official Docker Engine + Compose v2
    if [[ -z $host_root ]] && command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        local dver
        dver=$(docker --version 2>/dev/null | head -n1)
        if command -v systemctl >/dev/null 2>&1 && ! systemctl is-enabled --quiet docker 2>/dev/null; then
            record_check "docker-engine" "WARN" "${dver} is running, but docker.service is not enabled at boot."
        else
            record_check "docker-engine" "PASS" "${dver} + Compose plugin ready and enabled at boot."
        fi
    elif [[ -n $host_root ]]; then
        record_check "docker-engine" "PASS" "Test-root mode: skipped live Docker daemon check."
    else
        record_check "docker-engine" "FAIL" "Docker Engine / Compose plugin is missing or not running. Run 'sudo bash oscar.sh prepare-host' (add '--offline' if using the Ubuntu offline bundle)."
    fi

    # 4. Docker JSON log rotation
    local daemon_json="${etc_dir}/docker/daemon.json"
    if [[ -f $daemon_json ]] && grep -Fq '"max-size"' "$daemon_json" && grep -Fq '"max-file"' "$daemon_json"; then
        record_check "docker-log-rotation" "PASS" "Bounded container log rotation is configured in /etc/docker/daemon.json."
    else
        record_check "docker-log-rotation" "WARN" "/etc/docker/daemon.json lacks bounded max-size/max-file log rotation; run 'sudo bash oscar.sh prepare-host'."
    fi

    # 5. Ubuntu 100 GiB LVM unallocated space trap + free disk space
    local unalloc_gib avail_gib
    unalloc_gib=$(detect_lvm_unallocated_gib)
    avail_gib=$(df -BG "${script_dir}" 2>/dev/null | awk 'NR==2 {gsub(/G/,"",$4); print $4}' || echo 0)
    if ((unalloc_gib >= 10)); then
        record_check "lvm-root-capacity" "WARN" "Ubuntu LVM volume group has ${unalloc_gib} GiB of UNALLOCATED disk space (the classic 100 GiB installer cap). Run 'sudo bash oscar.sh prepare-host --expand-lvm' to claim 100% of the NVMe."
    elif [[ $avail_gib =~ ^[0-9]+$ ]] && ((avail_gib < 40)); then
        record_check "lvm-root-capacity" "WARN" "Only ${avail_gib} GiB free on the filesystem hosting ${script_dir} (50+ GiB recommended)."
    else
        record_check "lvm-root-capacity" "PASS" "Storage capacity healthy (${avail_gib} GiB free; 0 GiB trapped in unallocated LVM extents)."
    fi

    # 6. Sleep / Suspend / Lid-close masking
    local logind_dropin="${etc_dir}/systemd/logind.conf.d/oscar-nosleep.conf"
    local sleep_masked=true
    if [[ -z $host_root ]] && command -v systemctl >/dev/null 2>&1; then
        local st
        st=$(systemctl is-enabled sleep.target suspend.target 2>/dev/null | paste -sd ',' - || true)
        [[ $st == *masked* ]] || sleep_masked=false
    fi
    if [[ -f $logind_dropin ]] && $sleep_masked; then
        record_check "sleep-suspend-masked" "PASS" "System sleep/suspend targets are masked and lid-close suspend is disabled."
    else
        record_check "sleep-suspend-masked" "WARN" "Sleep/suspend targets or lid-close ignore drop-in not yet applied; run 'sudo bash oscar.sh prepare-host'."
    fi

    # 7. Unattended-Upgrades Auto-Reboot Guard
    local uu_dropin="${etc_dir}/apt/apt.conf.d/52oscar-unattended-upgrades"
    if [[ -f $uu_dropin ]] && grep -Eq 'Automatic-Reboot[[:space:]]+"false"' "$uu_dropin"; then
        record_check "unattended-reboot-guard" "PASS" "Unattended-upgrades automatic reboots are disabled (52oscar-unattended-upgrades)."
    else
        record_check "unattended-reboot-guard" "WARN" "Unattended-upgrades auto-reboot guard not present; run 'sudo bash oscar.sh prepare-host'."
    fi

    # 8. Kernel network & inotify sysctl tuning
    local sysctl_dropin="${etc_dir}/sysctl.d/90-oscar.conf"
    if [[ -f $sysctl_dropin ]]; then
        record_check "kernel-sysctl" "PASS" "RTSP/PostgreSQL socket buffer and inotify tuning present (/etc/sysctl.d/90-oscar.conf)."
    else
        record_check "kernel-sysctl" "WARN" "/etc/sysctl.d/90-oscar.conf not yet installed; run 'sudo bash oscar.sh prepare-host'."
    fi

    # 9. Offline boot wait-online timeout protection
    local wait_dropin="${etc_dir}/systemd/system/systemd-networkd-wait-online.service.d/oscar-timeout.conf"
    if [[ -f $wait_dropin ]]; then
        record_check "offline-boot-wait-guard" "PASS" "Boot network-wait timeout bounded (prevents 2-minute boot hangs on air-gapped/no-DHCP sites)."
    else
        record_check "offline-boot-wait-guard" "WARN" "systemd-networkd-wait-online timeout guard missing; air-gapped multi-NIC boots may pause 120s without 'prepare-host'."
    fi

    # 10. Time synchronization & air-gapped orphan stratum
    local chrony_airgap="${etc_dir}/chrony/conf.d/90-oscar-airgap.conf"
    if [[ -n $host_root ]]; then
        [[ -f $chrony_airgap ]] && record_check "time-sync" "PASS" "Air-gapped chrony local-stratum fallback configured." \
            || record_check "time-sync" "WARN" "Air-gapped chrony config not yet written."
    elif command -v systemctl >/dev/null 2>&1 && (systemctl is-active --quiet chrony 2>/dev/null || systemctl is-active --quiet chronyd 2>/dev/null || systemctl is-active --quiet systemd-timesyncd 2>/dev/null); then
        record_check "time-sync" "PASS" "System time synchronization service is active."
    else
        record_check "time-sync" "WARN" "Neither chrony nor systemd-timesyncd is active; run 'sudo bash oscar.sh prepare-host'."
    fi

    # 11. Network static IP vs DHCP + Staged site plan awareness
    local dhcp_nics=() static_nics=() nic origin
    while IFS= read -r nic; do
        [[ -n $nic ]] || continue
        origin=$(nic_ipv4_origin "$nic")
        case "$origin" in
            dhcp) dhcp_nics+=("$nic") ;;
            static) static_nics+=("$nic") ;;
        esac
    done < <(list_physical_nics)

    if ((${#dhcp_nics[@]} == 0)) && ((${#static_nics[@]} > 0)); then
        record_check "network-address-stability" "PASS" "Static IPv4 active on: ${static_nics[*]}."
    elif [[ -f $staged_netplan_file ]]; then
        local staged_ips
        staged_ips=$(extract_staged_ips "$staged_netplan_file" | paste -sd ',' - || true)
        record_check "network-address-stability" "PASS" "Currently on DHCP (${dhcp_nics[*]:-none}) for off-site/hotel staging; static site Netplan is staged (${staged_ips:-ready}) for 'apply-site-network' on arrival."
    elif $allow_dhcp; then
        record_check "network-address-stability" "PASS" "DHCP acknowledged via --allow-dhcp (${dhcp_nics[*]:-none})."
    else
        record_check "network-address-stability" "WARN" "Active NICs use dynamic DHCP (${dhcp_nics[*]:-none}) and no site static IP plan is staged yet. Run 'sudo bash oscar.sh stage-site-network' (hotel staging) or pass '--allow-dhcp' if using router DHCP reservations."
    fi

    # 12. Field network tools
    local missing_tools=() tool
    for tool in ip ethtool nmap; do
        command -v "$tool" >/dev/null 2>&1 || missing_tools+=("$tool")
    done
    if ((${#missing_tools[@]} == 0)); then
        record_check "field-tools" "PASS" "Field NIC & sensor discovery tools installed (ip, ethtool, nmap)."
    else
        record_check "field-tools" "WARN" "Optional field diagnostic tools missing (${missing_tools[*]}); run 'sudo bash oscar.sh prepare-host'."
    fi

    local pass_count=0 warn_count=0 fail_count=0 i
    for i in "${!check_ids[@]}"; do
        case "${check_statuses[$i]}" in
            PASS) ((pass_count += 1)) ;;
            WARN) ((warn_count += 1)) ;;
            FAIL) ((fail_count += 1)) ;;
        esac
    done

    if $json_out; then
        printf '{\n  "platform": "ubuntu-x86_64",\n  "pass": %d,\n  "warn": %d,\n  "fail": %d,\n  "stagedSiteNetplan": %s,\n  "checks": [\n' \
            "$pass_count" "$warn_count" "$fail_count" "$([[ -f $staged_netplan_file ]] && echo true || echo false)"
        for i in "${!check_ids[@]}"; do
            local comma=','
            ((i + 1 == ${#check_ids[@]})) && comma=''
            printf '    {"id": "%s", "status": "%s", "detail": "%s"}%s\n' \
                "$(json_escape "${check_ids[$i]}")" \
                "$(json_escape "${check_statuses[$i]}")" \
                "$(json_escape "${check_details[$i]}")" \
                "$comma"
        done
        printf '  ]\n}\n'
    else
        printf 'OSCAR Ubuntu Host Readiness Audit\n'
        printf '=================================\n'
        for i in "${!check_ids[@]}"; do
            printf '[ %-4s ] %-27s %s\n' "${check_statuses[$i]}" "${check_ids[$i]}" "${check_details[$i]}"
        done
        printf '\nSummary: %d PASS, %d WARN, %d FAIL\n' "$pass_count" "$warn_count" "$fail_count"
    fi

    if ((fail_count > 0)); then
        return 1
    fi
    if $strict && ((warn_count > 0)); then
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# 2. PREPARE-HOST
# ---------------------------------------------------------------------------
install_packages_offline_dir() {
    local dir=$1
    [[ -d $dir ]] || return 1
    local debs=() deb pkg_name installed_state
    while IFS= read -r -d '' deb; do
        pkg_name=$(dpkg-deb -f "$deb" Package 2>/dev/null || true)
        if [[ -n $pkg_name ]]; then
            installed_state=$(dpkg-query -W -f='${Status}' "$pkg_name" 2>/dev/null || true)
            if [[ $installed_state == "install ok installed" ]]; then
                continue
            fi
        fi
        debs+=("$deb")
    done < <(find "$dir" -maxdepth 1 -type f -name '*.deb' -print0 | sort -z)

    if ((${#debs[@]} > 0)); then
        info "Installing ${#debs[@]} bundled offline .deb package(s) from ${dir}..."
        DEBIAN_FRONTEND=noninteractive dpkg -i --skip-same-version --refuse-downgrade "${debs[@]}" || \
            DEBIAN_FRONTEND=noninteractive dpkg --configure -a
    fi
    return 0
}

run_prepare_host() {
    local offline_mode=auto expand_lvm=false configure_ufw=false hold_docker=false
    while (($# > 0)); do
        case "$1" in
            --offline) offline_mode=true; shift ;;
            --online) offline_mode=false; shift ;;
            --expand-lvm) expand_lvm=true; shift ;;
            --configure-ufw) configure_ufw=true; shift ;;
            --hold-docker) hold_docker=true; shift ;;
            -h|--help)
                cat <<'EOF'
Usage: sudo bash oscar.sh prepare-host [options]

Options:
  --expand-lvm     Expand Ubuntu's default 100 GiB root LVM logical volume to 100% of free NVMe space
  --configure-ufw  Allow OpenSSH (22/tcp), HTTP (80/tcp), and HTTPS (443/tcp) in UFW and enable UFW
  --offline        Install Docker & field utilities strictly from bundled installers/ubuntu-24.04-x86_64/*.deb
  --hold-docker    Pin docker-ce & containerd.io via apt-mark hold so background APT runs never restart containers
EOF
                return 0
                ;;
            *) fail "Unknown prepare-host option: $1" ;;
        esac
    done

    require_linux
    require_root

    local docker_deb_dir="$script_dir/installers/ubuntu-24.04-x86_64"
    local tools_deb_dir="$script_dir/installers/ubuntu-24.04-x86_64/host-tools"
    if [[ $offline_mode == auto ]]; then
        if [[ -d $docker_deb_dir ]] && compgen -G "${docker_deb_dir}/*.deb" >/dev/null; then
            offline_mode=true
        else
            offline_mode=false
        fi
    fi

    # 1. Remove Snap Docker if installed and idle
    if [[ -z $host_root ]] && command -v snap >/dev/null 2>&1 && snap list docker >/dev/null 2>&1; then
        info "Removing Snap-confined Docker so official APT Docker Engine can manage volumes cleanly..."
        snap remove --purge docker
    fi

    # 2. Install Docker Engine + Compose v2 + field utilities (online APT or offline bundled .debs)
    if [[ -z $host_root ]]; then
        if [[ $offline_mode == true ]]; then
            info "Preparing packages from local offline bundle (zero internet required)..."
            if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
                [[ -d $docker_deb_dir ]] || fail "Offline mode requested, but ${docker_deb_dir} was not found. Use oscar-3.11.0-ubuntu-x86_64-offline-full.zip."
                install_packages_offline_dir "$docker_deb_dir"
            fi
            [[ -d $tools_deb_dir ]] && install_packages_offline_dir "$tools_deb_dir" || true
        else
            info "Installing official APT Docker Engine, Compose v2, chrony, openssh-server, and field NIC tools..."
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y
            apt-get install -y ca-certificates curl gnupg openssh-server chrony ethtool nmap arp-scan jq ntfs-3g rsync ufw lsb-release
            if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
                install -m 0755 -d /etc/apt/keyrings
                if [[ ! -s /etc/apt/keyrings/docker.asc ]]; then
                    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
                    chmod a+r /etc/apt/keyrings/docker.asc
                fi
                local codename arch
                codename=$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-noble}")
                arch=$(dpkg --print-architecture)
                cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable
EOF
                apt-get update -y
                apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            fi
        fi

        if $hold_docker; then
            apt-mark hold docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
        fi
    fi

    # 3. Expand LVM root LV if requested
    if $expand_lvm && [[ -z $host_root ]]; then
        local unalloc_gib root_src fstype
        unalloc_gib=$(detect_lvm_unallocated_gib)
        if ((unalloc_gib >= 2)); then
            root_src=$(findmnt -n -o SOURCE /)
            fstype=$(findmnt -n -o FSTYPE /)
            info "Expanding ${root_src} (${fstype}) to reclaim ${unalloc_gib} GiB of unallocated LVM space..."
            lvextend -l +100%FREE "$root_src"
            case "$fstype" in
                ext4|ext3) resize2fs "$root_src" ;;
                xfs) xfs_growfs / ;;
                *) warn "Expanded LV ${root_src}; run your filesystem's online grow tool for ${fstype}." ;;
            esac
        else
            info "LVM check: no unallocated volume-group space detected (nothing to expand)."
        fi
    fi

    # 4. Bounded Docker JSON log rotation (/etc/docker/daemon.json)
    mkdir -p "${etc_dir}/docker"
    local daemon_json="${etc_dir}/docker/daemon.json" daemon_changed=false
    if [[ ! -f $daemon_json ]]; then
        cat > "$daemon_json" <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "5"
  }
}
EOF
        chmod 0644 "$daemon_json"
        daemon_changed=true
    elif ! grep -Fq '"max-size"' "$daemon_json" && command -v python3 >/dev/null 2>&1; then
        python3 - "$daemon_json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
data.setdefault("log-driver", "json-file")
opts = data.setdefault("log-opts", {})
opts.setdefault("max-size", "50m")
opts.setdefault("max-file", "5")
p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
        daemon_changed=true
    fi

    # 5. Mask sleep/suspend/hibernate + laptop/KVM lid-close ignore
    mkdir -p "${etc_dir}/systemd/logind.conf.d"
    cat > "${etc_dir}/systemd/logind.conf.d/oscar-nosleep.conf" <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
EOF
    chmod 0644 "${etc_dir}/systemd/logind.conf.d/oscar-nosleep.conf"

    # 6. Prevent unattended-upgrades from automatically rebooting a 24/7 portal
    mkdir -p "${etc_dir}/apt/apt.conf.d"
    cat > "${etc_dir}/apt/apt.conf.d/52oscar-unattended-upgrades" <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::SyslogEnable "true";
EOF
    chmod 0644 "${etc_dir}/apt/apt.conf.d/52oscar-unattended-upgrades"

    # 7. Kernel socket buffers (100 RTSP cameras + 50 RPMs), inotify, & swappiness
    mkdir -p "${etc_dir}/sysctl.d"
    cat > "${etc_dir}/sysctl.d/90-oscar.conf" <<'EOF'
# OSCAR 24/7 Portal Tuning (50 RPM lanes + 100 H.264 RTSP cameras + PostgreSQL/DuckDB)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 16384
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
vm.swappiness = 10
EOF
    chmod 0644 "${etc_dir}/sysctl.d/90-oscar.conf"

    # 8. Bound systemd-networkd-wait-online so air-gapped / unplugged-NIC boots never stall 120s
    mkdir -p "${etc_dir}/systemd/system/systemd-networkd-wait-online.service.d"
    cat > "${etc_dir}/systemd/system/systemd-networkd-wait-online.service.d/oscar-timeout.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=/lib/systemd/systemd-networkd-wait-online --any --timeout=10
EOF
    chmod 0644 "${etc_dir}/systemd/system/systemd-networkd-wait-online.service.d/oscar-timeout.conf"

    # 9. Air-gapped chrony local orphan clock fallback (keeps time monotonic offline)
    mkdir -p "${etc_dir}/chrony/conf.d"
    cat > "${etc_dir}/chrony/conf.d/90-oscar-airgap.conf" <<'EOF'
# Allow chrony to maintain a stable local reference if deployed on an air-gapped site without NTP
local stratum 10
EOF
    chmod 0644 "${etc_dir}/chrony/conf.d/90-oscar-airgap.conf"

    if [[ -z $host_root ]]; then
        sysctl --system >/dev/null 2>&1 || true
        systemctl daemon-reload || true
        systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true
        systemctl enable --now docker >/dev/null 2>&1 || true
        if $daemon_changed && ! docker ps -q --filter label=com.docker.compose.project=oscar | grep -q .; then
            systemctl restart docker || true
        fi
        systemctl enable --now ssh >/dev/null 2>&1 || systemctl enable --now sshd >/dev/null 2>&1 || true
        systemctl enable --now fstrim.timer >/dev/null 2>&1 || true
        if systemctl list-unit-files chrony.service >/dev/null 2>&1; then
            systemctl enable --now chrony >/dev/null 2>&1 || true
            systemctl restart chrony >/dev/null 2>&1 || true
        fi
        if $configure_ufw && command -v ufw >/dev/null 2>&1; then
            info "Configuring UFW host firewall (allowing 22/tcp SSH, 80/tcp HTTP redirect, 443/tcp HTTPS)..."
            ufw allow 22/tcp >/dev/null
            ufw allow 80/tcp >/dev/null
            ufw allow 443/tcp >/dev/null
            ufw --force enable >/dev/null
        fi
    fi

    info "Ubuntu 24.04 host preparation complete."
    run_host_check --allow-dhcp || true
}

# ---------------------------------------------------------------------------
# 3. IDENTIFY-NICS (Physical Port Mapping & Live Cable Plug/Unplug Detector)
# ---------------------------------------------------------------------------
print_nic_table() {
    printf '%-12s %-9s %-12s %-10s %-19s %-22s %s\n' \
        "INTERFACE" "TYPE" "CABLE" "SPEED" "MAC ADDRESS" "CURRENT IPv4 (MODE)" "HARDWARE"
    printf '%-12s %-9s %-12s %-10s %-19s %-22s %s\n' \
        "------------" "---------" "------------" "----------" "-------------------" "----------------------" "------------------------"
    local nic ip_str origin
    while IFS= read -r nic; do
        [[ -n $nic ]] || continue
        ip_str=$(nic_ipv4_summary "$nic")
        origin=$(nic_ipv4_origin "$nic")
        [[ $ip_str == '-' ]] || ip_str="${ip_str} (${origin})"
        printf '%-12s %-9s %-12s %-10s %-19s %-22s %s\n' \
            "$nic" \
            "$(nic_type "$nic")" \
            "$(nic_carrier_label "$nic")" \
            "$(nic_speed_label "$nic")" \
            "$(nic_mac "$nic")" \
            "$ip_str" \
            "$(nic_hw_desc "$nic")"
    done < <(list_physical_nics)
}

run_identify_nics() {
    local watch_secs=0 blink_nic=''
    while (($# > 0)); do
        case "$1" in
            --watch)
                if [[ ${2:-} =~ ^[0-9]+$ ]]; then watch_secs=$2; shift 2; else watch_secs=60; shift; fi
                ;;
            --blink)
                blink_nic=${2:?missing interface name for --blink}; shift 2
                ;;
            -h|--help)
                cat <<'EOF'
Usage:
  sudo bash oscar.sh identify-nics                Show all physical Ethernet/Wi-Fi ports, MACs, and cable state
  sudo bash oscar.sh identify-nics --watch [SEC]  Watch live cable plug/unplug events (label physical RJ45 ports!)
  sudo bash oscar.sh identify-nics --blink <NIC>  Blink the RJ45 port LED for 15 seconds (when NIC driver supports it)
EOF
                return 0
                ;;
            *) fail "Unknown identify-nics option: $1" ;;
        esac
    done

    require_linux
    print_nic_table

    if [[ -n $blink_nic ]]; then
        require_root
        valid_iface_name "$blink_nic" || fail "Invalid interface name: $blink_nic"
        command -v ethtool >/dev/null 2>&1 || fail "ethtool is not installed. Run 'sudo bash oscar.sh prepare-host' first."
        info "Blinking physical RJ45 LED on ${blink_nic} for 15 seconds..."
        ethtool --identify "$blink_nic" 15 || warn "Driver for ${blink_nic} does not support LED blink; use '--watch' and plug/unplug a cable instead."
        return 0
    fi

    if ((watch_secs > 0)); then
        printf '\nWatching physical cable state for %d seconds (Ctrl+C to stop early)...\n' "$watch_secs"
        printf 'Tip: Plug or unplug ONE Ethernet cable at a time and label the physical port with tape.\n\n'
        declare -A prev_state=()
        local nic cur elapsed=0
        while IFS= read -r nic; do
            [[ -n $nic ]] || continue
            prev_state["$nic"]=$(nic_carrier_label "$nic")
        done < <(list_physical_nics)

        while ((elapsed < watch_secs)); do
            sleep 1
            ((elapsed += 1))
            while IFS= read -r nic; do
                [[ -n $nic ]] || continue
                cur=$(nic_carrier_label "$nic")
                if [[ ${prev_state["$nic"]:-unknown} != "$cur" ]]; then
                    printf '[%s] >>> %s changed to %-10s (MAC %s, speed %s) <<<\n' \
                        "$(date +%H:%M:%S)" "$nic" "$cur" "$(nic_mac "$nic")" "$(nic_speed_label "$nic")"
                    prev_state["$nic"]=$cur
                fi
            done < <(list_physical_nics)
        done
    fi
}

# ---------------------------------------------------------------------------
# 4. STAGE-SITE-NETWORK & APPLY-SITE-NETWORK & ROLLBACK-NETWORK
# ---------------------------------------------------------------------------
prompt_default() {
    local prompt=$1 default_val=${2:-} reply=''
    if [[ -n $default_val ]]; then
        printf '%s [%s]: ' "$prompt" "$default_val" >&2
    else
        printf '%s: ' "$prompt" >&2
    fi
    IFS= read -r reply || true
    reply=${reply%$'\r'}
    printf '%s' "${reply:-$default_val}"
}

validate_netplan_yaml_file() {
    local yaml_file=$1
    if command -v python3 >/dev/null 2>&1 && python3 -c 'import netplan' >/dev/null 2>&1; then
        python3 - "$yaml_file" <<'PY' >/dev/null 2>&1
import netplan, sys
parser = netplan.Parser()
parser.load_yaml(sys.argv[1])
state = netplan.State()
state.import_parser_results(parser)
PY
        return $?
    fi
    grep -Eq '^network:[[:space:]]*$' "$yaml_file" && grep -Eq '^[[:space:]]+version:[[:space:]]*2[[:space:]]*$' "$yaml_file"
}

write_staged_netplan() {
    local renderer=$1 primary_nic=$2 primary_cidr=$3 primary_gw=$4 primary_dns=$5 sensor_nic=$6 sensor_cidr=$7 site_hostname=$8
    mkdir -p "$staged_netplan_dir"
    chmod 0700 "$staged_netplan_dir"

    local tmp_yaml="${staged_netplan_file}.tmp.$$"
    {
        printf '# Generated by OSCAR stage-site-network (%s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '# Staged off-site (e.g., hotel room) without disrupting current DHCP/Wi-Fi.\n'
        printf '# Activate on arrival at the site with: sudo bash oscar.sh apply-site-network\n'
        printf 'network:\n'
        printf '  version: 2\n'
        printf '  renderer: %s\n' "$renderer"
        printf '  ethernets:\n'
        printf '    %s:\n' "$primary_nic"
        printf '      dhcp4: false\n'
        printf '      dhcp6: false\n'
        printf '      optional: true\n'
        printf '      addresses:\n'
        printf '        - %s\n' "$primary_cidr"
        if [[ -n $primary_gw ]]; then
            printf '      routes:\n'
            printf '        - to: default\n'
            printf '          via: %s\n' "$primary_gw"
        fi
        if [[ -n $primary_dns ]]; then
            printf '      nameservers:\n'
            printf '        addresses:\n'
            local dns_entry
            IFS=', ' read -r -a dns_list <<<"$primary_dns"
            for dns_entry in "${dns_list[@]}"; do
                [[ -n $dns_entry ]] || continue
                printf '          - %s\n' "$dns_entry"
            done
        fi
        if [[ -n $sensor_nic && -n $sensor_cidr ]]; then
            printf '    %s:\n' "$sensor_nic"
            printf '      dhcp4: false\n'
            printf '      dhcp6: false\n'
            printf '      # Isolated RPM & camera sensor network: intentionally NO default gateway\n'
            printf '      # and optional: true so boot never hangs when switches power up after server.\n'
            printf '      optional: true\n'
            printf '      addresses:\n'
            printf '        - %s\n' "$sensor_cidr"
        fi
    } > "$tmp_yaml"
    chmod 0600 "$tmp_yaml"

    if ! validate_netplan_yaml_file "$tmp_yaml"; then
        rm -f -- "$tmp_yaml"
        fail "Generated Netplan YAML failed Netplan schema validation. Check NIC names and IP addresses."
    fi

    mv -f "$tmp_yaml" "$staged_netplan_file"
    {
        printf 'PRIMARY_NIC=%s\n' "$primary_nic"
        printf 'PRIMARY_IP_CIDR=%s\n' "$primary_cidr"
        printf 'PRIMARY_GATEWAY=%s\n' "$primary_gw"
        printf 'PRIMARY_DNS=%s\n' "$primary_dns"
        printf 'SENSOR_NIC=%s\n' "$sensor_nic"
        printf 'SENSOR_IP_CIDR=%s\n' "$sensor_cidr"
        printf 'OSCAR_SITE_HOSTNAME=%s\n' "$site_hostname"
    } > "$staged_summary_file"
    chmod 0600 "$staged_summary_file"
}

run_stage_site_network() {
    local config_file='' from_netplan=''
    local primary_nic='' primary_cidr='' primary_gw='' primary_dns='' sensor_nic='' sensor_cidr='' site_hostname=''
    while (($# > 0)); do
        case "$1" in
            --config) config_file=${2:?missing file path for --config}; shift 2 ;;
            --from-netplan) from_netplan=${2:?missing YAML path for --from-netplan}; shift 2 ;;
            --primary-nic) primary_nic=${2:?}; shift 2 ;;
            --primary-ip) primary_cidr=${2:?}; shift 2 ;;
            --primary-gateway) primary_gw=${2:-}; shift 2 ;;
            --primary-dns) primary_dns=${2:-}; shift 2 ;;
            --sensor-nic) sensor_nic=${2:-}; shift 2 ;;
            --sensor-ip) sensor_cidr=${2:-}; shift 2 ;;
            --hostname) site_hostname=${2:-}; shift 2 ;;
            -h|--help)
                cat <<'EOF'
Usage:
  sudo bash oscar.sh stage-site-network
      Interactive step-by-step wizard (safe to run in a hotel room — keeps current Wi-Fi/DHCP active!)

  sudo bash oscar.sh stage-site-network --config ubuntu/site-network.env
      Stage from a simple KEY=VALUE worksheet file

  sudo bash oscar.sh stage-site-network --from-netplan my-site.yaml
      Stage an existing Netplan v2 YAML file after validating syntax
EOF
                return 0
                ;;
            *) fail "Unknown stage-site-network option: $1" ;;
        esac
    done

    require_linux
    require_root

    if [[ -n $from_netplan ]]; then
        [[ -f $from_netplan ]] || fail "Netplan file not found: $from_netplan"
        mkdir -p "$staged_netplan_dir"
        chmod 0700 "$staged_netplan_dir"
        if ! validate_netplan_yaml_file "$from_netplan"; then
            fail "Provided YAML failed Netplan schema validation: $from_netplan"
        fi
        cp "$from_netplan" "$staged_netplan_file"
        chmod 0600 "$staged_netplan_file"
        info "Staged custom Netplan file to ${staged_netplan_file} (current network NOT changed yet)."
    else
        if [[ -n $config_file ]]; then
            [[ -f $config_file ]] || fail "Config file not found: $config_file"
            while IFS='=' read -r k v || [[ -n ${k:-} ]]; do
                k=${k//[[:space:]]/}
                [[ -z $k || $k == \#* ]] && continue
                v=${v%$'\r'}
                v=${v#\"}
                v=${v%\"}
                v=${v#\'}
                v=${v%\'}
                case "$k" in
                    PRIMARY_NIC) primary_nic=$v ;;
                    PRIMARY_IP_CIDR) primary_cidr=$v ;;
                    PRIMARY_GATEWAY) primary_gw=$v ;;
                    PRIMARY_DNS) primary_dns=$v ;;
                    SENSOR_NIC) sensor_nic=$v ;;
                    SENSOR_IP_CIDR) sensor_cidr=$v ;;
                    OSCAR_SITE_HOSTNAME) site_hostname=$v ;;
                esac
            done < "$config_file"
        elif [[ -z $primary_nic && -t 0 ]]; then
            printf '\nOSCAR Off-Site / Hotel-Room Site Network Staging Wizard\n'
            printf '=======================================================\n'
            printf 'Current network adapters on this machine:\n\n'
            print_nic_table || true
            printf '\nNOTE: Saving this plan will NOT change your active hotel Wi-Fi/DHCP connection.\n'
            printf '      It prepares /etc/oscar/staged-netplan/90-oscar-site.yaml for one-command\n'
            printf '      activation once you arrive on-site.\n\n'

            local first_eth
            first_eth=$(list_physical_nics | while read -r n; do [[ $(nic_type "$n") == ethernet ]] && { echo "$n"; break; }; done || true)
            primary_nic=$(prompt_default "1) Primary / Operator LAN Ethernet interface name" "${first_eth:-enp1s0}")
            local raw_ip raw_mask
            raw_ip=$(prompt_default "2) On-site Primary Static IPv4 (e.g. 10.20.30.10/24 or 10.20.30.10)" "")
            if [[ $raw_ip != */* ]]; then
                raw_mask=$(prompt_default "   Subnet mask or prefix (e.g. 255.255.255.0 or 24)" "24")
                primary_cidr="${raw_ip}/${raw_mask#/}"
            else
                primary_cidr=$raw_ip
            fi
            primary_gw=$(prompt_default "3) On-site Default Gateway IPv4 (press Enter if offline/no router)" "")
            primary_dns=$(prompt_default "4) On-site DNS Server IPv4s, comma-separated (press Enter if offline)" "")

            local has_sensor
            has_sensor=$(prompt_default "5) Configure a 2nd dedicated Ethernet NIC for RPMs & Cameras? (y/N)" "N")
            if [[ $has_sensor =~ ^[Yy] ]]; then
                sensor_nic=$(prompt_default "   Sensor Ethernet interface name (must differ from ${primary_nic})" "")
                raw_ip=$(prompt_default "   Sensor Static IPv4 (e.g. 192.168.50.10/24 or 192.168.50.10)" "")
                if [[ $raw_ip != */* ]]; then
                    raw_mask=$(prompt_default "   Sensor subnet mask or prefix (e.g. 255.255.255.0 or 24)" "24")
                    sensor_cidr="${raw_ip}/${raw_mask#/}"
                else
                    sensor_cidr=$raw_ip
                fi
            fi
            site_hostname=$(prompt_default "6) On-site OSCAR hostname" "oscar.local")
        fi

        valid_iface_name "$primary_nic" || fail "Invalid PRIMARY_NIC '${primary_nic}'."
        primary_cidr=$(normalize_ipv4_cidr "$primary_cidr") || fail "Invalid PRIMARY_IP_CIDR '${primary_cidr}'. Use CIDR (10.20.30.10/24) or IP/Netmask (10.20.30.10/255.255.255.0)."
        if [[ -n $primary_gw ]]; then
            is_ipv4 "$primary_gw" || fail "Invalid PRIMARY_GATEWAY IPv4: ${primary_gw}"
        fi
        if [[ -n $primary_dns ]]; then
            local d
            IFS=', ' read -r -a dlist <<<"$primary_dns"
            for d in "${dlist[@]}"; do
                [[ -n $d ]] || continue
                is_ipv4 "$d" || fail "Invalid DNS IPv4 address: ${d}"
            done
        fi
        if [[ -n $sensor_nic || -n $sensor_cidr ]]; then
            [[ -n $sensor_nic && -n $sensor_cidr ]] || fail "Both SENSOR_NIC and SENSOR_IP_CIDR are required when configuring a second NIC."
            valid_iface_name "$sensor_nic" || fail "Invalid SENSOR_NIC '${sensor_nic}'."
            [[ $sensor_nic != "$primary_nic" ]] || fail "SENSOR_NIC (${sensor_nic}) must be a different port than PRIMARY_NIC (${primary_nic})."
            sensor_cidr=$(normalize_ipv4_cidr "$sensor_cidr") || fail "Invalid SENSOR_IP_CIDR '${sensor_cidr}'."
        fi

        local renderer
        renderer=$(detect_netplan_renderer)
        write_staged_netplan "$renderer" "$primary_nic" "$primary_cidr" "$primary_gw" "$primary_dns" "$sensor_nic" "$sensor_cidr" "${site_hostname:-oscar.local}"
        info "Validated and staged on-site Netplan configuration -> ${staged_netplan_file}"
    fi

    local san_args=() ip
    while IFS= read -r ip; do
        [[ -n $ip ]] && san_args+=("--tls-san" "$ip")
    done < <(extract_staged_ips "$staged_netplan_file")

    if [[ -z $host_root && -f "$script_dir/.oscar-init-state" && -f "$script_dir/oscar-setup.sh" ]]; then
        info "Updating existing OSCAR TLS certificate SANs so ${staged_netplan_file} IPs are pre-trusted..."
        bash "$script_dir/oscar-setup.sh" refresh-tls "${san_args[@]}"
    else
        printf '\nNext Steps While Still Off-Site / In the Hotel Room:\n'
        printf '  1) Initialize OSCAR (automatically embeds your staged on-site IPs into TLS):\n'
        printf '       sudo bash oscar.sh init --hostname %s' "${site_hostname:-oscar.local}"
        for ip in "${san_args[@]}"; do printf ' %s' "$ip"; done
        printf '\n'
        printf '  2) Open OSCAR Viewer / Admin UI locally, pre-load your RPM & Camera Lane CSV, and add users.\n'
        printf '  3) When you arrive ON-SITE and plug in the site cables, run ONE command:\n'
        printf '       sudo bash oscar.sh apply-site-network\n\n'
    fi
}

run_apply_site_network() {
    local keep_wifi=false
    while (($# > 0)); do
        case "$1" in
            --keep-wifi) keep_wifi=true; shift ;;
            -h|--help)
                cat <<'EOF'
Usage: sudo bash oscar.sh apply-site-network [--keep-wifi]

Backs up /etc/netplan/*.yaml, activates /etc/oscar/staged-netplan/90-oscar-site.yaml,
refreshes OSCAR's self-signed TLS certificate SANs if needed, and verifies OSCAR health.
To undo and revert to DHCP: sudo bash oscar.sh rollback-network
EOF
                return 0
                ;;
            *) fail "Unknown apply-site-network option: $1" ;;
        esac
    done

    require_linux
    require_root
    [[ -f $staged_netplan_file ]] || fail "No staged site network found at ${staged_netplan_file}. Run 'sudo bash oscar.sh stage-site-network' first."

    local ts backup_dir
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    backup_dir="${netplan_backup_root}/${ts}"
    mkdir -p "$backup_dir" "$live_netplan_dir"
    chmod 0700 "$netplan_backup_root" "$backup_dir"

    local f base
    for f in "$live_netplan_dir"/*.yaml "$live_netplan_dir"/*.yml; do
        [[ -e $f ]] || continue
        base=$(basename "$f")
        cp -a "$f" "$backup_dir/$base"
        if $keep_wifi && grep -Eq '^[[:space:]]*wifis:' "$f"; then
            info "Keeping existing Wi-Fi Netplan file (${base}) alongside static Ethernet."
        else
            rm -f "$f"
        fi
    done

    cp "$staged_netplan_file" "$live_netplan_dir/90-oscar-site.yaml"
    chmod 0600 "$live_netplan_dir/90-oscar-site.yaml"
    printf '%s\n' "$backup_dir" > "${oscar_etc_dir}/last-netplan-backup"

    if [[ -z $host_root ]]; then
        info "Applying on-site static Netplan configuration (backup saved to ${backup_dir})..."
        netplan apply
        sleep 2
        printf '\nActive On-Site NIC Status:\n'
        print_nic_table || true

        if [[ -f "$script_dir/.oscar-init-state" && -f "$script_dir/oscar-setup.sh" ]]; then
            info "Ensuring OSCAR TLS certificate covers active site IP addresses and services are running..."
            bash "$script_dir/oscar-setup.sh" refresh-tls
            bash "$script_dir/oscar-setup.sh" start
            bash "$script_dir/oscar-setup.sh" status
        fi
    else
        info "Test-root mode: installed ${live_netplan_dir}/90-oscar-site.yaml (backup: ${backup_dir})."
    fi

    printf '\nSite network cutover complete. If you ever need to revert to the previous DHCP config:\n'
    printf '  sudo bash oscar.sh rollback-network\n'
}

run_rollback_network() {
    require_linux
    require_root
    local backup_dir=''
    if [[ -f "${oscar_etc_dir}/last-netplan-backup" ]]; then
        backup_dir=$(cat "${oscar_etc_dir}/last-netplan-backup")
    fi
    if [[ -z $backup_dir || ! -d $backup_dir ]]; then
        backup_dir=$(find "$netplan_backup_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort | tail -n1 || true)
    fi
    [[ -n $backup_dir && -d $backup_dir ]] || fail "No Netplan backup found under ${netplan_backup_root}."

    info "Restoring Netplan configuration from ${backup_dir}..."
    rm -f "$live_netplan_dir/90-oscar-site.yaml"
    local f
    for f in "$backup_dir"/*; do
        [[ -e $f ]] || continue
        cp -a "$f" "$live_netplan_dir/"
    done
    if [[ -z $host_root ]]; then
        netplan apply
        sleep 2
        print_nic_table || true
    fi
    info "Network configuration rolled back."
}

# ---------------------------------------------------------------------------
# 5. DISCOVER-DEVICES (Find Unknown RPMs & RTSP Cameras on Offline Switches)
# ---------------------------------------------------------------------------
classify_open_ports() {
    local ports=$1
    if [[ ",$ports," == *,554,* || ",$ports," == *,8554,* ]]; then
        printf 'Likely IP Camera (RTSP)'
    elif [[ ",$ports," == *,10001,* || ",$ports," == *,2101,* || ",$ports," == *,4001,* || ",$ports," == *,4002,* || ",$ports," == *,502,* ]]; then
        printf 'Likely RPM / Serial-Ethernet Controller'
    elif [[ ",$ports," == *,8000,* || ",$ports," == *,37777,* ]]; then
        printf 'Likely Camera / NVR'
    elif [[ ",$ports," == *,80,* || ",$ports," == *,443,* || ",$ports," == *,8080,* ]]; then
        printf 'Web-Managed Device / Camera / Switch'
    elif [[ ",$ports," == *,22,* ]]; then
        printf 'Linux / SSH Host'
    else
        printf 'Active Network Device'
    fi
}

run_discover_devices() {
    local iface='' subnet='' temp_ip='' csv_out='/tmp/oscar-discovered-devices.csv'
    while (($# > 0)); do
        case "$1" in
            --interface|-i) iface=${2:?missing interface name}; shift 2 ;;
            --subnet|-s) subnet=${2:?missing subnet CIDR}; shift 2 ;;
            --temp-ip) temp_ip=${2:?missing temporary IP/CIDR (e.g. 192.168.1.250/24)}; shift 2 ;;
            --output|-o) csv_out=${2:?missing CSV path}; shift 2 ;;
            -h|--help)
                cat <<'EOF'
Usage:
  sudo bash oscar.sh discover-devices [--interface NIC] [--subnet CIDR] [--temp-ip IP/CIDR]

Examples:
  # Scan the subnet already assigned to enp2s0:
  sudo bash oscar.sh discover-devices --interface enp2s0

  # Scan an unknown/no-DHCP camera switch on factory subnet 192.168.1.0/24
  # (temporarily adds 192.168.1.250/24 during the scan and cleans it up automatically):
  sudo bash oscar.sh discover-devices --interface enp2s0 --temp-ip 192.168.1.250/24
EOF
                return 0
                ;;
            *) fail "Unknown discover-devices option: $1" ;;
        esac
    done

    require_linux
    require_root

    if [[ -z $iface ]]; then
        iface=$(list_physical_nics | while read -r n; do [[ $(nic_carrier_label "$n") == PLUGGED_IN && $(nic_type "$n") == ethernet ]] && { echo "$n"; break; }; done || true)
        [[ -n $iface ]] || fail "Could not auto-select a plugged-in Ethernet port. Pass '--interface <NIC>' (run 'sudo bash oscar.sh identify-nics' first)."
    fi
    valid_iface_name "$iface" || fail "Invalid interface: $iface"

    local added_temp_ip=''
    cleanup_temp_ip() {
        if [[ -n $added_temp_ip ]]; then
            ip addr del "$added_temp_ip" dev "$iface" 2>/dev/null || true
        fi
    }
    trap cleanup_temp_ip EXIT HUP INT TERM

    if [[ -n $temp_ip ]]; then
        temp_ip=$(normalize_ipv4_cidr "$temp_ip") || fail "Invalid --temp-ip '${temp_ip}' (expected e.g. 192.168.1.250/24)."
        ip link set "$iface" up || true
        if ! ip -4 -o addr show dev "$iface" | grep -Fq " ${temp_ip} "; then
            info "Temporarily assigning probe address ${temp_ip} on ${iface} (auto-removed after scan)..."
            ip addr add "$temp_ip" dev "$iface"
            added_temp_ip=$temp_ip
            sleep 1
        fi
        [[ -n $subnet ]] || subnet=$temp_ip
    fi

    if [[ -z $subnet ]]; then
        subnet=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk 'NR==1 {print $4}' || true)
        [[ -n $subnet ]] || fail "Interface ${iface} has no IPv4 address (no DHCP on this wire?). Pass '--temp-ip 192.168.1.250/24' (or 192.168.0.250/24, 10.0.0.250/24) to probe factory subnets."
    fi

    local self_ips
    self_ips=$(ip -4 -o addr show 2>/dev/null | awk '{sub(/\/.*/,"",$4); print $4}' | paste -sd '|' - || true)
    info "Scanning ${subnet} on ${iface} for cameras (RTSP 554/8554, HTTP 80/443/8000/8080) and RPM controllers..."

    local host_ips=()
    if command -v arp-scan >/dev/null 2>&1 && [[ -z $temp_ip ]]; then
        while IFS= read -r hip; do
            [[ -n $hip ]] && host_ips+=("$hip")
        done < <(arp-scan --interface="$iface" --localnet --quiet 2>/dev/null | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\t/ {print $1}' | LC_ALL=C sort -u || true)
    fi

    if ((${#host_ips[@]} == 0)) && command -v nmap >/dev/null 2>&1; then
        while IFS= read -r hip; do
            [[ -n $hip ]] && host_ips+=("$hip")
        done < <(nmap -sn -n -e "$iface" "$subnet" 2>/dev/null | awk '/Nmap scan report for / {print $NF}' | tr -d '()' | LC_ALL=C sort -u || true)
    fi

    printf 'ip,mac,open_ports,classification\n' > "$csv_out"
    printf '\n%-16s %-19s %-24s %s\n' "IP ADDRESS" "MAC ADDRESS" "OPEN PORTS" "CLASSIFICATION"
    printf '%-16s %-19s %-24s %s\n' "----------------" "-------------------" "------------------------" "---------------------------------------"

    local found=0 hip mac open_ports role
    for hip in "${host_ips[@]}"; do
        [[ "|${self_ips}|" == *"|${hip}|"* ]] && continue
        mac=$(ip neigh show "$hip" dev "$iface" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="lladdr") print $(i+1)}' | head -n1 || true)
        open_ports=''
        if command -v nmap >/dev/null 2>&1; then
            open_ports=$(nmap -Pn -n -T4 --open -p 22,80,443,502,554,2101,4001,4002,8000,8080,8554,10001,37777 "$hip" 2>/dev/null \
                | awk -F/ '/^[0-9]+\/tcp[[:space:]]+open/ {print $1}' | paste -sd ',' - || true)
        fi
        role=$(classify_open_ports "${open_ports:-none}")
        printf '%-16s %-19s %-24s %s\n' "$hip" "${mac:--}" "${open_ports:-icmp/arp-only}" "$role"
        printf '%s,%s,"%s","%s"\n' "$hip" "${mac:--}" "${open_ports:-}" "$role" >> "$csv_out"
        ((found += 1))
    done

    cleanup_temp_ip
    trap - EXIT HUP INT TERM
    printf '\nDiscovered %d live device(s) on %s (saved to %s).\n' "$found" "$iface" "$csv_out"
}

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
subcommand=${1:-help}
shift || true

case "$subcommand" in
    host-check|check)       run_host_check "$@" ;;
    prepare-host|apply)     run_prepare_host "$@" ;;
    identify-nics|nics)     run_identify_nics "$@" ;;
    stage-site-network)     run_stage_site_network "$@" ;;
    apply-site-network)     run_apply_site_network "$@" ;;
    rollback-network)       run_rollback_network "$@" ;;
    discover-devices|scan)  run_discover_devices "$@" ;;
    help|-h|--help)
        cat <<'EOF'
OSCAR Ubuntu 24.04 Host & Field Cutover Utility
===============================================

Commands (invoke via 'sudo bash oscar.sh <command>'):
  host-check          Audit Ubuntu 24.04 LVM, Docker, sleep, reboot, sysctl, time, and NIC readiness
  prepare-host        Install/configure Docker, disable sleep & auto-reboots, tune sysctl (online or --offline)
  identify-nics       List physical Ethernet/Wi-Fi ports, blink port LEDs, or --watch cable plug/unplug live
  stage-site-network  Pre-stage on-site static IP Netplan YAML in a hotel room without dropping Wi-Fi/DHCP
  apply-site-network  Activate the staged static IPs on-site, refresh TLS SANs, and verify OSCAR startup
  rollback-network    Revert /etc/netplan to the previous DHCP backup immediately
  discover-devices    Scan an attached or factory-default switch subnet for RPMs and RTSP cameras
EOF
        ;;
    *)
        fail "Unknown Ubuntu host command: ${subcommand}. Run 'bash configure-ubuntu-host.sh help'."
        ;;
esac
