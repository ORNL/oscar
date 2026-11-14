#!/usr/bin/env bash
set -Eeuo pipefail

script_path=${BASH_SOURCE[0]}
case $script_path in */*) script_parent=${script_path%/*} ;; *) script_parent=. ;; esac
script_dir=$(CDPATH= cd -- "$script_parent" && pwd -P)
command_name=${1:-help}
if (($#)); then shift; fi

case "$command_name" in
    backup|backup-verify|backup-prune|restore|archive)
        exec bash "$script_dir/oscar-storage.sh" "$command_name" "$@"
        ;;
esac

hostname_value=''
timezone_value=''
port_value=443
tls_mode='self-signed'
certificate_path=''
private_key_path=''
tls_sans=()
auto_network_sans=true
add_hosts=true
non_interactive=false
skip_start=false
adopt_legacy_volumes=false
adopt_legacy_storage_roots=false
backup_mode_value=''
backup_directory_value=''
prerequisites_mode=auto
log_service=all
log_tail=200
log_tail_explicit=false
log_follow=false
support_output_path=''

usage() {
    cat <<'EOF'
OSCAR deployment administration

  sudo ./oscar.sh init [--hostname oscar.local] [--port 443] [--timezone America/Chicago]
      [--tls-mode self-signed|import] [--certificate FILE --private-key FILE]
      [--tls-san DNS_OR_IP]... [--no-auto-network-sans]
      [--add-hosts-entry] [--skip-hosts-entry] [--skip-start]
      [--backup-mode disabled|single] [--backup-dir ABSOLUTE_PATH]
      [--prerequisites auto|existing|bundled]
  sudo ./oscar.sh check|verify|start|stop|restart|status
  sudo ./oscar.sh upgrade [--adopt-legacy-volumes] [--adopt-legacy-storage-roots]
      [--backup-mode disabled|single] [--backup-dir ABSOLUTE_PATH]
  sudo ./oscar.sh logs [--service all|oscar|postgres|gateway] [--tail 200] [--follow]
  sudo ./oscar.sh support-bundle [--tail 2500] [--output PATH]
  sudo ./oscar.sh backup
  sudo ./oscar.sh backup-verify BACKUP_ID
  sudo ./oscar.sh restore --backup BACKUP_ID --confirm BACKUP_ID
  sudo ./oscar.sh archive status|verify
  sudo ./oscar.sh archive hold list
  sudo ./oscar.sh archive hold create --store-key KEY --id-scope INT (--generation UUID | --observation ID) --reason TEXT
  sudo ./oscar.sh archive hold release --id UUID
  sudo ./oscar.sh archive dry-run --store-key KEY --id-scope INT --before YYYY-MM-DDTHH:MM:SSZ
  sudo ./oscar.sh archive purge --store-key KEY --id-scope INT --plan UUID --token TOKEN
  sudo ./oscar.sh archive export --store-key KEY --id-scope INT --generation UUID --destination PATH

Open oscar.sh with no arguments for the interactive administration menu.
For automated setup, use --non-interactive and provide
OSCAR_SETUP_ADMIN_PASSWORD in the process environment.
EOF
}

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
heading() { printf '\n== %s ==\n' "$*"; }

while (($#)); do
    case "$1" in
        --hostname) hostname_value=${2:?missing hostname}; shift 2 ;;
        --timezone) timezone_value=${2:?missing timezone}; shift 2 ;;
        --port) port_value=${2:?missing port}; shift 2 ;;
        --tls-mode) tls_mode=${2:?missing TLS mode}; shift 2 ;;
        --certificate) certificate_path=${2:?missing certificate path}; shift 2 ;;
        --private-key) private_key_path=${2:?missing private-key path}; shift 2 ;;
        --tls-san) tls_sans+=("${2:?missing TLS subject alternative name}"); shift 2 ;;
        --no-auto-network-sans) auto_network_sans=false; shift ;;
        --add-hosts-entry) add_hosts=true; shift ;;
        --skip-hosts-entry) add_hosts=false; shift ;;
        --non-interactive) non_interactive=true; shift ;;
        --skip-start) skip_start=true; shift ;;
        --adopt-legacy-volumes) adopt_legacy_volumes=true; shift ;;
        --adopt-legacy-storage-roots) adopt_legacy_storage_roots=true; shift ;;
        --backup-mode) backup_mode_value=${2:?missing backup mode}; shift 2 ;;
        --backup-dir) backup_directory_value=${2:?missing backup directory}; shift 2 ;;
        --prerequisites) prerequisites_mode=${2:?missing prerequisite mode}; shift 2 ;;
        --service) log_service=${2:?missing service}; shift 2 ;;
        --tail) log_tail=${2:?missing tail count}; log_tail_explicit=true; shift 2 ;;
        --follow) log_follow=true; shift ;;
        --output|--destination) support_output_path=${2:?missing output path}; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) fail "Unknown option: $1" ;;
    esac
done

[[ $prerequisites_mode =~ ^(auto|existing|bundled)$ ]] || fail '--prerequisites must be auto, existing, or bundled.'
[[ -z $backup_mode_value || $backup_mode_value == disabled || $backup_mode_value == single ]] ||
    fail '--backup-mode must be disabled or single.'
[[ -z $backup_directory_value || $backup_directory_value == /* ]] ||
    fail '--backup-dir must be an operator-selected safe absolute path.'

require_admin() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || fail 'Run this command as root (for example, with sudo).'
}

require_supported_storage_host() {
    [[ $(uname -s) != Darwin ]] ||
        fail "OSCAR $(release_version) storage deployment is not supported on macOS Docker Desktop because its unprivileged bind-mount transport cannot preserve both service write access and administrator-only root identity protection. Use Ubuntu 24.04 or Windows."
}

offline_manifest_hash() {
    [[ -f $script_dir/SHA256SUMS ]] || return 1
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$script_dir/SHA256SUMS" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum --algorithm 256 "$script_dir/SHA256SUMS" | awk '{print $1}'
    else
        fail 'sha256sum or shasum is required to verify an offline bundle.'
    fi
}

offline_verification_status() {
    local manifest_hash verified_hash
    manifest_hash=$(offline_manifest_hash) || { printf 'not an offline bundle'; return; }
    [[ -f $script_dir/.bundle-verified ]] || { printf 'not verified'; return; }
    IFS= read -r verified_hash <"$script_dir/.bundle-verified" || true
    if [[ $verified_hash == "$manifest_hash" ]]; then
        printf 'verified'
    else
        printf 'verification required (bundle changed)'
    fi
}

sync_receipt_path() {
    sync -f "$1" 2>/dev/null || sync
}

atomic_replace_receipt() {
    local source=$1 destination=$2
    if mv --help 2>&1 | grep -q -- '--no-target-directory'; then
        mv -fT -- "$source" "$destination"
    elif command -v perl >/dev/null 2>&1; then
        perl -e 'rename($ARGV[0], $ARGV[1]) or die "rename: $!\n"' "$source" "$destination"
    else
        fail 'An atomic same-directory rename implementation is required.'
    fi
}

write_offline_verification_receipt() {
    local manifest_hash=$1 receipt="$script_dir/.bundle-verified"
    temporary_receipt=$(mktemp "$script_dir/.bundle-verified.tmp.XXXXXX") ||
        fail 'Could not create a private offline-verification receipt.'
    cleanup_offline_receipt() { rm -f -- "$temporary_receipt"; }
    trap cleanup_offline_receipt EXIT HUP INT TERM
    printf '%s\n' "$manifest_hash" >"$temporary_receipt"
    chmod 0644 "$temporary_receipt"
    sync_receipt_path "$temporary_receipt"
    if [[ -e $receipt || -L $receipt ]]; then
        [[ -f $receipt && ! -L $receipt ]] || fail "Offline verification receipt is not a regular, non-symlink file: $receipt"
    fi
    atomic_replace_receipt "$temporary_receipt" "$receipt" || fail 'Offline verification receipt could not be atomically replaced.'
    sync_receipt_path "$script_dir"
    trap - EXIT HUP INT TERM
}

assert_offline_bundle_integrity() {
    local manifest_hash
    manifest_hash=$(offline_manifest_hash) || return 0
    heading 'Offline bundle integrity'
    [[ -f $script_dir/verify-bundle.sh ]] || fail 'The offline bundle verifier is missing.'
    bash "$script_dir/verify-bundle.sh" || fail 'Offline bundle integrity verification failed.'
    write_offline_verification_receipt "$manifest_hash"
}

docker_ready() {
    command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

install_bundled_prerequisites() {
    heading 'Docker prerequisite'
    case "$(uname -s)" in
        Linux)
            local installer_dir="$script_dir/installers/ubuntu-24.04-x86_64"
            local packages=()
            if [[ -d $installer_dir ]]; then
                while IFS= read -r -d '' package; do packages+=("$package"); done < <(find "$installer_dir" -maxdepth 1 -type f -name '*.deb' -print0)
            fi
            ((${#packages[@]})) || fail "Docker is unavailable. Place the official Ubuntu 24.04 x86-64 Docker .deb bundle in $installer_dir and run setup again."
            printf 'Installing bundled official Docker packages...\n'
            dpkg -i "${packages[@]}"
            systemctl enable --now docker
            ;;
        *) fail "Unsupported setup host: $(uname -s)" ;;
    esac

    for _attempt in {1..90}; do
        docker_ready && return
        sleep 2
    done
    fail 'Docker is installed but its engine is not ready. Start Docker, then run setup again.'
}

require_docker() {
    docker_ready && return
    if [[ $prerequisites_mode == existing ]]; then
        fail "The existing Docker installation is unavailable or not ready. Start Docker and ensure 'docker compose' works, or rerun init with --prerequisites auto."
    fi
    install_bundled_prerequisites
    docker_ready || fail 'Docker Engine and Docker Compose are required.'
}

is_ip_address() {
    local value=$1
    if [[ $value =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local octet
        IFS=. read -r -a octets <<<"$value"
        for octet in "${octets[@]}"; do ((10#$octet <= 255)) || return 1; done
        return 0
    fi
    [[ $value == *:* && $value =~ ^[0-9A-Fa-f:]+$ ]]
}

valid_hostname() {
    local value=$1 label
    is_ip_address "$value" && return 0
    ((${#value} >= 1 && ${#value} <= 253)) || return 1
    IFS=. read -r -a labels <<<"$value"
    for label in "${labels[@]}"; do
        ((${#label} >= 1 && ${#label} <= 63)) || return 1
        [[ $label =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ || $label =~ ^[A-Za-z0-9]$ ]] || return 1
    done
}

append_unique_tls_san() {
    local candidate=$1 existing
    valid_hostname "$candidate" || fail "Invalid TLS subject alternative name: $candidate"
    for existing in "${resolved_tls_sans[@]:-}"; do
        [[ $existing == "$candidate" ]] && return
    done
    resolved_tls_sans+=("$candidate")
}

detect_network_tls_sans() {
    local interface address dns_name
    if command -v ip >/dev/null 2>&1; then
        while read -r interface address; do
            case "$interface" in
                lo|docker*|br-*|veth*|virbr*|cni*|podman*) continue ;;
            esac
            address=${address%%/*}
            address=${address%%%*}
            # Ordinary SLAAC privacy addresses rotate far sooner than the
            # certificate. Include IPv6 automatically only for Tailscale,
            # whose node address is stable; site-stable IPv6 remains explicit.
            if [[ $address == *:* && $interface != tailscale* ]]; then continue; fi
            is_ip_address "$address" && append_unique_tls_san "$address"
        done < <(ip -o address show up scope global 2>/dev/null | awk '{print $2, $4}')
    fi

    # Tailscale IPs are normally discovered from tailscale0 above. Include its
    # stable MagicDNS name as well when the client is installed and connected.
    if command -v tailscale >/dev/null 2>&1; then
        dns_name=$(tailscale status --json 2>/dev/null |
            sed -n 's/.*"DNSName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)
        dns_name=${dns_name%.}
        [[ -z $dns_name ]] || append_unique_tls_san "$dns_name"
    fi
}

resolve_tls_sans() {
    local primary_name=$1 explicit
    local -a requested_sans=()
    [[ -z ${tls_sans[*]-} ]] || requested_sans=("${tls_sans[@]}")
    resolved_tls_sans=()
    append_unique_tls_san "$primary_name"
    if [[ -n ${requested_sans[*]-} ]]; then
        for explicit in "${requested_sans[@]}"; do append_unique_tls_san "$explicit"; done
    fi
    if [[ $tls_mode == self-signed ]] && $auto_network_sans; then detect_network_tls_sans; fi
}

tls_san_extension() {
    local value prefix output=''
    for value in "${resolved_tls_sans[@]}"; do
        prefix=DNS
        is_ip_address "$value" && prefix=IP
        [[ -z $output ]] || output+=,
        output+="$prefix:$value"
    done
    printf '%s' "$output"
}

tls_url_host() {
    local value=$1
    if [[ $value == *:* ]]; then printf '[%s]' "$value"; else printf '%s' "$value"; fi
}

print_client_access_instructions() {
    local value fingerprint
    printf '\nOSCAR client URLs covered by this certificate:\n'
    for value in "${resolved_tls_sans[@]}"; do
        printf '  https://%s:%s/\n' "$(tls_url_host "$value")" "$port_value"
    done
    if [[ $tls_mode == self-signed ]]; then
        printf 'LAN/Tailscale clients must trust the public certificate: %s\n' "$script_dir/tls/server.crt"
    else
        printf 'LAN/Tailscale clients must trust the imported certificate issuer chain presented by: %s\n' "$script_dir/tls/server.crt"
    fi
    fingerprint=$(docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
        --workdir / --user 0:0 --entrypoint openssl --volume "$script_dir/tls:/tls:ro" "$(oscar_image)" \
        x509 -in /tls/server.crt -noout -fingerprint -sha256)
    printf 'Verify before trusting: %s\n' "$fingerprint"
    printf 'Copy only server.crt to clients; never copy tls/server.key.\n'
    printf 'DNS names must resolve to this host on each client. Direct IP URLs require that IP in the list above.\n'
    printf 'The gateway listens on host interfaces. Permit inbound TCP %s only from approved LAN/Tailscale clients; permit TCP 80 only when the hostname redirect is required.\n' "$port_value"
}

set_env_value() {
    local name=$1 value=$2 env_file="$script_dir/.env" source_file="$script_dir/.env.example" temp_file
    [[ -f $env_file ]] && source_file=$env_file
    temp_file=$(mktemp "$script_dir/.env.tmp.XXXXXX")
    awk -v name="$name" -v value="$value" -F= '
        BEGIN { found=0 }
        $1 == name { print name "=" value; found=1; next }
        { print }
        END { if (!found) print name "=" value }
    ' "$source_file" >"$temp_file"
    chmod 600 "$temp_file"
    mv -f "$temp_file" "$env_file"
}

get_env_value() {
    local name=$1 env_file="$script_dir/.env"
    [[ -f $env_file ]] || return 0
    awk -F= -v name="$name" '$1 == name { print substr($0, index($0, "=") + 1); exit }' "$env_file"
}

valid_backup_mode() { [[ $1 == disabled || $1 == single ]]; }

configured_backup_mode() {
    local mode
    mode=$(get_env_value OSCAR_BACKUP_MODE)
    valid_backup_mode "$mode" || fail 'OSCAR_BACKUP_MODE must be exactly disabled or single.'
    printf '%s' "$mode"
}

normalize_backup_mode_for_upgrade() {
    local env_file="$script_dir/.env" count mode
    count=$(awk -F= '$1 == "OSCAR_BACKUP_MODE" { count++ } END { print count+0 }' "$env_file")
    if ((count == 0)); then
        # Every release before this setting continuously prepared backup/WAL
        # storage. Preserve that operator capability on upgrade; only fresh
        # installations default to disabled.
        set_env_value OSCAR_BACKUP_MODE single
        printf 'Preserved the legacy backup policy as OSCAR_BACKUP_MODE=single.\n'
        return
    fi
    ((count == 1)) || fail 'Upgrade source .env contains duplicate OSCAR_BACKUP_MODE bindings.'
    mode=$(get_env_value OSCAR_BACKUP_MODE)
    valid_backup_mode "$mode" || fail 'OSCAR_BACKUP_MODE must be exactly disabled or single.'
}

require_unique_literal_environment_keys() {
    local env_file="$script_dir/.env" name count value mode required
    [[ -f $env_file && ! -L $env_file ]] || fail 'Deployment .env must be a regular, non-symlink file.'
    mode=$(configured_backup_mode)
    for name in OSCAR_VERSION OSCAR_DEPLOYMENT_ID OSCAR_ARCHIVE_DIR OSCAR_BACKUP_MODE OSCAR_BACKUP_DIR OSCAR_WAL_ARCHIVE_DIR; do
        count=$(awk -F= -v name="$name" '$1 == name { count++ } END { print count+0 }' "$env_file")
        required=false
        case $name in
            OSCAR_VERSION|OSCAR_DEPLOYMENT_ID|OSCAR_ARCHIVE_DIR|OSCAR_BACKUP_MODE) required=true ;;
            OSCAR_BACKUP_DIR) [[ $mode == single ]] && required=true ;;
        esac
        if $required; then
            ((count == 1)) || fail "Deployment .env must contain exactly one literal $name binding."
        else
            ((count <= 1)) || fail "Deployment .env contains duplicate optional $name bindings."
            ((count == 1)) || continue
        fi
        value=$(get_env_value "$name")
        [[ -n $value && $value != *'$'* && $value != *'#'* && $value != *\"* && $value != *\'* &&
           $value != *[[:space:]]* ]] || fail "Deployment .env contains a Compose-interpreted or nonliteral $name value."
        [[ $name != OSCAR_BACKUP_MODE ]] || valid_backup_mode "$value" ||
            fail 'OSCAR_BACKUP_MODE must be exactly disabled or single.'
    done
}

# A pre-3.11.0 deployment legitimately has no deployment identity or external
# storage-root bindings yet.  Validate everything that is present without
# making the documented one-time adoption path depend on the new schema.  The
# fully normalized environment is subjected to the strict validator later.
require_upgrade_environment_keys() {
    local env_file="$script_dir/.env" name count value
    [[ -f $env_file && ! -L $env_file ]] || fail 'Deployment .env must be a regular, non-symlink file.'
    for name in OSCAR_VERSION OSCAR_DEPLOYMENT_ID OSCAR_ARCHIVE_DIR OSCAR_BACKUP_MODE OSCAR_BACKUP_DIR OSCAR_WAL_ARCHIVE_DIR; do
        count=$(awk -F= -v name="$name" '$1 == name { count++ } END { print count+0 }' "$env_file")
        if [[ $name == OSCAR_VERSION ]]; then
            ((count == 1)) || fail 'Upgrade source .env must contain exactly one literal OSCAR_VERSION binding.'
        else
            ((count <= 1)) || fail "Upgrade source .env contains duplicate $name bindings."
        fi
        if ((count == 1)); then
            value=$(get_env_value "$name")
            [[ -n $value && $value != *'$'* && $value != *'#'* && $value != *\"* && $value != *\'* &&
               $value != *[[:space:]]* ]] || fail "Upgrade source .env contains a Compose-interpreted or nonliteral $name value."
            [[ $name != OSCAR_BACKUP_MODE ]] || valid_backup_mode "$value" ||
                fail 'OSCAR_BACKUP_MODE must be exactly disabled or single.'
        fi
    done
}

require_managed_environment_bindings() {
    local name value mode
    require_unique_literal_environment_keys
    require_canonical_credential_bindings
    mode=$(configured_backup_mode)
    for name in OSCAR_ARCHIVE_DIR; do
        value=$(get_env_value "$name")
        [[ $value == /* ]] || fail "$name must be an absolute stable storage-root path."
    done
    if [[ $mode == single ]]; then
        value=$(get_env_value OSCAR_BACKUP_DIR)
        [[ $value == /* ]] || fail 'OSCAR_BACKUP_DIR must be an absolute stable storage-root path.'
    fi
    value=$(get_env_value OSCAR_WAL_ARCHIVE_DIR)
    [[ -z $value || $value == /* ]] || fail 'A preserved OSCAR_WAL_ARCHIVE_DIR must be an absolute path.'
}

is_pre_3110_release_version() {
    local value=$1 major minor patch
    [[ $value =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
    major=$((10#${BASH_REMATCH[1]}))
    minor=$((10#${BASH_REMATCH[2]}))
    patch=$((10#${BASH_REMATCH[3]}))
    ((major < 3 || (major == 3 && minor < 11)))
}

normalize_legacy_backup_key_binding() {
    local env_file="$script_dir/.env" source_version source_version_count count
    [[ -f $env_file && ! -L $env_file ]] || fail 'Deployment .env must be a regular file.'
    [[ $(configured_backup_mode) == single ]] || return 0
    source_version_count=$(awk -F= '$1 == "OSCAR_VERSION" { count++ } END { print count+0 }' "$env_file")
    ((source_version_count == 1)) || return 0
    source_version=$(get_env_value OSCAR_VERSION)
    is_pre_3110_release_version "$source_version" || return 0
    count=$(awk -F= '$1 == "OSCAR_BACKUP_KEY_FILE" { count++ } END { print count+0 }' "$env_file")
    if ((count == 0)); then
        set_env_value OSCAR_BACKUP_KEY_FILE ./secrets/backup-key.txt
        printf 'Added the canonical backup-key binding required for a pre-3.11.0 deployment upgrade.\n'
    fi
}

require_canonical_credential_bindings() {
    local name expected value count env_file="$script_dir/.env" mode
    [[ -f $env_file && ! -L $env_file ]] || fail 'Deployment .env must be a regular file.'
    mode=$(configured_backup_mode)
    while IFS=: read -r name expected; do
        [[ $name != OSCAR_BACKUP_KEY_FILE || $mode == single ]] || continue
        count=$(awk -F= -v name="$name" '$1 == name { count++ } END { print count+0 }' "$env_file")
        value=$(get_env_value "$name")
        [[ $count == 1 && $value == "$expected" ]] ||
            fail "$name must use the canonical supported binding $expected. Custom credential paths are not supported."
    done <<'EOF'
OSCAR_SECRETS_DIR:./secrets
OSCAR_TLS_DIR:./tls
OSCAR_BACKUP_KEY_FILE:./secrets/backup-key.txt
EOF
}

configure_storage_paths() {
    # Storage must outlive a versioned release directory. Persist absolute
    # sibling paths in .env so copying .env into a clean release cannot silently
    # attach empty archive/backup directories. A retired legacy-WAL binding is
    # preserved byte-for-byte when present but is never created or rewritten.
    local parent stable_root name suffix value legacy_default sibling_default
    parent=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
    stable_root="$parent/oscar-storage"
    while IFS=: read -r name suffix; do
        [[ $name != OSCAR_BACKUP_DIR || $(configured_backup_mode) == single ]] || continue
        value=$(get_env_value "$name")
        case $name in
            OSCAR_ARCHIVE_DIR) legacy_default=./data/archive ;;
            OSCAR_BACKUP_DIR) legacy_default=./backups ;;
        esac
        sibling_default="../oscar-storage/$suffix"
        if [[ -z $value || $value == "$legacy_default" || $value == "$sibling_default" ]]; then
            set_env_value "$name" "$stable_root/$suffix"
        elif [[ $value == /* ]]; then
            # The storage CLI performs the strict normalized-path,
            # overlap, and symlink-component checks before creating it.
            set_env_value "$name" "$value"
        else
            fail "$name must be an absolute path. Relative custom storage paths cannot be relocated safely during an upgrade: $value"
        fi
    done <<'EOF'
OSCAR_ARCHIVE_DIR:archive
OSCAR_BACKUP_DIR:backups
EOF
}

valid_deployment_id() {
    [[ $1 =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

volume_deployment_label() {
    local label
    label=$(docker volume inspect --format '{{ index .Labels "com.botts.oscar.deployment-id" }}' "$1" 2>/dev/null || true)
    [[ $label == '<no value>' ]] && label=''
    printf '%s' "$label"
}

ensure_deployment_id() {
    local deployment_id hex
    deployment_id=$(get_env_value OSCAR_DEPLOYMENT_ID)
    if [[ -z $deployment_id ]]; then
        hex=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
        deployment_id="${hex:0:8}-${hex:8:4}-4${hex:13:3}-8${hex:17:3}-${hex:20:12}"
        set_env_value OSCAR_DEPLOYMENT_ID "$deployment_id"
    fi
    valid_deployment_id "$deployment_id" ||
        fail 'OSCAR_DEPLOYMENT_ID in .env is missing or invalid.'
    printf '%s' "$deployment_id"
}

write_init_receipt() {
    local deployment_id=$1 state=$2 receipt="$script_dir/.oscar-init-state" temporary
    temporary=$(mktemp "$script_dir/.oscar-init-state.tmp.XXXXXX")
    {
        printf 'format=oscar-init-state\n'
        printf 'version=1\n'
        printf 'deployment_id=%s\n' "$deployment_id"
        printf 'state=%s\n' "$state"
    } >"$temporary"
    chmod 0600 "$temporary"
    mv -f "$temporary" "$receipt"
}

read_init_receipt_value() {
    local name=$1 receipt="$script_dir/.oscar-init-state"
    [[ -f $receipt && ! -L $receipt ]] || return 0
    awk -F= -v name="$name" '$1 == name { print substr($0, index($0, "=") + 1); exit }' "$receipt"
}

validate_init_receipt() {
    local receipt="$script_dir/.oscar-init-state" deployment_id state
    [[ -f $receipt && ! -L $receipt ]] || fail 'The OSCAR initialization receipt is missing, is not a regular file, or is a symbolic link.'
    [[ $(wc -l <"$receipt" | tr -d '[:space:]') == 4 ]] || fail 'The OSCAR initialization receipt has an invalid number of fields.'
    [[ $(grep -Fxc 'format=oscar-init-state' "$receipt") == 1 ]] || fail 'The OSCAR initialization receipt format is invalid.'
    [[ $(grep -Fxc 'version=1' "$receipt") == 1 ]] || fail 'The OSCAR initialization receipt version is invalid.'
    deployment_id=$(read_init_receipt_value deployment_id)
    state=$(read_init_receipt_value state)
    valid_deployment_id "$deployment_id" || fail 'The OSCAR initialization receipt deployment identity is invalid.'
    [[ $state == INITIALIZING || $state == COMPLETE ]] || fail 'The OSCAR initialization receipt state is invalid.'
    [[ $(grep -Ec '^deployment_id=' "$receipt") == 1 && $(grep -Ec '^state=' "$receipt") == 1 ]] ||
        fail 'The OSCAR initialization receipt contains duplicate or missing fields.'
}

read_adoption_receipt_value() {
    local name=$1 receipt="$script_dir/.oscar-volume-adoption"
    [[ -f $receipt && ! -L $receipt ]] || return 0
    awk -F= -v name="$name" '$1 == name { print substr($0, index($0, "=") + 1); exit }' "$receipt"
}

write_volume_adoption_receipt() {
    local deployment_id=$1 receipt="$script_dir/.oscar-volume-adoption" temporary state_created postgres_created
    state_created=$(docker volume inspect --format '{{.CreatedAt}}' oscar_oscar_state)
    postgres_created=$(docker volume inspect --format '{{.CreatedAt}}' oscar_postgres_data)
    [[ -n $state_created && -n $postgres_created ]] || fail 'Docker did not provide stable creation identities for the legacy volumes.'
    temporary=$(mktemp "$script_dir/.oscar-volume-adoption.tmp.XXXXXX")
    {
        printf 'format=oscar-volume-adoption\n'
        printf 'version=1\n'
        printf 'deployment_id=%s\n' "$deployment_id"
        printf 'oscar_state_created_at=%s\n' "$state_created"
        printf 'postgres_data_created_at=%s\n' "$postgres_created"
        printf 'adopted_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$temporary"
    chmod 0600 "$temporary"
    mv -f "$temporary" "$receipt"
}

validate_volume_adoption_receipt() {
    local deployment_id=$1 receipt="$script_dir/.oscar-volume-adoption" state_created postgres_created
    [[ -f $receipt && ! -L $receipt ]] || return 1
    [[ $(wc -l <"$receipt" | tr -d '[:space:]') == 6 &&
       $(grep -Fxc 'format=oscar-volume-adoption' "$receipt") == 1 &&
       $(grep -Fxc 'version=1' "$receipt") == 1 &&
       $(grep -Ec '^deployment_id=' "$receipt") == 1 &&
       $(grep -Ec '^oscar_state_created_at=' "$receipt") == 1 &&
       $(grep -Ec '^postgres_data_created_at=' "$receipt") == 1 &&
       $(grep -Ec '^adopted_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$receipt") == 1 ]] || return 1
    [[ $(read_adoption_receipt_value deployment_id) == "$deployment_id" ]] || return 1
    state_created=$(docker volume inspect --format '{{.CreatedAt}}' oscar_oscar_state 2>/dev/null || true)
    postgres_created=$(docker volume inspect --format '{{.CreatedAt}}' oscar_postgres_data 2>/dev/null || true)
    [[ -n $state_created && -n $postgres_created &&
       $(read_adoption_receipt_value oscar_state_created_at) == "$state_created" &&
       $(read_adoption_receipt_value postgres_data_created_at) == "$postgres_created" ]]
}

assert_deployment_volume_ownership() {
    local allow_adoption=${1:-false} deployment_id state_label postgres_label
    deployment_id=$(get_env_value OSCAR_DEPLOYMENT_ID)
    if ! valid_deployment_id "$deployment_id"; then
        $allow_adoption || fail 'OSCAR_DEPLOYMENT_ID is missing or invalid. Legacy volumes require the explicit --adopt-legacy-volumes upgrade acknowledgment.'
        deployment_id=$(ensure_deployment_id)
    fi
    docker volume inspect oscar_oscar_state >/dev/null 2>&1 || fail 'Required Docker volume is missing: oscar_oscar_state.'
    docker volume inspect oscar_postgres_data >/dev/null 2>&1 || fail 'Required Docker volume is missing: oscar_postgres_data.'
    state_label=$(volume_deployment_label oscar_oscar_state)
    postgres_label=$(volume_deployment_label oscar_postgres_data)
    if [[ $state_label == "$deployment_id" && $postgres_label == "$deployment_id" ]]; then
        return 0
    fi
    if [[ $state_label != "$postgres_label" || ( -n $state_label && $state_label != uninitialized ) ]]; then
        fail 'OSCAR named volumes have mixed or foreign deployment identities. Refusing to attach or mutate them.'
    fi
    if validate_volume_adoption_receipt "$deployment_id"; then
        return 0
    fi
    $allow_adoption || fail 'The existing volumes are unlabelled legacy state. Re-run upgrade once with --adopt-legacy-volumes after verifying that both volumes belong to this deployment; preserve .oscar-volume-adoption with future clean-directory upgrades.'
    write_volume_adoption_receipt "$deployment_id"
    printf 'Adopted legacy OSCAR volumes for deployment %s; audit receipt: %s/.oscar-volume-adoption\n' "$deployment_id" "$script_dir"
}

preflight_fresh_init() {
    local deployment_id receipt_id receipt_state state_exists=false volume label
    deployment_id=$(ensure_deployment_id)
    for volume in oscar_oscar_state oscar_postgres_data; do
        docker volume inspect "$volume" >/dev/null 2>&1 && state_exists=true || true
    done
    docker ps -aq --filter label=com.docker.compose.project=oscar | grep -q . && state_exists=true || true

    receipt_id=$(read_init_receipt_value deployment_id)
    receipt_state=$(read_init_receipt_value state)
    if [[ -n $receipt_id || -n $receipt_state ]]; then
        validate_init_receipt
        [[ $receipt_id == "$deployment_id" ]] ||
            fail 'The local OSCAR initialization receipt does not match .env.'
    elif $state_exists; then
        fail 'Existing Docker state for project oscar was found, but this directory did not initialize it. Use upgrade to retain that deployment. On an explicitly disposable test host, stop OSCAR and remove the old oscar project volumes before init.'
    else
        write_init_receipt "$deployment_id" INITIALIZING
        receipt_state=INITIALIZING
    fi

    if [[ $receipt_state == COMPLETE ]]; then
        for volume in oscar_oscar_state oscar_postgres_data; do
            docker volume inspect "$volume" >/dev/null 2>&1 ||
                fail "Initialized OSCAR volume is missing: $volume. Refusing to replace it silently."
        done
    fi
    for volume in oscar_oscar_state oscar_postgres_data; do
        if docker volume inspect "$volume" >/dev/null 2>&1; then
            label=$(volume_deployment_label "$volume")
            [[ $label == "$deployment_id" ]] ||
                fail "Docker volume $volume belongs to another or unlabelled deployment. Use upgrade, or explicitly reset this disposable test deployment."
        fi
    done
    printf '%s' "$deployment_id"
}

ensure_fresh_init_volumes() {
    local deployment_id receipt_id receipt_state volume label
    validate_init_receipt
    deployment_id=$(ensure_deployment_id)
    receipt_id=$(read_init_receipt_value deployment_id)
    receipt_state=$(read_init_receipt_value state)
    [[ $receipt_id == "$deployment_id" ]] || fail 'The OSCAR initialization receipt does not match .env.'
    [[ $receipt_state == INITIALIZING || $receipt_state == COMPLETE ]] ||
        fail 'The OSCAR initialization receipt state is invalid.'
    for volume in oscar_oscar_state oscar_postgres_data; do
        if ! docker volume inspect "$volume" >/dev/null 2>&1; then
            [[ $receipt_state == INITIALIZING ]] ||
                fail "Initialized OSCAR volume is missing: $volume. Refusing to replace it silently."
            docker volume create --label "com.botts.oscar.deployment-id=$deployment_id" "$volume" >/dev/null
        fi
        label=$(volume_deployment_label "$volume")
        [[ $label == "$deployment_id" ]] ||
            fail "Docker volume $volume does not belong to this OSCAR initialization."
    done
}

random_password() { head -c 32 /dev/urandom | base64 | tr -d '\r\n'; }

read_admin_password() {
    if [[ -n ${OSCAR_SETUP_ADMIN_PASSWORD:-} ]]; then
        ((${#OSCAR_SETUP_ADMIN_PASSWORD} >= 14)) || fail 'OSCAR_SETUP_ADMIN_PASSWORD must contain at least 14 characters.'
        printf '%s' "$OSCAR_SETUP_ADMIN_PASSWORD"
        return
    fi
    $non_interactive && fail 'Set OSCAR_SETUP_ADMIN_PASSWORD for non-interactive initialization.'
    local first second
    while true; do
        read -r -s -p 'Initial OSCAR administrator password: ' first; printf '\n' >&2
        read -r -s -p 'Confirm administrator password: ' second; printf '\n' >&2
        ((${#first} >= 14)) || { printf 'Use at least 14 characters.\n' >&2; continue; }
        [[ $first == "$second" ]] || { printf 'Passwords do not match.\n' >&2; continue; }
        printf '%s' "$first"
        return
    done
}

write_secret() {
    local path=$1 value=$2
    if [[ ! -e $path && ! -L $path ]]; then
        (set -C; umask 077; printf '%s' "$value" >"$path") || fail "Could not create secret without replacing an existing path: $path"
    fi
}

assert_safe_creatable_directory_path() {
    local value=$1 remainder=${1#/} current='' component
    IFS='/' read -r -a components <<<"$remainder"
    for component in "${components[@]}"; do
        [[ -n $component ]] || continue
        current="$current/$component"
        [[ ! -L $current ]] || fail "Privileged deployment paths must not contain symbolic links: $current"
        if [[ -e $current ]]; then
            [[ -d $current ]] || fail "Privileged deployment path component is not a directory: $current"
        else
            return 0
        fi
    done
}

assert_deployment_paths_safe() {
    local directory leaf
    assert_safe_creatable_directory_path "$script_dir"
    [[ -d $script_dir && ! -L $script_dir ]] || fail "Release directory is unsafe: $script_dir"
    for directory in "$script_dir/secrets" "$script_dir/tls"; do
        assert_safe_creatable_directory_path "$directory"
        if [[ -e $directory || -L $directory ]]; then
            [[ -d $directory && ! -L $directory ]] || fail "Deployment credential directory is unsafe: $directory"
        fi
    done
    for leaf in "$script_dir/.env" "$script_dir/secrets/oscar-admin-password.txt" \
        "$script_dir/secrets/oscar-db-password.txt" "$script_dir/secrets/postgres-bootstrap-password.txt" \
        "$script_dir/secrets/backup-key.txt" "$script_dir/tls/server.crt" "$script_dir/tls/server.key"; do
        if [[ -e $leaf || -L $leaf ]]; then
            [[ -f $leaf && ! -L $leaf ]] || fail "Deployment credential file is unsafe: $leaf"
        fi
    done
}

protect_deployment_files() {
    chmod 700 "$script_dir/secrets" "$script_dir/tls"
    # Compose file-backed secrets retain host file modes. The protected parent
    # prevents host traversal while 0644 lets the non-root containers read mounts.
    chmod 644 "$script_dir"/secrets/*.txt "$script_dir/tls/server.crt" "$script_dir/tls/server.key"
    chmod 600 "$script_dir/.env"
}

allow_docker_desktop_bind_mount_access() {
    [[ $(uname -s) == Darwin ]] || return 0
    [[ -n ${SUDO_UID:-} && -n ${SUDO_GID:-} ]] || return 0
    chown "$SUDO_UID:$SUDO_GID" "$script_dir/secrets" "$script_dir/tls"
}

oscar_image() {
    local version=local
    if [[ -f $script_dir/.env ]]; then
        version=$(awk -F= '$1 == "OSCAR_VERSION" { print substr($0, index($0, "=") + 1); exit }' "$script_dir/.env")
        [[ -n $version ]] || version=local
    fi
    printf 'oscar:%s' "$version"
}

release_version() {
    local version
    [[ -f $script_dir/.env.example ]] || fail 'The release version file .env.example is missing.'
    version=$(awk -F= '$1 == "OSCAR_VERSION" { print substr($0, index($0, "=") + 1); exit }' "$script_dir/.env.example")
    [[ -n $version ]] || fail 'OSCAR_VERSION is missing from .env.example.'
    printf '%s' "$version"
}

container_image_exists() { docker image inspect "$1" >/dev/null 2>&1; }

required_images() {
    compose config --images | awk 'NF && !seen[$0]++'
}

assert_deployment_images_available() {
    local missing=() image
    while IFS= read -r image; do container_image_exists "$image" || missing+=("$image"); done < <(required_images)
    ((${#missing[@]} == 0)) || fail "Required container images are unavailable: ${missing[*]}. Run 'oscar init' or 'oscar upgrade'."
}

prepare_deployment_images() {
    local missing=() image
    if [[ -f $script_dir/offline-images.tar ]]; then
        # The archive was authenticated by assert_offline_bundle_integrity for
        # every mutating setup run. Always load it, even when matching tags
        # already exist locally: a tag alone does not bind image content to the
        # authenticated release bundle.
        heading 'Importing offline container images'
        docker load --input "$script_dir/offline-images.tar"
    else
        # Connected releases build both local contexts on every mutating init/
        # upgrade. A matching mutable pre-release tag is not proof that its
        # bytes came from this extracted release (and can otherwise leave an
        # older PostGIS restore helper paired with a newer OSCAR image).
        heading 'Building deployment images'
        compose build oscar postgres

        # Recheck the complete inventory after building the two local images.
        # If the pinned gateway tag is already present, pulling it again is
        # unnecessary and can make an otherwise offline-capable upgrade depend
        # on a registry credential helper. Pull only when an image is still
        # missing after the local builds have completed.
        missing=()
        while IFS= read -r image; do container_image_exists "$image" || missing+=("$image"); done < <(required_images)
        ((${#missing[@]} == 0)) || compose pull gateway
    fi

    missing=()
    while IFS= read -r image; do container_image_exists "$image" || missing+=("$image"); done < <(required_images)
    ((${#missing[@]} == 0)) || fail "Required container images are unavailable: ${missing[*]}"
}

# Capability-free uid0 helpers use a neutral workdir rather than inheriting the
# image-owned, mode-0700 OSCAR state workdir.
initialize_tls() {
    local name=$1 tls_dir="$script_dir/tls" cert="$script_dir/tls/server.crt" key="$script_dir/tls/server.key" image san_value name_check output
    if [[ (-e $cert && ! -e $key) || (! -e $cert && -e $key) ]]; then fail 'TLS setup is incomplete. Remove the partial certificate/key pair or provide both files.'; fi
    image=$(oscar_image)

    if [[ -e $cert && -e $key && $tls_mode == 'self-signed' ]]; then
        if ! docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
            --tmpfs /tmp:rw,noexec,nosuid,nodev --workdir / --user 0:0 --entrypoint openssl --volume "${tls_dir}:/tls:ro" "$image" \
            x509 -in /tls/server.crt -noout -checkend 0 >/dev/null 2>&1; then
            echo 'Existing self-signed TLS certificate has expired; regenerating a new 10-year certificate.'
            rm -f "$cert" "$key"
        fi
    fi

    if [[ ! -e $cert && ! -e $key ]]; then
        case "$tls_mode" in
            import)
                [[ -f $certificate_path ]] || fail 'A valid --certificate PEM file is required.'
                [[ -f $private_key_path ]] || fail 'A valid --private-key PEM file is required.'
                cp "$certificate_path" "$cert"
                cp "$private_key_path" "$key"
                ;;
            self-signed)
                docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
                    --tmpfs /tmp:rw,noexec,nosuid,nodev --workdir / --user 0:0 --entrypoint openssl --volume "${tls_dir}:/out" "$image" \
                    req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 -subj "/CN=$name" \
                    -addext "subjectAltName=$(tls_san_extension)" -keyout /out/server.key -out /out/server.crt
                ;;
            *) fail "Unsupported TLS mode: $tls_mode" ;;
        esac
    fi

    # The parent directory remains mode 0700, while file-backed Compose secrets
    # must be readable by the deliberately non-root service processes.
    chmod 644 "$cert" "$key"
    docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
        --tmpfs /tmp:rw,noexec,nosuid,nodev --workdir / --user 0:0 --entrypoint sh --volume "${tls_dir}:/tls:ro" "$image" -c \
        'openssl x509 -in /tls/server.crt -pubkey -noout >/tmp/cert.pub && openssl pkey -in /tls/server.key -pubout >/tmp/key.pub && cmp -s /tmp/cert.pub /tmp/key.pub' \
        || fail 'The TLS certificate and private key are invalid or do not match.'
    for san_value in "${resolved_tls_sans[@]}"; do
        name_check=-checkhost
        is_ip_address "$san_value" && name_check=-checkip
        # openssl x509 -checkhost/-checkip reports a mismatch in its text but
        # still exits zero. Inspect the result text explicitly.
        docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
            --tmpfs /tmp:rw,noexec,nosuid,nodev --workdir / --user 0:0 --entrypoint sh --volume "${tls_dir}:/tls:ro" "$image" -eu -c '
            output=$(openssl x509 -in /tls/server.crt -noout "$1" "$2")
            printf "%s\n" "$output"
            case $output in *" does match certificate") ;; *) exit 1 ;; esac
        ' tls-name-check "$name_check" "$san_value" \
            || fail "The TLS certificate is not valid for $san_value."
    done
}

add_local_hosts_mapping() {
    local name=$1 hosts_file=/etc/hosts
    is_ip_address "$name" && return
    grep -Eq "^[[:space:]]*127\.0\.0\.1[[:space:]].*\b${name//./\\.}\b" "$hosts_file" && return
    printf '\n127.0.0.1\t%s\t# OSCAR setup\n' "$name" >>"$hosts_file"
}

base_configured() {
    local required
    for required in secrets/oscar-admin-password.txt secrets/oscar-db-password.txt secrets/postgres-bootstrap-password.txt tls/server.crt tls/server.key .env; do
        [[ -s $script_dir/$required ]] || return 1
    done
}

configured() {
    base_configured || return 1
    case $(get_env_value OSCAR_BACKUP_MODE) in
        disabled) return 0 ;;
        single) [[ -s $script_dir/secrets/backup-key.txt ]] ;;
        *) return 1 ;;
    esac
}

compose() {
    assert_deployment_paths_safe
    require_managed_environment_bindings
    (
        cd "$script_dir"
        env -u COMPOSE_FILE -u COMPOSE_PROJECT_NAME -u COMPOSE_ENV_FILES -u COMPOSE_PROFILES \
            -u OSCAR_VERSION -u OSCAR_DEPLOYMENT_ID -u OSCAR_ARCHIVE_DIR -u OSCAR_BACKUP_DIR \
            -u OSCAR_BACKUP_MODE -u OSCAR_WAL_ARCHIVE_DIR -u OSCAR_SECRETS_DIR -u OSCAR_TLS_DIR -u OSCAR_BACKUP_KEY_FILE \
            -u OSCAR_HTTPS_PORT -u OSCAR_TIMEZONE -u OSCAR_JAVA_OPTS -u OSCAR_POSTGIS_PLATFORM \
            docker compose --project-name oscar --env-file "$script_dir/.env" --file "$script_dir/compose.yaml" "$@"
    )
}

stop_application_tier_ordered() {
    # Compose does not apply depends_on in reverse for `stop`/`restart` and a
    # multi-service stop signals every container concurrently. Keep the
    # database available while OSCAR drains its writers and completes its
    # module shutdown. The service stop_grace_period values in compose.yaml
    # remain the authoritative per-service deadlines.
    compose stop gateway
    compose stop oscar
}

stop_deployment_ordered() {
    stop_application_tier_ordered
    compose stop postgres
}

psql_bootstrap() {
    compose exec -T postgres sh -eu -c '
        PGPASSWORD=$(cat /run/secrets/postgres_bootstrap_password)
        export PGPASSWORD
        exec psql --set=ON_ERROR_STOP=1 --username oscar_bootstrap --dbname gis "$@"
    ' psql-wrapper "$@"
}

ensure_storage_database_features() {
    psql_bootstrap --command 'CREATE EXTENSION IF NOT EXISTS pg_stat_statements;' >/dev/null
    local checksums
    checksums=$(psql_bootstrap --tuples-only --no-align --command 'SHOW data_checksums;' | tr -d '[:space:]')
    if [[ $checksums != on ]]; then
        printf 'WARNING: PostgreSQL data checksums are disabled. OSCAR %s enables them on fresh databases; rebuild this test/production database before relying on checksum protection.\n' "$(release_version)" >&2
    fi
}

finalize_pending_fresh_init() {
    local receipt="$script_dir/.oscar-init-state" deployment_id receipt_id receipt_state checksums expected_version image_label postgres_image postgres_label postgres_profile volume label attempt profile_ready=false
    [[ -e $receipt ]] || return 0
    validate_init_receipt
    deployment_id=$(ensure_deployment_id)
    receipt_id=$(read_init_receipt_value deployment_id)
    receipt_state=$(read_init_receipt_value state)
    [[ $receipt_id == "$deployment_id" ]] || fail 'The OSCAR initialization receipt does not match .env.'
    [[ $receipt_state == INITIALIZING ]] || return 0

    for volume in oscar_oscar_state oscar_postgres_data; do
        docker volume inspect "$volume" >/dev/null 2>&1 || fail "Fresh initialization did not create required Docker volume: $volume"
        label=$(volume_deployment_label "$volume")
        [[ $label == "$deployment_id" ]] || fail "Docker volume $volume does not belong to this OSCAR initialization."
    done

    expected_version=$(release_version)
    checksums=$(psql_bootstrap --tuples-only --no-align --command 'SHOW data_checksums;' | tr -d '[:space:]')
    [[ $checksums == on ]] || fail "Fresh OSCAR $expected_version initialization requires PostgreSQL data checksums."
    compose exec -T postgres sh -eu -c '
        expected_version=$1
        marker=/var/lib/postgresql/data/.oscar-data-checksum-init
        test -f "$marker" && test ! -L "$marker"
        test "$(wc -l <"$marker" | tr -d "[:space:]")" = 4
        test "$(grep -Fxc format=oscar-storage-profile "$marker")" = 1
        test "$(grep -Fxc "version=$expected_version" "$marker")" = 1
        test "$(grep -Fxc data_checksums=on "$marker")" = 1
        test "$(grep -Ec "^initialized_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$" "$marker")" = 1
    ' profile-check "$expected_version" || fail "The PostgreSQL volume is not marked as a complete OSCAR $expected_version storage profile."
    # The HTTP health endpoint can become ready while SensorHub is completing
    # its first durable configuration save. Treat that short interval as
    # startup, while retaining a strict bounded failure for the wrong profile.
    for attempt in {1..30}; do
        if compose exec -T oscar sh -eu -c '
            config=/var/lib/oscar/config.json
            test -f "$config" && test ! -L "$config"
            grep -Fq "\"objClass\": \"com.botts.impl.service.dailyfile.DailyFileJournalServiceConfig\"" "$config"
            grep -Fq "\"objClass\": \"org.sensorhub.impl.datastore.postgis.database.OscarTieredObsSystemDatabaseConfig\"" "$config"
            grep -Fq "\"frameRetentionCount\": 5" "$config"
        ' >/dev/null 2>&1; then
            profile_ready=true
            break
        fi
        ((attempt < 30)) && sleep 1
    done
    $profile_ready || fail "The saved OSCAR configuration does not contain the complete $expected_version storage profile after 30 seconds."
    image_label=$(docker image inspect "$(oscar_image)" --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' 2>/dev/null || true)
    [[ $image_label == "$expected_version" ]] || fail "The selected OSCAR image is not labeled $expected_version (received: ${image_label:-missing})."
    postgres_image=$(compose config --images | awk '/(^|\/)oscar-postgis:/ { print; exit }')
    [[ -n $postgres_image ]] || fail 'The Compose model does not identify the OSCAR PostGIS image.'
    postgres_label=$(docker image inspect "$postgres_image" --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' 2>/dev/null || true)
    postgres_profile=$(docker image inspect "$postgres_image" --format '{{ index .Config.Labels "com.botts.oscar.storage-profile" }}' 2>/dev/null || true)
    [[ $postgres_label == "$expected_version" && $postgres_profile == "$expected_version" ]] ||
        fail "The selected PostGIS image does not carry the OSCAR $expected_version storage-profile labels."
    write_init_receipt "$deployment_id" COMPLETE
}

export_host_support_bundle() {
    local effective_tail=$log_tail ts_compact generated_at target_zip target_parent stage_dir raw_dir helper_image container_ids cid cname
    $log_tail_explicit || effective_tail=2500
    [[ $effective_tail =~ ^[0-9]+$ ]] && ((effective_tail >= 1 && effective_tail <= 10000)) ||
        fail '--tail must be between 1 and 10000.'
    command -v python3 >/dev/null 2>&1 || fail 'python3 is required to package and redact the host support bundle.'

    ts_compact=$(date -u +%Y%m%dT%H%M%SZ)
    generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [[ -z $support_output_path ]]; then
        local default_dir
        default_dir=$(dirname "$script_dir")
        if [[ -z $default_dir || $default_dir == / || ! -w $default_dir ]]; then
            default_dir=${TMPDIR:-/tmp}
        fi
        target_zip="${default_dir%/}/oscar-host-support-${ts_compact}.zip"
    elif [[ -d $support_output_path ]]; then
        target_zip="${support_output_path%/}/oscar-host-support-${ts_compact}.zip"
    else
        target_zip=$support_output_path
    fi
    target_parent=$(dirname "$target_zip")
    mkdir -p "$target_parent"
    target_parent=$(CDPATH= cd -- "$target_parent" && pwd -P)
    target_zip="$target_parent/$(basename "$target_zip")"
    if [[ -f $script_dir/SHA256SUMS && ( $target_zip == "$script_dir"/* || $target_zip == "$script_dir" ) ]]; then
        fail 'Choose an --output path outside the offline bundle directory so SHA256SUMS verification remains intact.'
    fi
    [[ ! -L $target_zip ]] || fail "Support bundle output path must not be a symlink: $target_zip"

    stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/oscar-support-bundle.XXXXXX")
    raw_dir="$stage_dir/raw"
    mkdir -p "$raw_dir/host" "$raw_dir/docker" "$raw_dir/logs" "$raw_dir/volume/module-logs" "$raw_dir/tls" "$raw_dir/archive"
    cleanup_support_stage() { [[ -z ${stage_dir:-} ]] || rm -rf -- "$stage_dir"; }
    trap cleanup_support_stage EXIT HUP INT TERM

    heading 'Collecting OSCAR host support bundle'

    {
        printf 'Generated (UTC): %s\n' "$generated_at"
        printf 'Release directory: %s\n' "$script_dir"
        printf 'Release version (.env.example): %s\n' "$(release_version 2>/dev/null || echo unknown)"
        printf 'Effective user: id=%s sudo_user=%s\n' "$(id -u)" "${SUDO_USER:-none}"
        printf '\n--- uname -a ---\n'
        uname -a 2>&1 || true
        if [[ -r /etc/os-release ]]; then
            printf '\n--- /etc/os-release ---\n'
            cat /etc/os-release 2>&1 || true
        fi
        printf '\n--- uptime ---\n'
        uptime 2>&1 || true
        if command -v free >/dev/null 2>&1; then
            printf '\n--- free -h ---\n'
            free -h 2>&1 || true
        fi
        printf '\n--- df -h ---\n'
        df -h 2>&1 || true
        if command -v docker >/dev/null 2>&1; then
            printf '\n--- docker version ---\n'
            docker version 2>&1 || true
            printf '\n--- docker compose version ---\n'
            docker compose version 2>&1 || true
        else
            printf '\nDocker CLI: not installed\n'
        fi
    } >"$raw_dir/host/system-info.txt"

    if [[ -r $script_dir/.env && ! -L $script_dir/.env ]]; then
        cp "$script_dir/.env" "$raw_dir/host/env.raw" 2>/dev/null || true
    fi
    if [[ -r $script_dir/.oscar-init-state && ! -L $script_dir/.oscar-init-state ]]; then
        cp "$script_dir/.oscar-init-state" "$raw_dir/host/init-state.txt" 2>/dev/null || true
    fi

    if [[ -r $script_dir/tls/server.crt && ! -L $script_dir/tls/server.crt ]]; then
        if command -v openssl >/dev/null 2>&1; then
            openssl x509 -in "$script_dir/tls/server.crt" -noout -subject -issuer -dates -fingerprint -sha256 -ext subjectAltName \
                >"$raw_dir/tls/certificate-info.txt" 2>&1 || true
        elif docker_ready && container_image_exists "$(oscar_image)"; then
            docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
                --workdir / --user 0:0 --entrypoint openssl --volume "$script_dir/tls:/tls:ro" "$(oscar_image)" \
                x509 -in /tls/server.crt -noout -subject -issuer -dates -fingerprint -sha256 -ext subjectAltName \
                >"$raw_dir/tls/certificate-info.txt" 2>&1 || true
        fi
    fi

    if docker_ready; then
        docker ps -a --no-trunc --filter label=com.docker.compose.project=oscar \
            >"$raw_dir/docker/compose-ps.txt" 2>&1 || true
        docker volume ls --filter name=oscar \
            >"$raw_dir/docker/volumes.txt" 2>&1 || true

        container_ids=$(docker ps -aq --filter label=com.docker.compose.project=oscar 2>/dev/null || true)
        if [[ -n $container_ids ]]; then
            # shellcheck disable=SC2086
            docker inspect $container_ids >"$raw_dir/docker/inspect.raw.json" 2>/dev/null || true
            for cid in $container_ids; do
                cname=$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | sed 's|^/||; s|[^A-Za-z0-9._-]|_|g')
                [[ -n $cname ]] || cname=$cid
                docker logs --timestamps --tail "$effective_tail" "$cid" \
                    >"$raw_dir/logs/${cname}.log" 2>&1 || true
            done
        fi

        if docker volume inspect oscar_oscar_state >/dev/null 2>&1; then
            helper_image=$(oscar_image)
            if ! container_image_exists "$helper_image"; then
                helper_image=$(docker images --format '{{.Repository}}:{{.Tag}}' | awk '/^oscar:/ { print; exit }')
            fi
            if [[ -n $helper_image ]] && container_image_exists "$helper_image"; then
                docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
                    --workdir / --user 10001:10001 --entrypoint sh \
                    --volume oscar_oscar_state:/state:ro \
                    "$helper_image" -eu -c '
                        tail_count=$1
                        if [ -f /state/config.json ] && [ ! -L /state/config.json ]; then
                            printf "FILE:config.raw.json:"
                            head -c 4194304 /state/config.json | base64 | tr -d "\r\n"
                            printf "\n"
                        fi
                        if [ -f /state/logs/oscar.log ] && [ ! -L /state/logs/oscar.log ]; then
                            printf "FILE:oscar.log:"
                            tail -n "$tail_count" /state/logs/oscar.log | base64 | tr -d "\r\n"
                            printf "\n"
                        fi
                        if [ -d /state/.moduledata ]; then
                            count=0
                            for mod_log in /state/.moduledata/*/log.txt; do
                                [ -f "$mod_log" ] && [ ! -L "$mod_log" ] || continue
                                mod_name=$(basename "$(dirname "$mod_log")" | tr -c "A-Za-z0-9._-" "_")
                                printf "FILE:module-logs/%s.log:" "$mod_name"
                                tail -n 200 "$mod_log" | base64 | tr -d "\r\n"
                                printf "\n"
                                count=$((count + 1))
                                [ "$count" -lt 10 ] || break
                            done
                        fi
                    ' support-volume-extract "$effective_tail" >"$raw_dir/volume/extracted.b64" 2>/dev/null || true
            fi
        fi

        if [[ ${EUID:-$(id -u)} -eq 0 ]] && configured; then
            bash "$script_dir/oscar-storage.sh" archive status >"$raw_dir/archive/status.txt" 2>&1 || true
        fi
    fi

    python3 - "$raw_dir" "$target_zip" "$generated_at" "$(release_version 2>/dev/null || echo unknown)" "$effective_tail" <<'PY'
