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
      [--offline-bundle /path/to/oscar-3.12.0-ubuntu-x86_64-offline-full.zip] \
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
      [--one-sheet-pdf /path/to/OSCAR-Install-OneSheet.pdf | --no-one-sheet-pdf] \
      --confirm ERASE-USB

Safety guarantees:
  - Refuses internal NVMe/SATA/SAS OS drives, root/boot/var/OSCAR storage disks,
    and any drive carrying an OSCAR_BACKUP label.
  - Preserves Canonical/Microsoft UEFI Secure Boot signatures on the Ubuntu ISO.
  - Bakes USB-to-NVMe Bulk-Only Transport + No-LPM quirks into the installed OS
    from first boot and installs the interactive OSCAR First-Boot Provisioning Wizard.
  - Generates a printable 1-page Technician Handover One-Sheet PDF strictly on
    this local workstation (0600 permissions, NEVER written to the USB stick)
    containing usernames, passwords, passphrases, SHA-256 checksums, staged
    seed/network details, and post-autoinstall checklist steps.
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

resolve_default_one_sheet_pdf_path() {
    local host_slug ts target_home base_dir
    host_slug=$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')
    ts=$(date '+%Y%m%d-%H%M%S')
    if [[ -n ${SUDO_USER:-} && ${SUDO_USER} != root ]]; then
        target_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6 || true)
    else
        target_home=${HOME:-}
    fi
    if [[ -n $target_home && -d "$target_home/Desktop" ]]; then
        base_dir="$target_home/Desktop"
    elif [[ -n $target_home && -d "$target_home" ]]; then
        base_dir="$target_home"
    else
        base_dir="$PWD"
    fi
    printf '%s/OSCAR-Install-OneSheet-%s-%s.pdf' "$base_dir" "$host_slug" "$ts"
}

