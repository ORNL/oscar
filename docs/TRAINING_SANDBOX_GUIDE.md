# OSCAR 3.11.15 Guided Walkthrough Refresher (`:443`) & Ephemeral Hands-On Training Sandbox (`oscar-sandbox` `:8444`)

OSCAR 3.11.15 provides two complementary, built-in training and refresher experiences for gatehouse operators, shift supervisors, and system administrators:

1. **Anytime Live Console Guided Walkthrough (`:443` — Read-Only Refresher Mode):** Click **Guided Walkthrough** (*graduation-cap icon* in the top navigation bar, or inside **Help (`?`)** — *circled question-mark icon* — `-> Manual & Video Guides`) at any time during a live shift to open the side-by-side coach (`READ-ONLY REFRESHER` badge). Users can browse all **13 role-based labs**, watch offline `1080p` 4-language (`en`, `es`, `fr`, `el`) captioned videos, view annotated `1920×1080` reference screenshots, read inline visual symbol introductions for every navigation icon, navigate to pages, and click **Highlight [Page / Tool] Icon** (for example, **Highlight Status of Health Icon** on the *heart-pulse monitor icon* or **Highlight Help (`?`)** on the *circled question-mark icon*) with **zero** simulated alarm injections, **zero** `/stage-track` server mutations, and **zero** background polling when closed.
2. **Isolated Ephemeral Hands-On Practice Sandbox (`oscar-sandbox` on `:8444`):** Launch a completely isolated disposable practice stack (`1-click` from inside **Guided Walkthrough** or **Help (`?`)** when `enable-ui-bridge` is active on Ubuntu, or via `oscar.sh` / `oscar.bat sandbox start`) to inject simulated radiation alarms and detector faults, upload practice `.n42` / `.uff` / `.csv` / `.pmtiles` files, and practice **Split-Pane SensorHub Admin** edits with 100% zero impact on live PostgreSQL, Parquet archives, `config.json`, or physical RPM relays.

---

## 1. Zero-Contamination Architectural Guarantee & What Users Need to Know When Launching

A core requirement of radiation portal operations is that training data, practice faults, test users, and simulated alarms **never** mix with evidentiary operational records or cold-tier Parquet archives. Both the **Guided Walkthrough** and **Help (`?`)** launcher clearly explain the exact rules and automatic shutdown behavior before and during every session:

### What Every User Sees & Should Know Before Launching `:8444`

- **Live Console (`:443`) vs. Practice Sandbox (`:8444`):**
  - Inside **Guided Walkthrough** on `:443` (`READ-ONLY REFRESHER`), reading steps, playing videos, and highlighting controls is 100% read-only; however, clicking actual operational controls on the underlying `:443` page acts on the live site.
  - Inside `:8444` (`TRAINING SANDBOX`), every lane (`DemoLane01` / `DemoLane02`), Rapiscan stream, camera feed, database table, and configuration file is disposable — you can freely inject alarms, test faults, and edit lanes without affecting the live portal.
- **Automatic 2-Hour Shutdown & Complete Data Wipe (`120 min` Default TTL):**
  - Once launched, `:8444` **automatically shuts down 120 minutes (2 hours) later** (configurable via `--ttl-minutes` / `-TtlMinutes` on CLI) so practice containers can never consume server memory overnight.
  - Both the `:443` launcher card and the `:8444` top bar / Coach banner display a **live countdown and local shutdown clock time** (for example, `Auto-shutdown in 1h 58m (at 10:59 PM)`).
  - When the timer reaches `0` (or an Administrator clicks **Stop & Flush** / **Reset**), `docker compose down -v --remove-orphans` **permanently erases all `:8444` practice alarms, uploads, users, and lane edits in `< 2 s`** (`archive.enabled = false`, `0` `.parquet` files written). **Download your 1-page PDF Training Completion Record before the timer expires** if you want a completion record.
