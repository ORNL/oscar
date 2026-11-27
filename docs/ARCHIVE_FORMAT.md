# OSCAR 3.12.1 cold archive format

OSCAR's cold observation tier is a portable set of ZSTD-compressed Apache Parquet files, JSON
manifests, gzip-compressed datastream schema snapshots, and a PostgreSQL catalog. OSCAR uses the
catalog for safe online queries and lifecycle decisions; exported generations can be inspected
independently with DuckDB or another Parquet-capable tool. This is the primary cold tier for the
configured 26 allowlisted operational and evidentiary output names (`gammaCounts`, `gammaThreshold`,
`neutronCounts`, `setupGamma`, `setupNeutron`, `speed`, `backgroundReport`, `foregroundReport`,
`status`, `emlContextual`, `emlScanContextual`, `emlAnalysis`, `dailyFile`, `connectionStatus`,
`occupancyStatus`, `tamper`, `occupancy`, `adjudication`, `report`, `siteStatistics`,
`nationalSummary`, `vehicleOcr`, `location`, `alarm`, `KromekDetectorRadiometricsV1Report`,
`KromekSerialRadiometricStatusReport`), not a backup and not an export of every PostgreSQL table. A
recoverable system snapshot must also include the matching catalog, overlays/tombstones, application
state, and other coordinated payloads.

See [Storage architecture](STORAGE_ARCHITECTURE.md) for the system context and
[Storage operations](STORAGE_OPERATIONS.md) for the supported verification, export, and deletion
commands.

## On-disk layout

All paths stored in the catalog and manifests are relative to the configured archive root. The
standard container root is `/var/lib/oscar/archive`, backed by `${OSCAR_ARCHIVE_DIR}` on the host.

```text
archive-root/
  .oscar-storage-root
  datasets/
    observations/
      date=YYYY-MM-DD/
        profile=RAW_EVENTS/
          generation-<uuid>.parquet
          generation-<uuid>.schemas.json.gz
          generation-<uuid>.manifest.json
        profile=RAW_TELEMETRY/
          generation-<uuid>.parquet
          generation-<uuid>.schemas.json.gz
          generation-<uuid>.manifest.json
        profile=DAILY_EVENTS/
          generation-<uuid>.parquet
          generation-<uuid>.schemas.json.gz
          generation-<uuid>.manifest.json
        profile=RAW_GATED/            # HOT_RETENTION mode and read-only pre-3.12 legacy archives
          generation-<uuid>.parquet
          generation-<uuid>.schemas.json.gz
          generation-<uuid>.manifest.json
      date=YYYY-MM-01/
        profile=MONTHLY_EVENTS/
          generation-<uuid>.parquet
          generation-<uuid>.schemas.json.gz
          generation-<uuid>.manifest.json
```

The `date=` and `profile=` directories are Hive-style partitions. The date is the UTC date of the
generation window start (`YYYY-MM-01` for `MONTHLY_EVENTS`). In `PARQUET_PRIMARY` mode, closed
30-minute stage windows split directly at export into two strictly complementary Parquet V2
profiles:

- **`RAW_EVENTS`** (`archive_version = 2`, 20 columns, `ROW_GROUP_SIZE = 8192`, Split-Block Bloom
  filters at `0.01` FPR): the 9 searchable operational/evidentiary/summary streams (`occupancy`,
  `alarm`, `adjudication`, `report`, `vehicleOcr`, `emlAnalysis`, `tamper`, `siteStatistics`,
  `nationalSummary`).
