#!/usr/bin/env bash
# OSCAR Post-Autoinstall Interactive Provisioning, Restore & Import Wizard
# Launches automatically on first login after bare-metal Ubuntu 24.04 autoinstall
# (or anytime via `sudo bash oscar.sh wizard` / `sudo oscar-wizard`).
#
# Eliminates manual Linux mount/cp/chmod/umount commands by scanning attached USB
# drives read-only (-o ro), optimizing the Ubuntu host offline (including USB-NVMe
# Bulk-Only Transport + No-LPM quirks), and guiding the administrator through:
#   1. Restore from Continual / Occasional USB NVMe Backup (usb-backup restore)
#   2. Restore from Single-Snapshot Backup (oscar restore)
#   3. Fresh Install + Import Configuration (config.json / lanes.csv / .pmtiles)
#   4. Clean Fresh Site Installation (oscar init + optional static IP setup)
set -Eeuo pipefail

script_path=${BASH_SOURCE[0]}
[[ ! -L $script_path ]] || { printf 'ERROR: Refusing to execute symlinked script: %s\n' "$script_path" >&2; exit 1; }
case $script_path in */*) script_parent=${script_path%/*} ;; *) script_parent=. ;; esac
ubuntu_dir=$(CDPATH= cd -P -- "$script_parent" && pwd -P)
release_dir=$(CDPATH= cd -P -- "$ubuntu_dir/.." && pwd -P)

export OSCAR_WIZARD_ACTIVE=1

compose_project=${OSCAR_COMPOSE_PROJECT_NAME:-oscar}
state_volume=${OSCAR_STATE_VOLUME:-oscar_oscar_state}
wizard_mount_root="/run/oscar-wizard-mounts.$$"
declare -a temp_mounts=()
saved_printk_level=''

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

prune_disconnected_wizard_mounts() {
    [[ -d $wizard_mount_root ]] || return 0
    local m src_dev
    for m in "$wizard_mount_root"/*; do
        [[ -d $m ]] || continue
        if mountpoint -q "$m" 2>/dev/null; then
            src_dev=$(findmnt -rn -o SOURCE --target "$m" 2>/dev/null || true)
            if [[ $src_dev == /dev/* && ! -b $src_dev ]]; then
                umount -l "$m" 2>/dev/null || true
                rmdir "$m" 2>/dev/null || true
            fi
        fi
    done
}

cleanup_wizard() {
    local m
    set +e
    if [[ -n $saved_printk_level && -w /proc/sys/kernel/printk ]]; then
        printf '%s\n' "$saved_printk_level" >/proc/sys/kernel/printk 2>/dev/null || true
    fi
    if [[ -d $wizard_mount_root ]]; then
        for m in "$wizard_mount_root"/*; do
            if [[ -d $m ]] && mountpoint -q "$m" 2>/dev/null; then
                umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true
            fi
        done
    fi
    for (( idx=${#temp_mounts[@]}-1 ; idx>=0 ; idx-- )); do
        m=${temp_mounts[idx]}
        if [[ -n $m ]] && mountpoint -q "$m" 2>/dev/null; then
            umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true
        fi
    done
    rm -rf -- "$wizard_mount_root" 2>/dev/null || true
}
trap cleanup_wizard EXIT HUP INT TERM

usage() {
    cat <<'EOF'
Usage:
  sudo bash oscar.sh wizard                         (Interactive TUI / CLI wizard)
  sudo bash oscar.sh wizard --scan-only             (Scan & print detected USB backups, keys, and seed files)
  sudo bash oscar.sh wizard --non-interactive \
      --mode usb-restore|single-restore|import-config|clean-init \
      [--skip-prepare-host] [--bench-isolation] \
      [--from PATH] [--backup-id ID] [--backup-key FILE] \
      [--hostname oscar-host] [--port 443] \
      [--import-json FILE] [--import-csv FILE] [--import-pmtiles FILE] \
      [--keep-imported-users] [--site-network-env FILE] [--apply-site-network]
EOF
}

has_tui=false
if [[ -t 0 && -t 1 ]] && command -v whiptail >/dev/null 2>&1 && [[ ${TERM:-dumb} != dumb ]]; then
    has_tui=true
fi

ensure_usb_nvme_quirks_live() {
    local quirks_u="0bda:9210:u,152d:0583:u,174c:2362:u,152d:0562:u,152d:0578:u"
    local quirks_k="0bda:9210:k,152d:0583:k,174c:2362:k,152d:0562:k,152d:0578:k"
    if [[ -d /etc/modprobe.d ]]; then
        cat >/etc/modprobe.d/oscar-usb-nvme-quirks.conf <<EOF
# Force Bulk-Only Transport (no UAS) and disable USB3 U1/U2 Link Power Management
# on Realtek RTL9210, JMicron JMS583/562/578, and ASMedia ASM2362 NVMe enclosures.
options usb-storage quirks=${quirks_u}
options usbcore quirks=${quirks_k}
EOF
    fi
    modprobe usb_storage 2>/dev/null || true
    [[ -w /sys/module/usb_storage/parameters/quirks ]] && echo "$quirks_u" >/sys/module/usb_storage/parameters/quirks 2>/dev/null || true
    [[ -w /sys/module/usbcore/parameters/quirks ]] && echo "$quirks_k" >/sys/module/usbcore/parameters/quirks 2>/dev/null || true
    local ctrl
    for ctrl in /sys/bus/usb/devices/*/power/control; do
        [[ -w $ctrl ]] && echo on >"$ctrl" 2>/dev/null || true
    done
}