import base64
import json
import os
import re
import sys
import zipfile
from pathlib import Path

raw_dir = Path(sys.argv[1])
target_zip = Path(sys.argv[2])
generated_at = sys.argv[3]
release_ver = sys.argv[4]
tail_lines = int(sys.argv[5])

REDACTED = "[REDACTED]"
REDACTED_SECRET_FILE = "[REDACTED_SECRET_FILE]"
REDACTED_PRIVATE_KEY = "[REDACTED_PRIVATE_KEY]"
MAX_ZIP_BYTES = 25 * 1024 * 1024

SAFE_KEYS = {"cookiename", "keyalias", "idprovidertype", "authmethod", "securecookie"}
SECRET_FILE_KEYS = {"passwordfile", "secretfile", "privatekeyfile", "keystorepath", "truststorepath"}
SENSITIVE_EXACT = {
    "password", "passwd", "pwd", "secret", "token", "accesstoken", "access_token",
    "refreshtoken", "refresh_token", "idtoken", "id_token", "apikey", "api_key",
    "authorization", "cookie", "cookies", "set-cookie", "sessioncookie", "oscar_session",
    "jsessionid", "privatekey", "private_key", "passphrase", "credentials",
    "clientsecret", "client_secret", "keystorepassword", "truststorepassword", "hmac",
}