generate_technician_one_sheet_pdf() {
    local pdf_path=$1
    local parent_dir
    parent_dir=$(dirname -- "$pdf_path")
    mkdir -p "$parent_dir"

    # Pass all credentials strictly over fd 3 pipe JSON (never on process argv or env) and write with 0600 permissions.
    (
        umask 077
        python3 - "$pdf_path" 3<&0 <<'PY'
import json
import os
import pathlib
import re
import sys

pdf_out = pathlib.Path(sys.argv[1])
with os.fdopen(3, "r", encoding="utf-8") as _in_fh:
    payload = json.loads(_in_fh.read())


def to_ascii(val):
    if val is None:
        return ""
    s = str(val)
    replacements = {
        "\u2014": "--",
        "\u2013": "-",
        "\u2018": "'",
        "\u2019": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u2022": "*",
        "\u00a0": " ",
    }
    for k, v in replacements.items():
        s = s.replace(k, v)
    return "".join(ch if 32 <= ord(ch) <= 126 else "?" for ch in s)


def pdf_escape(s):
    s = to_ascii(s)
    return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def wrap_line(text, max_chars, max_lines=3):
    text = to_ascii(text).strip()
    if not text:
        return ["-"]
    if len(text) <= max_chars:
        return [text]
    lines = []
    remaining = text
    while remaining and len(lines) < max_lines:
        if len(remaining) <= max_chars:
            lines.append(remaining)
            remaining = ""
            break
        split_at = remaining.rfind(" ", 0, max_chars + 1)
        if split_at < max_chars // 3:
            split_at = max_chars
        lines.append(remaining[:split_at].rstrip())
        remaining = remaining[split_at:].lstrip()
    if remaining:
        if max_lines > 0:
            last = lines[-1]
            lines[-1] = (last[: max(1, max_chars - 3)].rstrip() + "...")
    return lines


def parse_env_summary(path_str):
    if not path_str or not os.path.isfile(path_str):
        return ""
    kv = {}
    try:
        for raw in pathlib.Path(path_str).read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            kv[k.strip()] = v.strip().strip('"').strip("'")
    except OSError:
        return ""
    parts = []
    if kv.get("PRIMARY_IP_CIDR"):
        p = f"Primary {kv.get('PRIMARY_NIC', 'NIC1')}: {kv['PRIMARY_IP_CIDR']}"
        if kv.get("PRIMARY_GATEWAY"):
            p += f" (GW {kv['PRIMARY_GATEWAY']})"
        if kv.get("PRIMARY_DNS"):
            p += f" DNS {kv['PRIMARY_DNS']}"
        parts.append(p)
    if kv.get("SENSOR_IP_CIDR"):
        parts.append(f"Sensor {kv.get('SENSOR_NIC', 'NIC2')}: {kv['SENSOR_IP_CIDR']}")
    if kv.get("OSCAR_SITE_HOSTNAME"):
        parts.append(f"Site Host: {kv['OSCAR_SITE_HOSTNAME']}")
    return " | ".join(parts)


def read_backup_key_summary(path_str):
    if not path_str or not os.path.isfile(path_str):
        return ""
    name = os.path.basename(path_str)
    try:
        raw_lines = [ln.strip() for ln in pathlib.Path(path_str).read_text(encoding="utf-8", errors="replace").splitlines() if ln.strip() and not ln.strip().startswith("#")]
    except OSError:
        return f"Staged at /srv/oscar/seed/{name}"
    if len(raw_lines) == 1 and len(raw_lines[0]) <= 128 and all(32 <= ord(c) <= 126 for c in raw_lines[0]):
        return f"{raw_lines[0]}  (file: /srv/oscar/seed/{name})"
    return f"Key file staged at /srv/oscar/seed/{name} ({len(raw_lines)} line(s))"


def fmt_size(path_str):
    if not path_str or not os.path.isfile(path_str):
        return ""
    sz = os.path.getsize(path_str)
    if sz >= 1024 ** 3:
        return f"{sz / (1024 ** 3):.2f} GiB"
    if sz >= 1024 ** 2:
        return f"{sz / (1024 ** 2):.1f} MiB"
    if sz >= 1024:
        return f"{sz / 1024:.1f} KiB"
    return f"{sz} B"


hostname = payload.get("hostname") or "oscar-host"
username = payload.get("username") or "oscaradmin"
linux_pw_plain = payload.get("linuxPasswordPlain") or ""
linux_pw_hashed_only = bool(payload.get("linuxPasswordHashedOnly"))
req_sudo_pw = bool(payload.get("requireSudoPassword"))
luks_pass = payload.get("luksPassphrase") or ""
ssh_keys_only = bool(payload.get("sshKeysOnly"))
ssh_keys = payload.get("sshKeys") or []
oscar_web_pw_plain = payload.get("oscarWebPasswordPlain") or ""
oscar_web_pw_hashed_only = bool(payload.get("oscarWebPasswordHashedOnly"))
auto_init = bool(payload.get("autoInitOscar"))
iso_path = payload.get("isoPath") or ""
bundle_path = payload.get("bundlePath") or ""
bundle_sha256 = payload.get("bundleSha256") or ""
lanes_file = payload.get("lanesFile") or ""
seed_dir = payload.get("seedDir") or ""
seed_files = payload.get("seedFiles") or []
target_desc = payload.get("targetDesc") or "Removable USB Drive"
generated_utc = payload.get("generatedUtc") or ""
generated_local = payload.get("generatedLocal") or ""
bundled_manuals = payload.get("bundledManuals") or []

# Discover staged seed files, site-network.env, and backup-key.txt
staged_seed_names = []
site_net_path = ""
backup_key_path = ""

def consider_seed_file(full_path, rel_name):
    global site_net_path, backup_key_path
    if rel_name not in staged_seed_names:
        staged_seed_names.append(rel_name)
    lower = os.path.basename(rel_name).lower()
    if lower == "site-network.env" and not site_net_path:
        site_net_path = full_path
    if "backup" in lower and "key" in lower and lower.endswith(".txt") and not backup_key_path:
        backup_key_path = full_path

if seed_dir and os.path.isdir(seed_dir):
    for root, _dirs, files in os.walk(seed_dir):
        for fn in sorted(files):
            fp = os.path.join(root, fn)
            rel = os.path.relpath(fp, seed_dir).replace("\\", "/")
            consider_seed_file(fp, rel)
for sf in seed_files:
    if sf and os.path.isfile(sf):
        consider_seed_file(sf, os.path.basename(sf))
if lanes_file and os.path.isfile(lanes_file):
    consider_seed_file(lanes_file, os.path.basename(lanes_file))
if oscar_web_pw_plain or oscar_web_pw_hashed_only:
    if "oscar-admin-password.txt" not in staged_seed_names:
        staged_seed_names.append("oscar-admin-password.txt (PBKDF2 hash)")
if auto_init:
    if "auto-provision.env" not in staged_seed_names:
        staged_seed_names.append("auto-provision.env")

site_net_summary = parse_env_summary(site_net_path)
backup_key_summary = read_backup_key_summary(backup_key_path)

oscar_version = "OS-Only USB"
if bundle_path:
    m = re.search(r"oscar-([0-9]+\.[0-9]+\.[0-9]+[^\s/\\]*?)-ubuntu", os.path.basename(bundle_path), re.I)
    oscar_version = f"v{m.group(1)}" if m else os.path.basename(bundle_path)

if linux_pw_plain:
    linux_pw_display = linux_pw_plain
    linux_pw_mono = True
elif linux_pw_hashed_only:
    linux_pw_display = "[Pre-hashed SHA-512 supplied; plaintext unavailable]"
    linux_pw_mono = False
else:
    linux_pw_display = f"OscarChangeMe!24  (TEMPLATE DEFAULT -- run: passwd {username})"
    linux_pw_mono = True

if oscar_web_pw_plain:
    oscar_web_display = f"User: admin   |   Pass: {oscar_web_pw_plain}"
    oscar_web_mono = True
elif oscar_web_pw_hashed_only:
    oscar_web_display = "User: admin   |   Pass: [Pre-encoded PBKDF2 hash supplied]"
    oscar_web_mono = False
else:
    oscar_web_display = "User: admin   |   Pass: [Set 14+ char password during first-boot wizard]"
    oscar_web_mono = False

if luks_pass:
    luks_display = f"ENABLED -- Passphrase: {luks_pass}"
    luks_mono = True
else:
    luks_display = "Disabled (unencrypted 100% internal NVMe/SSD LVM)"
    luks_mono = False

ssh_labels = []
for k in ssh_keys[:4]:
    parts = k.strip().split()
    if len(parts) >= 3:
        ssh_labels.append(f"{parts[0]} ({parts[2]})")
    elif len(parts) >= 1:
        ssh_labels.append(f"{parts[0]} (...{parts[-1][-12:]})")
if len(ssh_keys) > 4:
    ssh_labels.append(f"+{len(ssh_keys) - 4} more")
ssh_policy = "SSH keys ONLY (password login disabled)" if ssh_keys_only else "Password + SSH key login allowed"
if ssh_keys:
    ssh_display = f"{ssh_policy} | {len(ssh_keys)} key(s): {', '.join(ssh_labels)}"
else:
    ssh_display = f"{ssh_policy} | No SSH public keys staged"

iso_display = f"{os.path.basename(iso_path)} ({fmt_size(iso_path)})" if iso_path else "Not specified"
if bundle_path:
    bundle_display = f"{os.path.basename(bundle_path)} ({fmt_size(bundle_path)}) -> /srv/oscar/"
else:
    bundle_display = "None (OS-only Ubuntu 24.04 autoinstall USB)"
sha_display = bundle_sha256 if bundle_sha256 else ("Verified during USB write" if bundle_path else "N/A (no offline bundle)")
lanes_display = f"{os.path.basename(lanes_file)} -> /srv/oscar/seed/{os.path.basename(lanes_file)}" if lanes_file else "None pre-staged (configure in OSCAR UI or wizard)"
seeds_display = ", ".join(staged_seed_names) if staged_seed_names else "None"
manuals_display = ", ".join(bundled_manuals) if bundled_manuals else "Included inside offline bundle (/srv/oscar/)"
mode_display = (
    "Turnkey Unattended Auto-Init (oscar-autoprovision.service)"
    if auto_init
    else "Interactive First-Boot Wizard (auto-opens on login, or: sudo oscar-wizard)"
)

# PDF 1.4 Drawing Engine (US Letter: 612 x 792 pt, 36 pt margins => content x=36..576, w=540)
cmds = []
PAGE_W = 612.0
PAGE_H = 792.0
MARGIN_L = 36.0
CONTENT_W = 540.0


def set_fill(r, g, b):
    cmds.append(f"{r:.3f} {g:.3f} {b:.3f} rg")


def set_stroke(r, g, b):
    cmds.append(f"{r:.3f} {g:.3f} {b:.3f} RG")


def rect(x, y, w, h, fill=None, stroke=None, lw=0.6):
    cmds.append("q")
    if stroke:
        cmds.append(f"{lw:.2f} w")
        set_stroke(*stroke)
    if fill:
        set_fill(*fill)
    op = "B" if (fill and stroke) else ("f" if fill else "S")
    cmds.append(f"{x:.2f} {y:.2f} {w:.2f} {h:.2f} re {op}")
    cmds.append("Q")


def line(x1, y1, x2, y2, stroke=(0.80, 0.84, 0.88), lw=0.5):
    cmds.append("q")
    cmds.append(f"{lw:.2f} w")
    set_stroke(*stroke)
    cmds.append(f"{x1:.2f} {y1:.2f} m {x2:.2f} {y2:.2f} l S")
    cmds.append("Q")


def draw_text(x, y, text, font="F1", size=9.0, color=(0.10, 0.14, 0.20)):
    cmds.append("q")
    set_fill(*color)
    cmds.append(f"BT /{font} {size:.1f} Tf 1 0 0 1 {x:.2f} {y:.2f} Tm ({pdf_escape(text)}) Tj ET")
    cmds.append("Q")


# Colors
NAVY = (0.059, 0.153, 0.267)
SLATE = (0.118, 0.227, 0.373)
TEAL = (0.051, 0.580, 0.533)
BADGE_DARK = (0.200, 0.255, 0.333)
AMBER_BG = (0.996, 0.953, 0.780)
AMBER_BORDER = (0.851, 0.467, 0.024)
AMBER_TEXT = (0.573, 0.251, 0.055)
ROW_ALT = (0.969, 0.980, 0.988)
WHITE = (1.0, 1.0, 1.0)
BORDER = (0.796, 0.835, 0.882)
TEXT_DARK = (0.086, 0.125, 0.184)
TEXT_MUTED = (0.278, 0.333, 0.412)
CODE_BG = (0.945, 0.961, 0.976)

# Top Header Banner
cur_y = 758.0
header_h = 48.0
rect(MARGIN_L, cur_y - header_h, CONTENT_W, header_h, fill=NAVY)
draw_text(MARGIN_L + 12, cur_y - 19, "OSCAR BARE-METAL DEPLOYMENT -- TECHNICIAN ONE-SHEET", font="F2", size=12.5, color=WHITE)
sub_line = f"Target Host: {hostname}   |   OSCAR: {oscar_version}   |   Generated: {generated_utc or generated_local}"
draw_text(MARGIN_L + 12, cur_y - 36, sub_line[:95], font="F1", size=8.5, color=(0.82, 0.87, 0.93))

badge_txt = "TURNKEY AUTO-INIT" if auto_init else "INTERACTIVE WIZARD"
badge_w = 100.0 if auto_init else 106.0
badge_x = MARGIN_L + CONTENT_W - badge_w - 10
rect(badge_x, cur_y - 33, badge_w, 19, fill=(TEAL if auto_init else BADGE_DARK))
draw_text(badge_x + (11.0 if auto_init else 9.0), cur_y - 26.5, badge_txt, font="F2", size=7.8, color=WHITE)
cur_y -= (header_h + 6)

# Security Notice Callout Strip
warn_h = 24.0
rect(MARGIN_L, cur_y - warn_h, CONTENT_W, warn_h, fill=AMBER_BG, stroke=AMBER_BORDER, lw=0.9)
draw_text(MARGIN_L + 8, cur_y - 10.5, "SENSITIVE CREDENTIALS -- PRINT FOR SITE SECURITY BINDER & HANDOVER (LOCAL WORKSTATION COPY ONLY)", font="F2", size=7.6, color=AMBER_TEXT)
draw_text(MARGIN_L + 8, cur_y - 20.0, "This one-sheet is NEVER written to the USB drive. Print now for field setup, then securely delete this PDF after site handover.", font="F1", size=7.4, color=AMBER_TEXT)
cur_y -= (warn_h + 7)


def draw_section_header(title):
    global cur_y
    h = 16.5
    rect(MARGIN_L, cur_y - h, CONTENT_W, h, fill=SLATE)
    draw_text(MARGIN_L + 8, cur_y - 11.5, title, font="F2", size=8.6, color=WHITE)
    cur_y -= h


def draw_kv_table(rows):
    global cur_y
    label_w = 142.0
    val_x = MARGIN_L + label_w + 6.0
    top_y = cur_y
    for idx, row in enumerate(rows):
        label, value, is_mono, max_lines = row
        font_name = "F4" if is_mono else "F1"
        font_size = 8.1 if is_mono else 8.2
        max_chars = 66 if is_mono else 80
        wrapped = wrap_line(value, max_chars=max_chars, max_lines=max_lines)
        row_h = max(14.5, 4.5 + len(wrapped) * 10.2)
        bg = ROW_ALT if (idx % 2 == 1) else WHITE
        rect(MARGIN_L, cur_y - row_h, CONTENT_W, row_h, fill=bg)
        line(MARGIN_L, cur_y - row_h, MARGIN_L + CONTENT_W, cur_y - row_h, stroke=BORDER, lw=0.45)
        draw_text(MARGIN_L + 7, cur_y - 10.5, label, font="F2", size=8.0, color=TEXT_MUTED)
        ly = cur_y - 10.5
        for wl in wrapped:
            draw_text(val_x, ly, wl, font=font_name, size=font_size, color=TEXT_DARK)
            ly -= 10.2
        cur_y -= row_h
    line(MARGIN_L + label_w, top_y, MARGIN_L + label_w, cur_y, stroke=BORDER, lw=0.5)
    rect(MARGIN_L, cur_y, CONTENT_W, top_y - cur_y, fill=None, stroke=BORDER, lw=0.6)
    cur_y -= 7


# Section 1: Credentials & System Identity
draw_section_header("1. SYSTEM IDENTITY, PASSWORDS & PASSPHRASES")
sec1_rows = [
    ("Target Hostname / URLs", f"{hostname}  |  https://{hostname}/  |  /sensorhub/admin", True, 2),
    ("Linux Admin Username", f"{username}   (SSH: ssh {username}@{hostname})", True, 1),
    ("Linux Admin Password", linux_pw_display, linux_pw_mono, 2),
    ("Sudo Privilege Policy", "Password required for sudo" if req_sudo_pw else "Passwordless sudo (NOPASSWD enabled)", False, 1),
    ("LUKS2 Disk Encryption", luks_display, luks_mono, 2),
    ("SSH Access & Keys", ssh_display, False, 2),
    ("OSCAR Web Admin Login", oscar_web_display, oscar_web_mono, 2),
    ("Backup Encryption Key", backup_key_summary if backup_key_summary else "Not pre-staged (configure during USB backup setup)", bool(backup_key_summary), 2),
    ("Staged Site Network", site_net_summary if site_net_summary else "Non-blocking DHCP (configure static IP in First-Boot Wizard)", bool(site_net_summary), 2),
]
draw_kv_table(sec1_rows)

# Section 2: Installation Media, Checksums & Pre-Staged Files
draw_section_header("2. INSTALLATION MEDIA, VERIFIED CHECKSUMS & PRE-STAGED FILES")
sec2_rows = [
    ("Target USB / Image", target_desc, False, 1),
    ("Ubuntu 24.04 Live ISO", iso_display, False, 1),
    ("OSCAR Offline Bundle", bundle_display, False, 2),
    ("Verified Bundle SHA-256", sha_display, True, 2),
    ("Pre-Staged Lanes/Config", lanes_display, False, 2),
    ("Staged Seed Files", seeds_display, False, 2),
    ("Bundled Manuals / Docs", manuals_display, False, 2),
    ("First-Boot Mode", mode_display, False, 1),
]
draw_kv_table(sec2_rows)

# Section 3: Post-Autoinstall Field Setup Checklist
draw_section_header("3. POST-AUTOINSTALL FIELD SETUP & ACCESS CHECKLIST")
if auto_init:
    step4 = (
        f"4. Verify Turnkey OSCAR: Run 'sudo bash /srv/oscar/oscar-*/oscar.sh status' "
        f"(log: /var/log/oscar-autoprovision.log). Open https://{hostname}/ as 'admin', register site users/Passkeys, "
        f"and upload .pmtiles or site diagram if not pre-staged."
    )
else:
    step4 = (
        f"4. Run First-Boot Wizard: The OSCAR Provisioning Wizard auto-launches on first login "
        f"(or run 'sudo oscar-wizard') to optimize host offline, apply static IP, restore a backup, or initialize OSCAR."
    )

checklist_steps = [
    "1. Boot Target Server: Insert this USB into the target x86-64 machine (no internet needed) and select USB in UEFI Boot Menu.",
    "2. Complete Unattended Install: Ubuntu 24.04 installs onto the internal NVMe/SSD (100% LVM; USB drives protected) and unpacks OSCAR into /srv/oscar/. Remove USB when prompted and press Enter.",
    f"3. Unlock & Sign In: {'Enter the LUKS2 Boot Passphrase above when prompted. ' if luks_pass else ''}Log in on console or SSH as '{username}'.",
    step4,
    "5. Hardware & Ops Check: Verify SensorHub Admin (/sensorhub/admin), time sync, and lanes. Power 1-4 TB M.2 NVMe USB backup drives via a mains-powered USB 3.2 Gen 2 hub or 15W USB-C port (USB-NVMe quirks pre-installed).",
    "6. Handover & Cleanup: Record the assigned site IP below, file this printed one-sheet in the site binder, and securely delete the local PDF copy from the staging workstation.",
]

# Measure checklist height dynamically so it always fits comfortably above the footer
panel_top = cur_y
wrapped_steps = [wrap_line(st, max_chars=124, max_lines=3) for st in checklist_steps]
total_step_lines = sum(len(ws) for ws in wrapped_steps)
quick_cmd_h = 26.0
panel_h = 8.0 + total_step_lines * 9.5 + len(wrapped_steps) * 2.5 + quick_cmd_h + 6.0
min_panel_bottom = 94.0
if panel_top - panel_h < min_panel_bottom:
    line_step = 8.6
    step_gap = 1.6
    panel_h = 6.0 + total_step_lines * line_step + len(wrapped_steps) * step_gap + quick_cmd_h + 5.0
else:
    line_step = 9.5
    step_gap = 2.5

rect(MARGIN_L, panel_top - panel_h, CONTENT_W, panel_h, fill=WHITE, stroke=BORDER, lw=0.6)
cy = panel_top - 11.5
for ws in wrapped_steps:
    rect(MARGIN_L + 8, cy - 1.0, 6.5, 6.5, fill=WHITE, stroke=SLATE, lw=0.6)
    for sl in ws:
        draw_text(MARGIN_L + 19, cy, sl, font="F1", size=7.8, color=TEXT_DARK)
        cy -= line_step
    cy -= step_gap

cmd_box_y = panel_top - panel_h + 4.5
rect(MARGIN_L + 6, cmd_box_y, CONTENT_W - 12, quick_cmd_h, fill=CODE_BG, stroke=BORDER, lw=0.5)
draw_text(MARGIN_L + 12, cmd_box_y + 15.5, "Commands:  sudo bash /srv/oscar/oscar-*/oscar.sh status   |   sudo oscar-wizard   |   oscar.sh reset-admin-password", font="F3", size=7.3, color=NAVY)
draw_text(MARGIN_L + 12, cmd_box_y + 5.5, "Paths:     Release: /srv/oscar/   |   Seeds: /srv/oscar/seed/   |   Auto-Init Log: /var/log/oscar-autoprovision.log", font="F3", size=7.3, color=NAVY)

# Section 4: Technician Sign-Off Box (pinned cleanly near bottom margin)
sign_top = min(panel_top - panel_h - 6.0, 86.0)
sign_h = 44.0
sign_y = max(38.0, sign_top - sign_h)
rect(MARGIN_L, sign_y, CONTENT_W, sign_h, fill=ROW_ALT, stroke=BORDER, lw=0.6)
draw_text(MARGIN_L + 8, sign_y + 33.5, "FIELD DEPLOYMENT SIGN-OFF", font="F2", size=7.8, color=SLATE)
draw_text(MARGIN_L + 8, sign_y + 20.5, "Site / Facility: _____________________________________   Assigned IP: _________________________   Date: __________________", font="F1", size=8.0, color=TEXT_DARK)
draw_text(MARGIN_L + 8, sign_y + 7.5, "Technician: __________________________________________   Signature: ___________________________   Binder Ref: ____________", font="F1", size=8.0, color=TEXT_DARK)

# Bottom Micro-Footer
draw_text(MARGIN_L, 24.0, f"OSCAR Bare-Metal Autoinstall USB Creator   |   Host: {hostname}   |   Page 1 of 1   |   Local workstation copy only (NOT stored on USB)", font="F1", size=7.0, color=TEXT_MUTED)

stream_bytes = ("\n".join(cmds) + "\n").encode("latin-1")

# Assemble valid PDF 1.4 with exact xref offsets
objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {PAGE_W:.0f} {PAGE_H:.0f}] /Resources << /Font << /F1 4 0 R /F2 5 0 R /F3 6 0 R /F4 7 0 R >> >> /Contents 8 0 R >>".encode("ascii"),
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>",
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier-Bold /Encoding /WinAnsiEncoding >>",
    f"<< /Length {len(stream_bytes)} >>\nstream\n".encode("ascii") + stream_bytes + b"endstream",
]

