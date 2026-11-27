#!/usr/bin/env bash
# End-to-end validation for the standalone cross-platform
# oscar-<version>-autoinstall-usb-creator.zip release artifact.
set -Eeuo pipefail

repo_root=$(CDPATH= cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
version=${1:-$(sed -nE 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$repo_root/build.gradle" | head -n 1)}

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/oscar-test-usb-creator.XXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT HUP INT TERM

bash "$repo_root/tools/package-autoinstall-usb-creator.sh" "$version" "$work_dir/out"
zip_path="$work_dir/out/oscar-${version}-autoinstall-usb-creator.zip"
[[ -s $zip_path ]] || { printf 'FAIL: Missing creator zip: %s\n' "$zip_path" >&2; exit 1; }

# Ensure compact standalone size (< 512 KiB)
zip_bytes=$(stat -c '%s' "$zip_path")
(( zip_bytes < 524288 )) || { printf 'FAIL: Creator zip unexpectedly large (%d bytes)\n' "$zip_bytes" >&2; exit 1; }

mkdir -p "$work_dir/unpack"
unzip -q "$zip_path" -d "$work_dir/unpack"
[[ $(find "$work_dir/unpack" -mindepth 1 -maxdepth 1 | wc -l) -eq 1 ]] || { printf 'FAIL: Zip must unpack to a single root directory.\n' >&2; exit 1; }

pkg_root="$work_dir/unpack/oscar-${version}-autoinstall-usb-creator"
[[ -d $pkg_root ]] || { printf 'FAIL: Expected root dir missing: %s\n' "$pkg_root" >&2; exit 1; }

(cd "$pkg_root" && sha256sum --check --strict SHA256SUMS >/dev/null)

# Verify executable bits and CRLF/LF hygiene
[[ -x "$pkg_root/create-autoinstall-usb.sh" ]] || { printf 'FAIL: create-autoinstall-usb.sh must be executable.\n' >&2; exit 1; }
grep -q $'\r$' "$pkg_root/create-autoinstall-usb.bat" || { printf 'FAIL: create-autoinstall-usb.bat must have CRLF line endings.\n' >&2; exit 1; }
if grep -q $'\r$' "$pkg_root/create-autoinstall-usb.sh"; then
    printf 'FAIL: create-autoinstall-usb.sh must have LF line endings.\n' >&2
    exit 1
fi

# Verify --help and --list-drives work from the standalone extracted folder (outside full OSCAR tree)
bash "$pkg_root/create-autoinstall-usb.sh" --help | grep -Fq -- '--gui'
bash "$pkg_root/create-autoinstall-usb.sh" --list-drives | grep -Fq 'Protected OS / OSCAR / backup disks'

# Verify --render-user-data-only with --password-file + LUKS2 + --require-sudo-password + SSH keys only
printf 'StrongPortalAdmin!2026\n' > "$work_dir/pw.txt"
printf 'StrongLuksDiskPass!2026\n' > "$work_dir/luks.txt"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockKeyForStandaloneCreatorTest admin@portal\n' > "$work_dir/id_ed25519.pub"

bash "$pkg_root/create-autoinstall-usb.sh" \
    --hostname portal-gate-01 \
    --username siteadmin \
    --password-file "$work_dir/pw.txt" \
    --luks-passphrase-file "$work_dir/luks.txt" \
    --require-sudo-password \
    --ssh-key-file "$work_dir/id_ed25519.pub" \
    --ssh-keys-only \
    --render-user-data-only "$work_dir/rendered-user-data.yaml"

grep -Fq 'hostname: portal-gate-01' "$work_dir/rendered-user-data.yaml"
grep -Fq 'username: siteadmin' "$work_dir/rendered-user-data.yaml"
grep -Eq 'password: "\$6\$[./0-9A-Za-z]{1,16}\$[./0-9A-Za-z]{86}"' "$work_dir/rendered-user-data.yaml"
grep -Fq '"StrongLuksDiskPass!2026"' "$work_dir/rendered-user-data.yaml"
grep -Fq 'allow-pw: false' "$work_dir/rendered-user-data.yaml"
grep -Fq 'PasswordAuthentication no' "$work_dir/rendered-user-data.yaml"
grep -Fq 'oscar-autoprovision.service' "$work_dir/rendered-user-data.yaml"
if grep -Fq 'NOPASSWD:ALL' "$work_dir/rendered-user-data.yaml"; then
    printf 'FAIL: NOPASSWD:ALL must be omitted when --require-sudo-password is set.\n' >&2
    exit 1
fi
if grep -Fq 'StrongPortalAdmin!2026' "$work_dir/rendered-user-data.yaml"; then
    printf 'FAIL: Plaintext Linux password leaked into rendered user-data.\n' >&2
    exit 1
fi

# Verify PBKDF2 hashing for initial OSCAR web admin password matches OSCAR PBKDF2Credential format
python3 - "$pkg_root/create-autoinstall-usb.sh" <<'PY'
import base64, hashlib, subprocess, sys

script = sys.argv[1]
pw = "TurnkeyPortal!2026#Admin"
cmd = f'source <(sed -n "/^hash_oscar_pbkdf2_password()/,/^}}/p" "{script}"); hash_oscar_pbkdf2_password "{pw}"'
line = subprocess.check_output(["bash", "-c", cmd], text=True).strip()
assert line.startswith("# PBKDF2_PREENCODED:PBKDF2WithHmacSHA1:16:"), f"Unexpected header: {line}"
assert pw not in line, "Plaintext password leaked!"
parts = line.split(":")
# ['# PBKDF2_PREENCODED', 'PBKDF2WithHmacSHA1', '16', b64_salt, b64_dk]
assert len(parts) == 5, f"Unexpected parts: {parts}"
salt = base64.b64decode(parts[3])
dk = base64.b64decode(parts[4])
assert len(salt) == 16 and len(dk) == 16
expected = hashlib.pbkdf2_hmac("sha1", pw.encode("utf-8"), salt, 65536, dklen=16)
assert dk == expected, "PBKDF2 derived key mismatch!"
PY

# Verify stage_spreadsheet_csv returns bare bucket object key (never 'spreadsheets/' prefix)
grep -Fq 'printf '\''%s'\'' "$norm_csv"' "$pkg_root/oscar-firstboot-wizard.sh"

# Verify printable 1-page Technician Handover One-Sheet PDF generation (pure Python stdlib, 0600, special-char escaping)
mkdir -p "$work_dir/pdf-seed"
printf 'P@ss(word)\\#2026!Lin\n' > "$work_dir/pdf-linux-pw.txt"
printf 'Luks(Disk)\\Passphrase!2026\n' > "$work_dir/pdf-luks.txt"
printf 'OscarWeb(Admin)\\#2026!\n' > "$work_dir/pdf-web-pw.txt"
printf 'Name,UniqueID,AutoStart\nLane 01,lane-01,true\n' > "$work_dir/pdf-lanes.csv"
cp "$pkg_root/site-network.example.env" "$work_dir/pdf-seed/site-network.env"
printf 'BackupVault(Key)\\2026!Sec\n' > "$work_dir/pdf-seed/backup-key.txt"
printf 'mock-iso\n' > "$work_dir/ubuntu-24.04.5-live-server-amd64.iso"
printf 'mock-bundle\n' > "$work_dir/oscar-${version}-ubuntu-x86_64-offline-full.zip"
expected_bundle_sha=$(sha256sum --binary "$work_dir/oscar-${version}-ubuntu-x86_64-offline-full.zip" | awk '{print $1}')

bash "$pkg_root/create-autoinstall-usb.sh" \
    --iso "$work_dir/ubuntu-24.04.5-live-server-amd64.iso" \
    --offline-bundle "$work_dir/oscar-${version}-ubuntu-x86_64-offline-full.zip" \
    --hostname portal-gate-01 \
    --username siteadmin \
    --password-file "$work_dir/pdf-linux-pw.txt" \
    --luks-passphrase-file "$work_dir/pdf-luks.txt" \
    --require-sudo-password \
    --ssh-key-file "$work_dir/id_ed25519.pub" \
    --ssh-keys-only \
    --oscar-admin-password-file "$work_dir/pdf-web-pw.txt" \
    --lanes-file "$work_dir/pdf-lanes.csv" \
    --auto-init-oscar \
    --seed-dir "$work_dir/pdf-seed" \
    --render-one-sheet-pdf-only "$work_dir/handover.pdf"

[[ -s "$work_dir/handover.pdf" ]] || { printf 'FAIL: Missing generated Technician One-Sheet PDF.\n' >&2; exit 1; }
pdf_mode=$(stat -c '%a' "$work_dir/handover.pdf")
[[ $pdf_mode == "600" ]] || { printf 'FAIL: Technician One-Sheet PDF permissions must be 600 (got %s).\n' "$pdf_mode" >&2; exit 1; }

python3 - "$work_dir/handover.pdf" "$expected_bundle_sha" <<'PY'
import pathlib, sys

raw = pathlib.Path(sys.argv[1]).read_bytes()
expected_sha = sys.argv[2]
assert raw.startswith(b"%PDF-1.4\n"), "Missing %PDF-1.4 header"
assert b"xref\n" in raw and b"startxref\n" in raw and raw.endswith(b"%%EOF\n"), "Invalid PDF xref/EOF structure"
text = raw.decode("latin-1")
for needle in [
    "TECHNICIAN ONE-SHEET",
    "portal-gate-01",
    "siteadmin",
    r"P@ss\(word\)\\#2026!Lin",
    r"Luks\(Disk\)\\Passphrase!2026",
    r"OscarWeb\(Admin\)\\#2026!",
    r"BackupVault\(Key\)\\2026!Sec",
    "198.51.100.10/24",
    "203.0.113.10/24",
    expected_sha,
    "pdf-lanes.csv",
    "NEVER written to the USB drive",
    "FIELD DEPLOYMENT SIGN-OFF",
]:
    assert needle in text, f"Missing expected One-Sheet PDF token: {needle}"
PY

printf 'PASS: Standalone oscar-%s-autoinstall-usb-creator.zip validated (%d bytes).\n' "$version" "$zip_bytes"