PEM_RE = re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----")
URI_RE = re.compile(r"((?:jdbc:)?[a-zA-Z][a-zA-Z0-9+.-]*://)([^/@\s\"'<>]+)@")
AUTH_HDR_RE = re.compile(r"(?i)(\bAuthorization\s*[:=]\s*(?:Basic|Bearer|Digest|Token)\s+)([^\s,;\"']+)")
AUTH_SCHEME_RE = re.compile(r"(?i)\b(Bearer|Basic)\s+([A-Za-z0-9._~+/=-]{12,})")
COOKIE_HDR_RE = re.compile(r"(?i)(\b(?:Cookie|Set-Cookie)\s*:\s*)([A-Za-z0-9._-]+)=([^;\s\"',]+)((?:\s*;\s*[A-Za-z0-9._-]+=[^;\s\"',]+)*)")
COOKIE_PAIR_RE = re.compile(r"([A-Za-z0-9._-]+)=([^;\s\"',]+)")
SESSION_RE = re.compile(r"(?i)\b(OSCAR_SESSION|JSESSIONID)\s*=\s*([^;\s\"',]+)")
QUERY_RE = re.compile(r"(?i)([?&](?:password|passwd|pwd|token|access_token|refresh_token|api_key|apikey|secret|auth|session|sig|signature)=)([^&\s\"'#]+)")
KV_RE = re.compile(r"(?i)(\"?\b(?:password|passwd|pwd|secret|api[_-]?key|(?:(?:access|refresh|id|auth|session|csrf|api)[_-]?)?token|private[_-]?key|passphrase|db_password|admin_password)\b\"?\s*[:=]\s*)(\"[^\"]*\"|'[^']*'|[^\s,;}\]\"]+)")
EMAIL_RE = re.compile(r"\b([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*@([A-Za-z0-9.-]+\.[A-Za-z]{2,})\b")

