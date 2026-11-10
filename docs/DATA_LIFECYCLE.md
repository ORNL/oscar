# OSCAR 3.11.0 data lifecycle and retention policy

This document defines when OSCAR data changes form, when it may be removed, and which safety gates
apply. It complements the [storage architecture](STORAGE_ARCHITECTURE.md) and the operational
procedures in [Storage operations](STORAGE_OPERATIONS.md).

This policy applies to the supported Ubuntu Server 24.04 x86-64 and Windows 11 x86-64 deployment
hosts. macOS deployment and storage operations fail closed; it is not a supported storage host.

> **Companion Video Guides:** Watch [Module 03 — Verify Parquet Cold Archive & Single-Snapshot Backup (`03-archive-and-snapshot-backup.mp4`)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/03-archive-and-snapshot-backup.mp4) and [Module 04 — Configure OSCAR Service, Retention & Custom Disposition Codes (`04-admin-oscar-service-and-custom-codes.mp4`)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/04-admin-oscar-service-and-custom-codes.mp4) in [VIDEO_GUIDES.md](VIDEO_GUIDES.md).

## Policy summary

| Data class | Default transition | Removal gate | Removed automatically? |
| --- | --- | --- | --- |
| Operational, evidentiary, status, report & EML observations (21 outputs) | Commit first to a LOGGED UTC-aligned 30-minute PostgreSQL staging child (`osg_*`); make the closed window Parquet-eligible after five minutes and run the worker every minute (plus startup route reconciliation, retroactive migration of unarchived parent-table rows, and `VACUUM (FULL, ANALYZE) ONLY obs` compaction) | Valid Parquet/schema/manifest objects, active catalog generation, object checksum, exact row/UUID parity, and populated `oscar_obs_latest`, `oscar_archive_schema` summary counters, and `oscar_event_locator` | Yes; detach and drop the complete child transactionally (`NO INHERIT` + `DROP TABLE`), at most eight per cycle. Mutations to archived `occupancy` rows (when adjudicated) are recorded in `oscar_obs_overlay` and synchronized with `oscar_obs_latest` |
| Static singleton configuration observations (`sensorLocation`, `adjudicationCodes`, `siteInfo`) | Remain hot in the parent `ONLY oscar.obs` table (`immutable=false`, ~52 rows total across 50 lanes); prior `adjudicationCodes` rows are deduplicated on startup | Existing application policy and active `oscar_retention_hold` checks | No; never moved to stage partitions |
| Transient operational health & compatibility observations (`connectionStatus`, `occupancyStatus`, `dailyFile`) | Routed through 30-minute `osg_*` `PARQUET_PRIMARY` stage partitions into ZSTD Parquet with latest state cached in `oscar_obs_latest` (or pruned hourly from `ONLY oscar.obs` when `PARQUET_PRIMARY` is disabled); background camera `connectionStatus` heartbeats coalesced to 15-minute intervals while state transitions publish immediately | In `PARQUET_PRIMARY`: verified Parquet export + whole-partition drop (`DatabasePurger` skips row-wise `DELETE`s so no `oscar_tombstone` rows are created); in non-`PARQUET_PRIMARY`: > 1h old keeping latest per stream / verified daily CSV + SHA-256 manifest | Yes; retired via `O(1)` `NO INHERIT` + `DROP TABLE` in `PARQUET_PRIMARY` |
| Transient operational vs. audit commands (`cmd` & `commandstatus`) | Stored in PostgreSQL command tables | Completed non-`adjudicationControl` commands (`fileControl`, `hlsControl`, etc.) > 24h old; `adjudicationControl` streams excluded and protected by immutability triggers | Yes for completed non-`adjudicationControl` commands > 24h old (with automatic `VACUUM (FULL, ANALYZE)` reclamation); No for `adjudicationControl` audit commands (retained permanently) |
| Raw RPM daily-file source & daily setup parameter sync (`SG1`–`SG3`, `SN1`–`SN2`) | Append immediately; publish prior day after rollover; Rapiscan daily setup records (`SG1`–`SG3` and `SN1`–`SN2`) update live `RapiscanConfig` parameters in memory and coalesce changes into `config.json` via `RapiscanConfigSaver` | Valid immutable CSV, v1 manifest, `PUBLISHED` ledger, 30 days after the later of day close or actual publication, and exact sealed-journal replay parity; sites may additionally require verified backup confirmation | Yes for eligible private sealed segments; published daily files and `config.json` are not pressure-cleanup candidates |
| Alarm source MP4 | Immediately eligible for an asynchronous attempt to publish exactly five JPEGs | Exactly five verified JPEGs and manifest, then 24-hour rollback grace and no hold | Yes, on a later successful retention pass |
| Secondary retained JPEGs (`FIRST`, `QUARTER`, `THREE_QUARTERS`, `LAST`) | Pruned to the `MIDDLE` (`frame-03.jpg`) representative frame after `secondaryFrameRetentionDays` (30 by default) | Source MP4 already deleted (`SOURCE_DELETED`), no active manifest hold, and `frame-03.jpg` re-verified against its SHA-256 and byte count | Yes, on a later media-maintenance pass (`secondaryFrameRetentionDays > 0`) |
| Retained JPEG media set | Remains available (`5` JPEGs before secondary pruning, `MIDDLE` JPEG afterward) | Complete published manifest, no hold, rollback grace elapsed, minimum pressure age met, filesystem at pressure threshold | Yes, only under configured storage pressure |
| Uncatalogued legacy video | Legacy behavior only | Not eligible for new pressure cleanup | No |
| Daily files, reports, adjudication, sitemap | Remain in application state | Site policy and explicit administration | No by storage-pressure cleanup |
| Cold archive generation | Primary cold tier; `ACTIVE` during verified stage retirement, then `SEALED` after the complete stage child is gone | Explicit dry-run plan selecting only `SEALED` generations, review, unexpired one-time token, no hold, object hash recheck | No; an administrator must run `archive purge` |
| Docker logs | JSON log rotation | Docker rotation settings | Yes, size-based rotation |
| Coordinated recovery snapshot | Disabled by default; manual `single` mode commits one schema-v2 snapshot through authenticated `CURRENT` | Full HMAC/checksum/tar/`pg_verifybackup` verification and journal confirmation before pointer replacement | A prior non-current snapshot is cleaned only after the new pointer commits and the candidate independently passes full schema-v2 acceptance; all other candidates are preserved; `backup-prune` is retired |