- **Sign-In Credentials, Remote Zero-Trust Subdomain (`<site>-sandbox.<hub>`) + Let's Encrypt & Shared Passkeys, and Export Watermarks:**
  - **Over Remote Zero-Trust Access (`https://<site>.<hub>`):** Clicking **Open Practice Sandbox** opens **`https://<site>-sandbox.<hub>`** over standard HTTPS `:443` using the Hub's public **Let's Encrypt TLS certificate** (zero self-signed browser prompts and zero inbound `:8444` firewall ports), **shared parent-domain WebAuthn Passkeys (`rpId = <hub>`)**, Authentik OIDC SSO, Verified Tunnel SSO, and all operational local user accounts seeded one-way at startup. When the sandbox is stopped, `<site>-sandbox.<hub>` displays a clean status page with a button returning to `<site>.<hub>` to launch it in 1 click.
  - **On Direct LAN / Tailscale / VPN (`https://<oscar-host>`):** Clicking **Open Practice Sandbox (`:8444`)** opens **`https://<oscar-host>:8444`** directly in a new browser tab (both access paths work simultaneously). If the site uses a local/self-signed TLS certificate on LAN, accept the browser's HTTPS prompt once on port `:8444`.
  - Sign in with **your existing OSCAR username/password, OIDC SSO, or WebAuthn Passkey** (`oscar-sandbox` performs a one-way read-only seed on startup; changes inside the sandbox never write back to `:443`).
  - Every `PDF`, `CSV`, `JSON`, `XLSX`, and `QR` file exported from the sandbox is stamped **`TRAINING SANDBOX — NON-OPERATIONAL`**.
- **Safe Multi-User Role Rules (`Start` vs. `Stop`/`Reset`):**
  - Any signed-in user (`Viewer`, `Operator`, or `Administrator`) can view `:8444` host status/countdown and click **Launch Practice Sandbox (`:8444`)** when stopped. If `:8444` is already running, `start` is **idempotent** — it joins the active session without resetting another trainee's work. Only **Administrators** can trigger early **Stop & Flush** or **Reset**.

| Dimension | Operational OSCAR (`compose.yaml`, `:443`) | Ephemeral Training Sandbox (`compose.sandbox.yaml`, `:8444`) |
| :--- | :--- | :--- |
| **Docker Compose Project** | `oscar` | `oscar-sandbox` |
| **Container Images** | `oscar:3.11.15`, `oscar-postgis:3.11.15`, `nginx-unprivileged:1.30.7-alpine` | Reuses the exact already-installed `3.11.15` images (`0 B` extra image download) |
| **PostgreSQL Volume** | `oscar_postgres_data` (persistent, checksummed) | `oscar_sandbox_pg` (disposable, wiped on `stop`/`reset`/TTL) |
| **Application State Volume** | `oscar_oscar_state` (persistent `config.json`, Passkeys, journals) | `oscar_sandbox_state` (disposable, wiped on `stop`/`reset`/TTL) |
| **Parquet Cold Archive** | Host bind-mount `OSCAR_ARCHIVE_DIR` (`archive.enabled = true`) | **Zero host bind-mounts**; `tmpfs` `/var/lib/oscar/archive` + `archive.enabled = false` (`0` `.parquet` files written) |
| **Export Watermarking** | Clean operational exports | All sandbox PDF, CSV, JSON, XLSX, and QR exports stamped with `TRAINING SANDBOX — NON-OPERATIONAL` |
| **Production Overhead When Stopped** | Normal operation + optional 0-polling **Guided Walkthrough** button | **`0` threads, `0` open sockets, and `0` sandbox containers/volumes** |
| **Host RAM Protection** | Full host allocation | Preflight check verifies `>= 3.5 GiB` (`3584 MiB`) available RAM + bounded `-Xmx2g` JVM & `128 MB` Postgres `shared_buffers` |
| **Automatic Idle Cleanup** | Runs `24/7` (`restart: unless-stopped`) | Automatic TTL shutdown timer (default `120 minutes`) + `< 2 s` `down -v --remove-orphans` wipe |

---

## 2. Launching, Resetting & Stopping the Sandbox

### 2.1 Ubuntu Server 24.04 LTS CLI

From the extracted OSCAR 3.11.15 release directory:

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