stats = {
    "jsonFieldsRedacted": 0,
    "uriCredentialsRedacted": 0,
    "authHeadersRedacted": 0,
    "cookiesRedacted": 0,
    "querySecretsRedacted": 0,
    "keyValueSecretsRedacted": 0,
    "pemBlocksRedacted": 0,
    "emailsMasked": 0,
    "containerEnvStripped": 0,
}

def is_sensitive_key(k: str) -> bool:
    low = k.strip().lower()
    if low in SAFE_KEYS:
        return False
    if low in SENSITIVE_EXACT:
        return True
    return low.endswith(("password", "passwd", "secret", "token", "apikey", "api_key", "privatekey", "private_key", "passphrase"))

def redact_text(text: str) -> str:
    if not text:
        return ""
    out, n = PEM_RE.subn(REDACTED_PRIVATE_KEY, text)
    stats["pemBlocksRedacted"] += n
    out, n = URI_RE.subn(lambda m: f"{m.group(1)}{REDACTED}@", out)
    stats["uriCredentialsRedacted"] += n
    out, n = AUTH_HDR_RE.subn(lambda m: f"{m.group(1)}{REDACTED}", out)
    stats["authHeadersRedacted"] += n
    out, n = AUTH_SCHEME_RE.subn(lambda m: f"{m.group(1)} {REDACTED}", out)
    stats["authHeadersRedacted"] += n
    def _cookie_hdr(m):
        tail = COOKIE_PAIR_RE.sub(rf"\1={REDACTED}", m.group(4) or "")
        return f"{m.group(1)}{m.group(2)}={REDACTED}{tail}"
    out, n = COOKIE_HDR_RE.subn(_cookie_hdr, out)
    stats["cookiesRedacted"] += n
    out, n = SESSION_RE.subn(lambda m: f"{m.group(1)}={REDACTED}", out)
    stats["cookiesRedacted"] += n
    out, n = QUERY_RE.subn(lambda m: f"{m.group(1)}{REDACTED}", out)
    stats["querySecretsRedacted"] += n
    def _kv(m):
        val = m.group(2)
        if not val or val in ('""', "''") or REDACTED in val:
            return m.group(0)
        stats["keyValueSecretsRedacted"] += 1
        if len(val) >= 2 and val[0] == val[-1] and val[0] in ('"', "'"):
            return f"{m.group(1)}{val[0]}{REDACTED}{val[0]}"
        return f"{m.group(1)}{REDACTED}"
    out = KV_RE.sub(_kv, out)
    out, n = EMAIL_RE.subn(lambda m: f"{m.group(1)}***@{m.group(2)}", out)
    stats["emailsMasked"] += n
    return out

