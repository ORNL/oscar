# Cargo Non-Intrusive Inspection (WCO UFF 2.0 & 3.0) Integration Guide

OSCAR 3.11.12 integrates natively with commercial Cargo Non-Intrusive Inspection (NII) X-ray portals and mobile/rail scanners that publish **World Customs Organization (WCO) Unified File Format (`UFF 2.0` and `UFF 3.0.0`)** `.uff` inspection packages.

> **Zero-Clutter Shipped Default:** Most radiation portal deployments operate standalone RPMs and cameras without an NII X-ray scanner on day one. Cargo UFF share integration ships **disabled by default** (`enabled = false`). When disabled, OSCAR renders **zero extra buttons, columns, or banners** across the Dashboard, Event Log, Lane View, Navbar, and Event Details, and runs **zero background threads or network polls**. Operators at any site can still inspect individual `.uff` packages on demand at any time through the existing **Upload Files** button in **Secondary Inspection**.

---

## 1. Supported Standards & Commercial Share Topologies

OSCAR 3.11.12 parses both major WCO Unified File Format generations inside a single unified model without external native binaries:

| Capability | WCO `UFF 2.0` | WCO `UFF 3.0.0` |
| --- | --- | --- |
| **Root XML Schema** | `<UFF xmlns="UFF2">` + root `version` (`2.0`): `<Target>`, `<Scan>` (`<XraySystem>`, `<XRayFile>`, `<OcrResult>`, `<OutputFile>`), `<Analysis>` | `<UFF xmlns="UFF3">` + root `version` (`3.0.0`): `<Id>`, `<Target>` (`<Vehicle>`, `<Container>`, `<Declaration>`, `<Document>`), `<Scan>` (`<XraySystem>`, `<XRayFile>`, `<HEMDInfo>` / `<HEMDMap>` / `<ZMap>`, `<OcrResult>`, `<OutputFile>`), `<Analysis>` |
| **Primary Radiograph** | 16-bit unsigned grayscale TIFF (`uint16`, `0–65,535`, uncompressed, Deflate, or LZW with horizontal predictor) | 16-bit unsigned grayscale TIFF (`uint16`, `0–65,535`) with multi-view (`side`, `top`, `left`, `right`) and dual-energy metadata (`energiesMeV`, pixel pitch, scan speed) |
| **Material Discrimination** | Dual-energy / material overlay images where present | Palettized 8-bit **HEMD** (`<HEMD>`) PNG with explicit `<ZMap>` atomic-number (`Z_eff`) palette bands (`Organic`, `Inorganic / Mineral (NORM)`, `Metallic / High-Z`) |
| **Progressive Preview** | Optional 8-bit `preview.jpg` / `thumb.jpg` | Optional 8-bit `preview.jpg` (`< 200 ms` initial paint over WAN / Zero-Trust links prior to 16-bit `uint16` upgrade) |
| **Customs & Manifest** | `<CargoData>` container, consignor/consignee, HS code, goods description, and optional `.pdf` manifest | `<Vehicle>`, `<Declaration>` (`customsId`, `hsCode`, `goodsDescription`, `quantity`), and embedded Bill of Lading / Manifest `.pdf` |
| **OCR & Secondary Spectra** | Container / plate OCR text + crop JPEGs and embedded ANSI N42.42 (`.n42`) spectra | Multi-view `<OCRResult>` entries with confidence/crops, `<RadiationFile>` `.n42` spectra, and automated `<Analysis>` suspect `<Annotation>` bounding boxes |

### Supported Commercial NII Storage Topologies

OSCAR connects read-only to either:

1. **Authenticated SMBv2 / SMBv3 Network Shares (`sourceType = "smb"`, recommended):**
   - Connects directly in user space via `smbj` (`SMBv2.1` / `SMBv3.x`) with strict `4 s` TCP/session connect and `6 s` read timeouts so an offline NAS or scanner drop-folder never stalls portal monitoring or adjudication.
   - Requires **zero Linux `root` / `CAP_SYS_ADMIN` `mount.cifs` privileges** and **zero Windows service drive-letter mappings**, working identically inside Docker on Ubuntu Server 24.04 and Windows 11 WSL 2.
   - Supports both **CIP / NAS date-and-scanner hierarchies** (`\\nas.port.local\oscar-uff\2026\11\20\EAGLE-P60-LANE01\<uuid>.uff`) and **flat vendor hot-drop shares** (`\\scanner-drop.local\nii-hot-drop\<uuid>.uff`).
2. **Mounted / Local Host Directories (`sourceType = "local"`):**
   - Reads `.uff` packages from an administrator-mounted read-only host path inside `/var/lib/oscar/extensions/uff` (or an explicitly configured read-only mount), rejecting symlinks and path traversal (`..`).

---

## 2. Random-Access Indexing & Remote-Link Latency Architecture

Commercial `.uff` archives typically range from `8 MB` to `60 MB+` per cargo scan. Downloading complete archives during directory scans or over remote links would introduce unacceptable disk and network load. OSCAR eliminates that overhead at three layers:

1. **Trailing-64 KiB ZIP/ZIP64 Central Directory Reader (`UffZipReader`):**
   - Over SMBv2/SMBv3, OSCAR reads only the final `64 KiB` End-of-Central-Directory (EOCD / ZIP64 EOCD) block of each `.uff` file and streams only the `~2 KiB` `<uuid>.xml` entry into an XXE-hardened SAX/DOM parser.
   - A 160-scan (`~2 GB`) multi-scanner SMB archive indexes in `< 1 s` cold and `< 15 ms` warm via an incremental `(relativePath, sizeBytes, mtimeMillis)` cache (`/var/lib/oscar/extensions/uff/index-cache.json`).
2. **Progressive Two-Stage Radiograph Streaming (`CargoUffViewerDialog` + `Tiff16Decoder`):**
   - **Stage 0 (`< 200 ms` over LAN or remote Zero-Trust links):** Displays the archive's lightweight `preview.jpg` alongside parsed customs declaration, scanner metadata, and OCR candidates immediately.
   - **Stage 1 (Full 16-Bit Diagnostic Upgrade):** Streams the `uint16` TIFF (`xray/*.tif`) and palettized `HEMD` PNG (`xray/*_hemd.png`) on demand and renders interactive `0–65,535` Window/Level, Log-Attenuation, and `Z_eff` material stripping at `60 fps` on the browser GPU (`WebGL2` `R16UI` integer texture shader with automatic 2D Canvas `Uint32Array[65536]` LUT fallback).
3. **Zero-Download Adjudication Staging (`stage-for-adjudication`):**
   - Linking an SMB `.uff` scan to an alarm adjudication writes a `< 4 KB` `uff-link-<uuid>.uffref.json` descriptor into `buckets/adjudication` (plus any embedded Manifest `.pdf` and `.n42` spectrum for immediate Sandia WebID / offline nuclide analysis), leaving the multi-megabyte radiograph archive on the NAS while allowing 1-click 16-bit reopening from the **Adjudication Log**.

---

## 3. Administrator Setup (`/extensions` -> Cargo NII (WCO UFF))