Defaults are starting points, not universal retention policy. The site owner must set periods that
meet regulatory, evidentiary, privacy, legal-hold, and capacity requirements.

## Observation lifecycle

### 1. Hot ingestion

An accepted observation receives a sequential OSH internal ID. Its mutable result block is
serialized immediately, then queued for a bounded prepared-statement batch. The standard profile
flushes every second or at 10,000 observations. Until a successful flush, the observation is
not durable in PostgreSQL; a failed batch remains queued for a later commit attempt.

PostgreSQL remains authoritative for systems, datastream metadata, event records, occupancy/alarm
workflows, adjudications, reports, archive control state, and observations not selected for the
primary cold tier. For allowlisted immutable outputs, a successful commit to a LOGGED PostgreSQL
child is the durable staging boundary; OSCAR does not acknowledge those observations through a direct-to-Parquet path.
Parquet is the primary cold tier, not a backup, and only output names listed in
`archive.outputNames` are eligible for cold tiering. The 3.11.0 default list is:

```text
gammaCounts
gammaThreshold
neutronCounts
setupGamma
setupNeutron
speed
backgroundReport
foregroundReport
status
emlContextual
emlScanContextual
emlAnalysis
dailyFile
connectionStatus
occupancyStatus
tamper
occupancy
adjudication
report
siteStatistics
nationalSummary
```

Only static singleton configuration streams (`sensorLocation`, `adjudicationCodes`, and `siteInfo`, ~52 rows total across a 50-lane deployment) remain permanently in `ONLY oscar.obs`. After verified stage retirement, Parquet and the independently published daily files are the durable long-term representations of all 21 operational and evidentiary streams, while PostgreSQL retains `oscar_obs_latest` (one row per datastream for `< 0.5 ms` `resultTime=latest` / `phenomenonTime=latest` lookups), `oscar_archive_schema` (22 per-generation, per-datastream summary counters for `< 1 ms` SQL alarm/fault/adjudication counts and zero-match generation pruning), `oscar_event_locator` (`event_id` index), and `oscar_obs_overlay` (for adjudicated or re-adjudicated archived occupancies).

### 2. Non-disruptive archive export

The shipping `PARQUET_PRIMARY` worker runs at `parquetPrimaryIntervalMinutes` (one by default).
Allowlisted rows route into LOGGED children covering `immutableStageWindowMinutes` (30) of
UTC-aligned phenomenon time. A window becomes eligible only after
`parquetPrimaryArchiveDelayMinutes` (five) from close. PostgreSQL's transaction clock is the receipt
clock; a detector timestamp more than `maximumFuturePhenomenonSkewMinutes` (five) ahead is rejected
so a bad device clock cannot pin future staging indefinitely. This lookup includes accepted late
arrivals and is not based only on the last completed generation. A cycle starts at most
`maximumGenerationsPerCycle` (two), checks at most two unverified generations, retires at most
`maximumStagePartitionsPerCycle` (eight) complete stage children, and stops starting new
generations after `maximumCycleMinutes` (15); in-progress publication is allowed to complete safely.