def redact_json(node):
    if isinstance(node, list):
        return [redact_json(x) for x in node]
    if isinstance(node, dict):
        res = {}
        for k, v in node.items():
            low = k.strip().lower()
            if low in SECRET_FILE_KEYS:
                if isinstance(v, str) and v.strip():
                    stats["jsonFieldsRedacted"] += 1
                    res[k] = REDACTED_SECRET_FILE
                else:
                    res[k] = v
            elif is_sensitive_key(k):
                if v in (None, ""):
                    res[k] = v
                else:
                    stats["jsonFieldsRedacted"] += 1
                    res[k] = REDACTED
            else:
                res[k] = redact_json(v)
        return res
    if isinstance(node, str):
        return redact_text(node)
    return node

entries: dict[str, bytes] = {}
error_lines = 0
warn_lines = 0
highlights: list[str] = []

def add_text_entry(zip_path: str, text: str, scan_highlights: bool = False):
    global error_lines, warn_lines
    sanitized = redact_text(text)
    if scan_highlights:
        for line in sanitized.splitlines():
            if " ERROR " in line or line.startswith("ERROR") or "Exception:" in line or "FATAL" in line:
                error_lines += 1
                highlights.append(f"[{zip_path}] {line[:360]}")
                if len(highlights) > 30:
                    highlights.pop(0)
            elif " WARN " in line or line.startswith("WARN"):
                warn_lines += 1
                highlights.append(f"[{zip_path}] {line[:360]}")
                if len(highlights) > 30:
                    highlights.pop(0)
    entries[zip_path] = (sanitized.rstrip("\n") + "\n").encode("utf-8")

