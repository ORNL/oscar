# OSCAR 3.11.9 Pluggable Runtime Extensions & Regional Packs Guide

OSCAR 3.11.9 ships out of the box with complete, unrestricted default implementations for **Vehicle Container & License Plate OCR**, **Basemap Layers**, **Secondary-Inspection Gamma Spectroscopy**, **TLS Certificate Trust**, and **Adjudication Disposition Codes**—so every fresh installation and upgrade works immediately with zero extra downloads.

At the same time, sites operating in non-Latin license-plate regions, air-gapped border facilities without internet map tiles, specialized radiological laboratories, private-PKI enterprise networks, or agencies with standardized national disposition taxonomies can hot-swap or extend any of these subsystems from the browser at **`OSCAR Viewer -> Extensions` (`/extensions`)** (or via the authenticated `/sensorhub/oscar/extensions/*` REST API) **without recompiling OSCAR and without losing customizations across `oscar upgrade`**. *(Developers or hardware vendors adding a new physical Radiation Portal Monitor or radiation detector protocol should see the companion [Radiation Portal Monitor & Detector Driver Integration Guide](RADIATION_DETECTOR_DRIVER_GUIDE.md).)*

---

## 1. Summary of Pluggable Extension Domains

| Domain | Shipped Default *(Active on Fresh `init` & Unmodified `upgrade`)* | Uploadable Extension Formats | Persistent Host/Volume Path *(Never Overwritten by `upgrade`)* | 1-Click Reset Behavior |
| :--- | :--- | :--- | :--- | :--- |
| **1. Vehicle OCR (`ocr`)** | Bundled clean-room `Apache-2.0` / `CC0` hybrid ONNX pipeline (`stencil_det_fp32.onnx` + `PP-OCRv3` CTC + INT8 `PARSeq` + `DBNet`) + `PlateRuleSet.DEFAULT` (ISO 6346 Modulo-11 containers + `4–10` char Latin/alphanumeric plates) | **Data-only pack** (`.zip`, `.tar.gz`, or `.json` with `plate-rules.json` and/or custom `.onnx` + dict) **or** Java 21 **`OcrEngine` SPI `.jar`** | `/var/lib/oscar/extensions/ocr/` *(in `oscar_oscar_state`)* | Unloads custom pack/JAR and restores bundled ONNX models + `PlateRuleSet.DEFAULT` immediately |
| **2. Offline Regional Maps (`maps`)** | Online OpenStreetMap Streets + Esri World Imagery + uploaded Site Diagrams | **PMTiles v3 (`.pmtiles`)** vector (`MVT`) or raster (`PNG`, `JPEG`, `WEBP`) single-file archives (up to `16 GiB`/upload via UI, arbitrary size on disk) | Tiles: `/var/lib/oscar/extensions/maps-storage/` *(in `oscar_oscar_state`)*<br>Active state: `/var/lib/oscar/extensions/maps/.active.json` | Clears default offline `.pmtiles` selection and returns to shipped OpenStreetMap/Esri defaults (individual `.pmtiles` archives can also be deleted) |
| **3. Secondary Spectroscopy (`spectroscopy`)** | Sandia Full Spectrum WebID (`WebIdClient`) + `.n42`/`.spe`/`.spc`/`.xml` parser + built-in offline photopeak fallback | **`isotope-library.json`** photopeak pack (`.json`, `.zip`, `.tar.gz`) **or** Java 21 **`SpectroscopyIdentificationAlgorithm` SPI `.jar`** (`fallback` or `override` mode) | `/var/lib/oscar/extensions/spectroscopy/` *(in `oscar_oscar_state`)* | Unloads custom library/SPI and restores standard Sandia WebID + built-in photopeak fallback |
| **4. Enterprise CA Trust (`trusted-certs`)** | Standard Linux/JVM system `cacerts` root store | Public X.509 Root / Intermediate CA certificates (`.pem`, `.crt`, `.cer`; private keys strictly rejected) | `/var/lib/oscar/extensions/trusted-certs/` *(in `oscar_oscar_state`)* | Removes uploaded custom CAs and reloads clean JVM `cacerts` trust store |
| **5. Adjudication Policy Packs (`policy-packs`)** | ANSI/OSCAR Disposition Codes `1–11`, `Code 9998: Extended Occupancy Gamma Alarm`, `Code 9999: EML Non-Threat`, plus `config.customAdjudicationCodes` | **`policy-pack.json`** (`.json` or `.zip`) defining agency disposition codes, categories, and `en`/`es`/`fr`/`el` labels | `/var/lib/oscar/extensions/policy-packs/` *(in `oscar_oscar_state`)* | Removes active policy pack and republishes built-in codes + `config.customAdjudicationCodes` |
| **6. EML Alarm Assessment (`eml`)** | Core portal gross-count & `N-Sigma` alarming (`Code 9999` inactive until a licensed LLNL EML or custom `.jar` is uploaded) | Separately licensed LLNL ERNIE VM-250 archive **or** custom **`EmlAlarmAssessmentAlgorithm` `.jar`** (see [EML Integration Guide](EML_INTEGRATION.md)) | `/var/lib/oscar/eml-plugin/` *(in `oscar_oscar_state`)* | Unloads EML/custom JAR from memory and deletes the stored plugin archive |
| **7. Cargo NII (`uff`)** | **Disabled (`enabled = false`)** — `0` extra UI buttons/columns, `0` background threads, and `0` network polls (local `.uff` upload in Secondary Inspection remains available) | Read-only **SMBv2/SMBv3 network share** (`\\nas\oscar-uff`) or mounted directory serving **WCO `UFF 2.0` & `UFF 3.0.0`** `.uff` archives (see [Cargo UFF Integration Guide](CARGO_UFF_INTEGRATION.md)) | `/var/lib/oscar/extensions/uff/` (`uff-config.json` AES-256-GCM + `index-cache.json` in `oscar_oscar_state`) | Disables share correlation, clears the incremental index cache, and restores zero-clutter default |

