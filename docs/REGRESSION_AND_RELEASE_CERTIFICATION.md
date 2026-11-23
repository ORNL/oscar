# OSCAR End-to-End Regression Suite & Release Certification Guide

[`ORNL/oscar-regression`](https://github.com/ORNL/oscar-regression) provides automated end-to-end functional, fault-injection, multi-pass vehicle OCR, `PARQUET_PRIMARY` storage-lifecycle, destructive backup/restore, and 24/7 UI endurance validation for OSCAR 3.11.7 test deployments.

For a captioned 1080p walkthrough, watch [Module 22 (`22-regression-suite-setup-and-certification.mp4`)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/22-regression-suite-setup-and-certification.mp4) in [VIDEO_GUIDES.md](VIDEO_GUIDES.md).

> **Authorized Test Systems Only:** The `full`, `3.11.0-release`, `restore-drill`, and `ui-endurance` profiles inject deterministic RPM disconnects, detector/tamper/extended-occupancy faults, radiation alarms, and permanent `Code 9` adjudication audit records (and `restore-drill` overwrites PostgreSQL, state, and archive planes on an isolated target). Never point the regression suite at a production portal or physical RPM lane.

---

## 1. Prerequisites & Installation

Install the regression runner on a Linux workstation or dedicated test runner with network access to your emulator-backed OSCAR test deployment and RPM/RTSP simulator:

- **Node.js `20.16+`** (`22 LTS` recommended) and `npm`
- **Chromium** (installed via Playwright or system `BROWSER_EXECUTABLE_PATH`)
- **Non-interactive SSH access** (`StrictHostKeyChecking=yes`) to the OSCAR Docker host when `STORAGE_WORKFLOW=required` or host container CPU/RSS/OOM metrics sampling (`OSCAR_SSH_TARGET`) is enabled

```sh
git clone https://github.com/ORNL/oscar-regression.git
cd oscar-regression
npm ci
npm run install:browser

# Validate TypeScript types and run the 246 offline unit tests
npm run check
npm test
```

---

## 2. Configuration (`.env`) & Multi-Layer Safety Interlocks

Create a root- or owner-restricted `.env` file from `.env.example` (never commit `.env` to Git):

```sh
cp .env.example .env
chmod 600 .env
```

### Core Target, Emulator & Workflow Settings

| Variable | Example / Default | Purpose |
| --- | --- | --- |
| `OSCAR_BASE_URL` | `https://oscar-test.example.org` | HTTPS URL of the OSCAR Viewer under test |
| `OSCAR_TEST_TARGET_ACK` | `oscar-test.example.org` | **Safety interlock #1:** Must match the exact hostname in `OSCAR_BASE_URL` |
| `OSCAR_USERNAME` / `OSCAR_PASSWORD` | `admin` / `<secret>` | Test administrator credentials |
| `RPM_EMULATOR_URL` | `http://rpm-sim.example.org:8000` | HTTP control endpoint of the RPM emulator |
| `RPM_EMULATOR_TARGET_ACK` | `rpm-sim.example.org` | **Safety interlock #2:** Required for `full`; must match the emulator host |
| `TEST_RPM_ID` / `TEST_LANE_LABEL` | `rpm-50` / `Lane50` | Reserved emulator RPM and OSCAR lane isolated during `full` fault/alarm tests |
| `RPM_LANE_MAPPING_ACK` | `rpm-50:Lane50` | **Safety interlock #3:** Confirms exact `<TEST_RPM_ID>:<TEST_LANE_LABEL>` pairing |
| `EXPECTED_LANE_COUNT` / `EXPECTED_CAMERA_COUNT` | `50` / `50` *(or `6` / `6` on scaled Windows WSL 2)* | Expected online lane and camera counts on Status of Health and Dashboard |
| `OSCAR_LANE_CONFIG_PATH` | `fixtures/oscar-50-lane-config.csv` | Canonical 20-column (or `14 + 6*N` multi-camera) CSV used as the Operational View oracle |
| `OPERATIONAL_VIEW_WORKFLOW` | `required` | Validates all 7 Operational Views (`east-gate`, `west-gate`, `north-gate`, `south-gate`, `pedestrian`, `entrance`, `exit`) |
| `EVENT_UUID_WORKFLOW` | `required` *(or `auto` / `disabled`)* | Gates Event UUID search, direct links, view-scoping, and PDF/QR preservation |
| `ALARM_TRANSFER_CAMERA_WORKFLOW` | `required` *(or `auto` / `disabled`)* | Gates deterministic `640x480` QR Version 23 camera-scan and permission recovery |
| `VEHICLE_OCR_WORKFLOW` | `required` *(or `auto` / `disabled`)* | Gates PP-OCRv3 container/plate auto-fill (`EXPECTED_VEHICLE_OCR_CONTAINER=EGHU3972694` or `ANY`), `Compare Passes`, Linked Adjudication, and `VEHICLE_INCIDENT` reports |
| `SPECTROSCOPIC_WORKFLOW` | `auto` *(or `required` / `disabled`)* | Uploads local `.spe` / `.n42` files from `spectroscopic-files/`, verifying `N42 Report` and Sandia WebID |
| `CARGO_UFF_WORKFLOW` | `auto` *(or `required` / `disabled`)* | Verifies zero UI clutter when Cargo UFF is disabled, exercises local `.uff` upload + 16-bit `uint16` TIFF/HEMD viewer controls, tests live SMBv2/v3 share connection (`CARGO_UFF_SMB_SHARE`), scanner/time-window browsing, Tier-1 UUID omnibox lookup, 1-char fuzzy OCR correlation, and zero-download adjudication staging, and restores `uff.enabled = false` in `finally` |
| `EML_WORKFLOW` | `auto` *(or `required` / `disabled`)* | Uploads `OSCAR_EML_PLUGIN_PATH` (`.jar`) and verifies `Code 9999: EML Non-Threat` auto-adjudication |
| `STORAGE_WORKFLOW` | `required` | Gates OSCAR 3.11.7 `PARQUET_PRIMARY`, 5-JPEG retention, atomic publisher, and schema checks |
| `OSCAR_BACKUP_MODE` | `disabled` *(or `single`)* | Certifies fail-closed disabled backups or single-snapshot backup behavior (`STORAGE_BACKUP_WORKFLOW`) |
| `OSCAR_SSH_TARGET` | `oscar@oscar-test.example.org` | SSH host used for the remote mutation lease, Docker resource sampling, and storage probes |
| `OSCAR_RELEASE_DIR` | `/srv/oscar-test/oscar-3.11.7` | Canonical non-symlinked release path on `OSCAR_SSH_TARGET` |
| `OSCAR_STORAGE_TARGET_ACK` | `<host>\|<ssh>\|<dir>\|DISPOSABLE-STORAGE` | **Safety interlock #4:** Required before any storage probe executes |

### Rebinding After Deploying a New Release Directory

Whenever you unpack and deploy a new OSCAR 3.11.7 build into a clean versioned folder, preview and apply the release rebind helper (which verifies the running container provenance over strict SSH without touching secrets):

```sh
./scripts/rebind-active-release.sh --build-label 3.11.7-rc1
./scripts/rebind-active-release.sh --apply --build-label 3.11.7-rc1
```

---

## 3. Execution Profiles & All 26 Functional Scenarios

### Profile Reference

| Profile | Command | When to Use |
| --- | --- | --- |
| **`smoke`** | `npm run test:smoke` *(or `./scripts/run-regression.sh smoke`)* | Fast, non-fault-injecting verification across all 14 read-only, reporting, QR camera-scan, `runtime-extensions`, and `storage-health` scenarios |
| **`full`** | `npm run test:full` *(or `./scripts/run-regression.sh full`)* | Complete 26-scenario regression: runs `smoke` plus reserved-lane disconnect, detector/tamper faults, alarms, UUID, adjudication, `cargo-uff`, `training-sandbox`, EML, Vehicle OCR, `>= 150 s` extended occupancy, and natural `PARQUET_PRIMARY` partition retirement |
| **`3.11.0-release`** | `npm run test:3.11.0-release` | Strict unfiltered release certification gate (rejects `--scenario` filters, skipped required workflows, or mismatched `OSCAR_BUILD_LABEL`) |
| **`restore-drill`** | `OSCAR_BACKUP_MODE=single STORAGE_WORKFLOW=required STORAGE_BACKUP_WORKFLOW=required npm run test:restore-drill` | Destructive isolated single-snapshot backup, database/state/archive canary mutation, streamed-WAL base-backup restore, and timeline-promotion proof (requires the 4 `OSCAR_RESTORE_*_ACK` interlocks) |
| **`ui-endurance`** | `./scripts/run-ui-endurance.sh` | Continuous never-reloaded 24/7 Wallboard Watcher + PWA Service Worker notification + scoped/unscoped adjudication soak loop |

### Targeted Scenario Filtering (`--scenario`)

During feature development or targeted verification, pass a comma-separated `--scenario` list to `smoke` or `full` (the reserved RPM is still snapshotted and restored automatically in a `finally` block):

```sh
# Validate Dashboard health and multi-format report generation only
npm run test:smoke -- --scenario dashboard-health,reporting

# Validate RPM fault injection, Vehicle OCR correlation, and adjudication
npm run test:full -- --scenario rpm-faults,vehicle-ocr,adjudication
```

| Phase | Scenario ID | Key Assertions & SLOs |
| --- | --- | --- |
| Smoke | `preflight` | HTTPS reachability, cache-control headers, session auth, and datastream discovery (`<= 1.5 s`) |
| Smoke | `viewer-navigation` | Route navigation and persistent Dashboard panel toggles (`Lane Status`, `Event Table`, `Quick View`) |
| Smoke | `map-national-servers` | Georeferenced Site Map markers, National View statistics refresh, and `/servers` node table |
| Smoke | `sensorhub-admin` | `/sensorhub/admin` module readiness and localized `README` availability |
| Smoke | `status-of-health` | Online RPM/camera state and explicit `tamper_fault=false` baseline across all configured lanes |
| Smoke | `dashboard-health` | Per-lane compact health indicators, independent camera connectivity, and keyboard navigation |
| Smoke | `lane-video` | Real-time Gamma/Neutron waveform advancement, HLS video startup (`<= 15 s`), and multi-camera cycling |
| Smoke | `event-filtering` | Page 0 load (`<= 4.5 s`), count query (`<= 3.5 s`), Next-page (`<= 1.5 s`), Saved Queries, and UpSet chart (`<= 6.0 s`) |
| Smoke | `operational-views` | Exact lane membership across all 7 views, URL persistence, and fail-closed unknown view handling |
| Smoke | `reporting` | `RDS_SITE`, `LANE`, `EVENT`, `VEHICLE_INCIDENT`, `ADJUDICATION`, and `ADJUDICATION_DETAILS` in `PDF`/`CSV`/`JSON`/`XLSX` |
| Smoke | `alarm-transfer` | Signed `.oscar-alarm.json` export, `SHA-256` verification, chart redraw, and re-download fidelity |
| Smoke | `alarm-transfer-camera` | Synthetic `640x480` QR Version 23 camera scan, track cleanup, and camera permission recovery |
| Smoke | `runtime-extensions` | `/extensions` tabs, starter templates, regional OCR rules, PMTiles v3 `HTTP 206` map serving, spectroscopy library, CA X.509 trust (with private-key `HTTP 400` rejection), policy pack export, and 1-click reset to shipped defaults |
| Smoke | `storage-health` | 5-JPEG manifest/decode audit, atomic publisher check, `archive_mode=off`, OCI labels, and backup-mode gate |
| Full | `rpm-connection` | Reserved RPM TCP disconnect detection and clean reconnect recovery |
| Full | `rpm-faults` | `gamma-high`, `gamma-low`, `neutron-high`, and `tamper` fault transitions with valid ISO timestamps |
| Full | `rpm-alarms` | Back-to-back `1 s` gamma/neutron alarms, MP4 association, zero camera timeout logs, and Page 0 refill |
| Full | `event-uuid` | Public observation ID lookup, direct links, view-scoped isolation, and PDF/QR UUID fidelity |
| Full | `adjudication` | Full operator adjudication, `.spe`/`.n42` upload (`N42 Report` + Sandia WebID), and audit trail |
| Full | `cargo-uff` | Zero-clutter disabled check, local `.uff` upload, live SMBv2/v3 `UFF 2.0`/`3.0` picker, Tier-1 UUID omnibox lookup, `OCR ±1` correlation, 16-bit TIFF/HEMD viewer, zero-download `.uffref.json` adjudication staging, and `finally` reset |
| Full | `training-sandbox` | Launches `oscar.sh sandbox start` (`:8444`), exercises Track 1/2/3 staging, loopback Rapiscan scenario injection, Training Coach auto-verification, watermarked exports + PDF Completion Record, runs `sandbox stop`, and proves `0` delta across operational PostgreSQL, `oscar_oscar_state`, and Parquet archive |
| Full | `eml-auto-adjudication` | EML VM-250 `.jar` upload, per-lane toggle, and `Code 9999: EML Non-Threat` auto-adjudication |
| Full | `vehicle-ocr` | Live PP-OCRv3 ISO 6346 container read, auto-fill, `Compare Passes`, Linked Adjudication, and `VEHICLE_INCIDENT` PDF |
| Full | `extended-occupancy` | `>= 150 s` occupancy fault (`Fault - Extended Occupancy`) and `Code 9998` gamma-only auto-adjudication |
| Full | `adjudication-report` | Post-adjudication report verification confirming new disposition and isotope counts |
| Full | `storage-lifecycle` | Natural `30`-min staging partition -> `5`-min delay -> ZSTD Parquet parity proof -> whole-child retirement |

---

## 4. Interpreting Regression Output Artifacts (`results/<run-id>/`)

Every invocation writes a self-contained evidence directory under `results/<UTC-timestamp>-<runner>/` and exits `0` **only** when `incorrect == 0`:

- `summary.md` — Human-readable narrative `PASS`/`FAIL` report with check counts, peak/mean container CPU & RSS, restart/OOM verification (`0` required), and failed-check diagnostics.
- `functional-results.csv` — One row per assertion (`scenario`, `category`, `action`, `target`, `expected`, `observed`, `status`, `durationMs`, `evidence`, `error`).
- `performance.csv` — Time-series Docker container (`oscar`, `postgres`, `gateway`) CPU %, memory RSS, PID count, restart count, OOM flag, and host load samples tagged by active scenario phase.
- `storage-performance.csv` — Point-in-time PostgreSQL batch counters, `PARQUET_PRIMARY` generation/parity metrics, Daily File journal counters, and 5-JPEG retention ledger stats.
- `errors.csv` & `run.json` — Browser/network/API exception log and immutable run metadata (`suiteGitCommit`, `oscarLaneConfigSha256`, workflow flags).
- `evidence/` & `downloads/` — Full-HD failure/milestone PNG screenshots, reserved-RPM recovery snapshot JSON, generated PDF/XLSX reports, and exported QR packages.
