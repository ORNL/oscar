# OSCAR Change Log
All notable changes to this project will be documented in this file. 

## 3.11.10 (Amber) 2026-11-23

OSCAR `3.11.10` (Amber) is the current general-availability release on the `3.11` line for continuous 24/7 operation across up to 50 concurrent radiation portal monitor (RPM) and RTSP camera lanes on **Ubuntu Server 24.04 x86-64** and **Windows 11 x86-64** (Docker Desktop + WSL 2). Building directly on `3.11.9` (which added the **Standalone Cross-Platform Bare-Metal Ubuntu 24.04 Offline Autoinstall USB Creator (`GUI + TUI + CLI`)** with **Turnkey PBKDF2 Web `admin` Password & `lanes.csv` Pre-Configuration**), `3.11.10` hardens **Zero-Login GUI System Updates** across attached USB NVMe backup drives, minimal Ubuntu 24.04 autoinstall hosts, and Windows 11 `SYSTEM` Scheduled Tasks, documents the **Recommended `1–2 TB` External USB 3.2 Gen 2 NVMe SSD (`OSCAR_BACKUP`) Bill of Materials**, and standardizes the **`14+` Character Minimum Password Length** across runtime validation, `/users`, `/login/password-change`, and `reset-admin-password`.

### Highlights in `3.11.10`

- **Attached `OSCAR_BACKUP` USB NVMe Pre-Upgrade Sync Precedence & Hardware Sizing Guidance (`oscar-update.{sh,ps1}`, `DEPLOYMENT.md`, `CONTINUAL_AND_USB_BACKUP_GUIDE.md`, `UBUNTU_FIELD_SETUP_GUIDE.md`):**
  - Updates `oscar-update.sh` and `oscar-update.ps1` so whenever a configured `OSCAR_BACKUP` external USB NVMe drive is attached, GUI and CLI pre-upgrade backups (`--backup-first`) **always run zero-downtime online incremental `usb-backup sync`** (`~5–20 s`, `0.0 s` portal downtime) instead of falling back to cold monolithic `oscar-state.tar.gz` snapshots (`OSCAR_BACKUP_MODE=single`).
  - Extends `oscar-update-agent.service` `TimeoutStartSec` to `7200` for fallback cold snapshots and documents a dedicated `1–2 TB` External USB 3.2 Gen 2 NVMe SSD (`OSCAR_BACKUP` in `continual` mode) as a standard Bill-of-Materials item for physical deployments.
- **Minimal Ubuntu 24.04 `python3` `zipfile` Fallback & Windows 11 `SYSTEM` Administrator-SID ACL Recognition (`oscar-update.sh`, `oscar-storage.ps1`, `oscar-update.ps1`):**
  - Adds a secure `python3` `zipfile` extraction fallback (rejecting symlinks and path traversal while preserving executable bits) when `unzip` is absent on minimal Ubuntu Server 24.04 autoinstall hosts.
  - Updates `Assert-ProtectedAdministratorAcl` in `oscar-storage.ps1` so `OSCAR-UpdateAgent` running as `NT AUTHORITY\SYSTEM` (`S-1-5-18`) recognizes storage directories owned by local `Administrators` (`S-1-5-32-544`) group members who initialized the host, and preserves terminal `COMPLETED` / `ROLLED_BACK` / `FAILED` status across `install-agent` refreshes.
- **Unified `14+` Character Minimum Password Policy (`OscarIdentityStore`, `BasicSessionAuthenticator`, `UsersAccessManager.tsx`, `oscar-setup.{sh,ps1}`):**
  - Standardizes local PBKDF2 password validation, `/users` forms, `/login/enroll` & `/login/password-change` pages, `reset-admin-password` host CLIs, and all four localized operator manuals (`en`, `es`, `fr`, `el`) to `14+` characters to match `oscar init` without affecting existing accounts or 19-character temporary onboarding passwords.
- **Immediate Operational View (`Scoped View`) Refresh on Training Sandbox Track Transitions (`Node.ts`, `DataSourceContext.tsx`, `Navbar.tsx`, `TrainingCoachDock.tsx`, `TrainingSandboxManager.java`):**
  - Invalidates and re-fetches the `OperationalViewCatalog` whenever sandbox tracks switch (for example, **Operator Track → Supervisor Track** adding `south-gate` on `DemoLane02`, or **Administrator Track** lane edits) or when the Scoped View dropdown opens, surfacing `south-gate` immediately without requiring a browser refresh.

### Release artifacts — which file to download (`v3.11.10`)

| Release Asset | Target Audience & Use Case |
| :--- | :--- |
| `oscar-3.11.10.zip` (+ `.sha256`) | **Connected Ubuntu Server 24.04 or Windows 11 installations, CLI upgrades, and Zero-Login GUI System Updates.** Includes Docker Compose definitions (`compose.yaml`, `compose.rpm-proxy.yaml`, `compose.sandbox.yaml`, `compose.octelium.yaml`), Linux/Windows administration CLIs (`oscar.sh` / `oscar.bat` including `update`, `rpm-proxy`, `reset-admin-password`, `sandbox`, and `remote-access`), `configure-ubuntu-host.sh`, `configure-windows-host.ps1`, `ubuntu/` autoinstall creator & templates, application build context, all Markdown documentation, and all four localized PDF operator manuals. |
| `oscar-3.11.10-autoinstall-usb-creator.zip` (+ `.sha256`) | **Standalone Windows 11 & Ubuntu Bare-Metal Autoinstall USB Creator (`~53 KiB`, GUI + TUI + CLI).** Download alongside `oscar-3.11.10-ubuntu-x86_64-offline-full.zip` and `ubuntu-24.04.x-live-server-amd64.iso` to build a single-stick UEFI Secure-Boot Ubuntu 24.04 + air-gapped OSCAR installer USB drive (with optional PBKDF2 web `admin` password + `lanes.csv` pre-configuration and unattended first-boot setup) without extracting the offline bundle first. |
| `oscar-3.11.10-ubuntu-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Ubuntu 24.04 LTS installations (or slow hotel Wi-Fi staging).** Bundles official Ubuntu 24.04 Docker Engine + Compose v2 + `chrony`/`ethtool`/`nmap`/`arp-scan` `.deb` packages, pre-built container images (`oscar:3.11.10`, `oscar-postgis:3.11.10`, `oscar-rpm-proxy:3.11.10`, `nginx/nginx-unprivileged:1.30.7-alpine`), `oscar.sh update`, `rpm-proxy`, `reset-admin-password` & `sandbox`, bare-metal `create-autoinstall-usb` + `oscar-firstboot-wizard.sh`, and all Markdown/PDF documentation. |
| `oscar-3.11.10-windows-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations where Docker Desktop or WSL 2 is not yet installed.** Bundles pinned Docker Desktop `4.87.0` and WSL `2.7.3` installers, pre-built container images (`oscar:3.11.10`, `oscar-postgis:3.11.10`, `oscar-rpm-proxy:3.11.10`, `nginx/nginx-unprivileged:1.30.7-alpine`), administration scripts, and all Markdown/PDF documentation. |
| `oscar-3.11.10-windows-x86_64-offline-images.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations or upgrades where compatible Docker Desktop and WSL 2 are already running.** Contains the pre-built container image archive, administration scripts, and documentation without the Windows prerequisite installers. |

## 3.11.9 (Amber) 2026-11-23

OSCAR `3.11.9` (Amber) is the current general-availability release on the `3.11` line for continuous 24/7 operation across up to 50 concurrent radiation portal monitor (RPM) and RTSP camera lanes on **Ubuntu Server 24.04 x86-64** and **Windows 11 x86-64** (Docker Desktop + WSL 2). Building directly on `3.11.8` (which introduced the **Zero-Login GitHub & Offline Bundle GUI System Updater**, **13-Lab Hands-On Training Sandbox Verification & Loopback `WebRelay-Quad`**, **Zero Unused `<link rel="preload">` Warnings**, and **29 Human-Paced Workflow Video Guides**), `3.11.9` adds the **Standalone Cross-Platform Bare-Metal Ubuntu 24.04 Offline Autoinstall USB Creator (`oscar-3.11.9-autoinstall-usb-creator.zip`, GUI + TUI + CLI for Windows 11 and Ubuntu)** and fixes **Windows 11 `oscar.bat status` (`Get-ConfiguredEnvValue` + PowerShell AST Verification Gate)**.

### Highlights in `3.11.9`

- **Standalone Cross-Platform Bare-Metal Ubuntu 24.04 Offline Autoinstall USB Creator (`oscar-3.11.9-autoinstall-usb-creator.zip`, `create-autoinstall-usb.{bat,ps1,sh}`, `tools/package-autoinstall-usb-creator.sh`):**
  - Publishes a compact (`~49 KiB`) standalone release archive directly on GitHub Releases so administrators on any **Windows 11** or **Ubuntu** laptop can build a UEFI Secure-Boot Ubuntu Server 24.04 LTS + air-gapped OSCAR autoinstall USB drive directly from `ubuntu-24.04.x-live-server-amd64.iso` and `oscar-3.11.9-ubuntu-x86_64-offline-full.zip` without unpacking the `1.1 GiB` offline bundle first.
  - Supports **three complete execution modes on both platforms**:
    1. **Desktop GUI:** Double-clicking `create-autoinstall-usb.bat` on Windows 11 auto-elevates via UAC and opens a native DPI-aware Windows Forms GUI (USB drive selector with `Refresh Drives`, file/folder pickers, hostname/admin user, native C# `$6$` SHA-512 password hashing matching `openssl passwd -6`, `--require-sudo-password`, optional 12+ character LUKS2 full-disk encryption, SSH public key + SSH-keys-only policy, `ERASE-USB` safety unlock, and live progress log); on Ubuntu Desktop, `sudo bash create-autoinstall-usb.sh --gui` launches native GTK `zenity` dialogs (with `pkexec` elevation and automatic `whiptail` TUI fallback).
    2. **Interactive Terminal Wizard (TUI):** `create-autoinstall-usb.bat -Tui` on Windows 11 and `sudo bash create-autoinstall-usb.sh` (`--tui`) on Ubuntu step through drive selection, auto-detected ISO and `offline-full.zip` paths, server hostname, admin username, hidden password entry + `$6$` SHA-512 hashing, `sudo` password policy, LUKS2 full-disk encryption, SSH key policy, optional seed directory, and `ERASE-USB` confirmation.
    3. **Non-Interactive Scriptable CLI:** Full parity across Windows (`-IsoPath`, `-OfflineBundlePath`, `-DiskNumber`, `-Hostname`, `-Username`, `-PasswordFile` / `-PasswordHash`, `-LuksPassphraseFile`, `-RequireSudoPassword`, `-SshKeyFile`, `-SshKeysOnly`, `-SeedDirectory`, `-ConfirmToken ERASE-USB`) and Ubuntu (`--iso`, `--offline-bundle`, `--device` / `--output-image`, `--hostname`, `--username`, `--password-file` / `--password-hash`, `--luks-passphrase-file`, `--require-sudo-password`, `--ssh-key-file`, `--ssh-keys-only`, `--seed-dir`, `--confirm ERASE-USB`).
- **Bundled `1080p` `30 fps` Workflow Video Guides `#30` & `#31` (`248` 4-Language Subtitle Files) and Operator Manual Screenshots (`54` & `55`):**
  - Adds Guide **`#30`** (`30-zero-login-github-system-update.mp4`, `38s`) and Guide **`#31`** (`31-bare-metal-autoinstall-usb-creator.mp4`, `65s`) across `en`, `es`, `fr`, and `el`, plus annotated Operator Manual screenshots `54-zero-login-github-system-update.png` and `55-bare-metal-autoinstall-usb-creator.png` across all four localized Administrator & Operator Manuals.
- **Windows 11 `oscar.bat status` (`Invoke-Compose`) Fix & PowerShell AST Gate (`oscar-setup.ps1`, `test-storage-powershell.ps1`):**
  - Resolves `OSCAR_ARCHIVE_DIR` inside `Invoke-Compose` via `Get-ConfiguredEnvValue` so `.\oscar.bat status`, `start`, `stop`, `restart`, and `logs` execute cleanly on Windows 11, backed by a PowerShell AST parser verification gate in `tools/test-storage-powershell.ps1`.

### Release artifacts — which file to download (`v3.11.9`)

| Release Asset | Target Audience & Use Case |
| :--- | :--- |
| `oscar-3.11.9.zip` (+ `.sha256`) | **Connected Ubuntu Server 24.04 or Windows 11 installations, CLI upgrades, and Zero-Login GUI System Updates.** Includes Docker Compose definitions (`compose.yaml`, `compose.rpm-proxy.yaml`, `compose.sandbox.yaml`, `compose.octelium.yaml`), Linux/Windows administration CLIs (`oscar.sh` / `oscar.bat` including `update`, `rpm-proxy`, `reset-admin-password`, `sandbox`, and `remote-access`), `configure-ubuntu-host.sh`, `configure-windows-host.ps1`, `ubuntu/` autoinstall creator & templates, application build context, all Markdown documentation, and all four localized PDF operator manuals. |
| `oscar-3.11.9-autoinstall-usb-creator.zip` (+ `.sha256`) | **Standalone Windows 11 & Ubuntu Bare-Metal Autoinstall USB Creator (`~49 KiB`, GUI + TUI + CLI).** Download alongside `oscar-3.11.9-ubuntu-x86_64-offline-full.zip` and `ubuntu-24.04.x-live-server-amd64.iso` to build a single-stick UEFI Secure-Boot Ubuntu 24.04 + air-gapped OSCAR installer USB drive without extracting the offline bundle first. |
| `oscar-3.11.9-ubuntu-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Ubuntu 24.04 LTS installations (or slow hotel Wi-Fi staging).** Bundles official Ubuntu 24.04 Docker Engine + Compose v2 + `chrony`/`ethtool`/`nmap`/`arp-scan` `.deb` packages, pre-built container images (`oscar:3.11.9`, `oscar-postgis:3.11.9`, `oscar-rpm-proxy:3.11.9`, `nginx/nginx-unprivileged:1.30.7-alpine`), `oscar.sh update`, `rpm-proxy`, `reset-admin-password` & `sandbox`, bare-metal `create-autoinstall-usb` + `oscar-firstboot-wizard.sh`, and all Markdown/PDF documentation. |
| `oscar-3.11.9-windows-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations where Docker Desktop or WSL 2 is not yet installed.** Bundles pinned Docker Desktop `4.87.0` and WSL `2.7.3` installers, pre-built container images (`oscar:3.11.9`, `oscar-postgis:3.11.9`, `oscar-rpm-proxy:3.11.9`, `nginx/nginx-unprivileged:1.30.7-alpine`), administration scripts, and all Markdown/PDF documentation. |
| `oscar-3.11.9-windows-x86_64-offline-images.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations or upgrades where compatible Docker Desktop and WSL 2 are already running.** Contains the pre-built container image archive, administration scripts, and documentation without the Windows prerequisite installers. |

## 3.11.8 (Amber) 2026-11-23

OSCAR `3.11.8` (Amber) is the current general-availability release on the `3.11` line for continuous 24/7 operation across up to 50 concurrent radiation portal monitor (RPM) and RTSP camera lanes on **Ubuntu Server 24.04 x86-64** and **Windows 11 x86-64** (Docker Desktop + WSL 2). Incorporating everything introduced in `3.11.7` (including the **Optional Side-by-Side Central Alarm Station Rapiscan RPM Edge Proxy (`oscar-rpm-proxy`)** with **`<= 4.0 s` Disconnect Propagation**, **Platform-Wide Icon Spotlights**, **4-Language Video Subtitles**, **`EventTable` `page+1` Prefetch**, **Detector Driver Replay Suites**, and **Windows `oscar-setup.ps1` Fix**), `3.11.8` delivers **Full End-to-End Visual & Backend Verification Across All 13 Hands-On Training Sandbox Labs** (including destination-aware `/event-log` & `/health` auto-navigation, live occupancy transit progress, default `Adjudication Code` column visibility for `Code 9999` / `Code 9998`, a pure-Java loopback `WebRelay-Quad` server `127.0.0.1:10180` for Lab `3.5`, and container `0600` `config.json` permission seeding), **Zero Unused `<link rel="preload">` Browser Console Warnings**, **All 29 Workflow Video Guides Re-Recorded at First-Time Human Learning Speed (`232` 4-Language Subtitle Files)**, and **Validated Offline Release Packaging for `oscar-rpm-proxy`**.

### Highlights in `3.11.8`

- **Zero-Login GitHub & Offline Bundle GUI System Updater (`SystemUpdateServlet`, `SystemUpdateReleaseChecker`, `SystemUpdateHostBridge`, `oscar-update.{sh,ps1}`, `SystemUpdateCard.tsx`):**
  - Enables OSCAR Administrators to check for, SHA-256 verify, and install the latest official `ORNL/oscar` release directly from **`OSCAR Viewer -> Users & Access (`/users?tab=update`) -> System Update`** (also linked from **`Help (?)`**) or via `sudo bash oscar.sh update check|apply` (Ubuntu 24.04) and `.\oscar.bat update check|apply` (Windows 11) **with zero GitHub login, zero OAuth account, and zero Personal Access Token**.
  - Resolves public releases anonymously via `/ORNL/oscar/releases/latest` redirect discovery, `/releases.atom`, and `.zip.sha256` verification (immune to `api.github.com`'s 60 requests/hr unauthenticated NAT rate limit), supports streaming **Offline / Air-Gapped `.zip` Upload** (`POST /sensorhub/oscar/system-update/upload-bundle` up to `2 GiB`), extracts into a clean sibling release directory while preserving `.env`, `secrets/`, `tls/`, and `.oscar-volume-adoption` without exposing `docker.sock` inside containers, tracks live stage-by-stage progress across container restarts (`RECONNECTING` -> `COMPLETED`), and **automatically rolls back** to the untouched prior release directory if upgrade or HTTPS `/healthz` readiness fails.
- **End-to-End Hands-On Training Sandbox (`:8444`) Action & Loopback `WebRelay-Quad` Verification (`SandboxWebRelayLoopbackServer`, `TrainingSandboxManager`, `entrypoint.sh`, `TrainingCoachDock`, `EventTable`):**
  - Adds a pure-Java loopback ControlByWeb `WebRelay-Quad` HTTP/XML server (`127.0.0.1:10180` primary + `127.0.0.1:10181` ancillary, active strictly when `OSCAR_SANDBOX_MODE=true`) serving `/stateFull.xml` and `/state.xml` with hardware-timed pulse simulation (`relay1State..relay4State=0|1|2`), paired with 1-click **`Stage DemoLane01 + Loopback WebRelay`** and live `webRelayOnlineCount >= 1` auto-verification in Lab `3.5` (`adm-5`).
  - Auto-navigates to `lab.route` on Lab/Track/`Next Lab` selection, opens **Events (`/event-log`)** with live occupancy transit progress and default **`Adjudication Code`** column visibility (`Code 9999: EML Non-Threat`, `Code 9998: Extended Occupancy Gamma Alarm`) when injecting `norm_eml`, `extended_occupancy`, or `clean_pass`, opens **Status of Health (`/health`)** on fault/tamper/clear/`stage_webrelay_demo`, fixes `DemoLane02` multi-category supervisor seeding in `TrainingSandboxManager`, fixes `chmod 0600 /var/lib/oscar/config.json` prior to `SandboxAuthConfigSeeder` in `docker/oscar/entrypoint.sh`, and downgrades normal client HTTP EOF disconnects in `BasicSessionAuthenticator` to `DEBUG`.
- **Zero Unused `<link rel="preload">` Browser Console Warnings (`Navbar.tsx`):**
  - Sets `prefetch={false}` on cross-route navigation `<Link>` elements in `Navbar.tsx` so Next.js static export never injects unused cross-page stylesheet `<link rel="preload" as="style">` tags into `<head>`.
- **Human-Paced `1080p` `30 fps` CFR Workflow Video Guides (`#01`–`#29` + `232` `en`/`es`/`fr`/`el` Subtitles):**
  - Re-recorded all 29 bundled how-to guides (`ORNL/oscar-video-guides`) with smooth cursor trajectories, pre-click sky-blue target focus rings (`580 ms` pre-click dwell + `780 ms` post-click settle), natural typing cadence, `<= 115 WPM` caption reading speed, and `>= 4.5 s` steady screen holds after every UI/CLI transition across all 4 subtitle languages.
- **Offline Release Bundle Validation for `oscar-rpm-proxy` (`.github/workflows/release.yml`, `.gitignore`, `.dockerignore`):**
  - Updates `.github/workflows/release.yml` offline bundle structural and `offline-images.tar` manifest checks to validate `compose.rpm-proxy.yaml`, `oscar-rpm-proxy.{sh,ps1}`, `documentation/RPM_EDGE_PROXY_GUIDE.md`, `docker/rpm-proxy/Dockerfile`, and `oscar-rpm-proxy:3.11.8`, while excluding `__pycache__/*.pyc` from source and Docker contexts.

### Release artifacts — which file to download (`v3.11.8`)

