#!/usr/bin/env bash
# End-to-end integration test for OSCAR Continual & Occasional USB NVMe Backup,
# mode switching, safe USB eject -> laptop copy -> reconnect catch-up, and
# bare-metal restore onto a brand-new server.
set -Eeuo pipefail
trap 'echo "TEST FAILED AT LINE $LINENO: $BASH_COMMAND" >&2' ERR

repo_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
work_root=$(mktemp -d "${TMPDIR:-/tmp}/oscar-usb-e2e.XXXXXX")
proj_src="oscar_usbe2e_src_$$"
proj_dst="oscar_usbe2e_dst_$$"
vol_state_src="${proj_src}_state"
vol_pg_src="${proj_src}_pg"
vol_state_dst="${proj_dst}_state"
vol_pg_dst="${proj_dst}_pg"

cleanup() {
    local rc=$?
    if ((rc != 0)); then
        docker compose --project-name "$proj_dst" --project-directory "$work_root/server-b" --env-file "$work_root/server-b/.env" --file "$work_root/server-b/compose.yaml" logs postgres 2>&1 || true
    fi
    for d in "$work_root/server-a" "$work_root/server-b"; do
        if [[ -f "$d/compose.yaml" && -f "$d/.env" ]]; then
            docker compose --project-name "${d##*-}" --project-directory "$d" --env-file "$d/.env" --file "$d/compose.yaml" down -v >/dev/null 2>&1 || true
        fi
    done
    docker compose --project-name "$proj_src" --file "$work_root/server-a/compose.yaml" down >/dev/null 2>&1 || true
    docker compose --project-name "$proj_dst" --file "$work_root/server-b/compose.yaml" down >/dev/null 2>&1 || true
    docker volume rm -f "$vol_state_src" "$vol_pg_src" "$vol_state_dst" "$vol_pg_dst" >/dev/null 2>&1 || true
    docker run --rm --user 0:0 --volume "$work_root:/w" --entrypoint sh "oscar:${ver:-3.11.0}" -c 'rm -rf /w/*' >/dev/null 2>&1 || true
    rm -rf -- "$work_root"
    exit "$rc"
}
trap cleanup EXIT HUP INT TERM

ver=$(awk -F'"' '/^[[:space:]]*version[[:space:]]*=/ { print $2; exit }' "$repo_root/build.gradle")
docker image inspect "oscar:$ver" >/dev/null 2>&1 || { echo "SKIP: oscar:$ver image not present locally"; exit 0; }
docker image inspect "oscar-postgis:$ver" >/dev/null 2>&1 || { echo "SKIP: oscar-postgis:$ver image not present locally"; exit 0; }

echo "=== [1/6] Setting up isolated source server ($proj_src) ==="
mkdir -p "$work_root/server-a" "$work_root/server-b" "$work_root/usb-ssd" "$work_root/laptop-copy" "$work_root/escrow"
cp -a "$repo_root/dist/release/." "$work_root/server-a/"
cp -a "$repo_root/dist/release/." "$work_root/server-b/"

# Rewrite compose.yaml in server-a and server-b to use isolated external volumes & ephemeral high ports
python3 - "$work_root/server-a/compose.yaml" "$vol_state_src" "$vol_pg_src" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
txt = p.read_text()
txt = txt.replace("name: oscar_oscar_state", f"name: {sys.argv[2]}")
txt = txt.replace("name: oscar_postgres_data", f"name: {sys.argv[3]}")
txt = re.sub(r'^\s*-\s*"80:8080"\s*\n', '', txt, flags=re.M)
p.write_text(txt)
PY
python3 - "$work_root/server-b/compose.yaml" "$vol_state_dst" "$vol_pg_dst" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
txt = p.read_text()
txt = txt.replace("name: oscar_oscar_state", f"name: {sys.argv[2]}")
txt = txt.replace("name: oscar_postgres_data", f"name: {sys.argv[3]}")
txt = re.sub(r'^\s*-\s*"80:8080"\s*\n', '', txt, flags=re.M)
p.write_text(txt)
PY

