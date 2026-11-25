# AI Agent & Developer Guide — `ORNL/oscar` Multi-Repository Workspace

Welcome to **OSCAR** (Oak Ridge National Laboratory's OpenSensorHub-based Radiation Portal Monitoring, Mobile Detection, and Cargo Non-Intrusive Inspection platform).

This document is the canonical architectural contract for **both human contributors and AI coding agents** (`Antigravity` / `Gemini`, `Codex`, `Claude Code`, `Cursor`, `GitHub Copilot`). Read this file and [`docs/ARCHITECTURAL_ROADMAP.md`](docs/ARCHITECTURAL_ROADMAP.md) **before** designing, editing, or reviewing changes in `ORNL/oscar` or any of its linked repositories.

Workspace skills for AI agents are also checked into [`.agents/skills/`](.agents/skills/):
- [`.agents/skills/oscar-contributor-scale-guardrails/SKILL.md`](.agents/skills/oscar-contributor-scale-guardrails/SKILL.md) — 50-lane PostgreSQL/Parquet/DuckDB, 1 Hz driver, HLS, security, and localization verification runbook.
- [`.agents/skills/oscar-v312-feature-blueprints/SKILL.md`](.agents/skills/oscar-v312-feature-blueprints/SKILL.md) — File-by-file implementation blueprints for `v3.12.0` (`MobileDetectorSystem` and Opt-In Custom Widget Dashboards).

---

## 1. Repository Topology & Submodule Map

`ORNL/oscar` is the top-level release, packaging, Docker/Compose, and documentation root coordinating 9 repositories:

| Repository | Workspace Path (in `ORNL/oscar`) | Default Branch | Role | Repo-Local Agent Guide |
| --- | --- | --- | --- | --- |
| [`ORNL/oscar`](https://github.com/ORNL/oscar) | `.` (root) | `main` | Gradle composite build, Docker/Compose, setup/upgrade/backup scripts, release bundles, docs, roadmap | [`AGENTS.md`](AGENTS.md) |
| [`ORNL/osh-core`](https://github.com/ORNL/osh-core) | `include/osh-core` | `OSCAR` | OpenSensorHub core runtime, Jetty HTTP server, ConSys API, `FederatedObsStore`, module registry | Inherited from root `AGENTS.md` |
| [`ORNL/osh-addons`](https://github.com/ORNL/osh-addons) | `include/osh-addons` | `OSCAR` | `OscarTieredObsStore` (`PARQUET_PRIMARY`), PostGIS hot store, DuckDB Parquet federation, FFmpeg/HLS | Inherited from root `AGENTS.md` |
| [`ORNL/osh-oakridge-modules`](https://github.com/ORNL/osh-oakridge-modules) | `include/osh-oakridge-modules` | `main` | `LaneSystem`, Rapiscan/Aspect/RS-350/D5 drivers, EML, OCR, Cargo UFF, BasicSession auth, Vaadin Admin | [`include/osh-oakridge-modules/AGENTS.md`](https://github.com/ORNL/osh-oakridge-modules/blob/main/AGENTS.md) |
| [`ORNL/oscar-viewer`](https://github.com/ORNL/oscar-viewer) | `web/oscar-viewer` | `main` | Next.js / React / TypeScript operator console (`/` Dashboard, `/event-log`, `/lane-view`, `/map`, `/health`, `/report-view`, `/servers`, `/users`) | [`web/oscar-viewer/AGENTS.md`](https://github.com/ORNL/oscar-viewer/blob/main/AGENTS.md) |
| [`ORNL/osh-js`](https://github.com/ORNL/osh-js) | *(npm dependency in `web/oscar-viewer`)* | `add-consys` | Connected Systems REST / MQTT / WebSocket client SDK | — |
| [`ORNL/oscar-video-guides`](https://github.com/ORNL/oscar-video-guides) | *(bundled at build time into `/video-guides/`)* | `main` | `29` localized (`en`, `es`, `fr`, `el`) `< 2 min` MP4 workflow guides + WebVTT/SRT captions | — |
| [`ORNL/oscar-regression`](https://github.com/ORNL/oscar-regression) | *(standalone Playwright + TypeScript E2E suite)* | `main` | `25` end-to-end functional, storage-lifecycle, fault/alarm injection, OCR, UFF, and sandbox scenarios | — |
| [`ORNL/oscar-federation-hub`](https://github.com/ORNL/oscar-federation-hub) | *(standalone hub deployment)* | `main` | Multi-site Zero-Trust federation & tunnel gateway | — |

---

## 2. Roadmap, Milestones & Shared-Branch Collaboration Model

### 2.1 Live Roadmap & Tracking Links
- **In-Repository Engineering Roadmap:** [`docs/ARCHITECTURAL_ROADMAP.md`](docs/ARCHITECTURAL_ROADMAP.md)
- **GitHub Milestones (Live Progress View):** <https://github.com/ORNL/oscar/milestones>
  - [Milestone `#1` — Incorporated: `v3.10.0 – v3.11.15` Platform, Security & 50-Lane Scale Hardening](https://github.com/ORNL/oscar/milestone/1) ([`#78`](https://github.com/ORNL/oscar/issues/78), [`#79`](https://github.com/ORNL/oscar/issues/79))
  - [Milestone `#2` — Planned `v3.12.0`: Mobile Detector System (RS-350 & Kromek D5)](https://github.com/ORNL/oscar/milestone/2) ([`#80`](https://github.com/ORNL/oscar/issues/80))
  - [Milestone `#3` — Planned `v3.12.0`: Opt-In Custom Widget Dashboards (`/dashboards`)](https://github.com/ORNL/oscar/milestone/3) ([`#81`](https://github.com/ORNL/oscar/issues/81))
  - [Milestone `#4` — Planned `v3.12.0`: Field Cutover & Operational Polish](https://github.com/ORNL/oscar/milestone/4) ([`#74`](https://github.com/ORNL/oscar/issues/74), [`#75`](https://github.com/ORNL/oscar/issues/75), [`#77`](https://github.com/ORNL/oscar/issues/77))
  - [Milestone `#5` — Planned `v3.12.0`: Multi-Year Cold Parquet CQL Count & Query Scale](https://github.com/ORNL/oscar/milestone/5) ([`#84`](https://github.com/ORNL/oscar/issues/84), [`ORNL/osh-addons#21`](https://github.com/ORNL/osh-addons/issues/21))
- **GitHub Projects v2 Kanban Sync Tool:** [`tools/sync-project-board.mjs`](tools/sync-project-board.mjs) (`node tools/sync-project-board.mjs`)

### 2.2 Branch-Maintainer (`Write`) Workflow & Admin-Gated Releases
1. **Shared Feature/Fix Branches (`Write` Access):** Review-group developers have **Write (branch-maintainer)** access across all 9 `ORNL/*` repositories so multiple contributors and AI agents can push directly to shared branches (`feat/*`, `fix/*`) inside `ORNL/*` without fork-sync friction, triggering GitHub Actions CI automatically on every push.
2. **Matching Branch Names Across Repositories:** In [`ORNL/osh-oakridge-modules/.github/workflows/ci.yml`](https://github.com/ORNL/osh-oakridge-modules/blob/main/.github/workflows/ci.yml), CI automatically checks whether `ORNL/oscar` has a branch with the **exact same name** as the PR branch (`refs/heads/<branch>`), using it as the composite build root when present. Always use matching branch names across coordinated PRs (e.g., `feat/v3.12.0-mobile-detector-system`).
3. **Protected Default Branches, Release Tags & Mandatory `full` Regression Gate:** Active GitHub Rulesets on all 9 repositories block direct pushes, force-pushes, deletions, and unreviewed merges on default branches (`main` / `OSCAR` / `add-consys`) and `refs/tags/v*`. Only the Repository Admin merges certified PRs into default branches and signs off on `v*` releases after:
   - **Unfiltered `ORNL/oscar-regression` `full` suite `PASS` (`./scripts/run-regression.sh full` with zero `--scenario` filters and `0` incorrect checks)** on the 50-lane Ubuntu 24.04 LTS certification portal (`smoke` or targeted `--scenario` runs never substitute for `full`);
   - Live upgrade / deployment acceptance on **both** Ubuntu Server 24.04 LTS and Windows 11 + WSL 2 (`3/3` healthy services, `0` restarts, `0` OOMs); and
   - Bounded multi-host soak verification (`0` leaked DuckDB sessions, bounded anonymous heap).

---

## 3. Non-Negotiable 50-Lane Scale & Safety Invariants

OSCAR is certified for **continuous 24/7 multi-year operation at 50-lane scale** (`50` RPMs + `50–100` RTSP cameras + continuous EML/OCR/UFF activity). Every change **must** uphold all 8 invariants below:

1. **Constant Hot PostgreSQL Footprint (`PARQUET_PRIMARY`) & Zero Growing SQL Indexes:**
   - All 22 operational and evidentiary datastreams (`gammaCounts`, `gammaThreshold`, `neutronCounts`, `setupGamma`, `setupNeutron`, `speed`, `backgroundReport`, `foregroundReport`, `status`, `emlContextual`, `emlScanContextual`, `emlAnalysis`, `dailyFile`, `connectionStatus`, `occupancyStatus`, `tamper`, `occupancy`, `adjudication`, `report`, `siteStatistics`, `nationalSummary`, `vehicleOcr`) route into 30-minute PostgreSQL stage partitions (`osg_*`) that retire to Zstandard Parquet after SHA-256 parity (`ONLY oscar.obs` stays permanently near-empty at `~52` static singleton rows).
   - **Never** add growing B-tree or GIN indexes over unbounded historical observations (`docs/STORAGE_ARCHITECTURE.md`), and **never** use raw `?` JSONB operators inside JDBC `PreparedStatement` SQL (use `jsonb_typeof(col->'key')`).
2. **Bounded DuckDB Cold-Tier Concurrency (`max 2` sessions per JVM) & Mandatory `try-with-resources` Stream Closure:**
   - `DuckDbResourcePolicy` caps concurrent Parquet queries at `2` sessions (`30 s` timeout). **Never** introduce background UI timers, per-lane `searchObservations` loops, or premature bucket-count fan-out that open cold Parquet scans without an explicit user filter/sort action.
   - **Always** wrap every Java `IObsStore.select(...)`, `selectKeys(...)`, and `selectEntries(...)` (plus `ISystemDescStore.select*`) stream in `try-with-resources`, and pass `.withLimit(1)` on single-record `ObsFilter.Builder` lookups (`findFirst()`, `withLatestResult()`, exact-timestamp correlation) so tiered PostgreSQL/DuckDB cursors close deterministically on both hit and miss.
   - Always bound routine ConSys observation lookups by narrow time windows (`phenomenonTime` on `/sensorhub/api/observations`, or `resultTime` when calling `osh-js` `DataStream.searchObservations`, which strips `phenomenonTime`).
3. **Zero Per-Tick SWE `DataComponent.copy()` Tree Cloning on `>= 1 Hz` Drivers:**
   - Initialize a reusable `liveDataStruct = dataStruct.copy()` once in `init()`, reuse `DataBlock` / `liveDataStruct` across 1 Hz frames without mutating the canonical `getRecordDescription()` schema, and never hold coarse module locks shared with `doStop()` across blocking TCP/serial `tryConnect()` calls.
4. **EventBus & Async Submodule Hygiene:**
   - Store and cancel every `EventBus` `Subscription` in `doStop()` (never leave wildcard `ModuleRegistry.EVENT_GROUP_ID` listeners open), and use `OccupancyProcessStarter` on the parent system's `ExecutorService` so `initAsync = true` modules (`INITIALIZING -> INITIALIZED`) never block the EventBus thread.
5. **Canonical Operator Routes & Regression Selector Stability:**
   - Preserve all 8 canonical Viewer routes (`/`, `/map`, `/event-log`, `/lane-view`, `/report-view`, `/health`, `/servers`, `/users`), `scopedHref` `?view=<scope>` propagation, and `data-testid` attributes verified by `ORNL/oscar-regression` and `ORNL/oscar-video-guides`. New workspaces (such as `v3.12.0` `/dashboards`) must be **opt-in and additive**.
6. **Safety-Critical Global `AlarmAudio` Singleton:**
   - `AlarmAudio` must remain mounted once inside `web/oscar-viewer/src/app/Providers.tsx` so audible Gamma and Neutron radiation alarms sound on every route without duplicate per-widget audio instances.
7. **4-Locale Parity (`en`, `es`, `fr`, `el`) & Release Metadata Lockstep:**
   - Maintain 4-locale parity across Viewer catalogs (`npm run validate:locales`), SensorHub Admin `ConfigMessages*.properties` and `README{,_es,_fr,_el}.md` (`:sensorhub-webui-oscar:test`), and release metadata (`node tools/validate-release-metadata.js`).
8. **Strict Repository Sanitization:**
   - Never commit private RFC1918 lab IP addresses, internal `.local` / lab hostnames, credentials, `.DS_Store`, or non-redistributable vendor/EML binaries (`tools/validate-packaged-release.js`).

---

## 4. Quick Local Verification Commands

```bash
# 1. Validate release & localized operator manual metadata
node tools/validate-release-metadata.js

# 2. Run self-contained Java module & security unit tests
./gradlew --no-parallel \
  :sensorhub-service-oscar:test \
  :sensorhub-webui-oscar:test \
  :sensorhub-service-bucket:test \
  :sensorhub-service-dailyfile-journal:test \
  :sensorhub-system-lane:test \
  :sensorhub-security-basic-session:test \
  :sensorhub-driver-aspect:test \
  :sensorhub-driver-rs350:test \
  :sensorhub-driver-kromek-d3s:test \
  :sensorhub-driver-kromek-d5:test \
  :sensorhub-driver-rapiscan:test

# 3. Validate OSCAR Viewer locales, TypeScript, production bundle, and Cypress component suite
(cd web/oscar-viewer && npm run validate:locales && npm run lint && npm run build && npm run test:component)
```
