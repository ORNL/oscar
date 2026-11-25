#!/usr/bin/env bash
# OSCAR Bare-Metal Ubuntu Server 24.04 LTS Offline Autoinstall USB Builder (Linux: GUI + TUI + CLI)
# Creates a single-stick UEFI (Secure Boot compatible) + Legacy BIOS bootable
# Ubuntu 24.04 Live Server USB drive containing:
#   - Partitions 1-3: Signed Ubuntu 24.04 Live Server ISO image
#   - Partition 4 (CIDATA, FAT32): Declarative cloud-init autoinstall profile
#     with internal-disk pinning and USB-NVMe BOT + No-LPM stability quirks
#   - Partition 5 (OSCAR_MEDIA, NTFS): Air-gapped OSCAR offline-full bundle,
#     SHA-256 checksum, and optional pre-staged seed imports (config.json,
#     lanes.csv, site-network.env, *.pmtiles, backup-key.txt) for first-boot wizard
set -Eeuo pipefail

script_path=${BASH_SOURCE[0]}
[[ ! -L $script_path ]] || { printf 'ERROR: Refusing to execute symlinked script: %s\n' "$script_path" >&2; exit 1; }
case $script_path in */*) script_parent=${script_path%/*} ;; *) script_parent=. ;; esac
ubuntu_dir=$(CDPATH= cd -P -- "$script_parent" && pwd -P)
release_dir=$(CDPATH= cd -P -- "$ubuntu_dir/.." && pwd -P)

template_user_data="$ubuntu_dir/autoinstall/user-data.yaml"
template_meta_data="$ubuntu_dir/autoinstall/meta-data"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

usage() {
    cat <<'EOF'
Usage:
  sudo bash create-autoinstall-usb.sh                             (Interactive whiptail TUI wizard)
  sudo bash create-autoinstall-usb.sh --gui                       (Desktop GTK GUI via zenity, or TUI fallback)
  sudo bash create-autoinstall-usb.sh --tui                       (Force full-screen terminal TUI wizard)
  sudo bash create-autoinstall-usb.sh --list-drives               (List candidate removable USB drives)
  sudo bash create-autoinstall-usb.sh \
      --iso /path/to/ubuntu-24.04.5-live-server-amd64.iso \
      [--offline-bundle /path/to/oscar-3.11.15-ubuntu-x86_64-offline-full.zip] \
      (--device /dev/sdX | --output-image /path/to/autoinstall.img) \
      [--hostname oscar-host] \
      [--username oscaradmin] \
      [--password-hash '$6$...' | --password-file FILE] \
      [--luks-passphrase-file FILE] \
      [--require-sudo-password] \
      [--ssh-key-file ~/.ssh/id_ed25519.pub]... [--ssh-keys-only] \
      [--oscar-admin-password-file FILE | --oscar-admin-password-hash 'PBKDF2WithHmacSHA1:...'] \
      [--lanes-file /path/to/lanes.csv-or-config.json] \
      [--auto-init-oscar] \
      [--seed-dir /path/to/seed-folder] \
      [--seed-file /path/to/config.json]... \
      --confirm ERASE-USB

Safety guarantees:
  - Refuses internal NVMe/SATA/SAS OS drives, root/boot/var/OSCAR storage disks,
    and any drive carrying an OSCAR_BACKUP label.
  - Preserves Canonical/Microsoft UEFI Secure Boot signatures on the Ubuntu ISO.
  - Bakes USB-to-NVMe Bulk-Only Transport + No-LPM quirks into the installed OS
    from first boot and installs the interactive OSCAR First-Boot Provisioning Wizard.
EOF
}

hash_linux_password() {
    local plain=$1
    if command -v openssl >/dev/null 2>&1; then
        printf '%s' "$plain" | openssl passwd -6 -stdin | head -n 1
    else
        python3 - "$plain" <<'PY'
import hashlib, secrets, sys

B64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
pw = sys.argv[1].encode("utf-8")
salt = "".join(B64[b & 0x3F] for b in secrets.token_bytes(16)).encode("ascii")

alt = hashlib.sha512(pw + salt + pw).digest()
a = hashlib.sha512(pw + salt)
cnt = len(pw)
while cnt > 64:
    a.update(alt)
    cnt -= 64
if cnt:
    a.update(alt[:cnt])
cnt = len(pw)
while cnt:
    a.update(alt if (cnt & 1) else pw)
    cnt >>= 1
cur = a.digest()

dp = hashlib.sha512(pw * len(pw)).digest()
p_bytes = (dp * ((len(pw) // 64) + 1))[:len(pw)]
ds = hashlib.sha512(salt * (16 + cur[0])).digest()
s_bytes = (ds * ((len(salt) // 64) + 1))[:len(salt)]

for r in range(5000):
    c = hashlib.sha512()
    c.update(p_bytes if (r & 1) else cur)
    if r % 3:
        c.update(s_bytes)
    if r % 7:
        c.update(p_bytes)
    c.update(cur if (r & 1) else p_bytes)
    cur = c.digest()

def enc(b2, b1, b0, n):
    w = (b2 << 16) | (b1 << 8) | b0
    out = []
    for _ in range(n):
        out.append(B64[w & 0x3F])
        w >>= 6
    return "".join(out)

triples = [
    (cur[0],cur[21],cur[42],4),(cur[22],cur[43],cur[1],4),(cur[44],cur[2],cur[23],4),
    (cur[3],cur[24],cur[45],4),(cur[25],cur[46],cur[4],4),(cur[47],cur[5],cur[26],4),
    (cur[6],cur[27],cur[48],4),(cur[28],cur[49],cur[7],4),(cur[50],cur[8],cur[29],4),
    (cur[9],cur[30],cur[51],4),(cur[31],cur[52],cur[10],4),(cur[53],cur[11],cur[32],4),
    (cur[12],cur[33],cur[54],4),(cur[34],cur[55],cur[13],4),(cur[56],cur[14],cur[35],4),
    (cur[15],cur[36],cur[57],4),(cur[37],cur[58],cur[16],4),(cur[59],cur[17],cur[38],4),
    (cur[18],cur[39],cur[60],4),(cur[40],cur[61],cur[19],4),(cur[62],cur[20],cur[41],4),
    (0,0,cur[63],2)
]
print("$6$" + salt.decode("ascii") + "$" + "".join(enc(*t) for t in triples))
PY
    fi
}

hash_oscar_pbkdf2_password() {
    local plain=$1
    ((${#plain} >= 14)) || fail "Initial OSCAR web administrator password must contain at least 14 characters."
    python3 - "$plain" <<'PY'
import base64, hashlib, os, sys

pw = sys.argv[1].encode("utf-8")
salt = os.urandom(16)
dk = hashlib.pbkdf2_hmac("sha1", pw, salt, 1 << 16, dklen=16)
print(f"# PBKDF2_PREENCODED:PBKDF2WithHmacSHA1:16:{base64.b64encode(salt).decode('ascii')}:{base64.b64encode(dk).decode('ascii')}")
PY
}

protected_disk_names() {
    {
        local p src
        for p in / /boot /boot/efi /var /home "$release_dir"; do
            [[ -e $p ]] || continue
            src=$(findmnt -rn -o SOURCE --target "$p" 2>/dev/null || true)
            [[ $src == /dev/* ]] || continue
            printf '%s\n' "${src#/dev/}"
            lsblk -s -rno NAME "$src" 2>/dev/null || true
        done
        local bdev
        for bdev in $(blkid -L OSCAR_BACKUP 2>/dev/null || true); do
            [[ $bdev == /dev/* ]] || continue
            printf '%s\n' "${bdev#/dev/}"
            lsblk -s -rno NAME "$bdev" 2>/dev/null || true
        done
    } | sort -u
}

list_candidate_usb_disks() {
    local -A prot=()
    local p
    for p in $(protected_disk_names); do
        [[ -n $p ]] && prot[$p]=1
    done

    local line NAME PATH_VAL TYPE TRAN RM SIZE MODEL SERIAL
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        NAME=$(sed -n 's/.*\<NAME="\([^"]*\)".*/\1/p' <<<"$line")
        PATH_VAL=$(sed -n 's/.*\<PATH="\([^"]*\)".*/\1/p' <<<"$line")
        TYPE=$(sed -n 's/.*\<TYPE="\([^"]*\)".*/\1/p' <<<"$line")
        TRAN=$(sed -n 's/.*\<TRAN="\([^"]*\)".*/\1/p' <<<"$line")
        RM=$(sed -n 's/.*\<RM="\([^"]*\)".*/\1/p' <<<"$line")
        SIZE=$(sed -n 's/.*\<SIZE="\([^"]*\)".*/\1/p' <<<"$line")
        MODEL=$(sed -n 's/.*\<MODEL="\([^"]*\)".*/\1/p' <<<"$line")
        SERIAL=$(sed -n 's/.*\<SERIAL="\([^"]*\)".*/\1/p' <<<"$line")
        [[ $TYPE == disk ]] || continue
        [[ -z ${prot[$NAME]:-} ]] || continue
        [[ $NAME != nvme* && $NAME != loop* && $NAME != dm-* && $NAME != md* ]] || continue
        if [[ $TRAN == usb || $RM == 1 ]]; then
            if lsblk -rno LABEL "$PATH_VAL" 2>/dev/null | grep -Fxq 'OSCAR_BACKUP'; then
                continue
            fi
            local sz_gib=$(( ${SIZE:-0} / 1073741824 ))
            printf '%s\t%s GiB\t%s\t%s\n' "$PATH_VAL" "$sz_gib" "${MODEL:-USB Drive}" "${SERIAL:-n/a}"
        fi
    done < <(lsblk -P -b -o NAME,PATH,TYPE,TRAN,RM,SIZE,MODEL,SERIAL -e 7 2>/dev/null || true)
}

