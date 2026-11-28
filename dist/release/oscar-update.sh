#!/usr/bin/env bash
# OSCAR Zero-Login GitHub & Offline Bundle System Update Manager (Ubuntu 24.04 / 26.04 LTS)
# Discovers, SHA-256 verifies, extracts to a clean sibling release directory, and
# upgrades OSCAR in place (with automatic fail-safe rollback on failure) without
# requiring a GitHub account, Personal Access Token, or docker.sock inside containers.
set -Eeuo pipefail

script_path=${BASH_SOURCE[0]}
[[ ! -L $script_path ]] || { printf 'ERROR: Refusing to execute symlinked script: %s\n' "$script_path" >&2; exit 1; }
case $script_path in */*) script_parent=${script_path%/*} ;; *) script_parent=. ;; esac
script_dir=$(CDPATH= cd -P -- "$script_parent" && pwd -P)

prod_state_volume=${OSCAR_STATE_VOLUME:-oscar_oscar_state}
systemd_dir=${OSCAR_UPDATE_SYSTEMD_DIR:-/etc/systemd/system}
min_free_gib=${OSCAR_UPDATE_MIN_DISK_GIB:-4}

default_github_base="https://github.com/ORNL/oscar"
github_base=${OSCAR_UPDATE_GITHUB_BASE_URL:-$default_github_base}
github_base=${github_base%/}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_root() {
    if [[ ${OSCAR_UPDATE_ALLOW_NONROOT:-0} == 1 ]]; then
        return 0
    fi
    [[ ${EUID:-$(id -u)} -eq 0 ]] || fail 'Run this command with sudo (root privileges required).'
}

assert_allowed_github_origin() {
    if [[ ${OSCAR_UPDATE_ALLOW_CUSTOM_BASE_URL:-0} == 1 ]]; then
        return 0
    fi
    [[ $github_base == "$default_github_base" ]] || \
        fail "Refusing untrusted GitHub release origin: $github_base (expected $default_github_base)."
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
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/}
    s=${s//$'\t'/ }
    printf '%s' "$s"
}

validate_semver_311() {
    local v=${1:-}
    [[ $v =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-[0-9A-Za-z.-]+)?$ ]] || fail "Invalid release version format: $v"
    local major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]}
    if (( major < 3 || (major == 3 && minor < 11) )); then
        fail "In-place system update requires OSCAR 3.11.0 or newer (received $v)."
    fi
}

semver_gt() {
    # Returns 0 if $1 > $2
    local a=${1%%-*} b=${2%%-*}
    [[ $a != "$b" ]] || return 1
    local IFS=.
    local -a va=($a) vb=($b)
    local i
    for i in 0 1 2; do
        local na=${va[$i]:-0} nb=${vb[$i]:-0}
        if (( 10#$na > 10#$nb )); then return 0; fi
        if (( 10#$na < 10#$nb )); then return 1; fi
    done
    return 1
}

available_disk_gib() {
    local target_path=${1:-$script_dir}
    local avail_kb
    avail_kb=$(df -Pk "$target_path" 2>/dev/null | awk 'NR==2 {print $4}' || echo 33554432)
    awk -v kb="${avail_kb:-33554432}" 'BEGIN { printf "%.1f", kb / (1024 * 1024) }'
}

assert_free_disk() {
    local check_dir=${1:-$script_dir}
    local avail_kb min_kb
    avail_kb=$(df -Pk "$check_dir" 2>/dev/null | awk 'NR==2 {print $4}' || echo 33554432)
    min_kb=$(( min_free_gib * 1024 * 1024 ))
    (( avail_kb >= min_kb )) || fail "Insufficient free disk space on $(df -P "$check_dir" | awk 'NR==2 {print $6}') ($(available_disk_gib "$check_dir") GiB free; >= ${min_free_gib} GiB required)."
}

resolve_control_dir() {
    if [[ -n ${OSCAR_UPDATE_CONTROL_DIR:-} ]]; then
        printf '%s' "$OSCAR_UPDATE_CONTROL_DIR"
        return 0
    fi
    if command -v docker >/dev/null 2>&1 && docker volume inspect "$prod_state_volume" >/dev/null 2>&1; then
        local mp
        mp=$(docker volume inspect --format '{{.Mountpoint}}' "$prod_state_volume" 2>/dev/null || true)
        if [[ -n $mp && -d $mp ]]; then
            printf '%s/.moduledata/update-control' "$mp"
            return 0
        fi
    fi
    return 1
}

is_bridge_enabled() {
    if [[ ${OSCAR_UPDATE_FORCE_BRIDGE_ACTIVE:-0} == 1 ]]; then
        return 0
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --no-ask-password is-active --quiet oscar-update-agent.path 2>/dev/null || \
            systemctl --no-ask-password is-active --quiet oscar-update-agent.timer 2>/dev/null
        return $?
    fi
    return 1
}

is_usb_backup_attached() {
    local usb_cfg=${OSCAR_USB_BACKUP_CONFIG:-/etc/oscar/usb-backup.env}
    if [[ -f $usb_cfg ]]; then
        local mnt fs_uuid
        mnt=$(env_value USB_BACKUP_MOUNT '' "$usb_cfg")
        fs_uuid=$(env_value USB_BACKUP_FS_UUID '' "$usb_cfg")
        if [[ -n $mnt && -d $mnt && ! -e "$mnt/.oscar-unmounted-guard" && ! -e "$mnt/.oscar-ejected" ]]; then
            if [[ -n $fs_uuid ]] && command -v findmnt >/dev/null 2>&1; then
                findmnt -rn --target "$mnt" >/dev/null 2>&1 || return 1
                local mounted_src root_src
                mounted_src=$(findmnt -rn -o SOURCE --target "$mnt" 2>/dev/null || true)
                root_src=$(findmnt -rn -o SOURCE --target / 2>/dev/null || true)
                [[ -n $mounted_src && $mounted_src != "$root_src" ]] || return 1
            fi
            [[ -f "$mnt/OSCAR-Backup/.oscar-usb-backup-root" ]] && return 0
        fi
        return 1
    fi
    if [[ -x "$script_dir/oscar-usb-backup.sh" || -f "$script_dir/oscar-usb-backup.sh" ]]; then
        if bash "$script_dir/oscar-usb-backup.sh" status 2>/dev/null | grep -Eq '(Drive State:[[:space:]]*ATTACHED|"driveMounted"[[:space:]]*:[[:space:]]*true)'; then
            return 0
        fi
    fi
    return 1
}

is_backup_possible() {
    if is_usb_backup_attached; then
        return 0
    fi
    local bmode
    bmode=$(env_value OSCAR_BACKUP_MODE 'disabled')
    if [[ $bmode == single ]]; then
        return 0
    fi
    return 1
}

write_bridge_status() {
    local state=${1:-IDLE} stage=${2:-IDLE} pct=${3:-0} target_ver=${4:-} req_id=${5:-} action=${6:-} msg=${7:-} log_file=${8:-}
    local ctrl_dir
    ctrl_dir=$(resolve_control_dir || true)
    [[ -n $ctrl_dir ]] || return 0
    install -d -m 0700 -o 10001 -g 10001 "$ctrl_dir" "$ctrl_dir/staged" 2>/dev/null || install -d -m 0700 "$ctrl_dir" "$ctrl_dir/staged"

    local agent_active=false gui_enabled=true backup_ok=false cur_ver disk_gib log_tail=""
    is_bridge_enabled && agent_active=true
    local gui_pref
    gui_pref=$(env_value OSCAR_GUI_UPDATE 'enabled')
    if [[ -f /etc/oscar-update-bridge.disabled || ${gui_pref,,} == "disabled" || ${gui_pref,,} == "false" ]]; then
        gui_enabled=false
    fi
    is_backup_possible && backup_ok=true
    cur_ver=$(oscar_version)
    disk_gib=$(available_disk_gib "$script_dir")
    if [[ -n $log_file && -f $log_file ]]; then
        log_tail=$(tail -n 25 "$log_file" 2>/dev/null | cut -c 1-240 || true)
    fi

    local now_iso
    now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local tmp="$ctrl_dir/status.json.tmp.$$"
    {
        printf '{\n'
        printf '  "agentActive": %s,\n' "$agent_active"
        printf '  "guiUpdateEnabled": %s,\n' "$gui_enabled"
        printf '  "backupPossible": %s,\n' "$backup_ok"
        printf '  "state": "%s",\n' "$(json_escape "$state")"
        printf '  "stage": "%s",\n' "$(json_escape "$stage")"
        printf '  "progressPercent": %s,\n' "${pct:-0}"
        printf '  "currentVersion": "%s",\n' "$(json_escape "$cur_ver")"
        printf '  "releaseDir": "%s",\n' "$(json_escape "$script_dir")"
        printf '  "availableDiskGib": %s,\n' "$disk_gib"
        printf '  "updatedAt": "%s"' "$now_iso"
        if [[ -n $target_ver ]]; then
            printf ',\n  "targetVersion": "%s"' "$(json_escape "$target_ver")"
        fi
        if [[ -n $msg ]]; then
            printf ',\n  "message": "%s"' "$(json_escape "$msg")"
        fi
        if [[ -n $log_tail ]]; then
            printf ',\n  "logTail": "%s"' "$(json_escape "$log_tail")"
        fi
        if [[ -n $req_id ]]; then
            printf ',\n  "activeJob": {"requestId": "%s", "action": "%s", "state": "%s", "stage": "%s", "progressPercent": %s, "targetVersion": "%s", "message": "%s", "updatedAt": "%s"}' \
                "$(json_escape "$req_id")" "$(json_escape "$action")" "$(json_escape "$state")" "$(json_escape "$stage")" "${pct:-0}" "$(json_escape "$target_ver")" "$(json_escape "$msg")" "$now_iso"
        fi
        printf '\n}\n'
    } >"$tmp"
    chown 10001:10001 "$tmp" 2>/dev/null || true
    chmod 0600 "$tmp"
    mv -f -- "$tmp" "$ctrl_dir/status.json"
}

discover_latest_github_release() {
    assert_allowed_github_origin
    command -v curl >/dev/null 2>&1 || fail 'curl is required for GitHub release checks.'

    discovered_version=""
    discovered_sha256=""
    discovered_url=""

    local headers loc
    headers=$(curl -sI --connect-timeout 8 --max-time 15 \
        -A "OSCAR-SystemUpdater/3.11" \
        "${github_base}/releases/latest" 2>/dev/null || true)
    loc=$(printf '%s\n' "$headers" | awk 'tolower($1) == "location:" { sub(/^[^:]+:[[:space:]]*/, ""); gsub(/\r/, ""); print; exit }')
    if [[ -z $loc ]]; then
        headers=$(curl -sD - -o /dev/null --connect-timeout 8 --max-time 15 \
            -A "OSCAR-SystemUpdater/3.11" \
            "${github_base}/releases/latest" 2>/dev/null || true)
        loc=$(printf '%s\n' "$headers" | awk 'tolower($1) == "location:" { sub(/^[^:]+:[[:space:]]*/, ""); gsub(/\r/, ""); print; exit }')
    fi
    if [[ $loc =~ /releases/tag/v([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?)([/?#]|$) ]]; then
        discovered_version=${BASH_REMATCH[1]}
    fi

    if [[ -z $discovered_version ]]; then
        local atom
        atom=$(curl -fsSL --connect-timeout 8 --max-time 15 \
            -A "OSCAR-SystemUpdater/3.11" \
            "${github_base}/releases.atom" 2>/dev/null || true)
        discovered_version=$(printf '%s\n' "$atom" | sed -n 's|.*/releases/tag/v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)["/?<].*|\1|p' | head -n 1)
    fi

    [[ -n $discovered_version ]] || fail "Unable to reach GitHub Releases at ${github_base} (host may be offline; use --from-zip or GUI Offline Bundle Upload)."
    validate_semver_311 "$discovered_version"

    discovered_url="${github_base}/releases/download/v${discovered_version}/oscar-${discovered_version}.zip"
    local sha_raw
    sha_raw=$(curl -fsSL --connect-timeout 8 --max-time 15 \
        -A "OSCAR-SystemUpdater/3.11" \
        "${discovered_url}.sha256" 2>/dev/null || true)
    discovered_sha256=$(printf '%s\n' "$sha_raw" | grep -Eo '\b[0-9a-fA-F]{64}\b' | head -n 1 | tr 'A-F' 'a-f' || true)
}

do_check() {
    local json_mode=false
    while (($#)); do
        case "$1" in
            --json) json_mode=true ;;
            *) fail "Unknown check option: $1" ;;
        esac
        shift
    done
    local cur_ver update_avail=false
    cur_ver=$(oscar_version)
    discover_latest_github_release
    if semver_gt "$discovered_version" "$cur_ver"; then
        update_avail=true
    fi
    if $json_mode; then
        printf '{"currentVersion":"%s","latestVersion":"%s","updateAvailable":%s,"requiresGitHubLogin":false,"downloadUrl":"%s","expectedSha256":"%s"}\n' \
            "$(json_escape "$cur_ver")" "$(json_escape "$discovered_version")" "$update_avail" "$(json_escape "$discovered_url")" "$(json_escape "$discovered_sha256")"
        return 0
    fi
    printf 'Current installed version: %s\n' "$cur_ver"
    printf 'Latest GitHub release:     %s (zero GitHub login required)\n' "$discovered_version"
    [[ -z $discovered_sha256 ]] || printf 'Expected SHA-256:          %s\n' "$discovered_sha256"
    if $update_avail; then
        printf 'Status:                    UPDATE AVAILABLE (%s -> %s)\n' "$cur_ver" "$discovered_version"
        printf 'Apply upgrade:             sudo bash oscar.sh update apply\n'
    else
        printf 'Status:                    UP TO DATE\n'
    fi
}

resolve_sibling_target_dir() {
    local target_ver=$1
    local parent_dir parent_name grand_dir candidate
    parent_dir=$(CDPATH= cd -P -- "$script_dir/.." && pwd -P)
    parent_name=$(basename "$parent_dir")
    # Support both /srv/oscar/oscar-3.11.8 and /srv/oscar-test/releases/3.11.8/oscar-3.11.8 layouts
    if [[ $parent_name =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
        grand_dir=$(CDPATH= cd -P -- "$parent_dir/.." && pwd -P)
        install -d -m 0755 "$grand_dir/$target_ver"
        candidate="$grand_dir/$target_ver/oscar-$target_ver"
    else
        candidate="$parent_dir/oscar-$target_ver"
    fi
    if [[ $candidate == "$script_dir" ]]; then
        candidate="${candidate}-r$(date -u +%Y%m%d%H%M%S)"
    fi
    printf '%s' "$candidate"
}

copy_deployment_state_into_target() {
    local src_dir=$1 dst_dir=$2
    [[ -f "$src_dir/.env" ]] || fail "Active release directory $src_dir is missing .env (run init before upgrading)."
    cp -pf "$src_dir/.env" "$dst_dir/.env"

    if [[ -d "$src_dir/secrets" ]]; then
        install -d -m 0700 "$dst_dir/secrets"
        cp -pf "$src_dir/secrets/"* "$dst_dir/secrets/" 2>/dev/null || true
    fi
    if [[ -d "$src_dir/tls" ]]; then
        install -d -m 0755 "$dst_dir/tls"
        cp -pf "$src_dir/tls/"* "$dst_dir/tls/" 2>/dev/null || true
    fi
    for receipt in .oscar-init-state .oscar-volume-adoption; do
        if [[ -f "$src_dir/$receipt" && ! -L "$src_dir/$receipt" ]]; then
            cp -pf "$src_dir/$receipt" "$dst_dir/$receipt"
        fi
    done
}

verify_local_https_ready() {
    local target_dir=$1
    local port
    port=$(env_value OSCAR_HTTPS_PORT '443' "$target_dir/.env")
    if ! command -v curl >/dev/null 2>&1; then
        return 0
    fi
    local attempt
    for attempt in $(seq 1 30); do
        if curl -fsSk --connect-timeout 3 --max-time 5 "https://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

perform_upgrade() {
    local target_ver=${1:-} zip_source=${2:-} expected_sha=${3:-} backup_first=${4:-false} req_id=${5:-cli} action_name=${6:-upgrade}
    require_root
    [[ -f "$script_dir/.env" ]] || fail 'Current OSCAR directory is not initialized (.env not found).'
    command -v unzip >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || fail 'unzip or python3 is required to extract OSCAR release archives.'
    command -v sha256sum >/dev/null 2>&1 || fail 'sha256sum is required to verify OSCAR release archives.'

    local work_tmp log_file
    work_tmp=$(mktemp -d "${TMPDIR:-/tmp}/oscar-update.XXXXXX")
    log_file="$work_tmp/update.log"
    : >"$log_file"

    local downloaded_zip=""
    if [[ -z $zip_source ]]; then
        write_bridge_status "RUNNING" "CHECKING" 10 "$target_ver" "$req_id" "$action_name" "Checking GitHub Releases (no login required)..." "$log_file"
        assert_allowed_github_origin
        if [[ -z $target_ver ]]; then
            discover_latest_github_release
            target_ver=$discovered_version
            [[ -n $expected_sha ]] || expected_sha=$discovered_sha256
        else
            validate_semver_311 "$target_ver"
            if [[ -z $expected_sha ]]; then
                local sha_url="${github_base}/releases/download/v${target_ver}/oscar-${target_ver}.zip.sha256"
                expected_sha=$(curl -fsSL --connect-timeout 8 --max-time 15 -A "OSCAR-SystemUpdater/3.11" "$sha_url" 2>>"$log_file" | grep -Eo '\b[0-9a-fA-F]{64}\b' | head -n 1 | tr 'A-F' 'a-f' || true)
            fi
        fi
        [[ -n $expected_sha ]] || {
            write_bridge_status "FAILED" "FAILED" 0 "$target_ver" "$req_id" "$action_name" "Release SHA-256 checksum file not found for v${target_ver}." "$log_file"
            rm -rf -- "$work_tmp"
            fail "Could not retrieve SHA-256 checksum for oscar-${target_ver}.zip."
        }
    else
        [[ -f $zip_source && ! -L $zip_source ]] || fail "Bundle zip file not found: $zip_source"
        if [[ -z $target_ver ]]; then
            if command -v unzip >/dev/null 2>&1; then
                target_ver=$(unzip -p "$zip_source" '*/.env.example' 2>/dev/null | awk -F= '$1 == "OSCAR_VERSION" { print $2; exit }' | tr -d '\r')
            else
                target_ver=$(python3 - "$zip_source" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "r") as zf:
    for n in zf.namelist():
        if n.endswith("/.env.example"):
            for line in zf.read(n).decode("utf-8", errors="ignore").splitlines():
                if line.startswith("OSCAR_VERSION="):
                    print(line.split("=", 1)[1].strip())
                    raise SystemExit(0)
PY
)
            fi
        fi
        validate_semver_311 "$target_ver"
    fi

    assert_free_disk "$script_dir"

    if [[ $backup_first == true ]]; then
        if is_usb_backup_attached && [[ -f "$script_dir/oscar-usb-backup.sh" ]]; then
            write_bridge_status "RUNNING" "BACKING_UP" 22 "$target_ver" "$req_id" "$action_name" "Running zero-downtime incremental pre-upgrade sync to attached USB NVMe backup drive..." "$log_file"
            if ! bash "$script_dir/oscar-usb-backup.sh" sync >>"$log_file" 2>&1; then
                write_bridge_status "FAILED" "FAILED" 0 "$target_ver" "$req_id" "$action_name" "Pre-upgrade USB NVMe backup sync failed; aborting upgrade." "$log_file"
                rm -rf -- "$work_tmp"
                fail 'Pre-upgrade USB backup sync failed; deployment was left untouched.'
            fi
        elif [[ $(env_value OSCAR_BACKUP_MODE 'disabled') == single ]]; then
            write_bridge_status "RUNNING" "BACKING_UP" 22 "$target_ver" "$req_id" "$action_name" "Creating pre-upgrade encrypted backup snapshot..." "$log_file"
            if ! bash "$script_dir/oscar-setup.sh" backup >>"$log_file" 2>&1; then
                write_bridge_status "FAILED" "FAILED" 0 "$target_ver" "$req_id" "$action_name" "Pre-upgrade backup failed; aborting before modifying containers." "$log_file"
                rm -rf -- "$work_tmp"
                fail 'Pre-upgrade backup failed; deployment was left untouched.'
            fi
        fi
    fi

    if [[ -z $zip_source ]]; then
        local dl_url="${github_base}/releases/download/v${target_ver}/oscar-${target_ver}.zip"
        downloaded_zip="$work_tmp/oscar-${target_ver}.zip"
        write_bridge_status "RUNNING" "DOWNLOADING" 38 "$target_ver" "$req_id" "$action_name" "Downloading oscar-${target_ver}.zip from GitHub Releases..." "$log_file"
        if ! curl -fL --retry 2 --connect-timeout 15 -A "OSCAR-SystemUpdater/3.11" -o "$downloaded_zip" "$dl_url" >>"$log_file" 2>&1; then
            write_bridge_status "FAILED" "FAILED" 0 "$target_ver" "$req_id" "$action_name" "Failed downloading oscar-${target_ver}.zip from GitHub Releases." "$log_file"
            rm -rf -- "$work_tmp"
            fail "Download failed for $dl_url"
        fi
        zip_source=$downloaded_zip
    fi

    write_bridge_status "RUNNING" "VERIFYING_SHA256" 52 "$target_ver" "$req_id" "$action_name" "Verifying SHA-256 cryptographic digest of oscar-${target_ver}.zip..." "$log_file"
    local actual_sha
    actual_sha=$(sha256sum "$zip_source" | awk '{print tolower($1)}')
    if [[ -n $expected_sha && ${expected_sha,,} != "$actual_sha" ]]; then
        write_bridge_status "FAILED" "FAILED" 0 "$target_ver" "$req_id" "$action_name" "SHA-256 verification failed (expected ${expected_sha}, got ${actual_sha})." "$log_file"
        rm -rf -- "$work_tmp"
        fail "SHA-256 mismatch on $zip_source (expected $expected_sha, computed $actual_sha)."
    fi

    write_bridge_status "RUNNING" "EXTRACTING" 64 "$target_ver" "$req_id" "$action_name" "Extracting verified release into clean sibling directory..." "$log_file"
    local extract_stage="$work_tmp/expanded"
    mkdir -p "$extract_stage"
    local extract_ok=false
    if command -v unzip >/dev/null 2>&1; then
        unzip -q "$zip_source" -d "$extract_stage" >>"$log_file" 2>&1 && extract_ok=true || extract_ok=false
    else
        python3 - "$zip_source" "$extract_stage" >>"$log_file" 2>&1 <<'PY' && extract_ok=true || extract_ok=false
import os, pathlib, stat, sys, zipfile
zip_path, dst_root = sys.argv[1], pathlib.Path(sys.argv[2]).resolve()
with zipfile.ZipFile(zip_path, "r") as zf:
    for info in zf.infolist():
        unix_mode = info.external_attr >> 16
        if unix_mode and stat.S_ISLNK(unix_mode):
            raise SystemExit("Rejected symbolic link entry in release zip")
        target = (dst_root / info.filename).resolve()
        if dst_root not in target.parents and target != dst_root:
            raise SystemExit("Rejected path traversal entry in release zip")
        out_path = zf.extract(info, str(dst_root))
        if unix_mode and not info.is_dir():
            os.chmod(out_path, stat.S_IMODE(unix_mode))
        elif out_path.endswith(".sh"):
            os.chmod(out_path, 0o755)
PY
    fi
    if [[ $extract_ok != true ]]; then
        write_bridge_status "FAILED" "FAILED" 0 "$target_ver" "$req_id" "$action_name" "Failed extracting release zip archive." "$log_file"
        rm -rf -- "$work_tmp"
        fail 'Failed extracting release archive.'
    fi
    if find "$extract_stage" -type l -print -quit | grep -q .; then
        write_bridge_status "FAILED" "FAILED" 0 "$target_ver" "$req_id" "$action_name" "Rejected release archive containing symbolic links." "$log_file"
        rm -rf -- "$work_tmp"
        fail 'Rejected release archive containing symbolic links.'
    fi

    local extracted_root
    extracted_root=$(find "$extract_stage" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    [[ -n $extracted_root && -f "$extracted_root/oscar-setup.sh" && -f "$extracted_root/compose.yaml" ]] || {
        write_bridge_status "FAILED" "FAILED" 0 "$target_ver" "$req_id" "$action_name" "Extracted archive is missing oscar-setup.sh or compose.yaml." "$log_file"
        rm -rf -- "$work_tmp"
        fail 'Extracted archive is not a valid OSCAR release directory.'
    }

    local target_dir prev_existing_backup=""
    target_dir=$(resolve_sibling_target_dir "$target_ver")
    if [[ -e $target_dir ]]; then
        prev_existing_backup="${target_dir}.prev-$$"
        mv -f -- "$target_dir" "$prev_existing_backup"
    fi
    install -d -m 0755 "$(dirname "$target_dir")"
    mv -f -- "$extracted_root" "$target_dir"
    rm -f -- "$downloaded_zip" 2>/dev/null || true

    copy_deployment_state_into_target "$script_dir" "$target_dir"
    chmod +x "$target_dir"/*.sh 2>/dev/null || true

    write_bridge_status "RUNNING" "UPGRADING_CONTAINERS" 78 "$target_ver" "$req_id" "$action_name" "Building/loading OSCAR ${target_ver} images and upgrading containers (persistent volumes retained)..." "$log_file"

    local upgrade_ok=false
    if [[ ${OSCAR_UPDATE_DRY_RUN_UPGRADE:-0} == 1 ]]; then
        bash "$target_dir/oscar-setup.sh" simulated-upgrade >>"$log_file" 2>&1 && upgrade_ok=true || upgrade_ok=false
    else
        if bash "$target_dir/oscar-setup.sh" upgrade >>"$log_file" 2>&1; then
            write_bridge_status "RUNNING" "WAITING_HEALTHY" 92 "$target_ver" "$req_id" "$action_name" "Verifying HTTPS gateway readiness on OSCAR ${target_ver}..." "$log_file"
            if verify_local_https_ready "$target_dir"; then
                upgrade_ok=true
            else
                printf 'HTTPS /healthz readiness check timed out on %s\n' "$target_dir" >>"$log_file"
                upgrade_ok=false
            fi
        fi
    fi

    if $upgrade_ok; then
        [[ -z $prev_existing_backup ]] || rm -rf -- "$prev_existing_backup"
        # Delegate final status write to the newly activated target_dir script so releaseDir & currentVersion reflect target_ver!
        if [[ -f "$target_dir/oscar-update.sh" ]]; then
            bash "$target_dir/oscar-update.sh" write-completed-status "$target_ver" "$req_id" "$action_name" "$log_file" || true
        else
            write_bridge_status "COMPLETED" "COMPLETED" 100 "$target_ver" "$req_id" "$action_name" "Successfully upgraded OSCAR to ${target_ver}." "$log_file"
        fi
        printf 'OSCAR successfully upgraded to %s in %s\n' "$target_ver" "$target_dir"
        rm -rf -- "$work_tmp"
        return 0
    fi

    # Fail-safe rollback to the untouched previous release directory!
    write_bridge_status "RUNNING" "ROLLING_BACK" 88 "$target_ver" "$req_id" "$action_name" "Upgrade failed; automatically rolling back to previous OSCAR $(oscar_version) release..." "$log_file"
    if [[ ${OSCAR_UPDATE_DRY_RUN_UPGRADE:-0} == 1 ]]; then
        bash "$script_dir/oscar-setup.sh" simulated-rollback >>"$log_file" 2>&1 || true
    else
        bash "$script_dir/oscar-setup.sh" upgrade >>"$log_file" 2>&1 || bash "$script_dir/oscar-setup.sh" start >>"$log_file" 2>&1 || true
    fi
    rm -rf -- "$target_dir" 2>/dev/null || true
    if [[ -n $prev_existing_backup && -d $prev_existing_backup ]]; then
        mv -f -- "$prev_existing_backup" "$target_dir" 2>/dev/null || true
    fi
    write_bridge_status "ROLLED_BACK" "ROLLED_BACK" 0 "$target_ver" "$req_id" "$action_name" "Upgrade to ${target_ver} failed; automatically restored previous OSCAR $(oscar_version) deployment." "$log_file"
    rm -rf -- "$work_tmp"
    fail "Upgrade to ${target_ver} failed; rolled back to $(oscar_version)."
}

do_apply_cli() {
    local target_ver="" from_zip="" use_staged=false expected_sha="" backup_first=false
    while (($#)); do
        case "$1" in
            --version) shift; target_ver=${1:-} ;;
            --from-zip) shift; from_zip=${1:-} ;;
            --staged) use_staged=true ;;
            --sha256) shift; expected_sha=${1:-} ;;
            --backup-first) backup_first=true ;;
            --yes|-y) ;;
            *) fail "Unknown apply option: $1" ;;
        esac
        shift
    done
    if $use_staged && [[ -z $from_zip ]]; then
        local ctrl_dir
        ctrl_dir=$(resolve_control_dir || fail 'OSCAR state volume not found for --staged.')
        from_zip=$(ls -1t "$ctrl_dir/staged"/oscar-*.zip 2>/dev/null | head -n 1 || true)
        [[ -n $from_zip ]] || fail 'No staged release .zip found in update-control/staged/.'
        if [[ -z $expected_sha && -f "${from_zip}.sha256" ]]; then
            expected_sha=$(awk '{print $1; exit}' "${from_zip}.sha256")
        fi
    fi
    perform_upgrade "$target_ver" "$from_zip" "$expected_sha" "$backup_first" "cli-$(date +%s)" "cli-upgrade"
}

do_status() {
    local json_mode=false
    [[ ${1:-} == --json ]] && json_mode=true
    local ctrl_dir
    ctrl_dir=$(resolve_control_dir || true)
    if $json_mode && [[ -n $ctrl_dir && -f "$ctrl_dir/status.json" ]]; then
        cat "$ctrl_dir/status.json"
        return 0
    fi
    local cur_ver bridge="DISABLED"
    cur_ver=$(oscar_version)
    is_bridge_enabled && bridge="ACTIVE"
    if $json_mode; then
        printf '{"currentVersion":"%s","agentActive":%s,"releaseDir":"%s","availableDiskGib":%s}\n' \
            "$(json_escape "$cur_ver")" "$([[ $bridge == ACTIVE ]] && echo true || echo false)" "$(json_escape "$script_dir")" "$(available_disk_gib "$script_dir")"
        return 0
    fi
    printf 'OSCAR System Update Status\n'
    printf '  Installed Version: %s\n' "$cur_ver"
    printf '  Release Directory: %s\n' "$script_dir"
    printf '  GUI Update Agent:  %s\n' "$bridge"
    printf '  Free Disk Space:   %s GiB\n' "$(available_disk_gib "$script_dir")"
}

enable_ui_bridge() {
    require_root
    command -v systemctl >/dev/null 2>&1 || fail 'systemd is required for enable-ui-bridge.'
    rm -f -- /etc/oscar-update-bridge.disabled
    local ctrl_dir
    ctrl_dir=$(resolve_control_dir || true)
    if [[ -n $ctrl_dir ]]; then
        install -d -m 0700 -o 10001 -g 10001 "$ctrl_dir" "$ctrl_dir/staged" 2>/dev/null || install -d -m 0700 "$ctrl_dir" "$ctrl_dir/staged"
    fi
    cat >"$systemd_dir/oscar-update-agent.service" <<EOF
[Unit]
Description=OSCAR Zero-Login System Update Host Agent
After=docker.service

[Service]
Type=oneshot
TimeoutStartSec=7200
ExecStart=/bin/bash "$script_dir/oscar-update.sh" poll-bridge
EOF
    if [[ -n $ctrl_dir ]]; then
        cat >"$systemd_dir/oscar-update-agent.path" <<EOF
[Unit]
Description=Watch OSCAR System Update GUI Queue

[Path]
PathExists=$ctrl_dir/request.json
PathChanged=$ctrl_dir/request.json
Unit=oscar-update-agent.service

[Install]
WantedBy=multi-user.target
EOF
    fi
    cat >"$systemd_dir/oscar-update-agent.timer" <<EOF
[Unit]
Description=Refresh OSCAR System Update Host Status

[Timer]
OnBootSec=20s
OnUnitActiveSec=60s
AccuracySec=3s

[Install]
WantedBy=timers.target
EOF
    # Reload unit files and ensure .path + .timer are active WITHOUT restarting
    # oscar-update-agent.service (which may be the parent process during a GUI upgrade!).
    systemctl daemon-reload
    if [[ -n $ctrl_dir ]]; then
        systemctl enable --now oscar-update-agent.path >/dev/null 2>&1 || true
    fi
    systemctl enable --now oscar-update-agent.timer >/dev/null 2>&1 || true
    if [[ ! -f "${ctrl_dir:-/nonexistent}/.active-update.lock" ]]; then
        write_bridge_status "IDLE" "IDLE" 0 "" "" "enable-ui-bridge" "GUI System Update agent active."
    fi
}

install_agent() {
    require_root
    local gui_pref
    gui_pref=$(env_value OSCAR_GUI_UPDATE 'enabled')
    if [[ -f /etc/oscar-update-bridge.disabled || ${gui_pref,,} == "disabled" || ${gui_pref,,} == "false" || ${OSCAR_UPDATE_SKIP_SYSTEMD:-0} == "1" ]]; then
        write_bridge_status "IDLE" "IDLE" 0 || true
        return 0
    fi
    if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
        enable_ui_bridge >/dev/null 2>&1 || true
    else
        write_bridge_status "IDLE" "IDLE" 0 || true
    fi
}

disable_ui_bridge() {
    require_root
    touch /etc/oscar-update-bridge.disabled 2>/dev/null || true
    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now oscar-update-agent.path oscar-update-agent.timer >/dev/null 2>&1 || true
        rm -f -- "$systemd_dir/oscar-update-agent.path" "$systemd_dir/oscar-update-agent.timer" "$systemd_dir/oscar-update-agent.service"
        systemctl daemon-reload || true
    fi
    write_bridge_status "IDLE" "IDLE" 0 "" "" "disable-ui-bridge" "GUI System Update bridge disabled."
    printf 'Disabled OSCAR GUI System Update host bridge.\n'
}

poll_bridge() {
    local ctrl_dir
    ctrl_dir=$(resolve_control_dir || true)
    [[ -n $ctrl_dir ]] || return 0
    local lock_file="$ctrl_dir/.active-update.lock"
    local req_file="$ctrl_dir/request.json"

    if [[ ! -f $req_file ]]; then
        if [[ -f $lock_file ]]; then
            local lock_age=$(( $(date +%s) - $(stat -c %Y "$lock_file" 2>/dev/null || echo 0) ))
            if (( lock_age >= 0 && lock_age < 7200 )); then
                return 0
            fi
            rm -f -- "$lock_file"
        fi
        # Preserve terminal COMPLETED / ROLLED_BACK / FAILED summary until next request, only refreshing currentVersion & agentActive if status.json is missing
        if [[ ! -f "$ctrl_dir/status.json" ]]; then
            write_bridge_status "IDLE" "IDLE" 0
        fi
        return 0
    fi

    local processing="$ctrl_dir/request.processing.$$"
    mv -f -- "$req_file" "$processing" 2>/dev/null || return 0
    touch "$lock_file" 2>/dev/null || true

    local raw req_id action target_ver expected_sha bundle_name backup_str backup_first=false
    raw=$(cat "$processing")
    rm -f -- "$processing"

    req_id=$(printf '%s' "$raw" | sed -n 's/.*"requestId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    action=$(printf '%s' "$raw" | sed -n 's/.*"action"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    target_ver=$(printf '%s' "$raw" | sed -n 's/.*"targetVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    expected_sha=$(printf '%s' "$raw" | sed -n 's/.*"expectedSha256"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    bundle_name=$(printf '%s' "$raw" | sed -n 's/.*"bundleFileName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    backup_str=$(printf '%s' "$raw" | sed -n 's/.*"createBackupFirst"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' | head -n 1)
    [[ $backup_str == "true" ]] && backup_first=true

    case "$action" in
        upgrade-github)
            ( perform_upgrade "$target_ver" "" "$expected_sha" "$backup_first" "$req_id" "$action" ) || true
            ;;
        upgrade-staged)
            local safe_base staged_zip
            safe_base=$(basename -- "${bundle_name:-invalid}")
            staged_zip="$ctrl_dir/staged/$safe_base"
            if [[ -f $staged_zip && ! -L $staged_zip ]]; then
                ( perform_upgrade "$target_ver" "$staged_zip" "$expected_sha" "$backup_first" "$req_id" "$action" ) || true
            else
                write_bridge_status "FAILED" "FAILED" 0 "$target_ver" "$req_id" "$action" "Staged bundle not found: $safe_base"
            fi
            ;;
        *)
            write_bridge_status "IDLE" "IDLE" 0 "" "$req_id" "$action" "Refreshed system update status."
            ;;
    esac
    rm -f -- "$lock_file"
}

usage() {
    cat <<'EOF'
Usage:
  bash oscar.sh update check [--json]
  sudo bash oscar.sh update apply [--version X.Y.Z] [--from-zip FILE | --staged] [--sha256 HEX] [--backup-first]
  bash oscar.sh update status [--json]
  sudo bash oscar.sh update enable-ui-bridge | disable-ui-bridge
EOF
}

subcmd=${1:-help}
if (($#)); then shift; fi

case "$subcmd" in
    check)
        do_check "$@"
        ;;
    apply|upgrade)
        do_apply_cli "$@"
        ;;
    status)
        do_status "$@"
        ;;
    enable-ui-bridge)
        enable_ui_bridge
        printf 'Enabled zero-login GUI System Update bridge.\n'
        ;;
    install-agent)
        install_agent
        ;;
    disable-ui-bridge)
        disable_ui_bridge
        ;;
    poll-bridge|run-once)
        require_root
        poll_bridge
        ;;
    write-completed-status)
        write_bridge_status "COMPLETED" "COMPLETED" 100 "${1:-}" "${2:-}" "${3:-upgrade}" "Successfully upgraded OSCAR to ${1:-$(oscar_version)}." "${4:-}"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        usage >&2
        fail "Unknown update subcommand: $subcmd"
        ;;
esac
