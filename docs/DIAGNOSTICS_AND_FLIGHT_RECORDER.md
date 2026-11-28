# OSCAR Diagnostic Flight Recorder & Redacted Support Bundle Guide

OSCAR 3.12.2 includes a built-in, zero-configuration **Diagnostic Flight Recorder** and **Redacted Support Bundle (`.zip`)** system spanning both the browser console (`SupportDiagnostics.ts`) and the OpenSensorHub/Docker backend (`SupportBundleHandler.java` + `oscar.sh` / `oscar.bat support-bundle`). Operators and site administrators can export a complete, secret-scrubbed troubleshooting archive in one click from the web UI—or from the host command line even when containers are stopped, degraded, or unable to boot.

For a captioned 1080p walkthrough, watch [Module 18 (`18-operator-help-and-support-bundle.mp4`)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/18-operator-help-and-support-bundle.mp4) in [VIDEO_GUIDES.md](VIDEO_GUIDES.md) or directly inside the OSCAR Viewer via **Help (`?`) -> Manual & Video Guides**.

---

## 1. Architecture & Automatic Activation

No separate installation or daemon is required. Both tiers of the Flight Recorder start automatically on every `oscar init` and `oscar upgrade` deployment:

1. **Client Browser Flight Recorder (`SupportDiagnostics.ts`):**
   - Installed automatically at application bootstrap via `installSupportDiagnosticsRecorder()`.
   - Maintains an in-memory bounded ring buffer of the most recent **`400` diagnostic events** (`MAX_SUPPORT_DIAGNOSTIC_EVENTS = 400`, `600`-character message cap per event) across four categories (`console`, `runtime`, `network`, and `app`) and three severity levels (`info`, `warn`, `error`).
   - Automatically records:
     - `console.warn` and `console.error` calls without interfering with normal DevTools output.
     - Uncaught `window` runtime exceptions (`filename`, `lineno`, `colno`) and `unhandledrejection` Promise failures.
     - Non-2xx HTTP `fetch` responses and slow requests exceeding **`2,500 ms`** (`SLOW_FETCH_THRESHOLD_MS = 2500`), recording HTTP method, sanitized URL, status code, and elapsed latency (`durationMs`).
     - Privacy-safe browser environment capabilities (low-entropy User-Agent Client Hints, locale, timezone, viewport dimensions, online state, and `ServiceWorker` / `MediaSource` / `WebRTC` feature availability) plus node connectivity and active Operational View state (`SupportClientStateSummary`).
2. **Server Rolling Logs & Diagnostic Handler (`SupportBundleHandler.java`):**
   - Writes bounded rolling application logs inside the `oscar_oscar_state` volume at `/var/lib/oscar/logs/oscar.log` (`10 MB` per file, `5` rotated archives, **`50 MB` total disk ceiling**).
   - Exposes an authenticated, read-only `GET /sensorhub/buckets/reports/support-bundle?tailLines=<100..10000>` endpoint (`DEFAULT_TAIL_LINES = 2500`, `MAX_ZIP_BYTES = 15 MiB`, `POST`/`PUT`/`DELETE` rejected) requiring `reports` read permission, alongside the read-only gateway TLS expiry diagnostic endpoint `GET /sensorhub/oscar/diagnostics/tls-status` used by the conditional `/health` expiration banner.
   - Captures recursive module states (including nested `LaneSystem`, RPM TCP driver, FFmpeg/RTSP camera, `OcrResourceGovernor`, and `VideoRetention` error messages/stack traces), JVM heap/GC/thread snapshots, filesystem headroom, `PARQUET_PRIMARY` storage summary, and a sanitized copy of `config.json`.
3. **Offline / Crash-Loop Host CLI Collector (`oscar.sh` / `oscar.bat support-bundle`) & Host Readiness Audits (`host-check`):**
   - Operates directly on the Ubuntu Server 24.04 or Windows 11 + WSL 2 host without requiring the OSCAR web server or PostgreSQL container to be healthy.
   - Collects host OS/CPU/RAM/disk/WSL 2 state, public X.509 certificate metadata (`SAN` list, validity window, SHA-256 fingerprint), `docker compose ps`, Docker volume metadata, sanitized `docker inspect` output, container logs, and read-only `oscar_oscar_state` logs into `oscar-host-support-<UTC>.zip` (`<= 25 MiB`).
   - Companion `oscar.sh host-check` / `oscar.bat host-check` runs proactive 10-year operational checks including `gateway-tls-cert` (`<= 30 d` WARN, `<= 7 d` / expired FAIL), `postgres-xid-headroom` (`age(datfrozenxid)` wraparound monitoring), and Windows `wsl2-sparse-vhd` (`[experimental] sparseVhd=true` virtual-disk block reclamation).

---

## 2. Three Export Modes (Online UI, Client-Only Fallback & Host CLI)

### Mode A — In-UI 1-Click Combined Export (`oscar-support-<UTC>.zip`)

When the OSCAR Viewer is reachable:

1. Sign into the OSCAR Viewer as an operator or administrator with `reports` read access.
2. Click the **Help (`?`)** icon in the top navigation bar.
3. Click **Export Support Bundle** in the dialog header (or under the **Troubleshooting & Support Bundle (`.zip`)** card).
4. The browser fetches `/sensorhub/buckets/reports/support-bundle?tailLines=2500` (`10,000 ms` timeout), merges its in-memory `client/client-diagnostics.json` flight-recorder snapshot with the server diagnostic entries, updates `summary.json` (`bundleSource: "combined"`) and `redaction-report.json`, and downloads **`oscar-support-<YYYYMMDDTHHMMSSZ>.zip`**.

### Mode B — Automatic Client-Only Fallback (`oscar-client-support-<UTC>.zip`)

