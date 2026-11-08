# OSCAR 3.11.0 Release Overview, Architectural Rationale, and User Guide

OSCAR 3.11.0 is the official Oak Ridge National Laboratory (`ORNL/oscar`) release engineered for continuous 24/7 operation across multi-year retention windows at large radiation portal monitoring (RPM) sites (up to 50 concurrent RPM and RTSP camera lanes per server) on Ubuntu Server 24.04 x86-64 and Windows 11 x86-64.

This guide summarizes what changed, **why** each major architectural and operational change was implemented, which release artifact to download, and where **new users** and **existing users** should start.

---

## 1. Start Here: Choose Your Path

### Path A — New Users (Fresh Installation)

1. **Choose the right release package** from [GitHub Releases](https://github.com/ORNL/oscar/releases):
   - **Ubuntu Server 24.04 x86-64 (Connected):** Download `oscar-3.11.0.zip`.
   - **Windows 11 x86-64 (Connected):** Download `oscar-3.11.0.zip`.
   - **Windows 11 x86-64 (Air-Gapped / Offline, No Docker Installed Yet):** Download `oscar-3.11.0-windows-x86_64-offline-full.zip` (includes pinned Docker Desktop and WSL 2 installers plus pre-built container images).
   - **Windows 11 x86-64 (Air-Gapped / Offline, Docker Desktop & WSL 2 Already Running):** Download `oscar-3.11.0-windows-x86_64-offline-images.zip`.
2. **Prepare the host and initialize OSCAR:**
   - Follow the step-by-step [Quick Start](../dist/release/QUICKSTART.md) (`.\oscar.bat prepare-host` and `.\oscar.bat init` on Windows 11; `sudo bash oscar.sh init` on Ubuntu 24.04).
   - Review the [Administrator Guide](../dist/release/DEPLOYMENT.md) for static/reserved LAN IPv4 assignment, TLS certificate trust across operator workstations, Tailscale SANs, and optional `single`-snapshot backup configuration.
3. **Configure lanes, views, and operators:**
   - Open the [Operator and Administrator Manual (English)](../include/osh-oakridge-modules/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README.md) — or the [Español](../include/osh-oakridge-modules/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_es.md), [Français](../include/osh-oakridge-modules/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_fr.md), or [Ελληνικά](../include/osh-oakridge-modules/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_el.md) editions (also published as standalone PDFs on each GitHub Release) — to configure lanes, thresholds, users, adjudication workflows, and reports.
   - Follow the 16 single-task (< 2 min) captioned screen recordings and 3-to-4-step reference blocks in [How-To Video Guides](VIDEO_GUIDES.md) (`ORNL/oscar-video-guides`).

### Path B — Current Users Running `pre-3.11.0` (`3.10.0`, `3.9.x`, `3.8.x`, or Earlier)

OSCAR 3.11.0 introduces a data-checksummed PostgreSQL 16 cluster, the `PARQUET_PRIMARY` tiered observation store, deployment-bound storage-root identity markers, and the direct daily-file journal. **To protect existing deployments from unexpected data mutations, `upgrade` never silently converts a `pre-3.11.0` database or overwrites a saved `config.json`.**

Choose one of two explicit rollout options depending on site requirements:

1. **Recommended for Full 3.11.0 Multi-Year Storage & Performance (`PARQUET_PRIMARY`):**
   - Preserve the existing `pre-3.11.0` deployment read-only after taking its supported backup/export.
   - Deploy OSCAR 3.11.0 into a clean directory and fresh storage roots using `oscar init` ([Quick Start](../dist/release/QUICKSTART.md)) so PostgreSQL initializes with `--data-checksums`, `PARQUET_PRIMARY` 30-minute stage partitions, the direct daily-file journal, and five-frame JPEG media retention.
   - Re-import your site's lane CSV (updated with optional `Views` column assignments; see [Operational Views](OPERATIONAL_VIEWS.md)), click **Apply** and **Save Configuration** in SensorHub Admin, and run a supported `oscar restart`. Migrate historical records separately only if site policy requires it.
2. **Retaining an Existing Legacy Volume Set In-Place (Without `PARQUET_PRIMARY` Re-Initialization):**
   - Read the **3.11.0 storage migration boundary** section of the [Administrator Guide](../dist/release/DEPLOYMENT.md) and **Existing pre-3.11.0 deployments** in [Storage Operations](STORAGE_OPERATIONS.md) before running any command.
   - Only after verifying that the existing named Docker volumes and any nonempty archive/backup directories belong to that exact deployment, use the explicit one-time adoption flags (`--adopt-legacy-volumes` / `-AdoptLegacyVolumes` and, when applicable, `--adopt-legacy-storage-roots` / `-AdoptLegacyStorageRoots`). Retain the resulting `.oscar-volume-adoption` receipt alongside `.env`, `secrets/`, and `tls/`.

### Path C — Current Users Upgrading an Existing `3.11.0+` Same-Profile Deployment

1. If `OSCAR_BACKUP_MODE=single` is enabled, run and verify a fresh snapshot (`oscar backup` and `oscar backup-verify`; see [Backup and Restore](BACKUP_RESTORE.md)).
2. Extract the new release ZIP into a **clean sibling directory** (never extract over an existing release folder).
3. Copy **only** `.env`, `secrets/`, and `tls/` (plus `.oscar-volume-adoption` if previously created) from the prior release directory into the new directory.
4. Run `.\oscar.bat upgrade` (Windows) or `sudo bash oscar.sh upgrade` (Ubuntu). Setup validates volume/root ownership, runs the idempotent offline daily-file index check under the storage lock, and force-recreates all containers while preserving `oscar_oscar_state`, `oscar_postgres_data`, and external archive/backup roots. See **Upgrade** in [Administrator Guide](../dist/release/DEPLOYMENT.md).

---

## 2. Major New Features and Why They Were Implemented

### 2.1 `PARQUET_PRIMARY` Tiered Observation Storage & DuckDB Query Federation
- **What changed:** High-volume immutable detector streams (`gammaCounts`, `gammaThreshold`, `neutronCounts`, `setupGamma`, `setupNeutron`) now write into UTC-aligned 30-minute `LOGGED` PostgreSQL child partitions (`osg_*`). Once a 30-minute window closes (plus a 5-minute clock-skew/late-arrival safety delay), a background worker exports the window into Hive-partitioned (`year=YYYY/month=MM/day=DD`), Zstandard-compressed Apache Parquet files, verifies exact row count, UUID digest, and SHA-256 parity, and retires the entire staging table in `O(1)` metadata time (`NO INHERIT` + `DROP TABLE`). Mutable operational records (occupancies/alarms, adjudications, reports, commands, overlays, holds, and system metadata) remain in PostgreSQL. Embedded DuckDB transparently federates hot PostgreSQL stages and cold Parquet generations behind standard OpenSensorHub `IObsSystemDatabase` / OGC `ConSys` / CQL2 APIs.
- **Why it was implemented:** On a 50-lane site emitting continuous 1 Hz detector telemetry, a single-table PostgreSQL JSONB store accumulates millions of rows per day and billions over a 5-year (`1,825-day`) retention horizon. Continuous row-by-row `INSERT` and retention `DELETE` churn caused severe PostgreSQL MVCC dead-tuple bloat, autovacuum I/O contention, WAL amplification, and multi-gigabyte B-tree/GIN index growth — slowing live queries and consuming disk even after rows were logically deleted. Dropping whole 30-minute staging partitions eliminates row-level `DELETE` bloat completely, compresses cold detector history ~10–15x in self-describing Parquet, keeps `obs_datastreams` compact (~12–15 MiB with >93% PostgreSQL HOT updates), keeps live `ConSys` queries fast, and speeds up multi-day historical CQL/report scans by ~19x while preserving 100% OpenSensorHub API compatibility (and keeping `HOT_RETENTION` available for traditional non-OSCAR OpenSensorHub nodes).
- **Read more:** [Storage Architecture](STORAGE_ARCHITECTURE.md), [Data Lifecycle Policy](DATA_LIFECYCLE.md), [Cold Archive Format](ARCHIVE_FORMAT.md), and [Storage Operations](STORAGE_OPERATIONS.md).

### 2.2 Exact-Five JPEG Retained Alarm Media & Bounded MP4 Lifecycle
- **What changed:** Completed alarm camera recordings are asynchronously decoded into five deterministic baseline sRGB JPEG keyframes (`FIRST`, `QUARTER`, `MIDDLE`, `THREE_QUARTERS`, `LAST`) verified by a manifest commit marker, with bounded post-roll so even 1-second occupancies capture five frames. Source MP4 clips remain playable during a 24-hour post-publication rollback grace before automatic reclamation (failed or `<5`-frame clips preserve their MP4 indefinitely), and after 30 days secondary frames prune while `MIDDLE` (`frame-03.jpg`) stays online for multi-year event history. The Viewer renders an interactive 5-frame gallery with automatic legacy MP4 fallback.
- **Why it was implemented:** Retaining raw H.264 MP4 video for thousands of alarms across 50 cameras quickly exhausts terabytes of storage, while frame-dropping video re-transcoding was CPU-heavy and fragile on short clips. Extracting five verified JPEGs immediately preserves evidentiary visual context across the entire occupancy trajectory at a tiny fraction of MP4 disk cost, and pruning down to the middle frame after 30 days bounds multi-year media growth predictably.
- **Read more:** [Retained Media v1 Specification](../include/osh-oakridge-modules/docs/retained-media-v1.md), [Live Video & Recording Guide](LIVE_VIDEO.md), and [Data Lifecycle Policy](DATA_LIFECYCLE.md).

### 2.3 Crash-Recoverable Direct Daily-File Journal (`DailyFileJournalService`)
- **What changed:** Rapiscan, RS350, and Aspect drivers append raw detector records before parsing into a per-lane, length-prefixed, `CRC32C`-verified write-ahead journal on disk, decoupled from historical backlog rendering, with atomic daily CSV + SHA-256 manifest publication, 30-day replay-verified journal cleanup, and live Viewer display of the latest 15 daily-file messages.
- **Why it was implemented:** Legacy daily-file generation reconstructed CSVs from parsed database observations or in-memory buffers, meaning a restart, parser error, or database stall could drop raw vendor messages or cause multi-minute startup spikes across 50 lanes. Direct pre-parse journaling guarantees source-message durability and fast bounded restarts.
- **Read more:** [Daily-File Journal v1 Specification](../include/osh-oakridge-modules/docs/daily-file-journal-v1.md) and [Storage Architecture](STORAGE_ARCHITECTURE.md).

### 2.4 Opt-In Schema-v2 Single-Snapshot Backup, Self-Contained Restore & Legal Holds
- **What changed:** Fresh deployments default to `OSCAR_BACKUP_MODE=disabled` with `archive_mode=off` (no continuous external WAL archive mount). Administrators can opt into `single` mode on a non-overlapping backup path (`oscar upgrade --backup-mode single --backup-dir ...`), producing an HMAC-SHA-256-verified, `pg_verifybackup`-checked recovery point combining a streamed PostgreSQL base backup (`--wal-method=stream`), OSCAR state, Parquet cold-tier inventory, and AES-256-CBC encrypted credentials behind an atomic `CURRENT` pointer. Observation and generation legal holds (`GENERATION_EXACT`, `HOT_EXACT`, `COLD_RANGE_CONSERVATIVE`) and two-step tokenized cold-archive purges protect evidentiary records across API/UI and CLI operations.
- **Why it was implemented:** Continuous external PostgreSQL WAL archiving on unattended edge servers created silent disk-exhaustion hazards whenever backup media disconnected or filled up, and multi-snapshot local retention multiplied multi-gigabyte cold-archive footprints. Self-contained streamed base backups with `archive_mode=off` eliminate unbounded WAL accumulation while providing cryptographically verified, cross-host-portable disaster recovery (including over NTFS USB SSD or Gigabit LAN; PITR is intentionally out of scope).
- **Read more:** [Backup, Restore, and Recovery Runbook](BACKUP_RESTORE.md) and [Storage Operations](STORAGE_OPERATIONS.md).

### 2.5 URL-Scoped Operational Views, Lane/Camera Status of Health & Built-In Loopback RTSP/HLS Video Resilience
- **What changed:** Administrators can assign lanes to named workstation views (via Admin UI or CSV `Views` column) accessed at `/view/<slug>`, scoping live subscriptions, maps, event tables, statistics, health indicators, and reports. A dedicated Status of Health page and compact Dashboard lane pills report independent RPM and camera connectivity, gamma/neutron faults, tamper state, and extended occupancy in bounded 30-second batches. For `rtsp://` and `rtsps://` cameras, OSCAR now embeds and supervises a transparent loopback `mediamtx` RTSP proxy inside the `oscar` container (`127.0.0.1`, keeping real camera URLs unchanged across `config.json`, Admin UI, and CSV imports/exports), deduplicating identical streams to a single upstream TCP camera socket per server, normalizing leading `//` stream paths, verifying upstream readiness before reporting `Online`, reconnecting dropped streams in-place without restarting the SensorHub module, normalizing packet DTS/PTS discontinuities, and coordinating multi-operator shared live HLS leases with keyframe-gated startup.
- **Why it was implemented:** Large ports and facilities divide 50+ lanes across gate-specific operator consoles (`east-gate`, `west-gate`, `pedestrian`, etc.); opening unfiltered real-time MQTT/video feeds for every lane on every workstation wasted browser memory and distracted operators. Physical edge IP cameras also tightly cap concurrent TCP `:554` sessions and emit packet timestamp discontinuities or reject duplicate/malformed RTSP paths, while multiple operators viewing the same lane previously risked stopping each other's shared HLS stream on navigation.
- **Read more:** [Operational Views Guide](OPERATIONAL_VIEWS.md), [Status of Health Guide](STATUS_OF_HEALTH.md), and [Live Video Guide](LIVE_VIDEO.md).

### 2.6 Event UUID Direct Links, Full-Database Adjudication Code Filtering, QR Alarm Transfer & Serialized National Statistics
- **What changed:** Every occupancy carries a canonical Event UUID searchable on the Events page, linkable across workstations (honoring view access controls), printed in PDFs, and exportable/importable offline via single-code adaptive QR codes (camera scan or PNG/file import). Full-database event filters push CQL predicates — including **Adjudication Code** (`equals`, `does not equal`, `is any of`, `is empty`, `is not empty` across built-in Codes `1–11`, automated `Code 9999: EML Non-Threat`, and site-configured custom disposition codes, backed by an asynchronous, idempotent startup backfill for historical adjudications) — directly to indexed PostgreSQL GIN and DuckDB Parquet queries, alarm priority sorts `Gamma-Neutron > Neutron > Gamma`, and National Statistics commands run sequentially with terminal observation binding.
- **Why it was implemented:** Operators in air-gapped or segmented secondary-inspection booths needed a zero-network way to hand off alarm traces and metadata to handheld devices or secondary workstations, while concurrent full-history statistics refreshes previously competed for CPU and memory on multi-month archives.
- **Read more:** [Operator Manual (English)](../include/osh-oakridge-modules/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README.md).

### 2.7 Windows 11 Unattended Server Readiness, Modern Standby Fix, Pre-Login Docker & LAN/Tailscale TLS
- **What changed:** `configure-windows-host.ps1` (`.\oscar.bat prepare-host` / `.\oscar.bat host-check`) enforces 20 host-readiness checks on Windows 11: detects `S0 Low Power Idle` (Modern Standby) hardware via `powrprof.dll` and sets AC display timeout (`VIDEOIDLE`) to `0` (`Never`), registers `OSCAR-DockerDesktop-BootStart` (`AtStartup` `+10s`, `LogonType=S4U`) with an ACL-locked `%ProgramData%\OSCAR\start-docker-prelogin.ps1` helper so Docker Desktop and OSCAR start automatically after a power outage **before any user logs in**, caps WSL 2 memory/swap via `.wslconfig`, disables USB/NIC power saving, checks static vs. DHCP IPv4 stability, enables bugcheck auto-reboot, and auto-populates LAN IPv4 and Tailscale IPv4/IPv6/MagicDNS SANs into 10-year self-signed TLS certificates. Supported `stop`/`restart`/`upgrade` commands shut down `gateway -> oscar -> postgres` in strict dependency order.
- **Why it was implemented:** Live endurance testing on Windows 11 Modern Standby hardware revealed that Windows enters `S0 Low Power Idle` (`Kernel-Power 506`, dropping network and WSL 2 responsiveness) the moment the monitor blanks (`VIDEOIDLE > 0`), even when sleep timeout (`STANDBYIDLE`) is `0`, and that standard Windows startup tasks do not launch Docker Desktop after an unattended power-loss reboot until an interactive desktop login occurs. Unbounded WSL 2 page cache (`vmmemWSL`) could also starve the Windows host over multi-day runs.
- **Read more:** [Quick Start](../dist/release/QUICKSTART.md) and [Administrator Guide](../dist/release/DEPLOYMENT.md).

### 2.8 Admin-Uploaded External EML Runtime Plugin & Automatic `EML Non-Threat` Adjudication
- **What changed:** All non-redistributable EML JARs, models, and XML files have been removed from OSCAR repositories and release packages, replaced by a hot-loadable runtime plugin architecture (`EmlRuntimeRegistry`). Administrators upload their separately licensed EML `.jar` (or `.tar.gz`/`.zip` archive) in **Services -> OSCAR Service -> EML Plugin Path** (`emlPluginPath`) — stored privately in `/var/lib/oscar/eml-plugin/` (`oscar_state`, included in backups and never exposed via HTTP buckets) and extracted to `/tmp/oscar-eml-runtime` — and enable `emlEnabled`, `isCollimated`, and `laneWidth` per Rapiscan lane. When EML evaluates an occupancy on `GX` as a verified `RELEASE` non-threat (without fallback or evaluation error), OSCAR suppresses the alarm from the Dashboard queue and browser notifications from initial publication and automatically records an `Adjudication` (`sender="EML"`, code `9999` **EML Non-Threat**, `secondaryInspectionStatus="NONE"`) with structured `EML_METADATA` JSON queryable in **Events** (`Adjudicated = EML Non-Threat` or `Adjudication Code = 9999: EML Non-Threat`) and rendered in **Event Details** (`EmlAnalysisCard` + `AdjudicationLog`) across `en`, `es`, `fr`, and `el`.
- **Why it was implemented:** EML source and model artifacts are owned and distributed separately outside ORNL's open-source repositories, while high-throughput VM-250 portals experience frequent benign NORM alarms that otherwise flood the central Dashboard queue if operators must manually clear every EML-released occupancy. Admin plugin upload cleanly separates third-party licensing from OSCAR releases while preserving 100% auditability and searchability for every auto-adjudicated non-threat event.
- **Read more:** [EML Integration Guide](EML_INTEGRATION.md) and [Administrator Guide](../dist/release/DEPLOYMENT.md).

### 2.9 Multi-Format Reports (`PDF`, `CSV`, `JSON`, `Excel`), Summed `All Selected Lanes` Adjudication Summary & In-UI Operator Help
- **What changed:** The Report Generator (`/report`) now supports five report types (`RDS Site Report`, `Lane Report`, `Event Report`, `Adjudication Report`, and `Adjudication Details`) across three scopes (`Entire Node`, `Operational View`, and `Specific Lanes`) and four export formats (`PDF`, `CSV`, `JSON`, and `Excel (.xlsx)`), always generating a fresh report and rendering an inline PDF or interactive tabular preview before download. The **Adjudication Report** (`ADJUDICATION`) starts with summed **All Selected Lanes** (`ALL_LANES`) `Disposition` and `Isotope Results` tables across all selected lanes before breaking down each individual lane. In addition, the OSCAR Viewer navigation bar now includes an in-UI **Operator Help & Glossary** (`?` icon) localized in English, Spanish, French, and Greek (`en`, `es`, `fr`, `el`), and all 24 SensorHub Admin configuration modules provide localized in-UI `README` tabs with plain-language term definitions.
- **Why it was implemented:** Site supervisors and auditors needed structured spreadsheet (`CSV`, `.xlsx`) and machine-readable (`JSON`) exports alongside concise, non-repetitive `PDF` summaries, with an immediate site/scope-wide adjudication roll-up at the top of the Adjudication Report before per-lane tables, plus self-contained plain-language help directly inside both web consoles for air-gapped operator workstations.
- **Read more:** [Operator Manual (English)](../include/osh-oakridge-modules/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README.md) and [How-To Video Guides](VIDEO_GUIDES.md).

---

## 3. Complete Documentation Map by Audience

| Audience / Task | Primary Guide | Companion References |
| :--- | :--- | :--- |
| **New installation (Ubuntu 24.04 or Windows 11, connected or offline)** | [Quick Start](../dist/release/QUICKSTART.md) | [Administrator Guide](../dist/release/DEPLOYMENT.md) |
| **Upgrading from `pre-3.11.0` or `3.11.0+`** | [Administrator Guide — Upgrade](../dist/release/DEPLOYMENT.md) | [Storage Operations — Existing Deployments](STORAGE_OPERATIONS.md) |
| **Console operators & site supervisors (`en`, `es`, `fr`, `el`)** | [Operator Manual (EN)](../include/osh-oakridge-modules/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README.md) | [Español](../include/osh-oakridge-modules/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_es.md), [Français](../include/osh-oakridge-modules/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_fr.md), [Ελληνικά](../include/osh-oakridge-modules/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_el.md) (and release PDFs) |
| **Workstation views, health monitoring & live cameras** | [Operational Views](OPERATIONAL_VIEWS.md), [Status of Health](STATUS_OF_HEALTH.md) | [Live Video](LIVE_VIDEO.md) |
| **External EML plugin upload & automated `EML Non-Threat` review** | [EML Integration Guide](EML_INTEGRATION.md) | [Administrator Guide](../dist/release/DEPLOYMENT.md) |
| **Storage architecture, Parquet lifecycle, media & daily files** | [Storage Architecture](STORAGE_ARCHITECTURE.md), [Data Lifecycle](DATA_LIFECYCLE.md) | [Archive Format](ARCHIVE_FORMAT.md), [Daily-File Journal](../include/osh-oakridge-modules/docs/daily-file-journal-v1.md), [Retained Media](../include/osh-oakridge-modules/docs/retained-media-v1.md) |
| **Backups, disaster recovery, legal holds & cold-archive purge** | [Backup, Restore, and Recovery](BACKUP_RESTORE.md) | [Storage Operations](STORAGE_OPERATIONS.md) |
| **Developers, contributors & localization (`i18n`)** | [Translation System Guide](TRANSLATION_SYSTEM.md) | [`ORNL/oscar` Repository & `CONTRIBUTING.md`](https://github.com/ORNL/oscar/blob/main/CONTRIBUTING.md), [`ORNL/oscar-regression`](https://github.com/ORNL/oscar-regression) |

---

## 4. Contributors Across Repository and Submodules (Since `v3.10.0`)

- **Alex Almanza** ([`@earocorn`](https://github.com/earocorn)) — `ORNL/oscar`, `ORNL/osh-oakridge-modules`
- **Kalyn Stallings** ([`@kalynstricklin`](https://github.com/kalynstricklin)) — `ORNL/oscar-viewer`
- **Kyle Fitzpatrick** ([`@kyle-fitzp`](https://github.com/kyle-fitzp)) — `ORNL/osh-oakridge-modules`
- **Tyrone Harris** ([`@tyronechrisharris`](https://github.com/tyronechrisharris)) — `ORNL/oscar`, `ORNL/oscar-viewer`, `ORNL/osh-addons`, `ORNL/osh-core`, `ORNL/osh-js`, `ORNL/osh-oakridge-modules`