ensure_host_prepared() {
    local skip_flag=${1:-false}
    [[ $skip_flag == true ]] && return 0
    ensure_usb_nvme_quirks_live

    local docker_ok=false sysctl_ok=false
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        docker_ok=true
    fi
    [[ -f /etc/sysctl.d/90-oscar.conf ]] && sysctl_ok=true

    if $docker_ok && $sysctl_ok; then
        return 0
    fi

    info "Optimizing Ubuntu 24.04 host (Docker Engine, LVM capacity, sysctl, UFW, and USB-NVMe stability quirks)..."
    local -a prep_args=(prepare-host --expand-lvm --hold-docker --configure-ufw)
    if [[ -d "$release_dir/installers/ubuntu-24.04-x86_64" ]]; then
        prep_args+=(--offline)
    fi
    bash "$release_dir/oscar.sh" "${prep_args[@]}"
    ensure_usb_nvme_quirks_live
}

# Mount all readable external USB partitions read-only (-o ro) under wizard_mount_root
# and return active mount directories (both pre-existing mounts and newly mounted USB partitions).
discover_search_roots() {
    mkdir -p "$wizard_mount_root"
    chmod 0700 "$wizard_mount_root"
    prune_disconnected_wizard_mounts

    local -a roots=()
    [[ -d /srv/oscar/seed ]] && roots+=("/srv/oscar/seed")
    [[ -d /srv/oscar-usb-backup ]] && roots+=("/srv/oscar-usb-backup")

    local line NAME PATH_VAL TYPE TRAN RM SIZE FSTYPE LABEL MOUNTPOINT
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        NAME=$(sed -n 's/.*\<NAME="\([^"]*\)".*/\1/p' <<<"$line")
        PATH_VAL=$(sed -n 's/.*\<PATH="\([^"]*\)".*/\1/p' <<<"$line")
        TYPE=$(sed -n 's/.*\<TYPE="\([^"]*\)".*/\1/p' <<<"$line")
        TRAN=$(sed -n 's/.*\<TRAN="\([^"]*\)".*/\1/p' <<<"$line")
        RM=$(sed -n 's/.*\<RM="\([^"]*\)".*/\1/p' <<<"$line")
        SIZE=$(sed -n 's/.*\<SIZE="\([^"]*\)".*/\1/p' <<<"$line")
        FSTYPE=$(sed -n 's/.*\<FSTYPE="\([^"]*\)".*/\1/p' <<<"$line")
        LABEL=$(sed -n 's/.*\<LABEL="\([^"]*\)".*/\1/p' <<<"$line")
        MOUNTPOINT=$(sed -n 's/.*\<MOUNTPOINT="\([^"]*\)".*/\1/p' <<<"$line")

        [[ $TYPE == part || $TYPE == disk ]] || continue
        [[ -n $FSTYPE && $FSTYPE != LVM2_member && $FSTYPE != swap && $FSTYPE != iso9660 && $FSTYPE != squashfs ]] || continue
        [[ $LABEL != CIDATA && $LABEL != UBUNTU_LIVE && $LABEL != ESP && $LABEL != EFI ]] || continue
        # Skip tiny (< 32 MiB) FAT EFI system partitions on installer sticks
        if [[ $FSTYPE == vfat && ${SIZE:-0} =~ ^[0-9]+$ ]] && (( SIZE > 0 && SIZE < 33554432 )); then
            continue
        fi

        # Check parent transport if partition
        local parent_tran=$TRAN
        if [[ -z $parent_tran ]]; then
            local pk
            pk=$(lsblk -dnro PKNAME "$PATH_VAL" 2>/dev/null | head -n 1 || true)
            [[ -n $pk ]] && parent_tran=$(lsblk -dnro TRAN "/dev/$pk" 2>/dev/null | head -n 1 || true)
        fi
        [[ $parent_tran == usb || $RM == 1 || $LABEL == OSCAR_BACKUP || $LABEL == OSCAR_MEDIA ]] || continue

        if [[ -n $MOUNTPOINT && -d $MOUNTPOINT ]]; then
            roots+=("$MOUNTPOINT")
            [[ -d "$MOUNTPOINT/seed" ]] && roots+=("$MOUNTPOINT/seed")
        else
            local mp="$wizard_mount_root/$NAME"
            mkdir -p "$mp"
            if mount -o ro "$PATH_VAL" "$mp" 2>/dev/null; then
                temp_mounts+=("$mp")
                roots+=("$mp")
                [[ -d "$mp/seed" ]] && roots+=("$mp/seed")
            else
                rmdir "$mp" 2>/dev/null || true
            fi
        fi
    done < <(lsblk -P -b -o NAME,PATH,TYPE,TRAN,RM,SIZE,FSTYPE,LABEL,MOUNTPOINT -e 7 2>/dev/null || true)

    local u_home=${SUDO_USER:+$(getent passwd "$SUDO_USER" | cut -d: -f6)}
    [[ -n $u_home && -d $u_home ]] && roots+=("$u_home")
    [[ -d /root ]] && roots+=("/root")
    [[ -d "$release_dir/secrets" ]] && roots+=("$release_dir/secrets")

    # Deduplicate while preserving order
    local -A seen=()
    local r real_r
    for r in "${roots[@]}"; do
        [[ -d $r ]] || continue
        real_r=$(realpath -P -- "$r" 2>/dev/null || printf '%s' "$r")
        if [[ -z ${seen[$real_r]:-} ]]; then
            seen[$real_r]=1
            printf '%s\n' "$real_r"
        fi
    done
}