- **`RAW_TELEMETRY`** (`archive_version = 2`, 11 columns, `ROW_GROUP_SIZE = 65536`, ZSTD level 6,
  `effectiveTelemetryExportUncompressedBytes = 128 MiB` at `256 MiB` DuckDB limit, `ocr_bloom = NULL`):
  all remaining allowlisted high-rate streams (`gammaCounts`, `gammaThreshold`, `neutronCounts`,
  `dailyFile`, `connectionStatus`, `occupancyStatus`, `emlScanContextual`, `emlContextual`,
  `setupGamma`, `setupNeutron`, `speed`, `backgroundReport`, `foregroundReport`, `status`,
  `location`, `KromekDetectorRadiometricsV1Report`, `KromekSerialRadiometricStatusReport`).
  Written once (`1.0x` write amplification) and **never rewritten by compaction**.

`ArchiveCompactionManager` compacts only the event tier:

- **`DAILY_EVENTS`** (`archive_version = 2`, 20 columns, `ROW_GROUP_SIZE = 8192`, Split-Block Bloom
  filters at `0.01` FPR): compacts settled prior UTC days of `RAW_EVENTS` (`window_end <= now - 2h`
  and `activated_at <= now - 2h`), folds settled overlays (`>= 2h` old), and enforces rollover
  ceilings of `1,000,000` rows or `192 MiB` uncompressed (`~16–32 MiB` ZSTD Parquet) across strictly
  disjoint `[window_start, window_end)` parts.
- **`MONTHLY_EVENTS`** (`archive_version = 2`, 20 columns, `ROW_GROUP_SIZE = 16384`, Split-Block
  Bloom filters at `0.01` FPR): consolidates closed UTC months (`+15d` maturity with
  `DAILY_EVENTS.activated_at <= now - 7d`), folds settled overlays (`>= 7d` old), enforces the same
  `1,000,000`-row / `192 MiB` rollover ceilings, and independently defragments any single
  `MONTHLY_EVENTS` part with `>= 64` settled overlays (`>= 7d` old).

Legacy `RAW_GATED` (`archive_version = 1`) and any pre-split `DAILY_TELEMETRY` (`archive_version = 2`)
files remain read-only compatible via `union_by_name = true` and are never rewritten on upgrade.
To keep 10-year archives (`175,200+` `RAW_TELEMETRY` generations alongside `<= 198` event generations)
fast and I/O-bounded, pure event-stream catalog queries prune directly on
`oscar_archive_generation_time_idx` to `EVENT_QUERY_PROFILES` (`RAW_GATED`, `RAW_EVENTS`,
`DAILY_EVENTS`, `MONTHLY_EVENTS`) after verifying no legacy telemetry generation holds that stream,
summary queries always bind `s.generation_id = ANY (?::uuid[])` in `2,048`-UUID batches, and nightly
`oscar_archive_schema` reindexing is bloat-gated once relation size reaches `256 MiB`.

`.oscar-storage-root` is host-local administrator metadata, not an archive object. It is validated
and authenticated before live archive commands, then recognized only at that exact root-level name
so catalog orphan reconciliation can exclude it. It is also excluded from coordinated backup tar
payloads and preserved across restore. It must never be copied from a source deployment to claim a
target root; nested or similarly named files receive no exemption from archive-layout validation.

Do not infer query authorization from directory names or a file's presence. OSCAR reads only
objects whose generation is `ACTIVE` or `SEALED` in PostgreSQL and whose resolved path stays under
the configured root.

## Parquet schema

### Base 11-column schema (`RAW_GATED` format v1 & `RAW_TELEMETRY` format v2)

| Column | Type | Meaning |
| --- | --- | --- |
| `id_scope` | `INTEGER` | OSH scope for the observation ID |
| `id_value` | `BIGINT` | Stable sequential observation ID value |
| `datastream_scope` | `INTEGER` | OSH scope for the datastream ID |
| `datastream_id` | `BIGINT` | Stable datastream ID value |
| `foi_scope` | nullable `INTEGER` | OSH scope for the feature-of-interest ID |
| `foi_id` | nullable `BIGINT` | Feature-of-interest ID value |
| `phenomenon_time` | `TIMESTAMP` | Observation phenomenon time (UTC) |
| `result_time` | `TIMESTAMP` | Observation result time (UTC) |
| `result_json` | `VARCHAR` | OSH result block serialized against its datastream schema |
| `archive_version` | `INTEGER` | Row format version (`1` for `RAW_GATED`; `2` for `RAW_TELEMETRY`, `RAW_EVENTS`, `DAILY_EVENTS`, `MONTHLY_EVENTS`) |
| `profile` | `VARCHAR` | Archive selection profile (`RAW_EVENTS`, `RAW_TELEMETRY`, `DAILY_EVENTS`, `MONTHLY_EVENTS`, or `RAW_GATED`) |