If the OSCAR server or network tunnel is unreachable (HTTP error, network disconnect, or timeout `> 10 s`):

- Clicking **Export Support Bundle** in **Help (`?`)** never fails or hangs.
- The Viewer automatically packages its 400-event browser flight recorder, failed network timings, and `backendFetchError` alongside `serverCliFallback` instructions into **`oscar-client-support-<YYYYMMDDTHHMMSSZ>.zip`** (`bundleSource: "client-only"`), then prompts the administrator to pair it with a host CLI bundle.

### Mode C — Host CLI Export (`oscar-host-support-<UTC>.zip`)

Use the host CLI whenever Docker containers are stopped, restarting, or unreachable over HTTPS:

- **Ubuntu Server 24.04 LTS:**
  ```sh
  sudo bash oscar.sh support-bundle
  # Optional custom log tail (100..10000 lines) and output path:
  sudo bash oscar.sh support-bundle --tail 5000 --output /tmp/oscar-host-support.zip
  ```
- **Windows 11 x86-64 (Administrator PowerShell 5.1):**
  ```powershell
  .\oscar.bat support-bundle
  # Optional custom log tail and destination path:
  .\oscar.bat support-bundle -Tail 5000 -Destination C:\Users\Admin\Desktop\oscar-host-support.zip
  ```
- **Interactive Launcher Menu (`oscar.sh` / `oscar.bat` with no arguments):**
  Type `support-bundle` at the `oscar>` prompt.

By default, host support bundles are written **outside** the extracted release directory so offline `SHA256SUMS` verification inventories remain unmodified.

---

## 3. Archive Contents & Inspection Reference

Unzipping an exported bundle (`unzip -l oscar-support-<UTC>.zip`) reveals deterministic, machine- and human-readable JSON and log files:

| Entry Path | Source | Contents |
| --- | --- | --- |
| `summary.json` | Combined / CLI | Schema version (`1`), `bundleType`, `bundleSource` (`combined`, `client-only`, or `host-cli`), `oscarVersion` (`3.12.2`), UTC timestamp, event/error counts, and module health totals |
| `redaction-report.json` | Combined / CLI | Audit trail of `automatic-edge-redaction` counts (`clientRedactions`, `backendRedactions`, `totalRedactions`) and the explicit `neverCollected` exclusion list |
| `client/client-diagnostics.json` | Viewer UI | Sanitized current route, low-entropy browser environment, node list (without credentials), `eventCounts`, and the `events[]` flight-recorder ring buffer |
| `backend/modules.json` | Server API | Every OpenSensorHub module and nested lane/RPM/camera state (`STARTED`, `INITIALIZED`, fault/error strings, and bounded stack frames) |
| `backend/jvm-diagnostics.json` | Server API | Heap/non-heap memory pools, garbage-collector counters, uptime, and thread states |
| `backend/storage-summary.json` | Server API | `PARQUET_PRIMARY` archive path headroom, readiness marker status, and retention configuration |
| `backend/config.redacted.json` | Server API / Volume | Persisted SensorHub `config.json` with all password, secret, token, and URI userinfo fields replaced by `[REDACTED]` |
| `backend/oscar.log` & `backend/module-logs/*.log` | Server API / Volume | Bounded rolling log tail (`2,500` lines default, up to `10,000` lines, `<= 8 MiB` read cap) with inline credential/cookie/email masking |
| `host/system-info.txt` & `host/env.redacted.txt` | Host CLI | OS kernel, CPU/RAM/disk capacity, WSL 2 configuration (Windows), and sanitized `.env` |
| `tls/certificate-info.txt` & `docker/*` | Host CLI | Public TLS `server.crt` dates/SANs/SHA-256 fingerprint (never `server.key`), `compose-ps.txt`, `volumes.txt`, and secret-stripped `inspect.redacted.json` |

### Quick CLI Inspection Commands

```sh
# 1. Inspect overall health and flight-recorder error counts
unzip -p oscar-support-*.zip summary.json | python3 -m json.tool

# 2. Confirm automatic edge redaction counts and excluded secret paths
unzip -p oscar-support-*.zip redaction-report.json | python3 -m json.tool

# 3. List recent browser network failures or slow (>= 2500 ms) API calls
unzip -p oscar-support-*.zip client/client-diagnostics.json | \
  python3 -c 'import json,sys; d=json.load(sys.stdin); [print(e["timestamp"], e["level"], e["category"], e["message"]) for e in d["events"]]'
```

---

## 4. Automatic Edge Redaction & Zero-Secret Guarantees

Both client and server flight recorders sanitize strings **at capture time** (`redactSupportText`) before events enter memory or touch disk:

- **Masked in place (`[REDACTED]`):**
  - RTSP and HTTP URI userinfo (`rtsp://admin:pass@camera/...` -> `rtsp://[REDACTED]@camera/...`)
  - `Authorization: Basic / Bearer / Digest / Token ...` headers and standalone `Bearer <token>` values (including `oscar_fed_*` federation tokens and OIDC secrets)
  - `Cookie` / `Set-Cookie` headers and `OSCAR_SESSION` / `JSESSIONID` session identifiers
  - URL query secrets (`?password=`, `token=`, `access_token=`, `api_key=`, `secret=`, `sig=`)
  - JSON/YAML/env key-value pairs matching `password`, `passwd`, `pwd`, `secret`, `api_key`, `*token`, `private_key`, or `passphrase`
  - Email addresses (`a***@example.org`)
- **Never read or packaged under any mode:**
  - `secrets/*` and `/run/secrets/*` (database, bootstrap, admin, backup, and Octelium tunnel token files)
  - `tls/*.key`, PEM private keys, and `.keystore/*`
