# OSCAR End-to-End Regression Suite & Release Certification Guide

[`ORNL/oscar-regression`](https://github.com/ORNL/oscar-regression) provides automated end-to-end functional, fault-injection, multi-pass vehicle OCR, `PARQUET_PRIMARY` storage-lifecycle, destructive backup/restore, and 24/7 UI endurance validation for OSCAR 3.12.1 test deployments.

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

# Validate TypeScript types and run the offline unit test suite
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
| `STORAGE_WORKFLOW` | `required` | Gates OSCAR 3.12.1 `PARQUET_PRIMARY`, 5-JPEG retention, atomic publisher, and schema checks |
| `OSCAR_BACKUP_MODE` | `disabled` *(or `single`)* | Certifies fail-closed disabled backups or single-snapshot backup behavior (`STORAGE_BACKUP_WORKFLOW`) |
| `OSCAR_SSH_TARGET` | `oscar@oscar-test.example.org` | SSH host used for the remote mutation lease, Docker resource sampling, and storage probes |
| `OSCAR_RELEASE_DIR` | `/srv/oscar-test/oscar-3.12.1` | Canonical non-symlinked release path on `OSCAR_SSH_TARGET` |
| `OSCAR_STORAGE_TARGET_ACK` | `<host>\|<ssh>\|<dir>\|DISPOSABLE-STORAGE` | **Safety interlock #4:** Required before any storage probe executes |

### Rebinding After Deploying a New Release Directory

Whenever you unpack and deploy a new OSCAR 3.12.1 build into a clean versioned folder, preview and apply the release rebind helper (which verifies the running container provenance over strict SSH without touching secrets):

```sh
./scripts/rebind-active-release.sh --build-label 3.12.0-rc1
./scripts/rebind-active-release.sh --apply --build-label 3.12.0-rc1
```

---

## 3. Execution Profiles & All 28 Functional Scenarios

### Profile Reference

| Profile | Command | When to Use |
| --- | --- | --- |
| **`smoke`** | `npm run test:smoke` *(or `./scripts/run-regression.sh smoke`)* | Fast, non-fault-injecting verification across all 14 read-only, reporting, QR camera-scan, `runtime-extensions`, and `storage-health` scenarios |
| **`full`** | `npm run test:full` *(or `./scripts/run-regression.sh full`)* | **Mandatory pre-release / release sign-off gate:** Complete 28-scenario regression (`smoke` plus reserved-lane disconnect, detector/tamper faults, alarms, UUID, adjudication, `cargo-uff`, `training-sandbox`, `lane-webrelay`, `multi-node-federation`, EML, Vehicle OCR, `>= 150 s` extended occupancy, and natural `PARQUET_PRIMARY` Option A partition retirement) |
| **`3.11.0-release`** | `npm run test:3.11.0-release` | Strict unfiltered release certification gate (rejects `--scenario` filters, skipped required workflows, or mismatched `OSCAR_BUILD_LABEL`) |
| **`restore-drill`** | `OSCAR_BACKUP_MODE=single STORAGE_WORKFLOW=required STORAGE_BACKUP_WORKFLOW=required npm run test:restore-drill` | Destructive isolated single-snapshot backup, database/state/archive canary mutation, streamed-WAL base-backup restore, and timeline-promotion proof (requires the 4 `OSCAR_RESTORE_*_ACK` interlocks) |
| **`ui-endurance`** | `./scripts/run-ui-endurance.sh` | Continuous never-reloaded 24/7 Wallboard Watcher + PWA Service Worker notification + scoped/unscoped adjudication soak loop |

> **Non-Negotiable Release Sign-Off Rule:** `smoke` and `--scenario` filters are fast iteration and post-upgrade sanity checks only — they **never** certify an `ORNL/oscar` release (`v3.x.y`). Every release sign-off requires an unfiltered `./scripts/run-regression.sh full` `PASS` (`0` incorrect checks, `0` runtime errors, `0` restarts, `0` OOMs) on the 50-lane Ubuntu 24.04 LTS emulator-backed portal alongside live Ubuntu 24.04 LTS + Windows 11 WSL 2 upgrade acceptance and multi-host soak verification.

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
| Full | `training-sandbox` | Launches `oscar.sh sandbox start` (`:8444`), exercises Track 1/2/3 staging, loopback Rapiscan + RS-350 mobile detector + custom widget dashboard labs, Training Coach auto-verification, watermarked exports + PDF Completion Record, runs `sandbox stop`, and proves `0` delta across operational PostgreSQL, `oscar_oscar_state`, and Parquet archive |
| Full | `lane-webrelay` | Arms loopback ControlByWeb WebRelay-Quad `R1–R4`, verifies `AUTO` suppression on `Code 9999` / `Code 9998`, pulses `R3`/`R4` on actionable alarms, validates `MUTED`/`PASS_THROUGH`/`MANUAL` modal controls, and confirms fail-safe `0,0,0,0` release |
| Full | `multi-node-federation` | Registers a federated peer node with a scoped `Bearer` service token, executes cross-node Vehicle ID search + `VEHICLE_INCIDENT` export + linked adjudication, and verifies clean peer removal |
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

---

## 5. Self-Contained 50-Lane Staging Node & Manual `workflow_dispatch` Certification

Maintainers with **Write** (or higher) access on `ORNL/oscar` can trigger an automated `smoke` or `full` certification run directly from GitHub Actions against an isolated, self-contained 50-lane Ubuntu Server 24.04 staging node via [`.github/workflows/staging-50-lane-certification.yml`](https://github.com/ORNL/oscar/blob/main/.github/workflows/staging-50-lane-certification.yml).

### 5.1 Security Boundary & Trigger Rules

- **Strictly manual `workflow_dispatch` only:** Because `ORNL/oscar` is a public repository, `.github/workflows/staging-50-lane-certification.yml` intentionally forbids `pull_request`, `pull_request_target`, and `push` triggers so untrusted external forks can never execute code on the self-hosted `oscar-50-lane-staging` runner.
- **Isolated branch builds (zero direct staging access):** When a Write+ maintainer sets `deploy_branch=true` to test a feature/fix branch without SSH or Tailscale access to the staging host, Job 1 (`build-branch-release`) builds and unit-tests the connected release ZIP strictly inside a disposable **GitHub-hosted `ubuntu-latest` VM** from `ORNL/*` refs only (never untrusted external forks) and records its exact SHA-256 digest.
- **Allowlisted wrapper invocation & mandatory ZFS rollback:** Job 2 (`certify-50-lane-staging`) runs only the fixed root-owned host wrapper `/usr/local/bin/oscar-self-test` (`run-smoke`, `run-full`, or `run-branch-test`), validates all branch refs and `--scenario` filters strictly, verifies the downloaded branch ZIP's exact SHA-256 before extraction (with zip-slip rejection), serializes staging runs via job-level `concurrency: group: oscar-50-lane-staging`, forces mandatory `@pre-test` ZFS rollback + baseline Docker image tag restoration on exit (including failures or cancellations) for every branch test, and redacts IPv4 literals, tailnet hostnames, and SSH usernames before writing `GITHUB_STEP_SUMMARY` or uploading the 14-day `oscar-50-lane-staging-report-<suite>-<run_number>` artifact bundle.

### 5.2 Workflow Inputs & Triggering from GitHub UI or CLI

| Input | Type / Default | Effect |
| :--- | :--- | :--- |
| `suite` | `smoke` *(default)* \| `full` | Runs read-only `smoke` (~6–8 min) or full 28-scenario `full` (~45 min including fault/alarm injection, OCR, Cargo UFF, Training Sandbox, WebRelay, EML, `:8445` federation, and natural Parquet retirement). |
| `scenario` | `string` *(empty = all)* | Optional comma-separated filter (for example `preflight,viewer-navigation` or `multi-node-federation`). Remember: targeted `--scenario` runs never substitute for an unfiltered `full` release sign-off. |
| `deploy_branch` | `boolean` *(`false`)* | When `false`, tests the currently deployed staging baseline. When `true`, builds the requested `ORNL/*` branch(es) in GitHub-hosted `ubuntu-latest`, ephemerally upgrades staging under an `@pre-test` ZFS snapshot, executes `suite`, and **always** rolls staging back to its exact baseline ZFS state and Docker images on exit. |
| `oscar_ref` | `string` *(`main`)* | `ORNL/oscar` branch or tag to build when `deploy_branch=true` (for example `main` or `feat/my-branch`). |
| `modules_branch` | `string` *(empty)* | Optional `ORNL/osh-oakridge-modules` branch override when `deploy_branch=true` (leave blank to use `oscar_ref`'s pinned submodule commit). |
| `viewer_branch` | `string` *(empty)* | Optional `ORNL/oscar-viewer` branch override when `deploy_branch=true` (leave blank to use `oscar_ref`'s pinned submodule commit). |
| `addons_branch` | `string` *(empty)* | Optional `ORNL/osh-addons` branch override when `deploy_branch=true` (leave blank to use `oscar_ref`'s pinned submodule commit). |
| `with_fed_peer` | `boolean` *(`false`)* | Boots the ephemeral local federated peer stack (`:8445`) during `smoke` runs (`full` always boots it automatically for `multi-node-federation`). |
| `rollback_after_test` | `boolean` *(`true`)* | Rolls back and destroys the ephemeral `@pre-test` ZFS snapshot after baseline runs (`deploy_branch=true` always enforces rollback regardless of this toggle). |

Trigger via GitHub Actions UI (**Actions → Staging 50-Lane Certification (Manual) → Run workflow** on `main`) or via GitHub CLI (`gh`):

```sh
# 1. Fast read-only smoke check on the current 50-lane staging baseline
gh workflow run staging-50-lane-certification.yml -R ORNL/oscar -f suite=smoke

# 2. Test a maintainer's branch across 50 lanes (zero SSH/Tailscale access, mandatory ZFS rollback)
gh workflow run staging-50-lane-certification.yml -R ORNL/oscar \
  -f deploy_branch=true \
  -f oscar_ref=main \
  -f modules_branch=feat/my-backend-fix \
  -f viewer_branch=feat/my-viewer-fix \
  -f suite=smoke \
  -f scenario=preflight,viewer-navigation,adjudication

# 3. Full unfiltered 28-scenario 50-lane branch certification
gh workflow run staging-50-lane-certification.yml -R ORNL/oscar \
  -f deploy_branch=true \
  -f oscar_ref=feat/my-release-branch \
  -f suite=full

# 4. Watch run progress and download redacted CSV/Markdown reports once complete
gh run list -R ORNL/oscar --workflow staging-50-lane-certification.yml --limit 5
gh run download <RUN_ID> -R ORNL/oscar -D /tmp/staging-report
```

### 5.3 Ephemeral `@pre-test` ZFS Rollback & Single-Box Co-Location Notes

1. **Snapshot / rollback lifecycle:** Before `run-full` mutates the staging portal, `oscar-self-test` snapshots the staging storage dataset (`@pre-test`), boots the isolated ephemeral `:8445` federated peer when needed, executes `ORNL/oscar-regression`, archives the redacted results under `/srv/oscar-test/results/<timestamp>/`, and rolls back + destroys `@pre-test` in a `finally` cleanup trap (leaving `0` lingering snapshots and a clean `3/3` healthy baseline).
2. **Interpreting co-located browser paint timings:** On a self-contained single-host staging box that runs the 50-lane OSCAR stack, 50 simulated RPMs, 50+ FFmpeg RTSP camera publishers, an ephemeral `:8445` peer, AND headless Playwright Chromium simultaneously on shared CPU cores, client-side Chromium React paint thresholds (`nextRenderMs`, `returnRenderMs`, `priority10xBackMs`) can occasionally exceed strict desktop workstation budgets by `~0.2–1.5 s` even when server-side API latency is fast and `obs5xx == 0` / `countCalls == 0`. Always inspect `functional-results.csv`, `storage-performance.csv`, and `performance.csv` to separate local Chromium CPU contention from genuine server, storage, or functional regressions.

---

## 6. Multi-Repo Developer Checklist: Adding a New Datastream or Config Field Safely

Because OSCAR coordinates 9 repositories around strict 50-lane scale, `PARQUET_PRIMARY`, localization, and upgrade-preservation invariants, any PR that adds a **new datastream output** or **new Java `*Config` field** must verify every lockstep item below before opening the PR (see also [`AGENTS.md`](https://github.com/ORNL/oscar/blob/main/AGENTS.md) and [Radiation Detector Driver Integration Guide](RADIATION_DETECTOR_DRIVER_GUIDE.md)):

1. **Register New High-Rate / Operational Outputs in the `PARQUET_PRIMARY` Allowlist (All 4 Lockstep Locations):**
   - [`ORNL/osh-addons`](https://github.com/ORNL/osh-addons): Update `TieredArchiveConfig.DEFAULT_OUTPUT_NAMES`, preserve the prior list as a `PREVIOUS_*_DEFAULT_OUTPUT_NAMES` compatibility constant so existing upgraded sites auto-recognize prior defaults cleanly, and classify the stream into either **`RAW_EVENTS`** (searchable event/summary streams compacted daily/monthly) or write-once **`RAW_TELEMETRY`** (high-rate `1 Hz` / status streams written once and never rewritten).
   - [`ORNL/oscar`](https://github.com/ORNL/oscar): Update `dist/config/standard/config.json` (`archive.outputNames`), `tools/validate-release-metadata.js` (`expectedArchiveOutputs`), and `tools/validate-packaged-release.js` (`expectedArchiveOutputs`).
   - [`ORNL/oscar-regression`](https://github.com/ORNL/oscar-regression): Update expected allowlist checks in `src/storage-oracles.ts` and `scripts/oscar-storage-regression-probe.sh`.
   - **Existing upgraded sites:** Remember that `oscar upgrade` intentionally preserves an existing host's `/var/lib/oscar/config.json`. Document any newly added output in [RELEASE_NOTES_AND_UPGRADE_GUIDE.md](RELEASE_NOTES_AND_UPGRADE_GUIDE.md) so administrators enabling a new sensor/feature on upgraded hosts know whether `archive.outputNames` should include the new output (preventing unbounded writes to `ONLY oscar.obs`).
2. **Keep CQL Predicates, `oscar_archive_schema` Counters & Startup `< 60 s` in Lockstep:**
   - Never add growing B-tree or GIN indexes over unbounded historical observations, and never use raw `?` JSONB operators inside JDBC `PreparedStatement` SQL (use `jsonb_typeof(col->'key')`).
   - If `StatisticsOutput`, `ReportDataAggregator`, or Viewer tables query a new CQL predicate across high-rate streams, map it to an exact `JsonCqlEvaluator.SummaryCounterSpec` backed by `oscar_archive_schema` and `ArchiveCompactionManager.StreamStatsAccumulator` (verifying `COALESCE(s.<col>, COALESCE(s.row_count, 0))` for `upperBoundExpr`, `IS NOT NULL` for `exactReadyExpr`, and gating new `base_summary_mask` bits behind `JsonCqlEvaluator.BIT_MASK_V2`).
   - Never execute unbounded full-table `UPDATE oscar_archive_schema` or multi-file DuckDB backfills synchronously inside `ArchiveCatalog.migrate()` (keep inline updates gated to `<= 64` generations and drain larger upgrades asynchronously via `oscar-base-summary-backfill` so module startup stays well under OpenSensorHub's `60 s` timeout).
3. **Stream Closure, `1 Hz` Zero-Clone Drivers & EventBus Hygiene:**
   - Always wrap `IObsStore.select*` / `ISystemDescStore.select*` streams in `try-with-resources` and pass `.withLimit(1)` on single-record `ObsFilter.Builder` lookups so DuckDB's 2-session pool never leaks.
   - Pre-clone `liveDataStruct = dataStruct.copy()` once in `init()` on `>= 1 Hz` drivers rather than cloning SWE component trees per sample, and cancel every `EventBus` `Subscription` in `doStop()`.
4. **Java `*Config` Serialization & `ConfigCloner` Rules:**
   - Always initialize mutable collection fields in `*Config` classes with mutable standard collections (`new ArrayList<>()`, `new LinkedHashMap<>()`, `new LinkedHashSet<>()`) — never `List.of(...)` or `Collections.emptyList()` — so OpenSensorHub's `ConfigCloner` (`ModuleConfigBase.clone()`) and Vaadin Admin UI editors never throw `UnsupportedOperationException`.
   - Give every new config field a safe backward-compatible default (opt-in `enabled = false` for optional capabilities) so existing persisted `config.json` files deserialize cleanly without breaking live portals.
5. **4-Locale Admin UI, Viewer & Packaging Parity:**
   - Add `@DisplayInfo` labels/descriptions and matching entries in `ConfigMessages{,_es,_fr,_el}.properties` and module `i18n/README{,_es,_fr,_el}.md` (`./gradlew --no-parallel :sensorhub-webui-oscar:test` verifies parity), and mirror any Viewer strings across `web/oscar-viewer/src/locales/{en,es,fr,el}.json` (`npm run validate:locales`).
   - Any new standalone guide under `docs/*.md` must be added to **both** `into("osh-node-oscar/documentation")` and `into("documentation")` in `build.gradle`, `tools/validate-release-metadata.js`, and `tools/validate-packaged-release.js`.
6. **Coordinate Cross-Repo CI with Identical Branch Names:**
   - Use the **exact same branch name** across `ORNL/oscar`, `ORNL/osh-addons`, `ORNL/osh-oakridge-modules`, and `ORNL/oscar-viewer` (for example `feat/my-new-sensor`) so submodule CI workflows automatically build against the matching `ORNL/oscar` composite branch.