### Extended 20-column projected event schema (`RAW_EVENTS`, `DAILY_EVENTS`, `MONTHLY_EVENTS`, format v2)

In addition to all 11 base columns above, Parquet V2 event profiles pre-extract 9 typed scalar
columns in Java (`ProjectedEventColumns`) and write Split-Block Bloom filters
(`BLOOM_FILTER_FALSE_POSITIVE_RATIO = 0.01`) so DuckDB pushes CQL filters down without parsing
`result_json` during scans:

| Column | Type | Source JSON Field(s) |
| --- | --- | --- |
| `ocr_norm` | nullable `VARCHAR` | `normalizedValue` (`vehicleOcr`) |
| `occ_obs_id` | nullable `VARCHAR` | `occupancyObsId` (`vehicleOcr`, `adjudication`, `emlAnalysis`) |
| `event_id` | nullable `VARCHAR` | `eventId` (`occupancy`, `alarm`, `report`) |
| `adj_code` | nullable `INTEGER` | `adjudicationCode` |
| `adj_count` | nullable `INTEGER` | `adjudicatedIdsCount` (or `len(adjudicatedIds)`) |
| `gamma_alarm` | nullable `BOOLEAN` | `gammaAlarm` |
| `neutron_alarm` | nullable `BOOLEAN` | `neutronAlarm` |
| `max_gamma` | nullable `DOUBLE` | `maxGammaCount` / `maxGamma` |
| `max_neutron` | nullable `DOUBLE` | `maxNeutronCount` / `maxNeutron` |

Rows in every profile are written in deterministic sort order:

```text
datastream_id, phenomenon_time, result_time, id_value
```

Profile writer parameters (all ZSTD level 6 by default):

| Profile | Parquet Version | Columns | Row Group Size | Bloom Filters | Rollover Budget (`256 MiB` DuckDB) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `RAW_EVENTS` | Parquet V2 (`archive_version = 2`) | 20 (projected) | `8,192` | Yes (`0.01` FPR) | `32 MiB` uncompressed |
| `RAW_TELEMETRY` | Parquet V2 (`archive_version = 2`) | 11 (base) | `65,536` | No | `128 MiB` uncompressed (`~8–10 MiB` ZSTD) |
| `DAILY_EVENTS` | Parquet V2 (`archive_version = 2`) | 20 (projected) | `8,192` | Yes (`0.01` FPR) | `1,000,000` rows or `192 MiB` uncompressed (`2x` hard cap) |
| `MONTHLY_EVENTS` | Parquet V2 (`archive_version = 2`) | 20 (projected) | `16,384` | Yes (`0.01` FPR) | `1,000,000` rows or `192 MiB` uncompressed (`2x` hard cap) |
| `RAW_GATED` (legacy / `HOT_RETENTION`) | Parquet V1 (`archive_version = 1`) | 11 (base) | `122,880` | No | `32 MiB` uncompressed |

Sorting, disjoint multi-part window assignment, Hive-style date partitions, and Parquet V2 page
indexes/Bloom filters allow DuckDB min/max and Bloom metadata to skip unrelated row groups and files.

A busy UTC-aligned staging window may be represented by several immutable generations with the same catalog window.
Each generation contains the next deterministic `(phenomenon_time, id_value)` prefix that fits the
bounded export budget; later prefixes use normal job revisions. Catalog ownership remains exact per
observation, so combined staging/cold reads and portable exports do not duplicate rows.

