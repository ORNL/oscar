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
   - **CQL <-> Summary Counter Lockstep (`StatisticsOutput` / `ReportDataAggregator`):** Every CQL predicate queried over high-volume telemetry (`gammaCounts`, `neutronCounts`, `occupancyStatus`, `alarm`) must resolve to an exact `JsonCqlEvaluator.SummaryCounterSpec` backed by `oscar_archive_schema` (`26` counters) and `ArchiveCompactionManager.StreamStatsAccumulator`, locked by `TestArchiveLifecycleInvariants.statisticsAndReportCqlQueriesMapToExactSummaryCountersAndV2Masks`. Any newly added nullable summary column must use `COALESCE(s.<col>, COALESCE(s.row_count, 0))` for `upperBoundExpr` (preventing false zero-match pruning before backfill), guard `exactReadyExpr` with `IS NOT NULL`, zero-fill ineligible streams via `oscar_archive_schema_blob` subqueries, backfill eligible files via background DuckDB `read_parquet(..., filename=true, union_by_name=true)` registered in `DuckDbResourcePolicy.AdmissionController.isBackgroundCountOperation`, and version new `base_summary_mask` bits behind `JsonCqlEvaluator.BIT_MASK_V2`.
   - **Split-at-Export, 10-Year Catalog Pruning & Bounded DuckDB Writes:** Route only the 9 searchable event/summary streams to `RAW_EVENTS` / `DAILY_EVENTS` / `MONTHLY_EVENTS` (never compact high-rate `RAW_TELEMETRY`, and keep `ocr_bloom = NULL` on `RAW_TELEMETRY`). Always keep `s.generation_id = ANY (?::uuid[])` chunked at `2,048` UUIDs in `ArchiveCatalog` summary queries (never omit `generation_id` filtering when `candidates.size() > 64`), prune pure event-stream queries via `EVENT_QUERY_PROFILES` (`oscar_archive_generation_time_idx`), slice plain unfiltered `?limit=N` queries by `row_count`, and keep `oscar_archive_schema` nightly reindex bloat-gated (`< 256 MiB` OR `>= 50,000` dead tuples OR `>= 10%` dead ratio). Always use `DuckDbResourcePolicy.openFileBacked(...)` + native `DuckDBAppender` for large writes, `union_by_name=true` for multi-generation reads, and `ArchiveExporter.stageToLocalDirectory` (16 KiB bounded reads) whenever `ParquetArchiveReader.isPathOn9pMount(...)` is true on Windows 11 + WSL 2 `9p` mounts so DuckDB never hits `ENOMEM`.
   - **Graceful Durable-Publish Teardown (`SlidingOccupancyQuery`):** Never call `shutdownNow()` while a retention worker is inside NIO `FileChannel.lock()`/`force()` durable media publication; signal `stopRequested = true` + `stopping.shutdown()` during `inDurableAction` and wait a bounded grace window in `awaitStop(...)` before forcing interruption.
2. **DuckDB `2`-Session Cap, Mandatory `try-with-resources` Stream Closure & Time-Bounded ConSys Queries:**
   - Never trigger background timers or per-lane `searchObservations` fan-out that scan cold Parquet generations.
   - Always wrap every Java `IObsStore.select(...)`, `selectKeys(...)`, and `selectEntries(...)` (plus `ISystemDescStore.select*`) stream in `try-with-resources`, and pass `.withLimit(1)` on single-record `ObsFilter.Builder` lookups (`findFirst()`, `withLatestResult()`, exact-timestamp correlation).
   - Note that `osh-js` `DataStream.searchObservations(filter, pageSize)` strips `phenomenonTime` (`toQueryString([], ['phenomenonTime'])`); always bound `DataStream.searchObservations` calls using `resultTime: "<startIso>/<endIso>"` alongside any CQL `filter` (see `web/oscar-viewer/src/app/_components/adjudication/WebIdAnalysis.tsx`).
3. **`1 Hz+` Driver Allocation & Non-Blocking Teardown:**
   - Initialize `liveDataStruct = dataStruct.copy()` once in `init()` rather than calling `dataStruct.copy()` every second; keep `getRecordDescription()` pristine and assign `latestRecord = dataBlock`.
   - Never hold a lock shared with `doStop()` across blocking TCP/serial `tryConnect()` calls.
   - Store and cancel all `EventBus` `Subscription` handles in `doStop()`, and start `initAsync = true` (`INITIALIZING -> INITIALIZED`) occupancy modules off the EventBus thread via `OccupancyProcessStarter`.

## Step 3 — Verify Viewer Safety, Routes & Localization
1. Keep all 8 canonical routes (`/`, `/map/`, `/event-log/`, `/lane-view/`, `/report/`, `/health/`, `/servers/`, `/users/`) and `data-testid` attributes intact; propagate `?view=<scope>` and trailing slashes (`trailingSlash: true`) via `scopedHref` / `ensureTrailingSlashRoute` so Next.js static RSC navigation (`<route>/index.txt`) never triggers MPA document reloads.
2. Keep `<AlarmAudio />` mounted once in `web/oscar-viewer/src/app/Providers.tsx` (never per-widget).
3. Maintain 4-locale parity (`en`, `es`, `fr`, `el`) across `ConfigMessages*.properties`, `README{,_es,_fr,_el}.md`, and `web/oscar-viewer/src/locales/*.json`.
4. Never list raw Redux `laneMap` (`selectLaneMap`) directly in the dependency array of a React `useEffect` that issues HTTP `fetch` / ConSys / `vehicle-search` requests; on 50-lane portals `laneMap` is cloned dozens of times during datastream/schema hydration, causing `HTTP 499` abort storms and cold-archive permit contention. Store `laneMap` in a `useRef` (`laneMapRef.current = laneMap`) and depend on a memoized scalar topology or stream-ID key instead.
5. Never add unbounded full-table `UPDATE oscar_archive_schema` or multi-generation DuckDB scans synchronously inside `ArchiveCatalog.migrate()` or `OscarTieredObsStore` startup (`ModuleRegistry.loadAllModules` enforces a hard `60 s` datastore startup timeout); gate inline backfills to `<= 64` generations and drain larger upgrades newest-first in bounded committed batches on `oscar-base-summary-backfill` (`backfillPendingSchemaUpgradeColumnsBatch`).
6. Scrub all private RFC1918 IPs, internal `.local` hostnames, `.DS_Store`, and credentials.

## Step 4 — Run Mandatory Local Checks & Full Release Regression Gate
```bash
node tools/validate-release-metadata.js
./gradlew --no-parallel :sensorhub-service-oscar:test :sensorhub-webui-oscar:test :sensorhub-system-lane:test :sensorhub-security-basic-session:test :sensorhub-driver-rs350:test
(cd web/oscar-viewer && npm run validate:locales && npm run lint && npm run build && npm run test:component)
```

- **Mandatory Release Sign-Off Gate (`ORNL/oscar-regression`):** Never certify an `ORNL/oscar` `v3.x.y` release using `smoke` or `--scenario` subsets alone. Every release sign-off requires an **unfiltered `./scripts/run-regression.sh full` `PASS` (`0` incorrect checks)** on the 50-lane Ubuntu 24.04 LTS certification portal plus Windows 11 + WSL 2 upgrade and multi-host soak verification.
