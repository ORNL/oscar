# OSCAR 3.12.2 Vehicle OCR Field Deployment, Tuning & Operations Guide

OSCAR 3.12.2 includes an optional, strictly opt-in, on-premise **Vehicle OCR** pipeline (`sensorhub-process-ocr` + `LaneSystem`) that asynchronously reads **ISO 6346 shipping container numbers** (with check-digit validation) and **license plates** from recorded occupancy camera clips — requiring zero external cloud services, zero GPU hardware, and zero runtime overhead on lanes where OCR is disabled.

> **Companion References:**
> - **Video Walkthroughs:** Watch [Module 17 — Vehicle OCR Auto-Fill, Multi-Pass Compare & Linked Adjudication](https://github.com/ORNL/oscar-video-guides/blob/main/videos/17-vehicle-ocr-and-adjudication.mp4), [Module 23 — Windows 11 Host Readiness & OCR Lane Scaling](https://github.com/ORNL/oscar-video-guides/blob/main/videos/23-windows-wsl2-host-readiness-and-ocr-scaling.mp4), and [Module 25 — Pluggable Runtime Extensions, OCR Packs & Offline Maps](https://github.com/ORNL/oscar-video-guides/blob/main/videos/25-pluggable-runtime-extensions-and-pmtiles.mp4) in [VIDEO_GUIDES.md](VIDEO_GUIDES.md).
> - **Custom Models & Regional Plate Rules:** See [Pluggable Extensions Guide — Section 4](PLUGGABLE_EXTENSIONS_GUIDE.md#4-creating--uploading-custom-vehicle-ocr-models--regional-plate-rules-ocr) to hot-swap `plate-rules.json`, custom `.onnx` model packs, or Java `OcrEngine` SPI plugins in **OSCAR Viewer -> Extensions (`/extensions`)**.

---

## 1. Camera Aiming, Optical Geometry & Stream Configuration

Accurate container and license-plate OCR depends far more on clean optical framing and shutter speed than on raw 4K resolution.

### 1.1 Recommended Camera Stream Profiles (`2` Cameras per Lane)

| Camera Role | Recommended Profile | Bitrate (per Camera) | Why It Works Best |
| :--- | :--- | :--- | :--- |
| **OCR Camera** *(Rear container stencil and/or front plate)* | **`1920×1080` (`1080p`) @ `15 fps`**, H.264 (`Main` / `High`), **`1 s` (`15`-frame) closed GOP**, max shutter **`<= 1/500 s`** (`<= 2 ms`) | `~2.5–4.0 Mbps` | Tier-0 (`CenterNet`) detects oriented ROIs at `640×384`, then crops and `AffineTransform`-deskews directly from the **native `1080p` frame** before `48 px` CTC / INT8 `PARSeq` recognition (with Tier-2 DBNet capped at `1600 px`). Preserves sharp stroke separation on boxed ISO 6346 check digits without the `2×`–`4×` decode and MP4-grace cost of `30 fps` or `4K`. |
| **Overview Camera** *(Situational awareness, non-OCR)* | **`1280×720` (`720p`) @ `15 fps`**, H.264, `1–2 s` closed GOP | `~1.0–2.0 Mbps` | Keeps aggregate 50-lane (100-camera) RTSP ingress within `~175–300 Mbps` (`< 30%` of `1 GbE`) and holds retained JPEG galleries to `~88–100 KiB/frame`. |
| **Wide-FOV Single-Mast OCR** *(Optional)* | **`2560×1440` (`1440p`) @ `15 fps`**, `1 s` closed GOP | `~4.0–6.0 Mbps` | Useful only when one distant mast camera must capture both an upper container stencil and a lower bumper plate while keeping character height above minimum thresholds. |

### 1.2 Field Aiming & Lighting Checklist

1. **Character Pixel Height:** Adjust lens zoom and camera distance so target characters measure at least **`24–32 px` tall** for ISO 6346 container owner/serial/boxed check-digit markings (`>= 18–24 px` tall for license plates).
2. **Eliminate Motion Blur:** Cap maximum exposure time at **`<= 1/500 s` (`<= 2 ms`)** (`<= 1/1000 s` on free-flow lanes above `20 mph / 32 km/h`). Avoid aggressive 3D temporal noise reduction (DNR), which smears moving stencils.
3. **Disable Smart Codec / Dynamic GOP:** Always lock H.264 to a **`1 s` closed GOP** (`15` frames at `15 fps`) and disable vendor "Smart Codec" / "Zipstream" GOP stretching so short `1–3 s` occupancies always include multiple crisp keyframes (see [Live Video Guide](LIVE_VIDEO.md)).
4. **Nighttime IR & Retroreflective Plates:** If license plates wash out into solid white rectangles under nighttime IR illuminators, enable the camera's LPR/WDR/headlight-compensation profile or lower IR LED gain rather than increasing exposure time.
5. **Mask Burned-In Camera OSD / Timestamps:** If the IP camera burns a persistent date/time or lane banner across the top or bottom border that creates false OCR tokens, either disable the camera's OSD or set `ignoreTopFraction` / `ignoreBottomFraction` (`0.0–0.45`) in the lane's **Vehicle OCR** tab.

---

## 2. Per-Lane Configuration (`OcrConfig`) & Operating Modes

Vehicle OCR is strictly opt-in per lane in **SensorHub Admin -> Lane System -> Vehicle OCR** (`com.botts.impl.system.lane.config.OcrConfig`). When `enabled = false` (default), the lane registers **no** `vehicleOcr` datastream, creates zero EventBus subscriptions, and loads zero ONNX sessions.

| Field | Default | Range / Behavior | Operational Guidance |
| :--- | :--- | :--- | :--- |
| **Enable Vehicle OCR (`enabled`)** | `false` | `true` / `false` | Master per-lane switch. |
| **Alarms Only (`alarmsOnly`)** | `true` | `true` / `false` | **`true` (recommended production default):** Runs OCR only on Gamma/Neutron alarm occupancies. **`false` (continual mode):** Scans every occupancy; ephemeral non-alarm MP4 clips are deleted immediately after sampling while keeping `occupancy.videoPaths = []` (zero non-alarm MP4 buildup). |
| **Model Directory (`modelDir`)** | `models/ocr` | Relative to node dir or absolute | Shipped ONNX model directory (`det.onnx`, `rec.onnx`, `dict.txt`, plus hybrid Tier-0/PARSeq models). Runtime overrides uploaded in `/extensions` take precedence automatically. |
| **Read Container Numbers (`readContainerIds`)** | `true` | `true` / `false` | Enables ISO 6346 container detection (`[A-Z]{3}[UJZ]` + 6 digits + check digit), single-character OCR confusion repair (`0<->O`, `1<->I`, `5<->S`, `8<->B`, `6<->G`) **only** when uniquely validated by the ISO 6346 check digit, and chassis tare/capacity filtering (`MAXGROSS`, `TARE`, `PAYLOAD`, `CU.CAP`). |
| **Read License Plates (`readPlates`)** | `true` | `true` / `false` | Enables license-plate extraction using shipped or `/extensions` regional `plate-rules.json`. |
| **Camera UIDs (`cameraUids`)** | `[]` *(all cameras)* | Optional allowlist of camera system UIDs | Populate with only the lane's OCR-aimed camera UID(s) when a lane also has overview cameras to cut per-occupancy decode work in half. |
| **Frames Per Clip (`framesPerVideo`)** | `6` | `1–12` | Uniformly samples keyframes across `12%–88%` of clip duration (skipping tractor entry `0%–10%` and exit `90%–100%`). Default `6` balances rear/side container coverage and latency (`~1.13 s/clip` on Ubuntu 24.04). |
| **Container Min Confidence (`containerMinConfidence`)** | `0.50` | `0.0–1.0` | Drops non-checksum container candidates below threshold; checksum-valid ISO 6346 containers remain prioritized. |
| **Plate Min Confidence (`plateMinConfidence`)** | `0.60` | `0.0–1.0` | Drops license-plate candidates below threshold. |
| **Ignore Top / Bottom Band Fraction** | `0.0` / `0.0` | `0.0–0.45` | Masks top/bottom percentage of every sampled frame to exclude burned-in camera timestamps or OSD labels. |

After modifying any lane's **Vehicle OCR** settings in SensorHub Admin, click **Apply Changes**, then **Save** (confirm **Yes** and wait for **SensorHub Configuration Saved**).

---

## 3. Resource Governance, Storage Lifecycle & Viewer Behavior

### 3.1 Asynchronous Singleton Worker & `OcrResourceGovernor`

All OCR-enabled lanes share **one** reference-counted ONNX Runtime model singleton (`OnnxOcrEngine.acquireShared`) and **one** bounded low-priority background `VehicleOcrProcessor` (`DEFAULT_QUEUE_CAPACITY = 32`, drop-oldest overflow backpressure, up to `MAX_PUBLISHED_CANDIDATES = 6` ranked candidates per occupancy, and a complete `Throwable` fault barrier so OCR errors never affect RPM telemetry, cameras, or SensorHub).

Before each job and between frames, `OcrResourceGovernor` checks live JVM and OS telemetry:

| Threshold Constant | Default | Governor Action |
| :--- | :--- | :--- |
| `DEFAULT_MAX_SYSTEM_CPU` | `85%` (`0.85`) | Defers job non-blockingly (`1,500 ms` delay, up to `8` deferrals) so live RPM ingestion, HLS streaming, and Parquet archiving keep priority. |
| `DEFAULT_MAX_PROCESS_CPU` | `80%` (`0.80`) | Same non-blocking deferral on the timer wheel. |
| `DEFAULT_MAX_HEAP_USED_RATIO` / `DEFAULT_MIN_FREE_HEAP_BYTES` | `85%` (`0.85`) / `96 MiB` | Defers job until GC reclaims headroom. |
| Critical Heap Pressure (`0.92` ratio or `< 48 MiB` free) | `92%` / `48 MiB` | Emits `SHED_HEAP_PRESSURE` and safely sheds the OCR task to prevent `OutOfMemoryError`. |

### 3.2 `PARQUET_PRIMARY` Storage, Evidence Crops & Viewer Auto-Fill

- **`vehicleOcr` datastream (`PARQUET_PRIMARY` `RAW_EVENTS`):** Published candidates (~`65 B`/row ZSTD Parquet) tier into `RAW_EVENTS -> DAILY_EVENTS -> MONTHLY_EVENTS` with selective `256`-byte `ocr_bloom` Bloom filters and `[ocr_min_norm, ocr_max_norm]` zone maps — adding `< 0.02 GiB/year` (`5` lanes) to `< 0.12 GiB/year` (`50` lanes) in `alarmsOnly = true` mode.
- **Date-partitioned JPEG evidence crops (`OcrCropRetention`):** Best-frame crops (~`2.3–2.7 KiB`/crop) are stored under `/sensorhub/buckets/ocr/crops/<YYYY-MM-DD>/obs-<base64url-obsId>_*.jpg`. `StoragePressureRetention` prunes expired date partitions in `O(days)` after **`ocrCropRetentionDays = 365`** (default), while **always protecting** crops whose occupancy still retains `frame-03.jpg`, carries a media hold, or has been adjudicated by an operator (reclaiming oldest eligible crops under `85% -> 80%` disk pressure).
- **Operator workflow in OSCAR Viewer:**
  - Opening `/event-details?eventId=<uuid>` automatically pre-fills **Vehicle ID** when the top candidate is a **checksum-valid ISO 6346 container** or a **license plate with `>= 0.85` confidence**, displays clickable suggestion chips with crop thumbnails, and lets operators run **Multi-Pass Vehicle Search**, **Compare Passes**, **Linked Adjudication**, **Consolidated `VEHICLE_INCIDENT` PDF/CSV/JSON/XLSX Reports**, and optional `±1`-character fuzzy **Cargo UFF** container correlation ([Cargo UFF Guide](CARGO_UFF_INTEGRATION.md)).

### 3.3 Platform Sizing: Ubuntu 24.04 vs. Windows 11 + WSL 2

| Portal Profile | Recommended OS | OCR Posture & Measured Behavior |
| :--- | :--- | :--- |
| **Type A (`1–8` lanes, e.g., `5–6` lanes)** | Ubuntu Server 24.04 LTS or Windows 11 Pro + WSL 2 (`8` cores, `32 GB` RAM, `12–16 GB` `.wslconfig`) | Supports `100%` per-lane OCR (`alarmsOnly = true` or `false`) at `~1.13–2.6 s/clip`, `~1.8–2.0 GiB` steady `oscar` `cgroup anon` RAM, `0` drops, `0` sheds. |
| **Type B (`9–50` lanes)** | **Ubuntu Server 24.04 LTS bare-metal** (`8` cores min for `alarmsOnly = true`; `12–16+` physical P-cores for `50/50` continual OCR) | Supports up to `50/50` OCR lanes at `~1.13 s/clip`, `~1.8–2.24 GiB` steady `oscar` `cgroup anon` RAM, `0` drops, `0` sheds, and `0%` non-alarm MP4 accumulation. |

*(See [Administrator Guide — Recommended Hardware and Capacity Sizing](../dist/release/DEPLOYMENT.md#recommended-hardware-and-capacity-sizing) and [Release Overview Section 3](RELEASE_NOTES_AND_UPGRADE_GUIDE.md#3-multi-year-system-resources--performance-projections-5-lane--50-lane-reference-deployments-with-hybrid-ocr) for full 10-year projections.)*

---

## 4. Offline Benchmarking (`OcrCli`) & Custom Model Packs

### 4.1 Benchmarking Recorded Site Footage Before Field Rollout (`OcrCli`)

Before enabling OCR across production lanes, test sample camera `.mp4`/`.avi` clips or still frames locally with the bundled `OcrCli` diagnostic tool (`OcrCli <modelDir> <image-or-mp4-path> [maxFrames]`), or run a labeled multi-video JSONL benchmark via Gradle (`:sensorhub-process-ocr:runBatchBench`):

```sh
# 1. Run unit tests and batch JSONL benchmark from a source checkout of ORNL/oscar:
./gradlew --no-parallel :sensorhub-process-ocr:test :sensorhub-system-lane:test
./gradlew --no-parallel :sensorhub-process-ocr:runBatchBench --args="/path/to/manifest.jsonl dist/models/ocr"

# 2. Or evaluate a single clip against an extracted release (or build/install/oscar):
java -cp 'osh-node-oscar/lib/*' \
  com.botts.impl.process.ocr.cli.OcrCli \
  osh-node-oscar/models/ocr \
  /path/to/sample_transit.mp4 \
  6
```

When running `OcrCli` manually inside a running `oscar-oscar-1` Docker container, **always** pass the managed native temp properties so JavaCPP never leaves shared-library symlinks inside `/var/lib/oscar/.javacpp` (which backup validation rejects):

```sh
docker cp /path/to/sample_transit.mp4 oscar-oscar-1:/tmp/sample_transit.mp4
docker exec oscar-oscar-1 java \
  -Djava.io.tmpdir=/run/oscar-native \
  -Dorg.bytedeco.javacpp.cachedir=/run/oscar-native/javacpp \
  -cp '/opt/oscar/lib/*' \
  com.botts.impl.process.ocr.cli.OcrCli \
  /opt/oscar/models/ocr \
  /tmp/sample_transit.mp4 \
  6
docker exec oscar-oscar-1 rm -f /tmp/sample_transit.mp4
```

Each output line reports `<idType> <normalizedValue> conf=<0..1> checksum=<true|false> hits=<N> raw="<rawText>"`.

### 4.2 Swapping Regional Plate Rules or Custom ONNX Models (`/extensions`)

To customize license-plate regular expressions/regional rules (`plate-rules.json`), upload replacement ONNX detector/recognizer packs (`.zip` / `.tar.gz`), or load a custom Java 21 `OcrEngine` SPI `.jar` plugin **without rebuilding Docker images or losing overrides on `oscar upgrade`**, follow **[Pluggable Extensions Guide — Section 4](PLUGGABLE_EXTENSIONS_GUIDE.md#4-creating--uploading-custom-vehicle-ocr-models--regional-plate-rules-ocr)** and verify changes in **OSCAR Viewer -> Extensions (`/extensions`)**.
