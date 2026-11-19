#!/usr/bin/env bash
# Builds the Ubuntu 24.04 LTS x86-64 air-gapped offline installation bundle:
#   build/offline/oscar-<version>-ubuntu-x86_64-offline-full.zip
#   build/offline/oscar-<version>-ubuntu-x86_64-offline-full.zip.sha256
#
# Reuses build/install/oscar and cached offline-images.tar when present so
# release workflows do not rebuild container images a second time.

set -Eeuo pipefail

script_path=${BASH_SOURCE[0]}
case $script_path in */*) script_parent=${script_path%/*} ;; *) script_parent=. ;; esac
tool_root=$(CDPATH= cd -- "$script_parent" && pwd -P)
repo_root=$(CDPATH= cd -- "$tool_root/../.." && pwd -P)

output_root="${repo_root}/build/offline"
skip_connected_build=false
use_existing_expanded=false
skip_image_export=false
create_archive=false

while (($# > 0)); do
    case "$1" in
        --output-root) output_root=$(realpath -m "${2:?}"); shift 2 ;;
        --skip-connected-build) skip_connected_build=true; shift ;;
        --use-existing-expanded-release) use_existing_expanded=true; shift ;;
        --skip-image-export) skip_image_export=true; shift ;;
        --create-archive) create_archive=true; shift ;;
        -h|--help)
            cat <<'EOF'
Usage: ./tools/offline/build-ubuntu-offline-bundle.sh [options]

Options:
  --skip-connected-build           Skip ./build-all.sh when artifacts are already built
  --use-existing-expanded-release  Reuse existing build/install/oscar
  --skip-image-export              Reuse cached offline-images.tar under build/offline/.cache/images
  --create-archive                 Create .zip and .zip.sha256 in build/offline/
EOF
            exit 0
            ;;
        *)
            printf 'ERROR: Unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

expected_output_root="${repo_root}/build/offline"
case "${output_root}/" in
    "${expected_output_root}/"*) ;;
    *) printf 'ERROR: --output-root must remain under %s\n' "$expected_output_root" >&2; exit 1 ;;
esac

version=$(awk -F= '$1 == "OSCAR_VERSION" { print substr($0, index($0, "=") + 1); exit }' "${repo_root}/dist/release/.env.example")
[[ -n $version ]] || { printf 'ERROR: OSCAR_VERSION missing from dist/release/.env.example\n' >&2; exit 1; }

if ! $skip_connected_build; then
    (cd "$repo_root" && ./build-all.sh)
fi
if ! $use_existing_expanded; then
    (cd "$repo_root" && ./gradlew --no-parallel installRelDist)
fi

expanded_release="${repo_root}/build/install/oscar"
[[ -f "${expanded_release}/compose.yaml" ]] || {
    printf 'ERROR: Expanded release not found at %s\n' "$expanded_release" >&2
    exit 1
}

mkdir -p "${output_root}/.cache/images" "${output_root}/.cache/ubuntu-24.04-x86_64"
# Reuse the Windows offline builder's Linux amd64 image tar if it was already exported in the same CI job
cached_win_tar="${output_root}/.cache/images/oscar-${version}-windows-x86_64-offline-images.tar"
cached_ubuntu_tar="${output_root}/.cache/images/oscar-${version}-ubuntu-x86_64-offline-images.tar"
image_tar="$cached_ubuntu_tar"
if [[ -s $cached_win_tar ]]; then
    image_tar="$cached_win_tar"
elif ! $skip_image_export || [[ ! -s $cached_ubuntu_tar ]]; then
    if $skip_image_export && [[ ! -s $cached_ubuntu_tar ]]; then
        printf 'ERROR: --skip-image-export set, but no cached image archive exists.\n' >&2
        exit 1
    fi
    printf '==> Exporting Linux amd64 container images for Ubuntu offline bundle...\n'
    (
        cd "$expanded_release"
        OSCAR_VERSION="$version" OSCAR_POSTGIS_PLATFORM="linux/amd64" \
            docker compose -f "${expanded_release}/compose.yaml" build oscar postgres
        docker pull --platform linux/amd64 nginxinc/nginx-unprivileged:1.28.1-alpine
        docker save --output "$cached_ubuntu_tar" \
            "oscar:${version}" \
            "oscar-postgis:${version}" \
            "nginxinc/nginx-unprivileged:1.28.1-alpine"
    )
    image_tar="$cached_ubuntu_tar"
fi

deb_cache="${output_root}/.cache/ubuntu-24.04-x86_64"
if ! compgen -G "${deb_cache}/docker/*.deb" >/dev/null; then
    printf '==> Resolving Ubuntu 24.04 LTS (noble amd64) offline Docker & host-tool .deb closure...\n'
    rm -rf "${deb_cache}/docker" "${deb_cache}/host-tools"
    mkdir -p "${deb_cache}/docker" "${deb_cache}/host-tools"
    docker run --rm --platform linux/amd64 \
        -v "${deb_cache}:/out" \
        ubuntu:24.04 bash -Eeuo pipefail -c '
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq --no-install-recommends ca-certificates curl gnupg systemd python3 openssh-server ufw iproute2 >/dev/null
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc
            echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list
            apt-get update -qq

            mkdir -p /tmp/dl-docker/partial /tmp/dl-tools/partial
            apt-get install -y --no-install-recommends --download-only -o Dir::Cache::archives=/tmp/dl-docker \
                docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
                iptables libltdl7 pigz >/dev/null
            for f in /tmp/dl-docker/*.deb; do
                base=$(basename "$f")
                cp -f "$f" "/out/docker/${base//%/_}"
            done

            apt-get install -y --no-install-recommends --download-only -o Dir::Cache::archives=/tmp/dl-tools \
                chrony ethtool nmap arp-scan jq ntfs-3g rsync >/dev/null
            for f in /tmp/dl-tools/*.deb; do
                base=$(basename "$f")
                cp -f "$f" "/out/host-tools/${base//%/_}"
            done
            chmod -R a+rX /out
        '
fi

bundle_name="oscar-${version}-ubuntu-x86_64-offline-full"
staging_dir="${output_root}/${bundle_name}"
rm -rf -- "$staging_dir"
mkdir -p "$staging_dir"
cp -a "${expanded_release}/." "$staging_dir/"
cp -f "$image_tar" "${staging_dir}/offline-images.tar"

# Remove duplicate osh-node-oscar Docker build context (already baked into oscar:<version> image)
rm -rf -- "${staging_dir}/osh-node-oscar"

# Populate Ubuntu 24.04 .deb directories and generated component manifest
rm -rf -- "${staging_dir}/installers/windows-x86_64"
mkdir -p "${staging_dir}/installers/ubuntu-24.04-x86_64/host-tools"
cp -f "${deb_cache}/docker/"*.deb "${staging_dir}/installers/ubuntu-24.04-x86_64/"
cp -f "${deb_cache}/host-tools/"*.deb "${staging_dir}/installers/ubuntu-24.04-x86_64/host-tools/"

python3 - "$staging_dir" "$version" <<'PY'
import hashlib, json, pathlib, subprocess, sys

staging = pathlib.Path(sys.argv[1])
version = sys.argv[2]
components = []
for deb in sorted((staging / "installers/ubuntu-24.04-x86_64").rglob("*.deb")):
    rel = deb.relative_to(staging).as_posix()
    sha = hashlib.sha256(deb.read_bytes()).hexdigest()
    pkg = subprocess.check_output(["dpkg-deb", "-f", str(deb), "Package"], text=True).strip()
    ver = subprocess.check_output(["dpkg-deb", "-f", str(deb), "Version"], text=True).strip()
    components.append({
        "name": pkg,
        "version": ver,
        "file": rel,
        "sha256": sha,
    })

manifest = {
    "schemaVersion": 1,
    "platform": "ubuntu-24.04-x86_64",
    "oscarVersion": version,
    "components": components,
}
out_file = staging / "installers/components.ubuntu-24.04-x86_64.json"
out_file.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY

cat > "${staging_dir}/BUNDLE-INFO.txt" <<EOF
OSCAR offline installation bundle
Version: ${version}
Platform: Ubuntu Server / Desktop 24.04 LTS x86-64
Profile: Full
Contents: Full air-gapped installation media with official Ubuntu 24.04 Docker Engine .deb packages, host/network tools, and container images.
Generated UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Images: oscar:${version}, oscar-postgis:${version}, nginxinc/nginx-unprivileged:1.28.1-alpine

Extract this archive on the target Ubuntu 24.04 x86-64 machine, then run:
  sudo bash verify-bundle.sh
  sudo bash oscar.sh prepare-host --offline --expand-lvm
  sudo bash oscar.sh stage-site-network
  sudo bash oscar.sh apply-site-network
  sudo bash oscar.sh init
EOF

# Generate exact SHA256SUMS inventory (matching verify-bundle.sh contract)
(
    cd "$staging_dir"
    rm -f SHA256SUMS .bundle-verified
    find . -mindepth 1 -type f ! -name 'SHA256SUMS' ! -name '.bundle-verified' -printf '%P\n' \
        | LC_ALL=C sort \
        | while IFS= read -r rel; do
            hash=$(sha256sum "$rel" | awk '{print $1}')
            printf '%s *%s\n' "$hash" "$rel"
        done > SHA256SUMS
)

# Self-verify bundle integrity and then remove runtime receipt before zipping
bash "${staging_dir}/verify-bundle.sh"
rm -f "${staging_dir}/.bundle-verified"

printf '==> Ubuntu offline bundle staged: %s (%s)\n' "$staging_dir" "$(du -sh "$staging_dir" | awk '{print $1}')"

if $create_archive; then
    command -v zip >/dev/null 2>&1 || { printf 'ERROR: zip is required for --create-archive\n' >&2; exit 1; }
    archive_path="${output_root}/${bundle_name}.zip"
    checksum_path="${archive_path}.sha256"
    rm -f -- "$archive_path" "$checksum_path"
    printf '==> Creating %s...\n' "$archive_path"
    (cd "$output_root" && zip -q -r "$archive_path" "$bundle_name")
    archive_hash=$(sha256sum "$archive_path" | awk '{print $1}')
    printf '%s *%s.zip\n' "$archive_hash" "$bundle_name" > "$checksum_path"
    printf '==> Archive ready: %s (%s, sha256=%s)\n' \
        "$archive_path" "$(du -h "$archive_path" | awk '{print $1}')" "$archive_hash"
fi