sys_info = raw_dir / "host" / "system-info.txt"
if sys_info.is_file():
    add_text_entry("host/system-info.txt", sys_info.read_text(encoding="utf-8", errors="replace"))

env_raw = raw_dir / "host" / "env.raw"
configured_ver = None
if env_raw.is_file():
    env_lines = []
    for raw_line in env_raw.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#") or "=" not in raw_line:
            env_lines.append(redact_text(raw_line))
            continue
        k, v = raw_line.split("=", 1)
        if k.strip() == "OSCAR_VERSION" and v.strip():
            configured_ver = v.strip()
        if is_sensitive_key(k) or "SECRET" in k.upper() or "KEY" in k.upper() and "BACKUP_MODE" not in k.upper():
            if v.strip():
                stats["keyValueSecretsRedacted"] += 1
                env_lines.append(f"{k}={REDACTED}")
            else:
                env_lines.append(f"{k}=")
        else:
            env_lines.append(f"{k}={redact_text(v)}")
    entries["host/env.redacted.txt"] = ("\n".join(env_lines) + "\n").encode("utf-8")

init_state = raw_dir / "host" / "init-state.txt"
if init_state.is_file():
    add_text_entry("host/init-state.txt", init_state.read_text(encoding="utf-8", errors="replace"))

cert_info = raw_dir / "tls" / "certificate-info.txt"
if cert_info.is_file():
    add_text_entry("tls/certificate-info.txt", cert_info.read_text(encoding="utf-8", errors="replace"))