---

## 2. Browser Management (`OSCAR Viewer -> Extensions`, `/extensions`)

Any signed-in OSCAR **Administrator** can manage all six extension domains from a single accessible workspace at **`https://<oscar-host>/extensions`** (**Extensions** in the OSCAR Viewer navigation bar), localized in **English, Spanish, French, and Greek** (`en`, `es`, `fr`, `el`):

![Pluggable Runtime Extensions & Regional Packs Hub](https://raw.githubusercontent.com/ORNL/osh-oakridge-modules/main/docs/oscar-operator-manual/images/46-runtime-extensions-hub.png)

![Air-Gapped Offline PMTiles Regional Basemap on Map View](https://raw.githubusercontent.com/ORNL/osh-oakridge-modules/main/docs/oscar-operator-manual/images/47-offline-pmtiles-basemap.png)

> **Captioned Video Walkthrough (`#25`, `20.7s`):** Watch **[Swap Pluggable OCR Packs & Air-Gapped Regional .pmtiles Basemaps](VIDEO_GUIDES.md#25-pluggable-runtime-extensions-and-pmtiles)** ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/25-pluggable-runtime-extensions-and-pmtiles.mp4) · [WebVTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/25-pluggable-runtime-extensions-and-pmtiles.vtt), also bundled offline in-app via **Help (`?`)** on `/extensions` and `/map`).

1. **Live Status & Provenance Badges:** Every tab clearly indicates whether the subsystem is currently running its **Shipped Built-In Default** or a **Custom Override**, along with the active package filename, SHA-256 digest, version/rule counts, and load timestamp.
2. **Streaming Upload with Progress:** Select a compliant archive or configuration file and upload it directly from the browser with live byte-level progress reporting (`<progress>`), server-side structural/magic-byte validation, and atomic activation—no container restart or shell access required.
3. **1-Click Reset to Shipped Default:** Every tab includes a confirmed **Reset to Shipped Default** action that immediately reverts to OSCAR's built-in implementation if a custom model, map, certificate, or policy pack needs to be rolled back.

---

## 3. Upgrade-Safe Persistence & Backup Guarantees

OSCAR separates shipped container binaries (`/app/...` inside the read-only image layers) from persistent administrator extensions:

- **Preserved Across Every `oscar upgrade`:**
  - `/var/lib/oscar/extensions/{ocr,maps,maps-storage,spectroscopy,trusted-certs,policy-packs}/` and `/var/lib/oscar/eml-plugin/` reside inside the external named Docker volume **`oscar_oscar_state`**, which `oscar upgrade` mounts intact and never formats or overwrites (keeping `OSCAR_ARCHIVE_DIR` reserved exclusively for verified `datasets/` cold Parquet archives).
  - On startup (`OSCARServiceModule.doStart()` -> `RuntimeExtensionsManager.initialize()`), OSCAR inspects each domain's `.active.json` state file. Whenever a valid custom extension is present, OSCAR activates that custom extension automatically; whenever no custom extension is configured, OSCAR runs the latest shipped built-in default from the upgraded image.
- **Included Automatically in Backups & Bare-Metal Restores:**
  - Both [Single-Snapshot Backups](BACKUP_RESTORE.md) (`oscar backup` / `oscar restore`) and [Continual & Occasional USB NVMe Incremental Backups](CONTINUAL_AND_USB_BACKUP_GUIDE.md) (`usb-backup` / `/usb-backups`) capture `oscar_oscar_state` (including `/var/lib/oscar/extensions/` and `/var/lib/oscar/eml-plugin/`).
  - Continual and occasional USB NVMe backups catalog `extensions/maps-storage/*.pmtiles` inside **`packs/state/`** with `O(1)` filename+size+mtime skip checks—so multi-gigabyte regional map archives are copied to the USB SSD **only once** when uploaded or changed, never re-streamed on every 15-minute delta sync, and restored automatically during `usb-backup restore`.

---

## 4. Creating & Uploading Custom Vehicle OCR Models & Regional Plate Rules (`ocr`)

By default, per-lane Vehicle OCR (`LaneConfig.ocrConfig`) runs OSCAR's bundled hybrid ONNX pipeline and `PlateRuleSet.DEFAULT`. You can customize OCR at two levels:

### Option A — Data-Only Model & Regional Plate-Rules Pack (`.zip`, `.tar.gz`, or `.json`) *(Recommended — Zero Java Code)*

A data-only OCR pack lets you adapt character sets, plate validation regular expressions, ISO 6346 container rules, and/or ONNX detection/recognition weights without writing Java. **Any `.onnx` model or dictionary file you omit from your archive is inherited automatically from OSCAR's shipped `models/ocr` defaults.**

#### Pack Directory Layout

Download a ready-to-edit starter pack directly from **`/extensions -> OCR Models & Engines -> Download Starter Pack (`.zip`)`** (`/sensorhub/oscar/extensions/templates/ocr-pack.zip`), or create a `.zip` / `.tar.gz` containing any combination of the following files at the archive root (you can also upload a standalone `plate-rules.json` file directly if you only want to change plate validation/formatting rules):

```text
my-regional-ocr-pack.zip
├── manifest.json                  # Optional metadata & inheritBuiltinModels flag
├── plate-rules.json               # Optional regional license-plate & ISO 6346 filter rules
├── det.onnx                       # Optional DBNet text detector replacement
├── rec.onnx                       # Optional CTC text recognizer replacement
├── dict.txt                       # Optional UTF-8 CTC character dictionary (1 token per line)
├── stencil_det_fp32.onnx          # Optional Tier-0 640x384 oriented CenterNet ROI detector
├── parseq_rec_int8.onnx           # Optional gated 32x128 PARSeq recognizer
└── parseq_vocab.txt               # Optional PARSeq token vocabulary
```

#### `manifest.json` Schema

```json
{
  "schemaVersion": 1,
  "packId": "mena-gcc-ocr-v1",
  "version": "1.2.0",
  "inheritBuiltinModels": true,
  "notes": "Supports 2-to-7 digit numeric plates alongside ISO 6346 containers while inheriting shipped ONNX weights"
}
```

#### `plate-rules.json` Schema & Regional Examples

`PlateRuleSet` controls how raw OCR tokens are normalized, filtered, and accepted as license plates alongside ISO 6346 containers:

```json
{
  "ruleSetId": "gcc-numeric-and-multilingual-v1",
  "description": "GCC Pure-Numeric + Multilingual Plates + ISO 6346",
  "minLength": 2,
  "maxLength": 10,
  "asciiOnly": false,
  "requireLetter": false,
  "requireDigit": true,
  "rejectIsoContainerArtifacts": true,
  "allowedRawRegex": "^[\\p{L}\\p{N}\\s\\-.]{2,14}$",
  "allowPatterns": [
    "^[0-9]{2,7}$",
    "^[\\p{L}\\p{N}]{4,10}$"
  ],
  "rejectExact": [
    "TARE",
    "GROSS",
    "PAYLOAD",
    "MAXGROSS",
    "NETWT",
    "CBM",
    "CUFT"
  ]
}
```

| Field | Default | Purpose |
| :--- | :--- | :--- |
| `ruleSetId` / `description` | `"shipped-default"` | Identifier and human-readable label surfaced in `/extensions` status and audit logs. |
| `minLength` / `maxLength` | `4` / `10` | Minimum and maximum normalized character count for non-container license plates. Lower `minLength` (for example, `2` or `3`) in jurisdictions with short diplomatic or numeric plates. |
| `asciiOnly` | `true` | Set to `false` to preserve non-ASCII Unicode letters (`\p{L}`, such as Greek, Cyrillic, Arabic, or Hangul characters emitted by a custom `dict.txt`) instead of restricting to `A–Z` / `0–9`. |
| `requireLetter` | `true` | Set to `false` in regions that issue pure-numeric plates (such as Gulf Cooperation Council states or port tractor fleet numbers). |
| `requireDigit` | `true` | Set to `false` if vanity or alphabetic-only plates must be accepted. |
| `rejectIsoContainerArtifacts` | `true` | Rejects partial ISO 6346 fragments and container door capacity/weight markings from being misclassified as license plates. |
| `allowedRawRegex` | Built-in alphanumeric pattern | Pre-normalization regular expression checked against candidate raw OCR tokens. |
| `allowPatterns` | `[]` *(any)* | Optional list of regular expressions; when non-empty, a normalized plate candidate must match at least one pattern. |
| `rejectExact` | Built-in container weight/capacity words | Exact uppercase tokens rejected as non-plate container door markings (`TARE`, `MAXGROSS`, `PAYLOAD`, `NETWT`, etc.). |

#### ONNX Tensor Contracts for Custom `.onnx` Models

If you train or export replacement `.onnx` models (for example, from **PaddleOCR v3/v4** via `paddle2onnx` or **PyTorch** via `torch.onnx.export` using ONNX opset `11`–`17`), conform to these input/output tensor signatures:

1. **`rec_model.onnx` + `rec_dict.txt` (CTC Line Recognizer):**
   - **Input (`x`):** `float32` tensor of shape `[1, 3, 48, W]` (channel order `BGR`, normalized `(pixel / 255.0 - 0.5) / 0.5` to `[-1.0, 1.0]`, dynamic width `W` up to `320+`).
   - **Output:** `float32` tensor of shape `[1, T, V]` (probabilities or logits; CTC blank token at index `0`, dictionary line `i` (`1`-based) in `rec_dict.txt` mapped to index `i`).
   - **`rec_dict.txt`:** UTF-8 text file with one character/symbol per line (`\n`-delimited, no blank lines).
2. **`det_model.onnx` (DBNet Full-Frame Text Detector):**
   - **Input (`x`):** `float32` tensor of shape `[1, 3, H, W]` (`H` and `W` multiples of `32`, ImageNet-normalized `mean=[0.485, 0.456, 0.406]`, `std=[0.229, 0.224, 0.225]`).
   - **Output:** `float32` probability map of shape `[1, 1, H, W]` in `[0.0, 1.0]`.

---

### Option B — Custom Java 21 `OcrEngine` SPI Plugin (`.jar`)

When you want to replace the entire inference pipeline (for example, wrapping a custom multi-stage vision model, OpenVINO/ONNX graph, or hardware-specific recognizer), package a Java 21 `.jar` implementing [`com.botts.impl.process.ocr.engine.OcrEngine`](https://github.com/ORNL/osh-oakridge-modules/blob/main/processing/sensorhub-process-ocr/src/main/java/com/botts/impl/process/ocr/engine/OcrEngine.java):

```java
package org.example.oscar.ocr;

import com.botts.impl.process.ocr.domain.OcrResult;
import com.botts.impl.process.ocr.domain.PlateRuleSet;
import com.botts.impl.process.ocr.domain.VehicleIdType;
import com.botts.impl.process.ocr.engine.OcrEngine;
import java.awt.Rectangle;
import java.awt.image.BufferedImage;
import java.time.Instant;
import java.util.List;

public final class CustomRegionalOcrEngine implements OcrEngine {

    @Override
    public OcrResult recognizeFrame(BufferedImage frame, Instant frameTime) {
        // Run your custom detector + recognizer on `frame`.
        // Return null or OcrResult.empty(frameTime) when no plate/container is legible.
        String normalizedText = "MSCU5285725";
        double confidence = 0.96;
        VehicleIdType idType = PlateRuleSet.DEFAULT.isValidIso6346(normalizedText)
                ? VehicleIdType.CONTAINER_ISO6346
                : VehicleIdType.LICENSE_PLATE;
        return new OcrResult(
                normalizedText,
                idType,
                confidence,
                idType == VehicleIdType.CONTAINER_ISO6346,
                new Rectangle(120, 80, 320, 96),
                frameTime,
                List.of(normalizedText));
    }

    @Override
    public String getEngineName() {
        return "CustomRegionalOcrEngine/1.0";
    }

    @Override
    public void close() {
        // Release any native sessions or thread pools when hot-reloaded or reset.
    }
}
```

Register your implementation **either** in `META-INF/MANIFEST.MF`:

```text
Manifest-Version: 1.0
Oscar-Ocr-Engine-Class: org.example.oscar.ocr.CustomRegionalOcrEngine
```

**or** in `META-INF/services/com.botts.impl.process.ocr.engine.OcrEngine`:

```text
org.example.oscar.ocr.CustomRegionalOcrEngine
```

**Compliance Requirements for `OcrEngine` JARs:**
- Target **Java 21** (`--release 21`), provide a public no-argument constructor (or `(Path extractedPluginDir)` constructor if bundling weight files inside the JAR/ZIP), and ensure `recognizeFrame(...)` is **thread-safe** across concurrent `OcrResourceGovernor` worker threads.
- Implement `close()` cleanly so native tensors/sessions are freed when an administrator hot-swaps or resets the OCR extension.
- OSCAR automatically handles video sampling, `OcrResourceGovernor` CPU/heap backpressure, JPEG crop retention (`/sensorhub/buckets/ocr/crops/`), and `PARQUET_PRIMARY` `vehicleOcr` storage around your `OcrEngine`.

---

## 5. Generating & Uploading Offline Regional Basemaps (`maps`, `.pmtiles`)

On fresh installations, OSCAR's Dashboard, Map, and Operational View maps use online OpenStreetMap Streets and Esri World Imagery tiles (plus any site diagram images uploaded in SensorHub Admin). For **air-gapped deployments**, **restricted border LANs**, or **high-resolution regional/drone orthomosaics**, administrators can upload single-file **PMTiles v3 (`.pmtiles`)** archives in **`/extensions -> Offline Maps`**.

### How `.pmtiles` Basemaps Work in OSCAR 3.11.9

- **Zero External Network Calls (100% Air-Gapped Safe):**
  - **Vector `.pmtiles` (`MVT`)** render directly onto HTML5 `<canvas>` in the browser using `protomaps-leaflet` with local system UI fonts (`sans-serif`)—making **zero** outbound requests to `protomaps.github.io`, `openstreetmap.org`, or external glyph/sprite CDNs.
  - **Raster `.pmtiles` (`PNG`, `JPEG`, `WEBP`)** render directly via `pmtiles` Leaflet raster layers for satellite imagery, aerial photography, or nautical/topographic charts.
- **Authenticated HTTP `206 Partial Content` Serving:** OSCAR validates the 127-byte PMTiles v3 header (`PMTiles\x03`, tile type, min/max zoom, bounding box, center coordinates) on upload, stores the archive in `/var/lib/oscar/extensions/maps-storage/<filename>.pmtiles`, and serves only the requested `16–64 KiB` zoom/tile byte ranges via `/sensorhub/oscar/extensions/maps/tiles/<filename>.pmtiles` (`Accept-Ranges: bytes`, `ETag`).
- **Default Offline Basemap & Layer Switcher:** Every uploaded `.pmtiles` archive appears automatically in the Leaflet layer control across Dashboard, Map, and Operational Views. Clicking **Set as Default Basemap** makes that `.pmtiles` archive the initial active basemap on every operator workstation (eliminating failed internet tile requests on air-gapped networks) while keeping tight lane-extent auto-zoom (`fitBounds`) and site diagrams intact.

### Three Ways to Create a Compliant `.pmtiles` File for Your Region

#### Recipe 1 — Extract Any Country, State, or Port Region in Seconds with `pmtiles` CLI *(Fastest Vector Basemap)*

On an internet-connected staging laptop, install the official [`go-pmtiles`](https://github.com/protomaps/go-pmtiles/releases) single binary and slice your exact bounding box (`minLon,minLat,maxLon,maxLat`) from a Protomaps OpenStreetMap build:

```bash
# Example: Extract a regional vector basemap (zooms 0-16) for a port corridor
pmtiles extract \
  https://build.protomaps.com/20261101.pmtiles \
  port-region-streets.pmtiles \
  --bbox=-85.10,35.75,-83.70,36.25 \
  --maxzoom=16
```

Upload `port-region-streets.pmtiles` in **`/extensions -> Offline Maps`** and click **Set as Default Basemap**.

#### Recipe 2 — Build Completely Offline from an OpenStreetMap `.osm.pbf` Extract with `tilemaker`

If you already have a Geofabrik regional `.osm.pbf` file:

```bash
tilemaker \
  --input region-latest.osm.pbf \
  --output region-vector.pmtiles \
  --config resources/config-openmaptiles.json \
  --process resources/process-openmaptiles.lua
```

#### Recipe 3 — Convert High-Resolution Drone / Satellite GeoTIFF Orthomosaics to Raster `.pmtiles`

To turn a georeferenced facility aerial GeoTIFF (`site-ortho.tif`) into a multi-zoom offline satellite layer up to zoom `20`:

```bash
# 1. Reproject to Web Mercator (EPSG:3857) and build XYZ/MBTiles pyramid
gdalwarp -t_srs EPSG:3857 -r bilinear site-ortho.tif site-ortho-3857.tif
gdal_translate -of MBTiles -co TILE_FORMAT=WEBP -co QUALITY=85 site-ortho-3857.tif site-ortho.mbtiles
gdaladdo -r average site-ortho.mbtiles 2 4 8 16 32

# 2. Convert MBTiles -> PMTiles v3
pmtiles convert site-ortho.mbtiles site-ortho-imagery.pmtiles
```

---

## 6. Custom Secondary-Inspection Spectroscopy & Nuclide Libraries (`spectroscopy`)

When operators upload secondary-inspection spectra (`.n42`, Ortec `.spe`, Ortec/Canberra `.spc`, or `.xml`) in Event Details or Adjudication, OSCAR runs Sandia Full Spectrum WebID (`WebIdClient`) when configured and automatically falls back to its built-in photopeak classifier when offline.

In **`/extensions -> Spectroscopy`**, administrators can upload either a **JSON photopeak isotope library** or a **Java 21 `SpectroscopyIdentificationAlgorithm` `.jar`**, and choose between two execution modes:
- **`fallback` *(Default)*:** Queries Sandia Full Spectrum WebID first when reachable and runs your custom classifier whenever WebID is unconfigured, unreachable, or returns empty identifications.
- **`override`:** Always executes your custom classifier/SPI first for deterministic offline/agency-standardized nuclide identification without calling external WebID endpoints.

### Option A — Custom Photopeak Library (`isotope-library.json` or `.zip`)

Download a starter template from **`/extensions -> Spectroscopy -> Download Template (`.json`)`** (`/sensorhub/oscar/extensions/templates/isotope-library.json`) and customize your target nuclides:

```json
{
  "schemaVersion": 1,
  "libraryId": "port-customs-riid-v1",
  "version": "1.0.0",
  "executionMode": "fallback",
  "defaultWindowKeV": 22.0,
  "defaultMinSnr": 3.5,
  "isotopes": [
    {
      "name": "Cs-137",
      "category": "Industrial",
      "energiesKeV": [661.7],
      "windowKeV": 20.0,
      "minSnr": 3.5
    },
    {
      "name": "Co-60",
      "category": "Industrial",
      "energiesKeV": [1173.2, 1332.5],
      "windowKeV": 24.0,
      "minSnr": 3.5
    },
    {
      "name": "U-235",
      "category": "SNM",
      "energiesKeV": [143.8, 185.7, 205.3],
      "windowKeV": 14.0,
      "minSnr": 4.5
    }
  ]
}
```

Valid `category` values align directly with OSCAR's adjudication & UpSet reporting categories: `SNM`, `Nuclear`, `Industrial`, `Medical`, `NORM`, or `Unknown`.

### Option B — Custom Java 21 `SpectroscopyIdentificationAlgorithm` SPI Plugin (`.jar`)

Implement [`org.sensorhub.impl.utils.rad.webid.SpectroscopyIdentificationAlgorithm`](https://github.com/ORNL/osh-oakridge-modules/blob/main/sensors/sensorhub-utils-rad/src/main/java/org/sensorhub/impl/utils/rad/webid/SpectroscopyIdentificationAlgorithm.java) and declare `Oscar-Spectroscopy-Class` in `META-INF/MANIFEST.MF` (or `META-INF/services/org.sensorhub.impl.utils.rad.webid.SpectroscopyIdentificationAlgorithm`):

```java
package org.example.oscar.spectroscopy;

import java.util.List;
import org.sensorhub.impl.utils.rad.webid.SpectroscopyAnalysisInput;
import org.sensorhub.impl.utils.rad.webid.SpectroscopyIdentificationAlgorithm;
import org.sensorhub.impl.utils.rad.webid.WebIdAnalysis;

public final class CustomDeconvolutionClassifier implements SpectroscopyIdentificationAlgorithm {

    @Override
    public WebIdAnalysis analyze(SpectroscopyAnalysisInput input) throws Exception {
        // Inspect input.foregroundCounts(), input.energyCalibrationCoeffs(),
        // input.liveTimeSeconds(), input.realTimeSeconds(), or input.rawFileBytes().
        return WebIdAnalysis.builder()
                .isotopes(List.of())
                .drfUsed("CustomDeconvolution/1.0")
                .chiSquare(1.02)
                .build();
    }

    @Override
    public String getAlgorithmName() {
        return "CustomDeconvolutionClassifier/1.0";
    }
}
```

---

## 7. Trusted Enterprise CA Certificates (`trusted-certs`)

Organizations running internal Active Directory Certificate Services (AD CS), FreeIPA, Smallstep, or government PKI authorities for **Corporate OIDC SSO** (`OidcClientHelper`), **internal HTTPS Sandia WebID servers** (`WebIdClient`), or federated endpoints can upload public X.509 CA certificates (`.pem`, `.crt`, or `.cer`, single cert or CA chain bundle) in **`/extensions -> Trusted CAs`**:

- **Zero-Restart Hot Reload:** `DynamicTrustManagerRegistry` builds a composite `X509TrustManager` combining standard JVM `cacerts` with all certificates in `/var/lib/oscar/extensions/trusted-certs/` and hot-swaps the active `SSLContext` immediately upon upload or removal.
- **Strict Private-Key Rejection:** Any file containing `PRIVATE KEY` PEM headers or PKCS#8/PKCS#12 private key material is rejected with `HTTP 400` before touching disk.
- **Audit Fingerprints:** Every trusted CA displays its Subject DN, Issuer DN, `notBefore` / `notAfter` validity window, and `SHA-256` fingerprint.

---

## 8. Agency Adjudication Code & Policy Packs (`policy-packs`)

In addition to editing individual custom disposition codes in SensorHub Admin, agencies managing multiple ports of entry can standardize disposition codes, secondary-inspection requirements, and localized (`en`/`es`/`fr`/`el`) operator wording by uploading (or exporting) a **`policy-pack.json`** file in **`/extensions -> Policy Packs`**:

```json
{
  "schemaVersion": 1,
  "packId": "customs-border-sop-2026",
  "version": "2026.1",
  "agencyName": "National Port Authority Secondary Inspection",
  "codes": [
    {
      "code": 101,
      "label": "Verified Medical Isotope Patient Permit"
    },
    {
      "code": 102,
      "label": "Manifested Agricultural Fertilizer (NORM)"
    }
  ],
  "operatorChecklist": [
    "Confirm container or license plate against OCR crop and manifest.",
    "Upload handheld secondary N42 spectrum before clearing Industrial/SNM alarms."
  ]
}
```

- **Reserved Built-In Codes Protected:** Codes `1–11`, `9998` (`Extended Occupancy Gamma Alarm`), and `9999` (`EML Non-Threat`) are reserved so historical reports and automated dispositions remain unambiguous; custom policy-pack codes must use integer codes `>= 12` (excluding `9998` and `9999`).
- **Live Republication & Reporting:** Uploading or resetting a Policy Pack immediately republishes `AdjudicationCodesOutput` to connected browsers over ConSys/MQTT and registers code labels across **Events** (`Adjudication Code` filter), **Adjudication Reports**, **Adjudication Details**, and **Vehicle Incident Reports** (`PDF`, `CSV`, `JSON`, `XLSX`).
- **1-Click Export:** Click **Export Active Policy Pack (`.json`)** on a reference node to download its custom codes as a ready-to-distribute `policy-pack.json` for sister sites.

---

## 9. Unified EML Alarm Assessment (`eml`) & REST API Reference

For full developer instructions on packaging licensed LLNL ERNIE VM-250 archives or building standalone `EmlAlarmAssessmentAlgorithm` `.jar` plugins, see the [EML Integration & Custom Alarm Assessment Plugin Guide](EML_INTEGRATION.md). Administrators can upload, inspect, or unload EML plugins either in **`/extensions -> EML Assessment`** or in SensorHub Admin (**Services -> OSCAR Service**).

### Authenticated REST Endpoints (`/sensorhub/oscar/extensions/*`)

All mutating endpoints (`POST`) and administrative status/template endpoints require an authenticated **Administrator** session (plus `X-Requested-With: OSCAR-Viewer` or `XMLHttpRequest` CSRF protection on `POST` requests). Operator map endpoints (`GET /maps/active` and `GET /maps/tiles/*`) allow any signed-in OSCAR user (`Viewer`, `Operator`, or `Administrator`) so operator browsers can render offline `.pmtiles` basemaps seamlessly:

| Method & Path | Role | Description |
| :--- | :--- | :--- |
| `GET /sensorhub/oscar/extensions/status` | `Administrator` | Returns unified JSON status across `ocr`, `maps`, `spectroscopy`, `trustedCerts`, `policyPacks`, and `eml`. |
| `GET /sensorhub/oscar/extensions/maps/active` | Any signed-in user | Returns public active offline `.pmtiles` layer metadata (`active`, `tileType`, `minZoom`, `maxZoom`, `bounds`, `tileUrl`). |
| `GET /sensorhub/oscar/extensions/maps/tiles/<fileName>.pmtiles` | Any signed-in user | Serves `HTTP 200` / `HTTP 206 Partial Content` (`Range: bytes=start-end`) with `ETag` for Leaflet `pmtiles` / `protomaps-leaflet`. |
| `GET /sensorhub/oscar/extensions/templates/{ocr-pack.zip,isotope-library.json,policy-pack.json}` | `Administrator` | Downloads starter templates for compliant OCR packs, photopeak libraries, and policy packs. |
| `POST /sensorhub/oscar/extensions/ocr/upload?filename=<name>` | `Administrator` | Raw binary body upload (`.zip`, `.tar.gz`, `.tgz`, `.jar`, or `.json`) to activate a custom OCR model/rules pack or `OcrEngine` SPI plugin. |
| `POST /sensorhub/oscar/extensions/ocr/action` | `Administrator` | JSON `{"action":"reset"}` — resets Vehicle OCR to shipped built-in ONNX models + `PlateRuleSet.DEFAULT`. |
| `POST /sensorhub/oscar/extensions/maps/upload?filename=<name>.pmtiles&defaultBasemap=true` | `Administrator` | Raw binary upload of a PMTiles v3 archive into `/var/lib/oscar/extensions/maps-storage/` and optional default activation. |
| `POST /sensorhub/oscar/extensions/maps/action` | `Administrator` | JSON `{"action":"activate","fileName":"..."}`, `{"action":"set-default","defaultBasemap":true}`, `{"action":"delete-pack","fileName":"..."}`, or `{"action":"reset"}`. |
| `POST /sensorhub/oscar/extensions/spectroscopy/upload?filename=<name>&executionMode=fallback\|override` | `Administrator` | Uploads an `isotope-library.json` pack or `SpectroscopyIdentificationAlgorithm` `.jar`. |
| `POST /sensorhub/oscar/extensions/spectroscopy/action` | `Administrator` | JSON `{"action":"set-mode","executionMode":"fallback"\|"override"}` or `{"action":"reset"}`. |
| `POST /sensorhub/oscar/extensions/trusted-certs/upload?filename=<name>.pem` | `Administrator` | Uploads public X.509 CA certificate(s) and hot-reloads `DynamicTrustManagerRegistry` (rejects private keys). |
| `POST /sensorhub/oscar/extensions/trusted-certs/action` | `Administrator` | JSON `{"action":"delete-cert","fileName":"..."}` or `{"action":"reset"}`. |
| `POST /sensorhub/oscar/extensions/policy-packs/upload?filename=<name>.json` | `Administrator` | Activates a `policy-pack.json` (or `.zip`) and republishes `AdjudicationCodesOutput` live. |
| `GET /sensorhub/oscar/extensions/policy-packs/export` | `Administrator` | Downloads the currently active disposition policy pack as JSON. |
| `POST /sensorhub/oscar/extensions/policy-packs/action` | `Administrator` | JSON `{"action":"reset"}` — restores shipped disposition codes + `config.customAdjudicationCodes`. |
| `POST /sensorhub/oscar/extensions/eml/upload?filename=<name>.jar` | `Administrator` | Uploads and hot-loads an EML or custom `EmlAlarmAssessmentAlgorithm` archive (`POST .../eml/action` with `{"action":"reset"}` unloads it). |

See also the [Administrator Guide](../dist/release/DEPLOYMENT.md), [EML Integration Guide](EML_INTEGRATION.md), and [Continual & Occasional USB NVMe Incremental Backup Guide](CONTINUAL_AND_USB_BACKUP_GUIDE.md).
