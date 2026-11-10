# OSCAR 3.11.0 How-To Video Guides

Concise, single-task `1920x1080` workflow screen recordings for **OSCAR 3.11.0**, published in [`ORNL/oscar-video-guides`](https://github.com/ORNL/oscar-video-guides) and mounted as a Git submodule at `docs/video-guides` in source checkouts (`git submodule update --init docs/video-guides`).

Every module starts immediately at `00:00` with the workflow action, runs under 2 minutes, includes embedded MP4 `mov_text` soft subtitles plus standalone WebVTT (`.vtt`) and SubRip (`.srt`) caption tracks, and pairs with a 3-to-4-step sequential reference block below.

## Technical Encoding Specification

| Parameter | Specification |
| --- | --- |
| Hardware Encoder | NVIDIA GeForce RTX 5060 Ti `h264_nvenc` (`High@L4.1`, `avc1`) |
| Container & Color | Universal `.mp4` (`+faststart`), `NV12` / `4:2:0` (`yuv420p`), `BT.709` |
| Compression & GOP | `10 s` forced IDR keyframe interval (`GOP 300 @ 30fps`) + `mpdecimate` differential static-frame dropping + NVENC `p7`/`hq` |
| Resolution & Framerate | `1920x1080` (`1080p`) capped at `30 FPS` peak variable framerate (VFR) |
| Accessibility | Embedded MP4 `mov_text` soft captions + standalone `.vtt` and `.srt` files + 3-to-4-step Markdown blocks |

> **Interactive HTML5 Player with Closed Captions:** In a source checkout with submodules initialized, open `docs/video-guides/index.html` in any browser to watch all 16 modules with synchronized closed captions enabled by default.

## Workflow Catalog

| # | Workflow Guide | Track | Duration | Size | Video & Captions |
| --- | --- | --- | --- | --- | --- |
| 01 | [Initialize OSCAR Deployment, Admin Credentials & TLS](#01-deployment-init-and-credentials) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/01-deployment-init-and-credentials.mp4)) | Track A | 11.2s | 201 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/01-deployment-init-and-credentials.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/01-deployment-init-and-credentials.srt) |
| 02 | [Upgrade OSCAR in a Clean Release Directory](#02-clean-directory-upgrade) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/02-clean-directory-upgrade.mp4)) | Track A | 12.8s | 293.5 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/02-clean-directory-upgrade.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/02-clean-directory-upgrade.srt) |
| 03 | [Verify Parquet Cold-Tier Archives & Single-Snapshot Backup](#03-archive-and-snapshot-backup) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/03-archive-and-snapshot-backup.mp4)) | Track A | 11.4s | 193.1 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/03-archive-and-snapshot-backup.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/03-archive-and-snapshot-backup.srt) |
| 04 | [Configure OSCAR Service Retention & Custom Disposition Codes](#04-admin-oscar-service-and-custom-codes) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/04-admin-oscar-service-and-custom-codes.mp4)) | Track B | 12.3s | 693.4 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/04-admin-oscar-service-and-custom-codes.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/04-admin-oscar-service-and-custom-codes.srt) |
| 05 | [Sync Multi-Lane Spreadsheet Configuration (config.csv)](#05-admin-lane-spreadsheet-sync) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/05-admin-lane-spreadsheet-sync.mp4)) | Track B | 10.6s | 418.8 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/05-admin-lane-spreadsheet-sync.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/05-admin-lane-spreadsheet-sync.srt) |
| 06 | [Configure a Lane System & Georeferenced Site Diagram](#06-admin-manual-lane-and-site-diagram) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/06-admin-manual-lane-and-site-diagram.mp4)) | Track B | 14.9s | 785 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/06-admin-manual-lane-and-site-diagram.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/06-admin-manual-lane-and-site-diagram.srt) |
| 07 | [Upload External EML VM-250 Plugin & Enable Per-Lane EML](#07-admin-eml-plugin-setup) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/07-admin-eml-plugin-setup.mp4)) | Track B | 11.8s | 818.1 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/07-admin-eml-plugin-setup.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/07-admin-eml-plugin-setup.srt) |
| 08 | [Sign In to OSCAR Viewer, Switch Language & Manage Nodes](#08-viewer-signin-language-and-nodes) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/08-viewer-signin-language-and-nodes.mp4)) | Track C | 16.9s | 3020.4 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/08-viewer-signin-language-and-nodes.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/08-viewer-signin-language-and-nodes.srt) |
| 09 | [Monitor Live 50-Lane Dashboard & Inspect Alarm Rows](#09-dashboard-monitoring-and-quick-adjudication) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/09-dashboard-monitoring-and-quick-adjudication.mp4)) | Track C | 12.9s | 939.5 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/09-dashboard-monitoring-and-quick-adjudication.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/09-dashboard-monitoring-and-quick-adjudication.srt) |
| 10 | [Scope Workstation Lanes with Fail-Closed Operational Views](#10-operational-views-scoping) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/10-operational-views-scoping.mp4)) | Track C | 11.4s | 662.3 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/10-operational-views-scoping.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/10-operational-views-scoping.srt) |
| 11 | [Inspect Live Lane Camera Stream & Gamma/Neutron Waveforms](#11-live-lane-video-and-charts) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/11-live-lane-video-and-charts.mp4)) | Track C | 12s | 2359.3 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/11-live-lane-video-and-charts.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/11-live-lane-video-and-charts.srt) |
| 12 | [Filter Event Log by Lane, Adjudication Code & Event UUID](#12-event-log-filtering-and-adjudication-codes) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/12-event-log-filtering-and-adjudication-codes.mp4)) | Track C | 10.9s | 1145.7 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/12-event-log-filtering-and-adjudication-codes.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/12-event-log-filtering-and-adjudication-codes.srt) |
| 13 | [Review Retained 5-Frame Media, Daily File Output & Adjudicate](#13-event-details-adjudication-and-daily-file) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/13-event-details-adjudication-and-daily-file.mp4)) | Track C | 19.4s | 1216.1 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/13-event-details-adjudication-and-daily-file.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/13-event-details-adjudication-and-daily-file.srt) |
| 14 | [Export Signed Alarm QR & Verify Offline on Air-Gapped Transfer](#14-airgapped-alarm-qr-transfer) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/14-airgapped-alarm-qr-transfer.mp4)) | Track C | 25.2s | 1723.7 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/14-airgapped-alarm-qr-transfer.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/14-airgapped-alarm-qr-transfer.srt) |
| 15 | [Monitor RPM/Camera Status of Health & Georeferenced Site Map](#15-status-of-health-and-site-map) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/15-status-of-health-and-site-map.mp4)) | Track C | 10.2s | 1251.1 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/15-status-of-health-and-site-map.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/15-status-of-health-and-site-map.srt) |
| 16 | [Analyze National View Statistics & Generate Multi-Format Reports](#16-national-statistics-and-reports) ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/16-national-statistics-and-reports.mp4)) | Track C | 17.1s | 544.2 KiB | [VTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/16-national-statistics-and-reports.vtt) · [SRT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/16-national-statistics-and-reports.srt) |

## Track A — CLI Deployment, Upgrades & Storage Lifecycle

<a id="01-deployment-init-and-credentials"></a>
### 01. Initialize OSCAR Deployment, Admin Credentials & TLS

Extract a clean OSCAR release archive, initialize administrator credentials and TLS SAN certificates with oscar init, and verify healthy container startup.

- **Screen Recording:** [`01-deployment-init-and-credentials.mp4` (11.2s, 201 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/01-deployment-init-and-credentials.mp4) · [WebVTT Captions (`.vtt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/01-deployment-init-and-credentials.vtt) · [SubRip Captions (`.srt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/01-deployment-init-and-credentials.srt)

1. Extract `oscar-3.11.0.zip` into a clean release directory on Ubuntu Server 24.04 or Windows 11 and change into `oscar-3.11.0/`.
2. Run `sudo bash oscar.sh init` (or `.\oscar.bat init` on Windows 11) and supply the deployment hostname, IANA timezone, and administrator password (`>= 14` characters).
3. Allow `init` to generate deployment-bound PostgreSQL secrets, TLS gateway certificates, and external `oscar_oscar_state` / `oscar_postgres_data` volumes.
4. Run `sudo bash oscar.sh status` (or `.\oscar.bat status`) to confirm `oscar-gateway`, `oscar`, and `oscar-postgis` report `running (healthy)`.

<a id="02-clean-directory-upgrade"></a>
### 02. Upgrade OSCAR in a Clean Release Directory

Verify a pre-upgrade snapshot, copy only .env, secrets/, and tls/ into a newly extracted release folder, and run oscar upgrade while preserving external volumes.

- **Screen Recording:** [`02-clean-directory-upgrade.mp4` (12.8s, 293.5 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/02-clean-directory-upgrade.mp4) · [WebVTT Captions (`.vtt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/02-clean-directory-upgrade.vtt) · [SubRip Captions (`.srt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/02-clean-directory-upgrade.srt)

1. When `single` backup mode is enabled, run `sudo bash oscar.sh backup` and `sudo bash oscar.sh backup-verify` from the active release directory before upgrading.
2. Extract the target `oscar-3.11.0.zip` archive into a separate sibling directory — never unzip over an existing release directory.
3. Copy only `.env`, `secrets/`, and `tls/` (plus `.oscar-volume-adoption` if previously adopted) into the newly extracted directory.
4. Run `sudo bash oscar.sh upgrade` (or `.\oscar.bat upgrade`) and confirm all containers return `healthy` with preserved named volumes and archive roots.

<a id="03-archive-and-snapshot-backup"></a>
### 03. Verify Parquet Cold-Tier Archives & Single-Snapshot Backup

Inspect PARQUET_PRIMARY cold-tier generation status, verify sealed Parquet SHA-256 parity receipts, and run a coordinated single-snapshot backup and verification.

- **Screen Recording:** [`03-archive-and-snapshot-backup.mp4` (11.4s, 193.1 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/03-archive-and-snapshot-backup.mp4) · [WebVTT Captions (`.vtt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/03-archive-and-snapshot-backup.vtt) · [SubRip Captions (`.srt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/03-archive-and-snapshot-backup.srt)

1. Run `sudo bash oscar.sh archive status` (or `.\oscar.bat archive status`) to inspect `PARQUET_PRIMARY` staging windows, sealed generation counts, and parity receipts.
2. Run `sudo bash oscar.sh archive verify` to validate manifest SHA-256 checksums and row-count parity across immutable Parquet files.
3. Ensure `single` backup mode is configured with a non-overlapping absolute backup directory (`--backup-mode single --backup-dir <path>`).
4. Run `sudo bash oscar.sh backup` followed by `sudo bash oscar.sh backup-verify` to create and verify the coordinated PostGIS, state, and archive-generation snapshot.

## Track B — SensorHub Admin Configuration

<a id="04-admin-oscar-service-and-custom-codes"></a>
### 04. Configure OSCAR Service Retention & Custom Disposition Codes

Open Services -> OSCAR Service in SensorHub Admin to review 5-JPEG media retention settings, storage-pressure thresholds, and custom adjudication disposition codes.

- **Screen Recording:** [`04-admin-oscar-service-and-custom-codes.mp4` (12.3s, 693.4 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/04-admin-oscar-service-and-custom-codes.mp4) · [WebVTT Captions (`.vtt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/04-admin-oscar-service-and-custom-codes.vtt) · [SubRip Captions (`.srt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/04-admin-oscar-service-and-custom-codes.srt)

1. Open `https://oscar.local/sensorhub/admin`, expand **Services**, and select **OSCAR Service**.
2. Review **Video Retention Config** (`timeToRetention = 0`, `frameRetentionCount = 5`, `jpegQuality = 85`) and **Storage Pressure Retention Config**.
3. Expand **Custom Disposition Codes** to add or update site-specific adjudication code entries alongside built-in codes.
4. Click **Apply Changes** and **Save** in the top toolbar to persist the updated service configuration.

<a id="05-admin-lane-spreadsheet-sync"></a>
### 05. Sync Multi-Lane Spreadsheet Configuration (config.csv)

Import or download the multi-lane config.csv spreadsheet in OSCAR Service to provision RPM endpoints, RTSP cameras, and OperationalViews assignments in bulk.

- **Screen Recording:** [`05-admin-lane-spreadsheet-sync.mp4` (10.6s, 418.8 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/05-admin-lane-spreadsheet-sync.mp4) · [WebVTT Captions (`.vtt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/05-admin-lane-spreadsheet-sync.vtt) · [SubRip Captions (`.srt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/05-admin-lane-spreadsheet-sync.srt)

1. Navigate to **Services -> OSCAR Service** in SensorHub Admin (`https://oscar.local/sensorhub/admin`).
2. Locate **Config File Path** / **Upload** under **General** to upload or export the site's multi-lane `config.csv` spreadsheet (including `OperationalViews` semicolon-delimited keys such as `east-gate;entrance`).
3. Click **Apply Changes** and **Save** to synchronize all lane definitions.
4. Expand **Sensors** in the left accordion to confirm every imported `Lane System` module is registered and online.

<a id="06-admin-manual-lane-and-site-diagram"></a>
### 06. Configure a Lane System & Georeferenced Site Diagram

Inspect individual Lane System location, Extended Occupancy Threshold (min), and camera/RPM options under Sensors, then configure the georeferenced facility Site Diagram bounding coordinates in OSCAR Service.

- **Screen Recording:** [`06-admin-manual-lane-and-site-diagram.mp4` (14.9s, 785 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/06-admin-manual-lane-and-site-diagram.mp4) · [WebVTT Captions (`.vtt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/06-admin-manual-lane-and-site-diagram.vtt) · [SubRip Captions (`.srt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/06-admin-manual-lane-and-site-diagram.srt)

1. Open **Sensors** in SensorHub Admin and select a **Lane System** module.
2. Review **General** (including **Extended Occupancy Threshold (min)** and **Operational View Keys**), **Fixed Location** (latitude/longitude coordinates), and **Lane Options** (RPM driver address and RTSP camera stream parameters).
3. Switch to **Services -> OSCAR Service** and inspect **Site Diagram Config** to upload a site map image and set georeferenced lower-left and upper-right coordinates.
4. Click **Apply Changes** and **Save** to publish lane coordinates and site map bounds to the Viewer.

<a id="07-admin-eml-plugin-setup"></a>
### 07. Upload External EML VM-250 Plugin & Enable Per-Lane EML

Verify or upload a separately licensed EML VM-250 .jar plugin in OSCAR Service, inspect per-lane EML enablement under Lane Options, and review built-in operator documentation.

- **Screen Recording:** [`07-admin-eml-plugin-setup.mp4` (11.8s, 818.1 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/07-admin-eml-plugin-setup.mp4) · [WebVTT Captions (`.vtt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/07-admin-eml-plugin-setup.vtt) · [SubRip Captions (`.srt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/07-admin-eml-plugin-setup.srt)

1. Open **Services -> OSCAR Service** in SensorHub Admin (`https://oscar.local/sensorhub/admin`).
2. Locate **EML Plugin Path** and use **Upload** to install the external licensed EML VM-250 `.jar` runtime into private state storage.
3. Open **Sensors -> <Rapiscan Lane> -> Lane Options** to verify per-lane EML analysis settings (`Collimated` / `Enable EML`).
4. Open the **README** tab in OSCAR Service to reference localized administrator guidance on automated `Code 9999: EML Non-Threat` adjudications.

## Track C — OSCAR Viewer Console Operations

<a id="08-viewer-signin-language-and-nodes"></a>
### 08. Sign In to OSCAR Viewer, Switch Language & Manage Nodes

Authenticate at the OSCAR TLS gateway login page, switch console UI localization live between English and Spanish, open the in-app Operator Quick Guide & Glossary (?), and inspect connected server nodes.

- **Screen Recording:** [`08-viewer-signin-language-and-nodes.mp4` (16.9s, 3020.4 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/08-viewer-signin-language-and-nodes.mp4) · [WebVTT Captions (`.vtt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/08-viewer-signin-language-and-nodes.vtt) · [SubRip Captions (`.srt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/08-viewer-signin-language-and-nodes.srt)

1. Open `https://oscar.local`, enter the operator **Username** and **Password**, and click **Sign in**.
2. Click the top-bar language selector (**English**) to switch the console interface live between `English`, `Español`, `Français`, and `Ελληνικά`, and click the `?` help icon to open the **Operator Quick Guide & Glossary**.
3. Open **Servers** (`/servers`) from the navigation drawer to verify **Local Node** status or add federated OSCAR nodes.

<a id="09-dashboard-monitoring-and-quick-adjudication"></a>
### 09. Monitor Live 50-Lane Dashboard & Inspect Alarm Rows

Monitor real-time 50-lane status tiles and live alarm occupancy rows on the Dashboard, customize visible panels with Customize Dashboard, and launch rapid alarm review.

- **Screen Recording:** [`09-dashboard-monitoring-and-quick-adjudication.mp4` (12.9s, 939.5 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/09-dashboard-monitoring-and-quick-adjudication.mp4) · [WebVTT Captions (`.vtt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/09-dashboard-monitoring-and-quick-adjudication.vtt) · [SubRip Captions (`.srt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/09-dashboard-monitoring-and-quick-adjudication.srt)

1. Open the OSCAR **Dashboard** (`/`) to monitor real-time **Lane Status** tiles across all configured portal lanes and toggle **Customize Dashboard** to show or hide **Lane Status**, **Events**, or **Map**.
2. Review incoming occupancy and gamma/neutron alarm rows in the live Dashboard event table, sorting or customizing visible columns as needed.
3. Click a row's action menu (`⋮`) or double-click an alarm row to open immediate event inspection and adjudication controls.

<a id="10-operational-views-scoping"></a>
### 10. Scope Workstation Lanes with Fail-Closed Operational Views

Scope the Dashboard and Status of Health to an assigned workstation Operational View (?view=east-gate) and verify fail-closed protection on unassigned views.

- **Screen Recording:** [`10-operational-views-scoping.mp4` (11.4s, 662.3 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/10-operational-views-scoping.mp4) · [WebVTT Captions (`.vtt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/10-operational-views-scoping.vtt) · [SubRip Captions (`.srt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/10-operational-views-scoping.srt)

1. Open a workstation-scoped URL such as `https://oscar.local/?view=east-gate` and confirm the **`View: east-gate`** badge appears in the header.
2. Navigate to **Status of Health** (`/health?view=east-gate`) to verify that only lanes assigned to `east-gate` are loaded.
3. Verify that unassigned or malformed `?view=` keys fail closed with an explicit warning banner and zero loaded lane data.

<a id="11-live-lane-video-and-charts"></a>
### 11. Inspect Live Lane Camera Stream & Gamma/Neutron Waveforms

Open Lane Details from the Dashboard to watch live RTSP/HLS camera video alongside real-time Gamma and Neutron count-rate charts (including Show Individual Detectors and Separate Plots (Accessibility) toggles) and lane occupancy history.

- **Screen Recording:** [`11-live-lane-video-and-charts.mp4` (12s, 2359.3 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/11-live-lane-video-and-charts.mp4) · [WebVTT Captions (`.vtt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/11-live-lane-video-and-charts.vtt) · [SubRip Captions (`.srt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/11-live-lane-video-and-charts.srt)

1. Click a lane tile under **Lane Status** on the Dashboard (`/`) to open **Lane Details** (`/lane-view`).
2. Monitor the live camera video player alongside the real-time **Gamma** (red) and **Neutron** (blue) count-rate waveform charts, and toggle **Show Individual Detectors** or **Separate Plots (Accessibility)** (`G1`–`G4`, `N1`–`N4`).
3. Scroll to the lane event table below the charts to inspect historical occupancies recorded on that lane.

<a id="12-event-log-filtering-and-adjudication-codes"></a>
### 12. Filter Event Log by Lane, Adjudication Code & Event UUID

Search historical occupancies in Event Log using server-side Advanced Filters (including Code 9998: Extended Occupancy Gamma Alarm, Code 9999: EML Non-Threat, and custom codes) and direct Event UUID lookup.

- **Screen Recording:** [`12-event-log-filtering-and-adjudication-codes.mp4` (10.9s, 1145.7 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/12-event-log-filtering-and-adjudication-codes.mp4) · [WebVTT Captions (`.vtt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/12-event-log-filtering-and-adjudication-codes.vtt) · [SubRip Captions (`.srt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/12-event-log-filtering-and-adjudication-codes.srt)

1. Navigate to **Event Log** (`/event-log`) to browse paginated historical occupancies and alarms across the deployment.
2. Click **ADVANCED FILTERS** to filter server-side by date/time window, lane, alarm status, or **Adjudication Code** (including automated `Code 9998: Extended Occupancy Gamma Alarm`, `Code 9999: EML Non-Threat`, and custom codes).
3. Paste an occupancy observation identifier into **Event UUID** and click **FIND EVENT** to open that exact record.

<a id="13-event-details-adjudication-and-daily-file"></a>
### 13. Review Retained 5-Frame Media, Daily File Output & Adjudicate

Inspect five-frame retained JPEG camera evidence, toggle individual detector charts, examine exact RPM Daily File Output lines (hot journal or cold historical slice), and submit an append-only adjudication.

- **Screen Recording:** [`13-event-details-adjudication-and-daily-file.mp4` (19.4s, 1216.1 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/13-event-details-adjudication-and-daily-file.mp4) · [WebVTT Captions (`.vtt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/13-event-details-adjudication-and-daily-file.vtt) · [SubRip Captions (`.srt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/13-event-details-adjudication-and-daily-file.srt)

1. Open **Event Details** (`/event-details?eventId=<id>`), verify the **Event UUID** header bar, and step through the five retained camera JPEG thumbnails under **Retained camera evidence**.
2. Toggle **Show Individual Detectors** / **Separate Plots (Accessibility)** on the waveform charts and scroll to **Daily File Output** to inspect exact `GS`, `GA`, `NS`, and `GX` RPM daily-file records.
3. Complete **Vehicle ID**, **Adjudicate** disposition code, **Secondary Inspection**, and **Notes** under **Adjudication Form**.
4. Click **Submit** and confirm in **Confirm Adjudication Submission** (`Confirm & Submit`) to append the signed audit record while preserving prior adjudications.

<a id="14-airgapped-alarm-qr-transfer"></a>
### 14. Export Signed Alarm QR & Verify Offline on Air-Gapped Transfer

Export a SHA-256-authenticated Alarm QR image from Event Details, then import and verify its cryptographic integrity and waveforms offline on Alarm Transfer.

- **Screen Recording:** [`14-airgapped-alarm-qr-transfer.mp4` (25.2s, 1723.7 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/14-airgapped-alarm-qr-transfer.mp4) · [WebVTT Captions (`.vtt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/14-airgapped-alarm-qr-transfer.vtt) · [SubRip Captions (`.srt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/14-airgapped-alarm-qr-transfer.srt)

1. On **Event Details**, click **Export Alarm QR** to generate the `OSCAR-ALARM:1:` signed transfer payload.
2. Click **Download QR Image** (or **Download Alarm File**) to save the portable PNG QR symbol or JSON package.
3. Open **Alarm Transfer** (`/alarm-transfer`) on the receiving workstation and import the QR PNG image or scan via camera.
4. Confirm **`The alarm data passed its SHA-256 integrity check.`** and review the reconstructed occupancy UUID and Gamma/Neutron waveforms.

<a id="15-status-of-health-and-site-map"></a>
### 15. Monitor RPM/Camera Status of Health & Georeferenced Site Map

Track RPM connectivity, camera stream health, detector/tamper faults, and Fault - Extended Occupancy (Ext-Occ, with automated Code 9998 gamma-only alarm adjudication) on Status of Health, then inspect georeferenced lane markers on Site Map.

- **Screen Recording:** [`15-status-of-health-and-site-map.mp4` (10.2s, 1251.1 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/15-status-of-health-and-site-map.mp4) · [WebVTT Captions (`.vtt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/15-status-of-health-and-site-map.vtt) · [SubRip Captions (`.srt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/15-status-of-health-and-site-map.srt)

1. Open **Status of Health** (`/health`) from the navigation drawer to inspect real-time RPM connectivity, camera stream status, and detector or tamper fault badges across every lane.
2. Review lane-level health indicators and `Fault - Extended Occupancy` (`Ext-Occ`) status (which suppresses gamma-only extended occupancy alarms from the Dashboard and auto-adjudicates them as `Code 9998: Extended Occupancy Gamma Alarm`).
3. Open **Map** (`/map`) to view georeferenced lane markers and real-time alarm/health status overlaid on the facility map.

<a id="16-national-statistics-and-reports"></a>
### 16. Analyze National View Statistics & Generate Multi-Format Reports

Review aggregated occupancy and alarm trends on National View, then configure and generate RDS Site, Lane, Event, Adjudication (starting with summed All Selected Lanes totals), or Adjudication Details Extract reports in PDF, CSV, JSON, or Excel (.xlsx) format.

- **Screen Recording:** [`16-national-statistics-and-reports.mp4` (17.1s, 544.2 KiB)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/16-national-statistics-and-reports.mp4) · [WebVTT Captions (`.vtt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/16-national-statistics-and-reports.vtt) · [SubRip Captions (`.srt`)](https://github.com/ORNL/oscar-video-guides/blob/main/captions/16-national-statistics-and-reports.srt)

1. Open **National View** (`/national-view`) to inspect aggregated occupancy totals, gamma/neutron alarm counts, and multi-lane trends.
2. Navigate to **Report Generator** (`/report`) and choose **Node Selector**, **Report Scope** (`Entire Node`, `Operational View`, or `Specific Lanes`), **Report Type** (`RDS_SITE`, `LANE`, `EVENT`, `ADJUDICATION`, or `ADJUDICATION_DETAILS`), **Export Format** (`PDF`, `CSV`, `JSON`, or `Excel (.xlsx)`), and **Time Range**.
3. Click **Generate Report** and review the rendered PDF or inline tabular preview (`CSV`, `JSON`, `XLSX`) and download the generated report.