The worker is independent of the ingestion thread: it runs once immediately at module startup and
then at the dedicated primary interval. New observations are committed to PostgreSQL staging first
and are not individually converted to Parquet. The worker selects a half-open 30-minute UTC window
`[start, end)`. It uses a PostgreSQL read-only
`REPEATABLE READ` snapshot and a 5,000-row fetch size while flushing explicitly cleared 500-row
inserts into embedded DuckDB. Live inserts continue. Rows are ordered by `(phenomenontime, id)` and
the exporter publishes the largest deterministic prefix permitted by the configured row cap and
the effective byte cap. The effective byte cap is the lower of the operator setting and one eighth
of DuckDB session memory—32 MiB with the standard 256 MiB session—leaving room for table pages,
sort keys, compression, and Parquet buffers. Remaining unowned rows become normal same-window job
revisions, so a restart resumes safely without tiny time slices or duplicate ownership. A single
row larger than the effective cap fails closed and remains hot for operator action.

On upgrade, the worker first reclaims the exact window of any latest-revision `FAILED` job or
two-hour-stale `EXPORTING` job that is wholly older than the cutoff. This includes sub-hour windows
created by the former time-bisection scheduler, preventing a successful replacement full-hour
archive from leaving an obsolete failed job in health reports.
If such a reclaimed window no longer has any eligible unowned rows, its attempt becomes
`SUPERSEDED` with an audit detail instead of remaining `FAILED`; later windows can continue.

The exporter and every other archive-side DuckDB operation use the configured memory, thread, and
temporary-space caps. Larger sorts or joins spill only into an operation-private directory, which
is removed after its connection closes. A fair process-wide gate admits no more than two sessions
by default; a waiter fails busy after 30 seconds before opening DuckDB or allocating scratch.
Exhausting admission, memory, or spill fails the operation without activating a generation or
dropping a stage child.

Publication order is:

1. Write and verify `generation-<uuid>.parquet`.
2. Write `generation-<uuid>.schemas.json.gz` from the same database snapshot.
3. Write `generation-<uuid>.manifest.json` last.
4. In one PostgreSQL transaction, write exact still-unowned IDs into the compact staging-owner
   ledger, require the count and UUID set to match the manifest, insert generation/object/schema
   catalog records, and move the job to `ACTIVE`.

The expensive snapshot read and Parquet/schema/manifest work occurs before the activation critical
section. Activation then takes an exclusive transaction-scoped advisory lock for that exact
store/scope and rechecks every exported row predicate while assigning ownership. Observation
inserts, updates, removals, overlays, tombstones, and lifecycle stage retirement take the shared
form of the store lock plus per-observation locks in ascending ID order. This fixed ordering prevents
an activation from racing a logical mutation without holding live ingestion behind file encoding.

If any step fails, partial objects are removed where possible, the job becomes `FAILED`, and the
LOGGED stage child remains. A failed or stale export job can be retried. A generation is not query-visible until
catalog activation succeeds.

### 3. Mixed-tier reads and mutations

During the brief verified transition, the same logical observation can exist in PostgreSQL and Parquet.
Queries read both eligible tiers, de-duplicate by OSH ID, and prefer the staged PostgreSQL copy. Time,
datastream, feature-of-interest, internal-ID, ordering, latest-value, limit, CQL, and value filters
are applied without changing public IDs.

Parquet is immutable. An update to an already archived observation is written to
`oscar_obs_overlay`; a removal writes an `oscar_tombstone`. Reads apply the overlay or hide the
tombstoned row. This avoids rewriting a large generation for a one-row change. These mutation
tables must therefore be protected and backed up with PostgreSQL.

Logical removal participates in the retention protocol. After the shared store and ordered
observation mutation locks are held, the same PostgreSQL transaction takes a shared lock on the
hold table and resolves exact observation holds plus generation holds for only the requested IDs'
candidate archive ranges. A single held removal fails visibly. A filtered bulk removal skips held
rows, removes other matching rows, and reports only successful removals. A hold created in the
former select/delete race window therefore commits before the shared lock and is observed, or
waits until the removal commits; it cannot be silently bypassed by a hot delete or tombstone.

Observation ingestion uses the same logical identity as the OSH reference store: datastream,
feature of interest, phenomenon time, and result time. Replaying the same value is idempotent; a
different value at that identity is a last-write-wins correction that keeps the original public
observation ID. During the verified staging transition the immutable parity row is left unchanged and the
correction is written transactionally to its generation-owned overlay. After stage retirement, a
bounded cold lookup resolves that same stable ID and still writes only the overlay, so a replay
cannot create a second hot observation beside the archived row.

The sequential allocator initializes from both the hot observation table and the maximum cataloged
archive ID for the exact store/scope. Catalog generations remain durable through sealing and purge,
so a restart cannot reuse a public OSH observation ID merely because its stage child was dropped.

### 4. Parity and whole-partition retirement