for dfile in ("compose-ps.txt", "volumes.txt"):
    p = raw_dir / "docker" / dfile
    if p.is_file():
        add_text_entry(f"docker/{dfile}", p.read_text(encoding="utf-8", errors="replace"))

container_summaries = []
inspect_raw = raw_dir / "docker" / "inspect.raw.json"
if inspect_raw.is_file():
    try:
        parsed_inspect = json.loads(inspect_raw.read_text(encoding="utf-8", errors="replace"))
        sanitized_inspect = []
        for item in parsed_inspect if isinstance(parsed_inspect, list) else []:
            if not isinstance(item, dict):
                continue
            cfg = item.get("Config") or {}
            if "Env" in cfg and cfg["Env"]:
                stats["containerEnvStripped"] += len(cfg["Env"])
            state = item.get("State") or {}
            summary_obj = {
                "name": (item.get("Name") or "").lstrip("/"),
                "image": cfg.get("Image"),
                "created": item.get("Created"),
                "status": state.get("Status"),
                "running": state.get("Running"),
                "restarting": state.get("Restarting"),
                "oomKilled": state.get("OOMKilled"),
                "exitCode": state.get("ExitCode"),
                "error": redact_text(str(state.get("Error") or "")),
                "startedAt": state.get("StartedAt"),
                "finishedAt": state.get("FinishedAt"),
                "restartCount": item.get("RestartCount"),
                "health": redact_json(state.get("Health")) if state.get("Health") else None,
                "mounts": [
                    {
                        "type": m.get("Type"),
                        "name": m.get("Name"),
                        "destination": m.get("Destination"),
                        "rw": m.get("RW"),
                    }
                    for m in (item.get("Mounts") or [])
                    if isinstance(m, dict) and not str(m.get("Destination") or "").startswith("/run/secrets")
                ],
            }
            container_summaries.append(summary_obj)
            sanitized_inspect.append(summary_obj)
        entries["docker/inspect.redacted.json"] = (json.dumps(sanitized_inspect, indent=2) + "\n").encode("utf-8")
    except Exception as exc:
        add_text_entry("docker/inspect.error.txt", str(exc))

logs_dir = raw_dir / "logs"
if logs_dir.is_dir():
    for lf in sorted(logs_dir.glob("*.log")):
        add_text_entry(f"logs/{lf.name}", lf.read_text(encoding="utf-8", errors="replace"), scan_highlights=True)

vol_root = (raw_dir / "volume").resolve()
extracted_b64 = vol_root / "extracted.b64"
if extracted_b64.is_file():
    for raw_b64_line in extracted_b64.read_text(encoding="ascii", errors="ignore").splitlines():
        if not raw_b64_line.startswith("FILE:"):
            continue
        parts = raw_b64_line.split(":", 2)
        if len(parts) != 3:
            continue
        rel_name, b64_payload = parts[1], parts[2]
        dest = (vol_root / rel_name).resolve()
        if vol_root not in dest.parents and dest != vol_root:
            continue
        try:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(base64.b64decode(b64_payload))
        except Exception:
            pass

vol_cfg = raw_dir / "volume" / "config.raw.json"
if vol_cfg.is_file():
    try:
        cfg_parsed = json.loads(vol_cfg.read_text(encoding="utf-8", errors="replace"))
        entries["volume/config.redacted.json"] = (json.dumps(redact_json(cfg_parsed), indent=2) + "\n").encode("utf-8")
    except Exception as exc:
        add_text_entry("volume/config.error.txt", str(exc))

vol_log = raw_dir / "volume" / "oscar.log"
if vol_log.is_file():
    add_text_entry("volume/oscar.log", vol_log.read_text(encoding="utf-8", errors="replace"), scan_highlights=True)

mod_logs_dir = raw_dir / "volume" / "module-logs"
if mod_logs_dir.is_dir():
    for mf in sorted(mod_logs_dir.glob("*.log")):
        add_text_entry(f"volume/module-logs/{mf.name}", mf.read_text(encoding="utf-8", errors="replace"), scan_highlights=True)

arch_status = raw_dir / "archive" / "status.txt"
if arch_status.is_file() and arch_status.stat().st_size > 0:
    add_text_entry("archive/status.txt", arch_status.read_text(encoding="utf-8", errors="replace"))

total_redactions = sum(stats.values())
redaction_report = {
    "schemaVersion": 1,
    "generatedAt": generated_at,
    "policy": "automatic-edge-redaction",
    "bundleSource": "host-cli",
    "neverCollected": ["secrets/*", "/run/secrets/*", "tls/*.key", ".keystore/*", "hivemq-data/*"],
    "counts": {**stats, "totalRedactions": total_redactions},
}
summary = {
    "schemaVersion": 1,
    "bundleType": "oscar-support-bundle",
    "bundleSource": "host-cli",
    "platform": "linux",
    "generatedAt": generated_at,
    "releaseVersion": release_ver,
    "configuredVersion": configured_ver or release_ver,
    "tailLinesRequested": tail_lines,
    "containers": container_summaries,
    "logs": {
        "errorLineCount": error_lines,
        "warnLineCount": warn_lines,
        "recentHighlights": highlights,
    },
    "redaction": {
        "applied": True,
        "totalRedactions": total_redactions,
    },
}

