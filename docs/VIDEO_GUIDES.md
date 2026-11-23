# OSCAR 3.11.9 How-To Video Guides

Concise, single-task `1920x1080` workflow screen recordings for **OSCAR 3.11.9**, published in [`ORNL/oscar-video-guides`](https://github.com/ORNL/oscar-video-guides) and mounted as a Git submodule at `docs/video-guides` in source checkouts (`git submodule update --init docs/video-guides`).

Every module starts immediately at `00:00` with the workflow action, runs under 2 minutes, includes embedded MP4 `mov_text` soft subtitles plus standalone WebVTT (`.vtt`) and SubRip (`.srt`) caption tracks, and pairs with a 3-to-4-step sequential reference block below.

## Technical Encoding Specification

| Parameter | Specification |
| --- | --- |
| Hardware Encoder | NVIDIA GeForce RTX 5060 Ti `h264_nvenc` (`High@L4.1`, `avc1`) |
| Container & Color | Universal `.mp4` (`+faststart`), `NV12` / `4:2:0` (`yuv420p`), `BT.709` |
| Compression & GOP | `8 s` forced IDR keyframe interval (`GOP 240 @ 30fps`) + NVENC `p7`/`hq` B-frame skip blocks |
| Resolution & Framerate | `1920x1080` (`1080p`) constant `30 FPS` (`CFR`) |
| Accessibility | Embedded MP4 `mov_text` soft captions + standalone `.vtt` and `.srt` files + 3-to-4-step Markdown blocks |

> **Interactive HTML5 Player & In-App Contextual Video Assistance:**
> - **Source checkouts:** With submodules initialized, open `docs/video-guides/index.html` in any browser to watch all 29 modules with synchronized closed captions enabled by default.
> - **Running OSCAR 3.11.9 deployments (offline-ready):** All 29 MP4 recordings and 4-language (`en`, `es`, `fr`, `el`) WebVTT/SRT captions (`232` subtitle tracks) are bundled directly in the OSCAR web root (`osh-node-oscar/web/video-guides/`) and served over TLS with HTTP byte-range streaming, automatic locale subtitle track selection, and zero idle network load:
>   - **OSCAR Viewer (`Guided Walkthrough` & `?` Help Dialog):** Click `Guided Walkthrough` or `?` on any console page to watch route-matched workflow videos inline with closed captions, trigger per-card/per-glossary video walkthroughs, or open the full local catalog at `/video-guides/index.html`.
>   - **SensorHub Admin (`/sensorhub/admin`):** Open any supported module's **README** tab (`OSCAR Service`, `Lane Sensor System`, `Rapiscan RPM`, `FFmpeg Video`, or `Durable Daily File Journal`) and expand the collapsed `Video guide (#XX)` disclosures on demand.

## Workflow Catalog

| # | Workflow Guide | Track | Duration | Size | Captions |
| --- | --- | --- | --- | --- | --- |
| 01 | [Initialize OSCAR Deployment, Admin Credentials & TLS](#01-deployment-init-and-credentials) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/01-deployment-init-and-credentials.mp4)) | Track A | 28.5s | 587.7 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/01-deployment-init-and-credentials.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/01-deployment-init-and-credentials.srt) |
| 02 | [Upgrade OSCAR in a Clean Release Directory](#02-clean-directory-upgrade) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/02-clean-directory-upgrade.mp4)) | Track A | 29.5s | 519.6 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/02-clean-directory-upgrade.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/02-clean-directory-upgrade.srt) |
| 03 | [Verify Parquet Cold-Tier Archives & Single-Snapshot Backup](#03-archive-and-snapshot-backup) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/03-archive-and-snapshot-backup.mp4)) | Track A | 28.5s | 545.2 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/03-archive-and-snapshot-backup.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/03-archive-and-snapshot-backup.srt) |
| 04 | [Configure OSCAR Service Retention & Custom Disposition Codes](#04-admin-oscar-service-and-custom-codes) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/04-admin-oscar-service-and-custom-codes.mp4)) | Track B | 41.5s | 1040.3 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/04-admin-oscar-service-and-custom-codes.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/04-admin-oscar-service-and-custom-codes.srt) |
| 05 | [Sync Multi-Lane Spreadsheet Configuration (config.csv)](#05-admin-lane-spreadsheet-sync) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/05-admin-lane-spreadsheet-sync.mp4)) | Track B | 30s | 682.8 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/05-admin-lane-spreadsheet-sync.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/05-admin-lane-spreadsheet-sync.srt) |
| 06 | [Configure a Lane System & Georeferenced Site Diagram](#06-admin-manual-lane-and-site-diagram) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/06-admin-manual-lane-and-site-diagram.mp4)) | Track B | 41s | 1078.5 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/06-admin-manual-lane-and-site-diagram.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/06-admin-manual-lane-and-site-diagram.srt) |
| 07 | [Upload External EML VM-250 Plugin & Enable Per-Lane EML](#07-admin-eml-plugin-setup) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/07-admin-eml-plugin-setup.mp4)) | Track B | 27s | 1939.6 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/07-admin-eml-plugin-setup.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/07-admin-eml-plugin-setup.srt) |
| 08 | [Sign In to OSCAR Viewer, Switch Language & Manage Nodes](#08-viewer-signin-language-and-nodes) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/08-viewer-signin-language-and-nodes.mp4)) | Track C | 31.5s | 3838.2 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/08-viewer-signin-language-and-nodes.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/08-viewer-signin-language-and-nodes.srt) |
| 09 | [Monitor Live 50-Lane Dashboard & Inspect Alarm Rows](#09-dashboard-monitoring-and-quick-adjudication) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/09-dashboard-monitoring-and-quick-adjudication.mp4)) | Track C | 29s | 2439.6 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/09-dashboard-monitoring-and-quick-adjudication.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/09-dashboard-monitoring-and-quick-adjudication.srt) |
| 10 | [Scope Workstation Lanes with Fail-Closed Operational Views](#10-operational-views-scoping) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/10-operational-views-scoping.mp4)) | Track C | 29s | 1164.3 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/10-operational-views-scoping.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/10-operational-views-scoping.srt) |
| 11 | [Inspect Live Lane Camera Stream & Gamma/Neutron Waveforms](#11-live-lane-video-and-charts) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/11-live-lane-video-and-charts.mp4)) | Track C | 62s | 3584.1 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/11-live-lane-video-and-charts.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/11-live-lane-video-and-charts.srt) |
| 12 | [Filter Event Log by UpSet Categories, Vehicle ID, Adjudication Code & Event UUID](#12-event-log-filtering-and-adjudication-codes) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/12-event-log-filtering-and-adjudication-codes.mp4)) | Track C | 56.5s | 4116.8 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/12-event-log-filtering-and-adjudication-codes.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/12-event-log-filtering-and-adjudication-codes.srt) |
| 13 | [Review Retained 5-Frame Media, Daily File Output & Adjudicate](#13-event-details-adjudication-and-daily-file) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/13-event-details-adjudication-and-daily-file.mp4)) | Track C | 39s | 2159.0 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/13-event-details-adjudication-and-daily-file.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/13-event-details-adjudication-and-daily-file.srt) |
| 14 | [Export Signed Alarm QR & Verify Offline on Air-Gapped Transfer](#14-airgapped-alarm-qr-transfer) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/14-airgapped-alarm-qr-transfer.mp4)) | Track C | 27s | 1628.5 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/14-airgapped-alarm-qr-transfer.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/14-airgapped-alarm-qr-transfer.srt) |
| 15 | [Monitor RPM/Camera Status of Health & Georeferenced Site Map](#15-status-of-health-and-site-map) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/15-status-of-health-and-site-map.mp4)) | Track C | 32.5s | 2886.0 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/15-status-of-health-and-site-map.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/15-status-of-health-and-site-map.srt) |
| 16 | [Analyze National View Statistics & Generate Multi-Format Reports](#16-national-statistics-and-reports) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/16-national-statistics-and-reports.mp4)) | Track C | 36s | 842.7 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/16-national-statistics-and-reports.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/16-national-statistics-and-reports.srt) |
| 17 | [Configure Vehicle OCR, Compare Multi-Pass Transits & Adjudicate](#17-vehicle-ocr-and-adjudication) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/17-vehicle-ocr-and-adjudication.mp4)) | Track C | 48.5s | 2912.5 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/17-vehicle-ocr-and-adjudication.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/17-vehicle-ocr-and-adjudication.srt) |
| 18 | [Use Flight Recorder, Help (?) & Redacted Support Bundles (UI & CLI)](#18-operator-help-and-support-bundle) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/18-operator-help-and-support-bundle.mp4)) | Track C | 37.5s | 3333.3 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/18-operator-help-and-support-bundle.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/18-operator-help-and-support-bundle.srt) |
| 19 | [Manage Users, Bulk QR Invites, Offline Passkeys & Federation Tokens](#19-viewer-users-passkeys-and-access) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/19-viewer-users-passkeys-and-access.mp4)) | Track C | 39.5s | 2798.3 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/19-viewer-users-passkeys-and-access.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/19-viewer-users-passkeys-and-access.srt) |
| 20 | [Federate Multi-Site Nodes, Search Vehicles Across Portals & Generate Reports](#20-multi-node-federation-vehicle-search-and-report) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/20-multi-node-federation-vehicle-search-and-report.mp4)) | Track C | 90s | 4423.5 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/20-multi-node-federation-vehicle-search-and-report.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/20-multi-node-federation-vehicle-search-and-report.srt) |
| 21 | [Onboard Authentik SSO Passkey Users & Revoke Access Across All Layers](#21-federated-sso-passkey-onboarding-and-revocation) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/21-federated-sso-passkey-onboarding-and-revocation.mp4)) | Track C | 39.5s | 1790.5 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/21-federated-sso-passkey-onboarding-and-revocation.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/21-federated-sso-passkey-onboarding-and-revocation.srt) |
| 22 | [Install, Configure & Run the End-to-End OSCAR Regression Suite](#22-regression-suite-setup-and-certification) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/22-regression-suite-setup-and-certification.mp4)) | Track D | 42.5s | 1748.3 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/22-regression-suite-setup-and-certification.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/22-regression-suite-setup-and-certification.srt) |
| 23 | [Prepare Windows 11 WSL 2 Hosts & Right-Size 100% Per-Lane OCR](#23-windows-wsl2-host-readiness-and-ocr-scaling) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/23-windows-wsl2-host-readiness-and-ocr-scaling.mp4)) | Track D | 55s | 13167.7 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/23-windows-wsl2-host-readiness-and-ocr-scaling.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/23-windows-wsl2-host-readiness-and-ocr-scaling.srt) |
| 24 | [Manage Continual & Occasional USB NVMe Backups & Safe Field Eject](#24-continual-and-occasional-usb-backups) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/24-continual-and-occasional-usb-backups.mp4)) | Track C | 43.5s | 1570.8 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/24-continual-and-occasional-usb-backups.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/24-continual-and-occasional-usb-backups.srt) |
| 25 | [Swap Pluggable OCR Packs & Air-Gapped Regional .pmtiles Basemaps](#25-pluggable-runtime-extensions-and-pmtiles) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/25-pluggable-runtime-extensions-and-pmtiles.mp4)) | Track C | 48s | 2039.9 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/25-pluggable-runtime-extensions-and-pmtiles.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/25-pluggable-runtime-extensions-and-pmtiles.srt) |
| 26 | [Stage Ubuntu 24.04 Off-Site & Cut Over to Air-Gapped Portal Subnets](#26-ubuntu-hotel-staging-and-airgapped-cutover) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/26-ubuntu-hotel-staging-and-airgapped-cutover.mp4)) | Track D | 33.5s | 1007.3 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/26-ubuntu-hotel-staging-and-airgapped-cutover.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/26-ubuntu-hotel-staging-and-airgapped-cutover.srt) |
| 27 | [Connect Cargo UFF SMB Shares, Search by UUID & Inspect 16-Bit Radiographs](#27-cargo-uff-smb-and-xray-inspection) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/27-cargo-uff-smb-and-xray-inspection.mp4)) | Track D | 55s | 3599.7 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/27-cargo-uff-smb-and-xray-inspection.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/27-cargo-uff-smb-and-xray-inspection.srt) |
| 28 | [Practice Safely in the Ephemeral Hands-On Training Sandbox & Guided Academy](#28-hands-on-training-sandbox) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/28-hands-on-training-sandbox.mp4)) | Track D | 79s | 3193.2 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/28-hands-on-training-sandbox.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/28-hands-on-training-sandbox.srt) |
| 29 | [Configure & Control Per-Lane Physical RPM Lights & Sound (WebRelay-Quad)](#29-lane-webrelay-lights-and-sound) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/29-lane-webrelay-lights-and-sound.mp4)) | Track C | 44s | 2607.8 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/29-lane-webrelay-lights-and-sound.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/29-lane-webrelay-lights-and-sound.srt) |

## Track A — CLI Deployment, Upgrades & Storage Lifecycle

<a id="01-deployment-init-and-credentials"></a>
### 01. Initialize OSCAR Deployment, Admin Credentials & TLS

Extract a clean OSCAR release archive, initialize administrator credentials and TLS SAN certificates with oscar init, and verify healthy container startup.

- **Video:** [Watch `01-deployment-init-and-credentials.mp4` (28.5s, 587.7 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/01-deployment-init-and-credentials.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/01-deployment-init-and-credentials.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/01-deployment-init-and-credentials.srt)

1. Extract `oscar-3.11.9.zip` into a clean release directory on Ubuntu Server 24.04 or Windows 11 and change into `oscar-3.11.9/`.
2. Run `sudo bash oscar.sh init` (or `.\oscar.bat init` on Windows 11) and supply the deployment hostname, IANA timezone, and administrator password (`>= 14` characters).
3. Allow `init` to generate deployment-bound PostgreSQL secrets, TLS gateway certificates, and external `oscar_oscar_state` / `oscar_postgres_data` volumes.
4. Run `sudo bash oscar.sh status` (or `.\oscar.bat status`) to confirm `oscar-gateway`, `oscar`, and `oscar-postgis` report `running (healthy)`.

<a id="02-clean-directory-upgrade"></a>
### 02. Upgrade OSCAR in a Clean Release Directory

Verify a pre-upgrade snapshot, copy only .env, secrets/, and tls/ into a newly extracted release folder, and run oscar upgrade while preserving external volumes.

- **Video:** [Watch `02-clean-directory-upgrade.mp4` (29.5s, 519.6 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/02-clean-directory-upgrade.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/02-clean-directory-upgrade.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/02-clean-directory-upgrade.srt)

1. When `single` backup mode is enabled, run `sudo bash oscar.sh backup` and `sudo bash oscar.sh backup-verify` from the active release directory before upgrading.
2. Extract the target `oscar-3.11.9.zip` archive into a separate sibling directory — never unzip over an existing release directory.
3. Copy only `.env`, `secrets/`, and `tls/` (plus `.oscar-volume-adoption` if previously adopted) into the newly extracted directory.
4. Run `sudo bash oscar.sh upgrade` (or `.\oscar.bat upgrade`) and confirm all containers return `healthy` with preserved named volumes and archive roots.

<a id="03-archive-and-snapshot-backup"></a>
### 03. Verify Parquet Cold-Tier Archives & Single-Snapshot Backup

Inspect PARQUET_PRIMARY cold-tier generation status, verify sealed Parquet SHA-256 parity receipts, and run a coordinated single-snapshot backup and verification.

- **Video:** [Watch `03-archive-and-snapshot-backup.mp4` (28.5s, 545.2 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/03-archive-and-snapshot-backup.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/03-archive-and-snapshot-backup.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/03-archive-and-snapshot-backup.srt)

1. Run `sudo bash oscar.sh archive status` (or `.\oscar.bat archive status`) to inspect `PARQUET_PRIMARY` staging windows, sealed generation counts, and parity receipts.
2. Run `sudo bash oscar.sh archive verify` to validate manifest SHA-256 checksums and row-count parity across immutable Parquet files.
3. Ensure `single` backup mode is configured with a non-overlapping absolute backup directory (`--backup-mode single --backup-dir <path>`).
4. Run `sudo bash oscar.sh backup` followed by `sudo bash oscar.sh backup-verify` to create and verify the coordinated PostGIS, state, and archive-generation snapshot.

## Track B — SensorHub Admin Configuration

<a id="04-admin-oscar-service-and-custom-codes"></a>
### 04. Configure OSCAR Service Retention & Custom Disposition Codes

Open Services -> OSCAR Service in SensorHub Admin to review 5-JPEG media retention settings, storage-pressure thresholds, and custom adjudication disposition codes.

- **Video:** [Watch `04-admin-oscar-service-and-custom-codes.mp4` (41.5s, 1040.3 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/04-admin-oscar-service-and-custom-codes.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/04-admin-oscar-service-and-custom-codes.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/04-admin-oscar-service-and-custom-codes.srt)

1. Open `https://oscar.local/sensorhub/admin`, expand **Services**, and select **OSCAR Service**.
2. Review **Video Retention Config** (`timeToRetention = 0`, `frameRetentionCount = 5`, `jpegQuality = 85`) and **Storage Pressure Retention Config**.
3. Expand **Custom Disposition Codes** to add or update site-specific adjudication code entries alongside built-in codes.
4. Click **Apply Changes** and **Save** in the top toolbar to persist the updated service configuration.

<a id="05-admin-lane-spreadsheet-sync"></a>
### 05. Sync Multi-Lane Spreadsheet Configuration (config.csv)

Import or download the multi-lane config.csv spreadsheet in OSCAR Service to provision RPM endpoints, RTSP cameras, and OperationalViews assignments in bulk.

- **Video:** [Watch `05-admin-lane-spreadsheet-sync.mp4` (30s, 682.8 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/05-admin-lane-spreadsheet-sync.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/05-admin-lane-spreadsheet-sync.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/05-admin-lane-spreadsheet-sync.srt)

1. Navigate to **Services -> OSCAR Service** in SensorHub Admin (`https://oscar.local/sensorhub/admin`).
2. Locate **Config File Path** / **Upload** under **General** to upload or export the site's multi-lane `config.csv` spreadsheet (including `OperationalViews` semicolon-delimited keys such as `east-gate;entrance`).
3. Click **Apply Changes** and **Save** to synchronize all lane definitions.
4. Expand **Sensors** in the left accordion to confirm every imported `Lane System` module is registered and online.

<a id="06-admin-manual-lane-and-site-diagram"></a>
### 06. Configure a Lane System & Georeferenced Site Diagram

Inspect individual Lane System location, Extended Occupancy Threshold (min), and camera/RPM options under Sensors, then configure the georeferenced facility Site Diagram bounding coordinates in OSCAR Service.

- **Video:** [Watch `06-admin-manual-lane-and-site-diagram.mp4` (41s, 1078.5 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/06-admin-manual-lane-and-site-diagram.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/06-admin-manual-lane-and-site-diagram.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/06-admin-manual-lane-and-site-diagram.srt)

1. Open **Sensors** in SensorHub Admin and select a **Lane System** module.
2. Review **General** (including **Extended Occupancy Threshold (min)** and **Operational View Keys**), **Fixed Location** (latitude/longitude coordinates), and **Lane Options** (RPM driver address and RTSP camera stream parameters).
3. Switch to **Services -> OSCAR Service** and inspect **Site Diagram Config** to upload a site map image and set georeferenced lower-left and upper-right coordinates.
4. Click **Apply Changes** and **Save** to publish lane coordinates and site map bounds to the Viewer.

<a id="07-admin-eml-plugin-setup"></a>
### 07. Upload External EML VM-250 Plugin & Enable Per-Lane EML

Verify or upload a separately licensed EML VM-250 .jar plugin in OSCAR Service, inspect per-lane EML enablement under Lane Options, and review built-in operator documentation.

- **Video:** [Watch `07-admin-eml-plugin-setup.mp4` (27s, 1939.6 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/07-admin-eml-plugin-setup.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/07-admin-eml-plugin-setup.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/07-admin-eml-plugin-setup.srt)

1. Open **Services -> OSCAR Service** in SensorHub Admin (`https://oscar.local/sensorhub/admin`).
2. Locate **EML Plugin Path** and use **Upload** to install the external licensed EML VM-250 `.jar` runtime into private state storage.
3. Open **Sensors -> <Rapiscan Lane> -> Lane Options** to verify per-lane EML analysis settings (`Collimated` / `Enable EML`).
4. Open the **README** tab in OSCAR Service to reference localized administrator guidance on automated `Code 9999: EML Non-Threat` adjudications.

## Track C — OSCAR Viewer Console Operations

<a id="08-viewer-signin-language-and-nodes"></a>
### 08. Sign In to OSCAR Viewer, Switch Language & Manage Nodes

Authenticate at the OSCAR TLS gateway login page (with Keep me signed in until I log out and offline Passkey support), switch console UI localization live across 4 languages, open the Operator Quick Guide (?), and configure federated OSCAR nodes.

- **Video:** [Watch `08-viewer-signin-language-and-nodes.mp4` (31.5s, 3838.2 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/08-viewer-signin-language-and-nodes.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/08-viewer-signin-language-and-nodes.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/08-viewer-signin-language-and-nodes.srt)

1. Open `https://oscar.local`, enter the operator **Username** and **Password** (with **Keep me signed in until I log out** enabled, or click **Sign in with a passkey**), and click **Sign in**.
2. Click the top-bar language selector (**English**) to switch the console interface live between `English`, `Español`, `Français`, and `Ελληνικά`, and click the `?` help icon to open the **Operator Quick Guide & Glossary**.
3. Open **Nodes** (`/servers`) from the navigation drawer to verify **Local Node** status or add federated OSCAR nodes using interactive browser sessions or scoped **Federation Service Tokens (`oscar_fed_...`)**.

<a id="09-dashboard-monitoring-and-quick-adjudication"></a>
### 09. Monitor Live 50-Lane Dashboard & Inspect Alarm Rows

Monitor real-time 50-lane status tiles and live alarm occupancy rows on the Dashboard, customize visible panels with Customize Dashboard, and launch rapid alarm review.

- **Video:** [Watch `09-dashboard-monitoring-and-quick-adjudication.mp4` (29s, 2439.6 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/09-dashboard-monitoring-and-quick-adjudication.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/09-dashboard-monitoring-and-quick-adjudication.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/09-dashboard-monitoring-and-quick-adjudication.srt)

1. Open the OSCAR **Dashboard** (`/`) to monitor real-time **Lane Status** tiles across all configured portal lanes and toggle **Customize Dashboard** to show or hide **Lane Status**, **Events**, or **Map**.
2. Review incoming occupancy and gamma/neutron alarm rows in the live Dashboard event table, sorting or customizing visible columns as needed.
3. Click a row's action menu (`⋮`) or double-click an alarm row to open immediate event inspection and adjudication controls.

<a id="10-operational-views-scoping"></a>
### 10. Scope Workstation Lanes with Fail-Closed Operational Views

Scope the Dashboard and Status of Health to an assigned workstation Operational View (?view=east-gate) and verify fail-closed protection on unassigned views.

- **Video:** [Watch `10-operational-views-scoping.mp4` (29s, 1164.3 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/10-operational-views-scoping.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/10-operational-views-scoping.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/10-operational-views-scoping.srt)

1. Open a workstation-scoped URL such as `https://oscar.local/?view=east-gate` and confirm the **`View: east-gate`** badge appears in the header.
2. Navigate to **Status of Health** (`/health?view=east-gate`) to verify that only lanes assigned to `east-gate` are loaded.
3. Verify that unassigned or malformed `?view=` keys fail closed with an explicit warning banner and zero loaded lane data.

<a id="11-live-lane-video-and-charts"></a>
### 11. Inspect Live Lane Camera Stream & Gamma/Neutron Waveforms

Open Lane Details from the Dashboard to watch live RTSP/HLS camera video alongside real-time Gamma and Neutron count-rate charts (including Show Individual Detectors and Separate Plots (Accessibility) toggles) and lane occupancy history.

- **Video:** [Watch `11-live-lane-video-and-charts.mp4` (62s, 3584.1 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/11-live-lane-video-and-charts.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/11-live-lane-video-and-charts.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/11-live-lane-video-and-charts.srt)

1. Click a lane tile under **Lane Status** on the Dashboard (`/`) to open **Lane Details** (`/lane-view`).
2. Monitor the live camera video player alongside the real-time **Gamma** (red) and **Neutron** (blue) count-rate waveform charts, and toggle **Show Individual Detectors** or **Separate Plots (Accessibility)** (`G1`–`G4`, `N1`–`N4`).
3. Scroll to the lane event table below the charts to inspect historical occupancies recorded on that lane.

<a id="12-event-log-filtering-and-adjudication-codes"></a>
### 12. Filter Event Log by UpSet Categories, Vehicle ID, Adjudication Code & Event UUID

Expand the Alarm Category Co-Occurrence (UpSet) panel to filter by populated-first main categories or combinations (including crimson Other SNM), correlate repeat occupancies by normalized Vehicle ID and Compare Passes, apply server-side Advanced Filters, and look up exact records by Event UUID.

- **Video:** [Watch `12-event-log-filtering-and-adjudication-codes.mp4` (56.5s, 4116.8 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/12-event-log-filtering-and-adjudication-codes.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/12-event-log-filtering-and-adjudication-codes.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/12-event-log-filtering-and-adjudication-codes.srt)

1. Navigate to **Event Log** (`/event-log`), enter a container or plate identifier in the **Vehicle / Container ID** search bar (ignoring case, spaces, and hyphens), click **SEARCH VEHICLE**, and click **COMPARE PASSES (`N`)** to inspect correlated transits.
2. Click **Alarm Category Co-Occurrence (UpSet)** (`Show`) to display populated main categories first (`Unknown`, `SNM`, `NORM`, `Medical`, `Industrial`, `Gamma`, `Neutron`), then click any populated **Categories** chip, combination bar, or rolled-up crimson **Other SNM** bar to filter the table.
3. Click **ADVANCED FILTERS** to filter server-side by date/time window, lane, alarm status, **Vehicle ID**, or **Adjudication Code** (including automated `Code 9998: Extended Occupancy Gamma Alarm`, `Code 9999: EML Non-Threat`, and custom codes).
4. Paste an occupancy observation identifier into **Event UUID** and click **FIND EVENT** to open that exact record.

<a id="13-event-details-adjudication-and-daily-file"></a>
### 13. Review Retained 5-Frame Media, Daily File Output & Adjudicate

Inspect five-frame retained JPEG camera evidence, toggle individual detector charts, examine exact RPM Daily File Output lines (hot journal or cold historical slice), and submit an append-only adjudication.

- **Video:** [Watch `13-event-details-adjudication-and-daily-file.mp4` (39s, 2159.0 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/13-event-details-adjudication-and-daily-file.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/13-event-details-adjudication-and-daily-file.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/13-event-details-adjudication-and-daily-file.srt)

1. Open **Event Details** (`/event-details?eventId=<id>`), verify the **Event UUID** header bar, and step through the five retained camera JPEG thumbnails under **Retained camera evidence**.
2. Toggle **Show Individual Detectors** / **Separate Plots (Accessibility)** on the waveform charts and scroll to **Daily File Output** to inspect exact `GS`, `GA`, `NS`, and `GX` RPM daily-file records.
3. Complete **Vehicle ID**, **Adjudicate** disposition code, **Secondary Inspection**, and **Notes** under **Adjudication Form**.
4. Click **Submit** and confirm in **Confirm Adjudication Submission** (`Confirm & Submit`) to append the signed audit record while preserving prior adjudications.

<a id="14-airgapped-alarm-qr-transfer"></a>
### 14. Export Signed Alarm QR & Verify Offline on Air-Gapped Transfer

Export a SHA-256-authenticated Alarm QR image from Event Details, then import and verify its cryptographic integrity and waveforms offline on Alarm Transfer.

- **Video:** [Watch `14-airgapped-alarm-qr-transfer.mp4` (27s, 1628.5 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/14-airgapped-alarm-qr-transfer.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/14-airgapped-alarm-qr-transfer.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/14-airgapped-alarm-qr-transfer.srt)

1. On **Event Details**, click **Export Alarm QR** to generate the `OSCAR-ALARM:1:` signed transfer payload.
2. Click **Download QR Image** (or **Download Alarm File**) to save the portable PNG QR symbol or JSON package.
3. Open **Alarm Transfer** (`/alarm-transfer`) on the receiving workstation and import the QR PNG image or scan via camera.
4. Confirm **`The alarm data passed its SHA-256 integrity check.`** and review the reconstructed occupancy UUID and Gamma/Neutron waveforms.

<a id="15-status-of-health-and-site-map"></a>
### 15. Monitor RPM/Camera Status of Health & Georeferenced Site Map

Track RPM connectivity, camera stream health, detector/tamper faults, and Fault - Extended Occupancy (Ext-Occ, with automated Code 9998 gamma-only alarm adjudication) on Status of Health, then inspect georeferenced lane markers on Site Map.

- **Video:** [Watch `15-status-of-health-and-site-map.mp4` (32.5s, 2886.0 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/15-status-of-health-and-site-map.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/15-status-of-health-and-site-map.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/15-status-of-health-and-site-map.srt)

1. Open **Status of Health** (`/health`) from the navigation drawer to inspect real-time RPM connectivity, camera stream status, and detector or tamper fault badges across every lane.
2. Review lane-level health indicators and `Fault - Extended Occupancy` (`Ext-Occ`) status (which suppresses gamma-only extended occupancy alarms from the Dashboard and auto-adjudicates them as `Code 9998: Extended Occupancy Gamma Alarm`).
3. Open **Map** (`/map`) to view georeferenced lane markers and real-time alarm/health status overlaid on the facility map.

<a id="16-national-statistics-and-reports"></a>
### 16. Analyze National View Statistics & Generate Multi-Format Reports

Review aggregated occupancy and alarm trends on National View, then configure and generate RDS Site, Lane, Event, Adjudication (starting with summed All Selected Lanes totals), Adjudication Details, or consolidated Vehicle Incident reports in PDF, CSV, JSON, or Excel (.xlsx) format.

- **Video:** [Watch `16-national-statistics-and-reports.mp4` (36s, 842.7 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/16-national-statistics-and-reports.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/16-national-statistics-and-reports.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/16-national-statistics-and-reports.srt)

1. Open **National View** (`/national-view`) to inspect aggregated occupancy totals, gamma/neutron alarm counts, and multi-lane trends.
2. Navigate to **Report Generator** (`/report`) and choose **Node Selector**, **Report Scope** (`Entire Node`, `Operational View`, or `Specific Lanes`), **Report Type** (`RDS_SITE`, `LANE`, `EVENT`, `ADJUDICATION`, `ADJUDICATION_DETAILS`, or `VEHICLE_INCIDENT`), **Export Format** (`PDF`, `CSV`, `JSON`, or `Excel (.xlsx)`), and **Time Range**.
3. When generating a **Vehicle Incident Report**, enter a normalized **Vehicle ID** (or leave blank for all tagged vehicles), click **Generate Report**, and review the rendered PDF or inline tabular preview (`CSV`, `JSON`, `XLSX`) before downloading.

<a id="17-vehicle-ocr-and-adjudication"></a>
### 17. Configure Vehicle OCR, Compare Multi-Pass Transits & Adjudicate

Inspect optional per-lane Vehicle OCR configuration in SensorHub Admin, open an alarm in Event Details to review ISO 6346 container auto-fill, OCR suggestion chips, and Multi-Pass Vehicle History, compare overlaid radiation traces across passes, and record an adjudication.

- **Video:** [Watch `17-vehicle-ocr-and-adjudication.mp4` (48.5s, 2912.5 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/17-vehicle-ocr-and-adjudication.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/17-vehicle-ocr-and-adjudication.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/17-vehicle-ocr-and-adjudication.srt)

1. Open **Sensors -> <Lane System> -> Vehicle OCR** in SensorHub Admin (`https://oscar.local/sensorhub/admin`) to review **Enable Vehicle OCR**, **Alarms Only**, **Frames Per Clip**, and confidence thresholds.
2. Open **Event Details** (`/event-details?eventId=<id>`) in OSCAR Viewer for an alarm occupancy on an OCR-enabled lane to verify ISO 6346 **Vehicle ID** auto-fill, clickable OCR suggestion chips, and the **Multi-Pass Vehicle History** correlation banner.
3. Click **COMPARE PASSES** to inspect chronological confirmation re-scans or secondary spectroscopic transits, visual continuity crops, and on-demand overlaid gamma/neutron radiation traces.
4. Select an **Adjudicate** disposition code and **Secondary Inspection** status, click **Submit**, and confirm in **Confirm Adjudication Submission** to append the signed audit decision.

<a id="18-operator-help-and-support-bundle"></a>
### 18. Use Flight Recorder, Help (?) & Redacted Support Bundles (UI & CLI)

Open Help (?) to browse the localized Operator Quick Guide & Glossary, export the built-in 400-event browser Flight Recorder + rolling server logs into oscar-support-<UTC>.zip (or run oscar.sh / oscar.bat support-bundle offline), and inspect summary.json and redaction-report.json.

- **Video:** [Watch `18-operator-help-and-support-bundle.mp4` (37.5s, 3333.3 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/18-operator-help-and-support-bundle.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/18-operator-help-and-support-bundle.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/18-operator-help-and-support-bundle.srt)

1. Click the **Help (`?`)** button in the OSCAR Viewer top navigation bar to open the localized **OSCAR 3.11.9 Operator Quick Guide & Glossary** (`en`, `es`, `fr`, `el`).
2. Open **Manual & Video Guides** and click **Export Support Bundle** to merge the 400-event browser Flight Recorder (`client/client-diagnostics.json`) with rolling server logs (`backend/oscar.log`) into `oscar-support-<UTC>.zip` (automatically falling back to `oscar-client-support-<UTC>.zip` if the server is offline).
3. When containers are stopped or unreachable over HTTPS, run `sudo bash oscar.sh support-bundle` (Ubuntu) or `.\oscar.bat support-bundle` (Windows) on the host to capture `oscar-host-support-<UTC>.zip`.
4. Inspect `summary.json`, `client/client-diagnostics.json`, and `redaction-report.json` to review recent errors and confirm automatic `[REDACTED]` credential scrubbing.

<a id="19-viewer-users-passkeys-and-access"></a>
### 19. Manage Users, Bulk QR Invites, Offline Passkeys & Federation Tokens

Open Users & Access (/users) to enroll offline WebAuthn Passkeys (with local passwords independent of Octelium tunnel credentials), bulk-enroll a CSV user list with 1-tap setup QR codes, mint scoped Federation Service Tokens, and launch Servers (/servers?auth=bearer) in Federation Token mode.

- **Video:** [Watch `19-viewer-users-passkeys-and-access.mp4` (39.5s, 2798.3 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/19-viewer-users-passkeys-and-access.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/19-viewer-users-passkeys-and-access.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/19-viewer-users-passkeys-and-access.srt)

1. Open **Users & Access** (`/users`) from the navigation drawer (or click your username in the top bar) to inspect your persistent session status (`Stays signed in until you click Log Out`), register offline **Passkeys / YubiKeys**, or update your local OSCAR password (which is completely separate from any Octelium Zero-Trust tunnel credentials).
2. Switch to **Users & Roles** and click **Bulk Enroll (CSV / Paste)** to upload or paste a CSV/Excel user list (`username, role, display_name, views`), preview validated rows, and click **Enroll User(s) & Generate QR Pack**.
3. Copy or print the generated **Startup Messages & 1-Tap Setup QR Codes** (`/login/enroll?token=oscar_inv_...`, including fallback workstation codes for phone-free facilities).
4. Open **Federation Tokens**, mint a least-privilege `oscar_fed_...` token, and click **Open Servers Page (Federation Token Mode)** (`/servers?auth=bearer`) on the NOC/HQ viewer to paste the token into **Servers** (`HTTPS`, port `443`).

<a id="20-multi-node-federation-vehicle-search-and-report"></a>
### 20. Federate Multi-Site Nodes, Search Vehicles Across Portals & Generate Reports

Mint a scoped oscar_fed_* Federation Service Token on a remote portal, register the remote HTTPS node on the Central HQ Viewer, verify combined lane counts in National View, correlate transits across nodes in Events -> Compare Passes, and export a unified multi-node Vehicle Incident Report (JSON & PDF).

- **Video:** [Watch `20-multi-node-federation-vehicle-search-and-report.mp4` (90s, 4423.5 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/20-multi-node-federation-vehicle-search-and-report.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/20-multi-node-federation-vehicle-search-and-report.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/20-multi-node-federation-vehicle-search-and-report.srt)

1. On the remote OSCAR portal, open **Users & Access (`/users`) -> Federation Tokens**, enter a descriptive node label, select `Viewer` or `Operator`, and click **Create Federation Token** to mint a revocable `oscar_fed_...` bearer credential.
2. On the primary/HQ OSCAR Viewer, open **Servers (`/servers`)**, enter the remote portal's **Name**, **Address**, and **Port `443`** with **Use a secure connection** checked, select **Federation Service Token**, paste the `oscar_fed_...` token, and click **Add Node**.
3. Verify combined multi-node statistics in **National View (`/national-view`)**, then open **Events (`/event-log`)**, enter an ISO 6346 container ID or license plate, and click **Compare Passes** to inspect cross-node crossings, OCR crops, and UpSet co-occurrence.
4. Open **Report Generator (`/report`)**, choose **Vehicle Incident Report**, keep **Include correlated passes from federated nodes** checked, and generate consolidated `JSON`, `CSV`, `Excel (.xlsx)`, and `PDF` reports containing transits from all federated nodes.

<a id="21-federated-sso-passkey-onboarding-and-revocation"></a>
### 21. Onboard Authentik SSO Passkey Users & Revoke Access Across All Layers

Create centralized operator and viewer accounts in Authentik, map roles via oscar-admins, oscar-operators, and oscar-viewers, issue single-use 1-tap SSO Passkey enrollment links, and permanently revoke access across Authentik, Octelium Zero-Trust Hub, and OSCAR /users.

- **Video:** [Watch `21-federated-sso-passkey-onboarding-and-revocation.mp4` (39.5s, 1790.5 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/21-federated-sso-passkey-onboarding-and-revocation.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/21-federated-sso-passkey-onboarding-and-revocation.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/21-federated-sso-passkey-onboarding-and-revocation.srt)

1. In **Authentik Admin (`https://auth.hub.example.org/if/admin/`) -> Directory -> Users**, click **Create**, enter the username, display name, and email address, and add the user to `oscar-admins`, `oscar-operators`, or `oscar-viewers`.
2. Open the user's **Overview** tab and click **Create Recovery Link** to copy a single-use `oscar-passkey-onboarding` URL so the recipient registers their FIDO2 Passkey in one tap.
3. To completely offboard a user, select the account in **Authentik -> Directory -> Users**, click **Delete**, and confirm permanent deletion; `oscar-hub-sync.timer` automatically purges the `managed-by: authentik-sync` user from Octelium within 30 seconds (or immediately via `sudo ./oscar-hub.sh sync-users`).
4. Open **Users & Access -> Users & Roles (`/users`)** on federated OSCAR nodes and delete any cached user profile row to clear active browser cookies.

<a id="24-continual-and-occasional-usb-backups"></a>
### 24. Manage Continual & Occasional USB NVMe Backups & Safe Field Eject

Open USB Backups (/usb-backups) to inspect an attached NTFS external USB 3.x NVMe SSD, configure Continual vs. Occasional zero-downtime sync, run an on-demand incremental backup, download the off-site recovery key, and perform a 1-click Safely Eject USB Drive offload.

- **Video:** [Watch `24-continual-and-occasional-usb-backups.mp4` (43.5s, 1570.8 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/24-continual-and-occasional-usb-backups.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/24-continual-and-occasional-usb-backups.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/24-continual-and-occasional-usb-backups.srt)

1. Open **USB Backups (`/usb-backups`)** from the left navigation drawer to inspect the attached external USB 3.x NVMe SSD (`ATTACHED & ONLINE`), carrier capacity, PostgreSQL WAL LSN, and deduplicated Parquet/media pack counts.
2. Under **Backup Mode & Sync Schedule**, choose **Continual Background Sync** (`15 min` default, `0.0 s` portal outage with automatic USB reconnect catch-up) or **Occasional / On-Demand Visit Sync**, and click **Save Mode & Schedule**.
3. Click **Sync Incremental Snapshot Now** to capture new sealed Parquet daily packs, retained media/OCR crops, and an encrypted PostgreSQL checkpoint, and click **Download Off-Site Recovery Key (`backup-key.txt`)** to store the decryption key in off-site escrow.
4. Before unplugging the drive for laptop offload (`COPY-TO-ANOTHER-DRIVE.bat` or `./copy-to-another-drive.sh`) or cold-iron recovery (`sudo bash oscar.sh usb-backup restore`), click **Safely Eject USB Drive** and wait for the green **SAFE TO UNPLUG** banner.

<a id="25-pluggable-runtime-extensions-and-pmtiles"></a>
### 25. Swap Pluggable OCR Packs & Air-Gapped Regional .pmtiles Basemaps

Open Runtime Extensions (/extensions) to inspect OSCAR's shipped built-in defaults, hot-swap a Unicode regional OCR plate-rule pack and an offline PMTiles v3 (.pmtiles) regional basemap, render live portal lane markers offline on Map (/map), review Spectroscopy, Trusted CAs, Policy Packs & EML, and restore shipped defaults.

- **Video:** [Watch `25-pluggable-runtime-extensions-and-pmtiles.mp4` (48s, 2039.9 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/25-pluggable-runtime-extensions-and-pmtiles.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/25-pluggable-runtime-extensions-and-pmtiles.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/25-pluggable-runtime-extensions-and-pmtiles.srt)

1. Open **Runtime Extensions (`/extensions`)** from the left navigation drawer to review the six upgrade-safe extension domains (`OCR Models & Engines`, `Offline Maps (.pmtiles)`, `Spectroscopy / Nuclide ID`, `Trusted CA Certificates`, `Adjudication Policy Packs`, and `EML Alarm Assessment`) persisted under `/var/lib/oscar/extensions/`.
2. On **OCR Models & Engines**, upload a compliant `plate-rules.json` or ONNX/SPI `.zip` package to activate regional non-Latin or numeric plate rules (`CUSTOM OVERRIDE (UPGRADE-SAFE)`) while inheriting OSCAR's shipped PP-OCRv3 + PARSeq models.
3. Switch to **Offline Maps (`.pmtiles`)**, enter a layer display name, upload a Protomaps **PMTiles v3** regional archive (`pmtiles extract ...`), and open **Map (`/map`)** to view live portal lane markers over `Offline: <Layer Name>` via HTTP `206` byte-range serving with zero internet requests.
4. Browse **Spectroscopy**, **Trusted CA Certificates**, **Adjudication Policy Packs**, and **EML Alarm Assessment**, or click **Reset to Shipped Default** on any tab to revert immediately with zero portal downtime.

## Track D — End-to-End Regression & Multi-OS Capacity Scaling

<a id="22-regression-suite-setup-and-certification"></a>
### 22. Install, Configure & Run the End-to-End OSCAR Regression Suite

Install ORNL/oscar-regression, run all 246 offline unit tests, configure .env capability gates and 4-layer safety interlocks, execute smoke, full, 3.11.0-release, restore-drill, and ui-endurance profiles across all 23 functional scenarios, and inspect summary.md and CSV evidence.

- **Video:** [Watch `22-regression-suite-setup-and-certification.mp4` (42.5s, 1748.3 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/22-regression-suite-setup-and-certification.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/22-regression-suite-setup-and-certification.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/22-regression-suite-setup-and-certification.srt)

1. Clone [`ORNL/oscar-regression`](https://github.com/ORNL/oscar-regression), run `npm ci` and `npm run install:browser`, and verify TypeScript compilation and all 246 offline unit tests with `npm run check && npm test`.
2. Copy `.env.example` to `.env` (`chmod 600 .env`), set target, emulator, `RPM_LANE_MAPPING_ACK`, and `DISPOSABLE-STORAGE` safety interlocks, and run `./scripts/rebind-active-release.sh --apply --build-label <label>` after clean-directory upgrades.
3. Execute `npm run test:smoke` (`13` read-only scenarios), `npm run test:full` (`23` scenarios including faults, alarms, Vehicle OCR, EML, and `PARQUET_PRIMARY` retirement), `npm run test:3.11.0-release`, `npm run test:restore-drill`, `./scripts/run-ui-endurance.sh`, or `-- --scenario <list>`.
4. Review `results/<UTC-timestamp>-<runner>/summary.md`, `functional-results.csv`, `performance.csv`, `storage-performance.csv`, `errors.csv`, and `evidence/` screenshots (`exit 0` requires `0` incorrect checks).

<a id="23-windows-wsl2-host-readiness-and-ocr-scaling"></a>
### 23. Prepare Windows 11 WSL 2 Hosts & Right-Size 100% Per-Lane OCR

Prepare unattended 24/7 Windows 11 + WSL 2 hosts with oscar.bat prepare-host, attach outbound Zero-Trust tunnels, and size 100% Container & License Plate OCR cleanly (6 OCR lanes on Windows 11 WSL 2 vs. 50 OCR lanes on Ubuntu Server 24.04 bare-metal) without 5 Hz RPM sample bunching.

- **Video:** [Watch `23-windows-wsl2-host-readiness-and-ocr-scaling.mp4` (55s, 13167.7 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/23-windows-wsl2-host-readiness-and-ocr-scaling.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/23-windows-wsl2-host-readiness-and-ocr-scaling.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/23-windows-wsl2-host-readiness-and-ocr-scaling.srt)

1. On Windows 11 x86-64 (Administrator PowerShell 5.1), run `.\oscar.bat host-check` and `.\oscar.bat prepare-host` to enable High Performance AC power, disable sleep/USB suspend, and write bounded `%USERPROFILE%\.wslconfig` limits.
2. Attach firewalled portals outbound over TLS `443` via `.\oscar-remote-access.ps1 configure` (Windows) or `sudo bash oscar-remote-access.sh configure` (Ubuntu).
3. When enabling `100%` per-lane Container & License Plate OCR (`ocrConfig.enabled = true`), size Windows 11 + WSL 2 deployments to `1–8` lanes (such as `6` lanes) so Hyper-V/WSL 2 network virtualization maintains smooth `200 ms` (`5 Hz`) radiation plots, and deploy `25–50` OCR-enabled lanes on Ubuntu Server 24.04 bare-metal.

<a id="26-ubuntu-hotel-staging-and-airgapped-cutover"></a>
### 26. Stage Ubuntu 24.04 Off-Site & Cut Over to Air-Gapped Portal Subnets

Unpack the self-contained Ubuntu 24.04 offline bundle on hotel/office Wi-Fi, identify physical NICs by carrier blink, pre-stage the portal's static Netplan YAML without dropping SSH, expand Ubuntu LVM root storage and initialize OSCAR offline, then cut over on-site and discover RPMs and RTSP cameras.

- **Video:** [Watch `26-ubuntu-hotel-staging-and-airgapped-cutover.mp4` (33.5s, 1007.3 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/26-ubuntu-hotel-staging-and-airgapped-cutover.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/26-ubuntu-hotel-staging-and-airgapped-cutover.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/26-ubuntu-hotel-staging-and-airgapped-cutover.srt)

1. Off-site (hotel or staging bench), extract `oscar-3.11.9-ubuntu-x86_64-offline-full.zip`, verify bundle checksums (`sudo bash verify-bundle.sh`), and run `sudo bash oscar.sh identify-nics --watch` while plugging a patch cord into the target NIC to confirm its Linux interface name (`enp2s0`).
2. Stage the portal's static IPv4 configuration safely without touching active Wi-Fi/SSH via `sudo bash oscar.sh stage-site-network --interface enp2s0 --ip 198.51.100.10/24 --gateway 198.51.100.1`.
3. Run `sudo bash oscar.sh prepare-host --offline --expand-lvm` to expand Ubuntu Server's default `100 GiB` LVM logical volume across the full NVMe disk and install offline `.deb` packages, then run `sudo bash oscar.sh init --offline` to load air-gapped container images and initialize credentials.
4. On-site inside the air-gapped portal rack, apply the pre-staged static subnet with `sudo bash oscar.sh apply-site-network` and scan the sensor LAN with `sudo bash oscar.sh discover-devices --interface enp2s0` to verify Rapiscan RPM (`10001–10050`) and RTSP camera (`554`/`8554`) endpoints.

<a id="27-cargo-uff-smb-and-xray-inspection"></a>
### 27. Connect Cargo UFF SMB Shares, Search by UUID & Inspect 16-Bit Radiographs

Connect a read-only SMBv2/SMBv3 Cargo NII share in Runtime Extensions (`/extensions`), look up unlabelled WCO `UFF 2.0` / `UFF 3.0.0` scans by UUID or 1-character fuzzy container OCR, inspect 16-bit `uint16` TIFF radiographs with HEMD atomic-number (`Z_eff`) bands aligned to the RPM gamma/neutron count profile, and link scans to adjudications.

- **Video:** [Watch `27-cargo-uff-smb-and-xray-inspection.mp4` (55s, 3599.7 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/27-cargo-uff-smb-and-xray-inspection.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/27-cargo-uff-smb-and-xray-inspection.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/27-cargo-uff-smb-and-xray-inspection.srt)

1. Open **Runtime Extensions (`/extensions`) -> Cargo NII (WCO UFF)**, enter a read-only SMBv2/SMBv3 share URL and credentials, click **Test Connection** to verify latency and indexed `.uff` count, and click **Save & Apply**.
2. Open **Events (`/event-log`)** and paste an unlabelled **Tier-1** UFF UUID or `<uuid>.uff` filename into the search bar (or open **Browse Cargo UFF** in **Event Details** to filter by scanner lane, alarm window, or `OCR ±1` fuzzy container correlation).
3. Launch **Open Cargo X-Ray** to adjust `0–65,535` 16-bit Window/Level, **Log Attenuation**, **High-Z Strip**, and **HEMD** `Organic` / `NORM` / `High-Z` bands alongside the synchronized **RPM Gamma & Neutron** strip, then click **Link to Adjudication**.

<a id="28-hands-on-training-sandbox"></a>
### 28. Practice Safely in the Ephemeral Hands-On Training Sandbox & Guided Academy

Launch the isolated ephemeral Training Sandbox (`:8444`) with zero production database or Parquet writes, inject live Rapiscan RPM alarms and NORM/fault scenarios from the Training Coach, practice SensorHub Admin lane setup in Split-Pane mode, and export a watermarked PDF Training Completion Record.

- **Video:** [Watch `28-hands-on-training-sandbox.mp4` (79s, 3193.2 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/28-hands-on-training-sandbox.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/28-hands-on-training-sandbox.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/28-hands-on-training-sandbox.srt)

1. Start the isolated sandbox (`sudo bash oscar.sh sandbox start`, `.\oscar.bat sandbox start`, or `Help (?) -> Launch Hands-On Training Sandbox`), open `:8444`, and confirm the single-row **TRAINING SANDBOX** badge and **Training Coach** dock.
2. Select **Track 1 — Operator (`Lab 1.3`)** on `/event-log`, click **Inject Distributed NORM (Code 9999)**, and watch the live loopback Rapiscan + EML pipeline auto-verify the lab outcome.
3. Switch to **Track 3 — Administrator** and click **Open Split-Pane SensorHub Admin** to configure lanes against loopback `127.0.0.1:10099` and `rtsp://127.0.0.1:8554/tutorial-cam` (or import `tutorial-1-lane.csv`) beside the Guided Coach.
4. Enter the trainee name to download a watermarked 1-page PDF **Training Completion Record**, then run `oscar.sh sandbox stop` (`oscar.bat sandbox stop`) to flush all disposable sandbox volumes in under 2 seconds.

<a id="29-lane-webrelay-lights-and-sound"></a>
### 29. Configure & Control Per-Lane Physical RPM Lights & Sound (WebRelay-Quad)

Configure per-lane ControlByWeb WebRelay-Quad HTTP/XML control in Status of Health (`/health`) or Lane View (`/lane-view`), inspect live `R1–R4` coil telemetry and `Code 9999` / `Code 9998` suppression counts, fire timed commissioning pulses on Gamma Red + Siren (`R3`) and Neutron Blue (`R4`), and verify fail-safe `0,0,0,0` pass-through.

- **Video:** [Watch `29-lane-webrelay-lights-and-sound.mp4` (44s, 2607.8 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/29-lane-webrelay-lights-and-sound.mp4) · [WebVTT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/29-lane-webrelay-lights-and-sound.vtt) · [SRT Captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/29-lane-webrelay-lights-and-sound.srt)

1. Sign in as an **Administrator**, open **Status of Health (`/health`)** or **Lane View (`/lane-view`)**, and click **Lights & Sound** on the target lane row to open the native `<dialog>` control modal.
2. Expand **WebRelay Endpoint & Policy Settings**, enter the lane's ControlByWeb `WebRelay-Quad` IPv4/hostname (`198.51.100.21`), port (`80`), pulse duration (`5 s`), and mode (`AUTO`), click **Test Connection**, and click **Save & Apply to Lane**.
3. Verify `R1=1` and `R2=1` intercept coils arm in `AUTO` mode (suppressing physical beacon/siren triggers on `Code 9999: EML Non-Threat` and optional `Code 9998`), then click **Pulse Gamma Light + Sound (`R3`)** and **Pulse Neutron Blue (`R4`)** to confirm timed commissioning outputs.
4. Click **Hardware Pass-Through (`0,0,0,0`)** or **Mute Outputs (`1,1,0,0`)** when needed during maintenance, or click **Return to Automatic (`AUTO`)** for normal gatehouse operation.