dep_id="11111111-2222-4333-8444-555555555555"
arch_a="$work_root/storage-a/archive"
arch_b="$work_root/storage-b/archive"
mkdir -p "$arch_a/datasets/observations/date=2026-10-01/profile=RAW_GATED" "$work_root/server-a/secrets" "$work_root/server-a/tls"
printf 'PARQUET_GEN_1_PAYLOAD\n' >"$arch_a/datasets/observations/date=2026-10-01/profile=RAW_GATED/gen-001.parquet"
cat >"$arch_a/.oscar-storage-root" <<EOF
format=oscar-storage-root-identity
version=1
deployment_id=$dep_id
root_kind=archive
adoption=new
claimed_at=2026-10-01T00:00:00Z
adopted_at=none
adopted_by=none
EOF
chmod 0600 "$arch_a/.oscar-storage-root"

cat >"$work_root/server-a/.env" <<EOF
OSCAR_VERSION=$ver
OSCAR_DEPLOYMENT_ID=$dep_id
OSCAR_HOSTNAME=oscar-test.local
OSCAR_HTTPS_PORT=18443
OSCAR_TIMEZONE=UTC
OSCAR_ARCHIVE_DIR=$arch_a
OSCAR_BACKUP_MODE=disabled
OSCAR_SECRETS_DIR=./secrets
OSCAR_TLS_DIR=./tls
OSCAR_BACKUP_KEY_FILE=./secrets/backup-key.txt
EOF

printf 'test-admin-pass\n' >"$work_root/server-a/secrets/oscar-admin-password.txt"
printf 'test-db-pass\n' >"$work_root/server-a/secrets/oscar-db-password.txt"
printf 'test-pg-boot-pass\n' >"$work_root/server-a/secrets/postgres-bootstrap-password.txt"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=oscar-test.local" \
    -keyout "$work_root/server-a/tls/server.key" -out "$work_root/server-a/tls/server.crt" >/dev/null 2>&1

docker volume create --label "com.botts.oscar.deployment-id=$dep_id" "$vol_state_src" >/dev/null
docker volume create --label "com.botts.oscar.deployment-id=$dep_id" "$vol_pg_src" >/dev/null

# Populate initial state volume (including frame-01.jpg + frame-03.jpg + dailyfile CSV + config.json)
docker run --rm --user 0:0 --volume "$vol_state_src:/state" --entrypoint sh "oscar:$ver" -eu -c '
    mkdir -p /state/.moduledata /state/files/dailyfiles /state/files/videos/retained-media/v1/events/ev1 /state/files/ocr/crops/2026-11-18
    printf "[{\"id\":\"seed\"}]\n" >/state/config.json
    printf "{\"users\":[\"admin\"]}\n" >/state/.moduledata/oscar-identity.json
    printf "lane1,2026-11-18,initial\n" >/state/files/dailyfiles/lane-01_2026-11-18.csv
    printf "FRAME01_SECONDARY\n" >/state/files/videos/retained-media/v1/events/ev1/frame-01.jpg
    printf "FRAME03_PRIMARY\n" >/state/files/videos/retained-media/v1/events/ev1/frame-03.jpg
    printf "OCR_CROP_1\n" >/state/files/ocr/crops/2026-11-18/crop1.jpg
    chown -R 10001:10001 /state
'

docker compose --project-name "$proj_src" --project-directory "$work_root/server-a" \
    --env-file "$work_root/server-a/.env" --file "$work_root/server-a/compose.yaml" \
    up --detach --no-build --pull never --wait postgres

pg_cid_a=$(docker compose --project-name "$proj_src" --project-directory "$work_root/server-a" \
    --env-file "$work_root/server-a/.env" --file "$work_root/server-a/compose.yaml" ps --quiet postgres | tr -d '[:space:]')
