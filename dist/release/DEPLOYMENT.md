# OSCAR Administrator Guide

OSCAR runs as three Docker Compose services: an HTTPS gateway, the non-root OSCAR application, and PostgreSQL/PostGIS. The selected HTTPS port is published to the host, and port 80 redirects requests to HTTPS. PostgreSQL has no host port.

Start with [QUICKSTART.md](QUICKSTART.md) for installation, and see [VIDEO_GUIDES.md](../../docs/VIDEO_GUIDES.md) for concise 1080p captioned screen recordings covering initialization ([Module 01](https://github.com/ORNL/oscar-video-guides/blob/main/videos/01-deployment-init-and-credentials.mp4)), clean-directory upgrades ([Module 02](https://github.com/ORNL/oscar-video-guides/blob/main/videos/02-clean-directory-upgrade.mp4)), archive/backup verification ([Module 03](https://github.com/ORNL/oscar-video-guides/blob/main/videos/03-archive-and-snapshot-backup.mp4)), and SensorHub Admin configuration ([Modules 04–07](../../docs/VIDEO_GUIDES.md#04-admin-oscar-service-and-custom-codes)). This guide documents deployment choices and routine administration.

## Supported deployment and operation hosts

- Windows 11 x86-64 with Docker Desktop and WSL 2
- Ubuntu Server 24.04 x86-64 with Docker Engine and the Compose plugin

The 3.11.0 storage profile fails closed on macOS because Docker Desktop for Mac cannot satisfy this
release's tested bind-root ownership and recovery-media isolation contract. Use Ubuntu or Windows
for initialization and operation; a Mac may still be used for source inspection or non-deployment
development.

### Recommended hardware and capacity sizing

OSCAR resource consumption divides into **baseline steady-state ingest** and **simultaneous occupancy bursts**:

- **Steady-state RPM & H.264 camera ingest (network + sequential disk I/O bound):** Each RPM streams `5 Hz` radiation telemetry (`~10–30 Kbps` per lane), while RTSP cameras are ingested through the built-in loopback `mediamtx` proxy using **H.264 packet stream-copy (`-c copy`)** without CPU video re-encoding during monitoring or occupancy MP4 clip recording. Baseline camera load therefore scales primarily with **total camera bitrate and sequential NVMe write throughput**.
- **Simultaneous occupancy & operator review bursts (CPU + RAM bound):** CPU cores and memory headroom are consumed when multiple lanes enter occupancy concurrently (triggering asynchronous two-pass five-JPEG keyframe extraction in `VideoRetention`, `30`-minute `PARQUET_PRIMARY` ZSTD archive exports, active shared live HLS viewer streams, and optional per-lane `960px -> 1600px` ONNX PP-OCRv3 container/license-plate recognition).

#### Scenario hardware sizing matrix

| Deployment Scenario | RPM Count | H.264 Camera Count & Stream Profile | Recommended Host OS | CPU (Physical x86-64 Cores) | System RAM | Primary Storage (OS + Archive) | Sensor Network |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Small / Single-Gate** | `1–4` RPMs | `2–8` cameras (`720p` or `1080p` @ `15 fps`) | Ubuntu Server 24.04 LTS or Windows 11 + WSL 2 | `4+` cores (`8+` threads) | `16 GB` (`8–10 GB` WSL 2 cap on Windows) | `512 GB` NVMe SSD | `1 GbE` |
| **Medium Site** | `5–20` RPMs | `10–40` cameras (`720p` or `1080p` @ `15 fps`) | Ubuntu Server 24.04 LTS (preferred) or Windows 11 + WSL 2 | `8+` cores (`16+` threads) | `32 GB` (`16–20 GB` WSL 2 cap on Windows) | `1–2 TB` TLC / enterprise NVMe SSD | Dedicated `1 GbE` sensor VLAN |
| **Large / High-Density Portal** | `25–50` RPMs | `50–100` cameras (`720p` @ `15 fps` or `1080p` @ `15–30 fps`) | **Ubuntu Server 24.04 LTS bare-metal strongly recommended** *(see OS comparison below)* | `12–16+` physical P-cores | `32–64 GB` | `2–4 TB` high-endurance NVMe SSD (separate physical drive recommended if `OSCAR_BACKUP_MODE=single`) | `1–2.5 GbE`+ dedicated sensor NIC |
| **Add-On: Per-Lane Container / Plate OCR (`ocrConfig`)** | Per OCR-enabled portal | `1080p` @ `15–30 fps` (`1–2 s` closed GOP) on OCR-designated cameras | Ubuntu Server 24.04 LTS recommended when `> 8` lanes run OCR | `+4` physical cores above base tier | `+4 GB` RAM above base tier | Uses bounded `< 100 MiB` FIFO crop cache (`2,000` JPEGs max) | Unchanged |
| **Optional Central Federation Hub ([`ORNL/oscar-federation-hub`](https://github.com/ORNL/oscar-federation-hub))** | Multi-site Zero-Trust tunnel + SSO | Outbound HTTPS `443` from site `oscar-tunnel` connectors | Ubuntu 24.04 LTS VM (cloud or on-prem, public DNS + `443`) | `2+ vCPUs` | **`8 GB` RAM** for Mode A (`--with-authentik` browser SSO console; ~`2.8 GiB` active RSS); **`4 GB` RAM** for CLI-only Mode B | `40+ GB` SSD | Public IPv4 (`TCP 80/443`, `UDP 443`) |

#### Camera H.264 resolution, frame rate, and GOP recommendations

| Camera Stream Profile | Typical H.264 Bitrate (per Camera) | Aggregate Ingress (`50` Cameras / `100` Cameras) | Operational Guidance |
| --- | --- | --- | --- |
| **`1280×720` (`720p`) @ `15 fps`**, `1–2 s` closed GOP | `~1.0–2.0 Mbps` | `~50–100 Mbps` / `~100–200 Mbps` | **Recommended baseline for general situational-awareness cameras** at `25–50`-lane portals; minimizes NVMe write amplification and five-JPEG decode CPU while supporting up to `8` cameras per lane. |
| **`1920×1080` (`1080p`) @ `15 fps`**, `1–2 s` closed GOP | `~2.5–4.0 Mbps` | `~125–200 Mbps` / `~250–400 Mbps` | **Recommended sweet spot for Container & License Plate OCR cameras** and primary evidentiary angles; preserves sharp stenciled ISO 6346 check digits without doubling packet rate. Supports up to `8` cameras per lane. |
| **`1920×1080` (`1080p`) @ `30 fps`**, `1–2 s` closed GOP | `~4.0–8.0 Mbps` | `~200–400 Mbps` / `~400–800 Mbps` | Use only on high-speed free-flow lanes where `15 fps` introduces motion blur; roughly doubles RTSP packet rate, temporary MP4 clip size, and two-pass JPEG decode work. |
| **`3840×2160` (`4K`) @ `15–30 fps`** | `~12–25+ Mbps` | Not recommended above `8–16` total cameras | Supported (`writeQueueSize: 4096`), capped at `2` cameras per lane by the `120 MP` per-event gallery ceiling. On multi-lane sites, point OSCAR at a `720p` or `1080p` H.264 sub-stream instead of a `4K` main stream. |

Always configure **H.264 (`Main` or `High` profile, CBR or capped VBR)** with a **`1–2` second closed GOP** (`I-frame` interval of `15–30` frames at `15 fps`) and disable camera Dynamic FPS / Smart Codec GOP stretching (`10+ s` keyframe gaps delay live HLS startup and short-occupancy keyframe capture). When `ocrConfig` is enabled on undersized hardware, `OcrResourceGovernor` automatically sheds OCR inference above `85%` host CPU load or `< 15%` free JVM heap so radiation alarm capture and adjudication are never starved.

#### Native Ubuntu Server 24.04 LTS vs. Windows 11 + WSL 2 at scale

Under sustained **50-lane + 100-camera** `PARQUET_PRIMARY` operation, the `oscar` container holds steady at `~5.4–5.6 GiB` RSS and `postgres` at `~0.8–1.0 GiB` RSS (plus WSL 2 page cache and `Local9pParquetCache`'s bounded `2–8 GiB` native `ext4` Parquet cache on Windows). Both host platforms pass full functional and endurance validation, with an important architectural difference at high lane counts:

- **Ubuntu Server 24.04 LTS (native Linux Docker bridge + native `ext4` NVMe):** Delivers metronome-steady `200 ms` (`5 Hz`) RPM sample ingestion across all `50` lanes with zero TCP reader bunching (`load average ~3.5–4.8` on desktop/server multi-core CPUs) and sub-millisecond hot-tier queries. **Choose Ubuntu Server 24.04 bare-metal for `25–50+` lane portals, `50–100` camera deployments, or multi-lane OCR.**
- **Windows 11 + Docker Desktop / WSL 2:** Routes inbound sensor TCP streams through Docker Desktop's user-space network proxy and virtualized Hyper-V storage/network layers. At `50`-lane + `100`-camera concurrency on laptop/workstation hardware, brief (`0.4–1.0 s`) host I/O or proxy scheduling pauses can bunch `2–5` consecutive `5 Hz` RPM samples into micro-bursts on live detector plots without dropping samples or delaying alarms. **When enabling `100%` per-lane Container & License Plate OCR (`ocrConfig.enabled = true`) on Windows 11 + WSL 2, size the deployment to `1–8` lanes (for example, `6` lanes @ `100%` OCR, validated with zero `5 Hz` RPM sample bunching and `~1.9 GiB` container RSS)** and federate higher-density portals onto an Ubuntu Server 24.04 bare-metal HQ node (`25–50` lanes @ `100%` OCR). If Windows 11 is required above `20` non-OCR lanes, use a desktop/workstation CPU with `8–12+` physical performance cores, `32–64 GB` host RAM (`20–32 GB` assigned to `%USERPROFILE%\.wslconfig`), dedicated internal NVMe storage (never external USB drives for active volumes), and run `.\oscar.bat prepare-host`.

### Windows 11 unattended server preparation

Windows 11 desktops and mobile workstations ship with `Balanced` power defaults that can suspend
idle sessions, trigger S0 Low Power Idle (Modern Standby) when the display turns off, throttle AC
processor Energy Performance Preference (`PERFEPP > 0`), suspend
close-lid laptops, power down USB 3 buses/USB Gigabit Ethernet adapters/external USB SSDs, and
allow unbounded `vmmemWSL` memory/CPU growth. Before initializing a 24/7 OSCAR deployment on
Windows 11, assign the host's network-governed static IPv4 address (or configure a site router DHCP
reservation) so DHCP lease rotation cannot change the server IP embedded in `tls/server.crt`, then
run `configure-windows-host.ps1` (directly or through `oscar.bat`) from an Administrator Windows
PowerShell 5.1 window:

```powershell
.\oscar.bat host-check
.\oscar.bat prepare-host
```

Standalone invocation supports JSON output, strict non-zero audit exit codes, explicit `.wslconfig`
overrides (including opt-in `-WslNetworkingMode mirrored` on dedicated site LAN hosts without
conflicting corporate VPNs/Hyper-V switches), DHCP-reservation acknowledgement (`-AllowDhcpAddress`), and idempotent OpenSSH
`administrators_authorized_keys` public-key enrollment with `SYSTEM` + `Administrators` ACLs
(inheritance disabled):

```powershell
.\configure-windows-host.ps1 -Mode apply -ConfigureLanHttpsFirewall -AuthorizeSshPublicKeyFile C:\staging\operator.pub
.\configure-windows-host.ps1 -Mode check -Strict -Json
```

`-Mode apply` sets AC and DC sleep, unattended-sleep, hibernate, disk spin-down, and display-idle
timeouts to `0` (Never — preventing Windows S0 Modern Standby `Kernel-Power 506` entry on display
power-off), sets AC-only processor scheduling (`PROCTHROTTLEMIN=100%`, `PROCTHROTTLEMAX=100%`,
`PERFEPP=0` Maximum Performance, and boost enabled while leaving DC battery profiles untouched), disables hibernation and Fast Startup unless `-KeepHibernate` is requested, sets laptop
lid-close action to `Do nothing`, disables USB selective suspend and USB 3 Link Power Management,
turns off PCIe Link State Power Management (ASPM), clears WMI `MSPower_DeviceEnable` power-off flags
across USB controllers/storage/network devices, disables physical network-adapter power saving with
`-NoRestart` so active SSH sessions stay connected, enables `CrashControl` `AutoReboot=1` with
kernel/automatic crash dump retention (`CrashDumpEnabled=7` if disabled), configures `sshd` and
`w32time` for `Automatic` startup, sets `NoAutoRebootWithLoggedOnUsers=1`,
`AlwaysAutoRebootAtScheduledTime=0`, and `AUOptions=3` for Windows Update, sets Win32
`LongPathsEnabled=1` for tools that inspect deep retained-media paths, writes a hardware-proportional
`%USERPROFILE%\.wslconfig` (`memory`, `processors`, `swap=4GB`, plus optional `networkingMode` when
`-WslNetworkingMode` is explicitly passed) when none exists so `vmmemWSL`
reserves CPU and RAM headroom for Windows/Hyper-V/drivers (existing `.wslconfig` files are preserved
unless `-ForceWslConfig`, `-WslMemoryGb`, `-WslProcessors`, or `-WslNetworkingMode` is supplied), disables Docker Desktop
idle Resource Saver (`UseResourceSaver=false`), and registers two Scheduled Tasks alongside
`AutoStart=true`:

- `OSCAR-DockerDesktop-BootStart` (`AtStartup` `+10s`, `LogonType=S4U`, `RunLevel=Highest`) invokes
  an ACL-protected `%ProgramData%\OSCAR\start-docker-prelogin.ps1` (`SYSTEM` and `Administrators`
  only, inheritance disabled) to launch the Docker Desktop engine (`docker desktop start --detach`)
  in Session 0 without storing credentials, allowing `restart: unless-stopped` OSCAR containers to
  recover automatically after a cold power-loss or crash reboot even before anyone signs in on the
  physical console.
- `OSCAR-DockerDesktop-AutoStart` (`AtLogOn`, `LogonType=Interactive`) complements Windows 11
  Automatic Restart Sign-On (ARSO) when maintenance restarts sign the installing administrator back
  in behind a locked screen.

First-time Docker Desktop installation and license acceptance still require an interactive
administrator desktop session once; after `prepare-host` is run under that administrator account,
both cold-boot pre-logon recovery and routine SSH administration operate without manual console
sign-in. `host-check` also audits primary physical LAN IPv4 `PrefixOrigin` (`network-address-stability`),
warning if DHCP is active unless `-AllowDhcpAddress` is passed for networks governed by router DHCP
reservations. On trusted site LANs where newly connected USB or PCIe Ethernet adapters default to
Windows' `Public` firewall profile (which blocks inbound Docker Desktop port publishing on `443`),
pass `-ConfigureLanHttpsFirewall` (or `.\oscar.bat prepare-host -ConfigureLanHttpsFirewall`) to
switch connected wired `802.3` Ethernet adapters to `Private` and configure a scoped
`OSCAR-HTTPS-Gateway-In` rule (`TCP 443,80`, `Private,Domain`, `LocalSubnet` and `100.64.0.0/10`).

### Ubuntu 24.04 unattended server preparation, hotel-room staging & air-gapped cutover

Ubuntu Server 24.04 LTS defaults to a `100 GiB` `ubuntu-lv` root logical volume even on multi-terabyte NVMe drives, offers a Snap-confined `docker` installer checkbox that breaks bind mounts, leaves `unattended-upgrades` or desktop sleep targets unguarded, and can stall boot for 120 seconds on air-gapped multi-NIC portals without internet or DHCP. Run `configure-ubuntu-host.sh` through `oscar.sh` before or after `init` (and see [UBUNTU_FIELD_SETUP_GUIDE.md](../../docs/UBUNTU_FIELD_SETUP_GUIDE.md) plus `ubuntu/` for declarative `autoinstall`, Netplan, and Ansible templates, bootable USB links, and unknown-IP sensor discovery):

```sh
sudo bash oscar.sh host-check
sudo bash oscar.sh prepare-host --expand-lvm --configure-ufw
```

When pre-staging a server off-site (for example, on hotel Wi-Fi/DHCP with the site schematic in hand before traveling to an offline, no-DHCP portal):

```sh
sudo bash oscar.sh identify-nics --watch      # plug/unplug a cable to label physical RJ45 ports
sudo bash oscar.sh stage-site-network         # stages /etc/oscar/staged-netplan/90-oscar-site.yaml without dropping hotel DHCP
sudo bash oscar.sh init                       # embeds both current & staged site static IPs into tls/server.crt
# ...after arriving on-site and connecting switch cables:
sudo bash oscar.sh apply-site-network         # backs up DHCP Netplan, applies static IPs, refreshes TLS SANs & verifies health
sudo bash oscar.sh discover-devices --interface enp2s0   # optional: scan wire for unknown camera/RPM IPs
```

## Administrative CLI

Use `oscar.bat` on Windows and `oscar.sh` on Ubuntu. The Windows launcher invokes Windows
PowerShell 5.1 (`powershell.exe`); PowerShell 7 is not required.

Opening either launcher with no arguments starts a persistent `oscar>` administration menu. On Windows, double-clicking `oscar.bat` requests UAC elevation automatically; an Administrator Windows PowerShell 5.1 window does not need to be opened first. On graphical Ubuntu, opening the executable `oscar.sh` starts the menu in a terminal. Desktop file-execution policy varies, so direct terminal commands remain the supported fallback. Ubuntu Server has no graphical launcher and is administered from its terminal.

The menu accepts the same command and options shown below. For example, enter `init`, `status`, `logs -Service postgres -Follow` on Windows, or `logs --service postgres --follow` on Ubuntu. Enter `exit` to close the menu. Supplying arguments directly bypasses the menu, preserving automation compatibility.

| Action | Windows | Ubuntu |
| --- | --- | --- |
| Initialize | `oscar.bat init` | `sudo bash oscar.sh init` |
| Check prerequisites | `oscar.bat check` | `sudo bash oscar.sh check` |
| Audit host power/LVM/NIC readiness | `oscar.bat host-check` | `sudo bash oscar.sh host-check` |
| Apply unattended server settings | `oscar.bat prepare-host` | `sudo bash oscar.sh prepare-host --expand-lvm` |
| Identify physical NIC ports | Not applicable | `sudo bash oscar.sh identify-nics --watch` |
| Stage / apply / roll back static site IPs | Not applicable | `sudo bash oscar.sh stage-site-network` / `apply-site-network` / `rollback-network` |
| Discover unknown RPM & camera IPs | Not applicable | `sudo bash oscar.sh discover-devices --interface NIC` |
| Refresh self-signed TLS SANs after IP change | Not applicable | `sudo bash oscar.sh refresh-tls` |
| Verify offline media | `oscar.bat verify` | `sudo bash oscar.sh verify` |
| Start | `oscar.bat start` | `sudo bash oscar.sh start` |
| Stop | `oscar.bat stop` | `sudo bash oscar.sh stop` |
| Restart | `oscar.bat restart` | `sudo bash oscar.sh restart` |
| Status | `oscar.bat status` | `sudo bash oscar.sh status` |
| Logs | `oscar.bat logs` | `sudo bash oscar.sh logs` |
| Upgrade | `oscar.bat upgrade` | `sudo bash oscar.sh upgrade` |
| Coordinated backup | `oscar.bat backup` | `sudo bash oscar.sh backup` |
| Verify backup | `oscar.bat backup-verify -BackupId ID` | `sudo bash oscar.sh backup-verify ID` |
| Archive status | `oscar.bat archive status` | `sudo bash oscar.sh archive status` |
| Archive integrity | `oscar.bat archive verify` | `sudo bash oscar.sh archive verify` |
| Retention holds | `oscar.bat archive hold list` | `sudo bash oscar.sh archive hold list` |

Directly invoked mutating commands require an elevated Windows PowerShell 5.1 window on Windows or root privileges on Ubuntu. The Windows menu obtains elevation through UAC, and the Ubuntu menu invokes `sudo` when a selected command requires it.

`start`, `stop`, and `restart` never build or download images. `init` and `upgrade` may prepare missing images for a connected release. After building the local OSCAR/PostGIS images, setup rechecks the complete inventory and pulls the gateway only if it is still absent; an already-cached pinned gateway therefore does not create an unnecessary registry or credential-helper dependency. If `offline-images.tar` is present, every mutating setup run re-verifies the exact bundle inventory against the co-packaged `SHA256SUMS` and loads that checksum-verified archive even when same-version tags already exist locally. It never substitutes a stale local image for the selected bundle and fails if any required image remains unavailable afterward. Because the manifest is bundled and unsigned, this is an integrity check, not publisher or release-origin authentication. Sites that require origin authentication must verify the outer ZIP against an independently trusted detached signature or provenance attestation before offline transfer.

On Windows, connected setup builds the two release-local images with explicit
`docker build` contexts after validating the deployment paths. This avoids the
Docker Compose 5.6/Buildx 0.37 filesystem-entitlement regression that can
misclassify an in-tree Dockerfile and request an unavailable `fs.read` approval.
OSCAR does not disable Bake filesystem checks globally or grant wildcard host
filesystem access; the image tags, release version argument, and PostgreSQL
platform remain identical to `compose.yaml`.

Use the launchers for a complete stop or restart rather than issuing an unscoped multi-service
`docker compose stop` or `docker compose restart`. The supported launchers stop the gateway first,
wait for OSCAR to finish its bounded journal/module shutdown while PostgreSQL remains available,
and stop PostgreSQL last. Restore uses the same dependency-safe order before replacing state.

Offline releases are published in two Windows x86-64 profiles:

- `offline-full` contains OSCAR images plus the approved Docker Desktop and WSL installers.
- `offline-images` contains OSCAR images only and requires Docker Desktop, WSL 2, and Docker Compose to be installed and running already.

Initialization defaults to `-Prerequisites auto`, which uses a working existing Docker installation and only launches bundled installers when Docker is unavailable. Use `-Prerequisites existing` to prohibit prerequisite installation, or `-Prerequisites bundled` to explicitly permit the bundled fallback. Official offline release media and bundled prerequisites are Windows-only. Supported Ubuntu deployments use a connected release with Docker Engine/Compose already installed; Bash `--prerequisites bundled` support is only for a separately qualified, site-prepared `.deb` set and is not built, validated, or published by the release workflow.

## Initial setup options

The defaults are hostname `oscar.local`, HTTPS port `443`, and a self-signed certificate. Setup asks for an administrator password of at least 14 characters, generates unique database credentials, validates TLS, and starts the deployment. For a new self-signed installation, setup automatically adds active non-container LAN IPv4 addresses, active Tailscale IPv4/IPv6 addresses, and the connected Tailscale MagicDNS name (when discoverable) to the certificate. It prints every covered client URL when initialization completes. Ordinary SLAAC privacy IPv6 addresses are intentionally excluded because they rotate before the certificate expires; add a site-stable IPv6 address explicitly when required.

With the default HTTPS port, entering the configured hostname without a scheme is supported: the gateway redirects the browser from HTTP to HTTPS while preserving the requested path. Deployments using a nonstandard HTTPS port must include that port in the URL printed by setup.

Windows example with an imported certificate:

```powershell
.\oscar.bat init -Hostname oscar.example.org -Port 443 `
    -TlsMode import -CertificatePath C:\certs\server.crt `
    -PrivateKeyPath C:\certs\server.key
```

Windows self-signed LAN/Tailscale example with additional stable names:

```powershell
.\oscar.bat init -Hostname oscar-site.example.org -Port 443 `
    -TlsSan 192.168.0.61,oscar-site.example-tailnet.ts.net
```

Ubuntu equivalent:

```sh
sudo bash oscar.sh init --hostname oscar.example.org --port 443 \
    --tls-mode import --certificate /secure/server.crt \
    --private-key /secure/server.key
```

Ubuntu self-signed LAN/Tailscale example with additional stable names:

```sh
sudo bash oscar.sh init --hostname oscar-site.example.org --port 443 \
    --tls-san 192.168.0.57 \
    --tls-san oscar-site.example-tailnet.ts.net
```

`--tls-san` is repeatable on Ubuntu. `-TlsSan` accepts a comma-separated list on Windows. Automatic
network SAN discovery is enabled only for newly generated self-signed certificates. Use
`--no-auto-network-sans` or `-NoAutoNetworkSans` when a deliberately hostname-only certificate is
required. Container bridge, Docker, WSL, loopback, and link-local addresses are excluded. If
Tailscale is enabled after initialization, replace the certificate through the controlled
certificate-renewal process or initialize with the expected stable Tailscale IP/MagicDNS name
explicitly; do not edit a certificate in place.

By default, setup maps the hostname only on the OSCAR host. Use `-SkipHostsEntry` or `--skip-hosts-entry` to leave local host resolution unchanged. Site DNS or a hosts entry is still required on every workstation that connects to OSCAR.

`server.crt` must be a PEM certificate or chain. `server.key` must be its matching unencrypted PEM private key. The certificate subject alternative names must contain every DNS name or IP address used to reach OSCAR.

For an isolated deployment, administrators may use a deployment-specific certificate authority and install only its public certificate on workstations. Never place the certificate-authority private key in this release directory, a container, or a diagnostic bundle.

### LAN and Tailscale client trust

The generated self-signed `tls/server.crt` is public and may be copied to operator workstations. An
imported certificate already chaining to a workstation-trusted issuer needs no additional import. Verify the certificate's
SHA-256 fingerprint against the value obtained directly from the OSCAR host before trusting it.
Never copy `tls/server.key`. Installing the public certificate trusts only this deployment's
self-signed identity; it does not make an unlisted hostname or IP valid.

- Windows client, from an elevated PowerShell window:
  `certutil -addstore -f Root .\server.crt`
- Ubuntu client: copy it to `/usr/local/share/ca-certificates/oscar-site.crt`, then run
  `sudo update-ca-certificates`. For Chrome or Chromium on Linux (which reads NSS `~/.pki/nssdb`
  rather than `/etc/ssl/certs`), also import it once per desktop user:
  `certutil -d "sql:$HOME/.pki/nssdb" -A -t "CT,C,C" -n "OSCAR Site" -i ./server.crt` (`libnss3-tools`).
- macOS client: run
  `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./server.crt`
  (or use Keychain Access to add `server.crt` to the System keychain and mark it **Always Trust**),
  after verifying the fingerprint. Note that Apple macOS and iOS enforce a maximum `825`-day
  validity period on leaf TLS server certificates (`ERR_CERT_VALIDITY_TOO_LONG`); see the site
  Root CA snippet below whenever macOS/iOS browsers or Touch ID / Face ID Passkeys are used on a LAN.

### Enabling local and LAN WebAuthn Passkeys (multi-node hostnames, DNS/hosts & TLS trust)

Browser WebAuthn Passkeys (`navigator.credentials.create` / `navigator.credentials.get`) enforce two
strict browser-side prerequisites that do not apply to local PBKDF2 password sign-in:

1. **A domain name (not a raw IP literal):** Opening `https://192.168.0.57/` continues to support
   username + password sign-in (including phone-free facilities), but browsers disable WebAuthn on
   IPv4/IPv6 literals. Always open OSCAR via a domain name such as `https://oscar.local`,
   `https://oscar.ubuntu`, or `https://oscar.win`. When operating **multiple OSCAR servers on the
   same LAN**, give each node its own distinct hostname during `init` (for example,
   `sudo bash oscar.sh init --hostname oscar.ubuntu` on node 1 and
   `.\oscar.bat init -Hostname oscar.win` on node 2) so host entries, TLS certificates, and Passkey
   relying-party IDs (`rpId`) never collide.
2. **A trusted HTTPS certificate without bypassed browser warnings:** Clicking past an untrusted
   certificate warning puts Chrome, Edge, and Safari into a degraded TLS state that blocks Passkey
   registration and sign-in. Complete the three steps below once per site so Passkeys work both
   locally on the host and across every LAN workstation or phone:

- **Step 1 — Resolve the node's domain name locally and across the LAN:**
  - *On the OSCAR host itself (offline-ready):* `oscar init` automatically maps `127.0.0.1 <hostname>`
    in `/etc/hosts` (`C:\Windows\System32\drivers\etc\hosts` on Windows) so local Passkey sign-in works
    even when the LAN cable is unplugged.
  - *Whole-LAN (recommended for multiple laptops and phones):* Add Local DNS (`A`) records on the site
    router or internal DNS server mapping each node's hostname to its static LAN IP (for example,
    `oscar.ubuntu -> 198.51.100.57` and `oscar.win -> 198.51.100.170`).
  - *Per-workstation fallback (air-gapped LAN without router DNS access):* Map the hostname(s) in each
    client workstation's `hosts` file:
    - macOS / Linux: `printf '198.51.100.57\toscar.ubuntu\n198.51.100.170\toscar.win\n' | sudo tee -a /etc/hosts`
    - Windows (elevated PowerShell):
      `Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "198.51.100.57`toscar.ubuntu"; ipconfig /flushdns`
- **Step 2 — Issue an `<= 825`-day LAN Root-CA certificate when macOS/iOS clients or multiple nodes are present (optional on Windows/Linux-only single nodes):**
  Generate a one-time site Root CA (`oscar-lan-root-ca.crt`), sign an `820`-day leaf certificate
  containing all DNS and IP Subject Alternative Names (`SAN`s) for each node, and shred the Root CA
  private key immediately so no extra secret needs to be stored:
  ```sh
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -days 3650 \
    -subj "/O=OSCAR Local Deployment/CN=OSCAR Local LAN Root CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -keyout ca.key -out oscar-lan-root-ca.crt
  openssl req -newkey rsa:3072 -nodes -subj "/CN=oscar.ubuntu" -keyout server.key -out server.csr
  printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:oscar.ubuntu,DNS:oscar.local,DNS:localhost,IP:198.51.100.57,IP:127.0.0.1\n' > server.ext
  openssl x509 -req -in server.csr -CA oscar-lan-root-ca.crt -CAkey ca.key -CAcreateserial \
    -out leaf.crt -days 820 -sha256 -extfile server.ext
  cat leaf.crt oscar-lan-root-ca.crt > server.crt
  shred -u ca.key 2>/dev/null || rm -f ca.key
  ```
  Pass `--tls-mode import --certificate server.crt --private-key server.key` during `init`, or to
  rename an **existing** deployment without re-initializing or losing data: update
  `OSCAR_HOSTNAME=oscar.ubuntu` in `.env`, copy `server.crt` and `server.key` into `tls/`, update
  `127.0.0.1 oscar.ubuntu` in the host's `hosts` file, and run
  `docker compose up -d --force-recreate gateway`.
- **Step 3 — Trust the public certificate (`oscar-lan-root-ca.crt` or `tls/server.crt`) once on each client device:**
  Use `certutil -addstore -f Root .\oscar-lan-root-ca.crt` on Windows, `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain oscar-lan-root-ca.crt` on macOS, or `update-ca-certificates` + `certutil -d "sql:$HOME/.pki/nssdb"` on Linux. One shared `oscar-lan-root-ca.crt` trusts every OSCAR node signed by that batch. Because WebAuthn scopes Passkeys to the exact domain (`rpId`), a Passkey enrolled at `https://oscar.ubuntu` signs in locally and across the LAN via `https://oscar.ubuntu`; if the same user also connects through a public Zero-Trust tunnel domain (`https://site.example.org`), they simply click **Add a Passkey or Security Key** once on that tunnel URL under the same OSCAR account.

For ordinary LAN operation, create a site DNS record pointing the configured hostname at the
OSCAR host's static address. A per-workstation hosts entry is an acceptable isolated-test fallback,
but it does not scale and must map the same hostname that appears in the certificate. Direct access
such as `https://192.168.0.57/` requires that exact IP SAN; accepting a warning for a certificate
issued only to `oscar.local` is not a supported substitute.

The gateway publishes the configured HTTPS port on the host interfaces by default. Scope the host
and upstream firewalls to permit that TCP port from authorized LAN subnets and, when used, the
Tailscale interface/tailnet only; do not expose it through a WAN port-forward. TCP port 80 is used
only for the hostname-to-HTTPS redirect and may remain blocked when clients use the printed HTTPS
URLs directly. On Windows, approve Docker Desktop access only for the intended network profile.

For Tailscale access, prefer the stable MagicDNS name and include it explicitly when it is not
discoverable during setup. Direct Tailscale-IP access is supported when the printed certificate
URL contains that IP. Tailscale connectivity does not distribute OSCAR's certificate trust: each
client must still trust `server.crt`, or the deployment must import a certificate already trusted
by those clients. Restrict Tailscale ACLs separately so only authorized operators can reach the
OSCAR HTTPS port.

## Windows offline installation

Extract the offline ZIP into a local NTFS directory. From an Administrator Windows PowerShell 5.1
(`powershell.exe`) window:

```powershell
.\verify-bundle.ps1
.\oscar.bat init
```

The equivalent CLI command is `oscar.bat verify`. Verification requires the exact bundle inventory:
every allowed regular payload file appears once in `SHA256SUMS`, every listed digest matches, only
OSCAR's closed non-executable runtime state paths (`.env`, `.oscar-init-state`,
`.oscar-volume-adoption`, the four `secrets/*.txt` files, `tls/server.{crt,key}`, and
`pre-restore-<id>` credential backups) may exist outside `SHA256SUMS` after initialization, and no
extra, linked, reparse-point, aliased, or prefix-colliding path is accepted. OSCAR records a receipt
for audit, but every later mutating `init` or `upgrade` repeats the full pass before it can execute a
bundle payload. Routine non-setup commands do not perform full bundle verification; run `verify`
explicitly whenever post-installation tampering is suspected.

The full artifact can launch only the unique, allowlisted and checksum-covered installer paths named by its manifest
when WSL or Docker Desktop is missing. An extra wildcard-matching installer is rejected rather than
selected. The images-only artifact must be initialized with a working existing runtime:

```powershell
.\oscar.bat init -Prerequisites existing
```

If an installer requires a restart, restart Windows and run `oscar.bat init` again. When `init` runs
with `-NonInteractive` or from an OpenSSH Session-0 shell, OSCAR passes `--quiet` (never
`--accept-license`) to the bundled Docker Desktop installer so it cannot block on an unseen
Session-0 completion dialog, then stops cleanly whenever a Windows feature restart or interactive
desktop Docker Desktop launch/license acceptance is required.

The offline CLI does not contact package repositories or container registries. Docker Desktop
licensing must be reviewed and accepted independently by the deploying organization; OSCAR does not
accept that agreement. A required installer restart is also an explicit administrator acceptance
step before setup is resumed.

## Logs

The default displays the last 200 lines from all services and exits:

```powershell
.\oscar.bat logs
```

Select a service and optionally follow it:

```powershell
.\oscar.bat logs -Service oscar -Tail 500
.\oscar.bat logs -Service postgres -Follow
.\oscar.bat logs -Service gateway
```

Ubuntu uses `--service`, `--tail`, and `--follow`.

## Persistent state and secrets

Initialization creates:

```text
.env
secrets/oscar-admin-password.txt
secrets/oscar-db-password.txt
secrets/postgres-bootstrap-password.txt
secrets/backup-key.txt
tls/server.crt
tls/server.key
```

Docker Compose mounts secrets read-only. On Ubuntu, the setup CLI makes `secrets` and `tls` mode `0700`, with contained files readable by the deliberately non-root services. On Windows, it restricts the directories to the installing administrator and `SYSTEM` while preserving container-readable, read-only mounts. During a fresh `init`, as soon as OSCAR hashes the initial administrator password into `/var/lib/oscar/config.json` (`PBKDF2WithHmacSHA256`, 310,000 iterations), setup overwrites `secrets/oscar-admin-password.txt` with a non-empty `# CONSUMED_AT_INIT: <UTC>` marker so the plaintext bootstrap password does not remain on disk (unless `OSCAR_KEEP_BOOTSTRAP_SECRET=true` is explicitly exported for automated test harnesses).

### Authentication, offline Passkeys, persistent sessions, SSO & remote-access tunnel

OSCAR 3.11.0 manages operator and service identities without requiring command-line edits or external internet access:

1. **Persistent "Stay Signed In Until Logout" Sessions:** Fresh configurations default `idleTimeoutSeconds = 0`, `absoluteTimeoutSeconds = 0`, `persistSessions = true`, and `allowKeepSignedIn = true` (`persistentCookieMaxAgeSeconds = 31536000`). Only SHA-256 digests of active `OSCAR_SESSION` cookies are stored in `/var/lib/oscar/.moduledata/oscar-identity.json` (`0600`), allowing dedicated gatehouse workstations to stay signed in across browser restarts, host reboots, and `oscar upgrade` until the user clicks **Log Out** or an administrator disables/revokes the account. Shared shift kiosks can switch to timed sessions (for example, `30m` idle / `8h` max) in **Users & Access -> Sign-In & SSO Policy**.
2. **Non-IT Users & Access Console (`/users` in OSCAR Viewer):**
   - **Self-Service Account, Offline Passkeys, Passwords & Tunnel Independence:** Every signed-in user can register phishing-resistant WebAuthn / FIDO2 Passkeys (`ES256` and `RS256` — Windows Hello, Touch ID, Face ID, or USB/NFC hardware security keys such as YubiKey) verified 100% locally by OSCAR with zero internet dependency, or update their local PBKDF2 password (`>= 12` characters) for phone-free facilities. **OSCAR local passwords and Octelium Zero-Trust tunnel credentials are two separate, independent authentication layers**: changing a user's OSCAR password does not require changing their Octelium password (and `oscar-tunnel` authenticates to the Hub with its own ServiceAccount token, so user password changes never affect tunnel uptime). WebAuthn requires opening OSCAR via a domain name (`https://oscar.local` or site DNS/Octelium hostname) rather than a raw IP address.
   - **Users, Roles, Bulk CSV Enrollment & 1-Tap QR Startup Invites:** Administrators create, disable, reset, sign out, or delete individual `Administrator`, `Operator`, and read-only `Viewer` accounts (with last-admin lockout protection), or click **Bulk Enroll (CSV / Paste)** to upload or paste a roster (`username, role, display_name, views`) of up to 500 users at once. For every enrolled user, OSCAR generates a ready-to-send startup text message, a printable handout card, a single-use QR code & setup link (`/login/enroll?token=oscar_inv_...` — read-only on `GET` so SMS/chat link-preview bots never burn the invite, letting the user register a 1-tap Passkey or set their private password and land directly in their assigned Operational View), AND a readable fallback code for phone-free workstations (`/login/password-change`). `Operator` and `Viewer` accounts can be restricted to specific **Operational Views** (enforced both in `BasicSessionAuthenticator` for `/view/<slug>` and in OSCAR Viewer).
   - **Scoped Federation Service Tokens (`oscar_fed_<shortId>_<secret>`) & Where to Use Them:** Administrators mint revocable `Viewer` or `Operator` tokens on the monitored node in **Users & Access -> Federation Tokens**, then open **Servers (`/servers?auth=bearer`)** on the monitoring/HQ OSCAR Viewer (or click **Open Servers Page (Federation Token Mode)** directly from the token banner) to paste the token into **Add Server -> Authentication Method: Federation Service Token** (`HTTPS`, port `443`), authenticating both ConSys/Bucket HTTP `Bearer` requests and HiveMQ WebSocket MQTT (`svc-fed-<shortId>`) without sharing human passwords.
   - **Optional Corporate OIDC + PKCE & Trusted Zero Trust Tunnel SSO:** Sites connected to an enterprise IdP (Entra ID, Okta, Keycloak) or the turnkey self-hosted [`ORNL/oscar-federation-hub`](https://github.com/ORNL/oscar-federation-hub) (Octelium + Authentik) can enable OIDC + PKCE (`Sign in with Organization SSO` on `/login`, JWKS signature validation, optional private-CA PEM trust via `oidcTrustedCaCertificatePath`, IdP group-to-role mapping for `oscar-admins` / `oscar-operators`, and an optional **External SSO Admin Console URL** surfaced as a 1-click **Open Federated User Console** shortcut on `/users`) while keeping local Passkeys and passwords active whenever WAN connectivity drops. Deployments behind an authenticated Octelium Zero Trust tunnel (`oscar-remote-access.sh` / `oscar-remote-access.ps1`) can also enable Trusted Tunnel header SSO (`X-Octelium-User` and optional `X-Octelium-Groups` gated by a `>= 16`-character `X-Oscar-Tunnel-Secret`, mapping `oscar-admins` -> `Administrator`, `oscar-operators` -> `Operator`, and fallback -> `Viewer` without overwriting `local` accounts). During `oscar upgrade`, setup automatically runs `oscar-remote-access sync --rebuild` whenever `$STORAGE_ROOT/remote-access/octelium.env` and `octelium-token.txt` are present so `oscar-tunnel:${OSCAR_VERSION}` is rebuilt and recreated in lockstep, and `oscar backup` / `oscar restore` encrypt and restore `remote-access/` alongside `secrets/` and `tls/`.

#### Turnkey self-hosted federated remote access & SSO (`ORNL/oscar-federation-hub`)

Organizations that operate multiple firewalled or NATed OSCAR sites and want a simple, self-hosted way to reach sites remotely and add or revoke operator access from a single place—without requiring an external cloud IdP or opening inbound firewall ports at field portals—can deploy the companion [`ORNL/oscar-federation-hub`](https://github.com/ORNL/oscar-federation-hub) stack on a central Linux VM or HQ server:

1. **Prepare the central Hub host:** Point `hub.example.org` and `*.hub.example.org` to a Linux host reachable on TCP/UDP `443` with an initialized Octelium cluster (`octeliumctl` authenticated) and Docker Compose v2, then clone and initialize [`ORNL/oscar-federation-hub`](https://github.com/ORNL/oscar-federation-hub):
   ```sh
   git clone https://github.com/ORNL/oscar-federation-hub.git
   cd oscar-federation-hub

   # Mode A (Recommended): Octelium Zero-Trust tunnel + Authentik browser user console
   ./oscar-hub.sh init --domain hub.example.org --with-authentik --admin-email secops@example.org

   # OR Mode B (Lightweight): Octelium CLI-only user management (no Authentik container stack)
   ./oscar-hub.sh init --domain hub.example.org
   ```
   Mode A automatically launches pinned Authentik containers (`versions.env`) and applies a Blueprint that pre-creates the `oscar-admins`, `oscar-operators`, and `oscar-viewers` groups, configures the `groups` OIDC claim, and pre-authorizes `https://<site>.hub.example.org/login/oidc/callback`.
2. **Register each OSCAR site & connect its outbound tunnel sidecar:** On the Hub host, mint a site-scoped workload connector token:
   ```sh
   ./oscar-hub.sh add-site north-gate --display-name "North Gate Portal" --with-trusted-headers
   ```
   Copy `state/tokens/north-gate.token` securely to that OSCAR 3.11.0 host and run OSCAR's built-in remote-access helper (then delete the temporary token file):
   ```sh
   # Ubuntu Server 24.04
   sudo bash oscar-remote-access.sh configure \
     --domain hub.example.org \
     --service north-gate \
     --token-file /root/north-gate.token
   sudo shred -u /root/north-gate.token
   ```
   ```powershell
   # Windows 11 + WSL 2 (Administrator PowerShell)
   .\oscar-remote-access.ps1 configure `
     -Domain hub.example.org `
     -Service north-gate `
     -TokenFile C:\Users\Admin\north-gate.token
   Remove-Item -Force C:\Users\Admin\north-gate.token
   ```
3. **Wire centralized SSO in OSCAR (`Users & Access -> Sign-In & SSO Policy`):** Sign in to the OSCAR Viewer as an `Administrator`, open **Users & Access (`/users`) -> Sign-In & SSO Policy**, and paste the exact settings printed by `oscar-hub.sh`:
   - **Browser OIDC SSO (Mode A):** Enable **OIDC Single Sign-On**, set **Issuer URL** to `https://auth.hub.example.org/application/o/oscar-federation-sso/`, **Client ID** to `oscar-federation-hub`, **Client Secret** from `state/secrets/oidc-client-secret.txt`, **Scopes** to `openid profile email groups`, **Admin / Operator Groups** to `oscar-admins` / `oscar-operators`, and **External SSO Admin Console URL** to `https://auth.hub.example.org/if/admin/` (which adds a 1-click **Open Federated User Console** button at the top of **Users & Roles**). If your Hub uses an internal PKI instead of Let's Encrypt, supply the mounted root CA PEM path in **OIDC Custom CA Certificate Path**.
   - **Zero-Click Trusted Tunnel SSO (`--with-trusted-headers`):** Optionally enable **Verified Tunnel Header SSO** with `X-Octelium-User`, `X-Octelium-Groups`, and the `>= 16`-character `X-Oscar-Tunnel-Secret` from `state/secrets/oscar-tunnel-shared-secret.txt` so operators already signed into the Hub land directly inside OSCAR with their mapped role.
   - **Coexistence with Local Offline Accounts & Node Data Federation:** Central `oidc`/`tunnel` accounts never overwrite local `authSource = "local"` accounts, so site-local Passkeys and PBKDF2 passwords continue working on the local LAN during WAN outages. For server-to-server alarm/video aggregation onto a Central OSCAR Viewer, mint a dedicated `oscar_fed_...` **Federation Service Token** on each site and add `north-gate.hub.example.org` (`HTTPS`, port `443`) on Central's **Servers** page so disabling a human employee never interrupts site-to-central telemetry.

The application configuration is copied into the `oscar_state` volume on first startup. Runtime configuration saves update only that persistent copy. Application libraries and viewer assets remain read-only in the image. PostgreSQL data is stored in the `postgres_data` volume. OSCAR 3.11.0 uses a long-lived host bind for the primary Parquet cold tier (`OSCAR_ARCHIVE_DIR`) so multi-year archives can reside on a dedicated host volume, survive `docker compose down -v` or Docker Desktop resets, and undergo direct host-side ACL, `.oscar-storage-root`, and offline backup verification; on Windows WSL 2 `9p`/`drvfs` mounts, OSCAR automatically caches SHA-256-verified Parquet generations inside a disk-proportional (`2–8 GiB`, excluded from backups) native `ext4` cache (`/var/lib/oscar/.cache/oscar-9p-parquet-cache`) so repeat historical queries avoid cross-VM `9p` read amplification without giving up host-bind durability. Keep `OSCAR_JAVA_OPTS` aligned with `.env.example` rather than forcing oversized `ForkJoinPool.common.parallelism` values on 4–8 core hosts. PostgreSQL runs with `archive_mode=off`, no external archive command, and no WAL bind. An existing `OSCAR_WAL_ARCHIVE_DIR` is preserved only to avoid deleting legacy data; current schema-v1/v2 restore does not use it. Fresh deployments set `OSCAR_BACKUP_MODE=disabled`; after explicit `single` opt-in, `OSCAR_BACKUP_DIR` is an operator-selected safe absolute host path that does not overlap the release or archive roots and is never mounted into a long-running service. A separate physical drive is recommended for failure isolation but is not required. A Docker named-volume backup or Parquet copy alone is incomplete.

The OSCAR service keeps the general-purpose `/tmp` tmpfs `noexec`. Embedded Java native libraries,
including DuckDB JDBC and JavaCPP/FFmpeg, are extracted instead to a separate 256 MiB tmpfs at
`/run/oscar-native`. That mount is executable only because the JVM must map shared objects; it is
still ephemeral, `nosuid`, `nodev`, owned by the non-root OSCAR user, and mode `0700`. The entrypoint
forces `java.io.tmpdir` to that path after `OSCAR_JAVA_OPTS` and refuses to start unless `/tmp` is a
dedicated `noexec` tmpfs and the native mount has the expected type, ownership, permissions, and
execution behavior. User-supplied multipart and spectrum-conversion temporary files remain on
`/tmp` through the separately managed `oscar.data.tmpdir` property, so they never enter the
executable native directory. Do not override either mount or add `-Djava.io.tmpdir` or
`-Dorg.bytedeco.javacpp.cachedir` or `-Doscar.data.tmpdir` to `OSCAR_JAVA_OPTS`. The entrypoint
also rejects `_JAVA_OPTIONS`, which OpenJDK applies after command-line options; custom launchers
must reproduce this two-mount contract.

DuckDB query scratch is separate from both temporary mounts and the immutable archive. Every
archive connection is limited by the persisted database-module settings (shipping defaults:
256 MiB memory, two threads, and 4 GiB spill) and gets a private child below
`/var/lib/oscar/duckdb-tmp` in `oscar_state`. Normal connection close removes the child; coordinated
backups exclude this scratch parent. OSCAR holds an operating-system lease in the persistent
`.oscar-duckdb.lock` file for its process/classloader lifetime, so a second owner cannot clean live
spill. The first session after a crash, while holding the lease, automatically removes only direct
children matching the canonical `<operation>-<lowercase UUID>` form; it preserves unrelated entries
and never follows symbolic links. Streaming archive reads check shutdown cancellation between rows
as well as cancelling an active JDBC statement. The scratch and archive roots must be disjoint. In
the Linux container (on either Ubuntu or Windows hosts), OSCAR requires POSIX mode `0700` on the
parent and each operation child, and a real regular non-link lease with mode `0600`; broader or
unsafe existing permissions are rejected. A non-container/non-POSIX embedding must provide
equivalent owner-only ACLs. Manual cleanup is a fallback only: stop OSCAR first and remove only
confirmed abandoned canonical operation children, never the lease or unrelated entries while a
process may be active.
The backup exclusion is intentionally limited to the reserved `/var/lib/oscar/duckdb-tmp` path.
OSCAR therefore rejects any other scratch path inside `/var/lib/oscar`; a custom path must be
outside that persistent state tree and disjoint from the archive.

The backup key encrypts `.env`, deployment secrets, and TLS private material inside coordinated backups. The encrypted `secrets/` payload contains a recovery copy of the key file, but there is no usable plaintext key in the backup: store an external protected copy in an independent secret escrow or failure domain.

The gateway gives content-hashed Viewer files under `/_next/static/` a private, one-year immutable browser cache policy, while `/sw.js` is always revalidated. This prevents repeated full-route navigations from downloading the same application bundles again without allowing a shared proxy to cache an authenticated response. HTML and API responses keep their normal revalidation behavior.

`oscar stop` retains containers, named data volumes, the archive bind, preserved legacy data, and the external
backup root. Do not use `docker compose down --volumes` as a records-destruction procedure: Compose
skips OSCAR's external named volumes, and neither that command nor container removal deletes the
archive, legacy-WAL, or backup roots. Authorized permanent destruction therefore requires the documented,
explicit removal of every retained data location.

WebID is disabled by default. Failure to reach an optional configured WebID endpoint must not prevent OSCAR from starting.

### External EML runtime plugin upload (`Code 9999`) & extended occupancy gamma auto-adjudication (`Code 9998`)

OSCAR does not bundle or redistribute external Enhanced Machine Learning (EML) VM-250 JARs, models, or XML configuration files. Sites licensed to run EML upload their EML plugin `.jar` (or `.tar.gz`/`.tgz`/`.zip` bundle) once in SensorHub Admin under **Services -> OSCAR Service -> EML Plugin Path** (`emlPluginPath`), click **Apply Changes** and **Save Configuration**, and enable **Enable EML** (`emlEnabled`), **Lane Collimated** (`isCollimated`), and **Lane Width** (`laneWidth`) on each Rapiscan VM-250 lane (or via the `EMLEnabled`, `EMLCollimated`, and `LaneWidth` CSV columns). The uploaded archive is stored privately in `/var/lib/oscar/eml-plugin/` (`0700`/`0600`) inside `oscar_oscar_state` (preserved across restarts, upgrades, and schema-v2 backups and never exposed over HTTP `/sensorhub/buckets`), extracted at runtime onto `/tmp/oscar-eml-runtime` (`oscar.data.tmpdir`), and loaded in an isolated `URLClassLoader`. When EML classifies an alarm occupancy as non-threat (`RELEASE`, `fallback=false`), OSCAR suppresses it from the Dashboard alarm queue and browser notifications and automatically adjudicates it as **`Code 9999: EML Non-Threat`** with structured `EML_METADATA` JSON queryable in the **Events** page (`Adjudicated = EML Non-Threat` or `Adjudication Code = 9999: EML Non-Threat`) and inspectable in **Event Details**. Full packaging, upload, lane configuration, and query instructions are in [`../../docs/EML_INTEGRATION.md`](../../docs/EML_INTEGRATION.md).

In addition, each lane configures an **Extended Occupancy Threshold** (`extendedOccupancyThresholdMinutes`, `1`–`1440` minutes, default `1` minute) in SensorHub Admin (**Lane Sensor System -> Extended Occupancy Threshold (min)**) and via the `ExtendedOccupancyMinutes` CSV column. When a vehicle remains in a Rapiscan, Aspect, or RS350 lane past that threshold, OSCAR publishes an `occupancyStatus` fault observation (`extendedOccupancyFault = true`, `alarmState = "Fault - Extended Occupancy"`), activates the **Extended Occupancy** indicator on the Status of Health page and Dashboard lane card, and increments the lane's `Ext-Occ` fault count in National Statistics and Lane Reports until the lane clears. When that extended occupancy completes with a **gamma-only alarm** (`gammaAlarm = true` and `neutronAlarm = false`), OSCAR automatically adjudicates the event prior to publication with disposition **`Code 9998: Extended Occupancy Gamma Alarm`** (`username = "AUTO"`, `secondaryInspectionStatus = "NONE"`, stamping `"extended-occupancy-gamma"` and `"code:9998"` onto `occupancy.adjudicatedIds`), suppressing it from the live Dashboard queue and browser notifications at `t = 0` while keeping it searchable on the **Events** page (`Adjudication Code = 9998: Extended Occupancy Gamma Alarm`) and visible in **Event Details** and **Adjudication Reports**. Any extended occupancy that includes a **neutron alarm** (`Gamma-Neutron` or `Neutron`) is never auto-adjudicated and remains an active alarm requiring operator adjudication.

The OSCAR container health check is an application-readiness check, not merely an HTTP liveness
probe. It becomes healthy only after the web service and every top-level auto-start module are
`STARTED`, and after each nested RPM/camera member has completed its startup attempt. A device that
cannot connect may settle offline while OSCAR remains healthy so the Status of Health page can
report it. During a 50-lane startup,
`docker compose ps` may therefore show OSCAR as `starting` after the login endpoint begins to
respond. Do not chain another restart or storage-maintenance operation during that interval. The
launcher and storage commands wait for this stronger health signal automatically. An `unhealthy`
result means at least one required module failed to complete startup; inspect the OSCAR container
logs for that module.

### Troubleshooting support bundles (Viewer UI and host CLI)

OSCAR writes bounded rolling server logs inside `oscar_oscar_state` at `/var/lib/oscar/logs/oscar.log` (`10 MB` per file, `5` rotated archives, `50 MB` total cap) and provides two redacted `.zip` export paths so operators and administrators can collect diagnostics whether the web console is healthy or the stack cannot start:

1. **In-UI 1-click export (`Help (?) -> Export Support Bundle`):** Signed-in operators with `reports` read permission can select **Help (`?`)** in the OSCAR Viewer navigation bar and click **Export Support Bundle** (also available on the **Troubleshooting & FAQ** tab). The browser merges its bounded flight-recorder ring buffer (`client/client-diagnostics.json` — recent warnings/errors, uncaught exceptions, failed or slow `>= 2500 ms` `fetch` timings, and node connectivity summary) with `/sensorhub/buckets/reports/support-bundle` (`backend/oscar.log`, `backend/module-logs/*.log`, `backend/modules.json` including nested lane/RPM/camera driver states and stack traces, `backend/jvm-diagnostics.json`, `backend/storage-summary.json`, and `backend/config.redacted.json`) into `oscar-support-<UTC>.zip` (`<= 15 MB`). If the backend is unreachable, the Viewer automatically downloads `oscar-client-support-<UTC>.zip` with host CLI instructions.
2. **External host CLI (`support-bundle`):** Even if `.env` is incomplete or containers are stopped or crash-looping, run:

```powershell
.\oscar.bat support-bundle [-Tail 2500] [-Destination PATH]
```

```sh
sudo bash oscar.sh support-bundle [--tail 2500] [--output PATH]
```

   The CLI collects host OS/memory/disk/WSL 2 metadata (`host/system-info.txt`), redacted `.env` (`host/env.redacted.txt`), public X.509 certificate dates/SANs/SHA-256 fingerprint (`tls/certificate-info.txt`), `docker/compose-ps.txt`, `docker/volumes.txt`, sanitized `docker/inspect.redacted.json` (with `Config.Env` and `/run/secrets` mounts stripped), `logs/*.log`, read-only `oscar_oscar_state` volume logs and redacted `config.json` (`volume/*`), `archive/status.txt` when configured, `summary.json`, and `redaction-report.json` into `oscar-host-support-<UTC>.zip` (`<= 25 MB`, written outside the release directory by default so offline `SHA256SUMS` inventories remain untouched). Both export paths automatically mask passwords, tokens, URI credentials, `Authorization`/`Cookie` headers, query secrets, PEM private keys, and email addresses, and never collect `secrets/*`, `/run/secrets/*`, `tls/*.key`, or `.keystore/*`.

## Security verification

After startup:

```sh
docker compose ps
docker compose exec -T postgres sh -eu -c '
  PGPASSWORD=$(cat /run/secrets/postgres_bootstrap_password)
  export PGPASSWORD
  exec psql --set=ON_ERROR_STOP=1 --username oscar_bootstrap --dbname gis "$@"
' psql-wrapper --command "SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls FROM pg_roles WHERE rolname = 'oscar_app';"
```

Every reported privilege flag for `oscar_app` must be false. A host scan must show port `80` and the configured HTTPS port, and must not show ports `8282` or `5432`. Port `80` must return only an HTTPS redirect.

## Upgrade

For a 3.11.0-or-newer same-storage-profile upgrade, create and verify a coordinated snapshot first when the site has explicitly selected `OSCAR_BACKUP_MODE=single`. A disabled site must use its separately approved protection procedure or opt in through `upgrade` before invoking backup or restore. A pre-3.11.0 release does not have this CLI; use that release's supported backup/export procedure and retain the old system read-only until the separately qualified migration is complete. Extract the new release into a clean sibling directory; do not overlay it on the previous release because removed files would otherwise remain in the image build context. Copy only `.env`, `secrets/`, and `tls/` from the existing deployment into the clean release directory. If the deployment has a `.oscar-volume-adoption` receipt, copy that file too. Preserve `OSCAR_BACKUP_MODE`, the absolute active `OSCAR_ARCHIVE_DIR` and `OSCAR_BACKUP_DIR` values, and any existing absolute `OSCAR_WAL_ARCHIVE_DIR` compatibility binding; setup must never delete legacy roots or data while changing modes. Before starting services, use `docker compose config` to confirm the archive bind and the absence of a PostgreSQL WAL bind, then inspect the single mode and backup-root entries in `.env`. Compose attaches the exact external volumes `oscar_oscar_state` and `oscar_postgres_data`; setup owns their creation and validates deployment identity. Then run:

```powershell
.\oscar.bat upgrade
```

```sh
sudo bash oscar.sh upgrade
```

The command preserves existing settings and data while normalizing the required 3.11.0 managed
bindings: deployment identity, exact backup mode, absolute external storage roots, and the canonical backup-key
binding. A legacy deployment may also receive a generated backup key plus explicit volume/root
adoption metadata when the corresponding adoption options are supplied. After those guarded
normalizations it updates `OSCAR_VERSION`, validates Compose, prepares the versioned images,
stops the application tier, and runs the new image's restartable offline daily-file lifecycle-index
migration using the Daily File Journal root, journal directory, and calendar zone from the persisted
`/var/lib/oscar/config.json`. If that module is absent the narrow migration is skipped. An already
indexed journal creates no new work markers; an empty configured journal may receive its durable
metadata. Completion metadata is committed last, so a crash or validation failure may leave only
idempotent work markers plus an explicit restart marker. OSCAR remains stopped and the same
`upgrade` command is safe to retry. The deployment-scoped storage lock excludes backup, restore,
and archive-administration commands from the ordered stop through migration and the force-recreated,
health-checked restart. The workflow retains the fixed `oscar_state`
and `postgres_data` volumes plus the exact external archive and preserved legacy/backup roots. Recreating every
container is required even when an image and service model are unchanged: release-local secret,
certificate, and gateway-config bind sources and the Compose `working_dir`/`config_files` provenance
must point to the new clean release directory. It never removes volumes or external storage roots.
OSCAR health includes complete recursive module readiness, so a successful command cannot return
while lane RPM or camera initialization is still in flight.

Confirm the result with `oscar.bat status`
(Windows) or `sudo bash oscar.sh status` (Ubuntu).

Retire the previous extracted release directory only after all upgraded services are healthy and
`docker inspect` confirms that every container's release-local bind sources and Compose
`working_dir`/`config_files` labels refer to the new directory. The absolute archive and backup
roots intentionally continue to refer to the persistent paths copied in `.env`; a legacy-WAL
binding only preserves the location of existing compatibility data. Do not remove a
previous release's parent or sibling storage directory merely because its service containers were
replaced.

Setup creates both named volumes with an `OSCAR_DEPLOYMENT_ID` label and refuses missing, mixed, or
foreign ownership. Compose treats those exact names as external resources and never creates or
relabels them. For a pre-label deployment only, first verify from the old release and Docker
metadata that **both** `oscar_oscar_state` and `oscar_postgres_data` belong together. Then acknowledge
that one-time adoption with `oscar.bat upgrade -AdoptLegacyVolumes` or
`sudo bash oscar.sh upgrade --adopt-legacy-volumes`. Setup records both immutable Docker volume
creation times and the deployment ID in `.oscar-volume-adoption`; later mismatches fail closed.
Never use this switch to combine volumes from different installations, and preserve the receipt on
every subsequent clean-directory upgrade.

Storage-root ownership is a separate gate. New roots receive an administrator-owned
`.oscar-storage-root` version-1 identity bound to `OSCAR_DEPLOYMENT_ID` and the exact root kind. A
nonempty pre-3.11.0 active archive or backup root without that marker requires a one-time, reviewed
`oscar.bat upgrade -AdoptLegacyStorageRoots` or
`sudo bash oscar.sh upgrade --adopt-legacy-storage-roots`. The marker records the adoption time and
actor. Setup rejects a foreign UUID, swapped kind, unsafe marker, or unacknowledged nonempty root
before claiming any path. Backups exclude these host-local markers, and restore preserves and
revalidates the target markers instead of accepting identities from backup media. A retired
legacy-WAL tree is neither claimed nor mutated by current setup.

The OSCAR application libraries and exported Viewer are part of the `oscar:<version>` image. A restart does not rebuild that image. To test OSCAR 3.11.0 from a connected release artifact, prepare the clean release directory as described above. Use `init` and fresh state for the complete 3.11.0 storage profile; use `upgrade` only when intentionally retaining the existing storage/configuration profile. Confirm that `docker compose images` reports `oscar:3.11.0` before accepting the test result.

Release image tags are immutable once published. Connected `init` and `upgrade` rebuild both local image contexts (`oscar:3.11.0` and `oscar-postgis:3.11.0`) before recreating services, even when those tags already exist, so a pre-release same-tag iteration cannot silently retain an older application or restore helper. On Ubuntu this is equivalent to `OSCAR_VERSION=3.11.0 docker compose build oscar postgres`. The Windows setup performs two bounded `docker build` operations, including `docker build --platform linux/amd64 --build-arg OSCAR_VERSION=3.11.0 --tag oscar-postgis:3.11.0 --file postgis/Dockerfile postgis`; this avoids Docker Compose 5.6's in-tree Dockerfile entitlement regression without granting wildcard filesystem access. The regression platform check requires each packaged helper to match its deployed image byte-for-byte. Never replace a published `oscar:3.11.0` image with different contents.

The default configuration for a new installation is labeled `OSCAR 3.11.0`. An upgrade preserves `/var/lib/oscar/config.json`, including a customized deployment name, so the Admin UI may continue to display the prior or site-specific label. Do not overwrite that value merely to display a version number. Use `OSCAR_VERSION` in `.env` and `docker compose images` to verify the running release. The OSCAR image also stamps that value into the OCI `org.opencontainers.image.version` label; inspect it on PowerShell or a POSIX shell with `docker image inspect oscar:3.11.0 --format '{{json .Config.Labels}}'` and require the label value `3.11.0` before accepting the image.

On Windows, setup and storage administration stream every bounded shell body and direct `psql`
statement into the one-shot container over UTF-8 standard input. The direct `docker run` adapter owns
the required `--interactive` attachment, while Compose execution remains non-TTY with `exec -T`.
Setup relays storage-command parameters to its child PowerShell process through a bounded,
allowlisted Base64/JSON environment envelope and a fixed encoded command; operator text is never
forwarded as native executable arguments. These rules preserve multiline checks, SQL, paths, and
quoted values exactly under Windows PowerShell 5.1 native argument handling. A failed initialization
check leaves the receipt in `INITIALIZING`; correct the reported problem and rerun `oscar.bat init`
from the same release and protected runtime state rather than deleting the volumes.

### 3.11.0 storage migration boundary

OSCAR 3.11.0 changes the default database module, write path, daily-file source capture, media-retention format, and PostgreSQL initialization. `upgrade` deliberately does not overwrite the saved module configuration or recreate the PostgreSQL cluster, so an upgraded pre-3.11.0 system does not automatically gain the complete 3.11.0 storage profile or data checksums.

Initialize the current test systems and new production systems with a fresh 3.11.0 database/configuration. If existing production history must be retained, keep the old system read-only after a verified backup and use a separately designed and tested migration. Do not delete production volumes merely to make the new module start. Follow the parity, restore-drill, and bounded hot-deletion validation in [`../../docs/STORAGE_OPERATIONS.md`](../../docs/STORAGE_OPERATIONS.md).

The OSCAR container keeps `/var/lib/oscar/config.json` readable and writable only by the OSCAR runtime user (`0600`) and repairs older read-only copies during startup. After importing a lane CSV, wait for every lane to appear under **Sensors**, select the global **Save** action, restart OSCAR, and confirm that the same lanes reload. Historical systems in PostgreSQL are not proof that runtime sensor modules were saved; an empty **Sensors** tree after restart indicates that the module configuration was not persisted.

On Windows, OSCAR grants the local `docker-users` group read-only access to the protected `secrets` and `tls` directories so Docker Desktop can mount them. This is required when setup is elevated with a different administrator account than the signed-in account running Docker Desktop. The group receives temporary write access only while `init` generates or imports the certificate.

## Storage administration

The release implements an opt-in one-current-snapshot backup/verification/restore workflow,
retention holds, and archive status, integrity, portable export, and restartable tokenized deletion
commands. `backup-prune` is retired and performs no deletion. The full procedures are in:

- [`../../docs/STORAGE_ARCHITECTURE.md`](../../docs/STORAGE_ARCHITECTURE.md)
- [`../../docs/DATA_LIFECYCLE.md`](../../docs/DATA_LIFECYCLE.md)
- [`../../docs/ARCHIVE_FORMAT.md`](../../docs/ARCHIVE_FORMAT.md)
- [`../../docs/BACKUP_RESTORE.md`](../../docs/BACKUP_RESTORE.md)
- [`../../docs/STORAGE_OPERATIONS.md`](../../docs/STORAGE_OPERATIONS.md)

The hold list and creation result include `resolution_mode`. A
`COLD_RANGE_CONSERVATIVE` observation hold protects matching generation ranges but is not proof that
the exact ID exists in sparse Parquet; verify the event or use an exact generation hold for legal
certainty. `LEGACY_UNKNOWN` is a protective migration-only label for pre-3.11.0 observation holds
whose exact-vs-range provenance cannot be reconstructed; the CLI never creates it. Active
observation and generation holds are enforced inside the same transaction as
hot/cold logical removal and tombstone creation. Single removal fails on a hold; filtered bulk
removal skips protected rows and counts only rows actually removed.

The same files are under `documentation/` in the packaged release. `backup` verifies the newly
created schema-v2 snapshot automatically and authenticates its checksum inventory with the separately stored
backup key. It rejects unsafe tar members and any v2 `wal-archive.tar.gz`, atomically marks the recovery point `VERIFIED`, and,
while OSCAR remains stopped, confirms only exact published daily-file/segment sets captured by the
accepted authenticated snapshot. After confirmation, an atomic HMAC-authenticated `CURRENT`
replacement commits the one logical snapshot; only then can the previous non-current fully accepted
schema-v2 snapshot be cleaned. Confirmation failure leaves the old pointer authoritative. PostgreSQL remains
online for `pg_basebackup --wal-method=stream`; there is no cumulative WAL snapshot.
`backup-verify` runs `pg_verifybackup` in a dependency-free utility container, so the
live database and its catalog receipt are not recovery dependencies. Use `backup-verify` to recheck
it before every upgrade or retention reduction. Schema-v1 snapshots remain explicitly verifiable
and restorable and require their historical WAL payload for authentication; restore ignores that
external payload because streamed `postgres/pg_wal` is sufficient. OSCAR does not provide PITR.
One logical snapshot is the steady state, not the peak capacity requirement. A replacement keeps
the old snapshot while the complete new candidate is built, verified, accepted, and committed
through `CURRENT`, so size the backup root for both. The next locked storage command uses the
authenticated pointer to reconcile any non-current snapshot or private staging debris left by a
crash. Cleanup removes only candidates that independently pass complete schema-v2 core and
acceptance verification; schema-v1, failed, partial, unauthenticated, unaccepted, and incomplete
deletion candidates are preserved with warnings. If no `CURRENT` exists, one uniquely accepted
schema-v2 candidate is adopted by reconstructing authenticated `CURRENT`; multiple accepted
candidates are preserved and stop for operator review.
All storage-administration commands share one nonblocking, crash-released deployment lock; a
concurrent invocation fails rather than racing backup/archive state. The lock is keyed by
`OSCAR_DEPLOYMENT_ID` in `/run/lock/oscar-storage` on Ubuntu or
`%ProgramData%\OSCAR\StorageLocks` on Windows, so it
continues to coordinate old and new extracted releases. Live commands validate every root identity
and both named-volume ownership identities; only offline-capable `backup-verify` is exempt from
those live dependencies. Verification is still an acceptance mutation: it publishes/replaces
`VERIFIED` and normalizes backup permissions, and may update the live catalog only after proving
volume ownership.
Fresh deployments default to backup mode `disabled`; backup, verification, restore, and the retired
prune command fail with opt-in guidance until setup changes the mode to `single`. For a fresh
database, the standard data lifecycle explicitly selects `PARQUET_PRIMARY`: all 22 allowlisted
operational and evidentiary outputs (`gammaCounts`, `gammaThreshold`,
`neutronCounts`, `setupGamma`, `setupNeutron`, `speed`, `backgroundReport`, `foregroundReport`,
`status`, `emlContextual`, `emlScanContextual`, `emlAnalysis`, `dailyFile`, `connectionStatus`,
`occupancyStatus`, `tamper`, `occupancy`, `adjudication`, `report`, `siteStatistics`,
`nationalSummary`, `vehicleOcr`) commit first to LOGGED, UTC-aligned
30-minute PostgreSQL staging children (with startup route reconciliation, retroactive Parquet
migration, and `VACUUM (FULL, ANALYZE) ONLY obs` compaction for any legacy unarchived parent-table rows). A one-minute worker makes a closed child eligible after a five-minute safety delay; a
detector timestamp more than five minutes ahead of the database receipt clock is rejected. After
manifest-last activation, object re-hash, exact row/UUID parity, and population of `oscar_obs_latest`,
`oscar_archive_schema` summary counters, and `oscar_event_locator`, OSCAR transactionally detaches
and drops the complete child, retiring at most eight children per cycle. There is no three-day raw
PostgreSQL overlap in this mode. The normal staging budget is at most 60 minutes, but this is an
operational SLO rather than a hard deadline during backlog, failure, lock contention, or downtime.
Static singleton configuration streams (`sensorLocation`, `adjudicationCodes`, `siteInfo`) remain in
PostgreSQL `ONLY oscar.obs`, adjudications and re-adjudications of archived `occupancy` rows are
recorded in `oscar_obs_overlay` + `oscar_obs_latest`, and transient camera/HLS/statistics
commands (`cmd_commands` / `cmd_status` > 24h, excluding `%adjudicate%`) are pruned hourly;
fresh primary staging children omit generic payload and mutable-event indexes. After safe stage
retirement, Parquet and the independently published daily files are the durable long-term
representations; the compact staging-owner ledger is removed with its child.
Parquet is the primary cold tier, not a backup. Cold archive deletion always requires a reviewed
`archive dry-run` plan and its one-time token.

Certificate renewal and a site-specific migration of retained pre-3.11.0 history remain controlled administrator operations and must be validated before an upgrade is declared production-ready.

## Compatibility scripts

`setup.*`, `launch-all.*`, and `stop-all.*` remain as compatibility wrappers. New documentation and automation should use only `oscar.bat` or `oscar.sh`.

Offline map layers are not currently required. The CLI retains an explicit MBTiles import TODO for a future milestone.

## Local timezone and daily files

Initialization prompts for an IANA timezone such as `America/Chicago`, `America/New_York`, or `UTC`. Use `--timezone America/Chicago` on Linux/macOS or `-Timezone America/Chicago` on Windows to specify it on the command line. Windows timezone display names such as `Central Standard Time` are not accepted. Setup validates the name against the OSCAR image's timezone database.

The setting is saved as `OSCAR_TIMEZONE` in `.env`. A repeated initialization preserves the existing timezone by default; new deployments and non-interactive initialization without a timezone default to `UTC`.

OSCAR uses this timezone as its Java default, including dailyfile local timestamps and local-midnight file rollover. Daylight-saving transitions follow the selected region. Dailyfile UTC timestamps remain UTC. Other application features using the Java default timezone also follow this setting.

For an existing deployment, set `OSCAR_TIMEZONE=America/Chicago` in `.env` and run `docker compose up -d --no-build --pull never oscar` from the release directory to recreate the application container. A plain container restart does not apply changed environment variables. The release image must include the updated entrypoint.

Rapiscan and Aspect both write `dailyfiles/<fileId>_<YYYY-MM-DD>.csv`, using the final segment of the sensor UID as the file ID. Rows contain device-specific message values followed by local and UTC times in `HH-mm-ss.SSS` format, with CRLF line endings and no header. Their SWE output names are both `dailyFile` (label `Daily File`), with `samplingTime` as the first field. Their second field is `rpmMessage` (label `RPM Message`) for both drivers. These datastream messages contain the device payload; the appended local and UTC columns belong to the stored CSV files.

The `rpmMessage` field replaces `rapiscanMessage` and `aspectMessage`. External consumers selecting either old JSON property must use `rpmMessage` for new observations and retain support for the old names when reading historical data. On driver registration, OSH creates a new datastream version if the prior schema has observations; an empty datastream is updated in place. Consumers caching datastream IDs should rediscover the current `dailyFile` stream after upgrading. Stored CSV files have no field-name headers and are unaffected. The historical `test/staging-test-db.sql` snapshot retains its original field names.