1. Sign in to OSCAR Viewer as an **Administrator** and open **Runtime Extensions (`/extensions`)** from the left navigation drawer.
2. Select the **Cargo NII (WCO UFF)** tab.
3. Check **Enable Cargo UFF Share / Drop-Folder Integration** and choose **SMB Network Share (SMBv2/SMBv3)** (or **Mounted / Local Host Directory**).
4. Enter the read-only share parameters:
   - **SMB Share UNC or URL:** e.g., `\\nas.port.local\oscar-uff` (or `smb://nas.port.local/oscar-uff`)
   - **Optional Subfolder:** e.g., `smb-date-archive` or `2026/11` (leave blank to scan the share root)
   - **Domain / Workgroup:** e.g., `WORKGROUP` or `PORT.LOCAL`
   - **Read-Only Username & Password:** dedicated read-only SMB service account. OSCAR encrypts the SMB password at rest using **AES-256-GCM** (`/var/lib/oscar/extensions/uff/uff-config.json`), never returns plaintext secrets to browsers, and automatically scrubs SMB credentials in `SupportBundleRedactor` (`[REDACTED]`).
   - **Alarm Correlation Window (minutes):** default `60` minutes (`5–1440` min).
   - **Allow 1-Character OCR Fuzzy Matching:** enabled by default so common camera/stencil OCR confusions (`0↔O`, `8↔B`, `5↔S`, `2↔Z`, `1↔I`, `6↔G`) between the RPM lane camera and the X-ray portal still correlate automatically.
5. Click **Test Connection** to verify round-trip SMB latency, discovered `.uff` count, and a sample `UFF 2.0` / `UFF 3.0.0` header, then click **Save & Apply**.