`result_json` is not a self-describing replacement for the OSH schema. Keep the matching schema
snapshot whenever a Parquet object is copied.

## Datastream schema snapshot

`generation-<uuid>.schemas.json.gz` is gzip-compressed UTF-8 JSON:

```json
{
  "format": "oscar-datastream-schema-snapshot",
  "version": 1,
  "schemas": [
    {
      "dataStreamId": 123,
      "json": "{...serialized OSH IDataStreamInfo...}"
    }
  ]
}
```

The schemas are loaded in the same PostgreSQL repeatable-read transaction as the observations. The
manifest lists their datastream IDs and the snapshot's path, SHA-256, byte count, and gzip
compression. OSCAR normally uses the live datastream schema; it falls back to this snapshot if the
live record is unavailable.

## Generation manifest

`generation-<uuid>.manifest.json` is UTF-8 JSON and is published after the Parquet and schema
objects. Its format is `oscar-observation-archive`, version `1`. A representative shape is:

```json
{
  "format": "oscar-observation-archive",
  "version": 1,
  "generationId": "00000000-0000-4000-8000-000000000000",
  "profile": "RAW_GATED",
  "windowStart": "2026-10-01T00:00:00Z",
  "windowEnd": "2026-10-01T01:00:00Z",
  "object": "datasets/observations/date=2026-10-01/profile=RAW_GATED/generation-....parquet",
  "sha256": "<lowercase SHA-256>",
  "bytes": 123456,
  "rowCount": 10000,
  "minimumId": 200000,
  "maximumId": 219999,
  "idScope": 4,
  "datastreamSchemaIds": [123, 124],
  "datastreamSchemas": {
    "object": "datasets/observations/date=2026-10-01/profile=RAW_GATED/generation-....schemas.json.gz",
    "sha256": "<lowercase SHA-256>",
    "bytes": 2345,
    "compression": "gzip"
  },
  "columns": ["id_scope:INTEGER", "..."],
  "sort": ["datastream_id", "phenomenon_time", "result_time", "id_value"],
  "compression": "zstd",
  "createdAt": "2026-10-17T12:34:56Z"
}
```

The actual UUID, IDs, counts, paths, timestamps, and digest replace the example values. Time windows
are half-open: `windowStart <= phenomenon_time < windowEnd`.

The manifest is a file-level commit marker, but online activation also requires the matching
PostgreSQL catalog transaction. A copied manifest must not be inserted into the catalog by hand.

## PostgreSQL catalog

The catalog migration is versioned in `oscar_storage_schema_version`. Its operational tables are:

The binary verifies the exact checksum of every recorded schema-version marker and refuses to open a
catalog with a higher recorded version. When a v4 marker is present, the v4-to-v5 upgrade verifies
that marker before applying any v5 DDL. This authenticates the declared migration lineage; it is not
a checksum of the live v4 table definitions. The transactional migration and its constraints validate
the live shape they consume, while a legacy catalog with no v4 marker follows the explicitly supported
marker-bootstrap path.
In-place storage-schema downgrade is unsupported: restore a coordinated backup into an isolated
deployment running the matching release rather than starting older code on a newer catalog.

