---
name: oscar-contributor-scale-guardrails
description: >-
  Enforce OSCAR's 50-lane storage, DuckDB concurrency, 1 Hz driver allocation,
  EventBus lifecycle, global AlarmAudio, canonical Viewer route, localization,
  and sanitization guardrails before writing or reviewing code across ORNL/oscar
  and its submodules. Activate whenever modifying Java modules, drivers, SQL/CQL
  queries, or Next.js Viewer components.
---

# OSCAR Contributor 50-Lane Scale & Safety Guardrails

Use this skill before proposing, implementing, or reviewing changes in [`ORNL/oscar`](https://github.com/ORNL/oscar), [`ORNL/osh-core`](https://github.com/ORNL/osh-core), [`ORNL/osh-addons`](https://github.com/ORNL/osh-addons), [`ORNL/osh-oakridge-modules`](https://github.com/ORNL/osh-oakridge-modules), or [`ORNL/oscar-viewer`](https://github.com/ORNL/oscar-viewer).

## Step 1 — Check Architectural Context First
1. Read [`AGENTS.md`](../../../AGENTS.md) and [`docs/ARCHITECTURAL_ROADMAP.md`](../../../docs/ARCHITECTURAL_ROADMAP.md).
2. If editing `include/osh-oakridge-modules` or `web/oscar-viewer`, also read the submodule's `AGENTS.md`.

## Step 2 — Verify Storage, Query & Concurrency Invariants
1. **`PARQUET_PRIMARY` Hot/Cold Routing:**
   - Never persist unbounded `>= 1 Hz` telemetry (`gammaCounts`, `neutronCounts`, `LiveDriverLocationOutput`, RS-350/D5 `ForegroundOutput` / `BackgroundOutput`, `connectionStatus`) permanently in `ONLY oscar.obs`.
   - If adding a new datastream, verify `OscarTieredObsStore` (`osh-addons`), `DatabasePurger` (`osh-oakridge-modules`), and `dist/config/standard/config.json` (`archive.outputNames`, if cold-archived) in lockstep.
   - Never add growing B-tree/GIN SQL indexes or raw `?` JSONB operators in JDBC `PreparedStatement` queries (`use jsonb_typeof(col->'key')`).
2. **DuckDB `2`-Session Cap, Mandatory `try-with-resources` Stream Closure & Time-Bounded ConSys Queries:**
   - Never trigger background timers or per-lane `searchObservations` fan-out that scan cold Parquet generations.
   - Always wrap every Java `IObsStore.select(...)`, `selectKeys(...)`, and `selectEntries(...)` (plus `ISystemDescStore.select*`) stream in `try-with-resources`, and pass `.withLimit(1)` on single-record `ObsFilter.Builder` lookups (`findFirst()`, `withLatestResult()`, exact-timestamp correlation).
   - Note that `osh-js` `DataStream.searchObservations(filter, pageSize)` strips `phenomenonTime` (`toQueryString([], ['phenomenonTime'])`); always bound `DataStream.searchObservations` calls using `resultTime: "<startIso>/<endIso>"` alongside any CQL `filter` (see `web/oscar-viewer/src/app/_components/adjudication/WebIdAnalysis.tsx`).
3. **`1 Hz+` Driver Allocation & Non-Blocking Teardown:**
   - Initialize `liveDataStruct = dataStruct.copy()` once in `init()` rather than calling `dataStruct.copy()` every second; keep `getRecordDescription()` pristine and assign `latestRecord = dataBlock`.
   - Never hold a lock shared with `doStop()` across blocking TCP/serial `tryConnect()` calls.
   - Store and cancel all `EventBus` `Subscription` handles in `doStop()`, and start `initAsync = true` (`INITIALIZING -> INITIALIZED`) occupancy modules off the EventBus thread via `OccupancyProcessStarter`.

## Step 3 — Verify Viewer Safety, Routes & Localization
1. Keep all 8 canonical routes (`/`, `/map`, `/event-log`, `/lane-view`, `/report-view`, `/health`, `/servers`, `/users`) and `data-testid` attributes intact; propagate `?view=<scope>` via `scopedHref`.
2. Keep `<AlarmAudio />` mounted once in `web/oscar-viewer/src/app/Providers.tsx` (never per-widget).
3. Maintain 4-locale parity (`en`, `es`, `fr`, `el`) across `ConfigMessages*.properties`, `README{,_es,_fr,_el}.md`, and `web/oscar-viewer/src/locales/*.json`.
4. Scrub all private RFC1918 IPs, internal `.local` hostnames, `.DS_Store`, and credentials.

## Step 4 — Run Mandatory Local Checks & Full Release Regression Gate
```bash
node tools/validate-release-metadata.js
./gradlew --no-parallel :sensorhub-service-oscar:test :sensorhub-webui-oscar:test :sensorhub-system-lane:test :sensorhub-security-basic-session:test :sensorhub-driver-rs350:test
(cd web/oscar-viewer && npm run validate:locales && npm run lint && npm run build && npm run test:component)
```

- **Mandatory Release Sign-Off Gate (`ORNL/oscar-regression`):** Never certify an `ORNL/oscar` `v3.x.y` release using `smoke` or `--scenario` subsets alone. Every release sign-off requires an **unfiltered `./scripts/run-regression.sh full` `PASS` (`0` incorrect checks)** on the 50-lane Ubuntu 24.04 LTS certification portal plus Windows 11 + WSL 2 upgrade and multi-host soak verification.