out = bytearray()
out.extend(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
offsets = [0]
for idx, obj in enumerate(objects, start=1):
    offsets.append(len(out))
    out.extend(f"{idx} 0 obj\n".encode("ascii"))
    out.extend(obj)
    out.extend(b"\nendobj\n")

xref_pos = len(out)
out.extend(f"xref\n0 {len(objects) + 1}\n".encode("ascii"))
out.extend(b"0000000000 65535 f \n")
for off in offsets[1:]:
    out.extend(f"{off:010d} 00000 n \n".encode("ascii"))
out.extend(f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref_pos}\n%%EOF\n".encode("ascii"))

pdf_out.write_bytes(bytes(out))
os.chmod(pdf_out, 0o600)
PY
    )

    if [[ -n ${SUDO_USER:-} && ${SUDO_USER} != root ]]; then
        local sudo_group
        sudo_group=$(id -gn "$SUDO_USER" 2>/dev/null || printf '%s' "$SUDO_USER")
        chown "${SUDO_USER}:${sudo_group}" "$pdf_path" 2>/dev/null || true
    fi
    chmod 0600 "$pdf_path" 2>/dev/null || true
}

emit_one_sheet_pdf_from_state() {
    local pdf_path=$1
    local target_desc_val=$2
    local bundle_sha_val=$3
    shift 3
    local -a manuals_list=("$@")
    local gen_utc gen_local
    gen_utc=$(date -u '+%Y-%m-%d %H:%M UTC')
    gen_local=$(date '+%Y-%m-%d %H:%M %Z')

    local -a kv_stream=(
        "hostname" "$hostname_val"
        "username" "$username_val"
        "linuxPasswordPlain" "$linux_pw_for_sheet"
        "linuxPasswordHashedOnly" "$([[ -n $password_hash && -z $linux_pw_for_sheet ]] && echo true || echo false)"
        "requireSudoPassword" "$($require_sudo_password && echo true || echo false)"
        "luksPassphrase" "$luks_passphrase"
        "sshKeysOnly" "$($ssh_keys_only && echo true || echo false)"
        "oscarWebPasswordPlain" "$oscar_web_pw_for_sheet"
        "oscarWebPasswordHashedOnly" "$([[ -n $oscar_admin_pw_hash && -z $oscar_web_pw_for_sheet ]] && echo true || echo false)"
        "autoInitOscar" "$($auto_init_oscar && echo true || echo false)"
        "isoPath" "$iso_path"
        "bundlePath" "$offline_bundle"
        "bundleSha256" "$bundle_sha_val"
        "lanesFile" "$lanes_file"
        "seedDir" "$seed_dir"
        "targetDesc" "$target_desc_val"
        "generatedUtc" "$gen_utc"
        "generatedLocal" "$gen_local"
    )
    local item
    for item in "${ssh_keys[@]+"${ssh_keys[@]}"}"; do
        kv_stream+=("sshKeys[]" "$item")
    done
    for item in "${seed_files[@]+"${seed_files[@]}"}"; do
        kv_stream+=("seedFiles[]" "$item")
    done
    for item in "${manuals_list[@]+"${manuals_list[@]}"}"; do
        kv_stream+=("bundledManuals[]" "$item")
    done

    printf '%s\0' "${kv_stream[@]}" | python3 -c '
import json, sys
raw = sys.stdin.buffer.read().split(b"\x00")
if raw and raw[-1] == b"":
    raw.pop()
obj = {"sshKeys": [], "seedFiles": [], "bundledManuals": []}
bool_keys = {"linuxPasswordHashedOnly", "requireSudoPassword", "sshKeysOnly", "oscarWebPasswordHashedOnly", "autoInitOscar"}
for i in range(0, len(raw) - 1, 2):
    k = raw[i].decode("utf-8", "replace")
    v = raw[i + 1].decode("utf-8", "replace")
    if k.endswith("[]"):
        obj.setdefault(k[:-2], []).append(v)
    elif k in bool_keys:
        obj[k] = (v == "true")
    else:
        obj[k] = v
sys.stdout.write(json.dumps(obj))
' | generate_technician_one_sheet_pdf "$pdf_path"
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
linux_pw_for_sheet=''
luks_passphrase_file=''
luks_passphrase=''
require_sudo_password=false
sudo_explicit=false
ssh_keys_only=false
ssh_keys_only_explicit=false
render_user_data_only=''
render_one_sheet_pdf_only=''
one_sheet_pdf_path=''
no_one_sheet_pdf=false
confirm_token=''
oscar_admin_pw_plain=''
oscar_admin_pw_file=''
oscar_admin_pw_hash=''
oscar_web_pw_for_sheet=''
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
        --render-one-sheet-pdf-only) render_one_sheet_pdf_only=${2:?missing --render-one-sheet-pdf-only}; shift 2 ;;
        --one-sheet-pdf) one_sheet_pdf_path=${2:?missing --one-sheet-pdf}; shift 2 ;;
        --no-one-sheet-pdf) no_one_sheet_pdf=true; shift ;;
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
    if ! $no_one_sheet_pdf; then
        linux_pw_for_sheet=$pw_from_file
    fi
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
        if ! $no_one_sheet_pdf; then
            oscar_web_pw_for_sheet=$opw_from_file
        fi
    fi
    unset opw_from_file
