# Adding Support for a Radiation Portal Monitor (RPM) or Radiation Detector

This developer and vendor integration guide explains how to add support in OSCAR (`3.11.2+`) for a new **Radiation Portal Monitor (RPM)**, **spectroscopic portal**, **area radiation monitor**, or **handheld/backpack radiation detector**.

Because OSCAR is built on [OpenSensorHub](https://github.com/ORNL/osh-core) and discovers radiation streams dynamically via **OGC SWE Common semantic property definitions** rather than hardcoded vendor names in the web client, any new sensor driver that publishes canonical `RADHelper` data structures automatically inherits:

- **`PARQUET_PRIMARY` Multi-Year Tiered Storage:** Automatic 30-minute `LOGGED` PostgreSQL stage partitioning, parity-verified Zstandard Apache Parquet archival (`~10–15x` compression), `< 0.5 ms` `oscar_obs_latest` lookups, and embedded DuckDB mixed hot/cold querying with zero SQL schema changes.
- **OSCAR Viewer Live & Historical UI (`en`, `es`, `fr`, `el`):** Live lane gamma/neutron/threshold strip charts, logarithmic/linear energy spectrograms, Status of Health connection/tamper/fault cards, Dashboard alarm queues, Event Details playback, QR air-gapped transfer, Multi-Pass Vehicle Comparison (`VehiclePassComparisonDialog`), and 6-type `PDF`/`CSV`/`JSON`/`XLSX` report generation—**with zero React/TypeScript changes required**.
- **Synchronized Lane Automation (for Portal RPMs):** Loopback `MediaMTX` RTSP camera clip capture, 5-frame sRGB JPEG evidence extraction (`RetainedMedia`), `Code 9998: Extended Occupancy Gamma Alarm` protection, optional `Code 9999: EML Non-Threat` evaluation, and optional asynchronous per-lane Container & License Plate OCR (`sensorhub-process-ocr`).

---

## 1. Choose the Right Integration Pattern

Before creating a new Java driver module, check which of the four integration paths matches the hardware and protocol:

| Scenario | Recommended Pattern | Reference Implementation | Recompile Required? |
| :--- | :--- | :--- | :--- |
| **0. Existing protocol or spectrum file, custom nuclide ID or alarm logic only** *(e.g., ANSI N42.42 / `.spe` / `.spc` uploads, RS350 spectra, or Rapiscan VM-250 `GX` frames)* | Upload an `isotope-library.json`, `SpectroscopyIdentificationAlgorithm` `.jar`, or `EmlAlarmAssessmentAlgorithm` `.jar` at **`OSCAR Viewer -> Extensions` (`/extensions`)** | [Pluggable Extensions Guide](PLUGGABLE_EXTENSIONS_GUIDE.md) · [EML Integration Guide](EML_INTEGRATION.md) | **No** *(hot-swappable at runtime; survives `oscar upgrade`)* |
| `1. Standalone or Mobile Radiation Detector / Backpack / Walker / Area Monitor` *(continuous counts, dose, spectra, and optional GPS fixes without vehicle occupancy gates or lane cameras)* | Implement `AbstractSensorModule<VendorConfig>` in `sensors/sensorhub-driver-<vendor>`, or wrap RS-350 / Kromek D5 walkers in [`MobileDetectorSystem`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-system-lane/src/main/java/com/botts/impl/system/lane/mobile/MobileDetectorSystem.java) (Section 4) | [`sensorhub-driver-kromek-d3s`](https://github.com/ORNL/osh-oakridge-modules/tree/main/sensors/sensorhub-driver-kromek-d3s) · [`sensorhub-driver-kromek-d5`](https://github.com/ORNL/osh-oakridge-modules/tree/main/sensors/sensorhub-driver-kromek-d5) · [`sensorhub-driver-rs350`](https://github.com/ORNL/osh-oakridge-modules/tree/main/sensors/sensorhub-driver-rs350) · [`sensorhub-driver-tstar`](https://github.com/ORNL/osh-oakridge-modules/tree/main/sensors/sensorhub-driver-tstar) | **No** for RS-350 / Kromek D5 walkers (`MobileDetectorSystem` built in); **Yes** for new vendor protocols |
| **2. Gross-Counting Portal RPM** *(portal reports occupancy start/end + gamma/neutron counts over TCP ASCII, Modbus TCP, UDP, RS-232/485, or HTTP/MQTT)* | Implement `AbstractSensorModule<VendorConfig>` + `OccupancyOutput` + `DailyFileJournalConnection`, plus `VendorRPMConfig` & `VendorStateManager` in `sensorhub-system-lane` | [`sensorhub-driver-rapiscan`](https://github.com/ORNL/osh-oakridge-modules/tree/main/sensors/sensorhub-driver-rapiscan) *(TCP stream)* · [`sensorhub-driver-aspect`](https://github.com/ORNL/osh-oakridge-modules/tree/main/sensors/sensorhub-driver-aspect) *(Modbus TCP)* | **Yes** *(driver + `LaneSystem` + CSV parser)* |
| **3. Spectroscopic Portal / Secondary Inspection RPM** *(portal streams continuous `foregroundReport` / `backgroundReport` channel spectra and triggers automatic WebID / photopeak nuclide ID)* | Implement `AbstractSensorModule<VendorConfig>` + companion `IProcessModule` occupancy synthesizer + register in `LaneSystem.WEBID_SENSORS` | [`sensorhub-driver-rs350`](https://github.com/ORNL/osh-oakridge-modules/tree/main/sensors/sensorhub-driver-rs350) + [`sensorhub-process-rs350-occupancy`](https://github.com/ORNL/osh-oakridge-modules/tree/main/processing/sensorhub-process-rs350-occupancy) | **Yes** *(driver + occupancy process + `LaneSystem` + CSV parser)* |

---

## 2. Canonical Output Names, SWE Common URIs & `PARQUET_PRIMARY` Routing

Two contracts make a new detector work seamlessly across OSCAR's storage engine and browser UI:

1. **Exact Output Name (`ISensorDataInterface.getName()`):** `OscarTieredObsStore` (`PARQUET_PRIMARY`, configured in [`TieredArchiveConfig.DEFAULT_OUTPUT_NAMES`](https://github.com/ORNL/osh-addons/blob/OSCAR/persistence/sensorhub-datastore-postgis/src/main/java/org/sensorhub/impl/datastore/postgis/archive/TieredArchiveConfig.java)) routes high-rate and evidentiary streams into 30-minute PostgreSQL stage partitions and Zstandard Parquet cold archives by matching the **output name**. Static singleton outputs such as `sensorLocation` intentionally stay in the parent `oscar.obs` table.
2. **SWE Common Semantic Definition URIs (`DataComponent.setDefinition(...)`):** OSCAR Viewer ([`Utilities.ts`](https://github.com/ORNL/oscar-viewer/blob/main/src/lib/data/oscar/Utilities.ts) and [`Constants.tsx`](https://github.com/ORNL/oscar-viewer/blob/main/src/lib/data/Constants.tsx)) discovers streams by inspecting `observedProperties[].definition` on each ConSys API datastream rather than matching vendor class names.

Use the helper builders in [`RADHelper`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-utils-rad/src/main/java/org/sensorhub/impl/utils/rad/RADHelper.java) (`org.sensorhub.impl.utils.rad.RADHelper`) and adhere to the table below:

| Canonical Output Name | Tiered in `PARQUET_PRIMARY`? | Required SWE Common `definition` URI(s) | Purpose in OSCAR |
| :--- | :---: | :--- | :--- |
| `gammaCounts` | **Yes** | `http://www.opengis.net/def/Alarm` **and** `.../GammaGrossCount` *(substring)* | 1 Hz (or sub-second) gross + per-pillar gamma counts and live alarm state (`RADHelper.DEF_GAMMA`, `RADHelper.DEF_ALARM`) |
| `gammaThreshold` | **Yes** | `http://www.opengis.net/def/Threshold` | Live background-derived gamma alarm threshold line overlaid on live/event charts (`RADHelper.DEF_THRESHOLD`) |
| `neutronCounts` | **Yes** | `http://www.opengis.net/def/Alarm` **and** `.../NeutronGrossCount` *(substring)* | Gross + per-pillar neutron counts and live neutron alarm state (`RADHelper.DEF_NEUTRON`, `RADHelper.DEF_ALARM`) |
| `speed` | **Yes** | `http://www.opengis.net/def/SpeedTime` *(or KPH/MPH child)* | Vehicle transit speed displayed on Live Lane, Event Details, and reports |
| `tamper` | **Yes** | `http://www.opengis.net/def/TamperStatus` | Enclosure/door tamper state surfaced on Status of Health and Lane Reports (`RADHelper.DEF_TAMPER`) |
| `connectionStatus` | **Yes** | `http://www.opengis.net/def/ConnectionStatus` *(or `.../property/OGC/0/ConnectionStatus`)* | Online/offline reachability badge on Dashboard & Status of Health *(coalesce steady-state heartbeats; emit transitions immediately)* |
| `sensorLocation` | Static *(parent `obs`)* | `http://www.opengis.net/def/property/OGC/0/SensorLocation` *(or `http://sensorml.com/ont/swe/property/LocationVector`)* | WGS84 `(lat, lon, alt)` coordinate for Dashboard, Site Map, and Operational View maps |
| `dailyFile` | **Yes** | `http://www.opengis.net/def/RPMMessage` *(or vendor subtype)* | Raw/normalized vendor message stream driving `OccupancyWrapper` state transitions and Event Details **Daily File** slices |
| `occupancy` | **Yes** *(+ `oscar_obs_overlay`)* | `http://www.opengis.net/def/PillarOccupancyCount` (`OccupancyOutput`) | Evidentiary pass record (`startTime`, `endTime`, `gammaAlarm`, `neutronAlarm`, `maxGammaCount`, `maxNeutronCount`, `videoPaths`, `adjudicatedIds`, `webIdObsIds`) |
| `foregroundReport` | **Yes** | `http://www.opengis.net/def/Duration` **+** `.../LinearSpectrum` **+** `.../Dose` | Spectroscopic foreground channel array, live/real duration, gross counts, and dose rate (triggers spectrogram UI) |
| `backgroundReport` | **Yes** | `http://www.opengis.net/def/Duration` **+** `.../LinearSpectrum` *(without `Dose`)* | Spectroscopic background reference channel array |
| `setupGamma` / `setupNeutron` | **Yes** | Vendor setup parameters (`nsigma`, background window, thresholds) | Historical audit trail of detector calibration/setup parameters |
| `location` | **Yes** | `http://www.opengis.net/def/property/OGC/0/SensorLocation` *(or WGS 84 lat/lon/alt vector)* | 1 Hz mobile GPS breadcrumb trail & alarm position fixes when `enableLocationOutput = true` on `MobileDetectorSystem` |
| `alarm` | **Yes** | `http://www.opengis.net/def/Alarm` *(and nuclide/category fields)* | Real-time spectroscopic/radiometric alarm state stream for mobile and spectroscopic detectors |
| `KromekDetectorRadiometricsV1Report` | **Yes** | `http://sensorml.com/ont/swe/property/KromekDetectorRadiometricsV1Report` | Kromek D5 1 Hz dose, dose rate, live time, gamma/neutron counts, and 4,096-channel `uint16` spectrum |
| `KromekSerialRadiometricStatusReport` | **Yes** | `http://sensorml.com/ont/swe/property/KromekSerialRadiometricStatusReport` | Kromek D5 1 Hz dose/gamma/neutron alarm flags, device timestamp, and embedded GPS latitude/longitude |

> **Important:** If you introduce a brand-new high-rate output name not listed in `TieredArchiveConfig.DEFAULT_OUTPUT_NAMES`, either reuse one of the canonical names above or add the new output name to `DEFAULT_OUTPUT_NAMES` in [`TieredArchiveConfig.java`](https://github.com/ORNL/osh-addons/blob/OSCAR/persistence/sensorhub-datastore-postgis/src/main/java/org/sensorhub/impl/datastore/postgis/archive/TieredArchiveConfig.java) so 1 Hz telemetry is never left unpartitioned in `ONLY oscar.obs`.

---

## 3. Step-by-Step Implementation Walkthrough

The steps below walk through adding a fictional vendor RPM (`AcmeRPM` / `sensorhub-driver-acme`). For a **standalone radiation detector** (Pattern 1), complete **Steps 1, 2, 7, 8, and 10** only. For a **full portal lane RPM** (Patterns 2 & 3), complete **all 10 steps**.

### Step 1 — Create the Sensor Driver Module (`ORNL/osh-oakridge-modules`)

Create `include/osh-oakridge-modules/sensors/sensorhub-driver-acme/` mirroring [`sensorhub-driver-aspect`](https://github.com/ORNL/osh-oakridge-modules/tree/main/sensors/sensorhub-driver-aspect) or [`sensorhub-driver-rapiscan`](https://github.com/ORNL/osh-oakridge-modules/tree/main/sensors/sensorhub-driver-rapiscan):

```text
include/osh-oakridge-modules/sensors/sensorhub-driver-acme/
├── build.gradle
└── src/
    ├── main/
    │   ├── java/com/botts/impl/sensor/acme/
    │   │   ├── AcmeActivator.java
    │   │   ├── AcmeConfig.java
    │   │   ├── AcmeDescriptor.java
    │   │   ├── AcmeSensor.java
    │   │   └── output/
    │   │       ├── GammaOutput.java
    │   │       ├── NeutronOutput.java
    │   │       ├── DailyFileOutput.java
    │   │       └── ConnectionStatusOutput.java
    │   └── resources/
    │       ├── META-INF/services/org.sensorhub.api.module.IModuleProvider
    │       └── com/botts/impl/sensor/acme/i18n/
    │           ├── ConfigMessages.properties
    │           ├── ConfigMessages_es.properties
    │           ├── ConfigMessages_fr.properties
    │           ├── ConfigMessages_el.properties
    │           ├── README.md
    │           ├── README_es.properties / README_es.md
    │           ├── README_fr.md
    │           └── README_el.md
    └── test/java/com/botts/impl/sensor/acme/
        └── AcmeSensorTest.java
```

1. **Dependencies (`build.gradle`):** Depend on `org.sensorhub:sensorhub-core`, `:sensorhub-utils-rad`, and any transport module (`sensorhub-comm-ip`, `sensorhub-comm-rxtx` for serial RS-232/485, or `j2mod` for Modbus TCP).
2. **`IModuleProvider` SPI:** Put the fully qualified `AcmeDescriptor` class name (`com.botts.impl.sensor.acme.AcmeDescriptor`) in `src/main/resources/META-INF/services/org.sensorhub.api.module.IModuleProvider` so OpenSensorHub discovers the driver automatically.
3. **`SensorConfig` (`AcmeConfig extends SensorConfig`):**
   - Annotate editable fields with `@DisplayInfo(label = "...", desc = "...")`.
   - Embed a standard `CommProviderConfig<?>` (`TCPCommProviderConfig`, `UDPCommProviderConfig`, `ModbusTCPCommProviderConfig`, or serial `RxtxSerialCommProviderConfig`) so connection timeouts and reconnect policies remain uniform.
   - Include `DailyFileJournalClientConfig dailyFileJournal = new DailyFileJournalClientConfig();` if the portal emits raw messages that should be journaled before parsing (Step 3).
4. **`AbstractSensorModule` (`AcmeSensor extends AbstractSensorModule<AcmeConfig>`):**
   - In `doInit()`, generate deterministic UIDs from `config.serialNumber`:
     ```java
     generateUniqueID("urn:osh:sensor:acme:", config.serialNumber);
     generateXmlID("Acme", config.serialNumber);
     ```
   - Wrap network/serial lifecycle in OpenSensorHub's [`RobustConnection`](https://github.com/ORNL/osh-core/blob/OSCAR/sensorhub-core/src/main/java/org/sensorhub/impl/module/RobustConnection.java) so unplugged cables, power-cycled portals, or switch reboots reconnect automatically in the background without crashing `LaneSystem` startup.
   - Ensure `doStop()` closes sockets cleanly, interrupts reader threads, and stops background executors so hot-reconfiguring a lane in SensorHub Admin never leaks threads or TCP sockets.

---

### Step 2 — Publish Standard SWE Common Outputs (`RADHelper` & `OccupancyOutput`)

Use [`RADHelper`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-utils-rad/src/main/java/org/sensorhub/impl/utils/rad/RADHelper.java) to construct each `AbstractSensorOutput<AcmeSensor>`:

- **Gross-Counting Outputs (`gammaCounts` & `neutronCounts`):**
  Include a sampling timestamp (`radHelper.createPrecisionTimeStamp()`), an alarm state field with definition `RADHelper.DEF_ALARM` (`http://www.opengis.net/def/Alarm`), a gross count field (`RADHelper.DEF_GAMMA` or `RADHelper.DEF_NEUTRON`), and per-detector/pillar counts (`gammaGrossCount1..N` / `neutronGrossCount1..N`).
  ```java
  RADHelper rad = new RADHelper();
  recordStruct = rad.createRecord()
      .name("gammaCounts")
      .label("Gamma Counts")
      .definition(RADHelper.DEF_GAMMA)
      .addField("samplingTime", rad.createPrecisionTimeStamp())
      .addField("alarmState", rad.createText().definition(RADHelper.DEF_ALARM).label("Alarm State").build())
      .addField("grossCount", rad.createQuantity().definition(RADHelper.DEF_GAMMA).uomCode("1/s").build())
      .build();
  ```
- **Occupancy Output (`occupancy`):**
  Reuse [`OccupancyOutput<AcmeSensor>`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-utils-rad/src/main/java/org/sensorhub/impl/utils/rad/output/OccupancyOutput.java) directly from `sensorhub-utils-rad` rather than writing a custom occupancy schema! Build each completed pass with [`Occupancy.Builder`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-utils-rad/src/main/java/org/sensorhub/impl/utils/rad/model/Occupancy.java) (`occupancyCount`, `startTime`, `endTime`, `samplingTime`, `gammaAlarm`, `neutronAlarm`, `maxGammaCount`, `maxNeutronCount`, `gammaBackground`, `neutronBackground`) and call `occupancyOutput.setData(occupancy)`. `OccupancyOutput` automatically stamps `PendingExtendedOccupancyAutoAdjudicationRegistry` (`Code 9998`) and `PendingEmlAutoAdjudicationRegistry` (`Code 9999`) markers before publishing to `EventBus`, and attaches camera `videoPaths` when `CameraRecordingCoordinator` finishes.
- **Spectroscopic Portal Outputs (`foregroundReport` & `backgroundReport`, Pattern 3):**
  Follow [`RS350Sensor`](https://github.com/ORNL/osh-oakridge-modules/tree/main/sensors/sensorhub-driver-rs350): publish `foregroundReport` containing `Duration` (`http://www.opengis.net/def/Duration`), `LinearSpectrum` (`http://www.opengis.net/def/LinearSpectrum`), and `Dose` (`http://www.opengis.net/def/Dose`), and `backgroundReport` containing `Duration` + `LinearSpectrum`. If the instrument emits ANSI N42.42 XML directly, parse it via thread-safe `RADHelper.getRadInstrumentData(xmlString)` and publish via [`N42Output`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-utils-rad/src/main/java/org/sensorhub/impl/utils/rad/output/N42Output.java).
- **Connection Heartbeat Hygiene (`connectionStatus`):**
  Publish state changes (`isConnected: true <-> false`) immediately, and coalesce unchanged steady-state heartbeats (for example, once every `15` minutes) so 50 lanes do not flood PostgreSQL with redundant `connectionStatus` rows.

---

### Step 3 — Crash-Safe Raw Telemetry Journaling (`DailyFileJournalConnection`)

For portal RPMs whose raw vendor messages form part of the evidentiary audit trail (like Rapiscan ASCII daily files, Aspect register snapshots, or RS350 message streams), wire [`DailyFileJournalConnection`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-utils-rad/src/main/java/org/sensorhub/impl/utils/rad/dailyfile/DailyFileJournalConnection.java) into the reader loop **before** parsing:

1. Open a `DailyFileJournalConnection` in `doStart()` bound to the lane's identifier and vendor format tag.
2. Call `dailyFileJournal.appendRaw(...)` as soon as each raw frame arrives off the socket/serial port, *before* running protocol parsing. `DailyFileJournalService` writes `CRC32C`-framed `.dailyfile-journal` segments to disk synchronously and rolls completed UTC days into immutable CSVs + SHA-256 `.manifest.v1.json` files under `files/dailyfiles/` (see [Daily-File Journal v1 Contract](https://github.com/ORNL/osh-oakridge-modules/blob/main/docs/daily-file-journal-v1.md)).
3. Also publish a `dailyFile` observation (`definition = http://www.opengis.net/def/RPMMessage`) for each state-relevant message so:
   - `OccupancyWrapper` receives real-time occupancy/alarm state transitions on `EventUtils.getDataStreamDataTopicID(rpmUid, "dailyFile")`, and
   - Event Details (`DailyFileSliceHandler`) can display historical raw vendor lines around any occupancy window across UTC midnight boundaries.

---

### Step 4 — Integrate with `LaneSystem` & Synchronized Camera/Alarm State (`sensorhub-system-lane`)

To make the new RPM selectable inside a **Lane Sensor System** (giving it synchronized RTSP cameras, 5-JPEG media retention, `Code 9998` extended-occupancy faults, Adjudication, and optional Vehicle OCR), update [`sensorhub-system-lane`](https://github.com/ORNL/osh-oakridge-modules/tree/main/sensors/sensorhub-system-lane):

1. **Add `AcmeRPMConfig` (`com.botts.impl.system.lane.config.AcmeRPMConfig extends RPMConfig`):**
   - Define any vendor-specific lane-wizard fields (e.g., unit address, collimation, polling rate) with `@DisplayInfo` annotations alongside inherited `remoteHost` and `remotePort`.
2. **Implement `AcmeStateManager` (`com.botts.impl.system.lane.helpers.occupancy.state.AcmeStateManager extends StateManager`):**
   - Override `parseDailyFile()`, `isOccupied()`, `isAlarming()`, and `isNonOccupied()` (compare [`AspectStateManager.java`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-system-lane/src/main/java/com/botts/impl/system/lane/helpers/occupancy/state/AspectStateManager.java) and [`RapiscanStateManager.java`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-system-lane/src/main/java/com/botts/impl/system/lane/helpers/occupancy/state/RapiscanStateManager.java)).
   - Register `if (sensor instanceof AcmeSensor) return new AcmeStateManager();` inside [`OccupancyWrapper.stateManagerFor(...)`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-system-lane/src/main/java/com/botts/impl/system/lane/helpers/occupancy/OccupancyWrapper.java).
   - Whenever `StateManager` transitions `NON_OCCUPANCY -> OCCUPANCY / ALARMING_OCCUPANCY -> NON_OCCUPANCY`, `OccupancyWrapper` automatically opens and closes `FFMPEGSensor` recordings across all lane cameras, runs the `extendedOccupancyThresholdMinutes` watchdog, attaches `videoPaths` (for alarms) or hands transient clips to `OcrHelper` (when `alarmsOnly = false`), and publishes the completed `Occupancy`.
3. **Register in [`LaneSystem.java`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-system-lane/src/main/java/com/botts/impl/system/lane/LaneSystem.java) & [`LaneEndpointSync.java`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-system-lane/src/main/java/com/botts/impl/system/lane/LaneEndpointSync.java):**
   - Add `ACME_URI = "urn:osh:sensor:acme"` and include `AcmeSensor` in `doInit()` member discovery, `handleLaneEvent()` lifecycle/removal/endpoint-sync checks, and `createRPMConfig(RPMConfig)` (`if (rpmConfig instanceof AcmeRPMConfig ...)`).
   - **Spectroscopic portals only (Pattern 3):**
     - If the hardware streams continuous spectra without native occupancy records, add a companion `IProcessModule` (modeled on `Rs350OccupancyProcessModule`) in `createOccupancyProcessConfig(...)` to synthesize `occupancy` and `dailyFile` transitions from foreground count-rate/sigma excursions.
     - Add `AcmeSensor.class` to `WEBID_SENSORS` in `LaneSystem.java` so `WebIdHelper` automatically submits each occupancy's foreground/background spectrum to `SpectroscopyRuntimeRegistry` / Sandia WebID / built-in photopeak identification and links the resulting `webIdAnalysis` observation ID onto `occupancy.webIdObsIds`.

---

### Step 5 — Add Bulk CSV Lane Spreadsheet Import (`sensorhub-service-oscar`)

Sites with `10–50` lanes provision and update lanes via CSV import (**SensorHub Admin -> Services -> OSCAR Service**). Update [`SpreadsheetParser.java`](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/java/com/botts/impl/service/oscar/spreadsheet/SpreadsheetParser.java) (and `SchemaV1.java` if optional vendor columns are needed):

```java
} else if (rpmType.equalsIgnoreCase("Acme")) {
    var acme = new AcmeRPMConfig();
    acme.remoteHost = row.get(SchemaV1.RPM_HOST);
    acme.remotePort = Integer.parseInt(row.get(SchemaV1.RPM_PORT));
    rpmConfig = acme;
}
```

Add a unit test in `SpreadsheetParserTest` verifying round-trip CSV parsing, validation errors on missing ports/hosts, and coexistence with `Rapiscan`, `Aspect`, and `RS350` rows.

---

### Step 6 — Verify Reports & Multi-Pass Vehicle Correlation (`sensorhub-service-oscar`)

- **Standard Reports (`RDS_SITE`, `LANE`, `EVENT`, `ADJUDICATION`, `ADJUDICATION_DETAILS`):** [`ReportDataAggregator.java`](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/java/com/botts/impl/service/oscar/reports/helpers/ReportDataAggregator.java) aggregates `occupancy`, `occupancyStatus`, `tamper`, `connectionStatus`, and `adjudication` streams generically across every `LaneSystem`, so standard reports work automatically once `OccupancyOutput` and status streams use the canonical definitions from Section 2.
- **Multi-Pass `VEHICLE_INCIDENT` Radiation Trace Overlay:** [`VehicleIncidentAggregator.java`](https://github.com/ORNL/osh-oakridge-modules/blob/main/services/sensorhub-service-oscar/src/main/java/com/botts/impl/service/oscar/vehicle/VehicleIncidentAggregator.java) extracts per-second `[timestampMs, gammaCounts, neutronCounts]` profiles during each pass window from `gammaCounts` + `neutronCounts` (gross-counting portals) or `foregroundReport` (spectroscopic portals). Verify in a JUnit test (`VehicleIncidentSearchAndReportTest`) that your `gammaCounts` / `neutronCounts` JSON field names (`grossCount` / `summedGammaCounts` or `linearSpectrum`) resolve cleanly in `VehicleIncidentAggregator`.

---

### Step 7 — Add 4-Language Admin Labels & In-UI `README` Tabs (`en`, `es`, `fr`, `el`)

OSCAR enforces 100% 4-language parity across English, Spanish (`es`), French (`fr`), and Greek (`el`) in both OSCAR Viewer and OpenSensorHub Vaadin Admin:

1. Create `ConfigMessages.properties`, `ConfigMessages_es.properties`, `ConfigMessages_fr.properties`, and `ConfigMessages_el.properties` under `src/main/resources/com/botts/impl/sensor/acme/i18n/` covering every public/inherited `@DisplayInfo` field on `AcmeConfig`, and add `AcmeRPMConfig.type.name` + field keys to `sensorhub-system-lane/.../config/i18n/ConfigMessages*.properties`.
2. Create plain-language `README.md`, `README_es.md`, `README_fr.md`, and `README_el.md` in the same `i18n/` resource folder explaining every setting, network port, and radiation term in plain operator language (displayed when an administrator clicks the **`README`** tab in `/sensorhub/admin`).
3. Register `"/com/botts/impl/sensor/acme/i18n/ConfigMessages"` and `AcmeConfig.class` in [`OakridgeSensorI18nTest.java`](https://github.com/ORNL/osh-oakridge-modules/blob/main/tools/sensorhub-webui-oscar/src/test/java/com/botts/ui/oscar/forms/OakridgeSensorI18nTest.java) (`BUNDLE_PATHS`, `MODULE_CONFIGS`, and `README_CONFIGS`) and `LaneConfigI18nTest.java`.

---

### Step 8 — Wire Into the Top-Level OSCAR Build & Field Discovery (`ORNL/oscar`)

1. **`include/osh-oakridge-modules/settings.gradle` & root `settings.gradle`:** Register `:sensorhub-driver-acme` pointing to `include/osh-oakridge-modules/sensors/sensorhub-driver-acme`.
2. **Root [`build.gradle`](https://github.com/ORNL/oscar/blob/main/build.gradle):** Add `implementation project(':sensorhub-driver-acme')` under `// Drivers` so `./build-all.sh` and `build-all.bat` bundle the driver JAR into `osh-node-oscar/lib/` inside `oscar-<version>.zip` and the `oscar:<version>` Docker image.
3. **Optional Field Port Discovery ([`dist/release/configure-ubuntu-host.sh`](https://github.com/ORNL/oscar/blob/main/dist/release/configure-ubuntu-host.sh)):** If the detector listens on a vendor-specific default TCP port not already scanned by `discover-devices` (`10001`, `1622`, `502`, `2101`, `4001`, `1001`), add that port to the `discover-devices` probe list so field engineers can locate unlabelled portals on DHCP-free sensor switches.

---

### Step 9 — Optional Custom Post-Processing via `/extensions` (Zero Core Forking)

If your detector also ships proprietary nuclide-identification algorithms, specialized photopeak libraries, or agency-specific non-threat suppression models that cannot be open-sourced under `MPL-2.0`:

- Keep the hardware transport and SWE Common sensor driver clean and open-source (Steps 1–8), and
- Package proprietary algorithms as upgrade-safe runtime plugins uploaded via **`OSCAR Viewer -> Extensions` (`/extensions`)** (`SpectroscopyIdentificationAlgorithm` `.jar` / `isotope-library.json` for spectroscopy, or `EmlAlarmAssessmentAlgorithm` `.jar` for portal alarm assessment). See the [Pluggable Runtime Extensions & Regional Packs Guide](PLUGGABLE_EXTENSIONS_GUIDE.md) and [EML Integration & Custom Alarm Assessment Plugin Guide](EML_INTEGRATION.md) for complete SPI interfaces and manifest contracts.

---

### Step 10 — Test, Emulator-Certify & Validate Packaging

Run the verification suite from the `ORNL/oscar` checkout root before opening a pull request:

```bash
# 1. Driver protocol replay, state-machine, report, and 4-locale Admin UI / README parity tests
./gradlew --no-parallel \
  :sensorhub-driver-acme:test \
  :sensorhub-system-lane:test \
  :sensorhub-service-oscar:test \
  :sensorhub-webui-oscar:test

# 2. Viewer locale & component checks (confirming zero broken stream discovery assumptions)
(cd web/oscar-viewer && npm run validate:locales && npm test)

# 3. Release metadata, link hygiene, and full distribution build + packaged layout verification
node tools/validate-release-metadata.js
./build-all.sh
```

For full 50-lane continuous soak and fault-injection certification, add a deterministic protocol emulator mode in [`ORNL/oscar-regression`](https://github.com/ORNL/oscar-regression) (see [End-to-End Regression & Release Certification Guide](REGRESSION_AND_RELEASE_CERTIFICATION.md)) exercising:

1. Normal background -> non-alarming occupancy -> gamma alarm -> neutron alarm -> gamma+neutron alarm transitions,
2. Extended occupancy (`> extendedOccupancyThresholdMinutes`) verifying `Fault - Extended Occupancy` + `Code 9998` on gamma-only exit and **no** auto-adjudication when `neutronAlarm = true`,
3. Cable-disconnect / TCP reset recovery (`connectionStatus` `false -> true` without duplicate listener threads or leaked sockets), and
4. `PARQUET_PRIMARY` 30-minute partition sealing, mixed hot/cold Event Log queries, and `RDS_SITE` / `LANE` / `EVENT` / `VEHICLE_INCIDENT` report generation.

---

## 4. Mobile Detector System (`MobileDetectorSystem` — RS-350 Backpack & Kromek D5 Walkers)

OSCAR includes a dedicated first-class system module—**Mobile Detector System** ([`MobileDetectorSystem.java`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-system-lane/src/main/java/com/botts/impl/system/lane/mobile/MobileDetectorSystem.java), SensorML system definition `http://sensorml.com/ont/swe/system/MobileDetectorLane` and keyword `oscar:mobile-detector:true`; see [`README-mobile-detector.md`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-system-lane/README-mobile-detector.md))—for deploying wearable **RS-350** backpacks and handheld **Kromek D5** RIID walkers alongside fixed vehicle portals:

- **Curated SensorHub Admin Provisioning (`MobileDetectorConfigForm`):**
  - In **SensorHub Admin (`/sensorhub/admin`)**, right-click **Sensors -> Add New Module -> Mobile Detector System**.
  - [`MobileDetectorConfigForm`](https://github.com/ORNL/osh-oakridge-modules/blob/main/tools/sensorhub-webui-oscar/src/main/java/com/botts/ui/oscar/forms/MobileDetectorConfigForm.java) presents only mobile-applicable settings: **Module Name** (`12` characters or fewer, for example `Walker01`), **Unique ID** (mapped to `urn:osh:system:lane:<uniqueID>`), optional **Operational View Keys**, and **Detector Connection** (**RS-350 Backpack** or **Kromek D5** plus **Remote Host** and **Remote Port**, such as `198.51.100.40` port `10110` or `10111`).
  - `MobileDetectorSystem.doInit()` automatically enables `outputs.enableLocationOutput = true` on the underlying `RS350Config` or `D5Config` child driver so live GPS `location` fixes stream without manual submodule edits, while fixed-portal RS-350 and Kromek D5 lanes keep `enableLocationOutput = false` cleanly separated. Fixed-portal options that do not apply to walkers—RTSP cameras (`ffmpegConfig = null`), **Vehicle OCR** (`ocrConfig.enabled = false`), **Extended Occupancy** (`isExtendedOccupancyMonitoringEnabled() == false`, preventing false `Fault - Extended Occupancy` or `Code 9998` dispositions), **WebRelay-Quad** (`webRelayConfig.enabled = false`), and static portal coordinates—are automatically suppressed.
- **26-Stream `PARQUET_PRIMARY` Archival & Indoor / No-GPS Liveness Fallback:**
  - `TieredArchiveConfig.DEFAULT_OUTPUT_NAMES` includes all **26** operational, evidentiary, and mobile datastreams (adding `location`, `alarm`, `KromekDetectorRadiometricsV1Report`, and `KromekSerialRadiometricStatusReport`), ensuring 1 Hz GPS trails, radiometric status reports, and 1,024-/4,096-channel spectra seal into 30-minute stage partitions and Zstandard Parquet cold archives without growing `ONLY oscar.obs`.
  - When an operator walks indoors or under dense canopy where GPS fixes are unavailable (`(0, 0)` or omitted), Status of Health (`/health`) and `/lane-view` sustain `Online` heartbeat liveness via incoming `foregroundReport` (RS-350) or `KromekDetectorRadiometricsV1Report` / `KromekSerialRadiometricStatusReport` (Kromek D5) observations, displaying **Indoor / GPS unavailable** while suppressing portal-only fault columns.
- **Live `/map` Crumb Trails, Hotspot Alarm Popups & `/lane-view` Spectroscopy:**
  - **Map (`/map` & Custom Dashboard Map Widgets):** Plots live walker markers, configurable 1 Hz GPS breadcrumb trails (`trailLength = 300` fixes by default), and geo-pinned mobile alarm hotspot markers (`today`, `1h`, `8h`, or `24h` window) color-coded by adjudication status with one-click popups into event inspection and episode adjudication.
  - **Lane View (`/lane-view`):** Replaces fixed-portal camera tiles with a live **Mobile Detector** telemetry summary card (dose rate in `µSv/h`, gamma/neutron counts, live WGS 84 coordinates or indoor status, and alarm badge) paired with interactive logarithmic/linear **1,024-channel** ANSI N42.42 spectra + automatic `WebID` / photopeak nuclide identification for **RS-350** backpacks and **4,096-channel** real-time spectra (`KromekDetectorRadiometricsV1Report`) for **Kromek D5** walkers.
- **Reference Protocol Simulators (`tools/mobile-detector-mocks/`):**
  - `tools/mobile-detector-mocks/rs350_mock.py`: Zero-dependency Python TCP server (`default :10110`) streaming 1 Hz `STX (0x02) .. ETX (0x03)` framed ANSI N42.42-2011 XML documents along a synthetic waypoint loop with 1,024-channel linear / 256-channel compressed spectra, GPS coordinates, and `1/r²` `Cs-137` / `Co-60` hotspot `<RadAlarm>` blocks (`python3 tools/mobile-detector-mocks/rs350_mock.py --port 10110`).
  - `tools/mobile-detector-mocks/d5_mock.py`: Zero-dependency Python TCP server (`default :10111`) implementing Kromek's binary serial protocol over RFC 1055 SLIP (`0xC0 .. 0xC0` delimiters) in response to 1 Hz driver polls for `0x07/0xC2` `RadiometricsV1` (`4,096 × uint16` spectrum + dose/counts), `0x08/0x82` `RadiometricStatus` (alarm flags + GPS lat/lon), `0x07/0xC5` battery/temperature status, and `0x07/0xC7` device identity (`python3 tools/mobile-detector-mocks/d5_mock.py --port 10111`).

> **Captioned Video Walkthrough (`#33`):** Watch **[Module 33 — Configure & Track Mobile Radiation Detectors (RS-350 Backpack & Kromek D5) (`33-mobile-radiation-detectors.mp4`)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/33-mobile-radiation-detectors.mp4)** ([WebVTT captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/33-mobile-radiation-detectors.vtt)) in [VIDEO_GUIDES.md](VIDEO_GUIDES.md#33-mobile-radiation-detectors).