for _pg_try in {1..30}; do
    docker exec "$pg_cid_a" sh -c 'PGPASSWORD=test-pg-boot-pass psql -U oscar_bootstrap -d gis -c "SELECT 1"' >/dev/null 2>&1 && break
    sleep 1
done
docker exec "$pg_cid_a" sh -c 'PGPASSWORD=test-pg-boot-pass psql -U oscar_bootstrap -d gis -c "CREATE TABLE usb_test_audit(id serial primary key, note text); INSERT INTO usb_test_audit(note) VALUES ('\''before_eject'\'');"' >/dev/null

run_usb_a() {
    OSCAR_USB_BACKUP_ALLOW_NONROOT=1 \
    OSCAR_USB_BACKUP_SKIP_SYSTEMD=1 \
    OSCAR_USB_BACKUP_CONFIG="$work_root/usb-a.env" \
    OSCAR_STORAGE_LOCK_DIR="$work_root/locks" \
    OSCAR_COMPOSE_PROJECT_NAME="$proj_src" \
    OSCAR_STATE_VOLUME="$vol_state_src" \
    OSCAR_POSTGRES_VOLUME="$vol_pg_src" \
    bash "$work_root/server-a/oscar-setup.sh" usb-backup "$@"
}

echo "=== [2/6] Testing prepare-drive (continual mode) & O(1) immutable pack skip ==="
run_usb_a prepare-drive --path "$work_root/usb-ssd" --mode continual --interval-minutes 15
cp -f "$work_root/server-a/secrets/backup-key.txt" "$work_root/escrow/backup-key.txt"

[[ -f "$work_root/usb-ssd/README-DATA-ADMIN.txt" ]]
[[ -f "$work_root/usb-ssd/COPY-TO-ANOTHER-DRIVE.bat" ]]
[[ -x "$work_root/usb-ssd/copy-to-another-drive.sh" ]]
[[ -f "$work_root/usb-ssd/OSCAR-Backup/packs/archive/archive-2026-10-01.tar" ]]

pack_mtime_before=$(stat -c %Y "$work_root/usb-ssd/OSCAR-Backup/packs/archive/archive-2026-10-01.tar")
sleep 2
run_usb_a sync
pack_mtime_after=$(stat -c %Y "$work_root/usb-ssd/OSCAR-Backup/packs/archive/archive-2026-10-01.tar")
[[ $pack_mtime_before == "$pack_mtime_after" ]] || { echo "FAIL: historical archive pack was rewritten!"; exit 1; }

echo "=== [3/6] Testing seamless mode switching (continual <-> occasional <-> disabled) ==="
run_usb_a mode occasional
grep -Fq "Configured Mode:       occasional" <<<"$(run_usb_a status)"
run_usb_a mode disabled
grep -Fq "Configured Mode:       disabled" <<<"$(run_usb_a status)"
run_usb_a mode continual --interval-minutes 10
grep -Fq "Configured Mode:       continual" <<<"$(run_usb_a status)"

echo "=== [4/6] Testing Field Data Admin eject -> laptop copy -> record while unplugged ==="
run_usb_a eject
grep -Fq "DETACHED" <<<"$(run_usb_a status)"
# Background timer tick while unplugged must succeed cleanly with exit 0
grep -Fq "DETACHED" <<<"$(run_usb_a sync --if-attached)"

# Laptop Visit #1 copy
grep -Fq "VERIFIED OK" <<<"$(bash "$work_root/usb-ssd/copy-to-another-drive.sh" "$work_root/laptop-copy")"