discover_usb_backups() {
    local r snap_id snap_time
    while IFS= read -r r; do
        if [[ -f "$r/OSCAR-Backup/LATEST" ]]; then
            snap_id=$(awk -F= '$1 == "snapshot_id" { print $2; exit }' "$r/OSCAR-Backup/LATEST" | tr -d '\r')
            snap_time='unknown'
            if [[ -f "$r/OSCAR-Backup/snapshots/$snap_id/epoch.json" ]]; then
                snap_time=$(sed -n 's/.*"createdAt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$r/OSCAR-Backup/snapshots/$snap_id/epoch.json" | head -n 1)
            fi
            local src_dev
            src_dev=$(findmnt -rn -o SOURCE --target "$r" 2>/dev/null || echo "dir")
            printf '%s\t%s\t%s\t%s\n' "$r" "${snap_id:-unknown}" "${snap_time:-unknown}" "$src_dev"
        fi
    done < <(discover_search_roots)
}

discover_single_backups() {
    local r mf b_dir b_parent b_id
    local -A seen_b=()
    while IFS= read -r r; do
        for mf in "$r"/backup-*/manifest.env "$r"/backups/backup-*/manifest.env "$r"/oscar-storage/backups/backup-*/manifest.env; do
            [[ -f $mf ]] || continue
            b_dir=$(dirname -- "$mf")
            b_parent=$(dirname -- "$b_dir")
            b_id=$(basename -- "$b_dir")
            [[ -z ${seen_b["$b_parent/$b_id"]:-} ]] || continue
            seen_b["$b_parent/$b_id"]=1
            printf '%s\t%s\n' "$b_parent" "$b_id"
        done
    done < <(discover_search_roots)
}

discover_candidate_files() {
    local pattern=$1 r f
    local -A seen_f=()
    while IFS= read -r r; do
        while IFS= read -r -d '' f; do
            local real_f
            real_f=$(realpath -P -- "$f" 2>/dev/null || printf '%s' "$f")
            if [[ -z ${seen_f[$real_f]:-} ]]; then
                seen_f[$real_f]=1
                printf '%s\n' "$real_f"
            fi
        done < <(find "$r" -maxdepth 2 -type f -iname "$pattern" -print0 2>/dev/null || true)
    done < <(discover_search_roots)
}

stage_private_key_copy() {
    local src_key=$1
    [[ -f $src_key ]] || fail "Backup key file not found: $src_key"
    mkdir -p "$wizard_mount_root"
    local dst_key="$wizard_mount_root/staged-backup-key.txt"
    tr -d '\r' <"$src_key" >"$dst_key"
    chmod 0600 "$dst_key"
    printf '%s' "$dst_key"
}

select_backup_key_interactive() {
    while true; do
        mapfile -t key_cands < <(discover_candidate_files '*backup*key*.txt')
        if $has_tui; then
            local -a items=()
            local kc
            for kc in "${key_cands[@]}"; do
                items+=("$kc" "Detected key ($(stat -c '%s bytes' "$kc" 2>/dev/null || echo file))")
            done
            items+=("RESCAN" "Plug in USB stick with backup-key.txt and rescan")
            items+=("MANUAL" "Enter file path or paste backup key string manually")
            local sel
            sel=$(whiptail --title "Select Backup Encryption Key" \
                --menu "Choose the AES-256/HMAC backup-key.txt for this backup:" 18 78 8 "${items[@]}" 3>&1 1>&2 2>&3) || return 1
            if [[ $sel == RESCAN ]]; then
                continue
            elif [[ $sel == MANUAL ]]; then
                local manual_in
                manual_in=$(whiptail --title "Backup Key Path or Value" \
                    --inputbox "Enter absolute path to backup-key.txt OR paste the base64 key line:" 11 78 "" 3>&1 1>&2 2>&3) || return 1
                [[ -n $manual_in ]] || fail "No backup key provided."
                if [[ -f $manual_in ]]; then
                    stage_private_key_copy "$manual_in"
                    return 0
                else
                    mkdir -p "$wizard_mount_root"
                    local pasted="$wizard_mount_root/pasted-backup-key.txt"
                    printf '%s\n' "${manual_in//$'\r'/}" >"$pasted"
                    chmod 0600 "$pasted"
                    printf '%s' "$pasted"
                    return 0
                fi
            else
                stage_private_key_copy "$sel"
                return 0
            fi
        else
            printf '\nDetected Backup Key Files:\n' >&2
            local idx=1 kc
            for kc in "${key_cands[@]}"; do
                printf '  [%d] %s\n' "$idx" "$kc" >&2
                ((idx += 1))
            done
            printf '  [R] Rescan USB drives\n  [M] Enter path manually\nChoice: ' >&2
            local ch
            IFS= read -r ch
            if [[ ${ch^^} == R ]]; then
                continue
            elif [[ ${ch^^} == M ]]; then
                printf 'Path to backup-key.txt: ' >&2
                local mp
                IFS= read -r mp
                stage_private_key_copy "$mp"
                return 0
            elif [[ $ch =~ ^[0-9]+$ ]] && ((ch >= 1 && ch <= ${#key_cands[@]})); then
                stage_private_key_copy "${key_cands[$((ch - 1))]}"
                return 0
            fi
        fi
    done
}

# Safely merge an imported SensorHub/OSCAR config.json onto an initialized 3.11+ state volume
# while preserving container database/storage/auth infrastructure bindings.
merge_imported_config_json() {
    local imported_json=$1 keep_users=${2:-false} csv_rel_path=${3:-}
    [[ -f $imported_json ]] || fail "Imported JSON file not found: $imported_json"

    local ver="local"
    if [[ -f "$release_dir/.env" ]]; then
        ver=$(awk -F= '$1 == "OSCAR_VERSION" { print $2; exit }' "$release_dir/.env" | tr -d '\r')
    fi

    info "Merging site lanes, sensors, and OSCAR settings from $imported_json..."
    docker compose --project-name "$compose_project" --project-directory "$release_dir" \
        --env-file "$release_dir/.env" --file "$release_dir/compose.yaml" stop oscar >/dev/null

    local stage_dir="$wizard_mount_root/config-merge"
    mkdir -p "$stage_dir"
    chmod 0700 "$stage_dir"

    docker run --rm --user 0:0 --volume "${state_volume}:/state:ro" \
        --volume "$stage_dir:/out" --entrypoint sh "oscar:$ver" -eu -c 'cp -f /state/config.json /out/base-config.json && chmod 0644 /out/base-config.json'

    python3 - "$stage_dir/base-config.json" "$imported_json" "$stage_dir/merged-config.json" "$keep_users" "$csv_rel_path" <<'PY'
import json, pathlib, sys

base_path, imp_path, out_path, keep_users_str, csv_rel = sys.argv[1:6]
keep_users = keep_users_str.lower() == "true"

base_mods = json.loads(pathlib.Path(base_path).read_text(encoding="utf-8"))
imp_mods = json.loads(pathlib.Path(imp_path).read_text(encoding="utf-8"))
if not isinstance(imp_mods, list):
    raise SystemExit("ERROR: Imported config.json must be a top-level JSON array of SensorHub module configurations.")

# Core container-bound singleton module classes kept from the fresh 3.11+ init
INFRA_CLASSES = {
    "org.sensorhub.impl.security.session.BasicSessionConfig",
    "org.sensorhub.impl.service.HttpServerConfig",
    "org.sensorhub.impl.security.BasicSecurityRealmConfig",
    "org.sensorhub.ui.AdminUIConfig",
    "org.sensorhub.impl.service.consys.ConSysApiServiceConfig",
    "com.botts.impl.service.oscar.OSCARServiceConfig",
    "com.botts.impl.service.dailyfile.DailyFileJournalServiceConfig",
    "com.botts.impl.service.bucket.BucketServiceConfig",
    "org.sensorhub.impl.database.system.SystemDriverDatabaseConfig",
    "org.sensorhub.impl.datastore.postgis.database.OscarTieredObsSystemDatabaseConfig",
    "org.sensorhub.impl.datastore.h2.MVObsSystemDatabaseConfig",
    "com.botts.impl.service.fileserver.FileServerConfig",
    "org.sensorhub.impl.service.hivemq.MqttServerConfig",
    "org.sensorhub.impl.service.consys.mqtt.ConSysApiMqttServiceConfig",
}

base_db = next((m for m in base_mods if m.get("objClass") == "org.sensorhub.impl.database.system.SystemDriverDatabaseConfig"), None)
active_db_id = base_db["id"] if base_db else None

imp_oscar = next((m for m in imp_mods if m.get("objClass") == "com.botts.impl.service.oscar.OSCARServiceConfig"), None)
imp_realm = next((m for m in imp_mods if m.get("objClass") == "org.sensorhub.impl.security.BasicSecurityRealmConfig"), None)

PORTABLE_OSCAR_FIELDS = [
    "nodeId",
    "siteDiagramConfig",
    "siteDiagramPath",
    "customAdjudicationCodes",
    "spreadsheetConfigPath",
    "emlEnabled",
    "statsFrequencyMinutes",
    "webIdApiRoot",
]

merged = []
for m in base_mods:
    cls = m.get("objClass", "")
    if cls == "com.botts.impl.service.oscar.OSCARServiceConfig":
        m = dict(m)
        if imp_oscar:
            for k in PORTABLE_OSCAR_FIELDS:
                if k in imp_oscar and imp_oscar[k] is not None:
                    m[k] = imp_oscar[k]
        if csv_rel:
            m["spreadsheetConfigPath"] = csv_rel
    elif cls == "org.sensorhub.impl.security.BasicSecurityRealmConfig" and imp_realm:
        m = dict(m)
        if keep_users and isinstance(imp_realm.get("users"), list) and imp_realm["users"]:
            # Only copy users whose passwords are already hashed (never __INITIAL_ADMIN_PASSWORD__)
            valid_users = [u for u in imp_realm["users"] if isinstance(u, dict) and u.get("password") not in (None, "", "__INITIAL_ADMIN_PASSWORD__")]
            if valid_users:
                has_admin = any(u.get("id") == "admin" for u in valid_users)
                if not has_admin:
                    base_admins = [u for u in m.get("users", []) if u.get("id") == "admin"]
                    valid_users = base_admins + valid_users
                m["users"] = valid_users
        else:
            # Preserve fresh admin password while importing any extra non-admin accounts
            existing_ids = {u.get("id") for u in m.get("users", []) if isinstance(u, dict)}
            extra_users = [
                u for u in imp_realm.get("users", [])
                if isinstance(u, dict)
                and u.get("id") not in existing_ids
                and u.get("password") not in (None, "", "__INITIAL_ADMIN_PASSWORD__")
            ]
            if extra_users:
                m["users"] = list(m.get("users", [])) + extra_users
    merged.append(m)

existing_mod_ids = {m.get("id") for m in merged if isinstance(m, dict) and m.get("id")}
imported_count = 0
for m in imp_mods:
    if not isinstance(m, dict):
        continue
    cls = m.get("objClass", "")
    if cls in INFRA_CLASSES:
        continue
    if m.get("id") in existing_mod_ids:
        continue
    m_copy = json.loads(json.dumps(m))
    if active_db_id and "databaseID" in m_copy and m_copy["databaseID"]:
        m_copy["databaseID"] = active_db_id
    merged.append(m_copy)
    existing_mod_ids.add(m_copy.get("id"))
    imported_count += 1

pathlib.Path(out_path).write_text(json.dumps(merged, indent=2) + "\n", encoding="utf-8")
print(f"Merged {imported_count} site/lane/sensor module(s) from imported config.json.")
PY

    docker run --rm --user 0:0 --volume "${state_volume}:/state" \
        --volume "$stage_dir/merged-config.json:/merged.json:ro" \
        --entrypoint sh "oscar:$ver" -eu -c 'cp -f /merged.json /state/config.json && chown 10001:10001 /state/config.json && chmod 0600 /state/config.json'

    docker compose --project-name "$compose_project" --project-directory "$release_dir" \
        --env-file "$release_dir/.env" --file "$release_dir/compose.yaml" \
        up --detach --no-deps --no-build --pull never --wait --wait-timeout 300 oscar gateway
}

stage_spreadsheet_csv() {
    local csv_file=$1
    [[ -f $csv_file ]] || fail "CSV file not found: $csv_file"
    local ver
    ver=$(awk -F= '$1 == "OSCAR_VERSION" { print $2; exit }' "$release_dir/.env" | tr -d '\r')
    local base_csv
    base_csv=$(basename -- "$csv_file")
    docker run --rm --user 0:0 --volume "${state_volume}:/state" \
        --volume "$(realpath -- "$csv_file"):/in.csv:ro" \
        --entrypoint sh "oscar:$ver" -eu -c "mkdir -p /state/files/spreadsheets && cp -f /in.csv '/state/files/spreadsheets/$base_csv' && chown -R 10001:10001 /state/files/spreadsheets && chmod 0640 '/state/files/spreadsheets/$base_csv'"
    printf 'spreadsheets/%s' "$base_csv"
}

stage_pmtiles_archive() {
    local pmtiles_file=$1
    [[ -f $pmtiles_file ]] || fail "PMTiles file not found: $pmtiles_file"
    local ver base_pm sha_pm sz_pm now_iso
    ver=$(awk -F= '$1 == "OSCAR_VERSION" { print $2; exit }' "$release_dir/.env" | tr -d '\r')
    base_pm=$(basename -- "$pmtiles_file")
    [[ $base_pm == *.pmtiles ]] || fail "Offline map archive must end in .pmtiles: $base_pm"
    sha_pm=$(sha256sum "$pmtiles_file" | awk '{print $1}')
    sz_pm=$(stat -c '%s' "$pmtiles_file")
    now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    info "Installing offline PMTiles vector basemap ($base_pm)..."
    docker run --rm --user 0:0 --volume "${state_volume}:/state" \
        --volume "$(realpath -- "$pmtiles_file"):/in.pmtiles:ro" \
        --entrypoint sh "oscar:$ver" -eu -c "
            mkdir -p /state/.moduledata/extensions/pmtiles
            cp -f /in.pmtiles '/state/.moduledata/extensions/pmtiles/$base_pm'
            cat >/state/.moduledata/extensions/pmtiles/state.json <<JSON
{
  \"enabled\": true,
  \"activeFilename\": \"$base_pm\",
  \"sha256\": \"$sha_pm\",
  \"sizeBytes\": $sz_pm,
  \"updatedAt\": \"$now_iso\",
  \"updatedBy\": \"oscar-wizard\"
}
JSON
            chown -R 10001:10001 /state/.moduledata/extensions
        "
}

mark_wizard_completed() {
    mkdir -p /etc/oscar 2>/dev/null || true
    date -u +%Y-%m-%dT%H:%M:%SZ >/etc/oscar/wizard-completed 2>/dev/null || true
}

scan_only=false
non_interactive=false
skip_prepare_host=false
mode_val=''
from_path=''
backup_id=''
backup_key=''
hostname_val=''
port_val=443
import_json=''
import_csv=''
import_pmtiles=''
keep_imported_users=false
site_net_env=''
apply_site_net=false
bench_isolation=false

apply_bench_isolation_guard() {
    info "Enabling Safe Bench / DR Clone Isolation (DOCKER-USER tcp-reset outbound sensor guard)..."
    if command -v iptables >/dev/null 2>&1; then
        iptables -F DOCKER-USER 2>/dev/null || true
        iptables -I DOCKER-USER 1 -s 172.16.0.0/12 ! -d 172.16.0.0/12 -p tcp -m conntrack --ctstate NEW -j REJECT --reject-with tcp-reset 2>/dev/null || true
        iptables -I DOCKER-USER 2 -s 172.16.0.0/12 ! -d 172.16.0.0/12 -m conntrack --ctstate NEW -j REJECT 2>/dev/null || true
    fi
}

disable_restored_tunnel_for_bench() {
    if [[ -f "$release_dir/.env" ]]; then
        sed -i -e 's/^OCTELIUM_ENABLED=.*/OCTELIUM_ENABLED=false/' "$release_dir/.env" 2>/dev/null || true
    fi
}

prompt_bench_isolation_if_interactive() {
    $bench_isolation && return 0
    $non_interactive && return 0
    if $has_tui; then
        if whiptail --title "Live Network Sensor & Tunnel Safety Check" \
            --yesno "Is the original OSCAR server still running LIVE on this same network?\n\n- Choose <Yes> (Safe Bench / DR Drill Mode) to isolate outbound container traffic so this test restore CANNOT steal single-client RPM sockets or tunnel sessions from the active portal.\n\n- Choose <No> if this server is replacing the old hardware in production." \
            15 80; then
            bench_isolation=true
        fi
    else
        printf '\nIs the original OSCAR server still running LIVE on this network? [y/N] (y = Safe Bench Isolation): '
        local iso_ans
        IFS= read -r iso_ans
        [[ ${iso_ans^^} == Y* ]] && bench_isolation=true
    fi
}

while (($# > 0)); do
    case "$1" in
        --scan-only) scan_only=true; shift ;;
        --non-interactive) non_interactive=true; shift ;;
        --skip-prepare-host) skip_prepare_host=true; shift ;;
        --bench-isolation) bench_isolation=true; shift ;;
        --mode) mode_val=${2:?missing --mode}; shift 2 ;;
        --from) from_path=${2:?missing --from}; shift 2 ;;
        --backup-id) backup_id=${2:?missing --backup-id}; shift 2 ;;
        --backup-key) backup_key=${2:?missing --backup-key}; shift 2 ;;
        --hostname) hostname_val=${2:?missing --hostname}; shift 2 ;;
        --port) port_val=${2:?missing --port}; shift 2 ;;
        --import-json) import_json=${2:?missing --import-json}; shift 2 ;;
        --import-csv) import_csv=${2:?missing --import-csv}; shift 2 ;;
        --import-pmtiles) import_pmtiles=${2:?missing --import-pmtiles}; shift 2 ;;
        --keep-imported-users) keep_imported_users=true; shift ;;
        --site-network-env) site_net_env=${2:?missing --site-network-env}; shift 2 ;;
        --apply-site-network) apply_site_net=true; shift ;;
        -h|--help|help) usage; exit 0 ;;
        *) fail "Unknown wizard option: $1 (run with --help for usage)" ;;
    esac
