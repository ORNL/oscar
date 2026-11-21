# OSCAR 3.11.3 Ephemeral Hands-On Training Sandbox & Guided Academy (`oscar-sandbox`)

OSCAR 3.11.3 includes a built-in, self-contained **Hands-On Training Sandbox & Guided Academy (`oscar-sandbox`)** designed for gatehouse operators, shift supervisors, and system administrators to practice every operational and administrative workflow safely before connecting or modifying live port-of-entry radiation portal monitors (RPMs) and RTSP cameras.

---

## 1. Zero-Contamination Architectural Guarantee

A core requirement of radiation portal operations is that training data, practice faults, test users, and simulated alarms **never** mix with evidentiary operational records or cold-tier Parquet archives. `oscar-sandbox` enforces strict OS- and container-level isolation:

| Dimension | Operational OSCAR (`compose.yaml`, `:443`) | Ephemeral Training Sandbox (`compose.sandbox.yaml`, `:8444`) |
| :--- | :--- | :--- |
| **Docker Compose Project** | `oscar` | `oscar-sandbox` |
| **Container Images** | `oscar:3.11.3`, `oscar-postgis:3.11.3`, `nginx-unprivileged:1.30.7-alpine` | Reuses the exact already-installed `3.11.3` images (`0 B` extra image download) |
| **PostgreSQL Volume** | `oscar_postgres_data` (persistent, checksummed) | `oscar_sandbox_pg` (disposable, wiped on `stop`/`reset`) |
| **Application State Volume** | `oscar_oscar_state` (persistent `config.json`, Passkeys, journals) | `oscar_sandbox_state` (disposable, wiped on `stop`/`reset`) |
| **Parquet Cold Archive** | Host bind-mount `OSCAR_ARCHIVE_DIR` (`archive.enabled = true`) | **Zero host bind-mounts**; `tmpfs` `/var/lib/oscar/archive` + `archive.enabled = false` (`0` `.parquet` files written) |
| **Export Watermarking** | Clean operational exports | All sandbox PDF, CSV, JSON, XLSX, and QR exports stamped with `TRAINING SANDBOX — NON-OPERATIONAL` |
| **Production Overhead When Stopped** | Normal operation | **`0` threads, `0` open sockets, `0` memory, and `0` extra UI banners/buttons** |
| **Host RAM Protection** | Full host allocation | Preflight check verifies `>= 3.5 GiB` (`3584 MiB`) available RAM + bounded `-Xmx2g` JVM & `128 MB` Postgres `shared_buffers` |
| **Automatic Idle Cleanup** | Runs `24/7` (`restart: unless-stopped`) | Automatic TTL shutdown timer (default `120 minutes`) + `< 2 s` `down -v --remove-orphans` wipe |

---

## 2. Launching, Resetting & Stopping the Sandbox

### 2.1 Ubuntu Server 24.04 LTS CLI

From the extracted OSCAR 3.11.3 release directory:

```bash
# Launch the isolated sandbox on HTTPS port 8444 (default 120-minute auto-expiry TTL)
sudo bash oscar.sh sandbox start

# Optional flags: custom port, custom TTL, or starting directly in Supervisor / Administrator track
sudo bash oscar.sh sandbox start --port 8444 --ttl-minutes 120 --track operator

# Check sandbox container status and remaining TTL
sudo bash oscar.sh sandbox status

# Reset all sandbox volumes back to a clean slate in seconds
sudo bash oscar.sh sandbox reset --track administrator

# Stop the sandbox and flush 100% of ephemeral volumes and runtime secrets
sudo bash oscar.sh sandbox stop
```

### 2.2 Windows 11 + Docker Desktop (WSL 2) CLI

From an Administrator PowerShell or Command Prompt in the OSCAR 3.11.3 release directory:

```powershell
# Launch the isolated sandbox on HTTPS port 8444
.\oscar.bat sandbox start

# Optional parameters
.\oscar.bat sandbox start -Port 8444 -TtlMinutes 120 -Track operator

# Inspect status or stop and flush all practice volumes
.\oscar.bat sandbox status
.\oscar.bat sandbox stop
```