![Cargo NII SMB Share Configuration in Runtime Extensions](https://raw.githubusercontent.com/ORNL/osh-oakridge-modules/main/docs/oscar-operator-manual/images/48-cargo-uff-smb-share-extension.png)

To return a node to its shipped zero-clutter state at any time, click **Disable & Clear Index** on the **Cargo NII (WCO UFF)** tab.

---

## 4. Commercial Operator Workflows

### Workflow A — Direct Local `.uff` Upload (Always Available, Even Without an SMB Share)

1. Open any alarm in **Event Details (`/event-details`)** and scroll to **Secondary Inspection**.
2. Click **Upload Files** and select a `.uff` file (`up to 200 MB`) from a workstation folder or USB transfer stick.
3. OSCAR automatically:
   - Extracts any embedded `.n42` radiation file from the `.uff` archive and queues it for **WebID** / offline photopeak isotope identification;
   - Populates **Vehicle ID** if untouched when the `.uff` contains container or license plate OCR;
   - Displays an **Inspect 16-Bit Radiograph** button directly on the uploaded file row.

### Workflow B — Automatic Container / Plate Correlation (With 1-Character OCR Fuzzy Tolerance)

1. When Cargo UFF share integration is enabled and an occupancy has a **Vehicle / Container ID** (from OSCAR's asynchronous lane OCR or operator entry), Event Details queries the indexed share within the configured correlation window.
2. When a matching `.uff` scan is found—either an exact ISO 6346 / plate match or a **1-character OCR confusable match** (`OCR ±1` badge)—OSCAR displays the **Correlated Cargo NII Scan** banner above the adjudication form showing the UFF version, scanner ID, and declared HS code / goods description.
3. Click **Open Cargo X-Ray** to inspect the 16-bit radiograph aligned with the RPM radiation profile, or click **Link to Adjudication** to attach the scan, manifest PDF, and any `.n42` spectrum in one click.

### Workflow C — Scanner / Time-Window Browser & Tier-1 UUID / Filename Lookup

Many commercial NII scans (**Tier-1 sparse scans**) are generated before customs declarations are filed or when wet/glare conditions prevent container OCR, leaving `<uuid>.uff` as the primary identifier on the X-ray console or paper handoff slip. OSCAR supports two fast lookup paths:

1. **In Event Details (`Browse Cargo UFF`):**
   - Click **Browse Cargo UFF** in **Secondary Inspection** to open the **Cargo UFF Share Browser**.
   - Filter by **Scanner Lane** (`EAGLE-P60-LANE01`, `HCVM-PORTAL-02`, `VACIS-M6500-03`, `RAIL-SCAN-04`, etc.) and **Time Window** around the RPM alarm timestamp (`±15m`, `±1h`, `±4h`, `±24h`, or `All`), **or** paste a raw UFF UUID, `<uuid>.uff` filename, or full Windows UNC path (`\\nas\oscar-uff\...\<uuid>.uff`) into the search box.
2. **In Event Log (`/event-log` Smart Omnibox):**
   - Paste a UFF UUID, `<uuid>.uff` filename, or UNC share path directly into the **Vehicle / Container ID** search bar on **Events (`/event-log`)** and click **Search**.
   - OSCAR resolves the `.uff` package immediately, displays a **UFF `<version>` · `<scanner>`** chip with **Open Cargo X-Ray**, and—when the `.uff` archive contains an OCR container or plate ID—automatically populates all matching RPM lane passes in the Event Log table.

![Cargo UFF Share Browser and 1-Character Fuzzy OCR Correlation](https://raw.githubusercontent.com/ORNL/osh-oakridge-modules/main/docs/oscar-operator-manual/images/50-cargo-uff-smb-picker-and-fuzzy-ocr.png)

---

## 5. 16-Bit Radiograph, HEMD Material & RPM Alignment Inspector

Inside **Cargo NII Radiograph & Material Inspector (`CargoUffViewerDialog`)**, operators have non-destructive diagnostic tools tailored for NORM vs. shielding/threat adjudication:

- **16-Bit Window / Level (`0 – 65,535`):** Drag the dual-thumb `uint16` range slider or click **Auto 2–98%**, **Light / Organic**, **Standard Cargo**, or **High Penetration** to reveal dense cargo interiors without 8-bit clipping.
- **Radiometric Transforms:** Toggle **Log Attenuation** (`-ln(I / I_0)` mass-thickness response), **Invert Polarity** (white-hot vs. black-hot attenuation), and **High-Z Strip** (dims low-density organic/mineral clutter to isolate dense metallic shielding `Z_eff >= 19`).
- **HEMD Effective Atomic-Number (`Z_eff`) Band Filters (`UFF 3.0.0`):** Independently toggle **Organic (`Z 1–9`)**, **Inorganic / NORM (`Z 10–18`, e.g., ceramics, fertilizer, kitty litter, stone)**, and **Metallic / High-Z (`Z >= 19`, e.g., lead, tungsten, steel, shielded sources)** overlays and adjust HEMD opacity.
- **Automated `<Analysis>` Annotations:** Toggle scanner vendor anomaly bounding boxes (`Suspect` / `Clear` assessment and confidence).
- **Longitudinal RPM Gamma & Neutron Alignment Strip:** Displays the occupancy's time-series **Gamma** and **Neutron** count profile directly underneath the cargo radiograph, with a **Flip Cab (`Cab Left` ↔ `Cab Right`)** toggle so operators can verify whether a localized gamma/neutron peak aligns spatially with homogeneous declared NORM cargo or a localized High-Z shielded anomaly.
- **Customs Declaration, Manifest PDF & OCR Verification:** Review `<Declaration>` consignor/consignee, HS code, goods description, and gross weight (`kg`), open embedded Manifest `.pdf` documents in a sandboxed viewer, inspect NII OCR crop thumbnails, and click **Apply to Vehicle ID** or **Link to Adjudication**.

![16-Bit Cargo X-Ray Radiograph, HEMD Material Overlay, and RPM Strip Alignment](https://raw.githubusercontent.com/ORNL/osh-oakridge-modules/main/docs/oscar-operator-manual/images/49-cargo-uff-16bit-xray-inspector.png)

---

## 6. Related Documentation

- [Pluggable Runtime Extensions & Regional Packs Guide](PLUGGABLE_EXTENSIONS_GUIDE.md)
- [Release Overview and Upgrade Guide](RELEASE_NOTES_AND_UPGRADE_GUIDE.md)
- [OSCAR Deployment Guide](../dist/release/DEPLOYMENT.md)
- [OSCAR How-To Video Guides (`#27`: Cargo UFF SMB & 16-Bit X-Ray Inspection)](VIDEO_GUIDES.md)
- [Regression Suite & Release Certification (`cargo-uff` scenario)](REGRESSION_AND_RELEASE_CERTIFICATION.md)