done

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Run with sudo: sudo bash oscar.sh wizard"

if $has_tui && ! $scan_only && ! $non_interactive && [[ -r /proc/sys/kernel/printk && -w /proc/sys/kernel/printk ]]; then
    saved_printk_level=$(awk '{print $1}' /proc/sys/kernel/printk 2>/dev/null || true)
    dmesg --console-off 2>/dev/null || printf '1\n' >/proc/sys/kernel/printk 2>/dev/null || true
fi

if $scan_only; then
    ensure_usb_nvme_quirks_live
    printf '=== Detected USB Continual/Occasional Backups ===\n'
    discover_usb_backups || true
    printf '=== Detected Single-Snapshot Backups ===\n'
    discover_single_backups || true
    printf '=== Detected Backup Keys ===\n'
    discover_candidate_files '*backup*key*.txt' || true
    printf '=== Detected JSON Configurations ===\n'
    discover_candidate_files '*.json' | grep -Ev '/(epoch|status|request|state|manifest|components[^/]*)\.json$' || true
    printf '=== Detected CSV Spreadsheets ===\n'
    discover_candidate_files '*.csv' || true
    printf '=== Detected Offline PMTiles Basemaps ===\n'
    discover_candidate_files '*.pmtiles' || true
    exit 0
fi