From an Administrator PowerShell or Command Prompt in the OSCAR 3.11.15 release directory:

```powershell
# Launch the isolated sandbox on HTTPS port 8444
.\oscar.bat sandbox start

# Optional parameters
.\oscar.bat sandbox start -Port 8444 -TtlMinutes 120 -Track operator

# Inspect status or stop and flush all practice volumes
.\oscar.bat sandbox status
.\oscar.bat sandbox stop
```

### 2.3 Sign-In Convenience & Built-In 1-Click Browser Launch (`Guided Walkthrough` & `Help (?)`)

- **Seamless Existing Credentials:** When launched on an initialized OSCAR host, `oscar-sandbox` performs a **one-way read-only seed** of the site's TLS certificate (`tls/server.crt`) and user identity store (`.moduledata/oscar-identity.json`) into `/run/oscar-sandbox` (Ubuntu) or `%ProgramData%\OSCAR\sandbox-runtime` (Windows) and `oscar_sandbox_state`. Administrators and operators open `https://<oscar-host>:8444` and sign in using their **existing username, password, or offline WebAuthn Passkey** — while any password changes, practice user invites, or deletions inside `:8444` never touch production `oscar_oscar_state`. (Pass `--admin-password <password>` / `-AdminPassword <password>` to use an independent password instead, or launch on an uninitialized host to receive an auto-generated `Sandbox-<hex>` password.)
- **Out-of-the-Box 1-Click Browser Launcher in `Guided Walkthrough` & `Help (?)`:** Standard `oscar init`, `start`, `restart`, and `upgrade` runs automatically install and enable the lightweight host queue watcher on both **Ubuntu Server 24.04** (`oscar-sandbox-agent.path` + `oscar-sandbox-agent.timer`) and **Windows 11** (`OSCAR-SandboxAgent` Scheduled Task) with zero `docker.sock` exposure inside the `oscar` container. Clicking **Guided Walkthrough** in the top bar or **Help (`?`) -> Manual & Video Guides** displays live `:8444` status, auto-shutdown countdown, and a **1-click `Launch Practice Sandbox (:8444)`** button available to any signed-in user (idempotent if already running), while early **Stop** and **Reset** remain Administrator-only. Administrators who prefer CLI-only `:8444` startup can opt out anytime via `sudo bash oscar.sh sandbox disable-ui-bridge` / `.\oscar.bat sandbox disable-ui-bridge` (or `OSCAR_SANDBOX_UI_BRIDGE=disabled` in `.env`, and re-enable via `enable-ui-bridge`).

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
     - `norm_eml`: Spatially uniform 4-panel distributed cargo profile evaluated by `SandboxEmlTrainingAlgorithm` as `RELEASE` -> automatic **`Code 9999: EML Non-Threat`** disposition (automatically opening **Events (`/event-log`)** with live occupancy transit progress and the **`Adjudication Code`** column visible while explaining why benign `Code 9999` passes remain suppressed from the active Dashboard `/` threat queue).
     - `extended_occupancy`: Holds a gamma-only occupancy past the sandbox extended-occupancy threshold (`8 s` accelerated threshold inside sandbox mode) to trigger live **`Fault - Extended Occupancy`** followed by **`Code 9998: Extended Occupancy Gamma Alarm`** auto-adjudication on exit (also opening `/event-log` with visible **`Code 9998`** disposition badges).
     - `fault_gamma_high` / `fault_tamper` / `clear_faults` / `stage_webrelay_demo`: Live `GH` and `TT`/`TC` state-of-health transitions and 1-click loopback `WebRelay-Quad` staging on **Status of Health (`/health`)**.
2. **Loopback ControlByWeb® `WebRelay-Quad` HTTP/XML Servers (`127.0.0.1:10180` Primary & `127.0.0.1:10181` Ancillary):**
   - Pure-Java `SandboxWebRelayLoopbackServer` (started strictly inside `OSCAR_SANDBOX_MODE=true`) serves `/stateFull.xml` and `/state.xml` with live `relay1State..relay4State=0|1|2` (`2` = hardware-timed pulse via `pulseTime1..4`), enabling Lab `3.5` (`adm-5`) trainees to stage `DemoLane01` in 1 click, test HTTP/XML connectivity against `127.0.0.1:10180`, exercise `AUTO` / `MUTED` / `PASS_THROUGH` modes and timed beacon/siren pulses, and auto-verify `webRelayOnlineCount >= 1` with zero external relay hardware.
