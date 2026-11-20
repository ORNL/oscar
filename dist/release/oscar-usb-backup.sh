#!/usr/bin/env bash
# OSCAR Continual & Occasional USB NVMe Incremental Backup Manager (Ubuntu 24.04 LTS)
# Supports zero-downtime continual background sync, 1-command switching between
# continual and occasional modes, safe field USB eject -> laptop copy -> hotplug
# auto-catch-up, and full bare-metal restoration onto a replacement machine.
set -Eeuo pipefail

script_path=${BASH_SOURCE[0]}
[[ ! -L $script_path ]] || { printf 'ERROR: Refusing to execute symlinked script: %s\n' "$script_path" >&2; exit 1; }
case $script_path in */*) script_parent=${script_path%/*} ;; *) script_parent=. ;; esac
script_dir=$(CDPATH= cd -P -- "$script_parent" && pwd -P)
engine_script="$script_dir/oscar-usb-backup-engine.sh"
config_file=${OSCAR_USB_BACKUP_CONFIG:-/etc/oscar/usb-backup.env}
systemd_dir=${OSCAR_USB_SYSTEMD_DIR:-/etc/systemd/system}
udev_dir=${OSCAR_USB_UDEV_DIR:-/etc/udev/rules.d}
skip_systemd=${OSCAR_USB_BACKUP_SKIP_SYSTEMD:-0}
compose_project=${OSCAR_COMPOSE_PROJECT_NAME:-oscar}
state_volume=${OSCAR_STATE_VOLUME:-oscar_oscar_state}
postgres_volume=${OSCAR_POSTGRES_VOLUME:-oscar_postgres_data}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

heading() {
    printf '\n==> %s\n' "$*"
}

require_root() {
    if [[ ${OSCAR_USB_BACKUP_ALLOW_NONROOT:-0} == 1 ]]; then
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

usb_cfg_value() {
    local name=$1 default=${2:-}
    env_value "$name" "$default" "$config_file"
}

ejected_flag_file() {
    printf '%s/usb-backup.ejected' "$(dirname "$config_file")"
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

resolve_control_dir() {
    if [[ -n ${OSCAR_USB_CONTROL_DIR:-} ]]; then
        printf '%s' "$OSCAR_USB_CONTROL_DIR"
        return 0
    fi
    if command -v docker >/dev/null 2>&1 && docker volume inspect "$state_volume" >/dev/null 2>&1; then
        local mp
        mp=$(docker volume inspect --format '{{.Mountpoint}}' "$state_volume" 2>/dev/null || true)
        if [[ -n $mp && -d $mp ]]; then
            printf '%s/.moduledata/usb-backup-control' "$mp"
            return 0
        fi
    fi
    return 1
}

save_usb_config() {
    local mount_path=$1 mode=$2 interval=$3 fs_uuid=$4 fs_type=$5
    install -d -m 0700 "$(dirname "$config_file")"
    local tmp="$config_file.tmp.$$"
    cat >"$tmp" <<EOF
USB_BACKUP_MOUNT=$mount_path
USB_BACKUP_MODE=$mode
USB_BACKUP_INTERVAL_MINUTES=$interval
USB_BACKUP_FS_UUID=$fs_uuid
USB_BACKUP_FILESYSTEM=$fs_type
RELEASE_SCRIPT_DIR=$script_dir
EOF
    chmod 0600 "$tmp"
    mv -f -- "$tmp" "$config_file"
}

compose() {
    docker compose --project-name "$compose_project" --project-directory "$script_dir" \
        --env-file "$script_dir/.env" --file "$script_dir/compose.yaml" "$@"
}

oscar_version() {
    local v
    v=$(env_value OSCAR_VERSION '')
    [[ -n $v ]] || v=$(env_value OSCAR_VERSION 'local' "$script_dir/.env.example")
    printf '%s' "$v"
}

resolve_archive_dir() {
    local raw=${1:-$(env_value OSCAR_ARCHIVE_DIR '../oscar-storage/archive')}
    case $raw in
        /*) printf '%s' "$raw" ;;
        *) (mkdir -p "$script_dir/$raw" 2>/dev/null || true; cd "$script_dir" && realpath -m -- "$raw") ;;
    esac
}

ensure_backup_key() {
    local key_path=${1:-"$script_dir/secrets/backup-key.txt"}
    if [[ ! -f $key_path ]]; then
        install -d -m 0700 "$(dirname "$key_path")"
        openssl rand -base64 48 | tr -d '\n' >"$key_path"
        printf '\n' >>"$key_path"
        chmod 0600 "$key_path"
        printf 'Generated new AES-256/HMAC backup key at %s\n' "$key_path"
        printf 'IMPORTANT: Copy %s to secure off-host escrow (never store it solely on the USB backup drive).\n' "$key_path"
    fi
    printf '%s' "$key_path"
}

acquire_storage_lock() {
    local dep_id
    dep_id=$(env_value OSCAR_DEPLOYMENT_ID 'uninitialized')
    local lock_root=${OSCAR_STORAGE_LOCK_DIR:-/run/lock/oscar-storage}
    install -d -m 0700 "$lock_root"
    local lock_file="$lock_root/oscar-storage-${dep_id}.lock"
    exec 9>"$lock_file"
    if ! flock -w "${1:-60}" 9; then
        fail "Another OSCAR storage or backup operation is currently holding $lock_file."
    fi
}

is_drive_attached() {
    local mount_path=$1 fs_uuid=${2:-}
    [[ -n $mount_path && -d $mount_path ]] || return 1
    [[ ! -e "$mount_path/.oscar-unmounted-guard" ]] || return 1
    [[ ! -e "$mount_path/.oscar-ejected" ]] || return 1
    if [[ -n $fs_uuid ]] && command -v findmnt >/dev/null 2>&1; then
        findmnt -rn --target "$mount_path" >/dev/null 2>&1 || return 1
        local mounted_src
        mounted_src=$(findmnt -rn -o SOURCE --target "$mount_path" 2>/dev/null || true)
        local root_src
        root_src=$(findmnt -rn -o SOURCE --target / 2>/dev/null || true)
        [[ -n $mounted_src && $mounted_src != "$root_src" ]] || return 1
    fi
    [[ -f "$mount_path/OSCAR-Backup/.oscar-usb-backup-root" ]] || return 1
    return 0
}

configure_systemd_and_udev() {
    local mount_path=$1 mode=$2 interval=$3 fs_uuid=$4
    [[ $skip_systemd == 1 ]] && return 0
    command -v systemctl >/dev/null 2>&1 || return 0

    local svc="$systemd_dir/oscar-continual-backup.service"
    local tmr="$systemd_dir/oscar-continual-backup.timer"
    local hp_svc="$systemd_dir/oscar-usb-hotplug-catchup.service"
    local udev_rule="$udev_dir/99-oscar-usb-backup.rules"

    if [[ $mode == continual ]]; then
        cat >"$svc" <<EOF
[Unit]
Description=OSCAR Zero-Downtime Continual Incremental USB Backup Sync
After=docker.service local-fs.target
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash "$script_dir/oscar-usb-backup.sh" sync --if-attached
Nice=19
CPUSchedulingPolicy=batch
CPUQuota=100%
IOSchedulingClass=idle
EOF

        cat >"$tmr" <<EOF
[Unit]
Description=OSCAR Continual USB Backup Timer (every ${interval}m)

[Timer]
OnBootSec=2min
OnUnitActiveSec=${interval}min
Persistent=true

[Install]
WantedBy=timers.target
EOF

        cat >"$hp_svc" <<EOF
[Unit]
Description=OSCAR USB Backup Hotplug Auto-Mount & Catch-Up Sync
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash "$script_dir/oscar-usb-backup.sh" attach --quiet-if-busy
Nice=19
CPUSchedulingPolicy=batch
CPUQuota=100%
IOSchedulingClass=idle
EOF

        if [[ -n $fs_uuid ]]; then
            install -d -m 0755 "$udev_dir"
            cat >"$udev_rule" <<EOF
ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="$fs_uuid", TAG+="systemd", ENV{SYSTEMD_WANTS}+="oscar-usb-hotplug-catchup.service"
EOF
            udevadm control --reload-rules >/dev/null 2>&1 || true
        fi
        systemctl daemon-reload
        systemctl enable --now oscar-continual-backup.timer >/dev/null
    else
        systemctl disable --now oscar-continual-backup.timer >/dev/null 2>&1 || true
        rm -f -- "$udev_rule"
        udevadm control --reload-rules >/dev/null 2>&1 || true
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
}

disable_usb_autosuspend() {
    [[ $skip_systemd == 1 ]] && return 0
    # Prevent UAS multi-tag / UNMAP / U1-U2 LPM firmware lockups on Realtek RTL9210 (0bda:9210),
    # JMicron JMS583/562/578 (152d:0583/0562/0578), and ASMedia ASM2362 (174c:2362) USB 3.2 NVMe enclosures
    if [[ -d /etc/modprobe.d ]]; then
        cat >/etc/modprobe.d/oscar-usb-nvme-quirks.conf <<'EOF'
# Use rock-solid Bulk-Only Transport (BOT) and disable USB3 U1/U2 LPM on USB-to-NVMe
# bridge chips known to lock up under Linux UAS NCQ / UNMAP / LPM bursts
options usb-storage quirks=0bda:9210:u,152d:0583:u,174c:2362:u,152d:0562:u,152d:0578:u
options usbcore quirks=0bda:9210:k,152d:0583:k,174c:2362:k,152d:0562:k,152d:0578:k
EOF
    fi
    modprobe usb_storage 2>/dev/null || true
    if [[ -w /sys/module/usb_storage/parameters/quirks ]]; then
        echo "0bda:9210:u,152d:0583:u,174c:2362:u,152d:0562:u,152d:0578:u" >/sys/module/usb_storage/parameters/quirks 2>/dev/null || true
    fi
    if [[ -w /sys/module/usbcore/parameters/quirks ]]; then
        echo "0bda:9210:k,152d:0583:k,174c:2362:k,152d:0562:k,152d:0578:k" >/sys/module/usbcore/parameters/quirks 2>/dev/null || true
    fi
    if [[ -d $udev_dir ]]; then
        cat >"$udev_dir/98-oscar-usb-nosuspend.rules" <<'EOF'
# Prevent Linux USB autosuspend & cap USB-NVMe max_sectors_kb / UNMAP for sustained reliability
ACTION=="add", SUBSYSTEM=="usb", ATTR{bInterfaceClass}=="08", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="usb", DRIVERS=="uas|usb-storage", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z]", ENV{ID_BUS}=="usb", TEST=="queue/max_sectors_kb", ATTR{queue/max_sectors_kb}="1024"
ACTION=="add|change", SUBSYSTEM=="scsi_disk", DRIVERS=="sd", ENV{ID_BUS}=="usb", TEST=="provisioning_mode", ATTR{provisioning_mode}="disabled"
EOF
        udevadm control --reload-rules >/dev/null 2>&1 || true
    fi
    local ctrl blk pm
    for ctrl in /sys/bus/usb/devices/*/power/control; do
        [[ -w $ctrl ]] || continue
        echo on >"$ctrl" 2>/dev/null || true
    done
    for blk in /sys/block/sd*; do
        [[ -d $blk ]] || continue
        if readlink -f "$blk" 2>/dev/null | grep -q '/usb'; then
            [[ -w "$blk/queue/max_sectors_kb" ]] && echo 1024 >"$blk/queue/max_sectors_kb" 2>/dev/null || true
            for pm in "$blk"/device/scsi_disk/*/provisioning_mode; do
                [[ -w $pm ]] && echo disabled >"$pm" 2>/dev/null || true
            done
        fi
    done
}

protected_base_disks() {
    {
        local p src
        for p in / /boot /boot/efi /var "$script_dir" "$(resolve_archive_dir)"; do
            [[ -e $p ]] || continue
            src=$(findmnt -rn -o SOURCE --target "$p" 2>/dev/null || true)
            [[ $src == /dev/* ]] || continue
            printf '%s\n' "${src#/dev/}"
            lsblk -s -rno NAME "$src" 2>/dev/null || true
        done
    } | sort -u
}

cmd_list_drives() {
    heading 'Candidate External USB / Secondary Drives'
    local protected
    protected=$(protected_base_disks | tr '\n' ' ')
    printf 'Protected system/active devices (will NEVER be formatted): %s\n\n' "${protected:-none}"
    lsblk -o NAME,TRAN,RM,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT,MODEL -e 7
}

cmd_prepare_drive() {
    require_root
    [[ -f "$script_dir/.env" ]] || fail 'Initialize OSCAR first (`sudo bash oscar.sh init`) before preparing a backup drive.'
    local device='' adopt_uuid='' mount_path='/srv/oscar-usb-backup' path_only='' fs_type='ntfs'
    local mode='continual' interval=15 confirm='' skip_initial_sync=false no_format=false

    while (($#)); do
        case $1 in
            --device) device=${2:?missing --device}; shift 2 ;;
            --adopt-uuid) adopt_uuid=${2:?missing --adopt-uuid}; shift 2 ;;
            --no-format) no_format=true; shift ;;
            --mount) mount_path=${2:?missing --mount}; shift 2 ;;
            --path) path_only=${2:?missing --path}; shift 2 ;;
            --filesystem) fs_type=${2:?missing --filesystem}; shift 2 ;;
            --mode) mode=${2:?missing --mode}; shift 2 ;;
            --interval-minutes) interval=${2:?missing --interval-minutes}; shift 2 ;;
            --confirm) confirm=${2:?missing --confirm}; shift 2 ;;
            --skip-initial-sync) skip_initial_sync=true; shift ;;
            *) fail "Unknown prepare-drive option: $1" ;;
        esac
    done

    [[ $mode =~ ^(continual|occasional)$ ]] || fail '--mode must be continual or occasional.'
    [[ $interval =~ ^[0-9]+$ ]] && ((interval >= 5 && interval <= 1440)) || fail '--interval-minutes must be between 5 and 1440.'
    [[ $fs_type =~ ^(ntfs|ext4)$ ]] || fail '--filesystem must be ntfs (universal laptop-readable default) or ext4.'

    local archive_real
    archive_real=$(resolve_archive_dir)
    local fs_uuid='' actual_fs=$fs_type

    if [[ -n $adopt_uuid ]]; then
        [[ -z $device && -z $path_only ]] || fail 'Specify only one of --device, --adopt-uuid, or --path.'
        [[ $adopt_uuid =~ ^[A-Za-z0-9-]+$ ]] || fail "Invalid filesystem UUID: $adopt_uuid"
        fs_uuid=$adopt_uuid
        umount "$mount_path" 2>/dev/null || true
        install -d -m 0700 "$mount_path"
        printf 'OSCAR_UNMOUNTED_GUARD\n' >"$mount_path/.oscar-unmounted-guard"
        chmod 0400 "$mount_path/.oscar-unmounted-guard"
        sed -i "\|[[:space:]]$mount_path[[:space:]]|d" /etc/fstab
        sed -i "/UUID=$fs_uuid/d" /etc/fstab
        if [[ $fs_type == ntfs ]]; then
            local ntfs_driver=ntfs3
            modprobe ntfs3 2>/dev/null || ntfs_driver=ntfs
            printf 'UUID=%s\t%s\t%s\tuid=0,gid=0,umask=0077,nofail,x-systemd.device-timeout=5s\t0\t0\n' \
                "$fs_uuid" "$mount_path" "$ntfs_driver" >>/etc/fstab
        else
            printf 'UUID=%s\t%s\text4\tdefaults,nofail,noatime,x-systemd.device-timeout=5s\t0\t2\n' \
                "$fs_uuid" "$mount_path" >>/etc/fstab
        fi
        systemctl daemon-reload 2>/dev/null || true
        mount "$mount_path" 2>/dev/null || true
        disable_usb_autosuspend
        ensure_backup_key >/dev/null
        save_usb_config "$mount_path" "$mode" "$interval" "$fs_uuid" "$actual_fs"
        configure_systemd_and_udev "$mount_path" "$mode" "$interval" "$fs_uuid"
        if ! is_drive_attached "$mount_path" "$fs_uuid"; then
            printf 'Pre-registered USB backup carrier UUID=%s at %s (mode=%s, filesystem=%s — currently unplugged; ready for hotplug).\n' \
                "$fs_uuid" "$mount_path" "$mode" "$actual_fs"
            return 0
        fi
    elif [[ -n $device ]]; then
        [[ -z $path_only ]] || fail 'Specify either --device (for a physical USB SSD) or --path (for an already-mounted directory), not both.'
        [[ -b $device ]] || fail "Block device does not exist: $device"

        local dev_name=${device#/dev/} parent_disk
        parent_disk=$(lsblk -ndo PKNAME "$device" 2>/dev/null || true)
        local prot
        for prot in $(protected_base_disks); do
            if [[ $dev_name == "$prot" || $parent_disk == "$prot" ]]; then
                fail "Refusing to target protected OS/OSCAR disk: $device"
            fi
        done

        local part_dev=$device
        if [[ $no_format == false ]]; then
            [[ $confirm == FORMAT ]] || fail "Formatting $device erases all data on that USB drive. Re-run with --confirm FORMAT (or pass --no-format to adopt an already-formatted partition)."
            heading "Formatting USB NVMe SSD $device as $fs_type (label: OSCAR_BACKUP)"
            disable_usb_autosuspend
            umount "${device}"* 2>/dev/null || true
            wipefs -a "$device" >/dev/null 2>&1 || true
            if command -v parted >/dev/null 2>&1; then
                local parted_fs=ext4
                [[ $fs_type == ntfs ]] && parted_fs=ntfs
                parted -s "$device" mklabel gpt mkpart OSCAR_BACKUP "$parted_fs" 1MiB 100%
            elif [[ $fs_type == ntfs ]]; then
                printf 'label: gpt\nstart=2048, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name="OSCAR_BACKUP"\n' | sfdisk --quiet "$device"
            else
                printf 'label: gpt\nstart=2048, type=linux, name="OSCAR_BACKUP"\n' | sfdisk --quiet "$device"
            fi
            partprobe "$device" 2>/dev/null || true
            udevadm settle 2>/dev/null || sleep 2
            part_dev="${device}1"
            [[ $device =~ [0-9]$ ]] && part_dev="${device}p1"
            [[ -b $part_dev ]] || fail "Partition $part_dev did not appear after partitioning $device."
            umount "$part_dev" 2>/dev/null || true

            if [[ $fs_type == ntfs ]]; then
                command -v mkfs.ntfs >/dev/null 2>&1 || apt-get install -y --no-install-recommends ntfs-3g >/dev/null
                mkfs.ntfs -f -F -L OSCAR_BACKUP "$part_dev" >/dev/null
            else
                mkfs.ext4 -F -L OSCAR_BACKUP "$part_dev" >/dev/null
            fi
            udevadm settle 2>/dev/null || sleep 1
            umount "$part_dev" 2>/dev/null || true
        else
            if [[ $(lsblk -ndo TYPE "$device" 2>/dev/null || true) == disk ]]; then
                if [[ -b "${device}1" ]]; then
                    part_dev="${device}1"
                elif [[ -b "${device}p1" ]]; then
                    part_dev="${device}p1"
                fi
            fi
            umount "$part_dev" 2>/dev/null || true
            local detected_fs
            detected_fs=$(blkid -s TYPE -o value "$part_dev" 2>/dev/null | tr -d '[:space:]' || true)
            [[ $detected_fs =~ ^(ntfs|ext4)$ ]] || fail "Partition $part_dev has unsupported filesystem '${detected_fs:-none}'; expected ntfs or ext4."
            fs_type=$detected_fs
            actual_fs=$detected_fs
        fi
        fs_uuid=$(blkid -s UUID -o value "$part_dev" | tr -d '[:space:]')
        [[ -n $fs_uuid ]] || fail "Could not read filesystem UUID from $part_dev."

        # Place unmounted-root guard BEFORE mounting so OS root disk can never be filled when unplugged
        umount "$mount_path" 2>/dev/null || true
        install -d -m 0700 "$mount_path"
        printf 'OSCAR_UNMOUNTED_GUARD\n' >"$mount_path/.oscar-unmounted-guard"
        chmod 0400 "$mount_path/.oscar-unmounted-guard"

        # Register /etc/fstab with nofail so rebooting with USB unplugged NEVER hangs Ubuntu boot
        sed -i "\|[[:space:]]$mount_path[[:space:]]|d" /etc/fstab
        sed -i "/UUID=$fs_uuid/d" /etc/fstab
        if [[ $fs_type == ntfs ]]; then
            local ntfs_driver=ntfs3
            modprobe ntfs3 2>/dev/null || ntfs_driver=ntfs
            printf 'UUID=%s\t%s\t%s\tuid=0,gid=0,umask=0077,nofail,x-systemd.device-timeout=5s\t0\t0\n' \
                "$fs_uuid" "$mount_path" "$ntfs_driver" >>/etc/fstab
        else
            printf 'UUID=%s\t%s\text4\tdefaults,nofail,noatime,x-systemd.device-timeout=5s\t0\t2\n' \
                "$fs_uuid" "$mount_path" >>/etc/fstab
        fi
        systemctl daemon-reload 2>/dev/null || true
        mount "$mount_path"
        chmod 0700 "$mount_path" 2>/dev/null || true
        disable_usb_autosuspend
    else
        [[ -n $path_only ]] || fail 'Specify either --device /dev/sdX --confirm FORMAT (for a USB SSD) or --path /mounted/dir.'
        mkdir -p "$path_only"
        mount_path=$(realpath -- "$path_only")
        actual_fs='directory'
        if command -v findmnt >/dev/null 2>&1 && findmnt -rn -M "$mount_path" >/dev/null 2>&1; then
            local msrc
            msrc=$(findmnt -rn -M "$mount_path" -o SOURCE 2>/dev/null || true)
            if [[ $msrc == /dev/* ]]; then
                fs_uuid=$(blkid -s UUID -o value "$msrc" 2>/dev/null | tr -d '[:space:]' || true)
                actual_fs=$(findmnt -rn -M "$mount_path" -o FSTYPE 2>/dev/null || echo directory)
            fi
        fi
        disable_usb_autosuspend
    fi

    [[ $mount_path != "$script_dir"* && $mount_path != "$archive_real"* ]] ||
        fail "USB backup path ($mount_path) must not overlap the release directory or live archive directory."

    rm -f -- "$mount_path/.oscar-ejected" "$(ejected_flag_file)" 2>/dev/null || true
    mkdir -p "$mount_path/OSCAR-Backup/packs/archive" "$mount_path/OSCAR-Backup/packs/state" "$mount_path/OSCAR-Backup/snapshots"
    chmod 0700 "$mount_path/OSCAR-Backup" 2>/dev/null || true

    local dep_id host_name
    dep_id=$(env_value OSCAR_DEPLOYMENT_ID '')
    host_name=$(env_value OSCAR_HOSTNAME 'oscar.local')
    cat >"$mount_path/OSCAR-Backup/.oscar-usb-backup-root" <<EOF
format=oscar-usb-backup-root
version=1
deployment_id=$dep_id
hostname=$host_name
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

    ensure_backup_key >/dev/null
    local img="oscar:$(oscar_version)"
    docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --read-only --security-opt no-new-privileges \
        --tmpfs /tmp:rw,noexec,nosuid,nodev,size=64m \
        --user 0:0 --entrypoint bash \
        --volume "$engine_script:/engine.sh:ro" \
        --volume "$mount_path:/backup" \
        "$img" /engine.sh write-helpers /backup

    save_usb_config "$mount_path" "$mode" "$interval" "$fs_uuid" "$actual_fs"
    configure_systemd_and_udev "$mount_path" "$mode" "$interval" "$fs_uuid"

    printf 'Prepared OSCAR USB backup carrier at %s (mode=%s, filesystem=%s).\n' "$mount_path" "$mode" "$actual_fs"
    if [[ $skip_initial_sync == false ]]; then
        cmd_sync
    else
        write_agent_status_json >/dev/null 2>&1 || true
    fi
}

cmd_mode() {
    require_root
    [[ -f $config_file ]] || fail 'No USB backup drive is configured yet. Run `sudo bash oscar.sh usb-backup prepare-drive ...` first.'
    local new_mode=${1:-}
    shift || true
    [[ $new_mode =~ ^(continual|occasional|disabled)$ ]] ||
        fail 'Usage: oscar.sh usb-backup mode <continual|occasional|disabled> [--interval-minutes N]'

    local interval
    interval=$(usb_cfg_value USB_BACKUP_INTERVAL_MINUTES 15)
    while (($#)); do
        case $1 in
            --interval-minutes) interval=${2:?missing --interval-minutes}; shift 2 ;;
            *) fail "Unknown mode option: $1" ;;
        esac
    done
    [[ $interval =~ ^[0-9]+$ ]] && ((interval >= 5 && interval <= 1440)) || fail '--interval-minutes must be between 5 and 1440.'

    local mount_path fs_uuid fs_type
    mount_path=$(usb_cfg_value USB_BACKUP_MOUNT '')
    fs_uuid=$(usb_cfg_value USB_BACKUP_FS_UUID '')
    fs_type=$(usb_cfg_value USB_BACKUP_FILESYSTEM 'ntfs')

    save_usb_config "$mount_path" "$new_mode" "$interval" "$fs_uuid" "$fs_type"
    configure_systemd_and_udev "$mount_path" "$new_mode" "$interval" "$fs_uuid"

    case $new_mode in
        continual)
            printf 'Switched backup mode -> CONTINUAL (every %s minutes, zero portal downtime, auto-sync on USB reconnect).\n' "$interval"
            if is_drive_attached "$mount_path" "$fs_uuid"; then
                cmd_sync
            else
                write_agent_status_json >/dev/null 2>&1 || true
                printf 'Note: USB backup drive (%s) is currently unplugged. Sync will start automatically as soon as it is plugged in.\n' "$mount_path"
            fi
            ;;
        occasional)
            write_agent_status_json >/dev/null 2>&1 || true
            printf 'Switched backup mode -> OCCASIONAL (background timer disabled; run `sudo bash oscar.sh usb-backup sync` whenever you connect the drive).\n'
            ;;
        disabled)
            write_agent_status_json >/dev/null 2>&1 || true
            printf 'Switched backup mode -> DISABLED (background timer disabled; existing backup files on the USB drive were preserved).\n'
            ;;
    esac
}

cmd_sync() {
    require_root
    [[ -f $config_file ]] || fail 'No USB backup drive is configured yet. Run `sudo bash oscar.sh usb-backup prepare-drive ...` first.'
    local quiesce=false if_attached=false
    while (($#)); do
        case $1 in
            --quiesce) quiesce=true; shift ;;
            --if-attached) if_attached=true; shift ;;
            *) fail "Unknown sync option: $1" ;;
        esac
    done

    local mount_path mode fs_uuid ej_flag
    mount_path=$(usb_cfg_value USB_BACKUP_MOUNT '')
    mode=$(usb_cfg_value USB_BACKUP_MODE 'occasional')
    fs_uuid=$(usb_cfg_value USB_BACKUP_FS_UUID '')
    ej_flag=$(ejected_flag_file)

    if ! is_drive_attached "$mount_path" "$fs_uuid"; then
        if [[ -e $ej_flag ]]; then
            if [[ -n $fs_uuid ]] && ! blkid -U "$fs_uuid" >/dev/null 2>&1; then
                # Drive was physically removed after safe eject; re-arm auto-catch-up for next plug-in
                rm -f -- "$ej_flag" 2>/dev/null || true
            elif [[ $if_attached == true ]]; then
                printf 'USB backup drive (%s) is DETACHED (safely ejected and awaiting physical removal); skipping background timer mount.\n' "$mount_path"
                return 0
            fi
        fi
        # Attempt non-blocking fstab mount in case drive was just plugged in (unless awaiting physical removal)
        if [[ -n $fs_uuid && ! -e "$mount_path/.oscar-ejected" && ! -e $ej_flag ]]; then
            mount "$mount_path" 2>/dev/null || true
        fi
    fi

    if ! is_drive_attached "$mount_path" "$fs_uuid"; then
        if [[ $if_attached == true ]]; then
            printf 'USB backup drive (%s) is currently DETACHED; OSCAR continues recording on internal storage and will catch up automatically when reconnected.\n' "$mount_path"
            return 0
        fi
        fail "USB backup drive is not attached at $mount_path. Plug in the drive (or run \`sudo bash oscar.sh usb-backup attach\`)."
    fi

    acquire_storage_lock 120

    local dep_id root_dep_id ver img pg_img archive_real key_path
    dep_id=$(env_value OSCAR_DEPLOYMENT_ID '')
    root_dep_id=$(awk -F= '$1 == "deployment_id" { print $2; exit }' "$mount_path/OSCAR-Backup/.oscar-usb-backup-root" | tr -d '\r')
    [[ $dep_id == "$root_dep_id" ]] ||
        fail "USB backup drive belongs to deployment $root_dep_id, not active deployment $dep_id."

    ver=$(oscar_version)
    img="oscar:$ver"
    pg_img="oscar-postgis:$ver"
    archive_real=$(resolve_archive_dir)
    key_path=$(ensure_backup_key)

    compose ps --status running --services | grep -Fxq postgres ||
        fail 'PostgreSQL container must be running to capture an online backup.'

    local resume_gateway=false resume_oscar=false
    cleanup_quiesce() {
        local rc=$?
        if [[ ${resume_oscar:-false} == true || ${resume_gateway:-false} == true ]]; then
            local -a svcs=()
            [[ ${resume_oscar:-false} == true ]] && svcs+=(oscar)
            [[ ${resume_gateway:-false} == true ]] && svcs+=(gateway)
            compose up --detach --no-build --pull never --wait --wait-timeout 240 "${svcs[@]}" >/dev/null 2>&1 || true
        fi
        return "$rc"
    }
    trap cleanup_quiesce EXIT

    if [[ $quiesce == true ]]; then
        compose ps --status running --services | grep -Fxq gateway && resume_gateway=true || true
        compose ps --status running --services | grep -Fxq oscar && resume_oscar=true || true
        $resume_gateway && compose stop gateway >/dev/null
        $resume_oscar && compose stop oscar >/dev/null
    fi

    local ts ts_iso rand snap_id work pg_cid lsn epoch_id
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    ts_iso="${ts:0:4}-${ts:4:2}-${ts:6:2}T${ts:9:2}:${ts:11:2}:${ts:13:2}Z"
    rand=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')
    snap_id="${ts}-${rand}"
    work="$mount_path/OSCAR-Backup/snapshots/$snap_id.partial"
    rm -rf -- "$work"
    mkdir -p "$work"

    heading "Syncing incremental backup snapshot $snap_id (quiesce=$quiesce)"
    pg_cid=$(compose ps --quiet postgres | tr -d '[:space:]')
    [[ -n $pg_cid ]] || fail 'Could not resolve running PostgreSQL container ID.'

    # Query current LSN & UUID and stream online self-contained pg_basebackup (zero portal downtime!)
    local meta_line
    meta_line=$(docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network "container:$pg_cid" --read-only --cap-drop ALL \
        --security-opt no-new-privileges --user 999:999 --entrypoint sh \
        --volume "$script_dir/secrets/postgres-bootstrap-password.txt:/run/secrets/pg_pass:ro" \
        "$pg_img" -eu -c '
        PGPASSWORD=$(cat /run/secrets/pg_pass)
        export PGPASSWORD
        psql "host=127.0.0.1 port=5432 user=oscar_bootstrap dbname=gis" --tuples-only --no-align \
            --command "SELECT pg_current_wal_lsn()::text || '\''|'\'' || gen_random_uuid()::text;"
    ' | tr -d '[:space:]')
    lsn=${meta_line%%|*}
    epoch_id=${meta_line#*|}

    local pg_stage_vol="oscar_usb_pgstage_${rand}"
    docker volume create "$pg_stage_vol" >/dev/null
    docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --user 0:0 --entrypoint sh \
        --volume "${pg_stage_vol}:/pgbackup" "$pg_img" -eu -c 'rm -rf /pgbackup/* && chown 999:999 /pgbackup && chmod 0700 /pgbackup'
    docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network "container:$pg_cid" --read-only --cap-drop ALL \
        --cpus=1 --cpu-shares=128 \
        --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,nodev \
        --user 999:999 --entrypoint sh \
        --volume "${pg_stage_vol}:/pgbackup" \
        --volume "$script_dir/secrets/postgres-bootstrap-password.txt:/run/secrets/pg_pass:ro" \
        "$pg_img" -eu -c '
        PGPASSWORD=$(cat /run/secrets/pg_pass)
        export PGPASSWORD
        exec pg_basebackup --pgdata=/pgbackup --username=oscar_bootstrap \
            --dbname="host=127.0.0.1 port=5432 dbname=gis" --format=plain \
            --wal-method=stream --checkpoint=fast
    '
    # Verify PostgreSQL base backup integrity immediately while in volume staging
    docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --read-only --cap-drop ALL --cap-add DAC_READ_SEARCH \
        --cpus=1 --cpu-shares=128 \
        --security-opt no-new-privileges --user 999:999 --entrypoint pg_verifybackup \
        --volume "${pg_stage_vol}:/pgbackup:ro" \
        "$pg_img" --quiet /pgbackup
    docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --read-only --security-opt no-new-privileges \
        --cpus=1 --cpu-shares=128 \
        --user 0:0 --entrypoint sh \
        --volume "${pg_stage_vol}:/pgbackup:ro" \
        --volume "$mount_path:/backup" \
        "$img" -eu -c "mkdir -p '/backup/OSCAR-Backup/snapshots/$snap_id.partial' && tar -C /pgbackup -cf '/backup/OSCAR-Backup/snapshots/$snap_id.partial/postgres.tar' . && chmod -R a+rX '/backup/OSCAR-Backup'"
    docker volume rm -f "$pg_stage_vol" >/dev/null 2>&1 || true

    local -a extra_vols=()
    local ra_dir="$(dirname "$archive_real")/remote-access"
    if [[ -d $ra_dir && -f "$ra_dir/octelium.env" && ! -L "$ra_dir/octelium.env" ]]; then
        extra_vols+=(--volume "$ra_dir:/remote-access-src:ro")
    fi

    local sync_scratch
    sync_scratch=$(mktemp -d "${TMPDIR:-/var/tmp}/oscar-usb-sync-scratch.XXXXXX")
    chmod 0700 "$sync_scratch"

    docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --read-only --security-opt no-new-privileges \
        --cpus=1 --cpu-shares=128 \
        --tmpfs /tmp:rw,noexec,nosuid,nodev,size=1024m \
        --env OSCAR_USB_ENGINE_SCRATCH=/scratch \
        --user 0:0 --entrypoint bash \
        --volume "$engine_script:/engine.sh:ro" \
        --volume "$sync_scratch:/scratch" \
        --volume "${state_volume}:/state:ro" \
        --volume "$archive_real:/archive:ro" \
        --volume "$script_dir:/deployment:ro" \
        --volume "$key_path:/backup-key.txt:ro" \
        --volume "$mount_path:/backup" \
        "${extra_vols[@]}" \
        "$img" /engine.sh pack-sync "$snap_id" "$dep_id" "$ver" "$mode" "$lsn" "$epoch_id" "$ts_iso" || {
        local sync_rc=$?
        rm -rf -- "$sync_scratch"
        exit "$sync_rc"
    }
    rm -rf -- "$sync_scratch"

    mv -- "$work" "$mount_path/OSCAR-Backup/snapshots/$snap_id"

    docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --read-only --security-opt no-new-privileges \
        --cpus=1 --cpu-shares=128 \
        --tmpfs /tmp:rw,noexec,nosuid,nodev,size=256m \
        --user 0:0 --entrypoint bash \
        --volume "$engine_script:/engine.sh:ro" \
        --volume "$key_path:/backup-key.txt:ro" \
        --volume "$mount_path:/backup" \
        "$img" /engine.sh commit-latest "$snap_id" "$ts_iso"

    # Verify committed snapshot HMAC + manifest digests
    docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --read-only --security-opt no-new-privileges \
        --cpus=1 --cpu-shares=128 \
        --tmpfs /tmp:rw,noexec,nosuid,nodev,size=512m \
        --user 0:0 --entrypoint bash \
        --volume "$engine_script:/engine.sh:ro" \
        --volume "$key_path:/backup-key.txt:ro" \
        --volume "$mount_path:/backup:ro" \
        "$img" /engine.sh verify-snapshot false >/dev/null

    if $resume_oscar || $resume_gateway; then
        local -a svcs=()
        $resume_oscar && svcs+=(oscar)
        $resume_gateway && svcs+=(gateway)
        compose up --detach --no-build --pull never --wait --wait-timeout 240 "${svcs[@]}"
        resume_oscar=false
        resume_gateway=false
    fi
    trap - EXIT
    write_agent_status_json >/dev/null 2>&1 || true
    printf 'Incremental backup sync COMPLETE: snapshot=%s (portal downtime: %s)\n' \
        "$snap_id" "$(if $quiesce; then echo 'brief quiesce'; else echo '0s — remained online'; fi)"
}

cmd_eject() {
    require_root
    [[ -f $config_file ]] || fail 'No USB backup drive is configured.'
    local no_sync=false
    while (($#)); do
        case $1 in
            --no-sync) no_sync=true; shift ;;
            *) fail "Unknown eject option: $1" ;;
        esac
    done

    local mount_path fs_uuid fs_type
    mount_path=$(usb_cfg_value USB_BACKUP_MOUNT '')
    fs_uuid=$(usb_cfg_value USB_BACKUP_FS_UUID '')
    fs_type=$(usb_cfg_value USB_BACKUP_FILESYSTEM 'ntfs')

    if ! is_drive_attached "$mount_path" "$fs_uuid"; then
        install -d -m 0700 "$(dirname "$config_file")" 2>/dev/null || true
        printf 'ejected_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$(ejected_flag_file)" 2>/dev/null || true
        write_agent_status_json >/dev/null 2>&1 || true
        printf 'USB backup drive (%s) is already unmounted / detached. Safe to unplug.\n' "$mount_path"
        return 0
    fi

    if [[ $no_sync == false ]]; then
        heading 'Running final delta sync before safe USB eject'
        cmd_sync
    fi

    acquire_storage_lock 120
    sync
    if [[ -n $fs_uuid ]] || (command -v findmnt >/dev/null 2>&1 && findmnt -rn -M "$mount_path" >/dev/null 2>&1); then
        umount "$mount_path"
    else
        printf 'ejected_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$mount_path/.oscar-ejected"
    fi
    install -d -m 0700 "$(dirname "$config_file")" 2>/dev/null || true
    printf 'ejected_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$(ejected_flag_file)"
    sync
    write_agent_status_json >/dev/null 2>&1 || true
    cat <<EOF

================================================================================
SAFE TO UNPLUG: $mount_path has been flushed and cleanly unmounted.
- OSCAR remains 100% online and continues recording on internal NVMe storage.
- Plug the USB NVMe SSD into your laptop and run COPY-TO-ANOTHER-DRIVE.bat
  (Windows) or ./copy-to-another-drive.sh (macOS/Linux) to copy new packs.
- When finished, plug the USB NVMe SSD back into the OSCAR USB 3.x port; OSCAR
  will automatically pull in all data recorded while the drive was away.
================================================================================
EOF
}

cmd_attach() {
    require_root
    [[ -f $config_file ]] || fail 'No USB backup drive is configured.'
    local quiet_if_busy=false
    while (($#)); do
        case $1 in
            --quiet-if-busy) quiet_if_busy=true; shift ;;
            *) fail "Unknown attach option: $1" ;;
        esac
    done

    local mount_path fs_uuid
    mount_path=$(usb_cfg_value USB_BACKUP_MOUNT '')
    fs_uuid=$(usb_cfg_value USB_BACKUP_FS_UUID '')

    rm -f -- "$mount_path/.oscar-ejected" "$(ejected_flag_file)" 2>/dev/null || true
    if [[ -n $fs_uuid ]] && ! findmnt -rn -M "$mount_path" >/dev/null 2>&1; then
        mount "$mount_path" || {
            [[ $quiet_if_busy == true ]] && exit 0
            fail "Could not mount USB backup drive at $mount_path (check USB cable / lsblk)."
        }
    fi
    is_drive_attached "$mount_path" "$fs_uuid" ||
        fail "Drive at $mount_path does not contain a valid OSCAR-Backup/.oscar-usb-backup-root marker."

    heading 'USB backup drive attached — pulling in all data recorded while disconnected'
    cmd_sync
}

cmd_status() {
    heading 'OSCAR Continual / USB NVMe Backup Status'
    if [[ ! -f $config_file ]]; then
        printf 'Status: UNCONFIGURED (run `sudo bash oscar.sh usb-backup prepare-drive ...` to set up)\n'
        return 0
    fi
    local mount_path mode interval fs_uuid fs_type
    mount_path=$(usb_cfg_value USB_BACKUP_MOUNT '')
    mode=$(usb_cfg_value USB_BACKUP_MODE 'disabled')
    interval=$(usb_cfg_value USB_BACKUP_INTERVAL_MINUTES '15')
    fs_uuid=$(usb_cfg_value USB_BACKUP_FS_UUID '')
    fs_type=$(usb_cfg_value USB_BACKUP_FILESYSTEM 'ntfs')

    printf 'Configured Mode:       %s' "$mode"
    [[ $mode == continual ]] && printf ' (every %s min + USB hotplug auto-catch-up)' "$interval"
    printf '\n'
    printf 'Mount / Target Path:   %s (filesystem=%s%s)\n' "$mount_path" "$fs_type" "${fs_uuid:+, uuid=$fs_uuid}"

    if command -v systemctl >/dev/null 2>&1 && [[ $skip_systemd != 1 ]]; then
        local tmr_state
        tmr_state=$(systemctl is-active oscar-continual-backup.timer 2>/dev/null || echo inactive)
        printf 'Systemd Timer State:   %s\n' "$tmr_state"
    fi

    if is_drive_attached "$mount_path" "$fs_uuid"; then
        local free_human used_human
        free_human=$(df -h "$mount_path" | awk 'NR==2 {print $4}')
        used_human=$(du -sh "$mount_path/OSCAR-Backup" 2>/dev/null | awk '{print $1}' || echo unknown)
        printf 'Drive State:           ATTACHED (%s used by OSCAR-Backup, %s free on drive)\n' "$used_human" "$free_human"
        if [[ -f "$mount_path/OSCAR-Backup/LATEST" ]]; then
            local snap_id snap_dir
            snap_id=$(awk -F= '$1 == "snapshot_id" { print $2; exit }' "$mount_path/OSCAR-Backup/LATEST" | tr -d '\r')
            snap_dir="$mount_path/OSCAR-Backup/snapshots/$snap_id"
            printf 'Latest Verified Point: %s\n' "$snap_id"
            if [[ -f "$snap_dir/epoch.json" ]]; then
                awk -F'"' '
                    /"createdAt"/ { printf "Snapshot UTC Time:     %s\n", $4 }
                    /"postgresLsn"/ { printf "PostgreSQL LSN:        %s\n", $4 }
                ' "$snap_dir/epoch.json"
                awk -F': ' '
                    /"archivePackCount"/ { gsub(/[, ]/, "", $2); printf "Sealed Archive Packs:  %s\n", $2 }
                    /"statePackCount"/   { gsub(/[, ]/, "", $2); printf "State Media/CSV Packs: %s\n", $2 }
                    /"immutableStateFileCount"/ { gsub(/[, }]/, "", $2); printf "Tracked Media/CSV Files: %s\n", $2 }
                ' "$snap_dir/epoch.json"
            fi
        else
            printf 'Latest Verified Point: NONE (run `sudo bash oscar.sh usb-backup sync`)\n'
        fi
    else
        printf 'Drive State:           DETACHED / UNPLUGGED (OSCAR continues recording normally; plug drive back in to auto-catch-up)\n'
    fi
}

cmd_verify() {
    require_root
    disable_usb_autosuspend
    local from_path='' key_path='' deep=false
    while (($#)); do
        case $1 in
            --from) from_path=${2:?missing --from}; shift 2 ;;
            --backup-key) key_path=${2:?missing --backup-key}; shift 2 ;;
            --deep) deep=true; shift ;;
            *) fail "Unknown verify option: $1" ;;
        esac
    done
    [[ -n $from_path ]] || from_path=$(usb_cfg_value USB_BACKUP_MOUNT '')
    [[ -n $from_path && -d "$from_path/OSCAR-Backup" ]] || fail "OSCAR-Backup directory not found under: ${from_path:-<unspecified>}"
    [[ -n $key_path ]] || key_path="$script_dir/secrets/backup-key.txt"
    [[ -f $key_path ]] || fail "Backup key file not found: $key_path"

    local ver img pg_img snap_id
    ver=$(oscar_version)
    img="oscar:$ver"
    pg_img="oscar-postgis:$ver"

    snap_id=$(docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --read-only --security-opt no-new-privileges \
        --tmpfs /tmp:rw,noexec,nosuid,nodev,size=512m \
        --user 0:0 --entrypoint bash \
        --volume "$engine_script:/engine.sh:ro" \
        --volume "$(realpath -- "$key_path"):/backup-key.txt:ro" \
        --volume "$(realpath -- "$from_path"):/backup:ro" \
        "$img" /engine.sh verify-snapshot "$deep" | tr -d '[:space:]')

    local pg_verify_vol="oscar_usb_pgverify_${snap_id//[^a-zA-Z0-9]/}"
    docker volume create "$pg_verify_vol" >/dev/null
    docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --read-only --security-opt no-new-privileges \
        --user 0:0 --entrypoint sh \
        --volume "$(realpath -- "$from_path"):/backup:ro" \
        --volume "${pg_verify_vol}:/pgbackup" \
        "$img" -eu -c "tar -C /pgbackup --no-same-owner -xf '/backup/OSCAR-Backup/snapshots/$snap_id/postgres.tar' && chown -R 999:999 /pgbackup"
    docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --read-only --cap-drop ALL --cap-add DAC_READ_SEARCH \
        --security-opt no-new-privileges --user 999:999 --entrypoint pg_verifybackup \
        --volume "${pg_verify_vol}:/pgbackup:ro" \
        "$pg_img" --quiet /pgbackup
    docker volume rm -f "$pg_verify_vol" >/dev/null 2>&1 || true

    printf 'VERIFIED OK: USB incremental backup snapshot %s (HMAC, SHA-256 manifests, packs, secrets, and pg_verifybackup all valid).\n' "$snap_id"
}

cmd_restore() {
    require_root
    disable_usb_autosuspend
    local from_path='' key_path='' target_archive='' confirm=''
    while (($#)); do
        case $1 in
            --from) from_path=${2:?missing --from}; shift 2 ;;
            --backup-key) key_path=${2:?missing --backup-key}; shift 2 ;;
            --archive-dir) target_archive=${2:?missing --archive-dir}; shift 2 ;;
            --confirm) confirm=${2:?missing --confirm}; shift 2 ;;
            *) fail "Unknown restore option: $1" ;;
        esac
    done
    [[ $confirm == RESTORE ]] || fail 'Restore overwrites target PostgreSQL, state, archive, and credentials. Re-run with --confirm RESTORE'
    [[ -n $from_path ]] || from_path=$(usb_cfg_value USB_BACKUP_MOUNT '')
    [[ -n $from_path && -d "$from_path/OSCAR-Backup" ]] || fail "OSCAR-Backup directory not found under: ${from_path:-<unspecified>}"
    from_path=$(realpath -- "$from_path")
    [[ -n $key_path ]] || key_path="$script_dir/secrets/backup-key.txt"
    [[ -f $key_path ]] || fail "Backup key file not found: $key_path (supply --backup-key /path/to/backup-key.txt)"
    key_path=$(realpath -- "$key_path")

    # If this is a brand-new air-gapped machine with offline-images.tar, load images automatically if needed
    local ver
    ver=$(oscar_version)
    if ! docker image inspect "oscar:$ver" >/dev/null 2>&1 && [[ -f "$script_dir/offline-images.tar" ]]; then
        heading 'Loading offline container images on replacement host'
        docker load --input "$script_dir/offline-images.tar" >/dev/null
    fi
    docker image inspect "oscar:$ver" >/dev/null 2>&1 ||
        fail "Required image oscar:$ver is not loaded. Run \`sudo bash oscar.sh prepare-host --offline\` or build/load images first."
    docker image inspect "oscar-postgis:$ver" >/dev/null 2>&1 ||
        fail "Required image oscar-postgis:$ver is not loaded."

    heading 'Step 1/5 — Deep-verifying USB backup cryptographic HMAC, packs & PostgreSQL base backup'
    cmd_verify --from "$from_path" --backup-key "$key_path" --deep

    local snap_id
    snap_id=$(awk -F= '$1 == "snapshot_id" { print $2; exit }' "$from_path/OSCAR-Backup/LATEST" | tr -d '\r')
    local snap_dir="$from_path/OSCAR-Backup/snapshots/$snap_id"

    RESTORE_CREDS_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/oscar-usb-creds.XXXXXX")
    chmod 0700 "$RESTORE_CREDS_STAGE"
    trap 'rm -rf -- "${RESTORE_CREDS_STAGE:-}"' EXIT HUP INT TERM
    local creds_stage=$RESTORE_CREDS_STAGE

    docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --read-only --security-opt no-new-privileges \
        --tmpfs /tmp:rw,noexec,nosuid,nodev,size=64m \
        --user "$(id -u):$(id -g)" --entrypoint bash \
        --volume "$engine_script:/engine.sh:ro" \
        --volume "$key_path:/backup-key.txt:ro" \
        --volume "$from_path:/backup:ro" \
        --volume "$creds_stage:/restore-creds" \
        "oscar:$ver" /engine.sh decrypt-credentials "$snap_id"

    local restored_dep_id
    restored_dep_id=$(env_value OSCAR_DEPLOYMENT_ID '' "$creds_stage/.env")
    [[ -n $restored_dep_id ]] || fail 'Restored .env does not contain a valid OSCAR_DEPLOYMENT_ID.'

    # Preserve pre-existing credentials if restoring over an initialized host
    if [[ -f "$script_dir/.env" ]]; then
        compose stop gateway oscar postgres >/dev/null 2>&1 || true
        local safety="$script_dir/pre-restore-usb-$snap_id"
        mkdir -p "$safety"
        chmod 0700 "$safety"
        cp -a "$script_dir/.env" "$safety/" 2>/dev/null || true
        [[ -d "$script_dir/secrets" ]] && cp -a "$script_dir/secrets" "$safety/" || true
        [[ -d "$script_dir/tls" ]] && cp -a "$script_dir/tls" "$safety/" || true
    fi

    heading 'Step 2/5 — Installing restored credentials, storage roots & deployment-labeled volumes'
    if [[ -z $target_archive ]]; then
        if [[ -f "$script_dir/.env" ]]; then
            target_archive=$(resolve_archive_dir)
        else
            target_archive=$(resolve_archive_dir '../oscar-storage/archive')
        fi
    else
        target_archive=$(realpath -m -- "$target_archive")
    fi

    # Update OSCAR_ARCHIVE_DIR and OSCAR_VERSION in restored .env for the target machine
    awk -F= -v arch="$target_archive" -v v="$ver" '
        $1 == "OSCAR_ARCHIVE_DIR" { print "OSCAR_ARCHIVE_DIR=" arch; next }
        $1 == "OSCAR_VERSION"     { print "OSCAR_VERSION=" v; next }
        $1 == "OSCAR_BACKUP_MODE" { print "OSCAR_BACKUP_MODE=disabled"; next }
        $1 == "OSCAR_BACKUP_DIR"  { next }
        $1 == "OSCAR_WAL_ARCHIVE_DIR" { next }
        { print }
    ' "$creds_stage/.env" >"$creds_stage/.env.normalized"
    mv -f -- "$creds_stage/.env.normalized" "$creds_stage/.env"

    rm -rf -- "$script_dir/secrets" "$script_dir/tls"
    cp -f -- "$creds_stage/.env" "$script_dir/.env"
    cp -a -- "$creds_stage/secrets" "$script_dir/secrets"
    cp -a -- "$creds_stage/tls" "$script_dir/tls"
    chmod 0700 "$script_dir/secrets" "$script_dir/tls"
    chmod 0644 "$script_dir"/secrets/*.txt "$script_dir/tls/server.crt" "$script_dir/tls/server.key"
    [[ -f "$script_dir/secrets/backup-key.txt" ]] && chmod 0600 "$script_dir/secrets/backup-key.txt" || true
    chmod 0600 "$script_dir/.env"

    if [[ -d "$creds_stage/remote-access" && -f "$creds_stage/remote-access/octelium.env" ]]; then
        local target_ra_dir="$(dirname "$target_archive")/remote-access"
        install -d -m 0700 "$target_ra_dir"
        if [[ -f "$creds_stage/remote-access/octelium-token.txt" ]]; then
            cp -f "$creds_stage/remote-access/octelium-token.txt" "$target_ra_dir/octelium-token.txt"
            chown 10002:10002 "$target_ra_dir/octelium-token.txt" 2>/dev/null || chmod 0644 "$target_ra_dir/octelium-token.txt"
            chmod 0400 "$target_ra_dir/octelium-token.txt" 2>/dev/null || true
        fi
        awk -F= -v tok="$target_ra_dir/octelium-token.txt" '
            $1 == "OCTELIUM_TOKEN_FILE" { print "OCTELIUM_TOKEN_FILE=" tok; next }
            { print }
        ' "$creds_stage/remote-access/octelium.env" >"$target_ra_dir/octelium.env"
        chmod 0600 "$target_ra_dir/octelium.env"
    fi

    # Ensure external volumes exist with exact deployment_id label
    local vol existing_lbl
    for vol in "$state_volume" "$postgres_volume"; do
        if docker volume inspect "$vol" >/dev/null 2>&1; then
            existing_lbl=$(docker volume inspect --format '{{ index .Labels "com.botts.oscar.deployment-id" }}' "$vol" 2>/dev/null || true)
            if [[ $existing_lbl != "$restored_dep_id" ]]; then
                docker volume rm -f "$vol" >/dev/null
                docker volume create --label "com.botts.oscar.deployment-id=$restored_dep_id" "$vol" >/dev/null
            fi
        else
            docker volume create --label "com.botts.oscar.deployment-id=$restored_dep_id" "$vol" >/dev/null
        fi
    done

    install -d -o 0 -g 10001 -m 1770 "$target_archive" 2>/dev/null || mkdir -p "$target_archive"
    cat >"$target_archive/.oscar-storage-root" <<EOF
format=oscar-storage-root
version=1
root_kind=archive
deployment_id=$restored_dep_id
origin=created
EOF
    chown 0:0 "$target_archive/.oscar-storage-root" 2>/dev/null || true
    chmod 0600 "$target_archive/.oscar-storage-root"

    heading 'Step 3/5 — Extracting cold Parquet archive packs & OSCAR application state'
    local restore_scratch
    restore_scratch=$(mktemp -d "${TMPDIR:-/var/tmp}/oscar-usb-restore-scratch.XXXXXX")
    chmod 0700 "$restore_scratch"
    docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --read-only --security-opt no-new-privileges \
        --tmpfs /tmp:rw,noexec,nosuid,nodev,size=1024m \
        --env OSCAR_USB_ENGINE_SCRATCH=/scratch \
        --user 0:0 --entrypoint bash \
        --volume "$engine_script:/engine.sh:ro" \
        --volume "$restore_scratch:/scratch" \
        --volume "$from_path:/backup:ro" \
        --volume "${state_volume}:/state" \
        --volume "$target_archive:/archive" \
        "oscar:$ver" /engine.sh extract-restore "$snap_id" || {
        local restore_rc=$?
        rm -rf -- "$restore_scratch"
        exit "$restore_rc"
    }
    rm -rf -- "$restore_scratch"

    heading 'Step 4/5 — Restoring PostgreSQL cluster & promoting onto clean timeline'
    docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --read-only --security-opt no-new-privileges \
        --user 0:0 --entrypoint sh \
        --volume "$from_path:/backup:ro" \
        --volume "${postgres_volume}:/data" \
        "oscar:$ver" -eu -c "find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /data --no-same-owner -xf '/backup/OSCAR-Backup/snapshots/$snap_id/postgres.tar' && chown -R 999:999 /data && chmod 0700 /data"
    local src_tl
    src_tl=$(docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
        --user 999:999 --entrypoint /usr/local/bin/oscar-prepare-restore \
        --volume "${postgres_volume}:/data" \
        "oscar-postgis:$ver" /data | tr -d '[:space:]')
    [[ $src_tl =~ ^[1-9][0-9]*$ ]] || fail "Invalid source PostgreSQL timeline: $src_tl"

    compose up --detach --no-deps --no-build --pull never --wait --wait-timeout 300 postgres
    local pg_cid
    pg_cid=$(compose ps --quiet postgres | tr -d '[:space:]')
    docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network "container:$pg_cid" --read-only --cap-drop ALL \
        --security-opt no-new-privileges --user 999:999 --entrypoint sh \
        --volume "$script_dir/secrets/postgres-bootstrap-password.txt:/run/secrets/pg_pass:ro" \
        "oscar-postgis:$ver" -eu -c '
        PGPASSWORD=$(cat /run/secrets/pg_pass)
        export PGPASSWORD
        for s in restore_command recovery_target recovery_target_timeline recovery_target_action; do
            psql "host=127.0.0.1 port=5432 user=oscar_bootstrap dbname=gis" -q -c "ALTER SYSTEM RESET $s;"
        done
        psql "host=127.0.0.1 port=5432 user=oscar_bootstrap dbname=gis" -q -c "CHECKPOINT; SELECT pg_reload_conf();"
    ' >/dev/null
    compose stop postgres >/dev/null
    compose up --detach --no-deps --no-build --pull never --wait --wait-timeout 300 postgres

    if [[ ${OSCAR_USB_RESTORE_POSTGRES_ONLY:-0} != 1 ]]; then
        heading 'Step 5/5 — Starting OSCAR application & HTTPS gateway'
        compose up --detach --no-deps --no-build --pull never --wait --wait-timeout 300 oscar gateway
        if [[ -f "$script_dir/oscar-remote-access.sh" && -d "$(dirname "$target_archive")/remote-access" ]]; then
            bash "$script_dir/oscar-remote-access.sh" sync || true
        fi
    fi

    rm -rf -- "${RESTORE_CREDS_STAGE:-}"
    trap - EXIT
    printf '\nRESTORE COMPLETE: Snapshot %s is now live on https://%s:%s/\n' \
        "$snap_id" "$(env_value OSCAR_HOSTNAME oscar.local)" "$(env_value OSCAR_HTTPS_PORT 443)"
}

json_req_field() {
    local file=$1 key=$2
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$file" "$key" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as fh:
        data = json.load(fh)
    val = data.get(sys.argv[2], '')
    if isinstance(val, bool):
        print('true' if val else 'false')
    elif val is None:
        print('')
    else:
        print(str(val))
except Exception:
    pass
PY
        return 0
    fi
    sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p; s/.*\"$key\"[[:space:]]*:[[:space:]]*\(true\|false\|[0-9][0-9]*\).*/\1/p" "$file" | head -n 1
}

