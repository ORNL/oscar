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

## 6. Developer API for Custom Alarm Assessment Algorithms (`EmlAlarmAssessmentAlgorithm`)

In addition to supporting external LLNL ERNIE VM-250 bundles (`config/vm250Analysis.xml` + `gov.llnl.ernie.*`), OSCAR 3.11.0 provides a clean, first-class plugin API so developers can create custom alarm assessment algorithms and upload them through the exact same **Services -> OSCAR Service -> EML Plugin Path** capability (`.jar`, `.zip`, `.tar.gz`, `.tgz`, or `.tar`).

Custom alarm assessment plugins run inside an isolated `URLClassLoader`, receive the per-lane calibration parameters and ordered Rapiscan daily-file occupancy lines on every `GX` (Gamma Exit) event, publish their output on the `emlAnalysis` and `emlContextual` datastreams (`PARQUET_PRIMARY`), and automatically trigger `t = 0` Dashboard suppression and **`Code 9999: EML Non-Threat`** adjudication whenever they return `result = "RELEASE"` with `fallback = false`.

### 6.1 Plugin Discovery Mechanisms

`EmlLoadedRuntime` automatically detects a custom alarm assessment algorithm when any uploaded archive (`.jar` or `.zip`/`.tar.gz` containing `jars/*.jar`) includes one of the following descriptors:

1. **JAR Manifest Attribute (`META-INF/MANIFEST.MF`) — Recommended for Zero-Dependency Standalone JARs:**
   ```text
   Manifest-Version: 1.0
   Oscar-Alarm-Assessment-Class: com.example.assessment.CustomSpectralAssessor
   ```
2. **Java `ServiceLoader` Descriptor (`META-INF/services/org.sensorhub.impl.utils.rad.eml.EmlAlarmAssessmentAlgorithm`):**
   ```text
   com.example.assessment.CustomSpectralAssessor
   ```
3. **Properties Descriptor (`META-INF/oscar-alarm-assessment.properties` or `config/oscar-alarm-assessment.properties`):**
   ```properties
   class=com.example.assessment.CustomSpectralAssessor
   ```

> **No XML/CSV Boilerplate Required:** When any of the three descriptors above is present, `EmlArchiveExtractor` and `EmlLoadedRuntime` do **not** require `config/vm250Analysis.xml`, `config/vm250LaneDatabase.xml`, or `config/CMU_metric.csv`. Any supplementary model weights or configuration files packaged in the archive are extracted into a private `0700` directory (`extractedPluginRoot`) and passed to `initialize(Path extractedPluginRoot)`.

### 6.2 Option A: Zero-Dependency Standalone Java Plugin (Standard JDK Only)

Developers can build a custom alarm assessment plugin using **only standard JDK 21 types** (`java.util.Map`, `java.util.List`, `java.nio.file.Path`) with zero compile-time dependencies on OSCAR or OpenSensorHub:

```java
package com.example.assessment;

import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public class CustomSpectralAssessor {

    // Optional lifecycle hook called once when the plugin is extracted and activated
    public void initialize(Path extractedPluginRoot) throws Exception {
        // Load any custom model files from extractedPluginRoot if needed
    }

    public String getVersionId() {
        return "1.0.0";
    }

    public String getCollimatedModelId() {
        return "custom-spectral-collimated";
    }

    public String getUncollimatedModelId() {
        return "custom-spectral-uncollimated";
    }

    /**
     * Thread-safe occupancy evaluation invoked on every Rapiscan GX (Gamma Exit) message.
     *
     * @param laneParams keys: "portId" (String), "laneId" (Integer), "collimated" (Boolean),
     *                   "laneWidth" (Double, meters), "intervals" (Integer, SG1), "occupancyHoldin" (Integer, SG1)
     * @param dailyFileLines ordered Rapiscan daily-file lines for the occupancy:
     *                       latest NS background, latest GS/GB background, and all scan lines from GS through GX
     * @return Map with assessment decision and probabilities (or null to skip publication)
     */
    public Map<String, Object> evaluate(Map<String, Object> laneParams, List<String> dailyFileLines) {
        boolean localizedSpike = dailyFileLines.stream()
                .filter(line -> line.startsWith("GA,"))
                .anyMatch(this::hasHighLocalizedDetectorRatio);

        double releaseProb = localizedSpike ? 0.03 : 0.98;
        double investigateProb = 1.0 - releaseProb;

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("result", localizedSpike ? "INVESTIGATE" : "RELEASE");
        result.put("fallback", false);
        result.put("releaseProbability", releaseProb);
        result.put("investigateProbability", investigateProb);
        result.put("primaryThreshold", 0.05);
        result.put("overallSourceType", localizedSpike ? "Threat" : "NORM");
        result.put("probabilityNORM", localizedSpike ? 0.02 : 0.98);
        result.put("probabilityThreat", localizedSpike ? 0.97 : 0.01);
        result.put("probabilityNonEmitting", 0.01);
        return result;
    }

    private boolean hasHighLocalizedDetectorRatio(String gaLine) {
        // Example: GA, HH:MM:SS,G1,G2,G3,G4
        String[] parts = gaLine.split(",");
        if (parts.length < 6) return false;
        double g1 = Double.parseDouble(parts[2].trim());
        double g2 = Double.parseDouble(parts[3].trim());
        return g2 > 0 && (g1 / g2) > 4.0;
    }

    public void close() {
        // Optional cleanup when plugin is unloaded or hot-swapped
    }
}
```

#### Packaging the Standalone Plugin JAR with Standard `javac` + `jar`

```sh
mkdir -p build/classes
javac --release 21 -d build/classes CustomSpectralAssessor.java
printf 'Manifest-Version: 1.0\nOscar-Alarm-Assessment-Class: com.example.assessment.CustomSpectralAssessor\n' > build/MANIFEST.MF
jar cfm custom-spectral-assessor-1.0.0.jar build/MANIFEST.MF -C build/classes .
```