tmp_zip = target_zip.with_name(target_zip.name + ".tmp")
with zipfile.ZipFile(tmp_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
    zf.writestr("summary.json", json.dumps(summary, indent=2) + "\n")
    zf.writestr("redaction-report.json", json.dumps(redaction_report, indent=2) + "\n")
    for name, payload in entries.items():
        if tmp_zip.stat().st_size + len(payload) // 2 > MAX_ZIP_BYTES - 65536:
            break
        zf.writestr(name, payload)

os.chmod(tmp_zip, 0o600)
os.replace(tmp_zip, target_zip)
PY

    chmod 0600 "$target_zip"
    if [[ ${EUID:-$(id -u)} -eq 0 && -n ${SUDO_UID:-} && -n ${SUDO_GID:-} && ${SUDO_UID} != 0 ]]; then
        chown "${SUDO_UID}:${SUDO_GID}" "$target_zip" 2>/dev/null || true
    fi
    cleanup_support_stage
    trap - EXIT HUP INT TERM
    printf 'Support bundle written to: %s\n' "$target_zip"
}

case "$command_name" in
    help) usage ;;
    check)
        heading 'Prerequisite check'
        printf 'Administrator: %s\n' "$([[ ${EUID:-$(id -u)} -eq 0 ]] && echo true || echo false)"
        printf 'Docker CLI: %s\n' "$(command -v docker >/dev/null 2>&1 && echo true || echo false)"
        printf 'Docker ready: %s\n' "$(docker_ready && echo true || echo false)"
        printf 'Offline bundle: %s\n' "$([[ -f $script_dir/offline-images.tar ]] && echo true || echo false)"
        printf 'Bundle verification: %s\n' "$(offline_verification_status)"
        printf 'Configured: %s\n' "$(configured && echo true || echo false)"
        # TODO(offline-maps): add MBTiles validation/import after deployment requirements are defined.
        ;;
    verify)
        require_admin
        assert_deployment_paths_safe
        [[ -f $script_dir/SHA256SUMS ]] || fail 'SHA256SUMS is missing. This is not a complete offline bundle.'
        assert_offline_bundle_integrity true
        ;;
    init)
        require_admin
        require_supported_storage_host
        assert_deployment_paths_safe
        assert_offline_bundle_integrity
        require_docker
        if [[ -z $hostname_value ]]; then
            if $non_interactive; then fail '--hostname is required in non-interactive mode.'; fi
            read -r -p 'Hostname or IP address [oscar.local]: ' hostname_value
            hostname_value=${hostname_value:-oscar.local}
        fi
        if [[ -z $timezone_value ]]; then
            timezone_default=UTC
            if [[ -f $script_dir/.env ]]; then
                timezone_default=$(awk -F= '$1 == "OSCAR_TIMEZONE" { print substr($0, index($0, "=") + 1); exit }' "$script_dir/.env")
                timezone_default=${timezone_default:-UTC}
            fi
            if ! $non_interactive; then
                read -r -p "Local IANA timezone (e.g. America/Chicago) [$timezone_default]: " timezone_value
            fi
            timezone_value=${timezone_value:-$timezone_default}
        fi
        [[ $timezone_value =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]] || fail 'Use an IANA timezone such as America/Chicago or UTC.'
        valid_hostname "$hostname_value" || fail "Invalid hostname or IP address: $hostname_value"
        resolve_tls_sans "$hostname_value"
        [[ $port_value =~ ^[0-9]+$ ]] && ((port_value >= 1 && port_value <= 65535)) || fail 'Port must be between 1 and 65535.'
        ((port_value != 80)) || fail 'Port 80 is reserved for the HTTP-to-HTTPS redirect.'
        target_backup_mode=${backup_mode_value:-disabled}
        if [[ $target_backup_mode == disabled && -n $backup_directory_value ]]; then
            fail '--backup-dir is valid only when --backup-mode single is selected.'
        fi
        if [[ $target_backup_mode == single && -z $backup_directory_value ]]; then
            fail 'Fresh single-backup mode requires --backup-dir with a safe absolute path that does not overlap the release or archive roots.'
        fi
        mkdir -p "$script_dir/secrets" "$script_dir/tls"
        allow_docker_desktop_bind_mount_access
        set_env_value OSCAR_VERSION "$(release_version)"
        set_env_value OSCAR_HTTPS_PORT "$port_value"
        set_env_value OSCAR_HOSTNAME "$hostname_value"
        [[ -z $backup_mode_value ]] || set_env_value OSCAR_BACKUP_MODE "$backup_mode_value"
        [[ -z $backup_directory_value ]] || set_env_value OSCAR_BACKUP_DIR "$backup_directory_value"
        require_canonical_credential_bindings
        configure_storage_paths
        preflight_fresh_init >/dev/null
        ensure_fresh_init_volumes
        require_managed_environment_bindings
        [[ -e $script_dir/secrets/oscar-admin-password.txt ]] || write_secret "$script_dir/secrets/oscar-admin-password.txt" "$(read_admin_password)"
        [[ -e $script_dir/secrets/oscar-db-password.txt ]] || write_secret "$script_dir/secrets/oscar-db-password.txt" "$(random_password)"
        [[ -e $script_dir/secrets/postgres-bootstrap-password.txt ]] || write_secret "$script_dir/secrets/postgres-bootstrap-password.txt" "$(random_password)"
        if [[ $(configured_backup_mode) == single ]]; then
            [[ -e $script_dir/secrets/backup-key.txt ]] || write_secret "$script_dir/secrets/backup-key.txt" "$(random_password)$(random_password)"
        fi
        prepare_deployment_images
        docker run --rm --entrypoint test "$(oscar_image)" -f "/usr/share/zoneinfo/$timezone_value" \
            || fail "Unknown IANA timezone: $timezone_value"
        set_env_value OSCAR_TIMEZONE "$timezone_value"
        bash "$script_dir/oscar-storage.sh" prepare-directories
        initialize_tls "$hostname_value"
        protect_deployment_files
        $add_hosts && add_local_hosts_mapping "$hostname_value"
        configured || fail 'Setup did not produce every required deployment file.'
        if ! $skip_start; then
            compose up --detach --no-build --pull never --wait --wait-timeout 240
            ensure_storage_database_features
            finalize_pending_fresh_init
        fi
        printf '\nOSCAR setup complete: https://%s:%s/sensorhub/admin\n' "$hostname_value" "$port_value"
        print_client_access_instructions
        ;;
    start)
        require_admin; require_supported_storage_host; require_docker; configured || fail 'Run init before starting OSCAR.'
        assert_deployment_volume_ownership false
        assert_deployment_images_available
        compose up --detach --no-build --pull never --wait --wait-timeout 240
        ensure_storage_database_features
        finalize_pending_fresh_init
        ;;
    stop)
        require_admin; require_docker; configured || fail 'Run init before stopping OSCAR.'
        stop_deployment_ordered
        printf 'OSCAR stopped. Persistent application and database data were retained.\n'
        ;;
    restart)
        require_admin; require_supported_storage_host; require_docker; configured || fail 'Run init before restarting OSCAR.'
        assert_deployment_volume_ownership false
        assert_deployment_images_available
        stop_deployment_ordered
        compose up --detach --no-build --pull never --wait --wait-timeout 240
        ensure_storage_database_features
        finalize_pending_fresh_init
        ;;
    status)
        require_docker; compose ps
        if configured; then
            local_hostname=$(awk -F= '$1 == "OSCAR_HOSTNAME" { print substr($0, index($0, "=") + 1); exit }' "$script_dir/.env")
            local_port=$(awk -F= '$1 == "OSCAR_HTTPS_PORT" { print substr($0, index($0, "=") + 1); exit }' "$script_dir/.env")
            printf 'OSCAR URL: https://%s:%s/sensorhub/admin\n' "${local_hostname:-oscar.local}" "${local_port:-443}"
        fi
        ;;
    logs)
        require_docker; configured || fail 'Run init before reading OSCAR logs.'
        [[ $log_service =~ ^(all|oscar|postgres|gateway)$ ]] || fail '--service must be all, oscar, postgres, or gateway.'
        [[ $log_tail =~ ^[0-9]+$ ]] && ((log_tail >= 1 && log_tail <= 10000)) || fail '--tail must be between 1 and 10000.'
        log_args=(logs --tail "$log_tail")
        $log_follow && log_args+=(--follow)
        [[ $log_service == all ]] || log_args+=("$log_service")
        compose "${log_args[@]}"
        ;;
    support-bundle)
        export_host_support_bundle
        ;;
    upgrade)
        require_admin
        require_supported_storage_host
        assert_deployment_paths_safe
        assert_offline_bundle_integrity
        require_docker; base_configured || fail 'This release directory has not been initialized.'
        require_upgrade_environment_keys
        heading 'Upgrade preflight'
        normalize_backup_mode_for_upgrade
        normalize_legacy_backup_key_binding
        current_backup_mode=$(configured_backup_mode)
        target_backup_mode=${backup_mode_value:-$current_backup_mode}
        if [[ $target_backup_mode == disabled && -n $backup_directory_value ]]; then
            fail '--backup-dir is valid only when single-backup mode is enabled.'
        fi
        if [[ $current_backup_mode == disabled && $target_backup_mode == single && -z $backup_directory_value ]]; then
            fail 'Enabling single-backup mode requires --backup-dir with a safe absolute path that does not overlap the release or archive roots.'
        fi
        [[ -z $backup_mode_value ]] || set_env_value OSCAR_BACKUP_MODE "$backup_mode_value"
        [[ -z $backup_directory_value ]] || set_env_value OSCAR_BACKUP_DIR "$backup_directory_value"
        require_canonical_credential_bindings
        assert_deployment_volume_ownership "$adopt_legacy_volumes"
        configure_storage_paths
        require_unique_literal_environment_keys
        target_version=$(release_version)
        set_env_value OSCAR_VERSION "$target_version"
        require_managed_environment_bindings
        if [[ $(configured_backup_mode) == single ]]; then
            [[ -e $script_dir/secrets/backup-key.txt ]] || write_secret "$script_dir/secrets/backup-key.txt" "$(random_password)$(random_password)"
        fi
        protect_deployment_files
        printf 'Preparing OSCAR %s\n' "$target_version"
        prepare_deployment_images
        prepare_storage_args=(prepare-directories)
        $adopt_legacy_storage_roots && prepare_storage_args+=(--adopt-existing)
        bash "$script_dir/oscar-storage.sh" "${prepare_storage_args[@]}"
        # The storage command keeps its deployment-scoped lock across the
        # ordered stop, config-aware journal migration, and force-recreated
        # restart. Persistent named volumes are retained throughout.
        bash "$script_dir/oscar-storage.sh" upgrade-state
        ensure_storage_database_features
        finalize_pending_fresh_init
        printf 'Upgrade deployment completed. Persistent OSCAR and PostgreSQL volumes were retained.\n'
        ;;
    *) fail "Unknown command: $command_name" ;;
esac
