#!/usr/bin/env bash
# Packages the standalone cross-platform OSCAR Bare-Metal Ubuntu 24.04
# Offline Autoinstall USB Creator archive:
#   oscar-<version>-autoinstall-usb-creator.zip
# Runs on Windows 11 (GUI + TUI + CLI) and Ubuntu (GUI + TUI + CLI) without
# requiring users to unpack oscar-<version>-ubuntu-x86_64-offline-full.zip first.
set -Eeuo pipefail

repo_root=$(CDPATH= cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
version=${1:-}
out_dir=${2:-"$repo_root/build/distributions"}

if [[ -z $version ]]; then
    version=$(sed -nE 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$repo_root/build.gradle" | head -n 1)
fi
[[ -n $version ]] || { printf 'ERROR: Could not determine OSCAR release version.\n' >&2; exit 1; }

pkg_name="oscar-${version}-autoinstall-usb-creator"
mkdir -p "$out_dir"
out_dir=$(CDPATH= cd -P -- "$out_dir" && pwd -P)
zip_path="$out_dir/${pkg_name}.zip"

stage_root=$(mktemp -d "${TMPDIR:-/tmp}/oscar-usb-creator-pkg.XXXXXX")
trap 'rm -rf -- "$stage_root"' EXIT HUP INT TERM

pkg_dir="$stage_root/$pkg_name"
mkdir -p "$pkg_dir/autoinstall" "$pkg_dir/netplan"

src_ubuntu="$repo_root/dist/release/ubuntu"
cp -f -- "$src_ubuntu/create-autoinstall-usb.bat" "$pkg_dir/create-autoinstall-usb.bat"
cp -f -- "$src_ubuntu/create-autoinstall-usb.ps1" "$pkg_dir/create-autoinstall-usb.ps1"
cp -f -- "$src_ubuntu/create-autoinstall-usb.sh" "$pkg_dir/create-autoinstall-usb.sh"
cp -f -- "$src_ubuntu/oscar-firstboot-wizard.sh" "$pkg_dir/oscar-firstboot-wizard.sh"
cp -f -- "$src_ubuntu/site-network.example.env" "$pkg_dir/site-network.example.env"
cp -f -- "$src_ubuntu/ansible-site-hosts.yml" "$pkg_dir/ansible-site-hosts.yml"
cp -f -- "$src_ubuntu/autoinstall/user-data.yaml" "$pkg_dir/autoinstall/user-data.yaml"
cp -f -- "$src_ubuntu/autoinstall/meta-data" "$pkg_dir/autoinstall/meta-data"
cp -f -- "$src_ubuntu/netplan/01-single-nic-static.yaml.example" "$pkg_dir/netplan/01-single-nic-static.yaml.example"
cp -f -- "$src_ubuntu/netplan/02-dual-nic-operator-and-sensor-vlan.yaml.example" "$pkg_dir/netplan/02-dual-nic-operator-and-sensor-vlan.yaml.example"

# Rewrite relative docs link in standalone README so it points to GitHub docs cleanly
sed "s|(../../../docs/UBUNTU_FIELD_SETUP_GUIDE.md)|(https://github.com/ORNL/oscar/blob/v${version}/docs/UBUNTU_FIELD_SETUP_GUIDE.md)|g" \
    "$src_ubuntu/README.md" > "$pkg_dir/README.md"

chmod 0755 "$pkg_dir/create-autoinstall-usb.sh" "$pkg_dir/oscar-firstboot-wizard.sh"
chmod 0644 \
    "$pkg_dir/create-autoinstall-usb.bat" \
    "$pkg_dir/create-autoinstall-usb.ps1" \
    "$pkg_dir/README.md" \
    "$pkg_dir/site-network.example.env" \
    "$pkg_dir/ansible-site-hosts.yml" \
    "$pkg_dir/autoinstall/user-data.yaml" \
    "$pkg_dir/autoinstall/meta-data" \
    "$pkg_dir/netplan/01-single-nic-static.yaml.example" \
    "$pkg_dir/netplan/02-dual-nic-operator-and-sensor-vlan.yaml.example"

(
    cd "$pkg_dir"
    LC_ALL=C find . -type f ! -path './SHA256SUMS' -printf '%P\n' | LC_ALL=C sort | while IFS= read -r rel; do
        sha256sum --binary "$rel"
    done > SHA256SUMS
    chmod 0644 SHA256SUMS
)

rm -f -- "$zip_path"
python3 - "$stage_root" "$pkg_name" "$zip_path" <<'PY'
import os, pathlib, stat, sys, zipfile

stage_root = pathlib.Path(sys.argv[1])
pkg_name = sys.argv[2]
zip_path = pathlib.Path(sys.argv[3])
pkg_dir = stage_root / pkg_name

with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for path in sorted(pkg_dir.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(stage_root).as_posix()
        zi = zipfile.ZipInfo(rel)
        zi.date_time = (2026, 1, 1, 0, 0, 0)
        zi.compress_type = zipfile.ZIP_DEFLATED
        mode = 0o755 if path.suffix == ".sh" else 0o644
        zi.external_attr = (stat.S_IFREG | mode) << 16
        zf.writestr(zi, path.read_bytes())

print(f"Packaged {zip_path} ({zip_path.stat().st_size} bytes)")
PY
