#!/usr/bin/env bash
# OSCAR Incremental & Continual USB Backup Container Engine
# Runs inside the hardened oscar:<version> container (--network none) on both
# Ubuntu Server 24.04 LTS and Windows 11 (Docker Desktop + WSL 2) so backup
# packs, HMAC manifests, and restores are 100% portable across host platforms.
set -Eeuo pipefail

ENGINE_SCRATCH=$(mktemp -d /tmp/oscar-usb-engine.XXXXXX)
trap 'rm -rf -- "${ENGINE_SCRATCH:-}"' EXIT HUP INT TERM

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

sha256_file() {
    sha256sum -- "$1" | awk '{print $1}'
}

hmac_file_base64() {
    local target=$1 key_file=$2
    openssl dgst -sha256 -mac HMAC -macopt "key:$(cat "$key_file")" -binary "$target" | openssl base64 -A
}

write_carrier_helpers() {
    local usb_root=$1
    [[ -d $usb_root ]] || fail "USB carrier root does not exist: $usb_root"

    cat >"$usb_root/README-DATA-ADMIN.txt" <<'EOF'
================================================================================
OSCAR PORTABLE / CONTINUAL USB NVMe BACKUP CARRIER
================================================================================

This drive contains an encrypted-credential, HMAC-authenticated incremental
OSCAR portal backup inside the "OSCAR-Backup" folder.

1. COPYING THIS BACKUP ON YOUR LAPTOP (WINDOWS, macOS, OR LINUX)
--------------------------------------------------------------------------------
- Do NOT edit, rename, or delete individual files inside "OSCAR-Backup".
- Keep the site's "backup-key.txt" stored separately from this drive.
- To copy this backup onto another external SSD or laptop folder quickly
  (transferring ONLY new daily packs since your last visit and verifying
  SHA-256 checksums):
    * Windows laptop: Double-click COPY-TO-ANOTHER-DRIVE.bat
      (or run: COPY-TO-ANOTHER-DRIVE.bat "E:\Site-Backup-Copy")
    * macOS / Linux laptop:
      bash ./copy-to-another-drive.sh "/Volumes/ArchiveSSD/Site-Backup-Copy"
- Standard File Explorer / Finder copy of the entire "OSCAR-Backup" folder
  is also supported.

2. RETURNING THIS DRIVE TO THE OSCAR SERVER
--------------------------------------------------------------------------------
- Simply plug this USB NVMe SSD back into the OSCAR server's USB 3.x port.
- In "continual" mode, OSCAR automatically detects the drive and pulls in all
  radiation telemetry, Daily-File CSVs, retained JPEGs, OCR crops, and database
  updates recorded while the drive was disconnected.
- In "occasional" mode (or to trigger immediate catch-up manually), run:
    * Ubuntu:  sudo bash oscar.sh usb-backup attach
    * Windows: .\oscar.bat usb-backup attach

3. RESTORING ONTO A REPLACEMENT OSCAR SERVER
--------------------------------------------------------------------------------
- Ubuntu:
    sudo bash oscar.sh usb-backup restore \
      --from /srv/oscar-usb-backup \
      --backup-key /secure/path/backup-key.txt \
      --confirm RESTORE
- Windows:
    .\oscar.bat usb-backup restore `
      -From R:\ `
      -BackupKey C:\secure\backup-key.txt `
      -Confirm RESTORE
================================================================================
EOF

    cat >"$usb_root/COPY-TO-ANOTHER-DRIVE.bat" <<'EOF'
@echo off
setlocal EnableExtensions
title OSCAR USB Backup - Copy and Verify to Another Drive

set "SRC_DIR=%~dp0OSCAR-Backup"
if not exist "%SRC_DIR%\LATEST" (
    echo ERROR: "%SRC_DIR%\LATEST" was not found on this drive.
    pause
    exit /b 1
)

set "DEST_ROOT=%~1"
if "%DEST_ROOT%"=="" (
    echo Enter destination folder on your laptop or second SSD
    echo Example: E:\OSCAR-Site-Archive
    set /p "DEST_ROOT=Destination path: "
)
if "%DEST_ROOT%"=="" (
    echo Cancelled.
    exit /b 1
)

set "DEST_BACKUP=%DEST_ROOT%\OSCAR-Backup"
echo.
echo [1/2] Incrementally copying OSCAR-Backup to "%DEST_BACKUP%" ...
robocopy "%SRC_DIR%" "%DEST_BACKUP%" /MIR /XO /FFT /MT:8 /R:2 /W:2 /NP /NFL /NDL
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 (
    echo ERROR: robocopy reported failure code %RC%.
    pause
    exit /b %RC%
)
copy /Y "%SRC_DIR%\LATEST" "%DEST_BACKUP%\LATEST" >nul 2>&1
copy /Y "%SRC_DIR%\.oscar-usb-backup-root" "%DEST_BACKUP%\.oscar-usb-backup-root" >nul 2>&1
if exist "%SRC_DIR%\packs\state\catalog.tsv" copy /Y "%SRC_DIR%\packs\state\catalog.tsv" "%DEST_BACKUP%\packs\state\catalog.tsv" >nul 2>&1
copy /Y "%~dp0README-DATA-ADMIN.txt" "%DEST_ROOT%\README-DATA-ADMIN.txt" >nul 2>&1
copy /Y "%~dp0COPY-TO-ANOTHER-DRIVE.bat" "%DEST_ROOT%\COPY-TO-ANOTHER-DRIVE.bat" >nul 2>&1
copy /Y "%~dp0copy-to-another-drive.sh" "%DEST_ROOT%\copy-to-another-drive.sh" >nul 2>&1

echo [2/2] Verifying snapshot SHA-256 digests at "%DEST_BACKUP%" ...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; " ^
  "$latestLine = Get-Content -LiteralPath '%DEST_BACKUP%\LATEST' | Where-Object { $_ -like 'snapshot_id=*' } | Select-Object -First 1; " ^
  "if (-not $latestLine) { throw 'Invalid LATEST pointer' }; " ^
  "$snapId = $latestLine.Substring('snapshot_id='.Length); " ^
  "$snapDir = Join-Path '%DEST_BACKUP%\snapshots' $snapId; " ^
  "Get-Content -LiteralPath (Join-Path $snapDir 'SHA256SUMS') | ForEach-Object { " ^
  "  if ($_ -match '^([0-9a-f]{64})  \./(.+)$') { " ^
  "    $p = Join-Path $snapDir ($Matches[2] -replace '/','\'); " ^
  "    $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant(); " ^
  "    if ($h -ne $Matches[1]) { throw ('Checksum mismatch: ' + $p) } " ^
  "  } " ^
  "}; " ^
  "Write-Host ('VERIFIED OK: Snapshot ' + $snapId + ' copied cleanly to %DEST_BACKUP%') -ForegroundColor Green"
if errorlevel 1 (
    echo ERROR: Destination checksum verification failed!
    pause
    exit /b 1
)
echo.
echo Copy and verification complete. You can now safely eject this drive and
echo plug the OSCAR USB NVMe SSD back into the OSCAR server.
if "%~1"=="" pause
exit /b 0
EOF
    sed -i 's/$/\r/' "$usb_root/COPY-TO-ANOTHER-DRIVE.bat" 2>/dev/null || true

    cat >"$usb_root/copy-to-another-drive.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
src_backup="$script_dir/OSCAR-Backup"
[[ -f "$src_backup/LATEST" ]] || { echo "ERROR: $src_backup/LATEST not found." >&2; exit 1; }

dest_root=${1:-}
if [[ -z $dest_root ]]; then
    printf 'Enter destination directory on your laptop or second drive: '
    IFS= read -r dest_root
fi
[[ -n $dest_root ]] || { echo "Cancelled." >&2; exit 1; }

mkdir -p "$dest_root/OSCAR-Backup"
echo "[1/2] Incrementally syncing OSCAR-Backup -> $dest_root/OSCAR-Backup ..."
if command -v rsync >/dev/null 2>&1; then
    rsync -rt --delete-after "$src_backup/" "$dest_root/OSCAR-Backup/"
else
    rm -rf "$dest_root/OSCAR-Backup"
    cp -R "$src_backup" "$dest_root/OSCAR-Backup"
fi
cp -f "$src_backup/LATEST" "$dest_root/OSCAR-Backup/LATEST"
cp -f "$src_backup/.oscar-usb-backup-root" "$dest_root/OSCAR-Backup/.oscar-usb-backup-root" 2>/dev/null || true
[[ -f "$src_backup/packs/state/catalog.tsv" ]] && cp -f "$src_backup/packs/state/catalog.tsv" "$dest_root/OSCAR-Backup/packs/state/catalog.tsv" || true
cp -f "$script_dir/README-DATA-ADMIN.txt" "$dest_root/" 2>/dev/null || true
cp -f "$script_dir/COPY-TO-ANOTHER-DRIVE.bat" "$dest_root/" 2>/dev/null || true
cp -f "$script_dir/copy-to-another-drive.sh" "$dest_root/" 2>/dev/null || true

snap_id=$(awk -F= '$1 == "snapshot_id" { print $2; exit }' "$dest_root/OSCAR-Backup/LATEST" | tr -d '\r')
snap_dir="$dest_root/OSCAR-Backup/snapshots/$snap_id"
echo "[2/2] Verifying snapshot $snap_id SHA-256 digests ..."
(
    cd "$snap_dir"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c SHA256SUMS >/dev/null
    else
        shasum -a 256 -c SHA256SUMS >/dev/null
    fi
)
echo "VERIFIED OK: Snapshot $snap_id copied cleanly to $dest_root/OSCAR-Backup"
EOF
    chmod 0755 "$usb_root/copy-to-another-drive.sh" 2>/dev/null || true
}

# Coalesce multiple sub-day state delta packs for a completed UTC day (or >= 4
# small sub-day packs for today) so 5-year pack count stays <= ~2,000 files.
coalesce_state_packs_if_needed() {
    local state_packs_dir=$1 catalog_file=$2 today_utc=$3 scratch=$4
    [[ -f $catalog_file ]] || return 0

    local day count merged_name merged_path extract_dir
    local -a day_packs=()
    for day in $(find "$state_packs_dir" -maxdepth 1 -type f -name 'pack-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.tar' \
        -printf '%f\n' 2>/dev/null | cut -c6-15 | sort -u); do
        mapfile -t day_packs < <(find "$state_packs_dir" -maxdepth 1 -type f -name "pack-${day}-*.tar" -printf '%f\n' | sort)
        count=${#day_packs[@]}
        if [[ $day != "$today_utc" && $count -gt 1 ]] || [[ $day == "$today_utc" && $count -ge 6 ]]; then
            extract_dir="$scratch/coalesce-$day"
            rm -rf -- "$extract_dir"
            mkdir -p "$extract_dir"
            local p
            for p in "${day_packs[@]}"; do
                tar -C "$extract_dir" --no-same-owner -xf "$state_packs_dir/$p"
            done
            merged_name="pack-${day}-000000.tar.tmp"
            merged_path="$state_packs_dir/$merged_name"
            (cd "$extract_dir" && tar -cf "$merged_path" .)
            rm -rf -- "$extract_dir"
            local final_pack="pack-${day}-000000.tar"
            for p in "${day_packs[@]}"; do
                [[ $p == "$final_pack" ]] && continue
                rm -f -- "$state_packs_dir/$p" "$state_packs_dir/$p.sha256"
            done
            mv -f -- "$merged_path" "$state_packs_dir/$final_pack"
            printf '%s  %s\n' "$(sha256_file "$state_packs_dir/$final_pack")" "$final_pack" >"$state_packs_dir/$final_pack.sha256"
            awk -F'\t' -v OFS='\t' -v d="pack-${day}-" -v target="$final_pack" '
                index($4, d) == 1 { $4 = target }
                { print }
            ' "$catalog_file" >"$scratch/catalog.updated"
            mv -f -- "$scratch/catalog.updated" "$catalog_file"
        fi
    done
}

cmd_pack_sync() {
    local snapshot_id=${1:?missing snapshot_id}
    local deployment_id=${2:?missing deployment_id}
    local oscar_version=${3:?missing oscar_version}
    local backup_mode=${4:?missing backup_mode}
    local postgres_lsn=${5:?missing postgres_lsn}
    local epoch_id=${6:?missing epoch_id}
    local timestamp_iso=${7:?missing timestamp_iso}

    local backup_root=/backup/OSCAR-Backup
    local work="$backup_root/snapshots/$snapshot_id.partial"
    local archive_packs="$backup_root/packs/archive"
    local state_packs="$backup_root/packs/state"
    local catalog_file="$state_packs/catalog.tsv"
    local scratch="$ENGINE_SCRATCH/pack-sync"
    mkdir -p "$scratch"

    mkdir -p "$archive_packs" "$state_packs" "$work"
    [[ -f "$work/postgres.tar" ]] ||
        fail 'Online PostgreSQL base backup (postgres.tar) is missing from staging directory.'

    local today_utc yesterday_utc
    today_utc=$(date -u +%Y-%m-%d)
    yesterday_utc=$(date -u -d 'yesterday' +%Y-%m-%d 2>/dev/null || date -u +%Y-%m-%d)

    # 1. Incremental Parquet Archive Sync:
    #    UTC dates strictly older than yesterday are immutable SEALED windows and
    #    are packed once into packs/archive/archive-YYYY-MM-DD.tar.
    : >"$work/pack-index.txt"
    local -a recent_archive_items=()
    if [[ -d /archive/datasets/observations ]]; then
        local date_dir base date_str pack_name pack_path sha
        for date_dir in /archive/datasets/observations/date=*; do
            [[ -d $date_dir ]] || continue
            base=${date_dir##*/}
            date_str=${base#date=}
            if [[ $date_str =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && $date_str < "$yesterday_utc" ]] &&
               [[ -z $(find "$date_dir" -name '*.partial*' -print -quit 2>/dev/null) ]]; then
                pack_name="archive-${date_str}.tar"
                pack_path="$archive_packs/$pack_name"
                if [[ ! -f $pack_path || ! -f "$pack_path.sha256" ]]; then
                    tar -C /archive -cf "$pack_path.tmp" "datasets/observations/$base"
                    mv -f -- "$pack_path.tmp" "$pack_path"
                    sha=$(sha256_file "$pack_path")
                    printf '%s  %s\n' "$sha" "$pack_name" >"$pack_path.sha256"
                else
                    sha=$(awk '{print $1; exit}' "$pack_path.sha256")
                fi
                printf '%s  packs/archive/%s\n' "$sha" "$pack_name" >>"$work/pack-index.txt"
            else
                recent_archive_items+=("datasets/observations/$base")
            fi
        done
    fi
    # Include any non-observations top-level entries inside /archive (excluding .oscar-storage-root and datasets/observations)
    local top_entry top_base
    for top_entry in /archive/* /archive/.[!.]*; do
        [[ -e $top_entry ]] || continue
        top_base=${top_entry##*/}
        [[ $top_base == ".oscar-storage-root" || $top_base == "datasets" ]] && continue
        recent_archive_items+=("$top_base")
    done
    if [[ -d /archive/datasets ]]; then
        for top_entry in /archive/datasets/*; do
            [[ -e $top_entry ]] || continue
            top_base=${top_entry##*/}
            [[ $top_base == "observations" ]] && continue
            recent_archive_items+=("datasets/$top_base")
        done
    fi
    if ((${#recent_archive_items[@]} > 0)); then
        tar -C /archive -cf "$work/archive-recent.tar" "${recent_archive_items[@]}"
    else
        tar -cf "$work/archive-recent.tar" --files-from /dev/null
    fi

    # 2. Incremental State Immutable Media / DailyFiles / Crops / Reports Sync:
    local -a imm_roots=(
        "files/dailyfiles"
        "files/.dailyfile-journal/segments"
        "files/videos/retained-media/v1/events"
        "files/ocr/crops"
        "files/adjudication"
        "files/reports"
    )
    : >"$scratch/live.tsv"
    local rel_root
    for rel_root in "${imm_roots[@]}"; do
        if [[ -d "/state/$rel_root" ]]; then
            (cd /state && find "$rel_root" -ignore_readdir_race -type f -printf '%p\t%s\t%Ts\n' 2>/dev/null) >>"$scratch/live.tsv" || true
        fi
    done
    LC_ALL=C sort -t $'\t' -k1,1 "$scratch/live.tsv" -o "$scratch/live.tsv"
    cut -f1 "$scratch/live.tsv" | gzip -1 >"$work/live-immutable-paths.txt.gz"

    [[ -f $catalog_file ]] || : >"$catalog_file"
    LC_ALL=C sort -t $'\t' -k1,1 "$catalog_file" -o "$scratch/catalog.sorted"

    # Determine new or modified files (size or mtime_sec changed) while pruning deleted catalog rows
    awk -F'\t' -v OFS='\t' -v delta_out="$scratch/delta.paths" -v kept_out="$scratch/kept.tsv" '
        FILENAME == ARGV[1] {
            cat_size[$1] = $2
            cat_mtime[$1] = $3
            cat_pack[$1] = $4
            next
        }
        {
            p = $1; sz = $2; mt = $3
            if ((p in cat_pack) && cat_size[p] == sz && cat_mtime[p] == mt) {
                print p, sz, mt, cat_pack[p] > kept_out
            } else {
                print p > delta_out
                print p, sz, mt, "__NEW_PACK__" > kept_out
            }
        }
    ' "$scratch/catalog.sorted" "$scratch/live.tsv"

    [[ -f "$scratch/delta.paths" ]] || : >"$scratch/delta.paths"
    [[ -f "$scratch/kept.tsv" ]] || : >"$scratch/kept.tsv"

    if [[ -s "$scratch/delta.paths" ]]; then
        local next_seq=1 existing_last
        existing_last=$(find "$state_packs" -maxdepth 1 -type f -name "pack-${today_utc}-*.tar" -printf '%f\n' 2>/dev/null | sort | tail -n 1 || true)
        if [[ -n $existing_last && $existing_last =~ ^pack-[0-9-]+-([0-9]{6})\.tar$ ]]; then
            next_seq=$((10#${BASH_REMATCH[1]} + 1))
        fi
        local new_pack
        new_pack=$(printf 'pack-%s-%06d.tar' "$today_utc" "$next_seq")
        # Ignore transient vanish if VideoRetention prunes an old frame mid-scan
        (cd /state && tar --ignore-failed-read --warning=no-file-changed --warning=no-file-removed \
            -cf "$state_packs/$new_pack.tmp" --files-from "$scratch/delta.paths") || {
            local rc=$?
            ((rc <= 1)) || fail "Failed creating incremental state pack $new_pack (tar exit $rc)."
        }
        mv -f -- "$state_packs/$new_pack.tmp" "$state_packs/$new_pack"
        printf '%s  %s\n' "$(sha256_file "$state_packs/$new_pack")" "$new_pack" >"$state_packs/$new_pack.sha256"
        sed "s/__NEW_PACK__/$new_pack/g" "$scratch/kept.tsv" >"$catalog_file.tmp"
    else
        cp -f -- "$scratch/kept.tsv" "$catalog_file.tmp"
    fi
    mv -f -- "$catalog_file.tmp" "$catalog_file"

    coalesce_state_packs_if_needed "$state_packs" "$catalog_file" "$today_utc" "$scratch"

    # Record only state packs actively referenced by catalog.tsv, and garbage-collect unreferenced state packs
    cut -f4 "$catalog_file" | LC_ALL=C sort -u >"$scratch/referenced_state_packs"
    local sp sp_base sp_sha
    for sp in "$state_packs"/pack-*.tar; do
        [[ -f $sp ]] || continue
        sp_base=${sp##*/}
        if grep -Fxq -- "$sp_base" "$scratch/referenced_state_packs"; then
            if [[ ! -f "$sp.sha256" ]]; then
                printf '%s  %s\n' "$(sha256_file "$sp")" "$sp_base" >"$sp.sha256"
            fi
            sp_sha=$(awk '{print $1; exit}' "$sp.sha256")
            printf '%s  packs/state/%s\n' "$sp_sha" "$sp_base" >>"$work/pack-index.txt"
        else
            rm -f -- "$sp" "$sp.sha256"
        fi
    done
    LC_ALL=C sort -k2,2 "$work/pack-index.txt" -o "$work/pack-index.txt"

    # 3. Mutable State Tar (everything in /state except image symlinks, scratch, archive, and the 5 immutable prefixes)
    (
        cd /state
        tar --ignore-failed-read --warning=no-file-changed --warning=no-file-removed \
            --exclude='./archive' --exclude='./backups' --exclude='./duckdb-tmp' \
            --exclude='./lib' --exclude='./web' --exclude='./rules' --exclude='./models' \
            --exclude='./documentation' --exclude='./trusted_certificates' --exclude='./config' \
            --exclude='./logback.xml' --exclude='./.cache' --exclude='./logs' \
            --exclude='./.moduledata/usb-backup-control' \
            --exclude='./files/videos/clips' --exclude='./files/videos/streams' \
            --exclude='./files/dailyfiles' \
            --exclude='./files/.dailyfile-journal/segments' \
            --exclude='./files/videos/retained-media/v1/events' \
            --exclude='./files/ocr/crops' \
            --exclude='./files/adjudication' \
            --exclude='./files/reports' \
            -cf "$work/mutable-state.tar" .
    ) || {
        local mrc=$?
        ((mrc <= 1)) || fail "Failed capturing mutable OSCAR state (tar exit $mrc)."
    }

    # 4. Encrypted Deployment Credentials (.env, secrets/, tls/, optional remote-access/)
    mkdir -p "$scratch/secret-stage/secrets" "$scratch/secret-stage/tls"
    cp -f /deployment/.env "$scratch/secret-stage/.env"
    cp -f /backup-key.txt "$scratch/secret-stage/secrets/backup-key.txt"
    for sec in oscar-admin-password.txt oscar-db-password.txt postgres-bootstrap-password.txt; do
        [[ -f "/deployment/secrets/$sec" ]] || fail "Missing required secret: $sec"
        cp -f "/deployment/secrets/$sec" "$scratch/secret-stage/secrets/$sec"
    done
    cp -f /deployment/tls/server.crt /deployment/tls/server.key "$scratch/secret-stage/tls/"
    if [[ -d /remote-access-src && -f /remote-access-src/octelium.env && ! -L /remote-access-src/octelium.env ]]; then
        mkdir -p "$scratch/secret-stage/remote-access"
        cp -f /remote-access-src/octelium.env "$scratch/secret-stage/remote-access/octelium.env"
        if [[ -f /remote-access-src/octelium-token.txt && ! -L /remote-access-src/octelium-token.txt ]]; then
            cp -f /remote-access-src/octelium-token.txt "$scratch/secret-stage/remote-access/octelium-token.txt"
        fi
    fi
    tar -C "$scratch/secret-stage" -czf "$scratch/secrets.tar.gz" .
    openssl enc -aes-256-cbc -pbkdf2 -salt -pass file:/backup-key.txt \
        -in "$scratch/secrets.tar.gz" -out "$work/deployment-secrets.tar.gz.enc"
    rm -rf -- "$scratch/secret-stage" "$scratch/secrets.tar.gz"

    # 5. Release Config Archive & Epoch Metadata
    local -a rel_files=()
    local candidate
    for candidate in .dockerignore .env.example DEPLOYMENT.md QUICKSTART.md compose.yaml compose.octelium.yaml \
        oscar.sh oscar.bat oscar-setup.sh oscar-setup.ps1 oscar-storage.sh oscar-storage.ps1 \
        oscar-usb-backup.sh oscar-usb-backup.ps1 oscar-usb-backup-engine.sh \
        configure-ubuntu-host.sh configure-windows-host.ps1 validate-storage-archive.sh; do
        [[ -f "/deployment/$candidate" ]] && rel_files+=("$candidate")
    done
    tar -C /deployment -czf "$work/release-config.tar.gz" "${rel_files[@]}"

    local archive_pack_count state_pack_count imm_file_count
    archive_pack_count=$(grep -c '  packs/archive/' "$work/pack-index.txt" || true)
    state_pack_count=$(grep -c '  packs/state/' "$work/pack-index.txt" || true)
    imm_file_count=$(wc -l <"$scratch/live.tsv" | tr -d '[:space:]')

    cat >"$work/epoch.json" <<EOF
{
  "format": "oscar-usb-incremental-backup",
  "version": 1,
  "backupEpochId": "$epoch_id",
  "snapshotId": "$snapshot_id",
  "deploymentId": "$deployment_id",
  "oscarVersion": "$oscar_version",
  "backupMode": "$backup_mode",
  "createdAt": "$timestamp_iso",
  "postgresLsn": "$postgres_lsn",
  "archivePackCount": $archive_pack_count,
  "statePackCount": $state_pack_count,
  "immutableStateFileCount": $imm_file_count
}
EOF

    # 6. Snapshot SHA256SUMS + HMAC-SHA256
    (
        cd "$work"
        find . -type f ! -name SHA256SUMS ! -name SHA256SUMS.hmac ! -name VERIFIED -print0 | LC_ALL=C sort -z |
            xargs -0 sha256sum >SHA256SUMS
    )
    hmac_file_base64 "$work/SHA256SUMS" /backup-key.txt >"$work/SHA256SUMS.hmac"
    printf '\n' >>"$work/SHA256SUMS.hmac"
    sync
}

cmd_commit_latest() {
    local snapshot_id=${1:?missing snapshot_id}
    local timestamp_iso=${2:?missing timestamp_iso}
    local backup_root=/backup/OSCAR-Backup
    local snap_dir="$backup_root/snapshots/$snapshot_id"
    [[ -d $snap_dir && -f "$snap_dir/SHA256SUMS.hmac" ]] || fail "Snapshot is incomplete: $snapshot_id"

    printf 'verified_at=%s\nsnapshot_id=%s\n' "$timestamp_iso" "$snapshot_id" >"$snap_dir/VERIFIED"

    local body_tmp="$backup_root/.LATEST.body.$$"
    local pointer_tmp="$backup_root/.LATEST.tmp.$$"
    printf 'format=oscar-usb-latest\nversion=1\nsnapshot_id=%s\n' "$snapshot_id" >"$body_tmp"
    local mac
    mac=$(hmac_file_base64 "$body_tmp" /backup-key.txt)
    {
        cat "$body_tmp"
        printf 'hmac_sha256=%s\n' "$mac"
    } >"$pointer_tmp"
    rm -f -- "$body_tmp"
    sync
    mv -f -- "$pointer_tmp" "$backup_root/LATEST"
    sync

    # Prune prior snapshots only AFTER LATEST atomically points to the new verified snapshot
    local old_dir old_base
    for old_dir in "$backup_root/snapshots"/*; do
        [[ -d $old_dir ]] || continue
        old_base=${old_dir##*/}
        [[ $old_base == "$snapshot_id" ]] && continue
        rm -rf -- "$old_dir"
    done
    chmod -R a+rX "$backup_root" 2>/dev/null || true
    sync
}

cmd_verify_snapshot() {
    local deep=${1:-false}
    local backup_root=/backup/OSCAR-Backup
    [[ -f "$backup_root/LATEST" ]] || fail "Missing $backup_root/LATEST pointer."

    local snap_id expected_mac actual_mac
    local scratch="$ENGINE_SCRATCH/verify"
    mkdir -p "$scratch"

    tr -d '\r' <"$backup_root/LATEST" >"$scratch/LATEST.clean"
    head -n 3 "$scratch/LATEST.clean" >"$scratch/LATEST.body"
    snap_id=$(awk -F= '$1 == "snapshot_id" { print substr($0, index($0, "=") + 1); exit }' "$scratch/LATEST.clean")
    expected_mac=$(awk -F= '$1 == "hmac_sha256" { print substr($0, index($0, "=") + 1); exit }' "$scratch/LATEST.clean")
    [[ $snap_id =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$ ]] || fail "Invalid snapshot_id in LATEST: $snap_id"
    actual_mac=$(hmac_file_base64 "$scratch/LATEST.body" /backup-key.txt)
    [[ $actual_mac == "$expected_mac" ]] || fail 'LATEST pointer HMAC authentication failed (wrong backup-key.txt or tampered pointer).'

    local snap_dir="$backup_root/snapshots/$snap_id"
    [[ -d $snap_dir ]] || fail "Snapshot directory missing: $snap_dir"
    local sums_mac_expected sums_mac_actual
    sums_mac_expected=$(tr -d '[:space:]' <"$snap_dir/SHA256SUMS.hmac")
    sums_mac_actual=$(hmac_file_base64 "$snap_dir/SHA256SUMS" /backup-key.txt)
    [[ $sums_mac_actual == "$sums_mac_expected" ]] || fail "Snapshot $snap_id SHA256SUMS.hmac authentication failed."

    (cd "$snap_dir" && sha256sum -c SHA256SUMS >/dev/null) || fail "Snapshot $snap_id payload SHA-256 mismatch."

    # Verify every referenced pack exists (and check sidecar or full SHA-256 when --deep)
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -n $line ]] || continue
        local expected_sha=${line%%  *}
        local rel_pack=${line#*  }
        local full_pack="$backup_root/$rel_pack"
        [[ -f $full_pack ]] || fail "Referenced pack is missing: $rel_pack"
        if [[ $deep == true ]]; then
            [[ $(sha256_file "$full_pack") == "$expected_sha" ]] || fail "Deep SHA-256 mismatch in pack: $rel_pack"
        elif [[ -f "$full_pack.sha256" ]]; then
            local recorded_sha
            recorded_sha=$(awk '{print $1; exit}' "$full_pack.sha256")
            [[ $recorded_sha == "$expected_sha" ]] || fail "Pack sidecar SHA-256 mismatch: $rel_pack"
        fi
    done <"$snap_dir/pack-index.txt"

    # Verify secret bundle decrypts cleanly and contains .env + secrets + tls
    mkdir -p "$scratch/secrets-check"
    openssl enc -d -aes-256-cbc -pbkdf2 -pass file:/backup-key.txt \
        -in "$snap_dir/deployment-secrets.tar.gz.enc" | tar -C "$scratch/secrets-check" -xzf -
    [[ -f "$scratch/secrets-check/.env" && -f "$scratch/secrets-check/tls/server.crt" && -f "$scratch/secrets-check/tls/server.key" ]] ||
        fail 'Decrypted secret archive is missing .env or TLS key material.'

    printf '%s\n' "$snap_id"
}

cmd_decrypt_credentials() {
    local snap_id=${1:?missing snapshot_id}
    local snap_dir="/backup/OSCAR-Backup/snapshots/$snap_id"
    openssl enc -d -aes-256-cbc -pbkdf2 -pass file:/backup-key.txt \
        -in "$snap_dir/deployment-secrets.tar.gz.enc" | tar -C /restore-creds --no-same-owner -xzf -
    chmod -R u+rwX,go-rwx /restore-creds
}

cmd_extract_restore() {
    local snap_id=${1:?missing snapshot_id}
    local backup_root=/backup/OSCAR-Backup
    local snap_dir="$backup_root/snapshots/$snap_id"
    local scratch="$ENGINE_SCRATCH/restore"
    mkdir -p "$scratch"

    # 1. Restore Parquet cold archive
    find /archive -mindepth 1 -maxdepth 1 ! -name '.oscar-storage-root' -exec rm -rf -- {} +
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -n $line ]] || continue
        local rel_pack=${line#*  }
        case $rel_pack in
            packs/archive/*.tar)
                tar -C /archive --no-same-owner -xf "$backup_root/$rel_pack"
                ;;
        esac
    done <"$snap_dir/pack-index.txt"
    if [[ -f "$snap_dir/archive-recent.tar" ]]; then
        tar -C /archive --no-same-owner -xf "$snap_dir/archive-recent.tar"
    fi
    chown -R 10001:10001 /archive/datasets 2>/dev/null || true

    # 2. Restore OSCAR state (mutable base state -> immutable packs in chronological order -> prune unlinked)
    find /state -mindepth 1 -maxdepth 1 ! -name 'archive' -exec rm -rf -- {} +
    tar -C /state --no-same-owner -xf "$snap_dir/mutable-state.tar"
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -n $line ]] || continue
        local rel_pack=${line#*  }
        case $rel_pack in
            packs/state/*.tar)
                tar -C /state --no-same-owner -xf "$backup_root/$rel_pack"
                ;;
        esac
    done < <(grep '  packs/state/' "$snap_dir/pack-index.txt" | LC_ALL=C sort -k2,2 || true)

    # Prune any immutable files that were unlinked (e.g. Day-30 secondary JPEGs) prior to snapshot
    gzip -dc "$snap_dir/live-immutable-paths.txt.gz" | LC_ALL=C sort -u >"$scratch/live.expected"
    : >"$scratch/live.extracted"
    local rel_root
    for rel_root in "files/dailyfiles" "files/.dailyfile-journal/segments" "files/videos/retained-media/v1/events" "files/ocr/crops" "files/adjudication" "files/reports"; do
        if [[ -d "/state/$rel_root" ]]; then
            (cd /state && find "$rel_root" -type f -printf '%p\n' 2>/dev/null) >>"$scratch/live.extracted" || true
        fi
    done
    LC_ALL=C sort -u "$scratch/live.extracted" -o "$scratch/live.extracted"
    LC_ALL=C comm -23 "$scratch/live.extracted" "$scratch/live.expected" >"$scratch/to_prune"
    if [[ -s "$scratch/to_prune" ]]; then
        (cd /state && xargs -d '\n' rm -f -- <"$scratch/to_prune")
    fi

    for link_name in lib web rules models documentation trusted_certificates config logback.xml; do
        rm -rf -- "/state/$link_name"
        ln -s "/opt/oscar/$link_name" "/state/$link_name"
    done
    chown -R 10001:10001 /state
    [[ -f /state/config.json ]] && chmod 0600 /state/config.json || true
    sync
}

subcmd=${1:-}
shift || true
case $subcmd in
    write-helpers) write_carrier_helpers "${1:-/backup}" ;;
    pack-sync) cmd_pack_sync "$@" ;;
    commit-latest) cmd_commit_latest "$@" ;;
    verify-snapshot) cmd_verify_snapshot "$@" ;;
    decrypt-credentials) cmd_decrypt_credentials "$@" ;;
    extract-restore) cmd_extract_restore "$@" ;;
    *) fail "Unknown engine subcommand: $subcmd" ;;
esac