# Interactive mode selection if --mode was not given
if [[ -z $mode_val ]]; then
    $non_interactive && fail "Specify --mode usb-restore|single-restore|import-config|clean-init when using --non-interactive."
    ensure_host_prepared "$skip_prepare_host"

    if $has_tui; then
        mode_val=$(whiptail --title "OSCAR First-Boot Provisioning & Recovery Wizard" \
            --menu "Host optimization & USB-NVMe stability quirks are active.\nChoose how you want to set up this OSCAR server:" \
            19 80 6 \
            "usb-restore"    "Restore from Continual / Occasional USB NVMe Backup" \
            "single-restore" "Restore from Single-Snapshot Backup Folder" \
            "import-config"  "Fresh Install + Import config.json / lanes.csv / .pmtiles" \
            "clean-init"     "Clean Fresh Site Installation (oscar init)" \
            "shell"          "Exit Wizard to Linux Shell (run 'sudo oscar-wizard' anytime)" \
            3>&1 1>&2 2>&3) || exit 0
    else
        cat <<'EOF'

OSCAR First-Boot Provisioning & Recovery Wizard
===============================================
  [1] Restore from Continual / Occasional USB NVMe Backup (usb-backup restore)
  [2] Restore from Single-Snapshot Backup Folder (oscar restore)
  [3] Fresh Install + Import config.json / lanes.csv / .pmtiles
  [4] Clean Fresh Site Installation (oscar init)
  [5] Exit to Linux Shell