| Release Asset | Target Audience & Use Case |
| :--- | :--- |
| `oscar-3.11.8.zip` (+ `.sha256`) | **Connected Ubuntu Server 24.04 or Windows 11 installations and upgrades.** Includes Docker Compose definitions (`compose.yaml`, `compose.rpm-proxy.yaml`, `compose.sandbox.yaml`, `compose.octelium.yaml`), Linux/Windows administration CLIs (`oscar.sh` / `oscar.bat` including `rpm-proxy`, `reset-admin-password`, `sandbox`, and `remote-access`), `configure-ubuntu-host.sh`, `configure-windows-host.ps1`, declarative `ubuntu/` staging templates, application build context, all Markdown documentation, and all four localized PDF operator manuals. |
| `oscar-3.11.8-ubuntu-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Ubuntu 24.04 LTS installations (or slow hotel Wi-Fi staging).** Bundles official Ubuntu 24.04 Docker Engine + Compose v2 + `chrony`/`ethtool`/`nmap`/`arp-scan` `.deb` packages, pre-built container images (`oscar:3.11.8`, `oscar-postgis:3.11.8`, `oscar-rpm-proxy:3.11.8`, `nginx/nginx-unprivileged:1.30.7-alpine`), `oscar.sh rpm-proxy`, `reset-admin-password` & `sandbox`, bare-metal `create-autoinstall-usb` + `oscar-firstboot-wizard.sh`, and all Markdown/PDF documentation. |
| `oscar-3.11.8-windows-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations where Docker Desktop or WSL 2 is not yet installed.** Bundles pinned Docker Desktop `4.87.0` and WSL `2.7.3` installers, pre-built container images (`oscar:3.11.8`, `oscar-postgis:3.11.8`, `oscar-rpm-proxy:3.11.8`, `nginx/nginx-unprivileged:1.30.7-alpine`), administration scripts, and all Markdown/PDF documentation. |
| `oscar-3.11.8-windows-x86_64-offline-images.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations or upgrades where compatible Docker Desktop and WSL 2 are already running.** Contains the pre-built container image archive, administration scripts, and documentation without the Windows prerequisite installers. |

## 3.11.7 (Amber) 2026-11-22

OSCAR `3.11.7` (Amber) is the current general-availability maintenance and field-integration release on the `3.11` line for continuous 24/7 operation across up to 50 concurrent radiation portal monitor (RPM) and RTSP camera lanes on **Ubuntu Server 24.04 x86-64** and **Windows 11 x86-64** (Docker Desktop + WSL 2). It adds the **Optional Side-by-Side Central Alarm Station (CAS) Rapiscan RPM Real-Time Edge Fan-Out Proxy (`oscar-rpm-proxy`)** with **`<= 4.0 s` Upstream-Gated Disconnect Propagation**, **Platform-Wide Interactive Icon Spotlights (`Highlight [Icon]`) & Visual Symbol Introductions**, **4-Language (`en`, `es`, `fr`, `el`) WebVTT/SRT Subtitles Across All 29 Bundled Video Guides**, **Sub-`150 ms` Dashboard Next-Page (`page + 1`) Pagination Prefetching**, **Wire-Protocol Replay & Lifecycle Test Suites for Aspect, RS-350, Kromek D3S, and Kromek D5 Drivers**, **Windows 11 `oscar-setup.ps1` `Get-EnvironmentValue` Status Fix**, and **Node 24 GitHub Actions (`@v5` / `action-gh-release@v3`)**.

### Highlights in `3.11.7`

- **Optional Side-by-Side CAS Rapiscan RPM Real-Time Edge Proxy (`compose.rpm-proxy.yaml`, `oscar-rpm-proxy.{sh,ps1}`, `docker/rpm-proxy/`, `docs/RPM_EDGE_PROXY_GUIDE.md`):**
  - Integrates an opt-in, isolated Docker Compose project (`--project-name oscar-rpm-proxy`, `oscar-rpm-proxy:3.11.7` preloaded in `offline-images.tar`) that maintains one upstream TCP connection per Rapiscan RPM (`1–50+` lanes) and fans out `\n`-framed real-time `1 Hz` telemetry simultaneously to an existing Central Alarm Station and OSCAR (`50` lanes × `2` consumers = `100` sockets benchmarked at `~40 ms` for `200` frames, `< 0.5 ms` per-frame latency, `< 2%` of 1 vCPU). Running `oscar restart` or `oscar upgrade` never interrupts the live CAS TCP stream.
  - Enforces **per-lane upstream-gated disconnect propagation (`<= 4.0 s`)** (`gate_listener_on_upstream`, `first_line_timeout_seconds = 4.0`, `idle_timeout_seconds = 4.0`, `disconnect_clients_on_upstream_loss`): if an RPM reboots, has its Ethernet cable unplugged, loses field-switch power, or freezes without sending TCP `FIN`/`RST`, `oscar-rpm-proxy` closes that lane's downstream listener and drops active consumers within `<= 4.0 s` so both CAS and OSCAR (**Status of Health** — *heart-pulse monitor icon*) flag the lane `OFFLINE` immediately and receive `Connection Refused` (`zero` `SYN-ACK` flapping) until live telemetry resumes.
  - Caches and replays per-lane Rapiscan `SG1..SG3` / `SN1..SN2` setup lines (plus active `TT` tamper state, cleared on `TC`), supports `discard` (default), `allow_primary` (CAS CIDR allowlist), and `forward` write policies, isolates stalled consumers via bounded per-client send queues, supports **Port-Mapped (`11601..11650`)** and **Ubuntu 24.04 Transparent Virtual-IP (`:1600` per lane + `arping` conflict check + ARP-flux sysctl + systemd persistence)** topologies, and generates both `config.json` and a ready-to-import 20-column OSCAR CSV in one command (`oscar.sh rpm-proxy configure --from-csv ... --emit-oscar-csv ...`).
- **Platform-Wide Interactive Icon Spotlights (`Highlight [Icon]`) & Visual Symbol Introductions (`Navbar`, `PlatformIcons`, `TrainingCurriculum`, `TrainingCoachDock`, `HelpDialog`, 4-Locale Operator Manuals):**
  - Adds interactive **`Highlight [Page / Tool] Icon`** spotlight buttons (including **Highlight Status of Health Icon** on the *heart-pulse monitor icon*, plus **Dashboard** *four-tile grid icon*, **Events** *warning-triangle (`!`) icon*, **Site Map** *map-pin icon*, **National Summary** *connected-nodes icon*, **Reports & Analytics** *bar-chart icon*, **Alarm Transfer** *QR-viewfinder icon*, **Users & Access** *person-and-gear icon*, **USB Backups** *USB-trident icon*, **Runtime Extensions** *puzzle-piece icon*, **Servers & Nodes** *cloud icon*, **Help (`?`)** *circled question-mark icon*, **Guided Walkthrough** *graduation-cap icon*, and **Settings** *gear icon*) across all 13 labs in the Guided Walkthrough / Practice Sandbox and on every Console Page card in `Help (?)`, paired with inline icon badges and plain-language symbol introductions across `en`, `es`, `fr`, and `el`.
- **4-Language (`en`, `es`, `fr`, `el`) WebVTT & SRT Video Subtitles (`docs/video-guides`, `HelpDialog`, `TrainingCoachDock`, `build.gradle`):**
  - Ships 232 verified `.vtt` and `.srt` subtitle files (`captions/{es,fr,el}/<slug>.{vtt,srt}` alongside English `captions/<slug>.{vtt,srt}`) across all 29 bundled `1080p` `30 fps` CFR guides (`100%` cue-timestamp parity), automatically selecting the active UI locale's `<track>` in OSCAR Viewer.
- **Sub-`150 ms` Dashboard Next-Page (`page + 1`) Prefetching, Non-Rapiscan Detector Driver Replay Tests, Windows `oscar-setup.ps1` Fix & Node 24 CI:**
  - `EventTable.tsx` background-prefetches `page + 1` rows (`0` duplicate `/observations/count` queries) with live MQTT invalidation so `Next Page` renders from warm cache even under 50-lane OCR load; adds deterministic wire-protocol replay & lifecycle JUnit suites for `sensorhub-driver-aspect` (Modbus TCP), `sensorhub-driver-rs350` (`N42.42` XML), `sensorhub-driver-kromek-d3s`, and `sensorhub-driver-kromek-d5`; fixes `Get-EnvironmentValue 'OSCAR_ARCHIVE_DIR'` in `dist/release/oscar-setup.ps1` (`.\oscar.bat status`) with a Windows PowerShell 5.1 regression gate; and upgrades GitHub Actions workflows across all repositories to Node 24 (`actions/checkout@v5`, `actions/setup-node@v5`, `actions/setup-java@v5`, `actions/cache@v5`, `softprops/action-gh-release@v3`).

### Release artifacts — which file to download (`v3.11.7`)

| Release Asset | Target Audience & Use Case |
| :--- | :--- |
| `oscar-3.11.7.zip` (+ `.sha256`) | **Connected Ubuntu Server 24.04 or Windows 11 installations and upgrades.** Includes Docker Compose definitions (`compose.yaml`, `compose.rpm-proxy.yaml`, `compose.sandbox.yaml`, `compose.octelium.yaml`), Linux/Windows administration CLIs (`oscar.sh` / `oscar.bat` including `rpm-proxy`, `reset-admin-password`, `sandbox`, and `remote-access`), `configure-ubuntu-host.sh`, `configure-windows-host.ps1`, declarative `ubuntu/` staging templates, application build context, all Markdown documentation, and all four localized PDF operator manuals. |
| `oscar-3.11.7-ubuntu-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Ubuntu 24.04 LTS installations (or slow hotel Wi-Fi staging).** Bundles official Ubuntu 24.04 Docker Engine + Compose v2 + `chrony`/`ethtool`/`nmap`/`arp-scan` `.deb` packages, pre-built container images (`oscar:3.11.7`, `oscar-postgis:3.11.7`, `oscar-rpm-proxy:3.11.7`, `nginx/nginx-unprivileged:1.30.7-alpine`), `oscar.sh rpm-proxy`, `reset-admin-password` & `sandbox`, bare-metal `create-autoinstall-usb` + `oscar-firstboot-wizard.sh`, and all Markdown/PDF documentation. |
| `oscar-3.11.7-windows-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations where Docker Desktop or WSL 2 is not yet installed.** Bundles pinned Docker Desktop `4.87.0` and WSL `2.7.3` installers, pre-built container images (`oscar:3.11.7`, `oscar-postgis:3.11.7`, `oscar-rpm-proxy:3.11.7`, `nginx/nginx-unprivileged:1.30.7-alpine`), administration scripts, and all Markdown/PDF documentation. |
| `oscar-3.11.7-windows-x86_64-offline-images.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations or upgrades where compatible Docker Desktop and WSL 2 are already running.** Contains the pre-built container image archive, administration scripts, and documentation without the Windows prerequisite installers. |

## 3.11.6 (Amber) 2026-11-22

OSCAR `3.11.6` (Amber) was a general-availability maintenance release on the `3.11` line for continuous 24/7 operation across up to 50 concurrent radiation portal monitor (RPM) and RTSP camera lanes on **Ubuntu Server 24.04 x86-64** and **Windows 11 x86-64** (Docker Desktop + WSL 2). It adds **1-Command Break-Glass Administrator Password Recovery (`reset-admin-password`)** for Passkey-only hostname/domain migrations and locked-out recovery, **Bare-Metal Ubuntu 24.04 Autoinstall LUKS2 / SSH / Sudo Hardening**, **Zero-Refresh Training Sandbox Live Reactivity**, **Full-Lane Moving Tractor-Trailer Sandbox Camera + Matched `2048×600` 16-Bit WCO `UFF 3.0.0` Truck NII Packages (`SCFU8572724` / `SWT03`)**, and **All 29 Constant-30-FPS Video Guides & 54 Light-Mode Operator Manual Screenshots**.

### Highlights in `3.11.6`

- **1-Command Break-Glass Administrator Password Recovery (`oscar.sh reset-admin-password`, `oscar.bat reset-admin-password`, `BreakGlassAdminResetTool`, `OscarIdentityStore`):**
  - Restores local administrator password sign-in after a Passkey-only hostname/domain migration or forgotten admin password via `sudo bash oscar.sh reset-admin-password` (Ubuntu) or `.\oscar.bat reset-admin-password` (Windows 11) with hidden TTY prompt or `--password-stdin` / `-PasswordStdin` (`--password` / `-Password` on `argv` is strictly rejected so credentials never enter `ps` or shell history).
  - Supports **zero-downtime live mode** (hashes with PBKDF2-HMAC-SHA256 `210,000` iterations + CSPRNG salt inside `oscar` before writing an atomic `0600` one-shot request consumed within `< 2 s` by `BasicSessionAuthenticator`, clearing rate-limit buckets, revoking active sessions for the target account, and leaving all enrolled FIDO2 Passkeys intact) and **offline mode** (atomic offline PBKDF2 update under container UID `10001` when `oscar` is stopped), while logging to host syslog / Windows Event Log and `security-break-glass-audit.log` and excluding `.break-glass-reset.*` from `support-bundle` archives.
- **Bare-Metal Ubuntu 24.04 Autoinstall & Host Security Hardening (`create-autoinstall-usb.{sh,ps1}`, `ubuntu/autoinstall/user-data.yaml`, `configure-ubuntu-host.sh`):**
  - Disables root SSH login by default (`PermitRootLogin no`) in `user-data.yaml` and adds `--luks-passphrase-file` / `-LuksPassphraseFile` (full-disk LUKS2 encryption), `--require-sudo-password` / `-RequireSudoPassword` (removing `NOPASSWD:ALL`), and `--ssh-keys-only` / `-SshKeysOnly` to `create-autoinstall-usb`, plus matching `host-check` (`os-default-password`, `ssh-hardening`, `sudo-password-policy`) and `prepare-host` (`--require-sudo-password`, `--ssh-keys-only`, `--ufw-ssh-cidr`, `--ufw-disable-ssh`) controls. Host LUKS2 encryption is completely transparent to cross-OS `Ubuntu <-> Windows 11` encrypted NTFS USB backup drives (`oscar-backup-key.txt`).
- **Zero-Refresh Training Sandbox Reactivity & Matched Moving-Truck Camera + WCO `UFF 3.0.0` NII (`SandboxRtspCameraStreamer`, `SandboxSampleAssets`, `SandboxRapiscanLoopbackServer`, `TamperOutput`, `TrainingCoachDock`, `useLaneHealth`):**
  - Host `start`/`stop`/`reset` actions poll live with `.active-job.lock` protection, while in-sandbox `Clear Faults`, `Fault: Gamma High`, `Fault: Tamper` (with millisecond-precision `TamperOutput` timestamps and active `extended_occupancy` cancellation), occupancy/alarm injections, track staging, and Split-Pane `/sensorhub/admin` changes update `/health`, `/`, `/event-log`, and lab badges live without page refresh.
  - Replaced the static sandbox container loop and `10×` RTP timestamp rescale bug with a `1.0×` real-time `1280×720` (`15 fps`, `0.33 s` GOP) articulated tractor-trailer portal drive-through (`SCFU8572724` / `SWT03` and `RSTU2402941` / `M50M1`) paired with full `2048×600` Deflate 16-bit Beer-Lambert truck WCO `UFF 3.0.0` packages (`dfb985c4-eb26-41ab-938b-ad2a1f5966d4`, `772e9494-96b1-433b-902e-fb39a864edc6`, and 1-char fuzzy `393a7a3f-a3f2-46a3-988a-3f21bf99857c`).
- **Visually Certified `30 fps` CFR Video Guides (`#01`–`#29`) & 54 Light-Mode Manual Screenshots:**
  - Re-recorded all 29 `1080p` `h264_nvenc` workflow guides at constant `30 fps` (`CFR`) with verified cue-to-frame timing and refreshed 30 operator manual screenshots to unified `1920×1080` Light Mode.

### Release artifacts — which file to download (`v3.11.6`)

| Release Asset | Target Audience & Use Case |
| :--- | :--- |
| `oscar-3.11.6.zip` (+ `.sha256`) | **Connected Ubuntu Server 24.04 or Windows 11 installations and upgrades.** Includes Docker Compose definitions (`compose.yaml`, `compose.sandbox.yaml`, `compose.octelium.yaml`), Linux/Windows administration CLIs (`oscar.sh` / `oscar.bat` including `reset-admin-password`, `sandbox`, and `remote-access`), `configure-ubuntu-host.sh`, `configure-windows-host.ps1`, declarative `ubuntu/` staging templates, application build context, all Markdown documentation, and all four localized PDF operator manuals. |
| `oscar-3.11.6-ubuntu-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Ubuntu 24.04 LTS installations (or slow hotel Wi-Fi staging).** Bundles official Ubuntu 24.04 Docker Engine + Compose v2 + `chrony`/`ethtool`/`nmap`/`arp-scan` `.deb` packages, pre-built container images (`oscar:3.11.6`, `oscar-postgis:3.11.6`, `nginx/nginx-unprivileged:1.30.7-alpine`), `oscar.sh reset-admin-password` & `sandbox`, bare-metal `create-autoinstall-usb` (with optional LUKS2 / SSH / sudo hardening) + `oscar-firstboot-wizard.sh`, and all Markdown/PDF documentation. |
| `oscar-3.11.6-windows-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations where Docker Desktop or WSL 2 is not yet installed.** Bundles pinned Docker Desktop `4.87.0` and WSL `2.7.3` installers, pre-built container images (`oscar:3.11.6`, `oscar-postgis:3.11.6`, `nginx/nginx-unprivileged:1.30.7-alpine`), administration scripts, and all Markdown/PDF documentation. |
| `oscar-3.11.6-windows-x86_64-offline-images.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations or upgrades where compatible Docker Desktop and WSL 2 are already running.** Contains the pre-built container image archive, administration scripts, and documentation without the Windows prerequisite installers. |

## 3.11.5 (Amber) 2026-11-22

OSCAR `3.11.5` (Amber) is the current general-availability release on the `3.11` line for continuous 24/7 operation across up to 50 concurrent radiation portal monitor (RPM) and RTSP camera lanes on **Ubuntu Server 24.04 x86-64** and **Windows 11 x86-64** (Docker Desktop + WSL 2). It extends the **Ephemeral Hands-On Training Sandbox (`oscar-sandbox`)** over **Zero-Trust Octelium Remote Access (`https://<site>-sandbox.<hub>`)** with **automatic Let's Encrypt TLS (`:443`)**, **shared parent-domain WebAuthn Passkeys (`rpId = <hub>`)**, **Authentik OIDC & Verified Tunnel SSO**, and **one-way operational user/role seeding**, while preserving direct **`https://<host>:8444`** access on LAN, Tailscale, and VPN networks.

### Highlights in `3.11.5`

- **Isolated Zero-Trust Remote Sandbox Subdomain (`https://<site>-sandbox.<hub>`) Over Standard HTTPS `:443` (`compose.octelium.yaml`, `docker/tunnel/entrypoint.sh`, `oscar-remote-access.{sh,ps1}`, `ORNL/oscar-federation-hub`):**
  - Reuses the site's existing single `oscar-tunnel` workload connector token (`octelium connect --serve-all`) and an unprivileged loopback NGINX listener inside `oscar-tunnel` (`127.0.0.1:18444 -> https://host.docker.internal:8444`) to expose the Practice Sandbox on its own isolated HTTPS origin (`https://<site>-sandbox.<hub>`) with valid Hub Let's Encrypt TLS and zero inbound firewall ports (`:8444` remains unexposed to the public internet).
  - Isolating the sandbox on `<site>-sandbox.<hub>` rather than a same-origin `/sandbox/` subpath prevents `localStorage` (`osh_nodes`) and root-relative `/sensorhub/*` API collisions with the live portal, requires zero dual static-export or Vaadin path-rewriting builds, allows `/sensorhub/admin` Lab 3.1 split-pane practice inside `<site>-sandbox.<hub>` while keeping `/sensorhub/admin` blocked on `<site>.<hub>`, and serves a clean HTML `503` status page when `:8444` is stopped. Direct `https://<host>:8444` remains simultaneously active on LAN/VPN.
- **Shared Parent-Domain WebAuthn Passkeys & One-Way Operational Auth Seeding (`BasicSessionAuthenticator`, `WebAuthnCodec`, `OscarIdentityStore`, `SandboxAuthConfigSeeder`, `oscar-sandbox.{sh,ps1}`):**
  - `BasicSessionAuthenticator.selectEffectiveRpId` automatically derives a suffix-validated parent Relying Party ID (`rpId = <hub>`) from `webAuthnRpId`, `OSCAR_WEBAUTHN_RP_ID` (injected in-memory from `octelium.env`), or Federation Hub URLs (`oidcIssuerUrl` / `externalIdentityConsoleUrl`), scoping `PasskeyRecord.rpId`, `allowCredentials`, and `PublicKeyCredential.signalAllAcceptedCredentials` so Passkeys enrolled on `https://<site>.<hub>` work immediately on `https://<site>-sandbox.<hub>` while LAN hostnames retain local `rpId` isolation.
  - `SandboxAuthConfigSeeder` extracts operational `BasicSecurityRealmConfig` users/roles, OIDC SSO settings, Verified Tunnel SSO settings, and `webAuthnRpId` one-way into the disposable sandbox at startup without mounting production state.
- **Context-Aware GUI Sandbox URL Resolution (`TrainingSandboxApi.ts`, `TrainingSandboxLauncherCard.tsx`, `TrainingCoachDock.tsx`):**
  - When browsing via `https://<site>.<hub>`, **Guided Walkthrough** and **Help (`?`)** automatically display and launch `https://<site>-sandbox.<hub>` (no `:8444` port suffix or self-signed TLS prompt); when browsing on LAN/VPN, they continue opening `https://<host>:8444`.

### Release artifacts — which file to download (`v3.11.5`)

| Release Asset | Target Audience & Use Case |
| :--- | :--- |
| `oscar-3.11.5.zip` (+ `.sha256`) | **Connected Ubuntu Server 24.04 or Windows 11 installations and upgrades.** Includes Docker Compose definitions (`compose.yaml`, `compose.sandbox.yaml`, `compose.octelium.yaml`), Linux/Windows administration CLIs (`oscar.sh` / `oscar.bat` including `sandbox` and `remote-access`), `configure-ubuntu-host.sh`, `configure-windows-host.ps1`, declarative `ubuntu/` staging templates, application build context, all Markdown documentation, and all four localized PDF operator manuals. |
| `oscar-3.11.5-ubuntu-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Ubuntu 24.04 LTS installations (or slow hotel Wi-Fi staging).** Bundles official Ubuntu 24.04 Docker Engine + Compose v2 + `chrony`/`ethtool`/`nmap`/`arp-scan` `.deb` packages, pre-built container images (`oscar:3.11.5`, `oscar-postgis:3.11.5`, `nginx/nginx-unprivileged:1.30.7-alpine`), `oscar.sh sandbox`, bare-metal `create-autoinstall-usb` + `oscar-firstboot-wizard.sh`, and all Markdown/PDF documentation. |
| `oscar-3.11.5-windows-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations where Docker Desktop or WSL 2 is not yet installed.** Bundles pinned Docker Desktop `4.87.0` and WSL `2.7.3` installers, pre-built container images (`oscar:3.11.5`, `oscar-postgis:3.11.5`, `nginx/nginx-unprivileged:1.30.7-alpine`), administration scripts, and all Markdown/PDF documentation. |
| `oscar-3.11.5-windows-x86_64-offline-images.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations or upgrades where compatible Docker Desktop and WSL 2 are already running.** Contains the pre-built container image archive, administration scripts, and documentation without the Windows prerequisite installers. |

## 3.11.4 (Amber) 2026-11-21

OSCAR `3.11.4` (Amber) introduced **Per-Lane ControlByWeb® WebRelay-Quad™ Physical RPM Lights & Sounder Control** and the **Anytime On-Demand Guided Walkthrough Refresher (`:443`) + Clear `:8444` Auto-Shutdown Orientation**, building directly on `3.11.3`'s **Ephemeral Hands-On Training Sandbox & Guided Academy (`oscar-sandbox`)**, **Commercial Cargo Non-Intrusive Inspection (`WCO UFF 2.0` & `UFF 3.0.0`)**, bare-metal Ubuntu 24.04 autoinstall USB + First-Boot Recovery Wizard provisioning, NGINX `1.30.7-alpine` security hardening, and the `PARQUET_PRIMARY` multi-year tiered-storage architecture introduced since public release [`v3.8.0`](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/releases/tag/v3.8.0).

### Major feature highlights in `3.11.4` (including `3.11.1`–`3.11.4` cumulative capabilities)

#### 1. Per-Lane ControlByWeb® WebRelay-Quad™ Physical RPM Lights & Sound Control (`LaneWebRelayController`, `WebRelayQuadClient`, `LaneWebRelayServlet`, `LaneWebRelayDialog`)

- **Zero-Clutter Shipped Default & Fail-Safe Hardware Pass-Through (`0,0,0,0`):**
  - Ships **disabled by default** (`enabled = false`) so lanes without external relay modules incur **`0` background threads, `0` open sockets, `0` `/health` network fetches, and `0` extra UI chips** on operator views.
  - When OSCAR stops, restarts, or loses power, de-energized coils (`0,0,0,0`) automatically restore direct hardware pass-through to the RPM's native alarm outputs so physical portal alarms are never silently lost.
- **Automated `AUTO` Occupancy & EML Gatekeeping + Optional Auxiliary Relay Unit:**
  - Supports **ControlByWeb WebRelay-Quad** (`X-WR-4R3-E` PoE / non-PoE and `X-410`) over standard `HTTP/1.1` XML (`stateFull.xml` with automatic `state.xml` fallback on legacy firmware, optional HTTP Basic Auth, and hardware-timed `relayNState=2&pulseTimeN=...` pulses).
  - In `AUTO` mode, arms `R1=1, R2=1` intercept coils (automatically re-arming within `pollIntervalSeconds` after PoE power blips), suppresses physical siren/beacon activations on benign **`Code 9999: EML Non-Threat`** and configurable **`Code 9998: Extended Occupancy Gamma Alarm`** (`suppressExtendedOccupancyGamma = true` default), and immediately pulses **Gamma Red Light + Siren (`R3`)** and/or **Neutron Blue Light (`R4`)** on actionable threats (Neutron alarms are **never** suppressed). Supports an optional synchronized second auxiliary dry-contact `WebRelay-Quad` per lane (`secondaryEnabled`, `mirrorPrimaryAlarmsToSecondary`), `#WEBRELAY` CSV import/export directives (omitting plaintext passwords on export), and `SupportBundleRedactor` password scrubbing.