# Simulate new portal data arriving WHILE the USB SSD is unplugged (plus Day-30 secondary frame pruning!)
docker exec "$pg_cid_a" sh -c 'PGPASSWORD=test-pg-boot-pass psql -U oscar_bootstrap -d gis -c "INSERT INTO usb_test_audit(note) VALUES ('\''recorded_while_usb_unplugged'\'');"' >/dev/null
mkdir -p "$arch_a/datasets/observations/date=2026-10-02/profile=RAW_GATED"
printf 'PARQUET_GEN_2_WHILE_UNPLUGGED\n' >"$arch_a/datasets/observations/date=2026-10-02/profile=RAW_GATED/gen-002.parquet"
docker run --rm --user 0:0 --volume "$vol_state_src:/state" --entrypoint sh "oscar:$ver" -eu -c '
    rm -f /state/files/videos/retained-media/v1/events/ev1/frame-01.jpg
    mkdir -p /state/files/videos/retained-media/v1/events/ev2
    printf "FRAME03_WHILE_UNPLUGGED\n" >/state/files/videos/retained-media/v1/events/ev2/frame-03.jpg
    printf "lane1,2026-11-19,while_unplugged\n" >/state/files/dailyfiles/lane-01_2026-11-19.csv
    chown -R 10001:10001 /state
'

echo "=== [5/6] Plugging USB SSD back in (attach), exercising Admin UI host agent queue, & delta-copying to laptop drive ==="
run_usb_a attach
[[ -f "$work_root/usb-ssd/OSCAR-Backup/packs/archive/archive-2026-10-02.tar" ]]

# Exercise Admin Panel control queue (agent-tick: refresh-status, export-backup-key, set-mode, eject -> SAFE_TO_UNPLUG, attach -> ATTACHED)
ctrl_dir="$work_root/usb-control"
mkdir -p "$ctrl_dir"
cat >"$ctrl_dir/request.json" <<'EOF'
{"requestId":"req-key-0001","requestedBy":"admin","action":"export-backup-key"}
EOF
OSCAR_USB_CONTROL_DIR="$ctrl_dir" run_usb_a agent-tick
[[ -s "$ctrl_dir/escrow-req-key-0001.key" ]] || { echo "FAIL: agent-tick did not export backup key"; exit 1; }
cmp -s "$ctrl_dir/escrow-req-key-0001.key" "$work_root/escrow/backup-key.txt" || { echo "FAIL: exported key mismatch"; exit 1; }
rm -f "$ctrl_dir/escrow-req-key-0001.key"

cat >"$ctrl_dir/request.json" <<'EOF'
{"requestId":"req-eject-0002","requestedBy":"admin","action":"eject","noSync":true}
EOF
OSCAR_USB_CONTROL_DIR="$ctrl_dir" run_usb_a agent-tick
grep -Fq '"driveState": "SAFE_TO_UNPLUG"' "$ctrl_dir/status.json" || { echo "FAIL: expected SAFE_TO_UNPLUG in status.json"; cat "$ctrl_dir/status.json"; exit 1; }

cat >"$ctrl_dir/request.json" <<'EOF'
{"requestId":"req-attach-0003","requestedBy":"admin","action":"attach"}
EOF
OSCAR_USB_CONTROL_DIR="$ctrl_dir" run_usb_a agent-tick
grep -Fq '"driveState": "ATTACHED"' "$ctrl_dir/status.json" || { echo "FAIL: expected ATTACHED in status.json"; cat "$ctrl_dir/status.json"; exit 1; }

grep -Fq "VERIFIED OK" <<<"$(bash "$work_root/usb-ssd/copy-to-another-drive.sh" "$work_root/laptop-copy")"

# Stop source server before spinning up replacement server
docker compose --project-name "$proj_src" --project-directory "$work_root/server-a" \
    --env-file "$work_root/server-a/.env" --file "$work_root/server-a/compose.yaml" down >/dev/null

echo "=== [6/6] Restoring laptop copy onto brand-new UNINITIALIZED server ($proj_dst) ==="
# Override port on restored .env after decrypt? Wait: server-a already used port 18443 which is now free!
OSCAR_USB_BACKUP_ALLOW_NONROOT=1 \
OSCAR_USB_BACKUP_SKIP_SYSTEMD=1 \
OSCAR_USB_RESTORE_POSTGRES_ONLY=1 \
OSCAR_USB_BACKUP_CONFIG="$work_root/usb-b.env" \
OSCAR_STORAGE_LOCK_DIR="$work_root/locks" \
OSCAR_COMPOSE_PROJECT_NAME="$proj_dst" \
OSCAR_STATE_VOLUME="$vol_state_dst" \
OSCAR_POSTGRES_VOLUME="$vol_pg_dst" \
bash "$work_root/server-b/oscar-setup.sh" usb-backup restore \
    --from "$work_root/laptop-copy" \
    --backup-key "$work_root/escrow/backup-key.txt" \
    --archive-dir "$arch_b" \
    --confirm RESTORE

