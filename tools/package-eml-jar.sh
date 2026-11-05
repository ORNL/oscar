#!/usr/bin/env bash
set -euo pipefail

# Repackages an administrator's separately licensed LLNL EML VM-250 release
# archive (e.g., EML-VM250-v1.0.2.tar.gz) into a compact single-file runtime
# plugin JAR (e.g., eml-vm250-1.0.2.jar) containing only config/* and jars/*.jar
# for upload in OSCAR SensorHub Admin (Services -> OSCAR Service -> EML Plugin Path).
#
# Never commit or distribute the input archive or generated JAR in OSCAR repositories.

usage() {
    cat >&2 <<'EOF'
Usage: ./tools/package-eml-jar.sh <path-to-EML-VM250.tar.gz-or-dir> [output-eml-jar-path]
EOF
    exit 2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
fi

input_path=$1
if [[ ! -e "$input_path" ]]; then
    echo "ERROR: Input path does not exist: $input_path" >&2
    exit 1
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/oscar-eml-pack.XXXXXX")
chmod 0700 "$work_dir"
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT HUP INT TERM

unpack_dir="$work_dir/unpacked"
stage_dir="$work_dir/stage"
mkdir -p "$unpack_dir" "$stage_dir/config" "$stage_dir/jars" "$stage_dir/META-INF"

if [[ -d "$input_path" ]]; then
    bundle_src="$input_path"
else
    lower_input=$(printf '%s' "$input_path" | tr '[:upper:]' '[:lower:]')
    case "$lower_input" in
        *.tar.gz|*.tgz)
            tar -xzf "$input_path" -C "$unpack_dir"
            ;;
        *.tar)
            tar -xf "$input_path" -C "$unpack_dir"
            ;;
        *.zip|*.jar)
            python3 - "$input_path" "$unpack_dir" <<'PY'
import sys, zipfile
from pathlib import Path
src = Path(sys.argv[1])
dst = Path(sys.argv[2]).resolve()
with zipfile.ZipFile(src, "r") as zf:
    for info in zf.infolist():
        target = (dst / info.filename).resolve()
        if not str(target).startswith(str(dst)):
            raise SystemExit(f"Unsafe archive entry: {info.filename}")
        if info.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(info, "r") as fin, open(target, "wb") as fout:
                fout.write(fin.read())
PY
            ;;
        *)
            echo "ERROR: Unsupported EML input archive format: $input_path" >&2
            exit 1
            ;;
    esac
    bundle_src="$unpack_dir"
fi

analysis_xml=$(find "$bundle_src" -maxdepth 4 -type f -name 'vm250Analysis.xml' | head -n 1 || true)
if [[ -z "$analysis_xml" ]]; then
    echo "ERROR: Could not locate config/vm250Analysis.xml inside $input_path" >&2
    exit 1
fi

config_src=$(dirname -- "$analysis_xml")
bundle_root=$(dirname -- "$config_src")
jars_src="$bundle_root/jars"

if [[ ! -d "$jars_src" ]]; then
    echo "ERROR: Could not locate jars/ directory next to config/ in $input_path" >&2
    exit 1
fi

cp -R "$config_src/." "$stage_dir/config/"
find "$jars_src" -maxdepth 1 -type f -name '*.jar' \
    ! -name '*-sources.jar' \
    ! -name '*-javadoc.jar' \
    -exec cp {} "$stage_dir/jars/" \;

jar_count=$(find "$stage_dir/jars" -maxdepth 1 -type f -name '*.jar' | wc -l | tr -d ' ')
if [[ "$jar_count" -eq 0 ]]; then
    echo "ERROR: No runtime JARs found in $jars_src" >&2
    exit 1
fi

base_name=$(basename -- "$input_path")
version_hint="custom"
if [[ "$base_name" =~ [vV]?([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
    version_hint="${BASH_REMATCH[1]}"
fi

if [[ $# -eq 2 ]]; then
    output_jar=$2
else
    output_jar="$(pwd)/eml-vm250-${version_hint}.jar"
fi

output_dir=$(dirname -- "$output_jar")
mkdir -p "$output_dir"
output_abs="$(cd -- "$output_dir" && pwd)/$(basename -- "$output_jar")"

cat >"$stage_dir/META-INF/MANIFEST.MF" <<EOF
Manifest-Version: 1.0
Bundle-Name: EML-VM250 Runtime Plugin Bundle
Bundle-Version: ${version_hint}
Created-By: OSCAR package-eml-jar
EOF

if command -v jar >/dev/null 2>&1; then
    (
        cd "$stage_dir"
        jar cfm "$output_abs" META-INF/MANIFEST.MF config jars
    )
else
    python3 - "$stage_dir" "$output_abs" <<'PY'
import sys, zipfile
from pathlib import Path
stage = Path(sys.argv[1])
out = Path(sys.argv[2])
with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    manifest = stage / "META-INF" / "MANIFEST.MF"
    zf.write(manifest, "META-INF/MANIFEST.MF")
    for folder in ("config", "jars"):
        for item in sorted((stage / folder).rglob("*")):
            if item.is_file():
                zf.write(item, item.relative_to(stage).as_posix())
PY
fi

chmod 0600 "$output_abs"
if command -v sha256sum >/dev/null 2>&1; then
    digest=$(sha256sum "$output_abs" | awk '{print $1}')
else
    digest=$(shasum -a 256 "$output_abs" | awk '{print $1}')
fi
size_bytes=$(wc -c <"$output_abs" | tr -d ' ')

printf 'Packaged EML plugin JAR: %s (%s bytes, %s runtime JARs, sha256=%s)\n' \
    "$output_abs" "$size_bytes" "$jar_count" "$digest"