collect_candidate_drives_json() {
    local configured_uuid=${1:-}
    local -A prot_map=()
    local p
    for p in $(protected_base_disks); do
        [[ -n $p ]] && prot_map[$p]=1
    done

    local lsblk_raw
    lsblk_raw=$(lsblk -P -b -o NAME,PKNAME,PATH,TYPE,TRAN,RM,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT,MODEL -e 7 2>/dev/null || true)
    [[ -n $lsblk_raw ]] || { printf '[]'; return 0; }

    local -a disk_names=()
    local -A d_path=() d_tran=() d_rm=() d_size=() d_model=()
    local -A p_path=() p_fstype=() p_label=() p_uuid=() p_mnt=()

    local line NAME PKNAME PATH_VAL TYPE TRAN RM SIZE FSTYPE LABEL UUID MOUNTPOINT MODEL
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        NAME=$(sed -n 's/.*\<NAME="\([^"]*\)".*/\1/p' <<<"$line")
        PKNAME=$(sed -n 's/.*\<PKNAME="\([^"]*\)".*/\1/p' <<<"$line")
        PATH_VAL=$(sed -n 's/.*\<PATH="\([^"]*\)".*/\1/p' <<<"$line")
        TYPE=$(sed -n 's/.*\<TYPE="\([^"]*\)".*/\1/p' <<<"$line")
        TRAN=$(sed -n 's/.*\<TRAN="\([^"]*\)".*/\1/p' <<<"$line")
        RM=$(sed -n 's/.*\<RM="\([^"]*\)".*/\1/p' <<<"$line")
        SIZE=$(sed -n 's/.*\<SIZE="\([^"]*\)".*/\1/p' <<<"$line")
        FSTYPE=$(sed -n 's/.*\<FSTYPE="\([^"]*\)".*/\1/p' <<<"$line")
        LABEL=$(sed -n 's/.*\<LABEL="\([^"]*\)".*/\1/p' <<<"$line")
        UUID=$(sed -n 's/.*\<UUID="\([^"]*\)".*/\1/p' <<<"$line")
        MOUNTPOINT=$(sed -n 's/.*\<MOUNTPOINT="\([^"]*\)".*/\1/p' <<<"$line")
        MODEL=$(sed -n 's/.*\<MODEL="\([^"]*\)".*/\1/p' <<<"$line")

        if [[ $TYPE == disk ]]; then
            [[ -n ${prot_map[$NAME]:-} ]] && continue
            if [[ $TRAN == usb || $RM == 1 || ( -n ${OSCAR_USB_CANDIDATE_ALLOW_DISK:-} && $PATH_VAL == "$OSCAR_USB_CANDIDATE_ALLOW_DISK" ) ]]; then
                disk_names+=("$NAME")
                d_path[$NAME]=$PATH_VAL
                d_tran[$NAME]=${TRAN:-usb}
                d_rm[$NAME]=${RM:-0}
                d_size[$NAME]=${SIZE:-0}
                d_model[$NAME]=${MODEL:-External USB Drive}
                if [[ -n $FSTYPE ]]; then
                    p_path[$NAME]=$PATH_VAL
                    p_fstype[$NAME]=$FSTYPE
                    p_label[$NAME]=$LABEL
                    p_uuid[$NAME]=$UUID
                    p_mnt[$NAME]=$MOUNTPOINT
                fi
            fi
        elif [[ $TYPE == part && -n $PKNAME && -z ${p_path[$PKNAME]:-} ]]; then
            p_path[$PKNAME]=$PATH_VAL
            p_fstype[$PKNAME]=$FSTYPE
            p_label[$PKNAME]=$LABEL
            p_uuid[$PKNAME]=$UUID
            p_mnt[$PKNAME]=$MOUNTPOINT
        fi
    done <<<"$lsblk_raw"

    local out='[' first=true dn sz sz_human is_cfg uuid_val
    for dn in "${disk_names[@]}"; do
        sz=${d_size[$dn]:-0}
        [[ $sz =~ ^[0-9]+$ ]] || sz=0
        sz_human=$(awk -v b="$sz" 'BEGIN {
            if (b >= 1000000000000) printf "%.2f TB", b / 1000000000000.0;
            else if (b >= 1000000000) printf "%.1f GB", b / 1000000000.0;
            else printf "%.1f MB", b / 1000000.0;
        }')
        uuid_val=${p_uuid[$dn]:-}
        is_cfg=false
        [[ -n $configured_uuid && $uuid_val == "$configured_uuid" ]] && is_cfg=true
        $first || out+=','
        first=false
        out+=$(printf '{"device":"%s","partition":"%s","model":"%s","transport":"%s","sizeBytes":%s,"sizeHuman":"%s","fstype":"%s","label":"%s","uuid":"%s","mountpoint":"%s","isConfiguredCarrier":%s}' \
            "$(json_escape "${d_path[$dn]}")" \
            "$(json_escape "${p_path[$dn]:-${d_path[$dn]}}")" \
            "$(json_escape "${d_model[$dn]}")" \
            "$(json_escape "${d_tran[$dn]}")" \
            "$sz" \
            "$(json_escape "$sz_human")" \
            "$(json_escape "${p_fstype[$dn]:-}")" \
            "$(json_escape "${p_label[$dn]:-}")" \
            "$(json_escape "$uuid_val")" \
            "$(json_escape "${p_mnt[$dn]:-}")" \
            "$is_cfg")
    done
    out+=']'
    printf '%s' "$out"
}