- **Per-Lane Administrator Control Across Viewer (`/health`, `/lane-view`) & SensorHub Admin (`/sensorhub/admin`):**
  - Administrators open an accessible native `<dialog>` modal (`Lights & Sound`) on `/health` or `/lane-view` (or edit `LaneConfigForm` in `/sensorhub/admin`) to switch lanes, inspect live `R1–R4` coil telemetry and `Code 9999` / `Code 9998` suppression counts, fire timed commissioning pulses or latched walk-around overrides, switch between `AUTO`, `MUTED` (`1,1,0,0`), `PASS_THROUGH` (`0,0,0,0`), and `MANUAL`, test HTTP/XML connectivity, and persist settings across `en`, `es`, `fr`, and `el`. See the [Per-Lane Physical RPM Lights & Sound (`WebRelay-Quad`) Guide](https://github.com/ORNL/oscar/blob/main/docs/LANE_WEBRELAY_GUIDE.md) and bundled how-to video guide `#29` (`29-lane-webrelay-lights-and-sound`).

#### 2. Anytime Live-Console Guided Walkthrough Refresher (`:443`) & Ephemeral Hands-On Training Sandbox (`oscar-sandbox`, `:8444`)

- **Anytime On-Demand Read-Only Refresher on `:443` + Clear Auto-Shutdown Orientation (`Navbar`, `TrainingCoachDock`, `TrainingSandboxLauncherCard`, `TrainingSandboxServlet`):**
  - Any signed-in user (`Viewer`, `Operator`, or `Administrator`) can click **Guided Walkthrough** in the top navigation bar (or inside **Help (`?`)**) at any time during a live shift to open the side-by-side **Read-Only Refresher Mode** (`0` background polling when closed, `0` fake alarm injections, and `0` `/stage-track` mutations on `:443`) across **13 role-based labs** (including **Lab 3.5 — Per-Lane Physical RPM Lights & Sound**).
  - Clearly documents live-console read-only boundaries, **`120-minute` (2-hour) automatic shutdown & `< 2 s` complete volume wipe** (with live countdown and local shutdown clock time), one-way credential/Passkey seeding (`https://<host>:8444`), and `TRAINING SANDBOX — NON-OPERATIONAL` watermarking. Standard `oscar init`, `start`, `restart`, and `upgrade` runs now automatically install and enable the zero-`docker.sock` host queue bridge on both **Ubuntu Server 24.04** (`oscar-sandbox-agent.path` + `.timer`) and **Windows 11** (`OSCAR-SandboxAgent` Scheduled Task) out of the box, giving all signed-in users 1-click idempotent `:8444` launch/open right from the GUI (while keeping early `Stop` / `Reset` Administrator-only and supporting opt-out via `disable-ui-bridge` or `OSCAR_SANDBOX_UI_BRIDGE=disabled`).
- **Zero-Contamination Ephemeral `:8444` Stack & Loopback Micro-Emulator (`compose.sandbox.yaml`, `oscar.sh` / `oscar.bat sandbox`):**
  - Reuses the installed `oscar:3.11.4`, `oscar-postgis:3.11.4`, and `nginx/nginx-unprivileged:1.30.7-alpine` images (`0 B` extra download) with disposable volumes (`oscar_sandbox_state`, `oscar_sandbox_pg`), `archive.enabled = false` (`0` `.parquet` files written), `>= 3.5 GiB` free-RAM guard, wire-exact loopback Rapiscan (`127.0.0.1:10099`/`10100`) and JNI H.264 container RTSP (`127.0.0.1:8554/tutorial-cam`) micro-emulators, downloadable `.csv`/`.n42`/`.uff`/`.pmtiles`/`.json` practice files, **Split-Pane `/sensorhub/admin`**, and 1-page PDF Training Completion Records. See the [Guided Walkthrough & Hands-On Training Sandbox Guide](https://github.com/ORNL/oscar/blob/main/docs/TRAINING_SANDBOX_GUIDE.md) and bundled how-to video guide `#28` (`28-hands-on-training-sandbox`).

#### 3. Commercial Cargo Non-Intrusive Inspection (`WCO UFF 2.0` & `UFF 3.0.0`) Share Correlation, Tier-1 UUID Lookup & 16-Bit Radiograph Inspection

- **Default-Off Read-Only SMBv2/SMBv3 Connector, Fuzzy `OCR ±1` Correlation & 16-Bit `WebGL2` + HEMD `Z_eff` Inspector:** Ships disabled by default (`0` extra UI clutter on standalone RPM portals) while allowing local `.uff` uploads (`up to 200 MB`) at any site and user-space SMBv2/SMBv3 share indexing (`trailing-64 KiB` ZIP64 Central Directory reads in `< 1 s` cold / `< 15 ms` warm), Tier-1 UUID omnibox search, progressive `preview.jpg` -> 16-bit `uint16` TIFF + palettized HEMD `Z_eff` inspection aligned with the RPM radiation profile, and `< 4 KB` `.uffref.json` adjudication staging. See the [Cargo UFF Integration Guide](https://github.com/ORNL/oscar/blob/main/docs/CARGO_UFF_INTEGRATION.md) and video guide `#27`.

### Release artifacts — which file to download (`v3.11.4`)

| Release Asset | Target Audience & Use Case |
| :--- | :--- |
| `oscar-3.11.4.zip` (+ `.sha256`) | **Connected Ubuntu Server 24.04 or Windows 11 installations and upgrades.** Includes Docker Compose definitions (`compose.yaml`, `compose.sandbox.yaml`, `compose.octelium.yaml`), Linux/Windows administration CLIs (`oscar.sh` / `oscar.bat` including `sandbox`), `configure-ubuntu-host.sh`, `configure-windows-host.ps1`, declarative `ubuntu/` staging templates, application build context, all Markdown documentation (including `LANE_WEBRELAY_GUIDE.md`, `TRAINING_SANDBOX_GUIDE.md`, and `CARGO_UFF_INTEGRATION.md`), and all four localized PDF operator manuals. |
| `oscar-3.11.4-ubuntu-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Ubuntu 24.04 LTS installations (or slow hotel Wi-Fi staging) where Docker Engine or internet access is unavailable.** Bundles official Ubuntu 24.04 Docker Engine + Compose v2 + `chrony`/`ethtool`/`nmap`/`arp-scan` `.deb` packages, pre-built container images (`oscar:3.11.4`, `oscar-postgis:3.11.4`, `nginx/nginx-unprivileged:1.30.7-alpine`), `oscar.sh sandbox`, bare-metal `create-autoinstall-usb` + `oscar-firstboot-wizard.sh`, and all Markdown/PDF documentation. |
| `oscar-3.11.4-windows-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations where Docker Desktop or WSL 2 is not yet installed.** Bundles pinned Docker Desktop `4.87.0` and WSL `2.7.3` installers, pre-built container images (`oscar:3.11.4`, `oscar-postgis:3.11.4`, `nginx/nginx-unprivileged:1.30.7-alpine`), administration scripts (including `oscar.bat sandbox`), and all Markdown/PDF documentation. |
| `oscar-3.11.4-windows-x86_64-offline-images.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations or upgrades where compatible Docker Desktop and WSL 2 are already running.** Contains the pre-built container image archive, administration scripts, and documentation without the Windows prerequisite installers. |
| `OSCAR-3.11.4-Administrator-Operator-Manual-{en,es,fr,el}.pdf` | **Standalone localized Administrator and Operator Manuals** in English (`en`), Español (`es`), Français (`fr`), and Ελληνικά (`el`). |
| `oscar-v3.11.4-source.zip` (+ `.sha256`) | **Complete tracked source archive including all submodules** (`osh-core`, `osh-addons`, `osh-oakridge-modules`, and `oscar-viewer`; GitHub's auto-generated source archive omits submodules). |
| `OSCAR-3.11.4-SHA256SUMS.txt` | **Master SHA-256 checksum manifest** covering all release ZIPs and localized PDF manuals. |

### Start here — documentation & cumulative `v3.8.0` → `v3.11.4` architectural guide

- **Complete Release Overview, Major Features (`v3.8.0` → `v3.11.4`), Architectural Rationale & Multi-Year Sizing:** [Release Overview, Architectural Rationale, and User Guide (`RELEASE_NOTES_AND_UPGRADE_GUIDE.md`)](https://github.com/ORNL/oscar/blob/main/docs/RELEASE_NOTES_AND_UPGRADE_GUIDE.md)
- **Quick Start & Host Administration:** [Quick Start (`QUICKSTART.md`)](https://github.com/ORNL/oscar/blob/main/dist/release/QUICKSTART.md) · [Administrator Guide (`DEPLOYMENT.md`)](https://github.com/ORNL/oscar/blob/main/dist/release/DEPLOYMENT.md) · [Ubuntu 24.04 Field Setup & Bare-Metal Guide (`UBUNTU_FIELD_SETUP_GUIDE.md`)](https://github.com/ORNL/oscar/blob/main/docs/UBUNTU_FIELD_SETUP_GUIDE.md)
- **Feature Guides:** [Per-Lane RPM Lights & Sound (`LANE_WEBRELAY_GUIDE.md`)](https://github.com/ORNL/oscar/blob/main/docs/LANE_WEBRELAY_GUIDE.md) · [Guided Walkthrough & Hands-On Training Sandbox (`TRAINING_SANDBOX_GUIDE.md`)](https://github.com/ORNL/oscar/blob/main/docs/TRAINING_SANDBOX_GUIDE.md) · [Commercial Cargo NII `WCO UFF 2.0 & 3.0` (`CARGO_UFF_INTEGRATION.md`)](https://github.com/ORNL/oscar/blob/main/docs/CARGO_UFF_INTEGRATION.md) · [Pluggable Extensions & Regional Packs (`PLUGGABLE_EXTENSIONS_GUIDE.md`)](https://github.com/ORNL/oscar/blob/main/docs/PLUGGABLE_EXTENSIONS_GUIDE.md) · [EML Integration (`EML_INTEGRATION.md`)](https://github.com/ORNL/oscar/blob/main/docs/EML_INTEGRATION.md) · [Continual & USB NVMe Backups (`CONTINUAL_AND_USB_BACKUP_GUIDE.md`)](https://github.com/ORNL/oscar/blob/main/docs/CONTINUAL_AND_USB_BACKUP_GUIDE.md) · [How-To Video Guides (29 Bundled 1080p Modules)](https://github.com/ORNL/oscar/blob/main/docs/VIDEO_GUIDES.md)
- **Storage, Recovery & Federation:** [Storage Architecture (`STORAGE_ARCHITECTURE.md`)](https://github.com/ORNL/oscar/blob/main/docs/STORAGE_ARCHITECTURE.md) · [Data Lifecycle (`DATA_LIFECYCLE.md`)](https://github.com/ORNL/oscar/blob/main/docs/DATA_LIFECYCLE.md) · [Backup & Restore (`BACKUP_RESTORE.md`)](https://github.com/ORNL/oscar/blob/main/docs/BACKUP_RESTORE.md) · [Self-Hosted Zero-Trust Hub & Authentik SSO (`ORNL/oscar-federation-hub`)](https://github.com/ORNL/oscar-federation-hub) · [50-Lane Regression Suite (`ORNL/oscar-regression`)](https://github.com/ORNL/oscar-regression)

## 3.11.3 (Amber) 2026-11-21

OSCAR `3.11.3` (Amber) is the current general-availability release on the `3.11` line for continuous 24/7 operation across up to 50 concurrent radiation portal monitor (RPM) and RTSP camera lanes on **Ubuntu Server 24.04 x86-64** and **Windows 11 x86-64** (Docker Desktop + WSL 2). It introduces the **Built-In Ephemeral Hands-On Training Sandbox & Multi-Modal Guided Academy (`oscar-sandbox`)** and incorporates **Commercial Cargo Non-Intrusive Inspection (`WCO UFF 2.0` & `UFF 3.0.0`)**, bare-metal Ubuntu 24.04 autoinstall USB + First-Boot Recovery Wizard provisioning, NGINX `1.30.7-alpine` security hardening, and the full `PARQUET_PRIMARY` multi-year tiered-storage architecture introduced since public release [`v3.8.0`](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/releases/tag/v3.8.0).

### Major feature highlights in `3.11.3` (including `3.11.1`–`3.11.3` cumulative capabilities)

#### 1. Built-In Ephemeral Hands-On Training Sandbox & Multi-Modal Guided Academy (`oscar-sandbox`, `:8444`)

- **Zero-Contamination Ephemeral Training Stack (`compose.sandbox.yaml`, `oscar-sandbox.sh`, `oscar-sandbox.ps1`, `oscar.sh sandbox`, `oscar.bat sandbox`):**
  - Launches an isolated Docker Compose stack (`--project-name oscar-sandbox`, default HTTPS port `:8444`) reusing the already-installed `oscar:3.11.3`, `oscar-postgis:3.11.3`, and `nginx/nginx-unprivileged:1.30.7-alpine` images (`0 B` extra image download) with disposable volumes (`oscar_sandbox_state`, `oscar_sandbox_pg`), `tmpfs` `/var/lib/oscar/archive`, `archive.enabled = false` (`0` `.parquet` files written), zero mounts to `oscar_postgres_data`, `oscar_oscar_state`, or `OSCAR_ARCHIVE_DIR`, a `>= 3.5 GiB` (`3584 MiB`) free-RAM preflight check, bounded `-Xmx2g` JVM & `128 MB` PostgreSQL `shared_buffers`, automatic TTL idle shutdown (default `120 min`), and `< 2 s` complete wipe (`down -v --remove-orphans`) on `stop` or `reset`.
  - Performs a one-way read-only seed of the host's TLS certificate and existing `BasicSecurityRealmConfig` PBKDF2 / WebAuthn Passkey identity store into disposable runtime storage (`/run/oscar-sandbox` on Linux; `%ProgramData%\OSCAR\sandbox-runtime` on Windows) so operators and administrators sign in on `:8444` with their existing credentials while keeping `0` threads, `0` sockets, and `0` extra UI banners on production (`:443`) when stopped. All sandbox `PDF`, `CSV`, `JSON`, `XLSX`, and `QR` exports are stamped with `TRAINING SANDBOX — NON-OPERATIONAL`.
- **Built-In Loopback Micro-Emulator & Practice Sample Assets (`TrainingSandboxManager`, `SandboxRapiscanLoopbackServer`, `SandboxRtspCameraStreamer`, `SandboxEmlTrainingAlgorithm`, `SandboxSampleAssets`):**
  - Strictly gated on `OSCAR_SANDBOX_MODE=true`. Runs wire-exact loopback Rapiscan ASCII servers (`127.0.0.1:10099` & `127.0.0.1:10100`) supporting 1-click injection of `clean_pass`, `gamma_alarm`, `neutron_alarm`, `gamma_neutron_alarm`, `norm_eml` (`Code 9999: EML Non-Threat`), `extended_occupancy` (`Fault - Extended Occupancy` + `Code 9998`), `fault_gamma_high`, `fault_tamper`, and `clear_faults`; streams synthetic `CC0-1.0` `1280×720` ISO 6346 container video (`MSCU5285725` / `OSCU4829106`) via loopback `mediamtx` (`rtsp://127.0.0.1:8554/tutorial-cam` & `/tutorial-cam-2`) for live HLS, 5-JPEG retention, and ONNX Container OCR; and serves downloadable practice `.csv`, `.n42`, `.uff` (`UFF 3.0.0` 16-bit `uint16` TIFF + palettized HEMD PNG), `.pmtiles`, and `.json` files.
- **Multi-Modal Guided Academy (`TrainingCoachDock`, `TrainingCurriculum`, `TrainingSandboxLauncherCard`):**
  - Adds a compact single-row `TRAINING SANDBOX` indicator in the top navigation bar (`< 12%` viewport height, zero startup modals) paired with a collapsible 4-language (`en`, `es`, `fr`, `el`) **Training Coach** covering **12 hands-on labs** across **Track 1 — Gatehouse Operator** (5 labs), **Track 2 — Shift Supervisor & Analyst** (3 labs), and **Track 3 — System Administrator** (4 Day-1 Blank-Slate labs with **Split-Pane `/sensorhub/admin` `<iframe>`**), combining inline captioned `1080p` videos, annotated `1920×1080` screenshots, `[data-testid]` spotlighting, `4 s` live API auto-verification, and 1-page vector PDF Training Completion Records (`oscar-training-completion-record.pdf`). See the [Hands-On Training Sandbox & Guided Academy Guide](https://github.com/ORNL/oscar/blob/main/docs/TRAINING_SANDBOX_GUIDE.md) and bundled how-to video guide `#28` (`28-hands-on-training-sandbox`).

#### 2. Commercial Cargo Non-Intrusive Inspection (`WCO UFF 2.0` & `UFF 3.0.0`) Share Correlation, Tier-1 UUID Lookup & 16-Bit Radiograph Inspection

- **Zero-Clutter Shipped Default & Always-Available Local `.uff` Upload:**
  - Ships **disabled by default** (`enabled = false`) so standalone RPM portals see **zero extra UI buttons, columns, or banners** across Dashboard, Event Log, Lane View, Navbar, and Event Details, and incur **zero background threads, open sockets, or network polls**.
  - Operators at any site—even with SMB share integration disabled—can upload individual `.uff` packages (`up to 200 MB`) on demand via **Upload Files** in **Secondary Inspection**, automatically extracting embedded `.n42` radiation spectra into Sandia WebID / offline photopeak nuclide analysis, auto-populating untouched **Vehicle ID** inputs from scanner OCR metadata, and inspecting 16-bit radiographs in-browser.
- **User-Space Read-Only SMBv2/SMBv3 & Mounted Directory Connector (`CargoUffManager`, `UffSmbConnector`, `UffZipReader`, `WcoUffParser`):**
  - Connects in user space from **Runtime Extensions (`/extensions`) -> Cargo NII (WCO UFF)** (`com.hierynomus:smbj:0.13.0`, `4 s` connect / `6 s` read timeouts, AES-256-GCM encrypted credentials in `/var/lib/oscar/extensions/uff/uff-config.json`, automatic `SupportBundleRedactor` scrubbing, 1-click **Test Connection** verification, and zero root `mount.cifs` privilege required) to both hierarchical CIP/NAS date-and-scanner trees (`YYYY/MM/DD/<SCANNER_ID>/<uuid>.uff`) and flat vendor drop-folders (`<uuid>.uff`).
  - Reads only the trailing `64 KiB` ZIP/ZIP64 Central Directory block over SMB (`UffZipReader`) and streams the `~2 KiB` `<uuid>.xml` manifest into an XXE-hardened dual `UFF 2.0` / `UFF 3.0.0` XML parser, indexing multi-gigabyte shares in `< 1 s` cold and `< 15 ms` warm via an incremental `(relativePath, sizeBytes, mtimeMillis)` cache (`index-cache.json`).
- **Fuzzy Container/Plate Correlation (`OCR ±1`), Tier-1 UUID Omnibox Lookup, 16-Bit `WebGL2` Radiograph + HEMD `Z_eff` Inspector & Zero-Download Adjudication Staging (`CargoUffViewerDialog`, `CargoUffSmbPickerDialog`, `Tiff16Decoder`):**
  - Supports automatic container/plate correlation with **1-character visual OCR confusion tolerance** (`0↔O`, `8↔B`, `5↔S`, `2↔Z`, `1↔I`, `6↔G`, badged `OCR ±1`), interactive scanner-lane & alarm time-window browsing (`Browse Cargo UFF`), and direct UFF UUID / `<uuid>.uff` filename / Windows UNC path lookup in **Events (`/event-log`)** for unlabelled **Tier-1** scans.
  - Streams `preview.jpg` in `< 200 ms` over LAN or Zero-Trust tunnels followed by full 16-bit `uint16` grayscale TIFF + palettized **HEMD** effective atomic-number (`Z_eff`) PNG rendering (`WebGL2` `R16UI` + `Uint32Array[65536]` LUT fallback) with interactive Window/Level contrast, High-Z / Low-Z presets, Pseudo-Color, Invert, Zoom/Pan, customs HS-code declaration/OCR tabs, longitudinal **RPM Gamma & Neutron Count Profile** alignment (`Cab Left` ↔ `Cab Right`), and `< 4 KB` zero-download NAS adjudication staging (`uff-link-<uuid>.uffref.json`). See the [Cargo UFF Integration Guide](https://github.com/ORNL/oscar/blob/main/docs/CARGO_UFF_INTEGRATION.md) and bundled how-to video guide `#27` (`27-cargo-uff-smb-and-xray-inspection`).

#### 3. Bare-Metal Provisioning, USB NVMe Restore Hardening & Gateway Security (`3.11.1`–`3.11.3`)

- **NGINX `1.30.7-alpine` TLS Gateway & Tunnel Hardening:** Upgrades the HTTPS gateway and remote-access tunnel base image to `nginx/nginx-unprivileged:1.30.7-alpine` (fixing CVE-2026-123007, CVE-2026-123633, and CVE-2026-118899) while preserving explicit `:port` host headers across non-`443` redirects.
- **Cross-Platform Ubuntu 24.04 Autoinstall USB Builders & First-Boot Recovery Wizard:** Adds `.\oscar.bat create-autoinstall-usb` (Windows 11) and `sudo bash oscar.sh create-autoinstall-usb` (Ubuntu) plus `sudo bash oscar.sh wizard` / `sudo oscar-wizard` supporting read-only USB NVMe backup restore, single-snapshot restore, `config.json` / `lanes.csv` / `.pmtiles` import, and clean site initialization.
- **USB-to-NVMe Enclosure Stability & Canonical `.oscar-storage-root` Restore Identity:** Configures Linux `usb-storage` Bulk-Only (`:u`) and `usbcore` No-LPM (`:k`) quirks (`Realtek RTL9210`, `JMicron JMS583/562/578`, `ASMedia ASM2362`), writes the canonical 8-line `format=oscar-storage-root-identity` marker during cold-iron `usb-backup restore`, and assigns deterministic Rapiscan/Aspect sensor UIDs prior to TCP connect so air-gapped startups never stall when RPMs are powered off.

### Release artifacts — which file to download (`v3.11.3`)

| Release Asset | Target Audience & Use Case |
| :--- | :--- |
| `oscar-3.11.3.zip` (+ `.sha256`) | **Connected Ubuntu Server 24.04 or Windows 11 installations and upgrades.** Includes Docker Compose definitions (`compose.yaml`, `compose.sandbox.yaml`, `compose.octelium.yaml`), Linux/Windows administration CLIs (`oscar.sh` / `oscar.bat` including `sandbox`), `configure-ubuntu-host.sh`, `configure-windows-host.ps1`, declarative `ubuntu/` staging templates, application build context, all Markdown documentation (including `TRAINING_SANDBOX_GUIDE.md` and `CARGO_UFF_INTEGRATION.md`), and all four localized PDF operator manuals. |
| `oscar-3.11.3-ubuntu-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Ubuntu 24.04 LTS installations (or slow hotel Wi-Fi staging) where Docker Engine or internet access is unavailable.** Bundles official Ubuntu 24.04 Docker Engine + Compose v2 + `chrony`/`ethtool`/`nmap`/`arp-scan` `.deb` packages, pre-built container images (`oscar:3.11.3`, `oscar-postgis:3.11.3`, `nginx/nginx-unprivileged:1.30.7-alpine`), `oscar.sh sandbox`, bare-metal `create-autoinstall-usb` + `oscar-firstboot-wizard.sh`, and all Markdown/PDF documentation. |
| `oscar-3.11.3-windows-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations where Docker Desktop or WSL 2 is not yet installed.** Bundles pinned Docker Desktop `4.87.0` and WSL `2.7.3` installers, pre-built container images (`oscar:3.11.3`, `oscar-postgis:3.11.3`, `nginx/nginx-unprivileged:1.30.7-alpine`), administration scripts (including `oscar.bat sandbox`), and all Markdown/PDF documentation. |
| `oscar-3.11.3-windows-x86_64-offline-images.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations or upgrades where compatible Docker Desktop and WSL 2 are already running.** Contains the pre-built container image archive, administration scripts, and documentation without the Windows prerequisite installers. |
| `OSCAR-3.11.3-Administrator-Operator-Manual-{en,es,fr,el}.pdf` | **Standalone localized Administrator and Operator Manuals** in English (`en`), Español (`es`), Français (`fr`), and Ελληνικά (`el`). |
| `oscar-v3.11.3-source.zip` (+ `.sha256`) | **Complete tracked source archive including all submodules** (`osh-core`, `osh-addons`, `osh-oakridge-modules`, and `oscar-viewer`; GitHub's auto-generated source archive omits submodules). |
| `OSCAR-3.11.3-SHA256SUMS.txt` | **Master SHA-256 checksum manifest** covering all release ZIPs and localized PDF manuals. |

### Start here — documentation & cumulative `v3.8.0` → `v3.11.3` architectural guide

- **Complete Release Overview, Major Features (`v3.8.0` → `v3.11.3`), Architectural Rationale & Multi-Year Sizing:** [Release Overview, Architectural Rationale, and User Guide (`RELEASE_NOTES_AND_UPGRADE_GUIDE.md`)](https://github.com/ORNL/oscar/blob/main/docs/RELEASE_NOTES_AND_UPGRADE_GUIDE.md)
- **Quick Start & Host Administration:** [Quick Start (`QUICKSTART.md`)](https://github.com/ORNL/oscar/blob/main/dist/release/QUICKSTART.md) · [Administrator Guide (`DEPLOYMENT.md`)](https://github.com/ORNL/oscar/blob/main/dist/release/DEPLOYMENT.md) · [Ubuntu 24.04 Field Setup & Bare-Metal Guide (`UBUNTU_FIELD_SETUP_GUIDE.md`)](https://github.com/ORNL/oscar/blob/main/docs/UBUNTU_FIELD_SETUP_GUIDE.md)
- **Feature Guides:** [Hands-On Training Sandbox (`TRAINING_SANDBOX_GUIDE.md`)](https://github.com/ORNL/oscar/blob/main/docs/TRAINING_SANDBOX_GUIDE.md) · [Commercial Cargo NII `WCO UFF 2.0 & 3.0` (`CARGO_UFF_INTEGRATION.md`)](https://github.com/ORNL/oscar/blob/main/docs/CARGO_UFF_INTEGRATION.md) · [Pluggable Extensions & Regional Packs (`PLUGGABLE_EXTENSIONS_GUIDE.md`)](https://github.com/ORNL/oscar/blob/main/docs/PLUGGABLE_EXTENSIONS_GUIDE.md) · [EML Integration (`EML_INTEGRATION.md`)](https://github.com/ORNL/oscar/blob/main/docs/EML_INTEGRATION.md) · [Continual & USB NVMe Backups (`CONTINUAL_AND_USB_BACKUP_GUIDE.md`)](https://github.com/ORNL/oscar/blob/main/docs/CONTINUAL_AND_USB_BACKUP_GUIDE.md) · [How-To Video Guides (28 Bundled 1080p Modules)](https://github.com/ORNL/oscar/blob/main/docs/VIDEO_GUIDES.md)
- **Storage, Recovery & Federation:** [Storage Architecture (`STORAGE_ARCHITECTURE.md`)](https://github.com/ORNL/oscar/blob/main/docs/STORAGE_ARCHITECTURE.md) · [Data Lifecycle (`DATA_LIFECYCLE.md`)](https://github.com/ORNL/oscar/blob/main/docs/DATA_LIFECYCLE.md) · [Backup & Restore (`BACKUP_RESTORE.md`)](https://github.com/ORNL/oscar/blob/main/docs/BACKUP_RESTORE.md) · [Self-Hosted Zero-Trust Hub & Authentik SSO (`ORNL/oscar-federation-hub`)](https://github.com/ORNL/oscar-federation-hub) · [50-Lane Regression Suite (`ORNL/oscar-regression`)](https://github.com/ORNL/oscar-regression)

## 3.11.2 (Amber) 2026-11-20

### Commercial Cargo NII (`WCO UFF 2.0` & `UFF 3.0.0`) integration & USB storage-root restore hardening in 3.11.2

- **Commercial Cargo Non-Intrusive Inspection (`WCO UFF 2.0` & `UFF 3.0.0`) Integration (`CargoUffManager`, `UffSmbConnector`, `UffZipReader`, `WcoUffParser`, `CargoUffViewerDialog`, `CargoUffSmbPickerDialog`):**
  - **Zero-Clutter Shipped Default:** Ships **disabled by default** (`enabled = false`). Standalone RPM portals see **zero extra UI buttons, columns, or banners** across Dashboard, Event Log, Lane View, Navbar, and Event Details, and incur **zero background threads or network polls**. Operators at any site can still inspect individual local `.uff` packages (`up to 200 MB`) at any time via **Upload Files** in **Secondary Inspection**, with automatic extraction of embedded `.n42` spectra into Sandia WebID / offline nuclide analysis and untouched **Vehicle ID** auto-population.
  - **Read-Only SMBv2/SMBv3 & Mounted Directory Share Connector (`/extensions` -> Cargo NII):** Connects in user space (`com.hierynomus:smbj:0.13.0`, `4 s` connect / `6 s` read timeouts, AES-256-GCM encrypted credentials in `/var/lib/oscar/extensions/uff/uff-config.json`, automatic `SupportBundleRedactor` scrubbing, zero root `mount.cifs` privilege required) to both hierarchical CIP/NAS date-and-scanner trees (`YYYY/MM/DD/<SCANNER_ID>/<uuid>.uff`) and flat vendor drop-folders (`<uuid>.uff`), indexing multi-gigabyte shares in `< 1 s` cold and `< 15 ms` warm via trailing-`64 KiB` ZIP/ZIP64 Central Directory random access (`UffZipReader`) and XXE-hardened dual `UFF 2.0` / `UFF 3.0.0` XML parsing.
  - **Commercial Operator Selection, Tier-1 UUID Omnibox Lookup & 1-Character Fuzzy OCR Correlation:** Supports automatic container/plate correlation with **1-character visual OCR confusion tolerance** (`0↔O`, `8↔B`, `5↔S`, `2↔Z`, `1↔I`, `6↔G`), interactive scanner-lane & alarm time-window browsing (`Browse Cargo UFF`), direct UFF UUID / `<uuid>.uff` filename / Windows UNC path lookup in **Events (`/event-log`)** for unlabelled **Tier-1** scans, progressive 2-stage radiograph delivery (`preview.jpg` in `< 200 ms` over remote Zero-Trust links followed by full 16-bit `uint16` grayscale TIFF + palettized **HEMD** `Z_eff` PNG on `WebGL2` `R16UI` / `Uint32Array[65536]` LUT), longitudinal **RPM Gamma & Neutron Count Profile** alignment (`Cab Left` ↔ `Cab Right`), and zero-download NAS adjudication staging (`uff-link-<uuid>.uffref.json`). See the [Cargo UFF Integration Guide](https://github.com/ORNL/oscar/blob/main/docs/CARGO_UFF_INTEGRATION.md) and bundled how-to video guide `#27` (`27-cargo-uff-smb-and-xray-inspection`).
- **Canonical 8-Line `.oscar-storage-root` Identity Marker on USB NVMe Restore (`ORNL/oscar#54`):** Updated `oscar-usb-backup.sh` and `oscar-usb-backup.ps1` so cold-iron `usb-backup restore` writes the canonical 8-line `format=oscar-storage-root-identity` marker (`version=1`, `kind=archive`, `deployment_id`, `postgres_cluster_id`, `oscar_state_id`, `archive_root_id`, `created_at`) expected by `oscar-storage.{sh,ps1} archive status` and `oscar verify`, with powered USB 3.x hub guidance documented for bus-powered NVMe enclosures during multi-gigabyte restores.

### Release artifacts — which file to download (`v3.11.2`)

| Release Asset | Target Audience & Use Case |
| :--- | :--- |
| `oscar-3.11.2.zip` (+ `.sha256`) | **Connected Ubuntu Server 24.04 or Windows 11 installations and upgrades.** Includes Docker Compose definitions, Linux/Windows administration CLIs (`oscar.sh` / `oscar.bat`), `configure-ubuntu-host.sh`, `configure-windows-host.ps1`, declarative `ubuntu/` staging templates, application build context, all Markdown documentation (including `CARGO_UFF_INTEGRATION.md`), and all four localized PDF operator manuals. |
| `oscar-3.11.2-ubuntu-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Ubuntu 24.04 LTS installations (or slow hotel Wi-Fi staging) where Docker Engine or internet access is unavailable.** Bundles official Ubuntu 24.04 Docker Engine + Compose v2 + `chrony`/`ethtool`/`nmap`/`arp-scan` `.deb` packages, pre-built container images (`oscar:3.11.2`, `oscar-postgis:3.11.2`, `nginx/nginx-unprivileged:1.30.7-alpine`), bare-metal `create-autoinstall-usb` + `oscar-firstboot-wizard.sh`, and all Markdown/PDF documentation. |
| `oscar-3.11.2-windows-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations where Docker Desktop or WSL 2 is not yet installed.** Bundles pinned Docker Desktop `4.87.0` and WSL `2.7.3` installers, pre-built container images (`oscar:3.11.2`, `oscar-postgis:3.11.2`, `nginx/nginx-unprivileged:1.30.7-alpine`), administration scripts, and all Markdown/PDF documentation. |
| `oscar-3.11.2-windows-x86_64-offline-images.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations or upgrades where compatible Docker Desktop and WSL 2 are already running.** Contains the pre-built container image archive, administration scripts, and documentation without the Windows prerequisite installers. |
| `OSCAR-3.11.2-Administrator-Operator-Manual-{en,es,fr,el}.pdf` | **Standalone localized Administrator and Operator Manuals** in English (`en`), Español (`es`), Français (`fr`), and Ελληνικά (`el`). |
| `oscar-v3.11.2-source.zip` (+ `.sha256`) | **Complete tracked source archive including all submodules** (`osh-core`, `osh-addons`, `osh-oakridge-modules`, and `oscar-viewer`; GitHub's auto-generated source archive omits submodules). |
| `OSCAR-3.11.2-SHA256SUMS.txt` | **Master SHA-256 checksum manifest** covering all release ZIPs and localized PDF manuals. |

## 3.11.1 (Amber) 2026-11-20

### Security, bare-metal provisioning & offline readiness highlights in 3.11.1

- Upgrade the HTTPS gateway and remote-access tunnel base image to `nginx/nginx-unprivileged:1.30.7-alpine`, fixing the November 18, 2026 NGINX vulnerabilities, including CVE-2026-123007, CVE-2026-123633, and CVE-2026-118899. Update connected/offline packaging and invalidate older offline image caches. Existing installations require a rebuilt release and container recreation; changing source files alone does not patch a running gateway.
- Add cross-platform bare-metal Ubuntu 24.04 autoinstall USB builders for Windows 11 (`.\oscar.bat create-autoinstall-usb` / `ubuntu/create-autoinstall-usb.ps1`) and Ubuntu (`sudo bash oscar.sh create-autoinstall-usb` / `ubuntu/create-autoinstall-usb.sh`), plus the interactive post-autoinstall First-Boot Provisioning & Recovery Wizard (`sudo bash oscar.sh wizard` / `sudo oscar-wizard` / `ubuntu/oscar-firstboot-wizard.sh`) supporting read-only USB NVMe backup restore, single-snapshot restore, `config.json` / `lanes.csv` / `.pmtiles` import, and clean site initialization.
- Harden Linux USB-to-NVMe enclosure stability (`Realtek RTL9210`, `JMicron JMS583/562/578`, `ASMedia ASM2362`) across `autoinstall`, `prepare-host`, and `usb-backup` by configuring both `usb-storage` Bulk-Only Transport (`:u`) and `usbcore` No-LPM (`:k`) quirks so Thunderbolt 3/4 and USB 3.2 Gen 2 links cannot lock up during multi-gigabyte verification or restore streams.
- Assign deterministic sensor unique identifiers prior to initial TCP connection attempts in `RapiscanSensor` and `AspectSensor` (matching `RS350Sensor`), ensuring `LaneSystem` and container application readiness (`/tmp/oscar-ready`) start cleanly even when RPMs are powered off or unreachable on air-gapped networks.

### Release overview
OSCAR 3.11.1 (Amber) is re-architected for multi-year, 24/7 operation across up to 50 concurrent radiation portal monitor (RPM) and RTSP camera lanes on **Ubuntu Server 24.04 x86-64** and **Windows 11 x86-64** (with Docker Desktop and WSL 2). Because [`v3.8.0` (2026-09-19)](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/releases/tag/v3.8.0) was the last general-public release prior to the interim `3.8.1`–`3.10.0` builds, the **New features since public release `v3.8.0`** section below summarizes every capability added across `3.8.1` through `3.11.1` in one place.

### Release artifacts — which file to download

| Release Asset | Target Audience & Use Case |
| :--- | :--- |
| `oscar-3.11.1.zip` (+ `.sha256`) | **Connected Ubuntu Server 24.04 or Windows 11 installations and upgrades.** Includes Docker Compose definitions, Linux/Windows administration CLIs (`oscar.sh` / `oscar.bat`), `configure-ubuntu-host.sh`, `configure-windows-host.ps1`, declarative `ubuntu/` staging templates, application build context, all Markdown documentation, and all four localized PDF operator manuals. |
| `oscar-3.11.1-ubuntu-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Ubuntu 24.04 LTS installations (or slow hotel Wi-Fi staging) where Docker Engine or internet access is unavailable.** Bundles official Ubuntu 24.04 Docker Engine + Compose v2 + `chrony`/`ethtool`/`nmap`/`arp-scan` `.deb` packages, pre-built container images (`oscar:3.11.1`, `oscar-postgis:3.11.1`, `nginx/nginx-unprivileged:1.30.7-alpine`), hotel-to-site NIC cutover tools, and all Markdown/PDF documentation. |
| `oscar-3.11.1-windows-x86_64-offline-full.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations where Docker Desktop or WSL 2 is not yet installed.** Bundles pinned Docker Desktop `4.87.0` and WSL `2.7.3` installers, pre-built container images (`oscar:3.11.1`, `oscar-postgis:3.11.1`, `nginx/nginx-unprivileged:1.30.7-alpine`), administration scripts, and all Markdown/PDF documentation. |
| `oscar-3.11.1-windows-x86_64-offline-images.zip` (+ `.sha256`) | **Air-gapped / offline Windows 11 installations or upgrades where compatible Docker Desktop and WSL 2 are already running.** Contains the pre-built container image archive, administration scripts, and documentation without the Windows prerequisite installers. |
| `OSCAR-3.11.1-Administrator-Operator-Manual-{en,es,fr,el}.pdf` | **Standalone localized Administrator and Operator Manuals** in English (`en`), Español (`es`), Français (`fr`), and Ελληνικά (`el`). |
| `oscar-v3.11.1-source.zip` (+ `.sha256`) | **Complete tracked source archive including all submodules** (`osh-core`, `osh-addons`, `osh-oakridge-modules`, and `oscar-viewer`; GitHub's auto-generated source archive omits submodules). |
| `OSCAR-3.11.1-SHA256SUMS.txt` | **Master SHA-256 checksum manifest** covering all release ZIPs and localized PDF manuals. |

### Start here — documentation for new and current users

- **New Users (Fresh Installation):**
  1. Read the [Release Overview, Architectural Rationale, and User Guide](https://github.com/ORNL/oscar/blob/main/docs/RELEASE_NOTES_AND_UPGRADE_GUIDE.md).
  2. Follow the [Quick Start Guide](https://github.com/ORNL/oscar/blob/main/dist/release/QUICKSTART.md) (`.\oscar.bat prepare-host` + `.\oscar.bat init` on Windows 11; `sudo bash oscar.sh init` on Ubuntu 24.04).
  3. Consult the [Administrator Guide](https://github.com/ORNL/oscar/blob/main/dist/release/DEPLOYMENT.md) for LAN/Tailscale TLS trust, firewall scoping, and optional `single`-snapshot backup setup, plus the localized Operator Manuals ([English](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README.md), [Español](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_es.md), [Français](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_fr.md), [Ελληνικά](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_el.md)).
- **Current Users Upgrading from `pre-3.11.0` (`3.10.0`, `3.9.x`, `3.8.x`):**
  - `oscar upgrade` intentionally preserves an existing `config.json` and PostgreSQL volume and **never** silently converts a `pre-3.11.0` database. For full 3.11.1 `PARQUET_PRIMARY` storage and checksummed PostgreSQL, preserve the old deployment read-only after backup/export and initialize a fresh 3.11.1 deployment. If deliberately retaining a legacy volume set in-place, follow the explicit one-time volume/root adoption workflow in the [Release Overview and Upgrade Guide](https://github.com/ORNL/oscar/blob/main/docs/RELEASE_NOTES_AND_UPGRADE_GUIDE.md), [Administrator Guide](https://github.com/ORNL/oscar/blob/main/dist/release/DEPLOYMENT.md), and [Storage Operations Runbook](https://github.com/ORNL/oscar/blob/main/docs/STORAGE_OPERATIONS.md).
- **Current Users Upgrading Same-Profile `3.11.1+` Deployments & Managing Storage:**
  - Extract into a clean sibling directory, copy `.env`, `secrets/`, and `tls/`, and run `oscar upgrade`. See [Storage Architecture](https://github.com/ORNL/oscar/blob/main/docs/STORAGE_ARCHITECTURE.md), [Data Lifecycle Policy](https://github.com/ORNL/oscar/blob/main/docs/DATA_LIFECYCLE.md), [Cold Archive Format](https://github.com/ORNL/oscar/blob/main/docs/ARCHIVE_FORMAT.md), [Continual & Occasional USB NVMe Incremental Backup Guide](https://github.com/ORNL/oscar/blob/main/docs/CONTINUAL_AND_USB_BACKUP_GUIDE.md), [Backup and Restore](https://github.com/ORNL/oscar/blob/main/docs/BACKUP_RESTORE.md), and [Storage Operations](https://github.com/ORNL/oscar/blob/main/docs/STORAGE_OPERATIONS.md).
- **Feature & Developer Guides:**
  - [Ubuntu 24.04 Field Setup, Hotel Staging & Air-Gapped Bare-Metal Guide](https://github.com/ORNL/oscar/blob/main/docs/UBUNTU_FIELD_SETUP_GUIDE.md) · [Operational Views](https://github.com/ORNL/oscar/blob/main/docs/OPERATIONAL_VIEWS.md) · [Status of Health](https://github.com/ORNL/oscar/blob/main/docs/STATUS_OF_HEALTH.md) · [Live Video & Recording](https://github.com/ORNL/oscar/blob/main/docs/LIVE_VIDEO.md) · [EML Integration](https://github.com/ORNL/oscar/blob/main/docs/EML_INTEGRATION.md) · [Pluggable Extensions & Regional Packs (`/extensions`)](https://github.com/ORNL/oscar/blob/main/docs/PLUGGABLE_EXTENSIONS_GUIDE.md) · [RPM & Radiation Detector Driver Integration Guide](https://github.com/ORNL/oscar/blob/main/docs/RADIATION_DETECTOR_DRIVER_GUIDE.md) · [Diagnostic Flight Recorder & Support Bundles](https://github.com/ORNL/oscar/blob/main/docs/DIAGNOSTICS_AND_FLIGHT_RECORDER.md) · [End-to-End Regression & Certification](https://github.com/ORNL/oscar/blob/main/docs/REGRESSION_AND_RELEASE_CERTIFICATION.md) · [Video Workflow Guides (26 Bundled 1080p Modules)](https://github.com/ORNL/oscar/blob/main/docs/VIDEO_GUIDES.md) · [Translation System (`i18n`)](https://github.com/ORNL/oscar/blob/main/docs/TRANSLATION_SYSTEM.md) · [Contributing Guide](https://github.com/ORNL/oscar/blob/main/CONTRIBUTING.md) · [50-Lane Regression Suite (`ORNL/oscar-regression`)](https://github.com/ORNL/oscar-regression) · [Self-Hosted Zero-Trust Hub & Authentik SSO (`ORNL/oscar-federation-hub`)](https://github.com/ORNL/oscar-federation-hub) · [50-Camera RTSP Emulator (`ORNL/Camera-emulator`)](https://github.com/ORNL/Camera-emulator).

### New features since public release `v3.8.0` (`v3.8.0` → `v3.11.1`)

For users upgrading or evaluating OSCAR from [`v3.8.0` (2026-09-19)](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/releases/tag/v3.8.0), the following user-facing and operational capabilities were introduced across `3.8.1`, `3.8.2`, `3.9.0`, `3.9.1`, `3.10.0`, and `3.11.1`:

- **Alarm Adjudication, EML Non-Threat Automation, Extended Occupancy Auto-Adjudication & Event Log Filtering:**
  - **Admin-Uploaded EML Runtime, Pluggable Alarm Assessment API (`EmlAlarmAssessmentAlgorithm`), Pluggable Runtime Extensions Hub (`/extensions`) & Automated `Code 9999: EML Non-Threat` Disposition (`3.11.1`):** Hot-loadable external EML and custom alarm assessment runtime plugin upload (`Services -> OSCAR Service -> EML Plugin Path` or `OSCAR Viewer -> Extensions`, stored privately in `/var/lib/oscar/eml-plugin/` with zero third-party EML artifacts redistributed in public repositories or release bundles), plus a unified **Pluggable Runtime Extensions & Regional Packs** hub (`/extensions` + `/sensorhub/oscar/extensions/*`, documented in [Pluggable Extensions Guide](https://github.com/ORNL/oscar/blob/main/docs/PLUGGABLE_EXTENSIONS_GUIDE.md)) keeping all unrestricted shipped defaults active out of the box while allowing upgrade-safe hot-swapping and 1-click default reset across **Vehicle OCR** (`plate-rules.json` + `.onnx` packs or `OcrEngine` `.jar` SPI), **Offline Regional Basemaps** (`.pmtiles` v3 vector/raster archives in `/var/lib/oscar/extensions/maps-storage/` served via `HTTP 206` with zero external CDN requests), **Secondary Spectroscopy** (`isotope-library.json` or `SpectroscopyIdentificationAlgorithm` `.jar` SPI in `fallback`/`override` mode), **Trusted Enterprise CAs** (`.pem`/`.crt` hot-reload via `DynamicTrustManagerRegistry`), **Agency Adjudication Policy Packs** (`policy-pack.json`), and **EML Alarm Assessment**. Supports both LLNL ERNIE VM-250 archives (`config/vm250Analysis.xml`) and custom developer alarm assessment plugins packaged either as zero-dependency standalone JDK JARs (`Oscar-Alarm-Assessment-Class` in `META-INF/MANIFEST.MF` with `Map<String, Object> evaluate(Map<String, Object>, List<String>)`) or via the typed `org.sensorhub.impl.utils.rad.eml.EmlAlarmAssessmentAlgorithm` `ServiceLoader` SPI (documented in [EML Integration & Custom Alarm Assessment Plugin Guide](https://github.com/ORNL/oscar/blob/main/docs/EML_INTEGRATION.md)). Automatically evaluates Rapiscan VM-250 `GX` spectra prior to publication, suppresses verified EML `RELEASE` non-threat alarms from the Dashboard and browser notifications at `t = 0` while keeping `INVESTIGATE` alarms prominent, persists durable `Code 9999: EML Non-Threat` adjudications with `EML_METADATA` JSON, and renders localized **EML Automated Analysis** cards in Event Details. Fresh installs without an uploaded EML JAR require no extra files and run with full core portal monitoring capabilities.
  - **Extended Occupancy Fault (`Fault - Extended Occupancy`) & Automated `Code 9998: Extended Occupancy Gamma Alarm` Disposition (`3.11.1`):** Each lane configures an **Extended Occupancy Threshold** (`extendedOccupancyThresholdMinutes`, `1`–`1440` minutes, default `1` minute, in SensorHub Admin under **Lane Sensor System -> Extended Occupancy Threshold (min)**). When a vehicle occupies a Rapiscan, Aspect, or RS350 lane past that threshold, OSCAR immediately publishes an `occupancyStatus` fault observation (`extendedOccupancyFault = true`, `alarmState = "Fault - Extended Occupancy"`), activates the **Extended Occupancy** fault indicator on the **Status of Health** page and Dashboard lane card, and counts the fault in National Statistics and Lane Reports until the lane clears. When that extended occupancy completes, if it triggered a **gamma-only alarm** (`gammaAlarm = true` and `neutronAlarm = false`), OSCAR stamps `"extended-occupancy-gamma"` and `"code:9998"` onto `occupancy.adjudicatedIds` prior to publication—suppressing the alarm from the active Dashboard queue and browser notifications at `t = 0` and superseding any pending EML non-threat evaluation—and persists a durable automated `Adjudication` with disposition **`Code 9998: Extended Occupancy Gamma Alarm`** (`username = "AUTO"`, `secondaryInspectionStatus = "NONE"`). Any extended occupancy that includes a **neutron alarm** (`Gamma-Neutron` or `Neutron`) is never auto-adjudicated and remains an active alarm requiring operator adjudication.
  - **Custom Disposition Codes (`3.10.0`) & Full-Database `Adjudication Code` Filtering (`3.11.1`):** Configure site-specific custom disposition codes in SensorHub Admin, display an optional **Adjudication Code** column on the Events page, and filter the full hot PostgreSQL + cold Parquet history by **Adjudication Code** (`equals`, `does not equal`, `is any of`, `is empty`, `is not empty`) across built-in Codes `1–11`, **`Code 9998: Extended Occupancy Gamma Alarm`**, **`Code 9999: EML Non-Threat`**, and custom codes (backed by indexed `"code:<n>"` markers and an asynchronous zero-blocking startup backfill for upgraded systems).
  - **Priority Alarm Ordering (`3.10.0`), 1-Click Chronological Dashboard & Events Toggle (`3.11.1`), Nested `AND`/`OR` Filters, Bulk Adjudication (`3.9.0`, `3.9.1`) & Optional Asynchronous Per-Lane Container/Plate OCR (`3.11.1`):** Automatic alarm priority sorting (`Gamma-Neutron` > `Neutron` > `Gamma`) with a 1-click **Newest first** (`aria-pressed`) toolbar toggle on both **Dashboard** and **Events** (`/event-log`) for purely chronological server-side and live occupancy sorting, full-database server-side nested `AND`/`OR` filter groups (with inclusive numeric `Occupancy ID`, `Max Gamma`, and `Max Neutron` comparisons), cross-page and all-filtered selection with bounded-concurrency **Bulk Adjudication**, direct vehicle ID entry during Dashboard adjudication (`3.9.0`), optional per-lane asynchronous resource-governed hybrid ONNX container/license-plate OCR (`LaneConfig.ocrConfig`, default `enabled = false` with zero overhead on disabled lanes, bundling clean-room `Apache-2.0`/`CC0` Tier-0 `640x384` oriented stencil/plate ROI detection `stencil_det_fp32.onnx` + native-1080p `AffineTransform` deskew + `48px` PP-OCRv3 CTC + gated INT8 `32x128` PARSeq `parseq_rec_int8.onnx` with `~1.13 s` early optical Modulo-11 lock-in alongside two-tier `960px -> 1600px` PP-OCRv3 DBNet fallback, rightward rear-door check-digit strip crop confirmation, and `>= 0.82` single-frame repaired check-digit confidence gating across multi-line ISO 6346 / tractor fleet ID reconstruction, `PARQUET_PRIMARY`-tiered `vehicleOcr` datastreams, date-partitioned `/sensorhub/buckets/ocr/crops/<YYYY-MM-DD>/` long-term evidence crop retention with `ocrCropRetentionDays = 365` aligned with `frame-03.jpg` and preserving held/operator-adjudicated occupancies, ephemeral non-alarm clip cleanup when `alarmsOnly = false`, and Viewer ISO 6346 check-digit / `>= 85%` plate auto-fill + clickable suggestion chips), and deduplicated live + historical adjudication logs (`3.11.1`).
  - **Event UUID Deep Links & Air-Gapped QR / File Alarm Transfer (`3.9.1`, `3.10.0`):** Exact Event UUID lookup from the Events page, shareable node-qualified Event Details URLs (`Share Occupancy`), visible occupancy observation IDs in Event Details and PDF exports, single-code compressed Base45 + SHA-256 **QR code** and portable alarm package export (preserving chart endpoints, extrema, and threshold crossings), and an offline **Alarm Transfer** page with live camera QR scanning and file import.
- **Multi-Gate Operations, Status of Health, Individual Detector Charts & Map Resilience:**
  - **URL-Scoped Operational Views & Top-Bar Scoped View Switcher (`3.9.1`, `3.11.1`):** Workstation-specific URLs (`/view/<slug>`) and the RBAC-aware top-bar **Scoped View** dropdown (`All Lanes` + configured views with lane counts for unrestricted users, or strictly permitted `allowedViews` without `All Lanes` for gate-scoped users) driven by backward-compatible lane CSV keywords (`OperationalViews`) scope lane discovery, Dashboard queues, maps, Event Log queries, National Statistics, reports, Status of Health, and browser alarm notifications to assigned portal groups, with fail-closed access checks on out-of-scope events and explicit result-horizon/truncation notices across all capped UI surfaces.
  - **Status of Health Page & Compact Dashboard Fault Indicators (`3.8.2`, `3.9.1`, `3.11.1`):** Dedicated localized Status of Health page and compact per-lane Dashboard badges tracking independent RPM and camera connectivity plus `Gamma High`, `Gamma Low`, `Neutron High`, `Tamper` (with deterministic Clear baseline on connect), and configurable **Extended Occupancy** faults across Rapiscan, Aspect, and RS350 lanes using bounded 30-second ConSys lateral/DuckDB health batches and independent fault-isolated lane loading (`3.8.2`).
  - **Individual Detector Charting, Live/Historical Daily File Views, Automatic Tight Lane-Extent Map Zoom & Site Diagram Fixes (`3.8.1`, `3.10.0`, `3.11.1`):** Switch between summed and individual gamma/neutron detector traces in both live Lane View and historical Event Details (including first-point Rapiscan neutron capture), inspect raw RPM Daily File messages on historical events and the latest 15 live messages in Lane View, automatically fit the Dashboard, Map, and Operational View maps tightly to the active lane extent (`zoomSnap: 0`, `padding: [14, 14]`, immediate `laneSystem` coordinate seeding, and `(0, 0)` Null Island exclusion) so all 4, 25, or 50 configured lanes are clearly visible without overlap or excess padding, and reliably render OpenStreetMap + uploaded site-diagram bounds (`3.8.1`).
- **Multi-Camera Live RTSP/HLS Video & Five-Frame Retained Alarm Media:**
  - **Loopback `MediaMTX` RTSP Fan-Out, Multi-Camera Lanes & Multi-Viewer HLS Leases (`3.9.1`, `3.10.0`, `3.11.1`):** Embedded loopback `mediamtx` (`1.12.2`) deduplicates identical camera streams to strictly **one** upstream `:554` TCP socket per camera per OSCAR server, pairs with infinite (`-1`) camera reconnects (`3.10.0`), dedicated bounded video executor pools, keyframe-gated HLS startup with localized retry controls, multi-camera lane feed switching, and per-viewer HLS session leases (`X-OSCAR-HLS-Viewer`) so multiple operators can watch the same camera concurrently.
  - **Five-Frame JPEG Evidence Gallery with 24-Hour MP4 Grace (`3.9.1`, `3.11.1`):** Generation-safe keyframe-verified MP4 alarm recording followed by asynchronous extraction of five deterministic sRGB JPEG frames (`FIRST`, `QUARTER`, `MIDDLE`, `THREE_QUARTERS`, `LAST`) per camera, an authenticated Viewer five-frame evidence gallery (with legacy MP4 playback fallback), a 24-hour MP4 rollback grace window, and 30-day secondary-frame pruning retaining `frame-03.jpg` (`MIDDLE`) long-term.
- **Multi-Year 50-Lane Storage (`PARQUET_PRIMARY`), Daily-File Journaling, Backup & Legal Holds:**
  - **`PARQUET_PRIMARY` Tiered Storage Engine Across All 22 Operational & Evidentiary Streams (`3.11.1`):** Stages all 22 operational and evidentiary observation streams (`gammaCounts`, `gammaThreshold`, `neutronCounts`, `setupGamma`, `setupNeutron`, `speed`, `backgroundReport`, `foregroundReport`, `status`, `emlContextual`, `emlScanContextual`, `emlAnalysis`, `dailyFile`, `connectionStatus`, `occupancyStatus`, `tamper`, `occupancy`, `adjudication`, `report`, `siteStatistics`, `nationalSummary`, `vehicleOcr`) into 30-minute `LOGGED` PostgreSQL partitions (`osg_*`), seals parity-verified windows into Zstandard Apache Parquet files (~10–15x smaller on disk), populates `oscar_obs_latest` (for `< 0.5 ms` `resultTime=latest` / `phenomenonTime=latest` lookups), 22 per-generation summary counters on `oscar_archive_schema` (for `< 1 ms` SQL alarm/fault/adjudication counts and zero-match generation pruning), and `oscar_event_locator`, retires stage partitions via `O(1)` `NO INHERIT` + `DROP TABLE`, reconciles existing routes and retroactively drains and compacts (`VACUUM (FULL, ANALYZE) ONLY obs`) legacy parent-table rows to Parquet on startup, leaving only ~52 static singleton configuration rows (`sensorLocation`, `adjudicationCodes`, `siteInfo`) in `ONLY oscar.obs`, and federates hot PostgreSQL + cold Parquet queries transparently through embedded DuckDB with CQL2 `!=` and JSONB array pushdown.
  - **Overlay-Backed Append-Only Adjudication Trail, Datastream-Scoped Tombstones, Coalesced Camera Heartbeats & 24-Hour Transient Command Pruning (`3.11.1`):** Records adjudications of archived `occupancy` rows in `oscar_obs_overlay` + `oscar_obs_latest` while scoping `countObservationMutations(Set<Long> dataStreams)` and `oscar_tombstone (obs_id, datastream_id)` to the queried datastreams (so tombstone checks and `resultTime=latest` pushdown stay `O(1)` per queried stream and preserve bounded `saturateAdd(limit, mutationCount)` pagination), skips row-wise `DatabasePurger` observation deletes when `PARQUET_PRIMARY` stage retirement is active so zero `oscar_tombstone` rows are created, coalesces unchanged background camera `connectionStatus` heartbeats in `FFMPEGSensor` to 15-minute intervals while publishing state transitions immediately and resetting the heartbeat timer on reconnect after confirm-after-connect verification, deduplicates `adjudicationCodes` on startup, and prunes completed transient non-`adjudicationControl` commands (`fileControl`, `hlsControl`) in `cmd`/`commandstatus` older than 24 hours (`PostgisCommandStoreImpl.purgeCompletedTransientCommandsBefore`).
  - **Pre-Parse Daily-File Journal & Dual UTC/Local Timestamps (`3.10.0`, `3.11.1`):** `DailyFileJournalService` captures `CRC32C`-framed raw Rapiscan, RS350, and Aspect messages on disk before parsing, publishes immutable legacy-compatible daily CSVs with UTC and wizard-configured local timestamps plus SHA-256 manifests, and bounds sealed journals after 30 days.
  - **Zero-Downtime Continual & Occasional USB NVMe Incremental Backup (`usb-backup` CLI + `/usb-backups` Browser Admin Panel), Field Laptop Offload, Single-Snapshot Backup, Legal Holds & Serialized Statistics (`3.11.1`):** Defaults to `OSCAR_BACKUP_MODE=disabled` (`archive_mode=off` to prevent unattended WAL disk exhaustion) and supports both **(a)** zero-downtime (`0.0 s` portal outage, `Nice=19` / `IOSchedulingClass=idle` / `--cpus=1` isolated) **Continual & Occasional USB NVMe Incremental Backups** managed either from the localized **OSCAR Viewer → USB Backups (`/usb-backups`)** Admin Panel (`UsbBackupControlBridge` + host `oscar-usb-backup-agent` watcher, zero `docker.sock` exposure) or via `oscar.sh usb-backup` / `oscar.bat usb-backup` (`oscar-usb-backup.{sh,ps1}` and `oscar-usb-backup-engine.sh`) with `O(1)` sealed daily `.tar` packs (`~1.03x` disk overhead for `400+ GiB` 5-year archives), 1-click/1-command live mode switching (`continual` <-> `occasional` <-> `disabled`), safe `eject` (`SAFE_TO_UNPLUG`) + cross-platform `NTFS` laptop delta copy (`COPY-TO-ANOTHER-DRIVE.bat` / `copy-to-another-drive.sh`) + automatic `udev`/Scheduled-Task reconnect catch-up of all data recorded while unplugged, 1-click `oscar-backup-key.txt` off-site escrow download, and 1-command bare-metal server migration (`usb-backup restore`), alongside **(b)** opt-in quiesced `single` mode (`oscar backup`), transactional observation/generation legal holds (`oscar_retention_hold`), audited two-step cold deletion, portable Parquet export packages, and serialized National Statistics refreshes.
- **Complete 4-Language Localization (`en`, `es`, `fr`, `el`), Bundled Offline Workflow Video Guides & Published PDF Manuals (`3.9.0`–`3.11.1`):**
  - Extends `v3.8.0`'s initial i18n foundation across all `737` Viewer UI keys, `/login` authentication, OpenSensorHub Vaadin Admin `ConfigMessages`, live/historical alarm statuses, custom disposition codes, 26 captioned 1080p workflow video guides ([`ORNL/oscar-video-guides`](https://github.com/ORNL/oscar-video-guides), `~32.1 MiB` total, also bundled directly inside OSCAR at `/video-guides/` with `text/vtt;charset=utf-8` WebVTT captions for 100% offline/air-gapped contextual click-to-play playback in Viewer `Help (?)` and all 20 localized SensorHub Admin module `README` tabs), and **four screenshot-complete localized Administrator & Operator Manual PDFs** published with every GitHub Release (`0 px` horizontal overflow at `1920x1080` and `1280x800`).
- **Vector PDFBox 3 Reports, Multi-Format Secondary Spectroscopy & Offline Photopeak Identification, Log-by-Default Spectrograms, UpSet Co-Occurrence Analytics, Consolidated `Vehicle Incident Report` (`VEHICLE_INCIDENT`), `Adjudication Details` (`PDF`/`CSV`/`JSON`/`XLSX`), Multi-Pass Vehicle ID Search & Comparison, 5.4x Faster 30-Day Lane Reports & Android PWA Install (`3.11.1`):**
  - Replaces legacy rasterized report generation with crisp pure-vector Apache PDFBox 3 + JFreeChart PDFs, adds multi-format secondary-inspection spectroscopy upload and playback (`.n42`, Ortec ASCII `.spe`, Ortec/Canberra binary `.spc`, and `.xml`) with energy-calibration resolution, automatic local photopeak nuclide identification fallback when Sandia Full Spectrum WebID is offline, and logarithmic-by-default gamma energy spectrograms (`Counts (Log)`) with an accessible 1-click `Log` / `Linear` scale toggle, adds **UpSet** co-occurrence intersection analytics across the Event Log and `Event` / `Adjudication` / `Vehicle Incident` PDF & JSON reports, adds normalized **Vehicle ID Search, Multi-Occupancy Pass Comparison (`VehiclePassComparisonDialog`), Cross-Node Linked Adjudication, and Consolidated `Vehicle Incident Report` (`VEHICLE_INCIDENT` in `PDF`, `CSV`, `JSON`, and `Excel .xlsx`)** across single-node and federated deployments (`GET /buckets/adjudication/vehicle-search` + `VehicleIncidentAggregator` over `Adjudication` and `vehicleOcr` with schema-aware Rapiscan/Aspect/RS350 gross-count profile extraction, `profileOnlyObsIds` sub-second radiation trace hydration, zero new PostgreSQL tables, and 100% `PARQUET_PRIMARY` stage-partition compatibility), splits itemized adjudication records into a dedicated **`Adjudication Details`** report (`PDF`, `CSV`, `JSON`, and native streaming Apache POI `.xlsx` with inline Viewer previews while omitting zero-count isotopes in the summary `Adjudication Report`), counts `eml-non-threat` occupancy suppressions accurately in `RDS Site` and `Event` reports, adds separate `Open` and `?download=1` `Download` actions plus `2.5 s` + `visibilitychange` status polling, accelerates 50-lane / 30-day `Lane Reports` ~5.4x via index-backed occupancy counts and multi-branch Parquet CQL prefiltering, retains daily-file occupancy windows across midnight rollover via a bounded slice API, and enables credentialed `<link rel="manifest" crossOrigin="use-credentials" />` Android Chrome PWA installation behind session auth.
- **Ubuntu 24.04 & Unattended Windows 11 Deployment, Non-IT Identity & Offline Passkeys, Air-Gapped Bundles, Support Bundles & Security Hardening (`3.9.0`–`3.11.1`):**
  - Connected (`oscar-3.11.1.zip`) and air-gapped Windows 11 (`offline-full` and `offline-images`) bundles, `configure-windows-host.ps1` (`prepare-host` / `host-check` across `21` automated checks including Modern Standby `VIDEOIDLE = 0`, AC low-latency processor EPP scheduling, pre-login `S4U` Docker Desktop boot startup, `.wslconfig` memory caps + opt-in `-WslNetworkingMode mirrored`, and bugcheck auto-reboot), disk-proportional (`2–8 GiB`) WSL 2 native `ext4` Parquet caching (`Local9pParquetCache`), LAN/Tailscale SAN TLS auto-generation, non-IT **Users & Access (`/users`)** console with persistent "Stay Signed In Until Logout" SHA-256 session digests (`.moduledata/oscar-identity.json`), automatic `secrets/oscar-admin-password.txt` bootstrap password scrubbing (`# CONSUMED_AT_INIT`), pure-Java offline WebAuthn / FIDO2 Passkeys (`ES256`/`RS256`) and phone-free PBKDF2 temporary/local passwords, **Bulk CSV/Paste User Enrollment** with ready-to-send startup text messages and single-use 1-tap Passkey/Password setup QR codes (`/login/enroll?token=oscar_inv_...`), `Administrator` / `Operator` / read-only `Viewer` roles with Operational View user scoping, scoped Federation Service Tokens (`oscar_fed_<shortId>_<secret>` over HTTP `Bearer` + MQTT `svc-fed-<shortId>`), optional Corporate OIDC + PKCE and Trusted Tunnel SSO, Octelium `remote-access/` encrypted backup/restore + `oscar upgrade` tunnel lockstep (`sync --rebuild`), 1-click Viewer **Export Support Bundle** (`Help (?)` + `/sensorhub/buckets/reports/support-bundle` over bounded `50 MB` rolling `oscar.log`) and offline/crash-loop-capable host CLI `oscar.sh support-bundle` / `oscar.bat support-bundle` with automatic credential/PII redaction, Sentry.io removal (`3.9.0`), Next.js 16 + React 19 upgrade (`3.9.1`), browser autoplay resilience (`3.9.0`), and automated 50-lane + 6-physical-camera end-to-end certification.

### Why the major architectural changes in 3.11.1 were implemented

- **Why `PARQUET_PRIMARY` Tiered Storage Replaced Single-Table PostgreSQL Detector Retention:** At a 50-lane site emitting 1 Hz gamma/neutron telemetry, single-table PostgreSQL JSONB retention generated millions of rows per day and severe MVCC dead-tuple bloat, autovacuum I/O contention, WAL amplification, and multi-gigabyte B-tree/GIN index fragmentation during row-by-row retention deletes. Staging immutable detector streams into 30-minute `LOGGED` PostgreSQL partitions (`osg_*`), sealing parity-verified windows into Zstandard-compressed Apache Parquet files (~10–15x smaller on disk), retiring whole stage partitions via `O(1)` `NO INHERIT` + `DROP TABLE`, and federating hot + cold reads through embedded DuckDB eliminates `DELETE` bloat, keeps PostgreSQL compact (~9–12 GiB), speeds up multi-day historical CQL/report scans ~19x, and preserves 100% OpenSensorHub `IObsSystemDatabase` / `ConSys` / CQL2 compatibility.
- **Why Five-Frame JPEG Media Replaced Long-Term Raw MP4 Storage:** Retaining full H.264 MP4 clips across 50 cameras consumes terabytes rapidly, while video re-encoding was CPU-heavy and brittle on 1-second occupancies. Asynchronous extraction of five deterministic baseline sRGB JPEGs (`FIRST`, `QUARTER`, `MIDDLE`, `THREE_QUARTERS`, `LAST`) with a 24-hour MP4 rollback grace and 30-day secondary-frame pruning (keeping `MIDDLE` / `frame-03.jpg` long-term) preserves visual evidence at a small fraction of MP4 disk usage.
- **Why Direct Pre-Parse Daily-File Journaling Was Added:** Reconstructing vendor daily CSVs from parsed database rows risked losing raw messages across restarts or parser errors and caused startup spikes on 50-lane systems. `DailyFileJournalService` records `CRC32C`-framed vendor messages on disk before parsing and decouples historical day rendering from live ingestion.
- **Why Schema-v2 Single-Snapshot Backup (`archive_mode=off`) Replaced Continuous External WAL Archiving:** Continuous external WAL archiving risked silent disk exhaustion on unattended servers if backup storage disconnected, while multiple local cold-tier copies multiplied storage cost. Opt-in `single` mode uses streamed `pg_basebackup`, `pg_verifybackup`, HMAC-SHA-256 inventory verification, and an atomic `CURRENT` pointer for self-contained same-host or cross-host recovery.
- **Why Operational Views, Batched Status of Health, Event UUID/QR & Serialized Statistics Were Built:** Multi-gate sites needed URL-scoped workstation views (`/view/<slug>`) so gate consoles subscribe only to assigned lanes; bounded 30-second health batching and keyframe-gated HLS recovery so 50-lane dashboards and cameras never stall browsers; single-code QR export/import for air-gapped alarm handoff; and serialized National Statistics refreshes so archive scans cannot overlap.
- **Why Windows 11 Modern Standby (`S0 Low Power Idle`) & Pre-Login Docker Hardening Were Added:** Endurance testing on Windows 11 Modern Standby hardware proved that AC display blanking (`VIDEOIDLE > 0`) triggers `Kernel-Power 506` idle suspension even when `STANDBYIDLE = 0`, and that Docker Desktop does not start after an unattended power-loss reboot until interactive login. `configure-windows-host.ps1` (`prepare-host` / `host-check`) now enforces `VIDEOIDLE = 0` on Modern Standby systems, registers `OSCAR-DockerDesktop-BootStart` (`LogonType=S4U`) for pre-login container startup, caps WSL 2 memory via `.wslconfig`, verifies NIC IPv4 stability, and enables bugcheck auto-reboot across 20 automated checks.
- **Why External EML Runtime Plugin Upload (`Code 9999`), Extended Occupancy Gamma Auto-Adjudication (`Code 9998`) & Adjudication Code Filtering Were Added:** Separately licensed EML libraries and models cannot be redistributed in public open-source repositories, while benign NORM cargo alarms on high-throughput Rapiscan VM-250 portals and gamma background-integration alarms caused by stationary vehicles holding a lane past the extended-occupancy threshold otherwise flood the Dashboard queue. A hot-loadable `EmlRuntimeRegistry` (`emlPluginPath` in `/var/lib/oscar/eml-plugin/`) suppresses verified EML `RELEASE` non-threat alarms at `t = 0` and records durable `Code 9999: EML Non-Threat` adjudications with `EML_METADATA` JSON; likewise, when a vehicle exceeds the lane's `extendedOccupancyThresholdMinutes` (`Fault - Extended Occupancy`), `OccupancyWrapper` automatically adjudicates gamma-only alarms (`gammaAlarm = true`, `neutronAlarm = false`) at `t = 0` with `Code 9998: Extended Occupancy Gamma Alarm` (`"extended-occupancy-gamma"` / `"code:9998"`) while keeping any neutron-bearing alarm active. Both automated disposition codes and built-in/custom codes are queryable via indexed full-database **Adjudication Code** filtering (`"code:<n>"` markers with an asynchronous startup backfill for existing deployments).

### How OSCAR 3.11.1 handles data now across all storage tiers

- **1. Operational, Evidentiary, Status, Report, EML & Vehicle OCR Streams (`PARQUET_PRIMARY` — 22 Allowlisted Outputs):**
  - `gammaCounts`, `gammaThreshold`, `neutronCounts`, `setupGamma`, `setupNeutron`, `speed`, `backgroundReport`, `foregroundReport`, `status`, `emlContextual`, `emlScanContextual`, `emlAnalysis`, `dailyFile`, `connectionStatus`, `occupancyStatus`, `tamper`, `occupancy`, `adjudication`, `report`, `siteStatistics`, `nationalSummary`, and `vehicleOcr` commit in bounded batches (`10,000` rows or `1 s`) into UTC-aligned 30-minute `LOGGED` PostgreSQL stage partitions (`osg_*`). Five minutes after each 30-minute window closes, a 1-minute background worker exports the window into ZSTD-compressed Apache Parquet (`archive/datasets/observations/date=YYYY-MM-DD/profile=RAW_GATED/`), populates `oscar_obs_latest`, 22 per-generation summary counters on `oscar_archive_schema`, and `oscar_event_locator`, verifies SHA-256 and exact row/UUID parity, and drops the stage child via `O(1)` `NO INHERIT` + `DROP TABLE`.
  - On startup, `ImmutableObservationStageManager.reconcileRoutes()` upgrades existing `oscar_obs_storage_route` rows for all 22 outputs to `immutable=true`, `reclaimEmptyOrRetiredStages()` drops empty expired `ATTACHED` and leftover `DETACHED` stage partitions, and `ArchiveLifecycleManager` retroactively exports any legacy unarchived rows sitting in `ONLY oscar.obs` for newly-promoted immutable streams into Parquet generations before deleting the migrated parent rows and compacting `ONLY oscar.obs` via `VACUUM (FULL, ANALYZE) ONLY obs`.
- **2. Overlay-Backed Append-Only Adjudication Updates & Static Singleton Reference Streams:**
  - Static singleton configuration streams (`sensorLocation`, `adjudicationCodes`, `siteInfo`, ~52 rows total across 50 lanes) remain in `ONLY oscar.obs` (`immutable=false`), with prior `adjudicationCodes` rows deduplicated on startup.
  - Every operator or automated adjudication (`AdjudicationControl`) is strictly **append-only**: it inserts a new `adjudication` observation and updates the parent `occupancy` row's `adjudicatedIds` JSONB array (appending the command ID and updating the `"code:<n>"` disposition marker). When an archived `occupancy` in a cold Parquet generation is adjudicated or re-adjudicated, `OscarTieredObsStore.put()` records the updated `occupancy` in `oscar_obs_overlay` and synchronizes `oscar_obs_latest` without rewriting Parquet.
- **3. Coalesced Camera Heartbeats & Stage-Retirement-Aware Maintenance:**
  - `FFMPEGSensor` coalesces unchanged background camera `connectionStatus` heartbeats to 15-minute intervals while publishing state transitions immediately, and `oscar_obs_latest` serves `< 0.5 ms` `resultTime=latest` / `phenomenonTime=latest` queries across all streams.
  - When `PARQUET_PRIMARY` stage retirement is active, `DatabasePurger` skips row-wise observation deletes so zero `oscar_tombstone` rows are created; when `PARQUET_PRIMARY` is disabled, `DatabasePurger` purges expired `connectionStatus`, routine `Clear` `occupancyStatus`, and manifest-validated `dailyFile` rows from `ONLY oscar.obs` via `obs_mutable_datastream_phenomenon_idx`.
- **4. Operational vs. Audit Command Streams (`cmd_commands` & `cmd_status` — 24-Hour Pruning):**
  - `DatabasePurger.purgeOldCommands()` runs hourly and deletes transient operational commands (`streamControl`, `videoControl`, `ptzControl`, `hlsControl`, `oscarServiceControl`) older than **24 hours** along with their cascading `cmd_status` rows (`PostgisCommandStoreImpl` + `PostgisCommandStatusStore`), while permanently preserving all `%adjudicate%` and audit command records.
- **5. Pre-Parse Daily-File Journal (`DailyFileJournalService`) & Retained Five-Frame Alarm Media:**
  - Raw Rapiscan, RS350, and Aspect messages are synchronously appended before parsing into `CRC32C`-framed `.open` segments (`files/.dailyfile-journal`), published at UTC midnight to immutable daily CSVs + SHA-256 manifests (`files/dailyfiles/`), served across midnight boundaries via `/buckets/dailyfiles/dailyfile-slice`, and cleaned from `.dailyfile-journal` after 30 days following exact replay verification.
  - Camera demuxers (`MpegTsProcessor`, `FileOutput`) reuse a single pre-allocated native `AVPacket` (`av_packet_unref` + `1 ms` `EAGAIN` yield). Completed alarm MP4 clips are immediately converted into five sRGB JPEGs (`FIRST`, `QUARTER`, `MIDDLE`, `THREE_QUARTERS`, `LAST`), source MP4s expire after a 24-hour rollback grace, and secondary frames prune after 30 days while `frame-03.jpg` (`MIDDLE`) remains online long-term.

### Storage-profile changes and rollout
- Introduce the `OscarTieredObsSystemDatabase` storage profile with sequential observation IDs, batched writes, compact short-lived stage ownership, and a versioned PostgreSQL archive catalog
- Initialize new PostgreSQL clusters with data checksums, WAL compression, I/O timing, and `pg_stat_statements`, while explicitly keeping `archive_mode=off` and omitting any external WAL bind; an existing cluster is not recreated by `upgrade`
- Preserve an upgraded deployment's saved `config.json` and database, so a pre-3.11.0 deployment is not silently converted to the complete 3.11.1 storage profile
- Require a fresh 3.11.1 database and standard configuration for the current test systems and new production deployments; preserve any required pre-3.11.0 production history through a separately validated migration
- Make fresh 3.11.1 deployments explicitly use `PARQUET_PRIMARY` for all 22 allowlisted operational and evidentiary outputs (`gammaCounts`, `gammaThreshold`, `neutronCounts`, `setupGamma`, `setupNeutron`, `speed`, `backgroundReport`, `foregroundReport`, `status`, `emlContextual`, `emlScanContextual`, `emlAnalysis`, `dailyFile`, `connectionStatus`, `occupancyStatus`, `tamper`, `occupancy`, `adjudication`, `report`, `siteStatistics`, `nationalSummary`, `vehicleOcr`): route each accepted value into a LOGGED, UTC-aligned 30-minute PostgreSQL staging partition, reconcile existing `oscar_obs_storage_route` entries and retroactively migrate and compact (`VACUUM (FULL, ANALYZE) ONLY obs`) legacy unarchived parent-table rows to Parquet on startup, reject detector timestamps more than five minutes ahead of the database receipt clock, and run the Parquet-primary worker every minute with a five-minute closed-window safety delay
- Publish Parquet, schema, and manifest objects before manifest-last catalog activation; record exact ownership in a compact short-lived ledger, re-hash the active Parquet object and require exact row/UUID parity, then transactionally detach and drop the complete staging relation instead of retaining raw detector rows for a three-day overlap or deleting them row by row; retire at most eight staging partitions per cycle
- Keep Parquet and published daily files as the durable long-term representations of allowlisted detector data while retaining mutable occupancy/alarm workflows, adjudications, reports, small OSH metadata, archive control records, overlays, and tombstones in PostgreSQL; the normal healthy staging budget is at most 60 minutes but is an operational SLO rather than a hard deadline during backlog or failure
- Omit the generic observation-payload GIN index and heavy event indexes from fresh `PARQUET_PRIMARY` staging children, while keeping lean routing/parity indexes on those short-lived relations and purpose-built event indexes on the PostgreSQL parent for mutable workflows; ordinary PostGIS, `HOT_RETENTION`, and existing schemas are unchanged
- Replace aging-video keyframe reduction with an additive exact-five JPEG retained-media format; keep the legacy occupancy `videoPaths` field and Viewer playback fallback for old/unconverted events
- Make completed alarm video immediately eligible for asynchronous five-JPEG conversion on the next retention scan, preserve the source MP4 for 24 hours after verified publication, and keep every failed/fewer-than-five-frame source intact
- Make new self-signed deployments LAN/Tailscale-ready by adding active non-container LAN IPv4, stable Tailscale IPv4/IPv6, and discoverable MagicDNS identity to certificate SANs, accepting explicit additional DNS/IP SANs, validating every requested identity, and printing covered client URLs plus a verifiable public-certificate fingerprint

### Statistics reliability and resource control
- Serialize scheduled and operator-requested full National Statistics publications, use fixed-delay scheduling, and retain cancellable datastore shutdown so long archive-backed scans cannot overlap and multiply CPU, memory, or scratch-space pressure
- Return a terminal `COMPLETED` command only after a newly persisted statistics observation is available, preserve legacy statistics timestamp decoding without double-counting history, and use strictly increasing millisecond cutoffs with open-lower incremental ranges
- Keep the Viewer busy until the durable command status is terminal, fetch the exact returned observation instead of an older `latest` result, fail visibly on terminal command errors, and cancel stale UI work when the node or operational-view scope changes
- Execute operational-view range scans sequentially, disable duplicate refresh controls while initial or manual work is active, and regression-test the exact command, observation, rendered counts, and resource-safe lifecycle

### Storage and data lifecycle
- Add a crash-recoverable, per-lane direct daily-file journal that captures Rapiscan and RS350 input before parsing and Aspect register snapshots before observation publication
- Make the daily journal a required driver dependency by default so startup or append failures cannot silently bypass source-record capture
- Frame journal records with timestamp, length, and CRC32C; bound unforced data by time, record count, and byte count; recover only incomplete tails and fail visibly on complete-frame corruption
- Decouple journal readiness from historical backlog recovery: recover the current lane before its first append, process older lane/days in bounded background batches without holding live writer locks, and skip re-rendering complete durable publications so a restart cannot time out every RPM or repeat a large CPU/I/O spike
- Durably create every journal and retained-media directory component with parent-directory synchronization; surface permission and filesystem failures instead of treating them as platform fallbacks
- Make daily-journal shutdown bounded and fail-visible: service stop first closes admission, drains active sensor writer handles while allowing their final records and keeping periodic fsync active, then stops maintenance and forces/closes every lane; a timed close fails module shutdown instead of silently abandoning an unclosed writer
- Mark Rapiscan, RS350, and Aspect readers as stopping before transport teardown and join source workers before releasing their journal handles, so expected disconnects do not produce false errors and a final source record already in durable I/O cannot race sensor shutdown; RS350 releases its source writer independently of deferred WebID cleanup
- Serialize supported stop, restart, upgrade preparation, and restore shutdown as gateway, then OSCAR, then PostgreSQL on both Ubuntu and Windows; PostgreSQL remains available through OSCAR's bounded writer/module drain instead of receiving a concurrent Compose stop signal
- Publish immutable legacy daily CSVs with exact time-zone windows, SHA-256 manifests, atomic commit ordering, and a manifest-gated compatibility-observation cleanup path
- Retry the bounded daily-file cleanup on every hourly maintenance pass after the midnight attempt, isolate it from unrelated purge failures, and retain all unsealed current-day compatibility rows until manifest-validated publication
- Bound private daily-journal storage even when managed backup is disabled: after 30 days from the later of day close or publication, freeze and delete a sealed day only after immutable CSV/manifest/ledger validation and exact journal-to-CSV replay; retain an opt-in accepted-backup gate for sites that require it
- Replace startup and once-per-minute all-history journal enumeration with durable bounded lifecycle work queues, and recover interrupted staged deletion without discarding a late or unverified segment
- Batch observation inserts with immediate `DataBlock` snapshots, prepared statements, PostgreSQL batch rewriting, and one statement-level datastream-range update per batch
- Correct observation natural-key uniqueness for null fields, make exact replays idempotent and same-key corrections last-write-wins under the stable OSH ID, route archived corrections through generation-owned overlays even after primary-stage retirement, fail index creation visibly when a legacy database contains ambiguous duplicates, and use the full expression index for natural-key conflict lookups even under PostgreSQL generic prepared plans
- Preserve the sequential observation-ID high-water from every cataloged archive state so a restart cannot reuse public IDs after a cold copy is cataloged and the corresponding primary stage is retired
- Export configured high-volume detector streams from a read-only repeatable-read snapshot into Hive-partitioned, sorted, ZSTD Parquet generations with gzip OSH datastream-schema snapshots
- Prevent dense-window Parquet retries from exhausting DuckDB memory by clearing bounded 500-row insertion batches and publishing memory-derived deterministic same-window prefixes; retries reuse the failed job (including exact legacy sub-hour windows), empty reclaimed attempts terminate as audited `SUPERSEDED` no-ops, later prefixes become ordinary revisions, and no unverified stage child is dropped
- Verify Parquet count/ID range before activation, publish manifests last, and atomically record exact ownership in a compact temporary ledger so late arrivals remain eligible for later generations
- Serialize archive activation/sealing against ingestion, updates, removals, overlays, tombstones, and stage detach/drop with transaction-scoped store and ordered observation locks, while keeping file export outside the critical section
- Merge PostgreSQL and catalog-authorized Parquet reads behind the OSH observation-store contract, preferring the staged overlap and applying archived overlays and tombstones without rewriting immutable files
- Push mutation-free explicit-stream `resultTime=latest` queries into indexed PostgreSQL lateral probes and DuckDB latest-per-stream reduction before merging the two tiers, so health refreshes read at most one staged and one cold candidate per stream instead of paging the complete detector history
- Implement PostgreSQL feature-parent lookup through the standard OSH datastore contract, so lane-scoped retention and purge code resolves the authoritative lane system instead of silently falling back to a child RPM identity
- Preserve open and closed temporal bounds through archive candidate pruning and DuckDB pushdown so cold selection, count, limit, and filtered removal match hot PostgreSQL semantics
- Add exact hot/cold row-digest parity receipts and whole-child primary-stage retirement; retain configurable rollback grace, bounded exact-ID deletion, and deferred sealing only for `HOT_RETENTION` compatibility, while generation/observation holds protect authoritative cold data
- Add versioned archive jobs, generations, objects, ID blocks, schemas, locators, overlays, tombstones, holds, verifications, deletion plans/ledger, media records, and backup epochs
- Compact processed-observation and deletion metadata behind restart-safe cursors so long-running systems do not accumulate unbounded bookkeeping rows
- Add embedded DuckDB query pushdown over explicit catalog-authorized file lists and portable generation export for independent Parquet inspection
- Bound every embedded DuckDB export, parity, deletion, query, metadata, and count connection to production-configurable memory, thread, and per-operation spill limits; add fair process-wide session admission with a bounded fail-busy wait; confine sensitive scratch to private disjoint directories and remove it on normal close
- Keep general-purpose container temporary storage `noexec` while routing JVM native-library extraction to a bounded, owner-only executable tmpfs that is verified before startup
- Preserve 64-bit Admin configuration values with type-correct Long, Integer, Short, and range converters, including the 2 GiB archive-generation limit, instead of narrowing every whole number through a 32-bit converter
- Bound Viewer health snapshots to ten stream IDs per request with two global workers and a ten-second per-batch deadline, preventing large accumulated databases from leaving every RPM and camera indicator stuck at `Waiting`
- Persist the successfully uploaded lane-CSV bucket key in the OSCAR Service configuration, so Apply Changes plus the global Save action recreates live Lane, RPM, and camera modules after a supported restart instead of leaving only historical system records in PostgreSQL
- Serialize the legacy ERNIE VM250 XML-schema initialization across Rapiscan lanes, preventing 50-lane Windows restarts from racing the process-global registry and leaving apparently Started RPM modules with an unusable analyzer
- Replace bundled EML libraries and model configs with an administrator-uploaded runtime plugin (`Services -> OSCAR Service -> EML Plugin Path`, stored privately in `/var/lib/oscar/eml-plugin/`, extracted onto `/tmp/oscar-eml-runtime`, and hot-loaded via an isolated `URLClassLoader`), enforce fail-closed packaging checks against redistributing EML artifacts, suppress EML `RELEASE` non-threat alarms from the Dashboard and browser notifications, and automatically record `Code 9999` (`EML Non-Threat`) adjudications with structured `EML_METADATA` JSON queryable via CQL2 (`adjudicatedIds='eml-non-threat'`) across PostgreSQL GIN and DuckDB Parquet and inspectable in Event Details across all four locales (`en`, `es`, `fr`, `el`)
- Accept provisional Java `Instant.MAX` (`+1000000000-12-31T23:59:59.999999999Z`) `rollbackDeleteAfter` timestamps in Viewer retained-media validation and downgrade benign browser/MQTT client disconnect EOF exceptions in `RestApiServlet` and `WebSocketProxy` from `ERROR`/`WARN` to `DEBUG`

### Media retention
- Serialize recording commands in a bounded per-camera FIFO and use generation-qualified filenames so reconnects and back-to-back occupancies cannot finalize or reuse another recording's clip
- Acknowledge occupancy MP4 OPEN only after the current recording generation has successfully muxed its first keyframe; bound readiness to five seconds, wake on stop/failure, reject stale generations, and remove the hidden partial instead of producing a zero-packet alarm clip
- Bind every published recording to its exact lane, camera, and alarm; reject blank, duplicate, cross-camera, stale-generation, or otherwise unowned paths instead of attaching them heuristically
- Cancel non-alarm recordings and fail closed on close timeouts, invalid output, or publication failure, while retaining authoritative late-close cleanup so delayed camera work cannot leave an orphaned clip
- Make camera, occupancy, and state-listener delivery race-safe so lifecycle transitions cannot lose, duplicate, or leak recording callbacks
- Retain exactly five distinct decoded positions (`FIRST`, `QUARTER`, `MIDDLE`, `THREE_QUARTERS`, and `LAST`) from each eligible alarm camera clip
- Give short saved alarm recordings a bounded post-roll until at least five video packets have been muxed, so one-second occupancies remain eligible for five-frame retention
- Encode each retained asset as an independently decodable opaque baseline sRGB JPEG with configurable quality (85 by default), SHA-256, dimensions, decoded ordinal, source PTS, and lifecycle metadata
- Publish frames before a versioned manifest commit marker, use a durable identity-keyed job ledger for idempotent retry, and preserve the source MP4 on every failure or fewer-than-five-frame result
- Fail closed unless retained media can resolve the authoritative `urn:osh:system:lane:*` parent, preventing a camera set from being committed under an RPM UID
- Bind each retention scan to a cancellable PostgreSQL operation and honor interruption between bounded maintenance items, allowing the supported OSCAR-before-PostgreSQL restart sequence to drain a historical backlog without leaving a database query running
- Preserve a successfully converted source for a configurable 24-hour rollback grace and delete it only on a later verified, unheld lifecycle pass
- Set the production profile to zero-day five-JPEG eligibility, scan asynchronous work in bounded five-minute windows, cache occupancy datastream IDs for 15 minutes, and persist bounded late-arrival plus repeating historical reconciliation cursors so restarts, delayed commits, and clock corrections do not skip eligible media
- Add an authenticated read-only event media API and Viewer five-frame gallery, with `404` fallback to unchanged legacy video playback
- Enforce streaming catalog/asset transfer limits plus bounded retained-media camera, frame-byte, dimension, decoded-pixel, and event-wide budgets in the Viewer; fetch only each camera's selected frame and limit event-wide frame-request concurrency
- Restrict storage-pressure cleanup to complete cataloged media sets, honor holds and source grace, publish `DELETING` before removal, and leave legacy video, daily files, adjudications, reports, and archives untouched

### Backup, deletion, and operations
- Default fresh deployments to `OSCAR_BACKUP_MODE=disabled`; require explicit `single` opt-in and an operator-selected safe absolute non-overlapping backup path before backup, verification, restore, or the retired prune command can run; recommend, but do not require, a separate physical drive for failure isolation
- Recover a unique fully accepted first-backup snapshot by reconstructing authenticated `CURRENT`; preserve ambiguous accepted sets plus schema-v1, failed, partial, unauthenticated, unaccepted, and incomplete deletion candidates for operator review, and fail closed on unsafe or acceptance-invalid `CURRENT`
- Add coordinated schema-v2 snapshot commands for a streamed PostgreSQL base backup, OSCAR state, primary Parquet cold tier, release metadata, and AES-256-CBC/PBKDF2-encrypted deployment credentials; omit cumulative `wal-archive.tar.gz`
- Automatically verify each new snapshot with SHA-256 and `pg_verifybackup`, retain versioned backup-epoch manifests and `VERIFIED` markers, and commit exactly one logical current snapshot through a four-line HMAC-authenticated `CURRENT` pointer
- Preserve explicit schema-v1 verification/restore compatibility, authenticating its required historical WAL payload but ignoring that external payload during restore because streamed `postgres/pg_wal` is sufficient, without treating legacy media as schema v2 or exposing a PITR workflow
- Authenticate each backup inventory with HMAC-SHA-256, stream the bounded canonical backup-time archive-generation UUID inventory, bind the catalog receipt to its count, byte length, and SHA-256 without duplicating a large UUID array in PostgreSQL, require the exact 3.11.1 epoch and image identities, and issue daily-journal confirmation receipts only after the recovery point has passed structural and cryptographic verification
- Authenticate the exact top-level backup payload inventory, require an explicit member allowlist for the release-configuration archive, reject duplicate names, path aliases, prefix collisions, links, reparse points, traversal, and out-of-root paths in every archive, and serialize every storage-administration mutation with a cross-command lock
- Publish backup and portable-export directories through a compiled Linux `renameat2(RENAME_NOREPLACE)` helper after durability barriers; stamp the helper's packaged-source SHA-256 into the image and regression-test collision preservation
- Keep coordinated snapshots outside every long-running service mount, give a network-scoped `pg_basebackup --wal-method=stream` client only its fresh staging directory, and exclude only verified image-owned state links from the mutable-state snapshot
- Preserve legacy WAL roots/data without mounting them into PostgreSQL or deleting them during setup/upgrade mode changes
- Resolve the Ubuntu release directory physically, reject symlinked launchers, and reject Windows launcher/release reparse points while canonicalizing storage-root ancestors, so an alias cannot bypass destructive-operation containment checks
- Restore PostgreSQL only through the selected online base backup's consistency endpoint, promote onto a fresh timeline, reconstruct the exact `VERIFIED` epoch receipt, and prove a post-promotion write across checkpoint and clean restart with `archive_mode=off`
- Preserve the existing Docker volume and bind-mount root metadata while restoring OSCAR state and cold archives by skipping each archive's root member, preventing otherwise valid restores from failing when the container runtime rejects timestamp or mode changes on a mounted root
- Reconcile the entire cold-archive root against the catalog and approved `datasets/` shape, including an otherwise empty/missing `datasets` tree, so unexpected top-level objects fail status, verification, and backup before publication
- Re-verify every payload against the bundle's exact SHA-256 inventory and always load the checksum-verified `offline-images.tar` during offline initialization or upgrade, even when same-version tags already exist locally, so stale development images cannot shadow the selected bundle; the co-packaged unsigned manifest provides integrity but not publisher/origin authentication
- Create persistent Docker volumes through setup, label new volumes with a deployment UUID, reject missing, foreign, or mixed ownership, and require an explicit audited adoption receipt before reusing unlabelled legacy volumes; declare the exact names external to Compose so upgrades never offer to recreate adopted data while reconciling immutable labels
- Force-recreate all service containers during a clean-directory upgrade so unchanged services cannot retain release-local secret/config mounts or Compose provenance from the previous directory, while preserving external storage roots and named data volumes
- Add explicit-confirmation restore and preservation of pre-restore deployment credentials
- Add an external primary-cold-tier archive bind, an optional administrator-owned single-snapshot root exposed only to scoped one-shot helpers, and size-rotated Docker logs
- Add archive status and full object-checksum verification commands that require exactly one active Parquet, manifest, and schema object for every query-visible generation, reject stale generation Parquet path/checksum or manifest-path pointers, and fail/retry if the canonical catalog snapshot changes during live verification
- Qualify archive-generation status fields across the object join so an object's identically named lifecycle columns cannot make the operator status query ambiguous
- Parse Docker image and volume inspection metadata as bounded, identity-validated JSON on Windows PowerShell 5.1, avoiding native-argument quote loss in setup, backup, and restore label checks
- Bind Windows durability-barrier flags with explicit unsigned Win32 types so PowerShell 5.1 can initialize protected storage roots without narrowing the high-bit `CreateFile` option
- Revalidate and extract the exact authenticated root-only OSCAR-state archive through a confined one-shot privilege bridge, then run daily-journal confirmation as the non-root OSCAR user before committing `CURRENT`
- Give every capability-free root helper an explicit neutral working directory on Linux and Windows, preventing the image's owner-only OSCAR state directory from breaking validators, extractors, HMAC helpers, TLS setup, or restore tools after capabilities are dropped
- Stream bounded UTF-8 bootstrap SQL over standard input on Windows PowerShell 5.1 instead of forwarding a quoted shell argument, preserving each statement exactly and retaining `ON_ERROR_STOP` failure behavior
- Stream the multiline PostgreSQL checksum-marker and saved OSCAR configuration acceptance checks over standard input on Windows PowerShell 5.1, so native quote rewriting cannot truncate a fresh initialization after healthy containers start
- Route every Windows setup/storage shell body and direct-`psql` statement through bounded UTF-8 standard input, require the direct `docker run` adapter to attach stdin itself, and relay setup-to-storage options through an allowlisted Base64/JSON environment envelope plus a fixed encoded child command so PowerShell 5.1 cannot rewrite operator values in native argv
- Run `pg_verifybackup` in a networkless, read-only helper with every capability dropped except `DAC_READ_SEARCH`, so both administrator-normalized Linux backups and UID-999 Docker Desktop backups remain verifiable without granting write access or weakening mode-0600/0700 host permissions
- Recheck the exact image inventory after connected OSCAR/PostGIS builds and pull the gateway only when it is still absent, avoiding an unnecessary registry/credential-helper dependency when the pinned gateway image is already cached
- Build connected Windows OSCAR/PostGIS images from explicit validated release contexts, avoiding the Docker Compose 5.6/Buildx 0.37 in-tree Dockerfile entitlement regression without disabling filesystem checks or granting wildcard host access
- Add supported generation/observation hold list/create/release commands with persistent actor, reason, and release audit fields
- Resolve observation-hold membership from an exact PostgreSQL row before consulting coarse archive ID ranges, so sparse/interleaved retired generations cannot reject unrelated extant rows while tombstoned and cold-only ambiguous targets remain fail-closed
- Persist each new hold's `GENERATION_EXACT`, `HOT_EXACT`, or `COLD_RANGE_CONSERVATIVE` resolution mode, expose it in both administration CLIs, preserve unresolvable pre-3.11.0 observation-hold provenance as protective `LEGACY_UNKNOWN`, and document that neither a cold range nor unknown legacy provenance proves a sparse observation ID exists
- Enforce active observation and exact-generation holds transactionally across single and filtered hot/cold datastore removals and tombstones; single removal fails visibly, bulk removal skips protected rows, and set-based candidate lookup avoids per-row connection borrows or store-wide hold materialization
- Fail closed for generic tiered datastore/datastream clear, drop, table-clone backup, and table-replacing restore APIs; prevent datastream removal while any held observation remains, and reject opening a catalog created by a newer storage-schema version
- Add a two-step cold-deletion workflow that freezes eligible sealed generations in a 24-hour plan, emits a one-time token, rechecks holds and each object hash, validates relative paths, persists restartable `DELETING` intent, and retains generation tombstones plus catalog/deletion-ledger audit records
- Add atomic portable archive generation packages with catalog-relative data/schema/manifest objects, catalog JSON, README, ready-to-run DuckDB query, and package checksums
- Add complete architecture, lifecycle, archive-format, backup/restore, operations, monitoring, failure-recovery, privacy, and staged-rollout documentation
- Fail closed on macOS for 3.11.1 deployment/storage operations because Docker Desktop for Mac cannot meet the protected bind-root ownership and recovery-media isolation contract; production hosts are Ubuntu 24.04 or Windows 11/WSL 2
- Add `(datastreamid, phenomenontime, id)` composite indexes and window-pruned partition routing on attached `PARQUET_PRIMARY` stage partitions to eliminate multi-partition sequential scans during live and historical chart queries
- Migrate legacy `dailyFile` datastream schemas (`rapiscanMessage`/`aspectMessage` to `rpmMessage`) in-place during store initialization, preserve backward-compatible JSON key deserialization, and harden PostGIS datastream/command-stream schema-evolution and member-system queries
- Refresh Event Details adjudication history deterministically after submission and deduplicate historical vs. live MQTT adjudication entries by observation ID and timestamp
- Add operational views based on configured keywords per lane
- Modify daily file UI to show latest 15 messages on live view
- Add individual detector charting to historical events
- Fix Rapiscan neutron chart not showing first point in occupancy

### Windows 11 unattended server readiness, upstream transition, and release CI
- Transition official upstream repositories, submodule pins, `osh-js` dependency lock, localized manual asset links, and governance files (`CODEOWNERS`, `CONTRIBUTING.md`, `SECURITY.md`) to [`github.com/ORNL`](https://github.com/ORNL)
- Add `configure-windows-host.ps1` (`.\oscar.bat prepare-host` and `.\oscar.bat host-check`) with 20 automated checks covering AC power/hibernate/USB/NIC power-saving policy, `S0 Low Power Idle` (Modern Standby) detection (`powrprof.dll!GetPwrCapabilities`) with `VIDEOIDLE = 0` (`Never`) enforcement, pre-login Docker Desktop startup (`OSCAR-DockerDesktop-BootStart` `AtStartup` `+10s`, `LogonType=S4U` with ACL-locked `%ProgramData%\OSCAR\start-docker-prelogin.ps1`), bounded `.wslconfig` memory/swap caps (`wsl2-resource-cap`), static vs. DHCP IPv4 stability (`network-address-stability` / `-AllowDhcpAddress`), bugcheck auto-reboot (`AutoReboot=1`, `CrashDumpEnabled=7`), Win32 long paths, W32Time sync, and optional LAN HTTPS `443` firewall rules
- Stage `Confirm-DailyJournalBackup` inside an isolated native Linux ext4 Docker named volume instead of NTFS over WSL 2 9P, and use Win32 `\\?\` long-path cleanup (`Remove-DirectoryTreeLongPath`) on Windows
- Set `absolute_redirect off;` in `dist/release/docker/gateway/default.conf` so `/view/<name>` workstation redirects preserve the external HTTPS host and port instead of exposing internal container port `:8443`
- Normalize `/opt/oscar` permissions in a dedicated Docker build stage to eliminate duplicate copy-up layers in `oscar:3.11.1` and offline Windows image bundles
- Add end-to-end live Docker Compose, `ConSys` API, headless Chromium Playwright UI/Admin, and single-snapshot backup regression verification (`tools/test-live-deployment-regression.sh` against [`ORNL/oscar-regression`](https://github.com/ORNL/oscar-regression)) to both continuous integration and tagged release builds, and publish SHA-256 manifests for all release ZIPs and localized PDF manuals
- Push down exact `PARQUET_PRIMARY` stream/CQL counts without `DataBlock` decoding, prune cold archive generations by bounded `resultTime`, eliminate `obs` self-joins in `scanHotMetadata`, replace in-place mutable stream counter updates with lock-free append-only delta compaction (`oscar_mutable_stream_counts_delta`), add generic-plan-compatible covering partial event indexes (`obs_non_alarm_ptime_desc_idx`, `obs_unadjudicated_alarm_idx`), and coalesce WSL 2 9P Parquet SHA-256 verification with `16 KiB` buffers
- Deduplicate initial Viewer lane-discovery snapshots, cancel superseded `EventTable` count/page requests via `AbortController`, deprioritize background pagination count sweeps (`priority: 'low'`), resolve cold-tier `gammaThreshold` lookups, and eliminate `BroadcastChannel` wallboard listener leaks
- Embed and automatically supervise a digest-pinned loopback `mediamtx` (`1.12.2`) RTSP/RTSPS proxy inside `oscar:3.11.1` (`MediaMtxSidecarManager`, `127.0.0.1` only, keeping real camera URLs unchanged across `config.json`, Admin UI, and CSV imports/exports), deduplicate identical camera streams to one upstream TCP socket per node with immediate `TEARDOWN` on stop/edit, collapse accidental leading `//` RTSP paths, unthrottle `>24 fps` live network cameras, normalize packet DTS/PTS discontinuities, reconnect dropped streams in place without restarting the SensorHub module, and coordinate per-viewer live HLS leases so multiple operators can watch the same lane concurrently
- Complete English (`en`), Spanish (`es`), French (`fr`), and Greek (`el`) localization and container-fit alignment across the React Viewer, Vaadin SensorHub Admin UI, `/login` session authentication page, and operator manuals: correct RPM domain terminology (including Greek `Ανιχνευτής`, `διέλευση`, and `αξιολόγηση`, French `Adjugé`, and Spanish `fallos`), localize live/historical occupancy alarm statuses and custom disposition codes, shorten verbose column/input/toolbar captions (such as compact `Λωρίδα`, `Διέλευση`, `Απομακρυσμένος κόμβος`, and `Τερματισμός`) and widen constrained DataGrid headers, open navigation drawer, and Admin split-pane widths so translated labels fit without horizontal clipping, localize `/login` via `osh-language` cookie, `?lang=`, and `Accept-Language` without inline scripts, and add 4-locale `ConfigMessages` bundles for core, PostGIS/Parquet, MQTT, FileServer, Bucket, DailyFileJournal, occupancy-process, and session-security modules
- Remove all non-redistributable EML JARs, models, and XML files from OSCAR repositories and release bundles; add hot-loadable admin EML and custom alarm assessment plugin upload (`emlPluginPath` stored privately in `/var/lib/oscar/eml-plugin/`, backed up in `oscar_state`, and extracted to `/tmp/oscar-eml-runtime`), a documented developer SPI (`org.sensorhub.impl.utils.rad.eml.EmlAlarmAssessmentAlgorithm` via `META-INF/services/`) plus zero-dependency standalone JAR support (`Oscar-Alarm-Assessment-Class` in `META-INF/MANIFEST.MF` or `META-INF/oscar-alarm-assessment.properties`), synchronous pre-publication `GX` evaluation (`EmlRuntimeRegistry`), zero-flash `t = 0` Dashboard/notification suppression for verified EML `RELEASE` non-threat alarms, durable automated `Code 9999: EML Non-Threat` adjudication records with `EML_METADATA` JSON, localized `EmlAnalysisCard` + `AdjudicationLog` views, and pinned TeX Live cache hardening in release PDF CI
- Add indexed full-database **Adjudication Code** filtering (`equals`, `does not equal`, `is any of`, `is empty`, `is not empty`) and an optional **Adjudication Code** column on the **Events** page across built-in Codes `1–11`, automated **`Code 9998: Extended Occupancy Gamma Alarm`**, automated **`Code 9999: EML Non-Threat`**, and site-configured custom disposition codes (`"code:<n>"` synthetic markers on `occupancy.adjudicatedIds`), backed by an asynchronous, idempotent startup backfill (`AdjudicationCodeMarkerBackfill`) for historical adjudications on upgraded deployments
- Add per-lane `extendedOccupancyThresholdMinutes` (`1`–`1440` min, default `1` min, configurable in SensorHub Admin and via the CSV `ExtendedOccupancyMinutes` column) that publishes `Fault - Extended Occupancy` on `occupancyStatus` when an active occupancy exceeds the threshold and automatically adjudicates gamma-only extended occupancies (`gammaAlarm = true`, `neutronAlarm = false`) prior to publication with **`Code 9998: Extended Occupancy Gamma Alarm`** (`"extended-occupancy-gamma"`, `"code:9998"`, `username = "AUTO"`) while preserving active alarm notifications for any occupancy with a neutron alarm
- Retain historical occupancy daily-file records across midnight rollover via a bounded cold-slice fallback API (`DailyFileSlice`), and integrate [`ORNL/oscar-video-guides`](https://github.com/ORNL/oscar-video-guides) across operator documentation (`docs/VIDEO_GUIDES.md`)
- Replace legacy report rendering with pure-vector Apache PDFBox 3 + JFreeChart PDFs, split itemized adjudication records into a dedicated **`Adjudication Details`** report (`PDF`, `CSV`, `JSON`, and native streaming `SXSSFWorkbook` `.xlsx` with inline Viewer previews and zero-count isotope omission in `Adjudication Report`), prepend a summed **All Selected Lanes** (`ALL_LANES`) disposition and isotope summary section to the start of the **`Adjudication Report`** before per-lane tables, count `eml-non-threat` markers on `occupancy` observations in `RDS Site` and `Event` reports, add separate `Open` and `?download=1` (`Content-Disposition: attachment`) `Download` controls plus `2.5 s` + `visibilitychange` HTTP command-status polling, accelerate 50-lane / 30-day `Lane Report` execution ~5.4x via index-backed `countMatchingEntries`, narrow CQL `alarmCategory != 'None'` queries, shared-prefix `JsonCqlEvaluator` prefiltering, and `ParquetArchiveReader` 64-row CQL batches, serve `Cache-Control: no-cache` on gateway HTML shell routes, and add credentialed `<link rel="manifest" crossOrigin="use-credentials" />` + separated `192x192`/`512x512` `"any"`/`"maskable"` icons for Android Chrome PWA installation behind session authentication
- Add an in-UI **Operator Help & Glossary** dialog (`?` icon in the Viewer top navigation bar) across `en`, `es`, `fr`, and `el`, add localized in-UI `README` tabs across all 24 SensorHub Admin configuration modules with plain-language term explanations, and automatically fit the Dashboard, Map, and Operational View maps tightly to the active lane extent (`zoomSnap: 0`, `padding: [14, 14]`, immediate `laneSystem` coordinate seeding, and `(0, 0)` Null Island exclusion)
- Automatically synchronize Rapiscan RPM daily setup parameters (`SG1`–`SG3` for all 16 gamma setup parameters and `SN1`–`SN2` for all 10 neutron setup parameters, including fractional `nsigma`) from the daily file feed into `RapiscanConfig` (`setupGammaConfig` and `setupNeutronConfig`), update live `GammaThresholdOutput` and `EMLService` calibration parameters in memory at `O(1)` cost, and persist changed configurations to `config.json` asynchronously via `RapiscanConfigSaver` (change-detected and coalesced across all 50 lanes on a single background thread with a 2-second debounce window so sensor TCP reader threads never perform disk I/O or lock contention)
- Tune asynchronous PP-OCRv3 ONNX container and license-plate OCR (`sensorhub-process-ocr` + `sensorhub-system-lane`) on real container transit streams (`FrameSampler` multi-frame stride sampling, `PlateHeuristics` dual-line ISO 6346 container and tractor fleet ID reconstruction, `CandidateAggregator` confidence/vote weighting, `LaneConfig.ocrConfig` default initialization), promote `vehicleOcr` into `PARQUET_PRIMARY`, add ephemeral non-alarm clip handoff (`OccupancyRecordingRegistry.takeDiscardableClipsForEphemeralConsumer` + `OcrJob.cleanupCallback`) so `alarmsOnly = false` leaves `occupancy.videoPaths = []` and deletes transient MP4s immediately after OCR while retaining deduplicated highest-confidence OCR evidence crops in date-partitioned `/var/lib/oscar/files/ocr/crops/<YYYY-MM-DD>/` aligned with `frame-03.jpg` and `ocrCropRetentionDays = 365` (preserving held and operator-adjudicated occupancies and reclaiming oldest eligible crops under `85% -> 80%` storage pressure), emit 60-second `OcrResourceGovernor` telemetry (`submitted`, `completed`, `deferred`, `droppedOverflow`, `shedHeap`, `queueDepth`, `avgJobMs`), scope `oscar_tombstone (obs_id, datastream_id)` per datastream so `resultTime=latest` pushdown remains `O(1)` on tombstoned cold archives, and require post-connect packet confirmation plus reconnect heartbeat-timer reset in `FFMPEGSensor`
- Bound historical `EventDetails` and `EventPreview` Chart.js `TimeScale` axes and playback annotations to the occupancy window with adaptive time units (`buildEventTimeScaleOptions`), expand sub-second occupancy sample windows across whole-second RPM sample boundaries (`expandEventSampleWindow`), normalize trimmed fractional-second ISO timestamps across occupancy lookup and read-state resolution, eliminate the one-render stale-datasource preview race when switching rows, and deduplicate `LaneCollection`/`Node` `ConSysApi` `BroadcastChannel` instances
- Add multi-format secondary-inspection spectroscopy upload and playback (`.n42`, Ortec ASCII `.spe`, Ortec/Canberra binary `.spc`, and `.xml`) with energy-calibration resolution and automatic local photopeak nuclide identification fallback (`WebIdAnalyzer` + `WebIdResourceHandler`) when Sandia Full Spectrum WebID is offline, default gamma energy spectrograms (`N42Chart`, `N42ChartPlayback`, `Rs350ChartPlayback`) to logarithmic vertical scaling (`Counts (Log)`) with an accessible 1-click `Log` / `Linear` scale toggle (`SpectrumScaleControl`), add **UpSet** co-occurrence intersection analytics across the Event Log and `Event` / `Adjudication` / `Vehicle Incident` PDF & JSON reports, polish multi-pass `Vehicle Incident Report` chart/lane-name rendering and bound Dashboard `EventTable` category-slice pagination, and bundle all 26 captioned `1080p` workflow video guides directly inside OSCAR (`/video-guides/`, `text/vtt;charset=utf-8` WebVTT captions behind `X-Content-Type-Options: nosniff`) for offline/air-gapped contextual click-to-play playback in Viewer `Help (?)` and all 20 localized SensorHub Admin module `README` tabs (`737` Viewer locale keys across `en`, `es`, `fr`, `el`)
- Add Event Log **Saved Queries** bookmarks (`SavedEventQueries`, `SavedQueriesPopover`), instant zero-API **Back to Filtered Events** session restoration, collapsible on-demand Event Log **UpSet Co-Occurrence** loading, secondary-inspection upload pre-toggling, and multi-isotope filtering; scale WSL 2 native `ext4` `Local9pParquetCache` dynamically with disk headroom (`2–8 GiB` default), prune non-WebID cold Parquet generations and parallelize profile hydration in `VehicleIncidentAggregator`, batch datastream member lookups and summary-counter candidate selection in `sensorhub-datastore-postgis`, add AC-only low-latency Windows CPU EPP tuning (`ac-processor-performance`) and opt-in `-WslNetworkingMode` in `configure-windows-host.ps1` / `oscar-setup.ps1`, and harden `oscar-storage.{sh,ps1}` + `validate-storage-archive.sh` (`gzip -1`, allowlisted `tls/` credential archiving, streaming `tar` validation, `1024m` validator `tmpfs`) for multi-week `50 GiB+` retained-media backups

### Contributors
Thanks to everyone who contributed across `ORNL/oscar` and its submodules since public release `v3.8.0`:
- **Alex Almanza** (@earocorn) — `ORNL/oscar`, `ORNL/oscar-viewer`, `ORNL/osh-oakridge-modules`
- **Drew Botts** (@drewbotts) — `ORNL/osh-oakridge-modules`
- **Kalyn Stallings** (@kalynstricklin) — `ORNL/oscar`, `ORNL/oscar-viewer`, `ORNL/osh-oakridge-modules`
- **Kyle Fitzpatrick** (@kyle-fitzp) — `ORNL/osh-oakridge-modules`
- **Tyrone Harris** (@tyronechrisharris) — `ORNL/oscar`, `ORNL/oscar-viewer`, `ORNL/osh-addons`, `ORNL/osh-core`, `ORNL/osh-js`, `ORNL/osh-oakridge-modules`

### Full changelog across repository and submodules
- **Since public release `v3.8.0` (`v3.8.0` → `v3.11.1`):**
  - **`ORNL/oscar`**: [`v3.8.0...v3.11.1`](https://github.com/ORNL/oscar/compare/v3.8.0...v3.11.1)
  - **`ORNL/oscar-viewer`**: [`2a67af88...b1319031`](https://github.com/ORNL/oscar-viewer/compare/2a67af881a7119f6d527e01746526ae4a4e0d57e...b13190315e06280a04fc8a6adc1a9f1cadd461c6)
  - **`ORNL/osh-addons`**: [`3708dcaa...e6891b02`](https://github.com/ORNL/osh-addons/compare/3708dcaa1d2189aaa75ad0b11af8483cc1468310...e6891b022ccda3f563082ad38de822f6c6f0a9df)
  - **`ORNL/osh-core`**: [`651fee4d...95bb1d32`](https://github.com/ORNL/osh-core/compare/651fee4d0ae694810c7c02f6cb8fd58c739a6068...95bb1d32e18702546e8204b4c52b2a6b09f75c44)
  - **`ORNL/osh-js`**: [`73dacad5...0d3716dc`](https://github.com/ORNL/osh-js/compare/73dacad5c7338722763263ef0ff5928fbd19de5b...0d3716dc5f5ce8c310757fd5e1e939231e22fe93)
  - **`ORNL/osh-oakridge-modules`**: [`38952169...9436a885`](https://github.com/ORNL/osh-oakridge-modules/compare/38952169099eee66f47c3c30beee4e5de774cea3...9436a885ebf4d9f3d8bacba566146b0d73a56838)
- **Since `v3.10.0` (`v3.10.0` → `v3.11.1`):**
  - **`ORNL/oscar`**: [`v3.10.0...v3.11.1`](https://github.com/ORNL/oscar/compare/v3.10.0...v3.11.1)
  - **`ORNL/oscar-viewer`**: [`a2dabf0e...b1319031`](https://github.com/ORNL/oscar-viewer/compare/a2dabf0e038a6a48acadf8c6fcdb71d916f9adb5...b13190315e06280a04fc8a6adc1a9f1cadd461c6)
  - **`ORNL/osh-addons`**: [`3708dcaa...e6891b02`](https://github.com/ORNL/osh-addons/compare/3708dcaa1d2189aaa75ad0b11af8483cc1468310...e6891b022ccda3f563082ad38de822f6c6f0a9df)
  - **`ORNL/osh-core`**: [`651fee4d...95bb1d32`](https://github.com/ORNL/osh-core/compare/651fee4d0ae694810c7c02f6cb8fd58c739a6068...95bb1d32e18702546e8204b4c52b2a6b09f75c44)
  - **`ORNL/osh-js`**: [`73dacad5...0d3716dc`](https://github.com/ORNL/osh-js/compare/73dacad5c7338722763263ef0ff5928fbd19de5b...0d3716dc5f5ce8c310757fd5e1e939231e22fe93)
  - **`ORNL/osh-oakridge-modules`**: [`4f20ab45...9436a885`](https://github.com/ORNL/osh-oakridge-modules/compare/4f20ab458f177ee0e492a8698227fd0a12fb0514...9436a885ebf4d9f3d8bacba566146b0d73a56838)

## 3.11.0 (Amber) 2026-11-15

- Superseded and archived in favor of **Release 3.11.1 (Amber)** (`nginx/nginx-unprivileged:1.30.7-alpine` November 2026 CVE security update, cross-platform bare-metal autoinstall USB builders, interactive post-autoinstall First-Boot Provisioning Wizard, USB-NVMe stability quirks, cross-platform forward-slash bucket resource URIs, and offline RPM startup UID readiness).

## 3.10.0 2026-10-26
### Changes
- Add custom disposition codes configurable in admin page
- Sort alarms by priority: Gamma-Neutron > Neutron > Gamma
- Add setup-wizard timezone configuration and update daily file format with UTC and local timestamps
- Set camera reconnect attempts to infinite (-1 in config)
- Add ability to share links to specific occupancies, referencing the occupancy's observation ID
- Add daily file output to historical occupancies and live lane view
- Add ability to chart individual detectors instead of the sum in live lane view

## 3.9.1 2026-10-16
### Upgrade notes
- This release changes operator-facing navigation and adds operational-view URL scoping; train operators and validate workstation URLs before production rollout
- Build or import the versioned `oscar:3.9.1` image and run `oscar upgrade`; `oscar restart` alone continues to use the previously installed image
- The upgrade retains the existing `oscar_state` and `postgres_data` volumes and does not require a database reset
### Changes
- Add exact Event UUID lookup from the Events page and durable, node-qualified Event Details links that retain operational-view scope and fail closed for inaccessible lanes
- Show the canonical occupancy observation identifier in Event Details and browser-generated PDFs, and include/display it in compact QR and portable alarm transfers while retaining legacy version-1 import compatibility
- Add a localized Status of Health page showing every visible lane, RPM and camera connectivity, gamma high/low, neutron high, tamper, and configurable extended-occupancy faults
- Add compact dashboard lane indicators for independent RPM and camera connectivity plus gamma high/low, neutron high, tamper, and extended-occupancy state, reusing the bounded health snapshot without adding per-lane health feeds
- Publish a canonical lane occupancy-status stream so extended occupancy works consistently with Rapiscan, Aspect, and RS350 RPMs
- Publish FFmpeg camera connection-state telemetry on lifecycle transitions and every 30 seconds, keeping healthy camera state current through hourly database cleanup while allowing a stopped publisher's stale value to age out
- Produce valid FFmpeg MP4/HLS recordings from H.264 cameras by requiring discovered video dimensions and preserving packet PTS, DTS, duration, stream index, and time base during remuxing
- Make FFmpeg transcoder queues thread-safe and blocking, preserve native packet ownership and delayed-output flushing, surface worker failures, and prevent overlapping pipeline generations during stop, restart, or reinitialization
- Keep MP4 packet delivery ordered with recording close so healthy occupancy clips cannot finalize before queued video packets are written
- Reject and remove incomplete video recordings instead of retaining zero-byte or unfinalized clips, with live-camera recording/HLS coverage plus reconnect and failure-cleanup regression tests
- Start each per-camera recording-command watchdog only after FIFO and bounded alarm/save-decision waits finish and the camera operation is submitted, preventing healthy short occupancies and keyframe-gated startup from falsely quarantining a camera while retaining bounded hung-operation cleanup
- Start live HLS output on the first decodable H.264 keyframe and withhold unavailable playlists instead of serving an empty manifest or a segment that begins mid-GOP
- Treat rapid lane switches before the first HLS keyframe as successful cancellations while preventing queued packets from leaking into a restart and preserving real write or cleanup failures
- Show localized live-video preparation, terminal failure, and retry states in the Viewer, with bounded recovery for transient playlist, network, and media errors
- Document a one-to-two-second camera keyframe interval and provide a one-second closed-GOP preparation path for the 50-camera emulator while retaining low-CPU stream-copy publishing
- Make video-retention compaction fail-safe by validating a decoded frame and durably replacing the original only after the compacted clip is complete, while preserving the source clip on every failure path
- Refresh Status of Health in globally limited batches of at most 50 streams on entry and every 30 seconds, with 10-second request deadlines, replacing per-stream real-time MQTT feeds while avoiding oversized requests, recovering from stalled nodes, and bounding CPU and server load at large sites
- Resolve each eligible batched latest-health read with one indexed PostgreSQL lookup per stream so query cost does not grow with retained observation history
- Publish a Clear tamper baseline whenever the Rapiscan driver establishes or re-establishes an RPM connection, before processing later `TT` and `TC` transitions
- Replace orphan-prone Rapiscan reader threads with one close-aware pooled reader per connection, stop and join the old reader before reconnecting, exit cleanly at end-of-stream, and preserve concurrent input for all 50 lanes
- Accept an RPM occupancy summary immediately after a mid-occupancy connection by recording a zero neutron maximum when no neutron sample has arrived yet, instead of terminating the message reader
- Keep Dashboard-to-Lane Details gamma and neutron streams connected through route handoff, bind them by datastream ID, and release subscriptions cleanly so live plots do not open as threshold-only or empty
- Apply event filters across the full database result set and add PostgreSQL indexes for OSCAR event-filter queries
- Add URL-scoped operational views so one OSCAR deployment can present different lane groups to different workstations
- Scope viewer subscriptions, statistics, reports, navigation, health monitoring, and alarm notifications to the active operational view
- Add backward-compatible lane CSV import/export for operational-view assignments
- Export alarms from the dashboard or Event Details as compact QR codes, PNG images, or portable alarm files for air-gapped transfer
- Preserve chart endpoints, extrema, and gamma threshold crossings while adaptively downsampling gamma, neutron, and threshold data to fit reliable single-code QR capacity
- Scan alarms with a camera or saved image, import portable files, verify transfer integrity, redraw charts, and download or share the received package
- Add complete English, Spanish, French, and Greek interface and operator-manual coverage for alarm transfer
- Package the maintained release guides and all four localized operator manuals in the connected ZIP while excluding obsolete legacy manuals
- Validate changelog, deployment, and localized manual version labels against the release tag
- Migrate the Viewer to Next.js 16, React 19, Cypress 16, and Vite 8; remove obsolete vulnerable tooling, eliminate all known npm audit advisories and deprecated locked packages, and enforce both checks in release builds
- Update the Bnd and Java build configuration so Gradle 8.5 emits no Gradle feature deprecations and remains compatible with the Gradle 9 migration path
- Normalize the persisted SensorHub configuration to owner-only writable permissions (`0600`), repairing overly restrictive copies created by earlier releases
- Document that CSV imports remain in memory until the global Save action completes and require restart verification before acceptance
- Stamp and validate the OSCAR semantic version in the container image's OCI metadata instead of inheriting the base operating-system version label

## 3.9.0 2026-09-23
### Changes
- Add nested AND/OR alarm filtering on the dashboard and Events page
- Add inclusive numeric filters for occupancy ID, maximum gamma, and maximum neutron values
- Add individual, cross-page, and all-filtered alarm selection with bulk adjudication
- Remove Sentry.io
- Handle browser autoplay rejection without breaking live video or alarm audio
- Allow vehicle ID entry during dashboard alarm adjudication
- Add complete English, Spanish, French, and Greek administrator/operator manuals
- Publish validated, screenshot-complete PDF manuals with each GitHub release

## 3.8.2 2026-09-21
### Changes
- Load lanes independently on viewer. Fixes issue that caused failure across all lanes when one lane was unreachable/unhealthy

## 3.8.1 2026-09-20
### Changes
- Fix OSM + site diagram layers
- Fix lane marker location discovery
- Fix camera stream resilience in backend & viewer
- Fix site diagram upload failures

## 3.8.0 2026-09-19
## Changes
- Full support for internationalization (i18n) in frontend viewer and administrative interface

## 3.7.5 2026-09-18
## Changes
- Add manual tamper clear action
- Fix charts that were only showing threshold and not counts
- Increase opacity of sitemap overlay and fit map to sitemap bounds

## 3.7.4 2026-09-16
## Changes
- Fix Leaflet blocking OSM tiles

## 3.7.3 2026-09-09
## Changes
- Allow installation when Docker has different permission set than administrator running setup command
- Fix minor bug in UI where lane UIDs could not have extensions (e.g. "...:lane:north:1")

## 3.7.2 2026-08-28
## Changes
- FFmpeg usage improvements

## 3.7.1 2026-08-27
## Changes
- Added configurable CORS whitelist to Jetty HTTP server

## 3.7.0 2026-08-22
## Changes
- Add cookie based session authentication as default so we dont store credentials in browser storage.
- Fix OSCAR viewer map to auto-fly to sitemap, even when offline.
- Add loading icon for unloaded client data.
- Fix dashboard lane tamper status to persist across refresh.
- MQTT fixes on client and server
- Make OSCAR CLI clickable
- Edit GH Actions workflow to generate offline builds
- Add "verify" to CLI and some flags to offline builder

## 3.6.2 2026-08-20
## Changes
- Fixed minor issue where GitHub actions workflow releases source containing node_modules, making source unnecessarily large

## 3.6.1 2026-08-20
## Changes
- Fixed bug where OSCAR CLI would show `oscar.local` as local hostname but not auto-map. 
  - Now this is automatically mapped on local machine to work.
- Fixed bug where gamma charts display "Gamma 0" at the start of an occupancy

## 3.6.0 2026-08-19
### Changes
- Decrease PostGIS connection pool size and idle time for connections
- Modify PostGIS datastore queries to prevent SQL injection
- Enforce file upload size limits and read-only permissions for files
- Add file upload policy to block common executable files
- Disable CSAPI HTML responses by default and add additional headers for security.
- Containerize all app components (OSH, postgres, reverse proxy)
- Remove default credentials from postgres and OSH
- Harden postgres permissions in deployment
- Added CLI for OSCAR initialization and app management

## 3.5.1 2026-08-01
### Changes
- Removed anonymous user/role.
- Enabled role-based access control for Connected Systems API by default.

## 3.5.0 2026-04-24
### Changes
- Updated LaneSystem README

This is the finalized release for OSCAR phase 3.5.

## 3.3.6 2026-04-23
### Changes
- Updated documentation with correct launch script names

## 3.3.5 2026-04-23
### Fixes
- Fixed bug in viewer with MQTT message parsing
- Updated documentation to reflect new changes

## 3.3.4 2026-04-22
### Fixes
- Fixed server side filtering with queries containing numeric comparisons

## 3.3.3 2026-04-22
### Fixes
- Fixed crashes caused by spreadsheet import
- Fixed locations not being deserialized/loaded from spreadsheet config

## 3.3.2 2026-04-17
### Fixes
- Fixed crash caused by video retention bug
- Fixed daily-file creation

## 3.3.1 2026-04-09
### Fixes
- Fixed OSCAR notifications
- Set video retention policy to enabled by default

## 3.3.0 2026-04-08
### Fixes
- Fixed client dashboard UI to allow double tapping occupancy instead of scrolling to click on "Details" button
- Fixed bug where video clips would not load on first /event-details page load
- Fixed Cambio usage to work offline
- Fixed bug where OSCAR Service Module would fail to restart

### Changes
- Modified occupancy data structure for RS350 occupancies, along with UI.
  - (This makes 3.3.0 incompatible with previous versions)

## 3.2.0 2026-04-04
### Changes
- Now fully supporting RS350 systems in backend and viewer
- Updated notification models and redirects.
- Updated Web ID / Adjudication UI
- Automated RS350 N42 Web ID analysis

## 3.1.0 2026-03-19
### Changes
- Attach node names to lane names on frontend dashboard to differentiate same-name lanes
- Add mobile UI and PWA support (with push notifications)
- Add support for adjudicating with Web ID supplemental analysis
### Fixed
- Fixed bug where chart points were out of order

## 3.0.0 2026-02-04
This is the official first release of 3.0.0
### Changes
- Data from database is purged regularly with "daily files" exported at midnight
- Added internationalization (i18n) to the frontend
- Sorted lanes by alphanumeric order in the frontend dashboard
- Use server-side filters in frontend tables
### Fixed
- Fixed issue where database is queried everytime Admin UI is loaded

## 3.0.0-rc.5 2025-12-11
### Changes
- Improved pagination speed on large datasets
- Make the time at which stats are published configurable
### Fixed
- Fixed bug with HLS thread-locking which causes live video to be unavailable after some time

## 3.0.0-rc.4 2025-12-05
### Changes
- Improved PostGIS query speed for observations
- Improved site stats page load time
### Fixed
- Fixed bug where adjudications would not submit, and duplicate isotopes would appear in adjudications
- Fixed an FFmpeg memory leak causing unbounded memory usage

## 3.0.0-rc.3 2025-11-26
### Fixed
- Fixed issue with FFmpeg transcoding causing node to crash
- Reduce launch script heap size to 6GB
- Reduce thread count for Rapiscan drivers

## 3.0.0-rc.2 2025-11-26
### Fixed
- Fixed issue with Windows `launch-all.bat` script not working
- Fixed embedded MQTT server issue on Windows

## 3.0.0-rc.1 - 2025-11-25
### Fixed
- Optimized requests on client via pagination and filtering
- Fixed adjudications not working properly on client
- Improved FFmpeg HLS latency and video consistency
- Fixed PostGIS queries taking too long
- Reverted launch script to use native JVM for OSH and Docker for PostGIS

## 3.0.0-alpha.4 - 2025-11-17
### Fixed
- Fixed MQTT not disconnecting on client
- Added fixes for FFmpeg issues
- Fixed occupancy videos not attached to every occupancy
- Fixed event preview charts
- Fixed video switching in live video / events
- Fixed issue where commands would never send due to duplicate control streams in CSAPI
- Added fix to decrease HLS latency

## 3.0.0-alpha.3 - 2025-11-12
### Added
- Added extra FFmpeg checks for invalid cameras.
### Changed
- Edited docker compose to restart OSH node on failure
- Edited docker compose to not use managed volume
- Edited ARM64 PostGIS Dockerfile to not use peer connection
- Changed web client to use single MQTT Web Socket connection for dashboard connections

## 3.0.0-alpha.2 - 2025-11-11
### Added
- Added MQTT Services to allow client to receive messages through a single persistent websocket instead of opening multiple websockets per lane.
- Added video retention
### Fixed
- Updated PostGIS to be able to handle commands and command statuses.

## 3.0.0-alpha.1 - 2025-11-07
### Added
- Added docker compose and Dockerfile for OSCAR OSH node, allowing PostGIS and OSH to be run with one script.
### Changed
- Swapped default H2 database with default PostGIS database.
- Update report paths to use valid Windows path

## 3.0.0-alpha - 2025-11-04
### Added
- [#19 Option to replace sitemap with site diagram](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/issues/19)
- [#43 Implement Report Generation](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/issues/43)
- [#48 Switched Database from H2 to PostgresSQL ](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/issues/48)
- [#53 Streamlined Initial Configuration via Spreadsheet Import](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/issues/53)
- Set up Sentry Testing
- Added Unit Tests for all drivers - (Rapiscan, Aspect, FFMpeg, Lane System)
- Set up Client testing using Cypress
- Added GitHub Actions for testing
### Changed
- [#106 Update client playback videostreams](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/issues/106)
- Use local storage to save nodes configured on client server page.
-
### Removed
- [#89 Upgrade Log4j from EOL 1.x to a secure version](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/issues/89)
### Fixed
- [#101 National View does not show the accurate data collected by each site](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/issues/101)

## [2.3.1] - 2025-09-13
### Added
- Current PostGIS database module. (needs to be updated, but this provides a base for testing later versions of OSCAR)
- Dockerfiles and script to launch PostGIS instance.
### Changed
- Restructured repository, moving most directories that are unused in development under `dist`

## [2.3.0] 
Release 2.3.0 

### Added
- Added Deployment version to config.json

### Changed
- [#89](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/issues/89)
Removed dependency to log4j

### Fixed
- [#90](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/issues/90)
Aspect Charts:The prior issue mentioned the Aspect RPMs and the Admin Panel, but this encompasses Aspects issues on the client as well.
- [#]()
Update charts in client to display Rapiscan and Aspect charts 
- [#]()
  Node Form Fix: Updated NodeForm to check if node is reachable before adding it to the list of Nodes, so when configuring a node it will ensure that you can access that node before it continues processing and updating the UI.


## [2.2] - 2025-07-30
Release 2.2 request, no updates since 1.3.7.


## [1.3.7] 2025-07-18

### Added
- [#80](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/issues/80)
  FEATURE REQUEST: Changelog
### Changed
- ToggleButtons are disabled when selected to prevent no component showing (e.g. On event-preview when 'cps' chart is selected you can only toggle to 'nsigma' chart)
- [#85](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/issues/85)
  Neutron Chart Tick Marks
- [#86](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/issues/86)
  Remove "Adjudicated" Filter from Alarming Occupancy Table
### Fixed
- Navigate from Map to Lane View by clicking on point marker
- [#90](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/issues/90)
  Aspect RPMS are not working in version 1.3.5
- [#91](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/issues/91)
  OSCAR Viewer Stability
- [#94](https://github.com/Botts-Innovative-Research/osh-oakridge-buildnode/issues/94)
  Incorrect Video Timeframe Display Leading to Playback Failure
- Aspect alarming events should now appear with charts/video in the event-preview and event-details