The lifecycle worker checks unverified active generations. It re-hashes the Parquet object, reads
its rows in ID order, loads the exact hot IDs in bounded batches, and compares canonical row
digests. The receipt records expected/actual rows and success or failure. A failed receipt leaves
all hot data in place.

The shipped 3.11.0 profile sets `deleteHotAfterArchive=true`. In `PARQUET_PRIMARY`, this means
relation-level retirement rather than row-wise deletion or a rollback-grace overlap. Before a child
can retire, every row must have an `ACTIVE` or `SEALED` exact owner with a successful
`HOT_COLD_PARITY` receipt, and the worker re-hashes each authoritative Parquet object. Under the
archive activation lock and a short database lock timeout, it records the child as `DETACHED`,
executes `NO INHERIT`, drops the relation, removes the temporary owner/partition records, and seals
fully retired generations in one transactional sequence. A crash before commit leaves the attached
child intact; a committed detached state is reconciled and completed safely on restart.

Retention holds protect the verified Parquet generation from cold purge; they do not require a
second raw copy to remain in the transient stage. The `rollbackGraceDays`, `deleteBatchSize`, and
row-deletion settings remain compatibility controls for `HOT_RETENTION` and are not a 72-hour raw
PostgreSQL policy in `PARQUET_PRIMARY`.

With the standard 30-minute window, five-minute delay, one-minute cadence, and five-minute accepted
future skew, healthy observations normally leave staging well inside the enforced 60-minute nominal
budget. This is an operational SLO, not a hard durability deadline: archive corruption, parity
failure, resource admission, backlog, database lock contention, or downtime intentionally leaves
the LOGGED child in place until safe retirement succeeds.

### 5. Cold-generation deletion