### 2.3 Sign-In Convenience & Optional 1-Click Browser Launch (`Help (?)`)

- **Seamless Existing Credentials:** When launched on an initialized OSCAR host, `oscar-sandbox` performs a **one-way read-only seed** of the site's TLS certificate (`tls/server.crt`) and user identity store (`.moduledata/oscar-identity.json`) into `/run/oscar-sandbox` / `oscar_sandbox_state`. Administrators and operators open `https://<oscar-host>:8444` and sign in using their **existing username, password, or offline WebAuthn Passkey** — while any password changes, practice user invites, or deletions inside `:8444` never touch production `oscar_oscar_state`. (Pass `--admin-password <password>` / `-AdminPassword <password>` to use an independent password instead, or launch on an uninitialized host to receive an auto-generated `Sandbox-<hex>` password.)
- **Optional 1-Click Browser Launcher in `Help (?)`:** Clicking **Help (`?`) -> Manual & Video Guides** on any node displays the **Hands-On Training Sandbox (`oscar-sandbox`)** card with 1-click copyable Linux/Windows start commands. Administrators who want 1-click browser **Launch / Reset / Stop** buttons without opening SSH can enable the lightweight host queue watcher once via `sudo bash oscar.sh sandbox enable-ui-bridge` (disable anytime with `sudo bash oscar.sh sandbox disable-ui-bridge`).