EOF
        printf 'Select [1-5]: '
        IFS= read -r m_choice
        case $m_choice in
            1) mode_val=usb-restore ;;
            2) mode_val=single-restore ;;
            3) mode_val=import-config ;;
            4) mode_val=clean-init ;;
            *) exit 0 ;;
        esac
    fi
else
    ensure_host_prepared "$skip_prepare_host"
fi

if [[ $mode_val == shell ]]; then
    if $has_tui; then
        if whiptail --title "First-Boot Auto-Launch" --yesno "Keep launching this wizard automatically on login until OSCAR is initialized?" 10 70; then
            :
        else
            mkdir -p /etc/oscar && touch /etc/oscar/wizard-dismissed
        fi
    fi
    exit 0
fi

# Optional site network staging before init/import
if [[ -n $site_net_env ]]; then
    bash "$release_dir/oscar.sh" stage-site-network --config "$site_net_env"
    $apply_site_net && bash "$release_dir/oscar.sh" apply-site-network
fi

case "$mode_val" in
    usb-restore)
        if [[ -z $from_path ]]; then
            $non_interactive && fail "Specify --from PATH for non-interactive usb-restore."
            while [[ -z $from_path ]]; do
                mapfile -t usb_bks < <(discover_usb_backups)
                if $has_tui; then
                    items=()
                    for row in "${usb_bks[@]}"; do
                        IFS=$'\t' read -r b_root b_snap b_time b_dev <<<"$row"
                        items+=("$b_root" "$b_dev — snap $b_snap ($b_time)")
                    done
                    items+=("RESCAN" "Plug in OSCAR_BACKUP USB drive and rescan")
                    menu_prompt="Detected read-only OSCAR USB NVMe backup drives:"
                    menu_h=18
                    if ((${#usb_bks[@]} == 0)); then
                        menu_prompt="No OSCAR_BACKUP drive detected yet.\n\nPower tip: 1-4 TB M.2 NVMe USB enclosures draw 6-8W at spin-up. Use a mains-powered USB 3.2 hub/dock or a dedicated 15W USB-C port (avoid 4.5W laptop USB-A ports or shared dual USB-C ports next to another USB-C dongle), confirm the enclosure LED is lit, then select RESCAN:"
                        menu_h=22
                    fi
                    sel_b=$(whiptail --title "Select USB Backup Drive" \
                        --menu "$menu_prompt" "$menu_h" 82 6 "${items[@]}" 3>&1 1>&2 2>&3) || exit 1
                    [[ $sel_b == RESCAN ]] && continue
                    from_path=$sel_b
                else
                    printf '\nDetected USB Backup Drives:\n'
                    if ((${#usb_bks[@]} == 0)); then
                        printf '  (None detected yet — Note: 1-4 TB M.2 NVMe USB enclosures draw 6-8W inrush; use a mains-powered USB 3.2 hub/dock or dedicated 15W USB-C port and confirm the enclosure LED is lit.)\n'
                    fi
                    idx=1
                    for row in "${usb_bks[@]}"; do
                        printf '  [%d] %s\n' "$idx" "$row"
                        ((idx += 1))
                    done
                    printf '  [R] Rescan USB drives\nChoice: '
                    IFS= read -r ch
                    [[ ${ch^^} == R ]] && continue
                    [[ $ch =~ ^[0-9]+$ ]] && ((ch >= 1 && ch <= ${#usb_bks[@]})) || fail "Invalid selection."
                    IFS=$'\t' read -r from_path _ <<<"${usb_bks[$((ch - 1))]}"
                fi
            done
        fi

        if [[ -n $backup_key ]]; then
            staged_key=$(stage_private_key_copy "$backup_key")
        else
            $non_interactive && fail "Specify --backup-key FILE for non-interactive usb-restore."
            staged_key=$(select_backup_key_interactive)
        fi

        prompt_bench_isolation_if_interactive
        $bench_isolation && apply_bench_isolation_guard

        info "Restoring OSCAR from read-only USB backup at $from_path..."
        bash "$release_dir/oscar.sh" usb-backup restore --from "$from_path" --backup-key "$staged_key" --confirm RESTORE
        if $bench_isolation; then
            disable_restored_tunnel_for_bench
        fi
        bash "$release_dir/oscar.sh" refresh-tls
        bash "$release_dir/oscar.sh" verify
        mark_wizard_completed
        info "USB Backup Restore & Verification COMPLETE."
        if $bench_isolation; then
            info "NOTE: Safe Bench / DR Clone Isolation is active (outbound container sensor/tunnel traffic blocked via DOCKER-USER). Run 'sudo iptables -F DOCKER-USER' when cutting over to live site hardware."
        fi
        ;;

    single-restore)
        if [[ -z $from_path || -z $backup_id ]]; then
            $non_interactive && fail "Specify --from BACKUP_DIR and --backup-id ID for non-interactive single-restore."
            while [[ -z $backup_id ]]; do
                mapfile -t single_bks < <(discover_single_backups)
                if $has_tui; then
                    items=()
                    idx=0
                    for row in "${single_bks[@]}"; do
                        IFS=$'\t' read -r s_dir s_id <<<"$row"
                        items+=("$idx" "$s_id  (in $s_dir)")
                        ((idx += 1))
                    done
                    items+=("RESCAN" "Plug in USB backup drive and rescan")
                    sel_s=$(whiptail --title "Select Single-Snapshot Backup" \
                        --menu "Choose snapshot to restore:" 18 80 8 "${items[@]}" 3>&1 1>&2 2>&3) || exit 1
                    [[ $sel_s == RESCAN ]] && continue
                    IFS=$'\t' read -r from_path backup_id <<<"${single_bks[$sel_s]}"
                else
                    printf '\nDetected Single-Snapshot Backups:\n'
                    idx=1
                    for row in "${single_bks[@]}"; do
                        printf '  [%d] %s\n' "$idx" "$row"
                        ((idx += 1))
                    done
                    printf '  [R] Rescan\nChoice: '
                    IFS= read -r ch
                    [[ ${ch^^} == R ]] && continue
                    [[ $ch =~ ^[0-9]+$ ]] && ((ch >= 1 && ch <= ${#single_bks[@]})) || fail "Invalid selection."
                    IFS=$'\t' read -r from_path backup_id <<<"${single_bks[$((ch - 1))]}"
                fi
            done
        fi

        if [[ -n $backup_key ]]; then
            staged_key=$(stage_private_key_copy "$backup_key")
        else
            $non_interactive && fail "Specify --backup-key FILE for non-interactive single-restore."
            staged_key=$(select_backup_key_interactive)
        fi

        prompt_bench_isolation_if_interactive
        $bench_isolation && apply_bench_isolation_guard

        # Seed minimal .env & backup-key if restoring onto an uninitialized host
        if [[ ! -f "$release_dir/.env" ]]; then
            cp -f -- "$release_dir/.env.example" "$release_dir/.env"
            sed -i \
                -e 's|^OSCAR_BACKUP_MODE=.*|OSCAR_BACKUP_MODE=single|' \
                -e "s|^OSCAR_BACKUP_DIR=.*|OSCAR_BACKUP_DIR=$from_path|" \
                "$release_dir/.env"
            chmod 0600 "$release_dir/.env"
        fi
        install -d -m 0700 "$release_dir/secrets"
        cp -f -- "$staged_key" "$release_dir/secrets/backup-key.txt"
        chmod 0600 "$release_dir/secrets/backup-key.txt"

        OSCAR_BACKUP_MODE=single OSCAR_BACKUP_DIR="$from_path" \
            bash "$release_dir/oscar.sh" restore --backup "$backup_id" --confirm "$backup_id"
        if $bench_isolation; then
            disable_restored_tunnel_for_bench
        fi
        bash "$release_dir/oscar.sh" refresh-tls
        bash "$release_dir/oscar.sh" verify
        mark_wizard_completed
        info "Single-Snapshot Restore & Verification COMPLETE."
        if $bench_isolation; then
            info "NOTE: Safe Bench / DR Clone Isolation is active (outbound container sensor/tunnel traffic blocked via DOCKER-USER). Run 'sudo iptables -F DOCKER-USER' when cutting over to live site hardware."
        fi
        ;;

    import-config)
        if ! $non_interactive && [[ -z $import_json && -z $import_csv && -z $import_pmtiles ]]; then
            # Interactive picker for config.json
            mapfile -t json_cands < <(discover_candidate_files '*.json' | grep -Ev '/(epoch|status|request|state|manifest|components[^/]*)\.json$' || true)
            if ((${#json_cands[@]} > 0)); then
                if $has_tui; then
                    items=("SKIP" "Do not import a config.json")
                    for jc in "${json_cands[@]}"; do items+=("$jc" "SensorHub/OSCAR JSON"); done
                    sel_j=$(whiptail --title "Import Saved config.json (Optional)" \
                        --menu "Select a config.json from USB/seed to import lanes & site settings:" 18 80 8 "${items[@]}" 3>&1 1>&2 2>&3) || exit 1
                    [[ $sel_j != SKIP ]] && import_json=$sel_j
                else
                    printf '\nDetected JSON configs (Enter 0 to skip):\n'
                    idx=1; for jc in "${json_cands[@]}"; do printf '  [%d] %s\n' "$idx" "$jc"; ((idx += 1)); done
                    printf 'Choice [0-%d]: ' "${#json_cands[@]}"; IFS= read -r ch
                    if [[ $ch =~ ^[1-9][0-9]*$ ]] && ((ch <= ${#json_cands[@]})); then import_json=${json_cands[$((ch - 1))]}; fi
                fi
            fi

            # Interactive picker for lanes.csv
            mapfile -t csv_cands < <(discover_candidate_files '*.csv')
            if ((${#csv_cands[@]} > 0)); then
                if $has_tui; then
                    items=("SKIP" "Do not import a CSV spreadsheet")
                    for cc in "${csv_cands[@]}"; do items+=("$cc" "Lane configuration CSV"); done
                    sel_c=$(whiptail --title "Import Lanes CSV Spreadsheet (Optional)" \
                        --menu "Select a lanes CSV spreadsheet from USB/seed:" 18 80 8 "${items[@]}" 3>&1 1>&2 2>&3) || exit 1
                    [[ $sel_c != SKIP ]] && import_csv=$sel_c
                else
                    printf '\nDetected CSV spreadsheets (Enter 0 to skip):\n'
                    idx=1; for cc in "${csv_cands[@]}"; do printf '  [%d] %s\n' "$idx" "$cc"; ((idx += 1)); done
                    printf 'Choice [0-%d]: ' "${#csv_cands[@]}"; IFS= read -r ch
                    if [[ $ch =~ ^[1-9][0-9]*$ ]] && ((ch <= ${#csv_cands[@]})); then import_csv=${csv_cands[$((ch - 1))]}; fi
                fi
            fi

            # Interactive picker for .pmtiles
            mapfile -t pm_cands < <(discover_candidate_files '*.pmtiles')
            if ((${#pm_cands[@]} > 0)); then
                if $has_tui; then
                    items=("SKIP" "Do not install an offline .pmtiles basemap now")
                    for pc in "${pm_cands[@]}"; do items+=("$pc" "Offline PMTiles basemap"); done
                    sel_p=$(whiptail --title "Import Offline PMTiles Basemap (Optional)" \
                        --menu "Select an offline .pmtiles map archive:" 18 80 8 "${items[@]}" 3>&1 1>&2 2>&3) || exit 1
                    [[ $sel_p != SKIP ]] && import_pmtiles=$sel_p
                else
                    printf '\nDetected .pmtiles basemaps (Enter 0 to skip):\n'
                    idx=1; for pc in "${pm_cands[@]}"; do printf '  [%d] %s\n' "$idx" "$pc"; ((idx += 1)); done
                    printf 'Choice [0-%d]: ' "${#pm_cands[@]}"; IFS= read -r ch
                    if [[ $ch =~ ^[1-9][0-9]*$ ]] && ((ch <= ${#pm_cands[@]})); then import_pmtiles=${pm_cands[$((ch - 1))]}; fi
                fi
            fi
        fi

        if [[ ! -f "$release_dir/.env" ]]; then
            local_hn=${hostname_val:-$(hostname 2>/dev/null || echo oscar-host)}
            local -a init_args=(init --hostname "$local_hn" --port "$port_val")
            $non_interactive && init_args+=(--non-interactive)
            info "Initializing fresh OSCAR deployment ($local_hn)..."
            bash "$release_dir/oscar.sh" "${init_args[@]}"
        fi

        csv_rel=''
        if [[ -n $import_csv ]]; then
            csv_rel=$(stage_spreadsheet_csv "$import_csv")
        fi
        if [[ -n $import_json ]]; then
            merge_imported_config_json "$import_json" "$keep_imported_users" "$csv_rel"
        elif [[ -n $csv_rel ]]; then
            # Attach CSV path into OSCARServiceConfig using empty module import
            empty_json="$wizard_mount_root/empty-import.json"
            printf '[]\n' >"$empty_json"
            merge_imported_config_json "$empty_json" false "$csv_rel"
        fi
        if [[ -n $import_pmtiles ]]; then
            stage_pmtiles_archive "$import_pmtiles"
        fi

        bash "$release_dir/oscar.sh" verify
        mark_wizard_completed
        info "Fresh Install + Configuration Import COMPLETE."
        ;;

    clean-init)
        if ! $non_interactive && $has_tui; then
            if whiptail --title "Optional Static Site Network Setup" \
                --yesno "Would you like to stage static site Ethernet IPs now (safe to run even on hotel DHCP/Wi-Fi)?" 10 74; then
                bash "$release_dir/oscar.sh" stage-site-network
                if whiptail --title "Apply Static IPs Now?" \
                    --yesno "Activate the staged static site IPs right now? (Choose 'No' if still in a hotel/lab on DHCP and apply on arrival at the site.)" 11 76; then
                    bash "$release_dir/oscar.sh" apply-site-network
                fi
            fi
        fi
        local_hn=${hostname_val:-$(hostname 2>/dev/null || echo oscar-host)}
        local -a init_args=(init --hostname "$local_hn" --port "$port_val")
        $non_interactive && init_args+=(--non-interactive)
        bash "$release_dir/oscar.sh" "${init_args[@]}"
        bash "$release_dir/oscar.sh" verify
        mark_wizard_completed
        info "Clean OSCAR Site Installation COMPLETE."
        ;;

    *)
        fail "Unsupported --mode '$mode_val' (expected usb-restore, single-restore, import-config, or clean-init)."
        ;;
esac