| Table | Role |
| --- | --- |
| `oscar_archive_job` | Export attempts, revision, state, error, and two-hour stale-job recovery |
| `oscar_archive_generation` | Window, profile, object/manifest paths, Parquet hash, ID range, state, parity flag |
| `oscar_archive_object` | Every generation object, kind, relative path, SHA-256, bytes, and lifecycle state |
| `oscar_archive_id_block` | Generation ID range used to plan exact-ID lookups |
| `oscar_archive_schema` | PostgreSQL copy of each generation's datastream schemas plus 26 per-generation, per-datastream summary counters (alarm, fault including `Fault - Neutron High`, RS-350 `alarmCategoryCode`, and adjudication-split counts, with whole-generation `TimeContainedSummarySpec` count pushdown and selective `ocr_bloom` on event streams) |
| `oscar_obs_schema_catalog` | Content-addressed `DataRecord` JSON catalog (`schema_sha256 PRIMARY KEY`) referenced by `oscar_obs_overlay` and `oscar_obs_latest` so per-row `schema_json` stays `NULL` |
| `oscar_obs_latest` | Latest observation per datastream (synchronized across Parquet activation and `oscar_obs_overlay` updates via `schema_sha256`) for `< 0.5 ms` `resultTime=latest` / `phenomenonTime=latest` queries |
| `oscar_obs_storage_route` | Stable mutable-versus-immutable classification for each observed datastream |
| `oscar_obs_stage_partition` | Attached/detached catalog for short-lived LOGGED Parquet-primary staging children |
| `oscar_obs_stage_owner` | Compact exact row-to-generation ownership while a staging child still overlaps Parquet; removed with the child |
| `oscar_event_locator` | Stable public-event to observation/generation locator reserved for direct lookup |
| `oscar_obs_overlay` | Mutable value for an updated immutable archived observation (such as an adjudicated or re-adjudicated cold occupancy, referencing `oscar_obs_schema_catalog` via `schema_sha256`) |
| `oscar_tombstone` | Logical removal of an immutable archived observation |
| `oscar_retention_hold` | Active/released generation or observation holds |
| `oscar_archive_verification` | Parity plus primary-stage retirement or compatibility hot-deletion receipts |
| `oscar_deletion_plan` / `oscar_deletion_plan_item` | Frozen, expiring cold-deletion selection |
| `oscar_deletion_ledger` | Per-object deletion audit trail |
| `oscar_media_manifest` / `oscar_media_asset` | Reserved structured media catalog records |
| `oscar_backup_epoch` | Link between a coordinated backup manifest and the bounded count, byte length, and SHA-256 receipt for its authenticated active/sealed-generation inventory; exact UUIDs stay in the backup file rather than a per-backup PostgreSQL array |

Archive-job state `SUPERSEDED` is an audited terminal no-op used when a reclaimed failed/stale
window contains no eligible unowned rows. It has no generation and is never query-visible.

Generation states used by the observation reader/lifecycle are:

```text
EXPORTING job --> ACTIVE generation --> SEALED generation --> DELETING generation --> PURGED generation
         `----> FAILED job