![Hands-On Training Sandbox Coach and Operator Lab](https://raw.githubusercontent.com/ORNL/osh-oakridge-modules/main/docs/oscar-operator-manual/images/51-training-sandbox-coach-and-operator-lab.png)

---

## 3. Built-In Loopback Micro-Emulator & Practice Sample Files

When `OSCAR_SANDBOX_MODE=true`, `TrainingSandboxManager` starts a zero-hardware loopback micro-emulator bound strictly to `127.0.0.1` inside the sandbox container:

1. **Wire-Exact Rapiscan ASCII RPM Loopback Servers (`127.0.0.1:10099` & `127.0.0.1:10100`):**
   - Publishes daily setup parameters (`SG1`–`SG3`, `SN1`–`SN2`, `TC`) and continuous 1 Hz background counts (`GB`, `NB`) so `RapiscanSensor` reports healthy `Online` SOH and realistic `NSIGMA` thresholds.
   - Supports instant 1-click scenario injection from the **Training Coach**:
     - `clean_pass`: Normal non-alarm vehicle occupancy (`GS` + `NS` + `SP` + `GX`).
     - `gamma_alarm`: Localized asymmetric point-source gamma spike (`GA`) requiring human operator adjudication.
     - `neutron_alarm`: Elevated neutron count (`NA`) — demonstrates that Neutron triggers **never** auto-release.
     - `gamma_neutron_alarm`: Combined `GA` + `NA` high-priority alarm.
     - `norm_eml`: Spatially uniform 4-panel distributed cargo profile evaluated by `SandboxEmlTrainingAlgorithm` as `RELEASE` -> automatic **`Code 9999: EML Non-Threat`** disposition.
     - `extended_occupancy`: Holds a gamma-only occupancy past the sandbox extended-occupancy threshold (`8 s` accelerated threshold inside sandbox mode) to trigger live **`Fault - Extended Occupancy`** followed by **`Code 9998: Extended Occupancy Gamma Alarm`** auto-adjudication on exit.
     - `fault_gamma_high` / `fault_tamper` / `clear_faults`: Live `GH` and `TT`/`TC` state-of-health transitions.
2. **Loopback RTSP Container Camera (`rtsp://127.0.0.1:8554/tutorial-cam` & `/tutorial-cam-2`):**
   - Encodes deterministic `CC0-1.0` `1280×720` `H.264` gatehouse container clips (`MSCU5285725` / `TN482KMP` and `OSCU4829106` / `VA917TRL`, Modulo-11 valid ISO 6346 container stencils) in-process via JavaCPP JNI (`libopenh264` / `libavformat`) and streams them into loopback `mediamtx` (`< 0.2%` CPU, zero external CLI binary dependencies).
   - Exercises the full production video pipeline: live HLS playback, 5-JPEG alarm frame extraction (`frame-01.jpg`–`frame-05.jpg`), and asynchronous ONNX Container & License Plate OCR (`vehicleOcr`).
3. **Downloadable Practice Sample Files (`/sensorhub/oscar/sandbox/samples/*`):**
   - `tutorial-1-lane.csv`: Valid `SpreadsheetParser` V1 CSV pre-targeted at `127.0.0.1:10099` and `127.0.0.1:8554/tutorial-cam` (`archiveEnabled = false`).
   - `sample-cs137-co60.n42`: Synthetic ANSI N42.42 secondary-inspection gamma spectrum (`Cs-137` 662 keV + `Co-60` 1173/1332 keV).
   - `sample-cargo-uff3.uff`: `CC0-1.0` WCO `UFF 3.0.0` cargo NII package containing a 16-bit `uint16` grayscale TIFF radiograph, 8-bit palettized **HEMD** effective-Z overlay (`Organic`, `Inorganic`, `Metallic`, `High-Z Shielding`), customs declaration, High-Z bounding-box annotation, and embedded `.n42` spectrum (also pre-indexed at `/var/lib/oscar/sandbox-tutorial/uff-share` with both exact and 1-character fuzzy OCR matches).
   - `sample-regional-map.pmtiles`: Compact Protomaps PMTiles v3 regional archive for testing air-gapped `/map` basemaps in **Runtime Extensions (`/extensions`)**.
   - `sample-policy-pack.json`: Agency Disposition Policy Pack (`Code 101` & `Code 102` localized across `en`, `es`, `fr`, `el`).

---

## 4. Multi-Modal Guided Academy Curriculum (3 Role Tracks · 12 Hands-On Labs)

Inside `:8444`, the single-row top bar displays a high-contrast **`TRAINING SANDBOX`** badge with remaining TTL alongside the collapsible **Training Coach** dock (`en`, `es`, `fr`, `el`). Every lab combines **four learning modalities** (`Watch · Read · Do · Auto-Verify`):

1. **Watch:** Inline click-to-play `1080p` workflow video guide (`/video-guides/videos/*.mp4`) with synchronized `.vtt` closed captions (`preload="none"`).
2. **Read:** Annotated `1920×1080` reference screenshot (`/manual-screenshots/*.png`) + plain-language **Operational Why**.
3. **Do:** Step-by-step actions paired with 1-click **Inject Practice Event**, **Download Practice File**, **Copy Endpoint**, **Highlight Control on Screen**, and **Split-Pane SensorHub Admin**.
4. **Auto-Verify:** Polls live ConSys, observation, command-status, bucket, and Runtime Extension APIs every `4 s` to mark each lab **Auto-Verified** as soon as the real outcome is achieved, and exports a **1-Page Vector PDF Training Completion Record** (`oscar-training-completion-record.pdf`) before the sandbox is flushed.

![Split-Pane SensorHub Admin and Training Coach](https://raw.githubusercontent.com/ORNL/osh-oakridge-modules/main/docs/oscar-operator-manual/images/52-training-sandbox-admin-split-pane.png)

### Track 1 — Gatehouse Operator (`operator`, 5 Labs)
*Automatically stages `DemoLane01` (`north-gate`) online with live Rapiscan, RTSP camera, OCR, and Cargo NII samples.*
- **Lab 1.1 — Live Lane Monitoring, Status of Health & Fault Triage:** Verify `Online` RPM/camera health on `/health`, inject `Fault - Gamma High` (`GH`) and `Tamper` (`TT`), clear faults (`TC`), and observe a clean vehicle pass.
- **Lab 1.2 — Priority Alarm Queue & 5-Frame Alarm Adjudication:** Inject a localized point-source Gamma Alarm, inspect the count profile and 5 retained JPEG frames on `/`, and submit a disposition code.
- **Lab 1.3 — NORM (`Code 9999`), Extended Occupancy (`Code 9998`) & Neutron Safety:** Compare spatially uniform NORM auto-release (`Code 9999`) and stalled gamma-only holds (`Code 9998`) against mandatory human review on Neutron alarms (`NA`).
- **Lab 1.4 — Container OCR, Secondary Spectroscopy (`.n42`) & QR Transfer:** Apply an ISO 6346 OCR container chip (`MSCU5285725`), attach `sample-cs137-co60.n42`, and inspect watermarked air-gapped QR packages.
- **Lab 1.5 — 16-Bit WCO UFF Cargo X-Ray & HEMD Material Inspection:** Search by UFF UUID or container ID, adjust 16-bit TIFF Window/Level contrast, and toggle HEMD High-Z shielding bands aligned with the RPM radiation strip.

### Track 2 — Shift Supervisor & Analyst (`supervisor`, 3 Labs)
*Stages 2 lanes (`DemoLane01` `north-gate` & `DemoLane02` `south-gate`) and seeds multi-category `SNM`, `Medical`, `NORM`, and multi-pass container history.*
- **Lab 2.1 — Operational Views & Multi-Pass Vehicle Correlation:** Scope the console via `Scoped View` (`north-gate` / `south-gate`), correlate multi-pass container `MSCU5285725` in `VehiclePassComparisonDialog`, and bookmark a Saved Query.
- **Lab 2.2 — UpSet `SNM` Co-Occurrence Analytics & 6-Type Multi-Format Reports:** Generate watermarked `PDF`, `CSV`, `JSON`, and `XLSX` reports in `/report` and inspect crimson `SNM` intersections on the UpSet chart.
- **Lab 2.3 — National Node Summary & Secret-Redacted Support Bundles:** Review aggregated KPIs on `/national-view` and export a credential-scrubbed `oscar-support-<UTC>.zip` diagnostic bundle from `Help (?)`.

### Track 3 — System Administrator (`administrator`, 4 Labs)
*Resets to a Day-1 Blank Slate (`0` lanes configured) while loopback Rapiscan `127.0.0.1:10099` and RTSP `127.0.0.1:8554/tutorial-cam` run in the background.*
- **Lab 3.1 — Manual Lane, Rapiscan RPM & Loopback RTSP Camera Setup:** Open **Split-Pane SensorHub Admin** (`/sensorhub/admin` side-by-side with the Training Coach) and configure `DemoLane01` from scratch.
- **Lab 3.2 — 1-Click Bulk Lane Spreadsheet Import (`tutorial-1-lane.csv`):** Download `tutorial-1-lane.csv` and provision lanes in bulk via `Services -> OSCAR Service`.
- **Lab 3.3 — Users, RBAC View Scoping, QR Enrollment & Offline Passkeys:** Practice creating view-scoped operators, printable QR enrollment invites, and `oscar_fed_...` tokens in `/users`.
- **Lab 3.4 — Runtime Extensions (`.pmtiles` Maps, Policy Packs & Cargo NII):** Upload `sample-regional-map.pmtiles` and `sample-policy-pack.json` (`Code 101` & `Code 102`) in `/extensions`, and review `/usb-backups`.

---

## 5. Related Documentation

- [Quick Start Guide](../dist/release/QUICKSTART.md)
- [Administrator Deployment Guide](../dist/release/DEPLOYMENT.md)
- [Operator & Administrator Manual (English)](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README.md)
- [How-To Video Guides (`#01`–`#28`)](VIDEO_GUIDES.md)
- [Cargo Non-Intrusive Inspection (WCO UFF 2.0 & 3.0) Guide](CARGO_UFF_INTEGRATION.md)
- [Pluggable Runtime Extensions & Regional Packs Guide](PLUGGABLE_EXTENSIONS_GUIDE.md)