3. **Loopback RTSP Moving-Truck Container Camera (`rtsp://127.0.0.1:8554/tutorial-cam` & `/tutorial-cam-2`):**
   - Encodes deterministic `CC0-1.0` `1280×720` (`15 fps`, `0.33 s` GOP) `H.264` gatehouse tractor-trailer drive-through clips (`SCFU8572724` / `SWT03` on `DemoLane01` and `RSTU2402941` / `M50M1` on `DemoLane02`, Modulo-11 valid ISO 6346 container stencils) in-process via JavaCPP JNI (`libopenh264` / `libavformat`) and streams them into loopback `mediamtx` (`< 0.2%` CPU, zero external CLI binary dependencies).
   - Synchronizes each occupancy injection with a full end-to-end lane transit (empty portal -> tractor cab entering -> 40-ft container traversing between the RPM pillars -> rear doors & trailer bumper exiting -> empty portal) at true `1.0×` real-time RTP timestamps, exercising live HLS playback, progressive 5-JPEG alarm frame extraction (`frame-01.jpg`–`frame-05.jpg`), and asynchronous ONNX Container & License Plate OCR (`vehicleOcr`).
4. **Downloadable Practice Sample Files (`/sensorhub/oscar/sandbox/samples/*`):**
   - `tutorial-1-lane.csv`: Valid `SpreadsheetParser` V1 CSV pre-targeted at `127.0.0.1:10099` and `127.0.0.1:8554/tutorial-cam` (`archiveEnabled = false`).
   - `sample-cs137-co60.n42`: Synthetic ANSI N42.42 secondary-inspection gamma spectrum (`Cs-137` 662 keV + `Co-60` 1173/1332 keV).
   - `sample-cargo-uff3.uff`: `CC0-1.0` WCO `UFF 3.0.0` tractor-trailer truck NII package (`dfb985c4-eb26-41ab-938b-ad2a1f5966d4`, matching `SCFU8572724` / `SWT03`) containing a `2048×600` Deflate-compressed 16-bit `uint16` Beer-Lambert truck radiograph, 8-bit palettized **HEMD** effective-Z overlay (`Organic`, `Intermediate`, `Inorganic`, `High-Z Shielding`), Bill of Lading Trade Manifest `.pdf`, customs declaration, normalized High-Z bounding-box annotation (`94%`), matching optical camera crops, and embedded `.n42` spectrum (also pre-indexed at `/var/lib/oscar/sandbox-tutorial/uff-share` alongside `RSTU2402941` NORM and `SCFU8S72724` 1-character fuzzy OCR packages).
   - `sample-regional-map.pmtiles`: Compact Protomaps PMTiles v3 regional archive for testing air-gapped `/map` basemaps in **Runtime Extensions (`/extensions`)**.
   - `sample-policy-pack.json`: Agency Disposition Policy Pack (`Code 101` & `Code 102` localized across `en`, `es`, `fr`, `el`).

---

## 4. Multi-Modal Guided Academy Curriculum (3 Role Tracks · 13 Guided Labs)

Inside `:8444` (and in Read-Only Refresher Mode via **Guided Walkthrough** on `:443`), the collapsible **Training Coach** dock (`en`, `es`, `fr`, `el`) covers **13 guided labs** across three role tracks. Every lab combines **four learning modalities** (`Watch · Read · Do · Auto-Verify`):

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
- **Lab 1.4 — Container OCR, Secondary Spectroscopy (`.n42`) & QR Transfer:** Apply an ISO 6346 OCR container chip (`SCFU8572724`), attach `sample-cs137-co60.n42`, and inspect watermarked air-gapped QR packages.
- **Lab 1.5 — 16-Bit WCO UFF Cargo X-Ray & HEMD Material Inspection:** Search by UFF UUID (`dfb985c4-eb26-41ab-938b-ad2a1f5966d4`) or container ID (`SCFU8572724`), adjust 16-bit TIFF Window/Level contrast, and toggle HEMD High-Z shielding bands aligned with the RPM radiation strip.

