---
name: oscar-v312-feature-blueprints
description: >-
  Implementation blueprint and pre-merge checklist for OSCAR v3.12.0 planned
  features: Mobile Detector System (RS-350 backpack & Kromek D5 walker across
  osh-oakridge-modules#57, oscar-viewer#49, oscar#76) and Opt-In Custom Widget
  Dashboards (/dashboards in oscar-viewer#50). Activate when developing,
  rebasing, or reviewing v3.12.0 feature branches.
---

# OSCAR `v3.12.0` Feature Blueprints

Use this skill when developing, rebasing, or reviewing the planned `v3.12.0` feature branches tracked in [`docs/ARCHITECTURAL_ROADMAP.md`](../../../docs/ARCHITECTURAL_ROADMAP.md) and [GitHub Milestones `#2`–`#5`](https://github.com/ORNL/oscar/milestones).

## Shared Branch Collaboration Rules
1. Collaborate directly on `ORNL/*` branches (`Write` branch-maintainer access is enabled for the review group; default branches and `v*` tags require Repository Admin merge after 50-lane certification, including an unfiltered `./scripts/run-regression.sh full` `PASS`).
2. Use **matching branch names** across coordinated repositories so `.github/workflows/ci.yml` resolves the matching `ORNL/oscar` branch automatically:
   - Mobile Detector System (`#80`): `feat/v3.12.0-mobile-detector-system`
   - Opt-In Custom Widget Dashboards (`#81`): `feat/v3.12.0-custom-dashboards` (keep unstacked from `feat/v3.12.0-mobile-detector-system`)
   - Multi-Year Cold Parquet CQL Count Cache (`#84` / `osh-addons#21`): `feat/v3.12.0-parquet-cql-count-cache`

## Blueprint A — Mobile Detector System ([`ORNL/oscar#80`](https://github.com/ORNL/oscar/issues/80))
1. **Rebase cleanly onto `v3.11.15`+ `main`** across `osh-oakridge-modules`, `oscar-viewer`, and `oscar`, dropping already-merged `v3.11.15` bugfix commits and preserving hardened `HLSVideoComponent.tsx`, `useLaneHealth.ts`, and `WebIdAnalysis.tsx`.
2. **Backend (`sensorhub-system-mobile`, `ORNL/osh-oakridge-modules#57`):**
   - Reuse `OccupancyProcessStarter` (including `initAsync = true` `INITIALIZING -> INITIALIZED` support) and `RpmRecoverySupervisor`.
   - Scope camera/HLS capability tracking to the `MobileDetectorSystem` instance (`doStop()` cleanup; no static global `ConcurrentHashMap`).
   - Verify mobile datastreams in `OscarTieredObsStore`, `DatabasePurger`, and `dist/config/standard/config.json` so 1 Hz GPS (`LiveDriverLocationOutput`) and spectra never bloat `ONLY oscar.obs`.
   - Add JUnit tests under `sensors/sensorhub-system-mobile/src/test/java` and wire `:sensorhub-system-mobile:test` into `.github/workflows/ci.yml`.
3. **Viewer (`ORNL/oscar-viewer#49`) & Root (`ORNL/oscar#76`):**
   - Route mobile radiation alarms through the single global `AlarmAudio` in `Providers.tsx`.
   - Bound GPS trail queries with explicit `resultTime` / `phenomenonTime` windows + `limit` (`<= 500`), manage live feeds via `SharedConnectionPool`, keep dev simulators excluded from `build/install/oscar` (`tools/validate-packaged-release.js`), and complete `en`/`es`/`fr`/`el` locale keys + Cypress component tests.

## Blueprint B — Opt-In Custom Widget Dashboards ([`ORNL/oscar#81`](https://github.com/ORNL/oscar/issues/81))
1. **Rebase directly onto `v3.11.15`+ `main`** in `ORNL/oscar-viewer` (`feat/v3.12.0-custom-dashboards`).
2. **Additive Opt-In Route (`/dashboards`):**
   - Keep all 8 canonical routes (`/`, `/map`, `/event-log`, `/lane-view`, `/report-view`, `/health`, `/servers`, `/users`) untouched as the default operator experience (`/` remains the canonical Dashboard).
   - Add `/dashboards` as an opt-in workspace in `Navbar.tsx` wrapped in `scopedHref("/dashboards", activeView)`.
3. **Safety & 50-Lane Resource Caps:**
   - Never remove `<AlarmAudio />` from `src/app/Providers.tsx` or mount `<AlarmAudio />` inside widgets.
   - Enforce per-dashboard widget caps (`<= 4` simultaneous live-video widgets, `<= 6` simultaneous live-chart widgets), replace `AlarmStatsRegistry` historical `searchObservations` / `1,440`-count polling with summarized server-side or bounded hot-state metrics (`0` periodic DuckDB cold scans), use `SharedConnectionPool` with clean teardown, honor `?view=<scope>` lane filtering, version `redux-persist` state, remove `.DS_Store`, and pass `npm run validate:locales` + Cypress component specs.

## Blueprint C — Multi-Year Cold Parquet CQL Count & Vehicle Search Scale ([`ORNL/oscar#84`](https://github.com/ORNL/oscar/issues/84), [`ORNL/osh-addons#21`](https://github.com/ORNL/osh-addons/issues/21), [`ORNL/osh-oakridge-modules#63`](https://github.com/ORNL/osh-oakridge-modules/issues/63))
1. **Overlay-Fingerprinted Per-Generation Count Cache (`ORNL/osh-addons` — `ParquetArchiveReader.java`):**
   - Extend `CqlGenerationCountKey` to include a compact deterministic digest of `genExcludedIds` (`(generation.sha256, normalizedDatastreamIds, cqlAstDigest, phenomenonWindow, resultCutoffBucket, genExcludedIdsDigest)`) rather than bypassing `unmutatedCqlCounts` whenever a 30-minute Parquet generation has `Code 9999` EML or operator overlays.
2. **Summary Upper-Bound Pruning (`oscar_archive_generation_summary`):**
   - Persist compact numeric upper bounds (`max_gamma_max`, `max_neutron_max`, `max_occupancy_duration_ms`) so cold cache misses prune non-matching generations in memory before opening DuckDB.
3. **Per-Stream `VehicleIncidentAggregator` Cache Watermarks & `PROFILE_LOAD_PARALLELISM <= 2` (`ORNL/osh-oakridge-modules`):**
   - Key `OcrSearchCacheSlot` and `AdjudicationSearchCacheSlot` per `db` with per-stream watermarks (`Map<String, Instant>`), avoid synchronous multi-month `slot.clear()` rescans inside HTTP request threads, and cap `PROFILE_LOAD_PARALLELISM` to `<= 2`.
4. **Viewer Count Abort & Coalescing (`ORNL/oscar-viewer`):**
   - Abort superseded `/observations/count` `AbortController` requests on rapid filter/sort toggles (`<= 50 ms` warm unsummarized count, `0` DuckDB sessions, `0` `cold-cql-count` timeouts under unfiltered `full` regression).