Upload `custom-spectral-assessor-1.0.0.jar` in **SensorHub Admin -> Services -> OSCAR Service -> EML Plugin Path**, click **Apply Changes**, and click **Save Configuration**.

### 6.3 Option B: Typed OSCAR SPI (`org.sensorhub.impl.utils.rad.eml.EmlAlarmAssessmentAlgorithm`)

When compiling against `sensorhub-utils-rad`, developers can implement [`EmlAlarmAssessmentAlgorithm`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-utils-rad/src/main/java/org/sensorhub/impl/utils/rad/eml/EmlAlarmAssessmentAlgorithm.java) directly for compile-time type safety with [`EmlLaneParameters`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-utils-rad/src/main/java/org/sensorhub/impl/utils/rad/eml/EmlLaneParameters.java), [`EmlEvaluationResult`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-utils-rad/src/main/java/org/sensorhub/impl/utils/rad/eml/EmlEvaluationResult.java), and [`EmlSourceBreakdown`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-utils-rad/src/main/java/org/sensorhub/impl/utils/rad/eml/EmlSourceBreakdown.java):

```java
package com.example.assessment;

import org.sensorhub.impl.utils.rad.eml.EmlAlarmAssessmentAlgorithm;
import org.sensorhub.impl.utils.rad.eml.EmlEvaluationResult;
import org.sensorhub.impl.utils.rad.eml.EmlLaneParameters;
import org.sensorhub.impl.utils.rad.eml.EmlSourceBreakdown;

import java.nio.file.Path;
import java.util.List;

public class TypedAlarmAssessor implements EmlAlarmAssessmentAlgorithm {

    @Override
    public void initialize(Path extractedPluginRoot) throws Exception {
        // Optional startup initialization
    }

    @Override
    public String getVersionId() {
        return "2.0.0";
    }

    @Override
    public String getCollimatedModelId() {
        return "typed-collimated-v2";
    }

    @Override
    public EmlEvaluationResult evaluate(EmlLaneParameters params, List<String> dailyFileLines) {
        String model = params.collimated() ? getCollimatedModelId() : getUncollimatedModelId();
        double releaseProb = 0.985;
        double investigateProb = 0.015;
        EmlSourceBreakdown overall = new EmlSourceBreakdown(
                "NORM", model, 0.0, 0.0, 0.0, 0.0, 0.0, releaseProb, investigateProb);
        return new EmlEvaluationResult(
                getVersionId(), model, 0.05, params.portId(), params.laneId(),
                System.currentTimeMillis(), 1L, "ALARM", true, false, false,
                "RELEASE", false, "", investigateProb, releaseProb,
                true, false, 1, 5.0, "", List.of(overall), overall);
    }
}
```

Register the class in `META-INF/services/org.sensorhub.impl.utils.rad.eml.EmlAlarmAssessmentAlgorithm` (or `META-INF/MANIFEST.MF` `Oscar-Alarm-Assessment-Class`).

### 6.4 Input & Output Contract Summary

| Field / Key | Type | Description |
| --- | --- | --- |
| **Input `laneParams.portId`** | `String` | Rapiscan sensor module name (e.g. `"Rapiscan01"`). |
| **Input `laneParams.laneId`** | `int` | Numeric lane identifier configured on the Rapiscan driver. |
| **Input `laneParams.collimated`** | `boolean` | `true` when `emlConfig.isCollimated` is enabled on the lane. |
| **Input `laneParams.laneWidth`** | `double` | Configured lane width in meters (default `4.82`). |
| **Input `laneParams.intervals`** | `int` | Gamma background/smoothing intervals (automatically synchronized from daily `SG1`). |
| **Input `laneParams.occupancyHoldin`** | `int` | Occupancy hold-in count (automatically synchronized from daily `SG1`). |
| **Input `dailyFileLines`** | `List<String>` | Ordered Rapiscan daily-file lines (`NS`, `GS`, `GB`, `GA`, `NB`, `NA`, `GH`, `GL`, `NH`, `NL`, `GX`). |
| **Output `result`** | `String` | `"RELEASE"` (auto-adjudicates as **`Code 9999: EML Non-Threat`** when `fallback=false` and `exceptionMessage` is empty) or `"INVESTIGATE"` (keeps alarm active on the Dashboard). |
| **Output `fallback`** | `boolean` | When `true`, forces human review on the Dashboard even if `result` is `"RELEASE"`. |
| **Output `releaseProbability`** | `double` | Non-threat release probability in `[0.0, 1.0]`. |
| **Output `investigateProbability`** | `double` | Threat / investigation probability in `[0.0, 1.0]`. |
| **Output `primaryThreshold`** | `double` | Decision threshold reported in `emlContextual` and `Code 9999` feedback (default `0.05`). |
| **Output `overallSourceType`** | `String` | Dominant classification label (e.g. `"NORM"`, `"NonEmitting"`, `"Threat"`). |

---

## 7. Companion Documentation

- [Administrator Guide](../dist/release/DEPLOYMENT.md) — server setup, upgrades, TLS, and storage CLI
- [Backup, Restore, and Recovery](BACKUP_RESTORE.md) — `oscar_state` backup coverage (including `/var/lib/oscar/eml-plugin`)
- [Storage Architecture](STORAGE_ARCHITECTURE.md) — `PARQUET_PRIMARY` hot/cold observation storage and CQL pushdown
- [Operator Manual (English)](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README.md) ([Español](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_es.md), [Français](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_fr.md), [Ελληνικά](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/resources/com/botts/impl/service/oscar/i18n/README_el.md))
