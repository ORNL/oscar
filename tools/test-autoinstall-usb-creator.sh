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
if grep -Fq 'NOPASSWD:ALL' "$work_dir/rendered-user-data.yaml"; then
    printf 'FAIL: NOPASSWD:ALL must be omitted when --require-sudo-password is set.\n' >&2
    exit 1
fi

printf 'PASS: Standalone oscar-%s-autoinstall-usb-creator.zip validated (%d bytes).\n' "$version" "$zip_bytes"