# Verify every piece of historical + while-unplugged state on the brand-new replacement machine!
pg_cid_b=$(docker compose --project-name "$proj_dst" --project-directory "$work_root/server-b" \
    --env-file "$work_root/server-b/.env" --file "$work_root/server-b/compose.yaml" ps --quiet postgres | tr -d '[:space:]')
for _pg_try in {1..30}; do
    docker exec "$pg_cid_b" sh -c 'PGPASSWORD=test-pg-boot-pass psql -U oscar_bootstrap -d gis -c "SELECT 1"' >/dev/null 2>&1 && break
    sleep 1
done
notes=$(docker exec "$pg_cid_b" sh -c 'PGPASSWORD=test-pg-boot-pass psql -U oscar_bootstrap -d gis -tAc "SELECT note FROM usb_test_audit ORDER BY id;"' | tr '\n' ',')
[[ $notes == "before_eject,recorded_while_usb_unplugged," ]] || { echo "FAIL: restored DB rows mismatch: $notes"; exit 1; }

# Prove non-root OSCAR runtime user (10001:10001) can read every restored cold Parquet generation & state file!
docker run --rm --user 10001:10001 --volume "$arch_b:/archive:ro" --volume "$vol_state_dst:/state:ro" --entrypoint sh "oscar:$ver" -eu -c '
    test "$(cat /archive/datasets/observations/date=2026-10-01/profile=RAW_GATED/gen-001.parquet)" = "PARQUET_GEN_1_PAYLOAD"
    test "$(cat /archive/datasets/observations/date=2026-10-02/profile=RAW_GATED/gen-002.parquet)" = "PARQUET_GEN_2_WHILE_UNPLUGGED"
    test -f /state/files/dailyfiles/lane-01_2026-11-18.csv
    test -f /state/files/dailyfiles/lane-01_2026-11-19.csv
    test -f /state/files/videos/retained-media/v1/events/ev1/frame-03.jpg
    test -f /state/files/videos/retained-media/v1/events/ev2/frame-03.jpg
    test ! -e /state/files/videos/retained-media/v1/events/ev1/frame-01.jpg
    test -f /state/.moduledata/oscar-identity.json
'

[[ $(wc -l <"$arch_b/.oscar-storage-root" | tr -d '[:space:]') == 8 &&
   $(grep -Fxc 'format=oscar-storage-root-identity' "$arch_b/.oscar-storage-root") == 1 &&
   $(grep -Fxc 'version=1' "$arch_b/.oscar-storage-root") == 1 &&
   $(grep -Fxc "deployment_id=$dep_id" "$arch_b/.oscar-storage-root") == 1 &&
   $(grep -Fxc 'root_kind=archive' "$arch_b/.oscar-storage-root") == 1 &&
   $(grep -Fxc 'adoption=new' "$arch_b/.oscar-storage-root") == 1 &&
   $(grep -Fxc 'adopted_at=none' "$arch_b/.oscar-storage-root") == 1 &&
   $(grep -Fxc 'adopted_by=none' "$arch_b/.oscar-storage-root") == 1 ]] || {
    echo "FAIL: restored .oscar-storage-root did not match canonical 8-line identity schema:"
    cat "$arch_b/.oscar-storage-root"
    exit 1
}

echo "ALL CONTINUAL & OCCASIONAL USB NVMe BACKUP / EJECT / LAPTOP-COPY / CATCH-UP / BARE-METAL RESTORE CHECKS PASSED!"
