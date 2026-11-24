# OSCAR

OSCAR (Open Source Central Alarm Monitoring) is a radiation portal monitoring and central alarm station platform ([`ORNL/oscar`](https://github.com/ORNL/oscar)), developed on OpenSensorHub. It combines OpenSensorHub modules, the OSCAR viewer, PostgreSQL/PostGIS, and a TLS gateway into a hardened Docker Compose deployment.

The configured HTTPS port and a port 80 HTTPS redirect are published. PostgreSQL and the OSCAR application port remain on private Compose networks. Java 21.0.10 is included in the OSCAR container image and is not required on deployment hosts.

## Official repositories

| Repository | Role |
| --- | --- |
| [`ORNL/oscar`](https://github.com/ORNL/oscar) | Top-level release packaging, Docker Compose runtime, storage/backup tooling, documentation, and CI/release pipelines |
| [`ORNL/osh-oakridge-modules`](https://github.com/ORNL/osh-oakridge-modules) | OSCAR OpenSensorHub drivers, services, storage/media lifecycle modules, and localized operator manuals |
| [`ORNL/oscar-viewer`](https://github.com/ORNL/oscar-viewer) | Next.js / React OSCAR web client (`en`, `es`, `fr`, `el`) |
| [`ORNL/osh-core`](https://github.com/ORNL/osh-core) | OpenSensorHub core fork (`OSCAR` branch) |
| [`ORNL/osh-addons`](https://github.com/ORNL/osh-addons) | OpenSensorHub addons & tiered PostGIS/Parquet storage (`OSCAR` branch) |
| [`ORNL/osh-js`](https://github.com/ORNL/osh-js) | OpenSensorHub JavaScript ConSys/MQTT client (`add-consys` branch) |
| [`ORNL/oscar-regression`](https://github.com/ORNL/oscar-regression) | End-to-end Playwright, ConSys API, emulator fault-injection, and 50-lane regression suite |
| [`ORNL/oscar-video-guides`](https://github.com/ORNL/oscar-video-guides) | Concise 1080p NVENC H.264 how-to workflow screen recordings, WebVTT/SRT captions, and sequential step guides (mounted at `docs/video-guides`) |
| [`ORNL/oscar-federation-hub`](https://github.com/ORNL/oscar-federation-hub) | Optional turnkey self-hosted Zero-Trust remote-access tunnel (Octelium) and centralized browser SSO user console (Authentik) for federated multi-site deployments |

## Installation and user guides

- **What's New, Architectural Rationale & Upgrade Guide:** Start with the [OSCAR 3.11.13 (Amber) Release Overview and User Guide](docs/RELEASE_NOTES_AND_UPGRADE_GUIDE.md) for a complete walkthrough of all new capabilities, why each architectural change was made, and step-by-step instructions for **new installations**, **`pre-3.11.0` upgrades/migrations**, and **`3.11.13+` zero-login GUI (`Users & Access -> System Update`) or CLI (`oscar update`) clean-directory upgrades**.
- **Side-by-Side Central Alarm Station (CAS) Rapiscan RPM Real-Time Edge Proxy (`oscar-rpm-proxy`):** At sites installing OSCAR alongside an existing Central Alarm Station across `1–50+` Rapiscan RPMs, enable the optional isolated `oscar-rpm-proxy` service (`sudo ./oscar.sh rpm-proxy configure --from-csv <lanes.csv> --start`) to fan out `\n`-framed `1 Hz` radiation telemetry in real time to both systems simultaneously with cached `SG1..SG3` / `SN1..SN2` setup replay, **`<= 4.0 s` upstream-gated disconnect & cable-pull propagation** (`zero` `SYN-ACK` flapping while an RPM is offline), Port-Mapped (`11601..11650`) or Ubuntu 24.04 Transparent Virtual-IP (`:1600` per lane) addressing, and zero CAS interruption during `oscar restart` / `upgrade`; see [Side-by-Side CAS Rapiscan RPM Edge Proxy Guide](docs/RPM_EDGE_PROXY_GUIDE.md).
- **Per-Lane Physical RPM Lights & Sound (`WebRelay-Quad`):** Optionally connect **ControlByWeb WebRelay-Quad** Ethernet relay modules per lane (`enabled = false` by default) to suppress physical red beacons and audible sirens on benign `Code 9999: EML Non-Threat` and `Code 9998: Extended Occupancy Gamma Alarm` events while pulsing `R3` (Gamma Red + Siren) and/or `R4` (Neutron Blue) on actionable threats with `0,0,0,0` fail-safe pass-through and live Administrator control on `/health`, `/lane-view`, and `/sensorhub/admin`; see [Per-Lane Physical RPM Lights & Sound Guide](docs/LANE_WEBRELAY_GUIDE.md).
- **Anytime Guided Walkthrough Refresher (`:443`) & Ephemeral Hands-On Training Sandbox (`oscar-sandbox` `:8444`):** Open **Guided Walkthrough** (*graduation-cap icon* in the top bar) anytime on the live console (`:443`) in safe **Read-Only Refresher Mode** across 13 role-based labs (complete with interactive **`Highlight [Page / Tool] Icon`** spotlights and inline visual symbol introductions), or launch the isolated `:8444` Practice Sandbox in **1 click directly from the GUI** (automatically enabled during `oscar init` / `upgrade` on both Ubuntu 24.04 and Windows 11, or via `sudo bash oscar.sh sandbox start` / `.\oscar.bat sandbox start`) with built-in loopback Rapiscan RPM & RTSP container camera micro-emulators, Split-Pane SensorHub Admin, a live `120-minute` auto-shutdown countdown, and complete `< 2 s` volume disposal on expiry or `sandbox stop`; see [Guided Walkthrough & Hands-On Training Sandbox Guide](docs/TRAINING_SANDBOX_GUIDE.md).
- **How-To Video Guides & 4-Language In-App Captioned Walkthroughs:** Watch the 29 single-task (< 2 min) 1080p workflow screen recordings with synchronized 4-language (`en`, `es`, `fr`, `el`) WebVTT/SRT captions and 3-to-4-step reference blocks in the [How-To Video Guides Catalog](docs/VIDEO_GUIDES.md), in [`ORNL/oscar-video-guides`](https://github.com/ORNL/oscar-video-guides), or offline/air-gapped directly inside OSCAR (`/video-guides/`) via contextual click-to-play controls in **Guided Walkthrough** (*graduation-cap icon*), Viewer **Help (`?`)** (*circled question-mark icon*), and SensorHub Admin module `README` tabs.
- **Commercial Cargo X-Ray / NII Integration (`WCO UFF 2.0` & `3.0.0`):** Sites operating alongside cargo X-ray scanners can optionally enable read-only SMBv2/SMBv3 share correlation, scanner/time-window browsing, Tier-1 UUID lookup, and 16-bit `uint16` TIFF + HEMD material inspection in [Cargo Non-Intrusive Inspection (`WCO UFF`) Guide](docs/CARGO_UFF_INTEGRATION.md) (disabled by default for zero screen clutter on standalone RPM portals).
- **New Installations:** Download the latest release from [GitHub Releases](https://github.com/ORNL/oscar/releases) and follow the [Quick Start](dist/release/QUICKSTART.md) for the shortest supported installation path on Ubuntu Server 24.04 or Windows 11 (connected or offline).
- **Simple Self-Hosted Multi-Site Federation & Remote Access:** For organizations connecting multiple NATed/firewalled OSCAR portals without inbound firewall port-forwards or enterprise IdP complexity, [`ORNL/oscar-federation-hub`](https://github.com/ORNL/oscar-federation-hub) provides a 3-step self-hosted Octelium Zero-Trust tunnel + optional Authentik OIDC browser user console (`oscar-admins`, `oscar-operators`, `oscar-viewers`) that works directly with OSCAR's built-in `oscar-remote-access.sh` / `oscar-remote-access.ps1` helpers while preserving local offline Passkeys and passwords on each site; see the [Administrator Guide](dist/release/DEPLOYMENT.md) (*Turnkey self-hosted federated remote access & SSO*).
- **Site, Hardware Sizing & Storage Administration:** The [Administrator Guide](dist/release/DEPLOYMENT.md) covers baseline server specifications, recommended OCR camera stream profiles (`1080p @ 15 fps`, `1 s` closed GOP + `720p @ 15 fps` overview), and `5`-lane vs. `50`-lane multi-year resource and query-latency projections across Ubuntu 24.04 and Windows 11 WSL 2, plus unattended host readiness (`prepare-host` / `host-check`), hotel-to-site static-IP staging, LAN/Tailscale TLS certificates, offline installation, lifecycle commands, storage administration, security verification, and upgrades.
- **Localized Operator Manuals (`en`, `es`, `fr`, `el`):** Complete administrator and console-operator manuals are included in [English](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README.md), [Español](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_es.md), [Français](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_fr.md), and [Ελληνικά](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_el.md), and published as standalone PDFs on each GitHub Release.

Supported deployment and operation hosts:

- Windows 11 x86-64 with Docker Desktop and WSL 2
- Ubuntu Server 24.04 x86-64 with Docker Engine and the Compose plugin

OSCAR 3.11.13 storage-profile deployment is intentionally blocked on macOS. Docker Desktop for Mac
cannot satisfy the tested bind-root ownership and recovery-media isolation contract used by this
release. Build/source inspection remains possible there, but initialize and operate 3.11.13 on a
supported Ubuntu or Windows host.

There is no default administrator password. The administrator supplies it during `oscar init`, and deployment-specific database credentials are generated automatically.

## Build from source

Clone all submodules:

```sh
git clone --recursive https://github.com/ORNL/oscar.git
cd oscar
```

The canonical connected-release builds are:

```bat
build-all.bat
```

```sh
./build-all.sh
```

Both scripts use the locked Node.js dependency set, reject any npm advisory, test release-version updates, run the Viewer component suite and the Java software-only storage/media suites, compile the Java modules, and create:

```text
build/distributions/oscar-<version>.zip
```

Hardware-dependent tests remain outside these packaging scripts and must be run in an appropriately equipped test environment.
The Unix build also runs `tools/test-storage-scripts.sh`, which exercises the portable Bash and
PowerShell storage-administration safety guards. Continuous integration and tagged release builds additionally run `tools/test-live-deployment-regression.sh`, which validates [`ORNL/oscar-regression`](https://github.com/ORNL/oscar-regression) (including its canonical 50-lane fixture `fixtures/oscar-50-lane-config.csv`), initializes the packaged Docker Compose deployment, exercises TLS gateway routing, ConSys API authentication, headless Chromium Viewer/Admin navigation, and verifies live archive and single-snapshot backup integrity. That harness does not replace the native Windows
PowerShell 5.1 gate: the release workflow runs `tools/test-storage-powershell.ps1` with
`powershell.exe` on Windows.

### Test a source-built release

The Viewer bundle and Java modules are copied into the versioned `oscar` container image. Building the ZIP does not update a running deployment, and `oscar restart` deliberately reuses the existing image.

For a full-system test, extract the newly built release into a clean directory and use `oscar init` for a disposable new deployment. OSCAR 3.11.13 therefore runs the new tiered database, direct daily-file journal, data-checksummed PostgreSQL cluster, primary Parquet cold tier, and optional external single-snapshot storage. Fresh deployments use `OSCAR_BACKUP_MODE=disabled`; `single` is a manual opt-in that requires an operator-selected safe absolute backup path that does not overlap the release or archive roots. A separate physical drive is recommended for failure isolation but is not required. PostgreSQL does not continuously archive WAL: it runs with `archive_mode=off` and no external WAL bind, and OSCAR does not provide PITR. Use a fresh 3.11.13 database and standard configuration when validating this storage profile; `upgrade` deliberately preserves an existing `config.json`, database volume, and legacy roots/data and does not silently migrate a pre-3.11.0 deployment.

For a 3.11.13-or-newer same-storage-profile upgrade, first create and verify a coordinated snapshot when the deployment has explicitly selected `single` mode, then copy only `.env`, `secrets/`, and `tls/` into a clean extracted release before running `oscar upgrade`; do not overlay the ZIP on old release-managed files. If the deployment previously adopted unlabelled legacy Docker volumes, also copy its `.oscar-volume-adoption` receipt. Initialization persists the archive path, and in `single` mode the backup path, as absolute paths outside the versioned release; the legacy-WAL binding is retained only to preserve any existing compatibility tree. Copying `.env` preserves those paths and the backup-mode policy. Confirm the archive bind and absence of a PostgreSQL WAL bind with `docker compose config`; the backup root is not mounted into a long-running service. Compose uses the fixed `oscar` project and exact external volumes `oscar_oscar_state` and `oscar_postgres_data`. During upgrade, the storage administrator lock covers the ordered application stop, configuration-aware offline daily-file lifecycle-index migration, and force-recreated service restart. The migration reads the persisted `/var/lib/oscar/config.json`, safely skips when no Daily File Journal module is configured, and creates no new work markers when the journal is already indexed. A failed or interrupted scan can leave idempotent work markers and an explicit restart marker, but it does not publish completion metadata; OSCAR remains stopped and the same upgrade is safe to retry. All named volumes and external roots remain attached. Retire the prior release directory only after health and mount/provenance verification. Never remove a parent or sibling path containing a preserved external archive, legacy-WAL, or backup root.

A pre-3.11.0 system does not have the coordinated-snapshot/root-identity contract and is not an ordinary in-place upgrade. Preserve it read-only after its supported backup/export, then use the separately qualified migration/bootstrap procedure. Only after confirming that both legacy named volumes and all nonempty active archive/backup roots belong to that deployment may an administrator use the explicit one-time adoption switches. Any legacy-WAL tree remains untouched compatibility data. The adoption switches create deployment-bound audit receipts/markers for active roots; they must never combine unrelated storage or bypass a foreign/swapped identity.

Do not reuse a published version number for different production images. During connected pre-release iteration, `init` and `upgrade` rebuild both local release contexts (`oscar:<version>` and `oscar-postgis:<version>`) even when matching tags are cached, then recreate the services without deleting named volumes. The bounded explicit Windows builds avoid Docker Compose 5.6's in-tree Dockerfile entitlement regression without granting wildcard filesystem access. The regression platform gate compares packaged and deployed helper hashes so a stale same-tag restore image cannot be certified. Never replace a published version tag with different image contents.

Viewer builds require Node.js 22.12 or newer on a supported even-numbered release line (22, 24, or 26). For isolated Viewer development, `cd web/oscar-viewer`, run `npm ci`, `npm run audit:dependencies`, and then `npm run dev`. This is useful for UI iteration against reachable OSCAR nodes, but it does not validate the packaged Viewer, FFmpeg camera telemetry, PostgreSQL filtering, container configuration, or the upgrade path. Use the release ZIP for final system testing.

## Developer documentation

The [translation system guide](docs/TRANSLATION_SYSTEM.md) documents language selection and persistence, admin and viewer resource lookup, sensor and Lane System form metadata, localized README help, and the complete procedure and validation checklist for adding or restoring a supported language.

The [operational views guide](docs/OPERATIONAL_VIEWS.md) explains how to assign lanes to workstation views, use view-specific URLs, and import or export assignments in lane spreadsheets.

The [Status of Health guide](docs/STATUS_OF_HEALTH.md) documents lane-level RPM and camera connectivity, detector and tamper faults, extended occupancy (`Fault - Extended Occupancy` and automated `Code 9998: Extended Occupancy Gamma Alarm` adjudication for gamma-only extended occupancy alarms), operational-view scoping, and the acceptance checklist.

The [live-video guide](docs/LIVE_VIDEO.md) documents keyframe requirements, the Viewer's preparing and recovery states, emulator expectations, troubleshooting, and end-to-end playback acceptance tests.

The [EML integration guide](docs/EML_INTEGRATION.md) documents how administrators package and upload a separately licensed EML VM-250 `.jar` plugin in **Services -> OSCAR Service** (or **OSCAR Viewer -> Extensions**), enable EML per Rapiscan lane, and query or review automated **EML Non-Threat** (`Code 9999`) and **Extended Occupancy Gamma Alarm** (`Code 9998`) adjudications and `EML_METADATA` in the Viewer and ConSys API.

The [pluggable runtime extensions & regional packs guide](docs/PLUGGABLE_EXTENSIONS_GUIDE.md) documents how administrators and developers extend or hot-swap **Vehicle OCR** (`plate-rules.json`, custom `.onnx` model packs, or `OcrEngine` `.jar` SPI plugins), **Offline Regional Basemaps** (`.pmtiles` vector and raster archives), **Secondary-Inspection Spectroscopy** (`isotope-library.json` or `SpectroscopyIdentificationAlgorithm` `.jar` plugins), **Trusted Enterprise CA Certificates** (`.pem`/`.crt`), **Agency Adjudication Policy Packs** (`policy-pack.json`), **EML Alarm Assessment**, and optional **Commercial Cargo NII (`WCO UFF 2.0` & `UFF 3.0.0`)** read-only SMBv2/SMBv3 shares ([Cargo UFF Integration Guide](docs/CARGO_UFF_INTEGRATION.md)) from **OSCAR Viewer -> Extensions (`/extensions`)** while preserving shipped built-in defaults on fresh installs and never overwriting custom overrides during `oscar upgrade`.

The [radiation portal monitor & detector driver integration guide](docs/RADIATION_DETECTOR_DRIVER_GUIDE.md) walks developers and hardware vendors step-by-step through adding support for a new standalone radiation detector, gross-counting RPM, or spectroscopic portal—covering `RADHelper` SWE Common semantic URIs, `PARQUET_PRIMARY` stream routing, `DailyFileJournalConnection` pre-parse crash-safe journaling, `LaneSystem` & `StateManager` camera/alarm synchronization, bulk CSV lane import, 4-language (`en`, `es`, `fr`, `el`) Admin UI/`README` parity, and emulator-backed regression certification.

The [storage architecture](docs/STORAGE_ARCHITECTURE.md) explains the 3.11.13 PostgreSQL hot store, Parquet cold tier, durable daily journal, and exact-five JPEG retained-media design for each successfully converted camera clip. The companion [data-lifecycle policy](docs/DATA_LIFECYCLE.md), [archive-format contract](docs/ARCHIVE_FORMAT.md), [backup/restore runbook](docs/BACKUP_RESTORE.md), [continual & occasional USB NVMe incremental backup guide](docs/CONTINUAL_AND_USB_BACKUP_GUIDE.md), and [storage-operations runbook](docs/STORAGE_OPERATIONS.md) cover retention, portability, zero-downtime USB NVMe continual sync and field laptop offload, deletion, recovery, monitoring, and rollout.

The [diagnostic flight recorder & support bundle guide](docs/DIAGNOSTICS_AND_FLIGHT_RECORDER.md) documents the built-in 400-event browser flight recorder, rolling server diagnostics, 1-click **Help (`?`) -> Export Support Bundle** action, offline client fallback, host CLI `oscar.sh` / `oscar.bat support-bundle` crash-loop collector, and automatic edge secret redaction.

The [end-to-end regression & release certification guide](docs/REGRESSION_AND_RELEASE_CERTIFICATION.md) documents installing, configuring, safety-locking, and running all 5 profiles (`smoke`, `full`, `3.11.0-release`, `restore-drill`, `ui-endurance`) and all 27 functional scenarios in [`ORNL/oscar-regression`](https://github.com/ORNL/oscar-regression).

The [Ubuntu 24.04 field setup, hotel-room staging & air-gapped bare-metal guide](docs/UBUNTU_FIELD_SETUP_GUIDE.md) walks step-by-step through bootable USB creation, bare-metal Ubuntu 24.04 installation (interactive or declarative `autoinstall`), hotel-room DHCP/Wi-Fi staging (`stage-site-network`) with 1-command static-IP on-site cutover (`apply-site-network`), completely offline `ubuntu-x86_64-offline-full` installation (`tools/offline/build-ubuntu-offline-bundle.sh`), and discovering unknown RPM/camera IP addresses (`discover-devices`).

## Build Windows offline media

On a connected Windows x86-64 build workstation with Docker available, run the builder with Windows
PowerShell 5.1 (`powershell.exe`):

```powershell
powershell -File tools/offline/build-offline-bundle.ps1 -CreateArchive
```

The default `Both` profile invokes `build-all.bat`, downloads checksum-pinned official Windows prerequisites, exports the required images, creates `SHA256SUMS`, and produces two artifacts:

```text
build/offline/oscar-<version>-windows-x86_64-offline-full.zip
build/offline/oscar-<version>-windows-x86_64-offline-images.zip
```

The `full` artifact includes the pinned Docker Desktop and WSL prerequisites. The smaller `images` artifact requires Docker Desktop and WSL 2 to be installed and running already. Neither offline deployment path performs downloads.
Every offline `init` or `upgrade` re-verifies that the exact payload set and bytes match the
co-packaged `SHA256SUMS`, then reloads the checksum-verified image archive even when matching tags
already exist. This detects corruption and changes relative to that manifest, but the manifest is
bundled and unsigned: it does not authenticate the publisher or release origin. If origin
authentication is required, verify the outer ZIP against an independently trusted detached
signature or provenance attestation before transferring it into the offline environment.

## Release checklist

Before tagging a release:

1. Run `node tools/update-version.js <version>` to update `build.gradle`, the release-workflow pin, the deployment name, and `OSCAR_VERSION`.
2. Write the parent and Viewer changelog entries. Review every current-release label enforced by `tools/validate-release-metadata.js` in the root/release/feature guides, Modules documentation wrappers, and all four localized manuals. Update current-release labels and translated content together, but preserve historical introduction versions and migration boundaries such as `pre-3.11.0` unless the compatibility policy itself changed.
3. Run `node tools/validate-release-metadata.js <version>` and confirm `dist/release/postgis/pgdata` does not exist.
4. Run the appropriate canonical build script.
5. Run `tools/test-storage-powershell.ps1` under Windows PowerShell 5.1, then complete and record the
   manual release-acceptance matrix: fresh initialization, same-profile upgrade, backup/verification,
   isolated restore, archive status/verification/export, copy-only mixed-tier queries, tokenized
   purge of disposable data, zero-day (next-scan) exact-five JPEG eligibility and fewer-than-five-frame fallback, and both
   offline profiles on Windows 11 x86-64 with Docker Desktop/WSL 2 and local NTFS. Repeat deployment
   and storage acceptance on Ubuntu Server 24.04 x86-64, and confirm macOS deployment operations fail
   closed. Record the release version, image IDs, test results, and approver. Docker Desktop license
   acceptance and any required restart remain administrator actions; OSCAR does not accept the
   agreement on their behalf.

Configure the GitHub `oscar-release-acceptance` environment with required reviewers. The tag
workflow reaches that protected environment only after the tiered-storage PostgreSQL suite, the
destructive disposable PostgreSQL self-contained restore/timeline drill, and the native Windows
PowerShell 5.1 gates pass; approval attests that the recorded manual matrix above passed before the
workflow packages or publishes artifacts.

Tags matching `v*` trigger the release workflow. Before packaging, the workflow runs the explicitly listed direct tiered-storage integration methods against a disposable PostgreSQL/PostGIS service pinned to the same base-image digest used by the release. Those methods cover the database hot/cold lifecycle, late arrivals, failed activation cleanup, observation conflict handling, archive-activation races with updates/removals, one-connection cold-removal revalidation, restart ID high-water, open time bounds, online index migration, final-flush failure, byte limits and splitting, sparse windows, stale-job retry, symlink rejection, and independent-store namespace isolation without pulling in the legacy inherited PostGIS suite. A separate destructive PostgreSQL 16 job proves self-contained base-backup recovery with no WAL volume, promotion onto a new timeline, a durable post-promotion write, `archive_mode=off`, and cleanup of recovery-only settings. A disposable Compose gate also proves that both adopted external volumes retain their identities and canaries without a volume-recreation prompt. A native Windows job parses and exercises the release PowerShell scripts under Windows PowerShell 5.1. These automated gates do not replace the manual Docker Desktop/WSL 2, Ubuntu deployment, backup/restore, purge/export, or FFmpeg acceptance matrix above. Ordinary `build-all.sh` runs remain software-only and do not require PostgreSQL or Docker on localhost. After the gates pass, the workflow invokes `build-all.sh` and publishes the connected release ZIP, localized operator-manual PDFs, source archive, and structurally validated Ubuntu 24.04 and Windows 11 offline media. The connected ZIP also contains the current Markdown guides and localized manuals; obsolete legacy manuals are excluded.

The release workflow builds and structurally validates both the `--network none`-verified Ubuntu 24.04 offline bundle (`ubuntu-x86_64-offline-full`) and the Windows offline bundles (`windows-x86_64-offline-full` and `windows-x86_64-offline-images`), while publication still requires the recorded Ubuntu 24.04 and Windows 11 Docker Desktop/WSL 2 runtime acceptance above.