```

- `ACTIVE`: files are queryable and a verified PostgreSQL overlap can still exist.
- `SEALED`: parity passed and the corresponding Parquet-primary stage child has been
  dropped (or, in `HOT_RETENTION`, its exact hot rows were deleted); files remain queryable.
- `DELETING`: a confirmed purge transaction made the entire generation non-queryable and persisted
  deletion intent before the first file removal. Re-running the same plan/token resumes it.
- `PURGED`: an approved cold-deletion plan removed the objects; it is not queryable.

Object rows transition from `ACTIVE` to durable `DELETING` intent and then `DELETED`. The
intermediate state makes a confirmed purge restartable with the same plan/token after interruption.
Catalog, generation tombstone, and deletion-ledger rows remain after a purge so policy deletion is
auditable. Observation overlays (`oscar_obs_overlay`), cached latest pointers (`oscar_obs_latest`),
event locators (`oscar_event_locator`), and observation tombstones (`oscar_tombstone`) carrying that
exact generation ID are removed in the final `PURGED` transaction because they no longer have a
queryable target; legacy unowned mutations are not guessed from ID ranges. The generation tombstone
and audit rows are not removed.

Hold creation/release and the purge visibility transition take the same PostgreSQL table lock. A
hold either commits first and excludes the generation, or the purge commits `DELETING` first and a
new hold is rejected; there is no interval in which a successful hold can race a file deletion.

## Integrity and atomicity

For each generation, OSCAR:

1. runs the source query in a read-only PostgreSQL `REPEATABLE READ` transaction;
2. verifies Parquet count, minimum ID, and maximum ID by reopening it in DuckDB;
3. forces each data object before publication;
4. publishes the manifest last;
5. records SHA-256 and bytes for Parquet, schema snapshot, and manifest in PostgreSQL;
6. marks exact source rows and activates the catalog in one PostgreSQL transaction; and
7. verifies the Parquet SHA-256 again before its first read in each OSCAR process.

The supported `archive verify` command additionally proves catalog completeness: every
query-visible (`ACTIVE` or `SEALED`) generation must have exactly one active Parquet object, one
active generation manifest, and one active datastream-schema snapshot, each with a confined path
and matching SHA-256. The required Parquet object's path and checksum must equal the generation's
authoritative `object_path` and `sha256`, and the manifest object's path must equal
`manifest_path`; verification hashes that exact file. It does not treat an absent object row—or a
stale generation pointer—as an empty successful verification. Verification reads one canonical
catalog snapshot before the file checks and requires the same snapshot afterward, so live archive
activation or purge makes the command fail/retry rather than report a mixed-time success.
The same snapshot verifies exactly one `oscar_archive_id_block` per query-visible generation, with
`min_id`/`max_id` equal to the generation bounds, and requires at least one matching
`oscar_archive_schema` row. This detects relational-catalog damage even when all three immutable
files and their checksums remain intact.

All embedded DuckDB work is resource bounded. Production defaults limit each connection to 256 MiB
of memory, two threads, and 4 GiB of spill in a private per-operation directory under
`/var/lib/oscar/duckdb-tmp`. A fair process-wide gate admits at most two sessions and fails a waiter
busy after 30 seconds, bounding the aggregate resource multiplier across exports, verification,
deletion, and cold queries. OSCAR rejects archive/scratch root overlap and, on POSIX, rejects an
existing scratch parent unless it is mode `0700`; the Linux deployment container provides the same
protection on Ubuntu and Windows hosts. A persistent `.oscar-duckdb.lock` lease (a real regular file,
mode `0600`) is held for the owning process/classloader lifetime. It prevents a concurrent owner
from cleaning live spill. On its first successful open, an owner holding the lease automatically
removes only recognized direct `<operation>-<lowercase UUID>` children abandoned by a prior owner;
unrelated entries and links are preserved. Normal operation children are closed and removed per
operation, while the lease remains until process shutdown. The entire scratch parent, including the
lease, is excluded from the portable archive and coordinated backup. Streaming reads cooperate with
shutdown between result rows in addition to cancelling the active JDBC statement.

Object publication and PostgreSQL activation cannot be one filesystem/database transaction. A file
that exists without an `ACTIVE`/`DELETING` catalog object is intentionally invisible and is reported
as an orphan by `archive status` and `archive verify`; a file whose catalog row is already `DELETED`
is also an error. A `.partial` file is reported while younger than the two-hour (`7200` s) stale-job
window and fails verification once stale. During background `drainDeletingGenerations` (when no
`EXPORTING` job is active), `ArchiveCompactionManager.sweepStaleUnregisteredPartials` automatically
removes unregistered `.partial` artifacts older than two hours and prunes empty `profile=` / `date=`
directories while failing closed on any UUID present in `oscar_archive_generation`. Online
`archive verify` itself remains report-only and never auto-deletes. A
cataloged object that is missing or has the wrong digest is an integrity incident; the reader fails
rather than silently returning an incomplete result.

The standard filesystem should support durable file force and rename semantics. Parquet publication
prefers an atomic move and falls back to a same-filesystem move when the Java platform reports that
atomic moves are unsupported. Keep a generation's objects on one reliable filesystem and never
write an archive directly onto a lossy synchronization directory.

## Querying a portable copy with DuckDB

First export a generation with the supported OSCAR command. Ubuntu:

```sh
sudo bash oscar.sh archive export \
  --store-key <store-key> \
  --id-scope <id-scope> \
  --generation 00000000-0000-4000-8000-000000000000 \
  --destination /secure/export/oscar-generation