### Track 2 — Shift Supervisor & Analyst (`supervisor`, 3 Labs)
*Stages 2 lanes (`DemoLane01` `north-gate` & `DemoLane02` `south-gate`) and seeds multi-category `SNM`, `Medical`, `NORM`, and multi-pass container history.*
- **Lab 2.1 — Operational Views & Multi-Pass Vehicle Correlation:** Scope the console via `Scoped View` (`north-gate` / `south-gate`), correlate multi-pass container `SCFU8572724` in `VehiclePassComparisonDialog`, and bookmark a Saved Query.
- **Lab 2.2 — UpSet `SNM` Co-Occurrence Analytics & 6-Type Multi-Format Reports:** Generate watermarked `PDF`, `CSV`, `JSON`, and `XLSX` reports in `/report` and inspect crimson `SNM` intersections on the UpSet chart.
- **Lab 2.3 — National Node Summary & Secret-Redacted Support Bundles:** Review aggregated KPIs on `/national-view` and export a credential-scrubbed `oscar-support-<UTC>.zip` diagnostic bundle from `Help (?)`.

### Track 3 — System Administrator (`administrator`, 5 Labs)
*Resets to a Day-1 Blank Slate (`0` lanes configured) while loopback Rapiscan `127.0.0.1:10099` and RTSP `127.0.0.1:8554/tutorial-cam` run in the background.*
- **Lab 3.1 — Manual Lane, Rapiscan RPM & Loopback RTSP Camera Setup:** Open **Split-Pane SensorHub Admin** (`/sensorhub/admin` side-by-side with the Training Coach) and configure `DemoLane01` from scratch.
- **Lab 3.2 — 1-Click Bulk Lane Spreadsheet Import (`tutorial-1-lane.csv`):** Download `tutorial-1-lane.csv` and provision lanes in bulk via `Services -> OSCAR Service`.
- **Lab 3.3 — Users, RBAC View Scoping, QR Enrollment & Offline Passkeys:** Practice creating view-scoped operators, printable QR enrollment invites, and `oscar_fed_...` tokens in `/users`.
- **Lab 3.4 — Runtime Extensions (`.pmtiles` Maps, Policy Packs & Cargo NII):** Upload `sample-regional-map.pmtiles` and `sample-policy-pack.json` (`Code 101` & `Code 102`) in `/extensions`, and review `/usb-backups`.
- **Lab 3.5 — Per-Lane Physical RPM Lights & Sound (`WebRelay-Quad`):** Stage `DemoLane01` + loopback ControlByWeb `WebRelay-Quad` (`127.0.0.1:10180`) in 1 click, test `/stateFull.xml` connectivity, review operating modes (`AUTO` EML `Code 9999` / `Code 9998` suppression, `PASS_THROUGH` `0,0,0,0` fail-safe, `MUTED`), inspect live `R1–R4` coil telemetry, and trigger timed commissioning pulses on `/health` and `/lane-view`.

---

## 5. Related Documentation

- [Quick Start Guide](../dist/release/QUICKSTART.md)
- [Administrator Deployment Guide](../dist/release/DEPLOYMENT.md)
- [Operator & Administrator Manual (English)](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README.md)
- [How-To Video Guides (`#01`–`#29`)](VIDEO_GUIDES.md)
- [Per-Lane Physical RPM Lights & Sound (`WebRelay-Quad`) Guide](LANE_WEBRELAY_GUIDE.md)
- [Cargo Non-Intrusive Inspection (WCO UFF 2.0 & 3.0) Guide](CARGO_UFF_INTEGRATION.md)
- [Pluggable Runtime Extensions & Regional Packs Guide](PLUGGABLE_EXTENSIONS_GUIDE.md)
