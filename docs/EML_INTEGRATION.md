# EML (Energy-Based Machine Learning) Runtime Plugin & Automated Adjudication Guide

OSCAR 3.11.0 supports optional runtime integration with the external **Energy-Based Machine Learning (EML)** VM-250 analyzer (such as `EML-VM250-v1.0.2`) for Rapiscan radiation portal monitor (RPM) lanes.

Because EML is separately licensed and maintained outside the open-source OSCAR repositories, **OSCAR never bundles, commits, or distributes EML JARs, models, or XML configuration files** in source repositories, Docker images, or GitHub Release assets. Instead, site administrators obtain an authorized EML distribution separately, upload the EML plugin archive once in SensorHub Admin (**Services -> OSCAR Service**), and enable EML per Rapiscan lane.

> **Companion Video Guide:** Watch [Module 07 — Upload External EML VM-250 Plugin & Enable Per-Lane EML (`07-admin-eml-plugin-setup.mp4`)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/07-admin-eml-plugin-setup.mp4) ([WebVTT captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/07-admin-eml-plugin-setup.vtt)) in [VIDEO_GUIDES.md](VIDEO_GUIDES.md#07-admin-eml-plugin-setup).

---

## 1. Distribution & Security Boundaries

1. **Zero Upstream Distribution:** `ORNL/oscar` and `ORNL/osh-oakridge-modules` enforce fail-closed packaging checks (`tools/validate-packaged-release.js`, `.gitignore`, and `.dockerignore`) that reject any EML archive, JAR (`gov.llnl.*`, `edu.cmu.cs.auton.*`), or model/configuration file (`vm250*.xml`, `CMU_metric.csv`, `uber_SSL_model_*.txt`).
2. **Private Persistent Storage (`oscar_state`):** Uploaded EML archives are stored privately on the server inside `/var/lib/oscar/eml-plugin/` (directory mode `0700`, file mode `0600`) in the `oscar_oscar_state` volume:
   - Never exposed through public or authenticated `/sensorhub/buckets` HTTP file endpoints.
   - Preserved automatically across container restarts, `oscar upgrade` runs, and `oscar-storage` coordinated schema-v2 backups and restores.
3. **Isolated Runtime Extraction (`/tmp` `noexec` Data Tmpfs):** At startup or immediately upon Admin upload, `EmlRuntimeRegistry` verifies the archive SHA-256, extracts pure-Java EML JARs and XML/model resources into a private `0700` directory under `/tmp/oscar-eml-runtime` (`oscar.data.tmpdir`, preserving `/run/oscar-native` exclusively for JNI shared libraries), and hot-loads the analyzer inside an isolated `URLClassLoader` via reflection.
4. **Graceful Startup Without a Plugin:** If a lane has `emlEnabled=true` (for example, imported from a 50-lane CSV) before an administrator uploads the EML JAR, all Rapiscan and Lane modules still start cleanly with zero `ClassNotFoundException` or `GX` processing errors; occupancies simply bypass EML evaluation until the plugin is uploaded.

---

## 2. Preparing the EML Plugin JAR (Optional Repackaging)

OSCAR's `EmlArchiveExtractor` accepts **either**:
- A single repackaged **`.jar`** plugin bundle (recommended, e.g. `eml-vm250-1.0.2.jar`, ~18 MiB) containing only `config/*` and `jars/*.jar`, **or**
- An unmodified `.tar.gz`, `.tgz`, or `.zip` EML release archive (such as `EML-VM250-v1.0.2.tar.gz`; OSCAR automatically skips `daily_file_examples/`, `src/`, `py/`, `__pycache__/`, and source/javadoc JARs during extraction while rejecting symlinks and path traversal).

To build a clean single-file `eml-vm250-<version>.jar` from an authorized `EML-VM250-<version>.tar.gz` distribution:

### Linux / macOS (Source Checkout Helper)

```sh
./tools/package-eml-jar.sh /path/to/EML-VM250-v1.0.2.tar.gz ./eml-vm250-1.0.2.jar
```

### Windows PowerShell 5.1 (Source Checkout Helper)

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\package-eml-jar.ps1 `
    -InputPath C:\staging\EML-VM250-v1.0.2.tar.gz `
    -OutputJarPath C:\staging\eml-vm250-1.0.2.jar
```

### Standalone Command Without a Source Checkout (Any Workstation with `tar` + `jar` or `zip`)

```sh
mkdir -p /tmp/eml-pack/stage && tar -xzf EML-VM250-v1.0.2.tar.gz -C /tmp/eml-pack && \
cp -R /tmp/eml-pack/EML-VM250-v1.0.2/config /tmp/eml-pack/EML-VM250-v1.0.2/jars /tmp/eml-pack/stage/ && \
(cd /tmp/eml-pack/stage && jar cf "$OLDPWD/eml-vm250-1.0.2.jar" config jars) && rm -rf /tmp/eml-pack
```

---

## 3. Uploading the EML Plugin & Enabling Lanes

### Step 1 — Upload the EML JAR in `Services -> OSCAR Service`

1. Sign in to SensorHub Admin (`https://<oscar-host>/sensorhub/admin`) with an administrator account.
2. Under **Services**, select **OSCAR Service** (or **OSCAR Service Module**).
3. Locate **EML Plugin Path** (`emlPluginPath`) in the service form and upload `eml-vm250-1.0.2.jar` (or `EML-VM250-v1.0.2.tar.gz`).
4. Click **Apply Changes**, then click the top-bar **Save Configuration** button and confirm **Yes** so `emlPluginPath` is persisted to `/var/lib/oscar/config.json`.
   - No container restart is required: `OSCARServiceModule` immediately activates the uploaded archive in `EmlRuntimeRegistry`, logs the active EML version, collimated model name, and SHA-256 prefix, and notifies all running Rapiscan lanes.

### Step 2 — Enable EML on Rapiscan VM-250 Lanes

You can enable EML per lane either through the **SensorHub Admin UI** or via **Lane Spreadsheet CSV** import:

- **In SensorHub Admin UI:**
  1. Expand **Sensors**, expand the target **Lane System**, and select its **Rapiscan RPM** driver.
  2. Under **EML Config**, check **Enable EML** (`emlEnabled`), set **Lane Collimated** (`isCollimated`: `true` for collimated detectors, `false` for uncollimated), and enter **Lane Width** (`laneWidth`, in meters, e.g. `5.49` or `3.66`).
  3. Click **Apply Changes**, then click **Save Configuration** -> **Yes**.
- **In a Lane Configuration CSV (`Spreadsheet Config Path`):**
  - Populate the EML columns on each VM-250 Rapiscan row:
    - `EMLEnabled`: `true`
    - `EMLCollimated`: `true` or `false`
    - `LaneWidth`: positive lane width in meters (for example `5.0`)
  - See [Administrator Guide](../dist/release/DEPLOYMENT.md) and [Operator Manual (English)](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README.md) for full CSV import rules.

---

## 4. Runtime Behavior: Automatic `EML Non-Threat` Adjudication

When a Rapiscan lane has `emlEnabled=true` and an EML plugin is active:

1. **Synchronous Pre-Publication Evaluation on `GX`:**
   - During an occupancy, the Rapiscan driver buffers raw 100 ms / daily-file lines (`GB`, `GA`, `NS`, `GS`, `NH`, `NL`, `GH`, `GL`, `GX`).
   - When the end-of-occupancy `GX` message arrives, OSCAR evaluates the buffered occupancy stream through `EmlRuntimeRegistry` **before** publishing the terminal `Occupancy` observation (`OccupancyOutput.setData`).
   - OSCAR also publishes the full EML output record on the `emlAnalysis` and `emlContextual` datastreams (`releaseProbability`, `investigativeProbability`, `decision`, `fallback`, per-source scores, `versionID`, and active model ID).
2. **Non-Threat Alarms (`decision = RELEASE` and `fallback = false`):**
   - If the occupancy triggered a Gamma, Neutron, or Gamma-Neutron alarm and EML returns `RELEASE` without `fallback` or evaluation error:
     - **Immediate Dashboard & Notification Suppression:** OSCAR attaches the synthetic marker `"eml-non-threat"` to `occupancy.adjudicatedIds` **before** `OccupancyOutput.setData(occupancy)` fires. Because `adjudicatedIdsCount > 0` from initial publication (`t = 0`), the event **never flashes on the Dashboard alarm queue** (`adjudicatedIdsCount=0`) and **never triggers browser/PWA sound or toast alerts**.
     - **Durable Automated Adjudication Record (`Code 9999`):** Immediately after the occupancy observation is persisted in PostgreSQL, `LaneSystem` records a real `Adjudication` observation (`sender="EML"`, disposition code `9999` — **EML Non-Threat**, `secondaryInspectionStatus="NONE"`, `occupancyObsId=<exact-obs-id>`), appends the real adjudication observation ID alongside `"eml-non-threat"` on `occupancy.adjudicatedIds`, and embeds structured `EML_METADATA:{...}` JSON in `feedback`.
3. **Threat / Investigate / Fallback Alarms (`INVESTIGATE` or `fallback = true`):**
   - Any alarm where EML returns `INVESTIGATE`, enters `fallback`, or encounters an evaluation error **remains unadjudicated** (`adjudicatedIdsCount = 0`), appears immediately on the **Dashboard** in standard priority order (`Gamma & Neutron` -> `Neutron` -> `Gamma`), and triggers normal operator notifications while still displaying its EML scores in **Event Details**.

---

## 5. Querying and Reviewing `EML Non-Threat` Events Later

All EML-suppressed alarms remain 100% auditable, queryable, and reviewable by operators and supervisors across English (`en`), Español (`es`), Français (`fr`), and Ελληνικά (`el`):

1. **Event Log (`Events` Page) Filtering:**
   - Open **Events -> Filters**, select field **Adjudicated**, and choose value **EML Non-Threat**:
     - `Adjudicated equals EML Non-Threat` compiles to `adjudicatedIdsCount>0 AND adjudicatedIds='eml-non-threat'`, leveraging indexed PostgreSQL GIN (`jsonb_path_exists`) and DuckDB Parquet `adjudicated_ids_count` row-group pushdown.
     - `Adjudicated equals Yes` returns both human-adjudicated and automated `EML Non-Threat` alarms; combine `Adjudicated equals Yes` **AND** `Adjudicated does not equal EML Non-Threat` to inspect only human-adjudicated alarms.
   - Or select field **Adjudication Code** (`equals`, `does not equal`, `is any of`, `is empty`, `is not empty`) to filter by exact latest disposition code across built-in Codes `1–11`, automated **`9998: Extended Occupancy Gamma Alarm`** (`adjudicatedIdsCount>0 AND adjudicatedIds='code:9998'`), automated **`9999: EML Non-Threat`** (`adjudicatedIdsCount>0 AND adjudicatedIds='code:9999'`), and any site-configured **Custom Disposition Codes**. Existing historical adjudications on upgraded deployments are automatically backfilled in the background (`AdjudicationCodeMarkerBackfill`) without impacting startup latency.
   - In the Event Log table, the **Adjudicated** column displays the localized **EML Non-Threat** label (`Sin amenaza EML`, `Sans menace EML`, `Μη απειλή EML`), and operators can toggle the optional **Adjudication Code** column from the DataGrid **Columns** menu.
2. **Event Details Inspection (`EmlAnalysisCard` & `AdjudicationLog`):**
   - Opening any EML-evaluated occupancy in **Event Details** renders the **EML Automated Analysis** card displaying:
     - Localized verdict chip (**EML Non-Threat** vs. **Investigate**),
     - **Release Probability** and **Investigate Probability** percentages,
     - **Model / Version**, **Collimated / Uncollimated** status, **Lane Width**, and **Fallback** indicator,
     - Non-zero source/category contributions (`primarySource`, `sources`).
   - The **Adjudication Log** table shows the automated disposition (`9999: EML Non-Threat`, secondary inspection `NONE`, clean human-readable summary inline, and pretty-printed `EML_METADATA` JSON in the **Read More** dialog). An operator can still submit a subsequent manual adjudication on the same event if site review requires overriding or annotating the automated disposition.
3. **Adjudication Reports & ConSys API Queries:**
   - PDF/HTML **Adjudication Reports** format code `9999` as `9999 - EML Non-Threat`.
   - External ConSys API / CQL2 clients can query EML auto-adjudicated occupancies or specific disposition codes directly via:
     ```text
     /sensorhub/api/observations?dataStream=<occupancy-ds-id>&filter=adjudicatedIdsCount>0%20AND%20adjudicatedIds='eml-non-threat'
     /sensorhub/api/observations?dataStream=<occupancy-ds-id>&filter=adjudicatedIdsCount>0%20AND%20adjudicatedIds='code:9999'
     ```

### `EML_METADATA` JSON Schema (Embedded in Automated Adjudication `feedback`)

Each automated `Code 9999` adjudication writes a human-readable summary line followed by `\nEML_METADATA:` and a single-line JSON object:

```json
{
  "schema": 1,
  "automated": true,
  "engine": "EML",
  "versionId": "1.0.2",
  "modelId": "uber_SSL_model_collimated.txt",
  "decision": "RELEASE",
  "releaseProbability": 0.9942,
  "investigateProbability": 0.0058,
  "fallback": false,
  "collimated": true,
  "laneWidthMeters": 5.0,
  "occupancyCount": "142",
  "alarmCategory": "Gamma",
  "primarySource": "NORM",
  "sources": {
    "NORM": 0.981
  }
}
```

---

## 6. Companion Documentation

- [Administrator Guide](../dist/release/DEPLOYMENT.md) — server setup, upgrades, TLS, and storage CLI
- [Backup, Restore, and Recovery](BACKUP_RESTORE.md) — `oscar_state` backup coverage (including `/var/lib/oscar/eml-plugin`)
- [Storage Architecture](STORAGE_ARCHITECTURE.md) — `PARQUET_PRIMARY` hot/cold observation storage and CQL pushdown
- [Operator Manual (English)](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README.md) ([Español](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_es.md), [Français](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_fr.md), [Ελληνικά](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_el.md))