write_agent_status_json() {
    local override_job_json=${1:-}
    local ctrl_dir
    ctrl_dir=$(resolve_control_dir) || return 0
    install -d -m 0770 "$ctrl_dir" 2>/dev/null || mkdir -p "$ctrl_dir"
    chown 10001:10001 "$ctrl_dir" 2>/dev/null || true

    local status_file="$ctrl_dir/status.json"
    local last_snap_cache
    last_snap_cache="$(dirname "$config_file")/usb-backup-last-snapshot.json"

    local prev_job_json='null'
    if [[ -n $override_job_json ]]; then
        prev_job_json=$override_job_json
    elif [[ -f $status_file ]] && command -v python3 >/dev/null 2>&1; then
        prev_job_json=$(python3 - "$status_file" <<'PY' 2>/dev/null || echo 'null'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as fh:
        d = json.load(fh)
    aj = d.get('activeJob')
    print(json.dumps(aj) if isinstance(aj, dict) else 'null')
except Exception:
    print('null')
PY
)
    fi

    local configured=false mode='unconfigured' interval=15 mount_path='' fs_type='ntfs' fs_uuid=''
    local timer_active=false drive_state='UNCONFIGURED' backup_key_present=false
    local total_bytes=0 used_bytes=0 free_bytes=0
    local latest_snap_json='null'

    [[ -f "$script_dir/secrets/backup-key.txt" ]] && backup_key_present=true

    if [[ -f $config_file ]]; then
        configured=true
        mount_path=$(usb_cfg_value USB_BACKUP_MOUNT '')
        mode=$(usb_cfg_value USB_BACKUP_MODE 'disabled')
        interval=$(usb_cfg_value USB_BACKUP_INTERVAL_MINUTES '15')
        [[ $interval =~ ^[0-9]+$ ]] || interval=15
        fs_uuid=$(usb_cfg_value USB_BACKUP_FS_UUID '')
        fs_type=$(usb_cfg_value USB_BACKUP_FILESYSTEM 'ntfs')

        if command -v systemctl >/dev/null 2>&1 && [[ $skip_systemd != 1 ]]; then
            systemctl is-active --quiet oscar-continual-backup.timer 2>/dev/null && timer_active=true || true
        fi

        if is_drive_attached "$mount_path" "$fs_uuid"; then
            drive_state='ATTACHED'
            local df_line
            df_line=$(df -B1 --output=size,used,avail "$mount_path" 2>/dev/null | awk 'NR==2 {print $1, $2, $3}' || true)
            if [[ -n $df_line ]]; then
                read -r total_bytes used_bytes free_bytes <<<"$df_line"
            fi
            [[ $total_bytes =~ ^[0-9]+$ ]] || total_bytes=0
            [[ $used_bytes =~ ^[0-9]+$ ]] || used_bytes=0
            [[ $free_bytes =~ ^[0-9]+$ ]] || free_bytes=0
            if [[ $fs_type == directory && -d "$mount_path/OSCAR-Backup" ]]; then
                used_bytes=$(find "$mount_path/OSCAR-Backup" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {printf "%.0f", s+0}')
            fi
            if [[ -f "$mount_path/OSCAR-Backup/LATEST" ]]; then
                local snap_id snap_epoch
                snap_id=$(awk -F= '$1 == "snapshot_id" { print $2; exit }' "$mount_path/OSCAR-Backup/LATEST" | tr -d '\r')
                snap_epoch="$mount_path/OSCAR-Backup/snapshots/$snap_id/epoch.json"
                if [[ -f $snap_epoch ]]; then
                    latest_snap_json=$(tr '\n\r' ' ' <"$snap_epoch" | sed 's/  */ /g')
                    install -d -m 0700 "$(dirname "$last_snap_cache")" 2>/dev/null || true
                    printf '%s\n' "$latest_snap_json" >"$last_snap_cache" 2>/dev/null || true
                fi
            fi
        else
            local ej_flag
            ej_flag=$(ejected_flag_file)
            if [[ -e $ej_flag || -e "$mount_path/.oscar-ejected" ]]; then
                if [[ -n $fs_uuid ]] && ! blkid -U "$fs_uuid" >/dev/null 2>&1; then
                    rm -f -- "$ej_flag" 2>/dev/null || true
                    drive_state='DETACHED'
                else
                    drive_state='SAFE_TO_UNPLUG'
                fi
            else
                drive_state='DETACHED'
            fi
            if [[ -f $last_snap_cache ]]; then
                latest_snap_json=$(cat "$last_snap_cache" 2>/dev/null || echo 'null')
                [[ -n $latest_snap_json ]] || latest_snap_json='null'
            fi
        fi
    fi

    local candidates_json now_iso tmp_status
    candidates_json=$(collect_candidate_drives_json "$fs_uuid")
    now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    tmp_status="$ctrl_dir/.status.$$.$RANDOM.tmp"

    cat >"$tmp_status" <<EOF
{
  "agentActive": true,
  "hostPlatform": "linux",
  "updatedAt": "$now_iso",
  "configured": $configured,
  "mode": "$(json_escape "$mode")",
  "intervalMinutes": $interval,
  "mountPath": "$(json_escape "$mount_path")",
  "filesystem": "$(json_escape "$fs_type")",
  "fsUuid": "$(json_escape "$fs_uuid")",
  "timerActive": $timer_active,
  "driveState": "$drive_state",
  "backupKeyPresent": $backup_key_present,
  "driveTotalBytes": $total_bytes,
  "driveFreeBytes": $free_bytes,
  "backupUsedBytes": $used_bytes,
  "latestSnapshot": $latest_snap_json,
  "candidateDrives": $candidates_json,
  "activeJob": $prev_job_json
}
EOF
    chmod 0660 "$tmp_status" 2>/dev/null || true
    chown 10001:10001 "$tmp_status" 2>/dev/null || true
    mv -f -- "$tmp_status" "$status_file"
}

handle_export_key_if_present() {
    local ctrl_dir=$1 req_file="$1/request.json"
    [[ -f $req_file ]] || return 1
    local act req_id
    act=$(json_req_field "$req_file" action)
    [[ $act == export-backup-key ]] || return 1
    req_id=$(json_req_field "$req_file" requestId)
    rm -f -- "$req_file"
    [[ $req_id =~ ^[A-Za-z0-9-]{8,64}$ ]] || return 0
    local key_path tmp_escrow final_escrow
    key_path=$(ensure_backup_key)
    tmp_escrow="$ctrl_dir/.escrow-${req_id}.tmp"
    final_escrow="$ctrl_dir/escrow-${req_id}.key"
    cp -f -- "$key_path" "$tmp_escrow"
    chmod 0660 "$tmp_escrow" 2>/dev/null || true
    chown 10001:10001 "$tmp_escrow" 2>/dev/null || true
    mv -f -- "$tmp_escrow" "$final_escrow"
    write_agent_status_json >/dev/null 2>&1 || true
    return 0
}

cmd_agent_tick() {
    require_root
    local status_only=false
    while (($#)); do
        case $1 in
            --status-only) status_only=true; shift ;;
            *) shift ;;
        esac
    done

    local ctrl_dir
    ctrl_dir=$(resolve_control_dir) || return 0
    install -d -m 0770 "$ctrl_dir" 2>/dev/null || mkdir -p "$ctrl_dir"
    chown 10001:10001 "$ctrl_dir" 2>/dev/null || true

    # Sweep any stale one-time escrow files older than 60 seconds
    find "$ctrl_dir" -maxdepth 1 -type f -name 'escrow-*.key' -mmin +1 -delete 2>/dev/null || true

    # Fast-path one-time backup-key export even if a background sync is running
    if handle_export_key_if_present "$ctrl_dir"; then
        return 0
    fi

    local lock_root=${OSCAR_STORAGE_LOCK_DIR:-/run/lock/oscar-storage}
    install -d -m 0700 "$lock_root"
    exec 8>"$lock_root/oscar-usb-agent.lock"
    if [[ -f "$ctrl_dir/request.json" ]]; then
        flock -w 10 8 || return 0
    else
        flock -n 8 || return 0
    fi

    while [[ -f "$ctrl_dir/request.json" ]]; do
        if handle_export_key_if_present "$ctrl_dir"; then
            continue
        fi
        local proc_file="$ctrl_dir/.processing.$$.json"
        mv -f -- "$ctrl_dir/request.json" "$proc_file" 2>/dev/null || break

        local req_id req_by act started_at
        req_id=$(json_req_field "$proc_file" requestId)
        req_by=$(json_req_field "$proc_file" requestedBy)
        act=$(json_req_field "$proc_file" action)
        started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

        if [[ $act == refresh-status ]]; then
            rm -f -- "$proc_file"
            local done_job
            done_job=$(printf '{"requestId":"%s","action":"refresh-status","state":"SUCCEEDED","startedAt":"%s","finishedAt":"%s","requestedBy":"%s","message":"Refreshed USB drive status."}' \
                "$(json_escape "$req_id")" "$started_at" "$started_at" "$(json_escape "$req_by")")
            write_agent_status_json "$done_job"
            continue
        fi

        local running_msg="Executing $act..."
        case $act in
            prepare-drive) running_msg="Initializing USB NVMe backup carrier and running initial online snapshot..." ;;
            sync)          running_msg="Capturing zero-downtime online incremental backup snapshot..." ;;
            eject)         running_msg="Syncing final delta and unmounting USB drive for safe removal..." ;;
            attach)        running_msg="Mounting USB backup drive and catching up data recorded while unplugged..." ;;
            verify)        running_msg="Verifying snapshot HMAC, SHA-256 pack digests, encrypted secrets, and PostgreSQL base backup..." ;;
            set-mode)      running_msg="Updating backup mode and host schedule..." ;;
        esac

        local run_job
        run_job=$(printf '{"requestId":"%s","action":"%s","state":"RUNNING","startedAt":"%s","requestedBy":"%s","message":"%s"}' \
            "$(json_escape "$req_id")" "$(json_escape "$act")" "$started_at" "$(json_escape "$req_by")" "$(json_escape "$running_msg")")
        write_agent_status_json "$run_job"

        local out_log="$ctrl_dir/.job-out.$$.log"
        local rc=0
        (
            set -Eeuo pipefail
            case $act in
                prepare-drive)
                    local dev adopt_uuid no_fmt confirm fs mode iv
                    dev=$(json_req_field "$proc_file" device)
                    adopt_uuid=$(json_req_field "$proc_file" adoptUuid)
                    no_fmt=$(json_req_field "$proc_file" noFormat)
                    confirm=$(json_req_field "$proc_file" confirm)
                    fs=$(json_req_field "$proc_file" filesystem)
                    mode=$(json_req_field "$proc_file" mode)
                    iv=$(json_req_field "$proc_file" intervalMinutes)
                    [[ $fs =~ ^(ntfs|ext4)$ ]] || fs=ntfs
                    [[ $mode =~ ^(continual|occasional)$ ]] || fail "Invalid initial mode: $mode"
                    [[ $iv =~ ^[0-9]+$ ]] && ((iv >= 5 && iv <= 1440)) || iv=15
                    local -a args=(prepare-drive --filesystem "$fs" --mode "$mode" --interval-minutes "$iv")
                    if [[ -n $adopt_uuid ]]; then
                        [[ $adopt_uuid =~ ^[A-Za-z0-9-]{4,64}$ ]] || fail "Invalid adoptUuid."
                        args+=(--adopt-uuid "$adopt_uuid")
                    else
                        [[ $dev =~ ^/dev/(sd[a-z][0-9]*|nvme[0-9]+n[0-9]+(p[0-9]+)?)$ ]] || fail "Invalid USB block device: $dev"
                        args+=(--device "$dev")
                        if [[ $no_fmt == true ]]; then
                            args+=(--no-format)
                        else
                            [[ $confirm == FORMAT ]] || fail "Confirmation token FORMAT is required."
                            args+=(--confirm FORMAT)
                        fi
                    fi
                    bash "$script_dir/oscar-usb-backup.sh" "${args[@]}"
                    ;;
                set-mode)
                    local mode iv
                    mode=$(json_req_field "$proc_file" mode)
                    iv=$(json_req_field "$proc_file" intervalMinutes)
                    [[ $mode =~ ^(continual|occasional|disabled)$ ]] || fail "Invalid mode: $mode"
                    [[ $iv =~ ^[0-9]+$ ]] && ((iv >= 5 && iv <= 1440)) || iv=15
                    bash "$script_dir/oscar-usb-backup.sh" mode "$mode" --interval-minutes "$iv"
                    ;;
                sync)
                    local q
                    q=$(json_req_field "$proc_file" quiesce)
                    if [[ $q == true ]]; then
                        bash "$script_dir/oscar-usb-backup.sh" sync --quiesce
                    else
                        bash "$script_dir/oscar-usb-backup.sh" sync
                    fi
                    ;;
                eject)
                    local ns
                    ns=$(json_req_field "$proc_file" noSync)
                    if [[ $ns == true ]]; then
                        bash "$script_dir/oscar-usb-backup.sh" eject --no-sync
                    else
                        bash "$script_dir/oscar-usb-backup.sh" eject
                    fi
                    ;;
                attach)
                    bash "$script_dir/oscar-usb-backup.sh" attach
                    ;;
                verify)
                    local dp
                    dp=$(json_req_field "$proc_file" deep)
                    if [[ $dp == true ]]; then
                        bash "$script_dir/oscar-usb-backup.sh" verify --deep
                    else
                        bash "$script_dir/oscar-usb-backup.sh" verify
                    fi
                    ;;
                *)
                    fail "Unsupported action: $act"
                    ;;
            esac
        ) >"$out_log" 2>&1 || rc=$?

        rm -f -- "$proc_file"
        local finished_at summary_line final_state final_job
        finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        if ((rc == 0)); then
            final_state='SUCCEEDED'
            summary_line=$(grep -E '^(Incremental backup sync COMPLETE|SAFE TO UNPLUG|VERIFIED OK|Switched backup mode|Prepared OSCAR USB|Pre-registered USB)' "$out_log" | tail -n 1 || true)
            [[ -n $summary_line ]] || summary_line="Completed $act successfully."
        else
            final_state='FAILED'
            summary_line=$(grep -E '^ERROR:' "$out_log" | tail -n 1 || tail -n 2 "$out_log" | tr '\n' ' ' || true)
            [[ -n $summary_line ]] || summary_line="Operation $act failed with exit code $rc."
        fi
        rm -f -- "$out_log"

        final_job=$(printf '{"requestId":"%s","action":"%s","state":"%s","startedAt":"%s","finishedAt":"%s","requestedBy":"%s","message":"%s"}' \
            "$(json_escape "$req_id")" "$(json_escape "$act")" "$final_state" "$started_at" "$finished_at" "$(json_escape "$req_by")" "$(json_escape "$summary_line")")
        write_agent_status_json "$final_job"
    done

    if [[ $status_only == true ]]; then
        write_agent_status_json
    fi
}