validate_safe_usb_device() {
    local dev=$1
    [[ -b $dev ]] || fail "Block device does not exist: $dev"
    local real_dev base_name dev_type tran rm_flag size_bytes
    real_dev=$(realpath -P -- "$dev")
    base_name=${real_dev#/dev/}
    dev_type=$(lsblk -dnro TYPE "$real_dev" 2>/dev/null | tr -d '[:space:]')
    [[ $dev_type == disk ]] || fail "$dev ($real_dev) is a '$dev_type', not a whole disk (pass e.g. /dev/sdb, not /dev/sdb1)."
    [[ $base_name != nvme* ]] || fail "Refusing internal PCIe NVMe device $real_dev."

    local p
    for p in $(protected_disk_names); do
        [[ $p != "$base_name" ]] || fail "Refusing protected OS / OSCAR / backup disk: $real_dev"
    done
    if lsblk -rno LABEL "$real_dev" 2>/dev/null | grep -Fxq 'OSCAR_BACKUP'; then
        fail "Refusing $real_dev because it contains an OSCAR_BACKUP partition."
    fi

    tran=$(lsblk -dnro TRAN "$real_dev" 2>/dev/null | tr -d '[:space:]')
    rm_flag=$(lsblk -dnro RM "$real_dev" 2>/dev/null | tr -d '[:space:]')
    if [[ $tran != usb && $rm_flag != 1 ]]; then
        fail "Refusing non-USB / non-removable disk $real_dev (TRAN=${tran:-none}, RM=${rm_flag:-0})."
    fi

    size_bytes=$(lsblk -bdnro SIZE "$real_dev" 2>/dev/null | tr -d '[:space:]')
    (( size_bytes >= 8 * 1024 * 1024 * 1024 )) || fail "USB drive $real_dev is smaller than 8 GiB (16+ GiB recommended when bundling offline-full.zip)."
}

render_custom_user_data() {
    local out_file=$1 host_val=$2 user_val=$3 pass_hash=$4 luks_pass=$5 req_sudo_pw=$6 ssh_keys_only_flag=$7
    shift 7
    local -a ssh_keys=("$@")

    [[ -f $template_user_data ]] || fail "Missing autoinstall template: $template_user_data"
    python3 - "$template_user_data" "$out_file" "$host_val" "$user_val" "$pass_hash" "$luks_pass" "$req_sudo_pw" "$ssh_keys_only_flag" "${ssh_keys[@]}" <<'PY'
import json, pathlib, re, sys

tpl_path, out_path, hostname, username, pass_hash, luks_pass, req_sudo_pw, ssh_keys_only_flag = sys.argv[1:9]
ssh_keys = [k.strip() for k in sys.argv[9:] if k.strip()]

text = pathlib.Path(tpl_path).read_text(encoding="utf-8")

text = re.sub(r'(^\s*hostname:\s*).*$', rf'\g<1>{hostname}', text, count=1, flags=re.M)
text = re.sub(r'(^\s*username:\s*).*$', rf'\g<1>{username}', text, count=1, flags=re.M)
if pass_hash:
    text = re.sub(r'(^\s*password:\s*).*$', lambda m: f'{m.group(1)}"{pass_hash}"', text, count=1, flags=re.M)

if ssh_keys:
    keys_yaml = "    authorized-keys:\n" + "".join(f'      - "{k}"\n' for k in ssh_keys)
    text = re.sub(r'^\s*authorized-keys:\s*\[\]\s*$', keys_yaml.rstrip('\n'), text, count=1, flags=re.M)

if ssh_keys_only_flag == "true":
    text = re.sub(r'(^\s*allow-pw:\s*).*$', r'\g<1>false', text, count=1, flags=re.M)
    text = text.replace(
        'PermitRootLogin no\\nX11Forwarding no\\nMaxAuthTries 4\\n',
        'PermitRootLogin no\\nPasswordAuthentication no\\nKbdInteractiveAuthentication no\\nX11Forwarding no\\nMaxAuthTries 4\\n',
    )

if luks_pass:
    luks_json = json.dumps(luks_pass)
    text = text.replace(
        '"sizing-policy": "all",\n          "match": {"path": target_disk},',
        f'"sizing-policy": "all",\n          "password": {luks_json},\n          "match": {{"path": target_disk}},',
    )
    text = text.replace(
        "    layout:\n      name: lvm\n      sizing-policy: all",
        f"    layout:\n      name: lvm\n      sizing-policy: all\n      password: {luks_json}",
    )

if req_sudo_pw == "true":
    text = re.sub(r'^\s*-\s*curtin in-target --target=/target -- sh -c \'echo "oscaradmin ALL=\(ALL\) NOPASSWD:ALL".*$\n?', '', text, count=1, flags=re.M)
elif username != "oscaradmin":
    text = text.replace("oscaradmin ALL=(ALL) NOPASSWD:ALL", f"{username} ALL=(ALL) NOPASSWD:ALL")
    text = text.replace("90-oscaradmin", f"90-{username}")

if username != "oscaradmin":
    text = text.replace("chown -R oscaradmin:oscaradmin /srv/oscar", f"chown -R {username}:{username} /srv/oscar")

pathlib.Path(out_path).write_text(text, encoding="utf-8", newline="\n")
PY
}

want_gui=false
want_tui=false
list_only=false
iso_path=''
offline_bundle=''
target_device=''
output_image=''
output_image_size_gib=12
hostname_val='oscar-host'
hostname_explicit=false
username_val='oscaradmin'
username_explicit=false
password_hash=''
password_file=''
luks_passphrase_file=''
luks_passphrase=''
require_sudo_password=false
sudo_explicit=false
ssh_keys_only=false
ssh_keys_only_explicit=false
render_user_data_only=''
confirm_token=''
oscar_admin_pw_plain=''
oscar_admin_pw_file=''
oscar_admin_pw_hash=''
lanes_file=''
auto_init_oscar=false
auto_init_explicit=false
seed_dir=''
declare -a ssh_key_files=()
declare -a seed_files=()

while (($# > 0)); do
    case "$1" in
        --gui) want_gui=true; shift ;;
        --tui) want_tui=true; shift ;;
        --list-drives) list_only=true; shift ;;
        --iso) iso_path=${2:?missing --iso}; shift 2 ;;
        --offline-bundle) offline_bundle=${2:?missing --offline-bundle}; shift 2 ;;
        --device) target_device=${2:?missing --device}; shift 2 ;;
        --output-image) output_image=${2:?missing --output-image}; shift 2 ;;
        --image-size-gib) output_image_size_gib=${2:?missing --image-size-gib}; shift 2 ;;
        --hostname) hostname_val=${2:?missing --hostname}; hostname_explicit=true; shift 2 ;;
        --username) username_val=${2:?missing --username}; username_explicit=true; shift 2 ;;
        --password-hash) password_hash=${2:?missing --password-hash}; shift 2 ;;
        --password-file) password_file=${2:?missing --password-file}; shift 2 ;;
        --luks-passphrase-file) luks_passphrase_file=${2:?missing --luks-passphrase-file}; shift 2 ;;
        --require-sudo-password) require_sudo_password=true; sudo_explicit=true; shift ;;
        --ssh-keys-only) ssh_keys_only=true; ssh_keys_only_explicit=true; shift ;;
        --oscar-admin-password) oscar_admin_pw_plain=${2:?missing --oscar-admin-password}; shift 2 ;;
        --oscar-admin-password-file) oscar_admin_pw_file=${2:?missing --oscar-admin-password-file}; shift 2 ;;
        --oscar-admin-password-hash) oscar_admin_pw_hash=${2:?missing --oscar-admin-password-hash}; shift 2 ;;
        --lanes-file) lanes_file=${2:?missing --lanes-file}; shift 2 ;;
        --auto-init-oscar) auto_init_oscar=true; auto_init_explicit=true; shift ;;
        --render-user-data-only) render_user_data_only=${2:?missing --render-user-data-only}; shift 2 ;;
        --ssh-key-file) ssh_key_files+=("${2:?missing --ssh-key-file}"); shift 2 ;;
        --seed-dir) seed_dir=${2:?missing --seed-dir}; shift 2 ;;
        --seed-file) seed_files+=("${2:?missing --seed-file}"); shift 2 ;;
        --confirm) confirm_token=${2:?missing --confirm}; shift 2 ;;
        -h|--help|help) usage; exit 0 ;;
        *) fail "Unknown option: $1 (run with --help for usage)" ;;
    esac