OSCAR does not age cold archive objects out automatically. An administrator uses the two-step
deletion flow documented under [Delete old cold generations](STORAGE_OPERATIONS.md#delete-old-cold-generations):

1. `archive dry-run` freezes the current set of eligible `SEALED` generations before a UTC cutoff,
   computes estimated rows/bytes/holds, and emits a random confirmation token once. The plan
   expires after 24 hours.
2. `archive purge` accepts only the matching plan and token, briefly stops only a previously running
   OSCAR service, and preflights every relative path and SHA-256 through a networkless, read-only
   one-shot helper that sees only the archive mount. It always attempts to resume OSCAR's prior
   state and does not report that resume complete until OSCAR's top-level auto-start services are
   started and each RPM/camera member nested under a lane has completed its startup attempt. An
   unavailable device may settle offline while OSCAR remains usable to report that state. This
   application-readiness barrier prevents a following administrative command from
   stopping a partially initialized node. Purge rechecks holds under the same database lock used
   by hold creation. One transaction
   moves every selected generation and object to durable `DELETING` state, making the entire
   generation non-queryable before filesystem removal begins. It then revalidates and deletes each
   object through the helper with archive write access and records `DELETED` or the crash-recovery
   result `ALREADY_ABSENT`. If interrupted, the same confirmed plan/token resumes generations and
   objects already in `DELETING` rather than creating an unreviewed selection.

Generation and object catalog rows remain with `PURGED`/`DELETED` state, along with a generation
tombstone and deletion ledger. This retained metadata is the audit trail that distinguishes a policy
removal from an unexplained missing object. Once that state is committed, sparse observation overlays (`oscar_obs_overlay`), cached latest
pointers (`oscar_obs_latest`), event locators (`oscar_event_locator`), and observation tombstones
(`oscar_tombstone`) explicitly owned by the purged generation are deleted in the same final
transaction; they are no longer queryable and otherwise would grow forever. A legacy mutation
without exact generation ownership is preserved for reviewed migration rather than being guessed
from a possibly gapped/overlapping ID range. The generation tombstone, generation/object catalog,
and deletion ledger are preserved. Purged generations are no longer query candidates. Do not remove
archive files directly with Explorer, Finder, `rm`, or a storage-array lifecycle rule; that creates
integrity failures instead of an auditable deletion.

`archive export` instead makes an independent portable copy of selected `ACTIVE` or `SEALED`
generations. Its catalog, explicit object list, checksums, and bundled DuckDB query make that package
queryable outside OSCAR, but the export is not live OSCAR storage and is not a coordinated backup.

### 6. Startup route reconciliation, retroactive parent-table migration, and mutable operational pruning

When `OscarTieredObsSystemDatabase` starts in `PARQUET_PRIMARY` mode:

- **Route reconciliation (`reconcileRoutes`):** Existing `oscar_obs_storage_route` rows whose output name belongs to the 21 allowlisted `archive.outputNames` (`gammaCounts`, `gammaThreshold`, `neutronCounts`, `setupGamma`, `setupNeutron`, `speed`, `backgroundReport`, `foregroundReport`, `status`, `emlContextual`, `emlScanContextual`, `emlAnalysis`, `dailyFile`, `connectionStatus`, `occupancyStatus`, `tamper`, `occupancy`, `adjudication`, `report`, `siteStatistics`, `nationalSummary`) are automatically upgraded to `immutable=true` and the in-memory route cache is invalidated so subsequent writes route into 30-minute `osg_*` staging partitions.
- **Empty and retired stage cleanup (`reclaimEmptyOrRetiredStages`):** Empty expired `ATTACHED` stage partitions and any leftover `DETACHED` stage partitions are dropped cleanly on startup and during lifecycle maintenance.
- **Retroactive parent-table migration and compaction (`ArchiveLifecycleManager`):** If an upgraded or reconciled deployment contains historical unarchived rows (`archivegenerationid IS NULL`) in the parent `ONLY oscar.obs` table for datastreams now marked `immutable=true`, the archive exporter selects those windows, publishes verified ZSTD Parquet generations, populates `oscar_obs_latest`, `oscar_archive_schema` summary counters, and `oscar_event_locator`, removes the sealed rows from `ONLY oscar.obs` after parity verification, deduplicates singleton configuration streams (`sensorLocation`, `adjudicationCodes`, `siteInfo`), and runs `VACUUM (FULL, ANALYZE) ONLY obs` once drained.

For overlay-backed evidentiary mutations, non-`PARQUET_PRIMARY` compatibility streams, and command streams (`cmd_commands` / `cmd_status`), OSCAR enforces:

- **Overlay-backed append-only adjudication records (`occupancy`, `adjudication`):** Every adjudication submission (`AdjudicationControl`) is strictly **append-only**: it inserts a new `adjudication` observation and updates the target `occupancy` observation's `adjudicatedIds` array (appending the new command ID and replacing the `"code:<n>"` marker with the latest disposition code so re-adjudications remain mutually exclusive across CQL filters). When the target `occupancy` has already been archived into a cold Parquet generation, `OscarTieredObsStore.put()` writes the updated `occupancy` into `oscar_obs_overlay` and synchronizes `oscar_obs_latest` without rewriting the immutable Parquet file.
- **Coalesced camera heartbeats and `DatabasePurger` stage-retirement awareness:** `FFMPEGSensor` coalesces unchanged background camera `connectionStatus` heartbeats to 15-minute intervals while publishing state transitions immediately. When `PARQUET_PRIMARY` stage retirement is active, `DatabasePurger` skips row-wise observation deletes so zero `oscar_tombstone` rows are created (when `PARQUET_PRIMARY` is disabled, `DatabasePurger` purges expired `connectionStatus`, routine `Clear` `occupancyStatus`, and manifest-validated `dailyFile` rows from `ONLY oscar.obs` via `obs_mutable_datastream_phenomenon_idx`).
- **Hourly 24-hour transient command pruning (`DatabasePurger.purgeOldCommands`):** Every hour, `DatabasePurger` deletes completed transient operational commands (`fileControl`, `hlsControl`, `streamControl`, `videoControl`, `ptzControl`, `oscarServiceControl`) older than **24 hours** along with their cascading `cmd_status` rows (`PostgisCommandStoreImpl` + `PostgisCommandStatusStore`), while permanently preserving all `%adjudicate%` and audit command streams.

## Daily-file lifecycle

### Capture

Each configured lane opens a writer in the Daily File Journal service. The journal client defaults
to `enabled=true`, `required=true`, and a 10-second service startup timeout. Records are appended in
lane order before parsing can discard malformed Rapiscan/RS350 input; Aspect records are appended
after the register snapshot is rendered.

An `.open` segment is forced after any of these defaults:

- 1,000 milliseconds;
- 128 records; or
- 1 MiB of framed data.

It rotates at 64 MiB or 15 minutes. The active segment and ledger are also forced at orderly close.
The durability interval is a maximum exposure window to sudden power loss, not permission to lose
or skip input after an I/O error.

### Recovery and day rollover

Startup validates the journal root and metadata without synchronously re-rendering the complete
historical backlog. Before a lane accepts its first new append, its current open segment is scanned
and any incomplete final frame is truncated to the last CRC-valid boundary. A complete frame with
an invalid length, timestamp, or CRC is reported as corruption and prevents silent continuation.
Older completed days and interrupted deletions are recovered in a bounded 16-lane/day-per-minute
background pass. This pass also handles older days for actively receiving lanes without holding the
live writer lock while a large CSV is rendered. Already complete ledger/manifest/CSV publications
take a metadata fast path and are not regenerated on each restart.

Dates are assigned using the configured IANA `zoneId` (UTC in the standard profile). Each daily
window is permanently recorded as `[startInclusive, endExclusive)`, so daylight-saving boundaries
are unambiguous. Completed days are sealed and rendered in journal order to the legacy headerless
CSV syntax. The data file is forced and atomically renamed, followed by its
`.manifest.v1.json`; the ledger is marked `PUBLISHED` last.

The manifest contains the lane UID, zone, immutable time window, record count, byte count,
filename, publication time, and SHA-256. Existing output is accepted only if it matches the
recovered journal; a conflicting immutable CSV or manifest is not overwritten.

### Compatibility observation cleanup

`dailyFileObservationMode` controls only the legacy OSH compatibility stream:

- `FULL` publishes every compatibility observation and uses manifest-gated completed-day cleanup.
- `LATEST` is the production compatibility label; it publishes the same live events and uses the
  same safe completed-day cleanup. It does not discard rows from the unsealed current day merely to
  retain one value.
- `NONE` disables compatibility observations but does not disable the durable journal.

The 3.11.0 standard profile uses `LATEST`. The lane system consumes each live `dailyFile` event to
derive occupancy transitions, so `NONE` would disable a required operational input. `LATEST` keeps
that live stream and registered datastream. The compatibility table contains the current unsealed
local day plus any manifest-blocked backlog; the journal and immutable daily CSV are the
authoritative history. This mode does not eliminate the initial PostgreSQL/WAL write because OSH
currently couples live event delivery with observation persistence.

OSCAR's completed-day cleanup validates the corresponding journal ledger,
manifest, CSV, window, and current checksum before it authorizes daily-file compatibility cleanup.
The exact-midnight pass is only an initial bounded attempt. If publication for a lane is still in
progress, no row or checkpoint is changed; the same oldest-first catch-up runs on every hourly
maintenance pass and retries it. `dailyFilePurgeWorkLimit` bounds each midnight or hourly invocation
to 50 lane/day attempts in the standard profile, so a multi-day backlog converges over successive
hours without an unbounded maintenance pass. Failures in other hourly purge phases are isolated and
cannot suppress this retry.
Setting `delegateObservationLifecycleToDatabase=true` delegates high-volume detector retention to
the tiered database; it does not disable daily-file or connection-status maintenance.

For operator inspection in Event Details, `DailyFileTable` queries the hot ConSys `dailyFile`
stream first and falls back on demand to the authenticated, read-only
`GET /buckets/dailyfiles/dailyfile-slice` endpoint whenever completed-day compatibility rows have
already been purged or an occupancy straddles midnight across a purged prior day and the current
unsealed day. The slice handler binary-searches the immutable manifest-verified daily CSV (capped
at a 24-hour window, 1,000 items, 512 KiB UTF-8 JSON, and eight concurrent slice permits), resolves
timestamps exclusively from server-receipt trailing columns paired with the manifest's `[startInclusive, endExclusive)` window and `zoneId`, and applies a `±5 ms` boundary guard for IEEE-754 epoch-second rounding.

### Sealed-segment deletion gate

A published CSV is not by itself permission to remove the private sealed journal that produced it.
The standard `requireBackupBeforeSealedJournalDeletion=false` policy keeps managed backup optional
without allowing the private duplicate source to grow forever. After
`sealedJournalRetentionDays` (30 by default) from the later of day close or actual publication,
OSCAR validates the immutable CSV, manifest, and `PUBLISHED` ledger, freezes the candidate day, and
replays every sealed segment. The rendered byte count and SHA-256 must exactly match the published
CSV. A late, missing, corrupt, linked, open, or otherwise unsafe segment blocks deletion. Lifecycle
discovery and processing are durably queued and bounded, so neither startup nor a one-minute
maintenance cycle traverses the entire retained history.

A site may set `requireBackupBeforeSealedJournalDeletion=true`. In that stronger mode, creation of
an optional coordinated snapshot keeps the application stopped through authenticated checksum,
archive-member, and PostgreSQL verification. OSCAR records backup confirmation only when that
accepted snapshot contains the exact CSV, manifest, and sealed-segment inventory and the live
publication still matches. The receipt is bound to the backup ID and authenticated
`oscar-state.tar.gz` SHA-256. Manual `backup-verify` does not create receipts or change `CURRENT`.

## Media lifecycle

### Source recording

Camera recordings continue to be referenced by the occupancy observation's `videoPaths` value.
The v1 retained-media representation is additive, so old clients and old events remain readable.

For new recordings, a bounded FIFO serializes start, close, and cancel commands independently for
each camera. A successful start owns one generation-qualified source path,
`videos/clips/<camera-token>/<timestamp>-g<generation>.mp4`. The validated close return value is the only
authoritative path eligible for the occupancy; OSCAR does not associate a recording by directory
order, timestamp proximity, or a mutable camera filename. Publication requires an exact match for
the owning event, lane, camera, and generation, plus a nonblank, unique, finalized, nonzero MP4.

Non-alarm occupancies cancel and remove their unpublished recordings. If a close or cancel times
out, the affected camera queue is quarantined from later recording work while the underlying result
remains observed. A validated result that arrives after invalidation is removed, including its
partial output, so it cannot become an orphan or be attached to a subsequent event. Reconnects and
listener changes are generation-gated and use race-safe collections to keep callbacks with their
original occupancy.

### Five-frame publication

With the standard `timeToRetention=0`, each completed camera source is immediately eligible; the
sliding retention query processes it asynchronously on a retention cycle (every five minutes by default). It decodes the clip twice: first to construct the frame timeline, then to capture the five
selected distinct ordinals. A valid set contains:

1. first frame;
2. nearest distinct frame to 25 percent of the decoded timeline;
3. nearest distinct frame to 50 percent;
4. nearest distinct frame to 75 percent; and
5. last frame.

Every JPEG is written to a partial, forced, checked for complete JPEG markers and baseline SOF0,
decoded independently, and checked for opaque sRGB dimensions. The five frames are published before
the manifest. The manifest records source and asset hashes, byte counts, dimensions, codec, timing,
selected ordinals, lifecycle states, and rollback deadline. A durable per-identity job ledger makes
retries idempotent.

Before committing the manifest, OSCAR reserves independent direct-addressed catalog-reconciliation
and pressure-queue slots. The cyclic reconciliation worker freezes the queue tail and processes only
its configured share of `maintenanceWorkLimit`, so lifecycle/ledger repair remains restart-safe and
does not enumerate the retained-media tree. A pre-manifest crash leaves only a stale slot that the
worker discards; a post-manifest crash always leaves durable repair work.

New OSCAR-managed alarm clips receive a bounded post-roll until five video packets have been
muxed. The source is never deleted on the creation attempt. Any error, including a legacy or
externally supplied clip with fewer than five decoded frames, preserves the source and records a
failed job. After successful publication the source is
`PRESERVED_FOR_ROLLBACK` for `sourceRollbackGraceHours` (24 by default). A subsequent retention pass
re-verifies the set and, if no hold applies, advances through `ELIGIBLE_FOR_DELETION` to `DELETED`.

Once a media set reaches `SOURCE_DELETED` and exceeds `secondaryFrameRetentionDays` (30 by default;
set `-1` to keep all five frames until storage-pressure cleanup), the maintenance worker re-verifies
the `MIDDLE` (`frame-03.jpg`) asset against its manifest SHA-256 and byte count, unlinks the four
secondary frames (`FIRST`, `QUARTER`, `THREE_QUARTERS`, and `LAST`), and updates their manifest
entries to `DELETED` while keeping `MIDDLE` `PUBLISHED`. The Viewer renders only `PUBLISHED` frames
without broken image requests. Any active manifest hold (`hold.active = true` with non-blank
`hold.reason` and ISO-8601 `hold.placedAt`) defers source deletion, secondary-frame pruning, and
storage-pressure deletion.

The standard worker runs every five minutes and advances the primary cursor by at most six hours of
event time per cycle. A separate delayed cursor revisits event time only after the 24-hour
late-arrival allowance, runs at most every six hours, and advances at most two hours per cycle. A
restart-resumable historical sweep handles older delayed records in 24-hour chunks and repeats
daily. Occupancy datastream IDs are cached for 15 minutes. These durable, bounded paths prevent a
late or previously uncatalogued clip from being skipped without restoring an all-history scan.

### Recording and retained-media regression gate

Release acceptance must create fresh alarm and non-alarm occupancies rather than validating only
pre-existing files. For every alarm, the suite resolves the exact event UUID and configured camera
UIDs, then requires one unique, nonblank generation-qualified source per camera, verifies that each
MP4 exists, is nonzero, and decodes with valid duration and dimensions, and rejects any new orphan
final or partial file. A non-alarm recording must leave no source behind. Back-to-back alarms and a
camera reconnect must preserve exact event/lane/camera ownership.

After the test-only retention interval elapses, acceptance requires one complete manifest per source
with exactly five independently decodable JPEGs, matching source identity and event/lane/camera
ledger fields, one successful attempt, and no failure record. The shipped production defaults are
one retention day and a five-minute query cadence; qualification may use an accelerated profile on
an isolated disposable site but must still prove the same five-frame and 24-hour source-grace
contracts.

The retained-media worker captures this profile when OSCAR starts. On a newly initialized
qualification site, save the accelerated profile and perform a supported OSCAR restart **before**
importing lanes or permitting emulator traffic. Verify the startup log and scan checkpoint use the
new eligible-through cutoff, then provision the lanes and perform the fixture's supported restart.
Saving the form alone does not reconfigure an already running worker. A checkpoint created under
an older profile deliberately resumes from its durable cursor instead of jumping over
unexamined history. Never delete or fast-forward a scan or reconciliation checkpoint to accelerate
a test. If a disposable site was initialized in the wrong order, recreate its disposable database
and state, or allow bounded oldest-first catch-up. Production requires catch-up or a reviewed
migration procedure.

### Viewer behavior

The Viewer requests the authenticated read-only event endpoint under
`/buckets/videos/media/{eventId}`. A returned media set is shown as five labeled still frames per
camera. Streaming validation caps the catalog body at 1 MiB, the response at eight cameras
(`MAX_MEDIA_SETS_PER_EVENT = 8`), each frame at 12 MiB and 20 megapixels, either dimension at
6,000 pixels, and the aggregate event across all published frames (`cameras × 5` frames prior to
30-day secondary pruning) at 64 MiB and 120 megapixels — supporting up to `8` cameras per lane at
`1080p` (`1920×1080`), `4` cameras per lane at `5 MP` (`3072×1728`), or `2` cameras per lane at `4K`
(`3840×2160`; see [Live Video](LIVE_VIDEO.md#multi-camera-lanes-and-per-lane-camera-limits)). A frame body is stopped as soon as it exceeds its manifest byte count, even without
a valid `Content-Length`. Only the currently selected
frame for each camera is fetched, with at most three event-wide frame requests in flight. A `404`
means no retained-media v1 set exists, so the Viewer uses the unchanged legacy `videoPaths`
playback path. Invalid or missing retained assets are not served as successful images.

### Storage pressure

The pressure worker checks the filesystem every minute. At 85 percent used, it consumes eligible
complete media sets from a durable publication-order queue until usage reaches 80 percent. A set
must be at least 10 minutes old, outside rollback grace, and not held. Each cycle inspects at most
`maximumMediaSetsPerCycle` entries (200 by default), and the durable head resumes after restart.
No pressure cycle enumerates or sorts the retained-media tree. A selected set is marked `DELETING`,
assets and any remaining source are removed, and the manifest commit marker is removed last so an
interrupted pass can retry.

Pressure cleanup does **not** scan arbitrary files. It does not delete uncatalogued legacy videos,
daily CSVs/journals, adjudication data, reports, or Parquet generations. If no eligible retained
media can reach the target, OSCAR logs an error and preserves protected data.

## Holds, overlays, tombstones, and audit records

The archive catalog includes these control records:

| Record | Purpose |
| --- | --- |
| `oscar_retention_hold` | Prevent physical and logical generation/observation deletion while active; persist exact vs conservative resolution provenance |
| `oscar_obs_overlay` | Current value of a mutation to an immutable archived observation |
| `oscar_tombstone` | Suppress a policy/user-deleted observation without rewriting Parquet |
| `oscar_archive_verification` | Immutable history of parity, deletion, and deferred-hold receipts |
| `oscar_deletion_plan` / `_item` | Frozen, expiring set reviewed for cold deletion |
| `oscar_deletion_ledger` | Per-object deletion outcome retained after file removal |
| `oscar_backup_epoch` | PostgreSQL link to a coordinated backup manifest and the count/bytes/SHA-256 receipt for its authenticated archive-generation inventory; the exact UUID set remains in the backup |

The release CLI can list, create, and release generation or exact-observation holds. Creation
requires a generation UUID or numeric observation ID plus a reason; release records the actor and
time without deleting the hold row. Use the commands in
[Storage operations](STORAGE_OPERATIONS.md#manage-retention-holds) only as part of the site's
approved legal/records workflow. An exact extant hot row takes precedence over unrelated coarse
archive ID ranges; cold-only overlapping queryable and retired ranges remain fail-closed, and a
tombstone always prevents a new hold. Directly editing these tables can make retention results
incorrect.

New holds persist `GENERATION_EXACT`, `HOT_EXACT`, or `COLD_RANGE_CONSERVATIVE`. The conservative
mode means a cold-only ID was covered by a candidate generation's min/max block; because sparse
Parquet IDs may leave gaps, it protects the range but is not evidence that the exact observation
exists. A migrated pre-3.11.0 observation hold is labeled `LEGACY_UNKNOWN`: its historical exact-vs-
range provenance cannot be reconstructed, so it remains protective but must not be cited as proof
that an exact observation existed. Confirm the event or use an explicit generation hold when legal
certainty is required.

## Policy changes

Before shortening any period or enabling a deletion flag:

1. Record the business owner, reason, and effective date.
2. Check active legal/investigative holds.
3. Take and verify a coordinated backup.
4. Run mixed-tier queries and archive integrity verification.
5. Perform a deletion dry run and review counts, bytes, and held generations.
6. Change one policy at a time and monitor at least one complete lifecycle interval.
7. Record the resulting verification/deletion receipts with the change ticket.

Changing an archive period does not retroactively make manually copied exports disappear. Track and
dispose of every external copy under the same policy.