elif [[ -n $oscar_admin_pw_plain ]]; then
    oscar_admin_pw_hash=$(hash_oscar_pbkdf2_password "$oscar_admin_pw_plain")
    if ! $no_one_sheet_pdf; then
        oscar_web_pw_for_sheet=$oscar_admin_pw_plain
    fi
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

if [[ -n $render_one_sheet_pdf_only ]]; then
    [[ $hostname_val =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || fail "Invalid --hostname: $hostname_val"
    [[ $username_val =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] || fail "Invalid Linux --username: $username_val"
    declare -a ssh_keys=()
    for kf in "${ssh_key_files[@]}"; do
        [[ -f $kf ]] || fail "SSH public key file not found: $kf"
        while IFS= read -r line; do
            line=${line%$'\r'}
            [[ -n $line && $line != \#* ]] && ssh_keys+=("$line")
        done <"$kf"
    done
    preview_sha=""
    if [[ -n $offline_bundle && -f $offline_bundle ]]; then
        preview_sha=$(sha256sum --binary "$offline_bundle" | awk '{print $1}')
    fi
    emit_one_sheet_pdf_from_state "$render_one_sheet_pdf_only" "${target_device:-${output_image:-Preview / Dry-Run}}" "$preview_sha"
    unset linux_pw_for_sheet oscar_web_pw_for_sheet luks_passphrase
    exit 0
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
    local cand ver
    for ver in 26.04 24.04; do
        for cand in \
            "$PWD"/ubuntu-"$ver"*-live-server-amd64.iso \
            "$ubuntu_dir"/ubuntu-"$ver"*-live-server-amd64.iso \
            "$(dirname "$release_dir")"/ubuntu-"$ver"*-live-server-amd64.iso \
            "${SUDO_USER:+/home/$SUDO_USER/Downloads}"/ubuntu-"$ver"*-live-server-amd64.iso \
            /srv/oscar/ubuntu-"$ver"*-live-server-amd64.iso \
            /tmp/*/ubuntu-"$ver"*-live-server-amd64.iso \
            /tmp/ubuntu-"$ver"*-live-server-amd64.iso; do
            if [[ -f $cand ]]; then printf '%s' "$cand"; return 0; fi
        done
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
        if ! $no_one_sheet_pdf; then
            linux_pw_for_sheet=$g_pw1
        fi
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
                    if ! $no_one_sheet_pdf; then
                        oscar_web_pw_for_sheet=$go1
                    fi
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
            if ! $no_one_sheet_pdf; then
                linux_pw_for_sheet=$pw1
            fi
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
            if ! $no_one_sheet_pdf; then
                linux_pw_for_sheet=$pw1
            fi
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
                if ! $no_one_sheet_pdf; then
                    oscar_web_pw_for_sheet=$opw1
                fi
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
                if ! $no_one_sheet_pdf; then
                    oscar_web_pw_for_sheet=$opw1
                fi
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

verified_bundle_sha=''
declare -a bundled_manuals_copied=()
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
    verified_bundle_sha=$(awk '{print $1; exit}' "$media_mnt/${bundle_base}.sha256" | tr -d '\r')
    bundle_dir=$(dirname -- "$offline_bundle")
    for extra_doc in \
        "$bundle_dir"/OSCAR-*-Administrator-Operator-Manual-*.pdf \
        "$bundle_dir"/OSCAR-*-SHA256SUMS.txt \
        "$release_dir/documentation/operator-manual"/OSCAR-*-Administrator-Operator-Manual-*.pdf; do
        if [[ -f $extra_doc ]]; then
            doc_base=$(basename -- "$extra_doc")
            cp -f -- "$extra_doc" "$media_mnt/$doc_base"
            bundled_manuals_copied+=("$doc_base")
        fi
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

saved_one_sheet_pdf=''
if ! $no_one_sheet_pdf; then
    saved_one_sheet_pdf=${one_sheet_pdf_path:-$(resolve_default_one_sheet_pdf_path "$hostname_val")}
    target_sheet_desc="${output_image:-${real_dev:-$write_target}${dev_desc:+ ($dev_desc)}}"
    info "Generating printable Technician Handover One-Sheet PDF on local workstation (0600, never stored on USB)..."
    emit_one_sheet_pdf_from_state "$saved_one_sheet_pdf" "$target_sheet_desc" "$verified_bundle_sha" "${bundled_manuals_copied[@]+"${bundled_manuals_copied[@]}"}"
fi
unset linux_pw_for_sheet oscar_web_pw_for_sheet luks_passphrase

if $has_zenity; then
    if [[ -n $saved_one_sheet_pdf && -f $saved_one_sheet_pdf ]]; then
        if zenity --question --width=560 --title="OSCAR Autoinstall USB Ready" \
            --ok-label="Open One-Sheet PDF to Print" --cancel-label="Close" \
            --text="OSCAR Bare-Metal Autoinstall USB is ready on ${output_image:-$write_target}!\n\nPrintable Technician Handover One-Sheet PDF saved locally (NEVER written to USB):\n$saved_one_sheet_pdf\n\nOpen the PDF now to print for site handover?"; then
            if [[ -n ${SUDO_USER:-} && ${SUDO_USER} != root ]] && command -v xdg-open >/dev/null 2>&1; then
                sudo -u "$SUDO_USER" DISPLAY="${DISPLAY:-}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" xdg-open "$saved_one_sheet_pdf" >/dev/null 2>&1 &
            elif command -v xdg-open >/dev/null 2>&1; then
                xdg-open "$saved_one_sheet_pdf" >/dev/null 2>&1 &
            fi
        fi
    else
        zenity --info --width=500 --title="OSCAR Autoinstall USB Ready" \
            --text="OSCAR Bare-Metal Autoinstall USB is ready on ${output_image:-$write_target}!\n\nSafe to eject and boot on the target x86-64 machine." || true
    fi
fi

info "SUCCESS: OSCAR Bare-Metal Autoinstall USB ready on ${output_image:-$write_target}."
if [[ -n $saved_one_sheet_pdf && -f $saved_one_sheet_pdf ]]; then
    info "TECHNICIAN ONE-SHEET PDF (local only, chmod 0600, NEVER stored on USB): $saved_one_sheet_pdf"
    info "Print this one-sheet for site handover and securely delete the digital copy afterwards."
fi