done

if [[ -n $luks_passphrase_file ]]; then
    [[ -f $luks_passphrase_file ]] || fail "LUKS passphrase file not found: $luks_passphrase_file"
    IFS= read -r luks_passphrase <"$luks_passphrase_file" || true
    luks_passphrase=${luks_passphrase%$'\r'}
    ((${#luks_passphrase} >= 12)) || fail "LUKS full-disk encryption passphrase must contain at least 12 characters."
fi

if [[ -n $password_file ]]; then
    [[ -f $password_file ]] || fail "Password file not found: $password_file"
    IFS= read -r pw_from_file <"$password_file" || true
    pw_from_file=${pw_from_file%$'\r'}
    [[ -n $pw_from_file ]] || fail "Password file is empty: $password_file"
    password_hash=$(hash_linux_password "$pw_from_file")
    unset pw_from_file
fi

if [[ -n $oscar_admin_pw_file ]]; then
    [[ -f $oscar_admin_pw_file ]] || fail "OSCAR admin password file not found: $oscar_admin_pw_file"
    IFS= read -r opw_from_file <"$oscar_admin_pw_file" || true
    opw_from_file=${opw_from_file%$'\r'}
    [[ -n $opw_from_file ]] || fail "OSCAR admin password file is empty: $oscar_admin_pw_file"
    if [[ $opw_from_file == '# PBKDF2_PREENCODED:'* ]]; then
        oscar_admin_pw_hash=$opw_from_file
    elif [[ $opw_from_file == PBKDF2WithHmacSHA1:* ]]; then
        oscar_admin_pw_hash="# PBKDF2_PREENCODED:$opw_from_file"
    else
        oscar_admin_pw_hash=$(hash_oscar_pbkdf2_password "$opw_from_file")
    fi
    unset opw_from_file
elif [[ -n $oscar_admin_pw_plain ]]; then
    oscar_admin_pw_hash=$(hash_oscar_pbkdf2_password "$oscar_admin_pw_plain")
    unset oscar_admin_pw_plain
elif [[ -n $oscar_admin_pw_hash && $oscar_admin_pw_hash != '# PBKDF2_PREENCODED:'* ]]; then
    [[ $oscar_admin_pw_hash == PBKDF2WithHmacSHA1:* ]] || fail "--oscar-admin-password-hash must start with PBKDF2WithHmacSHA1: or '# PBKDF2_PREENCODED:'."
    oscar_admin_pw_hash="# PBKDF2_PREENCODED:$oscar_admin_pw_hash"
fi

if [[ -n $lanes_file ]]; then
    [[ -f $lanes_file ]] || fail "Pre-configured lanes file not found: $lanes_file"
    case "${lanes_file,,}" in
        *.csv|*.json) ;;
        *) fail "--lanes-file must be a .csv lane spreadsheet or .json SensorHub/OSCAR configuration: $lanes_file" ;;
    esac
fi

if [[ -n $render_user_data_only ]]; then
    [[ $hostname_val =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || fail "Invalid --hostname: $hostname_val"
    [[ $username_val =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] || fail "Invalid Linux --username: $username_val"
    declare -a render_keys=()
    for kf in "${ssh_key_files[@]}"; do
        [[ -f $kf ]] || fail "SSH public key file not found: $kf"
        while IFS= read -r line; do
            line=${line%$'\r'}
            [[ -n $line && $line != \#* ]] && render_keys+=("$line")
        done <"$kf"
    done
    if $ssh_keys_only && ((${#render_keys[@]} == 0)); then
        fail "--ssh-keys-only requires at least one --ssh-key-file so you cannot lock yourself out of SSH."
    fi
    render_custom_user_data "$render_user_data_only" "$hostname_val" "$username_val" "$password_hash" "$luks_passphrase" "$require_sudo_password" "$ssh_keys_only" "${render_keys[@]}"
    exit 0
fi

if $list_only; then
    printf 'Protected OS / OSCAR / backup disks (NEVER touched): %s\n\n' "$(protected_disk_names | tr '\n' ' ')"
    printf 'DEVICE\tSIZE\tMODEL\tSERIAL\n'
    list_candidate_usb_disks || true
    exit 0
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    if $want_gui && command -v pkexec >/dev/null 2>&1 && [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
        exec pkexec env DISPLAY="${DISPLAY:-}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" XAUTHORITY="${XAUTHORITY:-}" SUDO_USER="${USER:-}" bash "$ubuntu_dir/create-autoinstall-usb.sh" --gui
    fi
    fail "Run with sudo: sudo bash create-autoinstall-usb.sh (or pass --gui on Ubuntu Desktop)"
fi

[[ $hostname_val =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || fail "Invalid --hostname: $hostname_val"
[[ $username_val =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] || fail "Invalid Linux --username: $username_val"

for req_cmd in dd sgdisk mkfs.vfat python3 sha256sum; do
    command -v "$req_cmd" >/dev/null 2>&1 || fail "Required tool '$req_cmd' is missing (apt-get install -y gdisk dosfstools python3)."
done

has_zenity=false
if $want_gui && ! $want_tui && command -v zenity >/dev/null 2>&1 && [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
    has_zenity=true
fi

has_tui=false
saved_printk_level=''
if ! $has_zenity && [[ -t 0 && -t 1 ]] && command -v whiptail >/dev/null 2>&1 && [[ ${TERM:-dumb} != dumb ]]; then
    has_tui=true
    if [[ -r /proc/sys/kernel/printk && -w /proc/sys/kernel/printk ]]; then
        saved_printk_level=$(awk '{print $1}' /proc/sys/kernel/printk 2>/dev/null || true)
        dmesg --console-off 2>/dev/null || printf '1\n' >/proc/sys/kernel/printk 2>/dev/null || true
    fi
fi

find_default_iso() {
    local cand
    for cand in \
        "$PWD"/ubuntu-24.04*-live-server-amd64.iso \
        "$ubuntu_dir"/ubuntu-24.04*-live-server-amd64.iso \
        "$(dirname "$release_dir")"/ubuntu-24.04*-live-server-amd64.iso \
        "${SUDO_USER:+/home/$SUDO_USER/Downloads}"/ubuntu-24.04*-live-server-amd64.iso \
        /srv/oscar/ubuntu-24.04*-live-server-amd64.iso \
        /tmp/*/ubuntu-24.04*-live-server-amd64.iso \
        /tmp/ubuntu-24.04*-live-server-amd64.iso; do
        if [[ -f $cand ]]; then printf '%s' "$cand"; return 0; fi
    done
}

find_default_bundle() {
    local cand
    for cand in \
        "$PWD"/oscar-*-ubuntu-x86_64-offline-full.zip \
        "$ubuntu_dir"/oscar-*-ubuntu-x86_64-offline-full.zip \
        "$(dirname "$release_dir")"/oscar-*-ubuntu-x86_64-offline-full.zip \
        "${SUDO_USER:+/home/$SUDO_USER/Downloads}"/oscar-*-ubuntu-x86_64-offline-full.zip \
        /srv/oscar/oscar-*-ubuntu-x86_64-offline-full.zip; do
        if [[ -f $cand ]]; then printf '%s' "$cand"; return 0; fi
    done
}

interactive_wizard=false
if [[ $confirm_token != ERASE-USB ]] && { $want_gui || $want_tui || [[ -z $target_device && -z $output_image ]] || [[ -z $iso_path ]]; }; then
    interactive_wizard=true
fi

# Desktop GTK GUI flow via zenity (--gui)
if $has_zenity && $interactive_wizard; then
    mapfile -t usb_rows < <(list_candidate_usb_disks)
    if ((${#usb_rows[@]} == 0)); then
        zenity --error --title="OSCAR Autoinstall USB Creator" \
            --text="No safe removable USB drives (>= 8 GiB) detected.\n\nInsert an external USB flash drive or SSD (16+ GiB recommended) and run again." || true
        exit 1
    fi
    zen_usb_args=()
    first_row=TRUE
    for row in "${usb_rows[@]}"; do
        IFS=$'\t' read -r d_path d_sz d_mod d_ser <<<"$row"
        zen_usb_args+=("$first_row" "$d_path" "$d_sz" "$d_mod ($d_ser)")
        first_row=FALSE
    done
    target_device=$(zenity --list --radiolist --width=680 --height=320 \
        --title="OSCAR Bare-Metal Autoinstall USB Creator" \
        --text="1. Select the removable USB drive to turn into a bootable Ubuntu 24.04 + OSCAR installer:" \
        --column="Select" --column="Device" --column="Size" --column="Model / Serial" \
        "${zen_usb_args[@]}") || exit 1

    if [[ -z $iso_path ]]; then
        default_iso=$(find_default_iso || true)
        iso_path=$(zenity --file-selection --title="2. Select Ubuntu 24.04 Live Server ISO (ubuntu-24.04.x-live-server-amd64.iso)" \
            ${default_iso:+--filename="$default_iso"} \
            --file-filter="Ubuntu Live Server ISO (*.iso) | *.iso" --file-filter="All files | *") || exit 1
    fi

    if [[ -z $offline_bundle ]]; then
        default_bundle=$(find_default_bundle || true)
        offline_bundle=$(zenity --file-selection --title="3. Select oscar-*-ubuntu-x86_64-offline-full.zip (Cancel to build OS-only USB)" \
            ${default_bundle:+--filename="$default_bundle"} \
            --file-filter="OSCAR Ubuntu Offline Bundle (*.zip) | *ubuntu*offline-full*.zip *.zip" --file-filter="All files | *" || true)
    fi

    id_reply=$(zenity --forms --title="4. Target Server Identity" --width=480 \
        --text="Configure the target bare-metal Ubuntu 24.04 server identity:" \
        --separator="|" \
        --add-entry="Target Hostname (default: oscar-host)" \
        --add-entry="Linux Admin Username (default: oscaradmin)" \
        --add-password="Linux Admin Password (blank keeps template default)" \
        --add-password="Confirm Linux Admin Password") || exit 1
    IFS='|' read -r g_host g_user g_pw1 g_pw2 <<<"$id_reply"
    [[ -n $g_host ]] && hostname_val=$g_host
    [[ -n $g_user ]] && username_val=$g_user
    if [[ -n $g_pw1 || -n $g_pw2 ]]; then
        [[ $g_pw1 == "$g_pw2" ]] || { zenity --error --text="Linux admin passwords did not match." || true; exit 1; }
        password_hash=$(hash_linux_password "$g_pw1")
        unset g_pw1 g_pw2
        if zenity --question --title="Sudo Password Policy" --text="Require password re-entry for sudo on '$hostname_val'? (Recommended)"; then
            require_sudo_password=true
        fi
    fi

    if zenity --question --title="LUKS2 Full-Disk Encryption" --default-cancel \
        --text="Enable LUKS2 full-disk encryption on the target server's internal NVMe/SSD?"; then
        luks_reply=$(zenity --forms --title="LUKS2 Passphrase" --width=460 \
            --text="Enter a LUKS2 disk encryption passphrase (minimum 12 characters):" \
            --separator="|" \
            --add-password="LUKS2 Passphrase (12+ chars)" \
            --add-password="Confirm LUKS2 Passphrase") || exit 1
        IFS='|' read -r gl1 gl2 <<<"$luks_reply"
        ((${#gl1} >= 12)) || { zenity --error --text="LUKS2 passphrase must contain at least 12 characters." || true; exit 1; }
        [[ $gl1 == "$gl2" ]] || { zenity --error --text="LUKS2 passphrases did not match." || true; exit 1; }
        luks_passphrase=$gl1
        unset gl1 gl2
    fi

    if [[ -n $offline_bundle ]]; then
        if [[ -z $oscar_admin_pw_hash ]]; then
            oscar_pw_reply=$(zenity --forms --title="5. Turnkey OSCAR Web Admin Password (Optional)" --width=500 \
                --text="Set the initial OSCAR web 'admin' password (14+ chars; hashed via PBKDF2 — leave blank to enter on site):" \
                --separator="|" \
                --add-password="OSCAR Web 'admin' Password (14+ chars)" \
                --add-password="Confirm OSCAR Web 'admin' Password" || true)
            if [[ -n $oscar_pw_reply ]]; then
                IFS='|' read -r go1 go2 <<<"$oscar_pw_reply"
                if [[ -n $go1 || -n $go2 ]]; then
                    ((${#go1} >= 14)) || { zenity --error --text="OSCAR web administrator password must contain at least 14 characters." || true; exit 1; }
                    [[ $go1 == "$go2" ]] || { zenity --error --text="OSCAR web administrator passwords did not match." || true; exit 1; }
                    oscar_admin_pw_hash=$(hash_oscar_pbkdf2_password "$go1")
                fi
                unset go1 go2 oscar_pw_reply
            fi
        fi

        if [[ -z $lanes_file ]] && zenity --question --title="Pre-Configure Site Lanes (Optional)" --default-cancel \
            --text="Do you want to pre-stage a lanes.csv spreadsheet or config.json so all lanes are pre-configured?"; then
            lanes_file=$(zenity --file-selection --title="Select lanes.csv or config.json" \
                --file-filter="OSCAR Lanes CSV or JSON (*.csv, *.json) | *.csv *.json" --file-filter="All files | *" || true)
        fi

        if [[ -n $oscar_admin_pw_hash ]] && ! $auto_init_explicit; then
            if zenity --question --title="Turnkey Unattended First-Boot Setup" \
                --text="Automatically initialize OSCAR and load pre-staged lanes on first boot?\n\n(On site you will only need to open https://$hostname_val/, register users, and upload .pmtiles or the site diagram.)"; then
                auto_init_oscar=true
            fi
        fi
    fi

    if zenity --question --title="Optional Extra Seed Folder" --default-cancel \
        --text="Do you want to pre-stage an extra seed folder (site-network.env, *.pmtiles, backup-key.txt)?"; then
        seed_dir=$(zenity --file-selection --directory --title="Select Seed Directory" || true)
    fi

    real_dev=$(realpath -P -- "$target_device")
    dev_desc=$(lsblk -dnro SIZE,MODEL,SERIAL "$real_dev" 2>/dev/null | tr '\n' ' ')
    confirm_token=$(zenity --entry --width=520 --title="Confirm USB Erase" \
        --text="WARNING: ALL DATA ON $real_dev ($dev_desc) WILL BE ERASED!\n\nType ERASE-USB to build the bootable installer:") || exit 1
    [[ $confirm_token == ERASE-USB ]] || { zenity --error --text="Cancelled (expected exact confirmation ERASE-USB)." || true; exit 1; }
fi

# Interactive terminal / whiptail TUI prompts when required arguments are omitted
if ! $has_zenity && [[ -z $target_device && -z $output_image ]]; then
    [[ -t 0 && -t 1 ]] || fail "Specify --device /dev/sdX (or --output-image FILE) when running non-interactively."
    mapfile -t usb_rows < <(list_candidate_usb_disks)
    ((${#usb_rows[@]} > 0)) || fail "No safe removable USB drives (>= 8 GiB) detected. Plug in a target USB stick/SSD and re-run."

    if $has_tui; then
        menu_items=()
        for row in "${usb_rows[@]}"; do
            IFS=$'\t' read -r d_path d_sz d_mod d_ser <<<"$row"
            menu_items+=("$d_path" "$d_sz — $d_mod ($d_ser)")
        done
        target_device=$(whiptail --title "OSCAR Bare-Metal Autoinstall USB Builder" \
            --menu "Select the external USB drive to erase and turn into an OSCAR Ubuntu 24.04 Autoinstall USB:" \
            18 78 8 "${menu_items[@]}" 3>&1 1>&2 2>&3) || exit 1
    else
        printf '\nCandidate External USB Drives:\n'
        idx=1
        for row in "${usb_rows[@]}"; do
            printf '  [%d] %s\n' "$idx" "$row"
            ((idx += 1))
        done
        printf 'Select USB drive number [1-%d]: ' "${#usb_rows[@]}"
        IFS= read -r choice
        [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#usb_rows[@]})) || fail "Invalid selection."
        IFS=$'\t' read -r target_device _ <<<"${usb_rows[$((choice - 1))]}"
    fi
fi

if [[ -z $iso_path ]]; then
    [[ -t 0 && -t 1 ]] || fail "Specify --iso /path/to/ubuntu-24.04.x-live-server-amd64.iso"
    default_iso=$(find_default_iso || true)
    if $has_tui; then
        iso_path=$(whiptail --title "Ubuntu 24.04 Live Server ISO" \
            --inputbox "Enter path to ubuntu-24.04.x-live-server-amd64.iso:" 10 78 "$default_iso" 3>&1 1>&2 2>&3) || exit 1
    else
        printf 'Path to ubuntu-24.04-live-server-amd64.iso [%s]: ' "$default_iso"
        IFS= read -r iso_path
        iso_path=${iso_path:-$default_iso}
    fi
fi
[[ -f $iso_path ]] || fail "Ubuntu Live Server ISO not found: $iso_path"

if ! $has_zenity && $interactive_wizard && [[ -z $offline_bundle ]] && [[ -t 0 && -t 1 ]]; then
    default_bundle=$(find_default_bundle || true)
    if $has_tui; then
        offline_bundle=$(whiptail --title "OSCAR Offline Full Bundle (Recommended)" \
            --inputbox "Path to oscar-*-ubuntu-x86_64-offline-full.zip (leave blank for OS-only installer):" 11 78 "$default_bundle" 3>&1 1>&2 2>&3) || exit 1
    else
        printf 'Path to oscar-*-ubuntu-x86_64-offline-full.zip (blank to skip) [%s]: ' "$default_bundle"
        IFS= read -r reply_b
        offline_bundle=${reply_b:-$default_bundle}
    fi
fi
if [[ -n $offline_bundle ]]; then
    [[ -f $offline_bundle ]] || fail "Offline bundle ZIP not found: $offline_bundle"
fi

if ! $has_zenity && $interactive_wizard && [[ -t 0 && -t 1 ]]; then
    if ! $hostname_explicit; then
        if $has_tui; then
            hostname_val=$(whiptail --title "Target Server Hostname" \
                --inputbox "Hostname for the new Ubuntu 24.04 server:" 10 74 "$hostname_val" 3>&1 1>&2 2>&3) || exit 1
        else
            printf 'Target server hostname [%s]: ' "$hostname_val"
            IFS= read -r reply_h
            hostname_val=${reply_h:-$hostname_val}
        fi
    fi
    if ! $username_explicit; then
        if $has_tui; then
            username_val=$(whiptail --title "Linux Admin Username" \
                --inputbox "Administrator username on the new Ubuntu 24.04 server:" 10 74 "$username_val" 3>&1 1>&2 2>&3) || exit 1
        else
            printf 'Linux admin username [%s]: ' "$username_val"
            IFS= read -r reply_u
            username_val=${reply_u:-$username_val}
        fi
    fi
    [[ $hostname_val =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || fail "Invalid hostname: $hostname_val"
    [[ $username_val =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] || fail "Invalid Linux username: $username_val"
fi

if ! $has_zenity && [[ -z $password_hash ]] && $interactive_wizard && [[ -t 0 && -t 1 ]]; then
    if $has_tui; then
        pw1=$(whiptail --title "OSCAR Linux Admin Password ($username_val)" \
            --passwordbox "Set password for '$username_val' on the new server (leave blank to keep template default):" 10 74 3>&1 1>&2 2>&3) || exit 1
        if [[ -n $pw1 ]]; then
            pw2=$(whiptail --title "Confirm Password" --passwordbox "Re-enter password for '$username_val':" 10 74 3>&1 1>&2 2>&3) || exit 1
            [[ $pw1 == "$pw2" ]] || fail "Passwords did not match."
            password_hash=$(hash_linux_password "$pw1")
            unset pw1 pw2
            if ! $sudo_explicit && whiptail --title "Sudo Password Policy" --yesno "Require password re-entry for sudo on '$hostname_val'? (Recommended)" 9 72; then
                require_sudo_password=true
            fi
        fi
    else
        printf "Set Linux password for '%s' (press Enter to keep template default): " "$username_val"
        IFS= read -rs pw1; printf '\n'
        if [[ -n $pw1 ]]; then
            printf "Confirm password for '%s': " "$username_val"
            IFS= read -rs pw2; printf '\n'
            [[ $pw1 == "$pw2" ]] || fail "Passwords did not match."
            password_hash=$(hash_linux_password "$pw1")
            unset pw1 pw2
            if ! $sudo_explicit; then
                printf 'Require password for sudo? [Y/n]: '
                IFS= read -r reply_sudo
                [[ -z $reply_sudo || $reply_sudo =~ ^[Yy] ]] && require_sudo_password=true
            fi
        fi
    fi
fi

if ! $has_zenity && [[ -z $luks_passphrase ]] && $interactive_wizard && [[ -t 0 && -t 1 ]]; then
    if $has_tui; then
        if whiptail --title "LUKS2 Full-Disk Encryption" --defaultno \
            --yesno "Enable LUKS2 full-disk encryption on the target server's internal NVMe/SSD?" 9 74; then
            lp1=$(whiptail --title "LUKS2 Passphrase" --passwordbox "Enter LUKS2 passphrase (12+ characters):" 10 74 3>&1 1>&2 2>&3) || exit 1
            ((${#lp1} >= 12)) || fail "LUKS2 passphrase must contain at least 12 characters."
            lp2=$(whiptail --title "Confirm LUKS2 Passphrase" --passwordbox "Re-enter LUKS2 passphrase:" 10 74 3>&1 1>&2 2>&3) || exit 1
            [[ $lp1 == "$lp2" ]] || fail "LUKS2 passphrases did not match."
            luks_passphrase=$lp1
            unset lp1 lp2
        fi
    else
        printf 'Enable LUKS2 full-disk encryption on the target server? [y/N]: '
        IFS= read -r reply_luks
        if [[ $reply_luks =~ ^[Yy] ]]; then
            printf 'Enter LUKS2 passphrase (12+ characters): '
            IFS= read -rs lp1; printf '\n'
            ((${#lp1} >= 12)) || fail "LUKS2 passphrase must contain at least 12 characters."
            printf 'Confirm LUKS2 passphrase: '
            IFS= read -rs lp2; printf '\n'
            [[ $lp1 == "$lp2" ]] || fail "LUKS2 passphrases did not match."
            luks_passphrase=$lp1
            unset lp1 lp2
        fi
    fi
fi

# Collect SSH public keys
declare -a ssh_keys=()
if ((${#ssh_key_files[@]} == 0)) && [[ -t 0 && -t 1 || $has_zenity == true ]]; then
    user_home=${SUDO_USER:+$(getent passwd "$SUDO_USER" | cut -d: -f6)}
    user_home=${user_home:-$HOME}
    for pub in "$user_home"/.ssh/*.pub; do
        [[ -f $pub ]] && ssh_key_files+=("$pub")
    done
fi
for kf in "${ssh_key_files[@]}"; do
    [[ -f $kf ]] || fail "SSH public key file not found: $kf"
    while IFS= read -r line; do
        line=${line%$'\r'}
        [[ -n $line && $line != \#* ]] && ssh_keys+=("$line")
    done <"$kf"
done

if ((${#ssh_keys[@]} > 0)) && ! $ssh_keys_only_explicit && $interactive_wizard; then
    if $has_zenity; then
        if zenity --question --title="SSH Keys Policy" --default-cancel \
            --text="Detected ${#ssh_keys[@]} SSH public key(s) in ~/.ssh.\n\nDisable SSH password login (SSH keys only)?"; then
            ssh_keys_only=true
        fi
    elif $has_tui; then
        if whiptail --title "SSH Keys Policy" --defaultno \
            --yesno "Detected ${#ssh_keys[@]} SSH public key(s) in ~/.ssh. Disable SSH password login (SSH keys only)?" 9 74; then
            ssh_keys_only=true
        fi
    elif [[ -t 0 && -t 1 ]]; then
        printf 'Detected %d SSH public key(s) in ~/.ssh. Disable SSH password login (SSH keys only)? [y/N]: ' "${#ssh_keys[@]}"
        IFS= read -r reply_ko
        [[ $reply_ko =~ ^[Yy] ]] && ssh_keys_only=true
    fi
fi

if ! $has_zenity && [[ -n $offline_bundle ]] && $interactive_wizard && [[ -t 0 && -t 1 ]]; then
    if [[ -z $oscar_admin_pw_hash ]]; then
        if $has_tui; then
            opw1=$(whiptail --title "Turnkey OSCAR Web Admin Password (Optional)" \
                --passwordbox "Set initial OSCAR web 'admin' password (14+ chars, hashed via PBKDF2; leave blank to enter on site):" 11 76 3>&1 1>&2 2>&3) || exit 1
            if [[ -n $opw1 ]]; then
                ((${#opw1} >= 14)) || fail "Initial OSCAR web administrator password must contain at least 14 characters."
                opw2=$(whiptail --title "Confirm OSCAR Web Admin Password" \
                    --passwordbox "Re-enter initial OSCAR web 'admin' password:" 10 74 3>&1 1>&2 2>&3) || exit 1
                [[ $opw1 == "$opw2" ]] || fail "OSCAR web administrator passwords did not match."
                oscar_admin_pw_hash=$(hash_oscar_pbkdf2_password "$opw1")
                unset opw1 opw2
            fi
        else
            printf "Set initial OSCAR web 'admin' password (14+ chars; Enter to set on site): "
            IFS= read -rs opw1; printf '\n'
            if [[ -n $opw1 ]]; then
                ((${#opw1} >= 14)) || fail "Initial OSCAR web administrator password must contain at least 14 characters."
                printf "Confirm initial OSCAR web 'admin' password: "
                IFS= read -rs opw2; printf '\n'
                [[ $opw1 == "$opw2" ]] || fail "OSCAR web administrator passwords did not match."
                oscar_admin_pw_hash=$(hash_oscar_pbkdf2_password "$opw1")
                unset opw1 opw2
            fi
        fi
    fi

    if [[ -z $lanes_file ]]; then
        if $has_tui; then
            lanes_file=$(whiptail --title "Pre-Configure Site Lanes (Optional)" \
                --inputbox "Optional path to lanes.csv spreadsheet or config.json to pre-configure lanes (leave blank to skip):" \
                11 78 "" 3>&1 1>&2 2>&3) || exit 1
        else
            printf 'Optional pre-configured lanes file (lanes.csv or config.json; Enter to skip): '
            IFS= read -r lanes_file
        fi
    fi
    if [[ -n $lanes_file ]]; then
        [[ -f $lanes_file ]] || fail "Pre-configured lanes file not found: $lanes_file"
    fi

    if [[ -n $oscar_admin_pw_hash ]] && ! $auto_init_explicit; then
        if $has_tui; then
            if whiptail --title "Turnkey Unattended First-Boot Setup" \
                --yesno "Automatically initialize OSCAR and load any pre-staged lanes on first boot (so on site you only register users and upload .pmtiles or the site background image)?" 11 78; then
                auto_init_oscar=true
            fi
        else
            printf 'Automatically initialize OSCAR & pre-staged lanes on first boot? [Y/n]: '
            IFS= read -r reply_ai
            [[ -z $reply_ai || $reply_ai =~ ^[Yy] ]] && auto_init_oscar=true
        fi
    fi
fi

if ! $has_zenity && [[ -z $seed_dir && ${#seed_files[@]} -eq 0 ]] && $interactive_wizard && [[ -t 0 && -t 1 ]]; then
    if $has_tui; then
        seed_dir=$(whiptail --title "Optional Extra Seed Folder" \
            --inputbox "Optional directory containing site-network.env, *.pmtiles, or backup-key.txt to pre-stage (leave blank if none):" \
            12 78 "" 3>&1 1>&2 2>&3) || exit 1
    else
        printf 'Optional extra seed directory (site-network.env / *.pmtiles / backup-key.txt; Enter to skip): '
        IFS= read -r seed_dir
    fi
fi
[[ -z $seed_dir || -d $seed_dir ]] || fail "Seed directory not found: $seed_dir"
for sf in "${seed_files[@]}"; do
    [[ -f $sf ]] || fail "Seed file not found: $sf"
done
if $auto_init_oscar; then
    [[ -n $offline_bundle ]] || fail "--auto-init-oscar requires --offline-bundle oscar-*-ubuntu-x86_64-offline-full.zip."
    [[ -n $oscar_admin_pw_hash ]] || fail "--auto-init-oscar requires --oscar-admin-password-file (or --oscar-admin-password-hash) so unattended initialization has an initial OSCAR web admin credential."
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/oscar-autoinstall-usb.XXXXXX")
loop_dev=''
cidata_mnt="$work_dir/mnt-cidata"
media_mnt="$work_dir/mnt-media"
mkdir -p "$cidata_mnt" "$media_mnt"

cleanup() {
    set +e
    if [[ -n $saved_printk_level && -w /proc/sys/kernel/printk ]]; then
        printf '%s\n' "$saved_printk_level" >/proc/sys/kernel/printk 2>/dev/null || true
    fi
    mountpoint -q "$cidata_mnt" 2>/dev/null && umount "$cidata_mnt"
    mountpoint -q "$media_mnt" 2>/dev/null && umount "$media_mnt"
    [[ -n $loop_dev ]] && losetup -d "$loop_dev" 2>/dev/null
    rm -rf -- "$work_dir"
}
trap cleanup EXIT HUP INT TERM

if [[ -z $password_hash ]]; then
    warn "No custom Linux password was set for '$username_val'; the template bootstrap password remains active until changed via 'passwd $username_val'!"
fi
if $ssh_keys_only && ((${#ssh_keys[@]} == 0)); then
    fail "--ssh-keys-only requires at least one SSH public key (--ssh-key-file or ~/.ssh/*.pub)."
fi

render_custom_user_data "$work_dir/user-data" "$hostname_val" "$username_val" "$password_hash" "$luks_passphrase" "$require_sudo_password" "$ssh_keys_only" "${ssh_keys[@]}"
cp -f -- "$template_meta_data" "$work_dir/meta-data"

write_target=''
p_cidata=''
p_media=''

if [[ -n $output_image ]]; then
    [[ $confirm_token == ERASE-USB ]] || fail "Pass --confirm ERASE-USB when creating an image."
    info "Creating ${output_image_size_gib} GiB sparse autoinstall disk image at $output_image..."
    rm -f -- "$output_image"
    truncate -s "${output_image_size_gib}G" "$output_image"
    dd if="$iso_path" of="$output_image" bs=16M conv=notrunc,fsync status=none
    sgdisk -e "$output_image" >/dev/null
    sgdisk -n 4:0:+64M -t 4:0700 -c 4:CIDATA -n 5:0:0 -t 5:0700 -c 5:OSCAR_MEDIA "$output_image" >/dev/null
    loop_dev=$(losetup --find --show --partscan "$output_image")
    udevadm settle 2>/dev/null || sleep 1
    write_target=$loop_dev
    p_cidata="${loop_dev}p4"
    p_media="${loop_dev}p5"
else
    validate_safe_usb_device "$target_device"
    real_dev=$(realpath -P -- "$target_device")
    dev_desc=$(lsblk -dnro SIZE,MODEL,SERIAL "$real_dev" 2>/dev/null | tr '\n' ' ')
    if [[ $confirm_token != ERASE-USB ]]; then
        [[ -t 0 && -t 1 ]] || fail "Pass --confirm ERASE-USB to confirm erasing $real_dev."
        if $has_tui; then
            confirm_token=$(whiptail --title "CONFIRM USB ERASE" \
                --inputbox "WARNING: ALL DATA ON USB DRIVE $real_dev ($dev_desc) WILL BE ERASED.\n\nType ERASE-USB to proceed:" \
                12 76 "" 3>&1 1>&2 2>&3) || exit 1
        else
            printf '\nWARNING: ALL DATA ON %s (%s) WILL BE ERASED!\nType ERASE-USB to proceed: ' "$real_dev" "$dev_desc"
            IFS= read -r confirm_token
        fi
        [[ $confirm_token == ERASE-USB ]] || fail "Confirmation cancelled (expected ERASE-USB)."
    fi

    info "Unmounting any mounted partitions on $real_dev..."
    for mp_dev in $(lsblk -lnpo NAME "$real_dev" | tail -n +2); do
        umount "$mp_dev" 2>/dev/null || umount -l "$mp_dev" 2>/dev/null || true
    done

    info "Writing Ubuntu 24.04 Live Server ISO to $real_dev (preserving signed UEFI + BIOS boot sectors)..."
    dd if="$iso_path" of="$real_dev" bs=16M conv=fsync status=progress
    sync

    info "Appending CIDATA (64 MiB FAT32) and OSCAR_MEDIA partitions onto $real_dev..."
    sgdisk -e "$real_dev" >/dev/null
    sgdisk -n 4:0:+64M -t 4:0700 -c 4:CIDATA -n 5:0:0 -t 5:0700 -c 5:OSCAR_MEDIA "$real_dev" >/dev/null
    partprobe "$real_dev" 2>/dev/null || blockdev --rereadpt "$real_dev" 2>/dev/null || true
    udevadm settle 2>/dev/null || sleep 2

    write_target=$real_dev
    if [[ $real_dev =~ [0-9]$ ]]; then
        p_cidata="${real_dev}p4"
        p_media="${real_dev}p5"
    else
        p_cidata="${real_dev}4"
        p_media="${real_dev}5"
    fi
fi

for _w in {1..20}; do
    [[ -b $p_cidata && -b $p_media ]] && break
    sleep 0.5
done
[[ -b $p_cidata && -b $p_media ]] || fail "Expected partitions $p_cidata and $p_media did not appear."

info "Formatting $p_cidata (FAT32 CIDATA) and staging cloud-init autoinstall profile..."
mkfs.vfat -F 32 -n CIDATA "$p_cidata" >/dev/null
mount "$p_cidata" "$cidata_mnt"
cp -f -- "$work_dir/user-data" "$cidata_mnt/user-data"
cp -f -- "$work_dir/meta-data" "$cidata_mnt/meta-data"
sync
umount "$cidata_mnt"

info "Formatting $p_media (OSCAR_MEDIA) and staging offline payload + seed files..."
if command -v mkfs.ntfs >/dev/null 2>&1; then
    mkfs.ntfs -f -Q -L OSCAR_MEDIA "$p_media" >/dev/null
elif command -v mkfs.exfat >/dev/null 2>&1; then
    mkfs.exfat -L OSCAR_MEDIA "$p_media" >/dev/null
else
    mkfs.ext4 -F -L OSCAR_MEDIA "$p_media" >/dev/null
fi

mount "$p_media" "$media_mnt"
mkdir -p "$media_mnt/seed"

if [[ -n $offline_bundle ]]; then
    bundle_base=$(basename -- "$offline_bundle")
    info "Copying $bundle_base to OSCAR_MEDIA and verifying SHA-256 on USB..."
    cp -f -- "$offline_bundle" "$media_mnt/$bundle_base"
    if [[ -f "${offline_bundle}.sha256" ]]; then
        cp -f -- "${offline_bundle}.sha256" "$media_mnt/${bundle_base}.sha256"
    else
        (cd "$media_mnt" && sha256sum --binary "$bundle_base" > "${bundle_base}.sha256")
    fi
    (cd "$media_mnt" && sha256sum --check --strict "${bundle_base}.sha256")
    bundle_dir=$(dirname -- "$offline_bundle")
    for extra_doc in \
        "$bundle_dir"/OSCAR-*-Administrator-Operator-Manual-*.pdf \
        "$bundle_dir"/OSCAR-*-SHA256SUMS.txt \
        "$release_dir/documentation/operator-manual"/OSCAR-*-Administrator-Operator-Manual-*.pdf; do
        [[ -f $extra_doc ]] && cp -f -- "$extra_doc" "$media_mnt/$(basename -- "$extra_doc")"
    done
fi

if [[ -n $seed_dir ]]; then
    cp -a -- "$seed_dir/." "$media_mnt/seed/"
fi
for sf in "${seed_files[@]}"; do
    cp -f -- "$sf" "$media_mnt/seed/$(basename -- "$sf")"
done
if [[ -n $lanes_file ]]; then
    cp -f -- "$lanes_file" "$media_mnt/seed/$(basename -- "$lanes_file")"
fi
if [[ -n $oscar_admin_pw_hash ]]; then
    printf '%s\n' "$oscar_admin_pw_hash" >"$media_mnt/seed/oscar-admin-password.txt"
    chmod 0600 "$media_mnt/seed/oscar-admin-password.txt" 2>/dev/null || true
fi
if $auto_init_oscar; then
    cat >"$media_mnt/seed/auto-provision.env" <<EOF
AUTO_INIT_OSCAR=true
OSCAR_HOSTNAME=$hostname_val
OSCAR_HTTPS_PORT=443
EOF
    chmod 0600 "$media_mnt/seed/auto-provision.env" 2>/dev/null || true
fi

cat >"$media_mnt/README-BARE-METAL-INSTALL.txt" <<EOF
OSCAR Bare-Metal Ubuntu Server 24.04 LTS Offline Autoinstall USB
================================================================
Generated UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Target Hostname: $hostname_val
Admin Username:  $username_val

How to Install on Bare-Metal Server / Laptop:
  1. Insert this USB drive into the target x86-64 machine (no internet needed).
  2. Power on and select this USB drive from the UEFI/BIOS One-Time Boot Menu.
  3. Ubuntu Server 24.04 LTS installs automatically onto the internal NVMe/SSD
     (100% LVM capacity, USB drives excluded, USB-NVMe stability quirks enabled)
     and unpacks OSCAR into /srv/oscar/.
  4. Remove this USB drive when prompted at the end of installation and press Enter.
  5. Log in as '$username_val' — the interactive OSCAR First-Boot Provisioning
     Wizard launches automatically so you can:
       - Optimize the Ubuntu host offline (Docker, sysctl, UFW, USB-NVMe quirks)
       - Restore from a Continual/Occasional USB NVMe Backup drive (including optional
         Safe Bench / DR Clone Isolation when testing while a live portal is active)
       - Restore from a Single-Snapshot Backup
       - Import a saved config.json, lanes.csv spreadsheet, or .pmtiles basemap
       - Run a clean site installation (with optional static IP staging)
     You can also re-open the wizard anytime via: sudo oscar-wizard

Hardware Power Tip for 1-4 TB M.2 NVMe USB Backup Enclosures:
  High-capacity PCIe NVMe USB enclosures draw 6-8W inrush at spin-up. Connect them
  via a mains-powered USB 3.2 Gen 2 hub/dock or a dedicated rear/15W USB-C port
  rather than a 4.5W laptop USB-A port or a shared dual USB-C port next to another
  USB-C dongle.
EOF

sync
umount "$media_mnt"

if [[ -n $loop_dev ]]; then
    losetup -d "$loop_dev"
    loop_dev=''
elif [[ -n ${real_dev:-} && -b $real_dev ]]; then
    udevadm settle 2>/dev/null || sleep 1
    for mp_dev in $(lsblk -lnpo NAME "$real_dev" | tail -n +2); do
        umount "$mp_dev" 2>/dev/null || true
    done
fi
sync

if $has_zenity; then
    zenity --info --width=500 --title="OSCAR Autoinstall USB Ready" \
        --text="OSCAR Bare-Metal Autoinstall USB is ready on ${output_image:-$write_target}!\n\nSafe to eject and boot on the target x86-64 machine." || true
fi

info "SUCCESS: OSCAR Bare-Metal Autoinstall USB ready on ${output_image:-$write_target}."