cmd_install_agent() {
    require_root
    local ctrl_dir
    ctrl_dir=$(resolve_control_dir) || {
        printf 'Skipping USB backup host agent registration (Docker volume %s is not initialized yet).\n' "$state_volume"
        return 0
    }
    install -d -m 0770 "$ctrl_dir"
    chown 10001:10001 "$ctrl_dir" 2>/dev/null || true
    disable_usb_autosuspend

    if [[ $skip_systemd != 1 ]] && command -v systemctl >/dev/null 2>&1; then
        cat >"$systemd_dir/oscar-usb-backup-agent.service" <<EOF
[Unit]
Description=OSCAR Admin Panel USB Backup Control Agent
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash "$script_dir/oscar-usb-backup.sh" agent-tick
Nice=19
IOSchedulingClass=idle
EOF

        cat >"$systemd_dir/oscar-usb-backup-agent.path" <<EOF
[Unit]
Description=Watch OSCAR Admin Panel USB Backup Control Queue

[Path]
PathExists=$ctrl_dir/request.json
PathChanged=$ctrl_dir/request.json
Unit=oscar-usb-backup-agent.service

[Install]
WantedBy=multi-user.target
EOF

        cat >"$systemd_dir/oscar-usb-backup-status.service" <<EOF
[Unit]
Description=OSCAR USB Backup Drive & Snapshot Status Refresh
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash "$script_dir/oscar-usb-backup.sh" agent-tick --status-only
Nice=19
IOSchedulingClass=idle
EOF

        cat >"$systemd_dir/oscar-usb-backup-status.timer" <<EOF
[Unit]
Description=Periodic OSCAR USB Backup Status Refresh (every 15s)

[Timer]
OnBootSec=10s
OnUnitActiveSec=15s
AccuracySec=2s

[Install]
WantedBy=timers.target
EOF

        if [[ -d $udev_dir ]]; then
            cat >"$udev_dir/97-oscar-usb-agent-status.rules" <<'EOF'
ACTION=="add|remove|change", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", TAG+="systemd", ENV{SYSTEMD_WANTS}+="oscar-usb-backup-status.service"
EOF
            udevadm control --reload-rules >/dev/null 2>&1 || true
        fi

        # Re-bind continual timer if usb-backup.env already exists (e.g. across release upgrades!)
        if [[ -f $config_file ]]; then
            local mnt md iv uuid ft
            mnt=$(usb_cfg_value USB_BACKUP_MOUNT '')
            md=$(usb_cfg_value USB_BACKUP_MODE 'disabled')
            iv=$(usb_cfg_value USB_BACKUP_INTERVAL_MINUTES '15')
            uuid=$(usb_cfg_value USB_BACKUP_FS_UUID '')
            ft=$(usb_cfg_value USB_BACKUP_FILESYSTEM 'ntfs')
            save_usb_config "$mnt" "$md" "$iv" "$uuid" "$ft"
            configure_systemd_and_udev "$mnt" "$md" "$iv" "$uuid"
        fi

        systemctl daemon-reload
        systemctl enable --now oscar-usb-backup-agent.path oscar-usb-backup-status.timer >/dev/null
    fi

    cmd_agent_tick --status-only
    printf 'Installed OSCAR USB backup host control agent (watching %s).\n' "$ctrl_dir"
}