```

Windows:

```powershell
.\oscar.bat archive export `
  -StoreKey <store-key> `
  -IdScope <id-scope> `
  -Generation 00000000-0000-4000-8000-000000000000 `
  -Destination D:\secure-export\oscar-generation
```

The destination must be a new directory. The command briefly stops only OSCAR when it was already
running and always attempts to resume it. A networkless, read-only-rootfs one-shot OSCAR-image
helper receives only the archive root read-only plus the fresh hidden export partial writable. It
revalidates every path component/no-link condition, verifies each source checksum, copies the object,
and verifies the copy. OSCAR preserves the catalog-relative `datasets/...` path and then renames the
complete package into place. It adds:

- `catalog-<generation-id>.json` with generation provenance;
- `objects-<generation-id>.json` with object paths, kinds, hashes, bytes, and states;
- `README.md` with portable-use instructions;
- `query.sql` ready for `duckdb < query.sql`; and
- `SHA256SUMS` covering every other package file.

Verify the online archive before export with `archive verify`, then verify `SHA256SUMS` after every
copy of the portable package.

From the export directory, DuckDB can query one file:

```sql
SELECT
    id_scope,
    id_value,
    datastream_id,
    phenomenon_time,
    result_json
FROM read_parquet(
    'datasets/observations/date=2026-10-01/profile=RAW_GATED/generation-<uuid>.parquet'
)
WHERE datastream_id = 123
  AND phenomenon_time >= TIMESTAMP '2026-10-01 00:15:00'
  AND phenomenon_time <  TIMESTAMP '2026-10-01 00:30:00'
ORDER BY phenomenon_time, id_value;
```

Or search a copied archive tree with partition discovery:

```sql
SELECT
    date,
    profile,
    datastream_id,
    min(phenomenon_time) AS first_sample,
    max(phenomenon_time) AS last_sample,
    count(*) AS samples
FROM read_parquet(
    'datasets/observations/date=*/profile=*/*.parquet',
    hive_partitioning = true,
    union_by_name = true
)
GROUP BY ALL
ORDER BY date, profile, datastream_id;
```

Treat `result_json` according to the corresponding serialized OSH datastream schema. For ad hoc
inspection, DuckDB JSON functions can extract known fields, but schema-aware tools should load the
`.schemas.json.gz` file rather than guess names or types.

## Copying and reviewing archives

Portable review does not require a running OSCAR installation. The supported export command copies
these as one unit:

- the Parquet object;
- its generation manifest;
- its gzip schema snapshot;
- the generation and object catalog JSON files;
- the generated README and DuckDB query; and
- the generated `SHA256SUMS` list.

Encrypt removable media and verify its checksums both after the copy and before review. Relative
paths make a complete archive tree relocatable, but an arbitrary copy is not automatically
registered as live OSCAR storage. Restoring OSCAR requires the coordinated PostgreSQL catalog and
archive copy described in [Backup and restore](BACKUP_RESTORE.md).

An external analyst can delete or reorganize an independent exported copy without changing the
running system. To delete the running system's oldest cold data without breaking queries, use the
tokenized `archive dry-run` and `archive purge` workflow; never manually delete the cataloged files.

## Compatibility rules for future writers

- Additive readers may accept future manifest or row versions only after explicit validation.
- A format-v1 writer must emit every documented column and exactly one matching schema snapshot.
- Public OSH scope/value ID pairs must never be renumbered during export.
- A writer must not modify an activated Parquet object in place. Corrections use overlays,
  tombstones, or a new generation/revision.
- The manifest remains the final file publication marker, and PostgreSQL activation remains the
  online query authorization marker.
- Object paths must stay relative, normalized, and under the configured archive root.