usage() {
    cat <<'EOF'
Usage:
  sudo bash oscar.sh usb-backup list-drives
  sudo bash oscar.sh usb-backup prepare-drive --device /dev/sdX [--no-format] [--mount /srv/oscar-usb-backup] [--filesystem ntfs|ext4] [--mode continual|occasional] [--interval-minutes 15] [--confirm FORMAT]
  sudo bash oscar.sh usb-backup prepare-drive --adopt-uuid UUID [--mount /srv/oscar-usb-backup] [--filesystem ntfs|ext4] [--mode continual|occasional] [--interval-minutes 15]
  sudo bash oscar.sh usb-backup prepare-drive --path /mounted/backup-dir [--mode continual|occasional] [--interval-minutes 15]
  sudo bash oscar.sh usb-backup mode <continual|occasional|disabled> [--interval-minutes 15]
  sudo bash oscar.sh usb-backup sync [--quiesce] [--if-attached]
  sudo bash oscar.sh usb-backup eject [--no-sync]
  sudo bash oscar.sh usb-backup attach
  sudo bash oscar.sh usb-backup status
  sudo bash oscar.sh usb-backup verify [--from PATH] [--backup-key FILE] [--deep]
  sudo bash oscar.sh usb-backup restore [--from PATH] [--backup-key FILE] [--archive-dir PATH] --confirm RESTORE
  sudo bash oscar.sh usb-backup install-agent
EOF
}

action=${1:-help}
shift || true
case $action in
    list-drives) cmd_list_drives "$@" ;;
    prepare-drive) cmd_prepare_drive "$@" ;;
    mode) cmd_mode "$@" ;;
    sync) cmd_sync "$@" ;;
    eject) cmd_eject "$@" ;;
    attach) cmd_attach "$@" ;;
    status) cmd_status "$@" ;;
    verify) cmd_verify "$@" ;;
    restore) cmd_restore "$@" ;;
    install-agent) cmd_install_agent "$@" ;;
    agent-tick) cmd_agent_tick "$@" ;;
    help|--help|-h) usage ;;
    *) fail "Unknown usb-backup subcommand: $action (run \`oscar.sh usb-backup help\`)" ;;
esac
