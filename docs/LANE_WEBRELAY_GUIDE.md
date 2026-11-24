# OSCAR 3.11.13 Per-Lane Physical RPM Lights & Sound Control (`WebRelay-Quad`)

OSCAR 3.11.13 adds optional per-lane physical radiation portal monitor (RPM) lights and sounder control over standard Ethernet using **ControlByWeb® WebRelay-Quad™** (`X-WR-4R3-E` PoE / non-PoE and `X-410`) network relay modules.

---

## 1. Operational Overview & Fail-Safe Design

At high-throughput ports of entry, benign Naturally Occurring Radioactive Material (`NORM`) cargo and stationary vehicles holding a lane frequently trigger raw RPM gamma alarms. Without software relay gatekeeping, every raw gamma trigger activates the lane's physical red beacon and audible sounder — creating gatehouse alarm fatigue while operators still need immediate physical visual/audible signaling for real un-suppressed Gamma and Neutron threats.

OSCAR 3.11.13 solves this per lane with **zero clutter when unconfigured** (`enabled = false` by default: `0` background threads, `0` open sockets, and `0` extra UI chips on disabled lanes) and **hardware fail-safe pass-through**:

| Logical Relay Channel | Function in `AUTO` Gatekeeping Mode | State When De-Energized (`0`) | State When Energized (`1`) |
| :--- | :--- | :--- | :--- |
| **Relay 1 (`R1`)** | Gamma Light & Siren Intercept Gate | Normal hardware pass-through (`NC` path closed) | Intercepted / suppressed by OSCAR until threat confirmed |
| **Relay 2 (`R2`)** | Neutron Blue Light Intercept Gate | Normal hardware pass-through (`NC` path closed) | Intercepted / suppressed by OSCAR until threat confirmed |
| **Relay 3 (`R3`)** | OSCAR Gamma Red Light + Audible Siren Driver | Off | Energized / pulsed (`pulseDurationSeconds`, default `5 s`) on actionable Gamma alarm |
| **Relay 4 (`R4`)** | OSCAR Neutron Blue Light Driver | Off | Energized / pulsed (`pulseDurationSeconds`, default `5 s`) on any Neutron alarm |

### Key Safety Guarantees

1. **Hardware Fail-Safe Pass-Through (`0,0,0,0`):** If OSCAR is stopped, upgraded, rebooted, or loses power, de-energized coils (`0,0,0,0`) return control directly to the RPM's native alarm outputs so physical portal alarms are never silently lost.
2. **Power-Blip Auto-Rearm:** While a lane is in `AUTO` or `MUTED` mode, OSCAR polls `/stateFull.xml` (automatically negotiating `/state.xml` on legacy firmware) every `pollIntervalSeconds` (`5 s` default) over `HTTP/1.1` and immediately re-arms `R1=1, R2=1` if the relay module reboots after a brief PoE power blip.
3. **Benign `Code 9999` & `Code 9998` Suppression vs. Mandatory Neutron Signaling:**
   - **`Code 9999: EML Non-Threat`:** When Enhanced Machine Learning (`EML`) or a custom `EmlAlarmAssessmentAlgorithm` evaluates an occupancy as a verified non-threat (`RELEASE`), OSCAR suppresses `R3` so the physical red light and siren remain silent.
   - **`Code 9998: Extended Occupancy Gamma Alarm`:** When `suppressExtendedOccupancyGamma = true` (default), stalled gamma-only extended occupancies suppress `R3` on exit; administrators can set `suppressExtendedOccupancyGamma = false` per lane if local SOP requires physical siren activation on stalled gamma holds.
   - **Neutron Safety Invariant:** Any occupancy involving a **Neutron** alarm (`Neutron` or `Gamma-Neutron`) is **never** suppressed and always pulses `R4` (plus `R3` on `Gamma-Neutron`).
4. **Optional Second Auxiliary Dry-Contact `WebRelay-Quad`:** Each lane optionally supports a second synchronized `WebRelay-Quad` (`secondaryEnabled = true`, e.g., `198.51.100.22`) for auxiliary gatehouse panels, PLC inputs, or traffic-arm interlocks (`mirrorPrimaryAlarmsToSecondary = true` by default, plus independent `R1–R4` manual toggle/pulse controls).

---

## 2. Network & ControlByWeb Device Preparation

1. **Assign a Static IPv4 Address on the Sensor Subnet:**
   - Factory ControlByWeb `WebRelay-Quad` units ship on a default `192.168.1.x` address. Place the unit on the OSCAR sensor VLAN/subnet with a static IPv4 reservation (for example, `198.51.100.21`, HTTP port `80`).
2. **Verify XML Control Access:**
   - In the ControlByWeb web setup UI, confirm HTTP XML state/control (`stateFull.xml` / `state.xml`) is enabled.
   - If HTTP Basic Authentication is enabled on the `WebRelay-Quad` (recommended; default username `admin`), record the password for entry in OSCAR (`WebRelayConfig.password`). OSCAR sends Basic Auth headers only when configured, redacts passwords in all API responses and support bundles (`webrelaypassword`), and omits plaintext passwords from exported CSV spreadsheets.
3. **Verify Reachability from the OSCAR Host:**
   ```bash
   curl -fsS http://198.51.100.21/stateFull.xml
   ```

---

## 3. Configuring & Operating Per-Lane Lights & Sound

Administrators can configure and control per-lane `WebRelay-Quad` hardware from **three** places:

### 3.1 OSCAR Viewer — Status of Health (`/health`) & Lane View (`/lane-view`)

1. Sign in to OSCAR Viewer (`https://oscar.local/`) with an **Administrator** account and open **Status of Health (`/health`)** or any lane's **Lane View (`/lane-view`)**.
2. Click **Lights & Sound** on the target lane row/header to open the **RPM Lights & Sound (`WebRelay-Quad`)** modal dialog:
   - **Lane Switcher:** Switch between any configured lane on the node without closing the modal.
   - **Live Telemetry & Suppression Counters:** Inspect online/offline status, active mode (`AUTO`, `PASS_THROUGH`, `MUTED`, `MANUAL`), live `R1–R4` coil indicators (`ENERGIZED` / `OFF`), pulsed alarm counters, and suppressed `Code 9999` / `Code 9998` counts.
   - **Quick Manual Actions (Commissioning & Gatehouse Control):**
     - **Pulse Gamma Light + Sound (`R3`)** / **Pulse Neutron Blue Light (`R4`)** for `pulseDurationSeconds` (`1–60 s`, hardware-timed `relayNState=2&pulseTimeN=...` so coils auto-clear even if Ethernet disconnects mid-pulse).
     - **Latch ON / Turn OFF** individual outputs during walk-around commissioning tests.
     - **Return to Automatic (`AUTO`)**, **Mute Physical Outputs (`MUTED`: `1,1,0,0`)**, or **Hardware Pass-Through (`0,0,0,0`)**.
   - **Configuration & Connection Test:** Expand **WebRelay Endpoint & Policy Settings**, enter the primary host (`198.51.100.21`), port (`80`), pulse duration (`5 s`), poll interval (`5 s`), optional Basic Auth credentials, and optional Auxiliary `WebRelay-Quad` settings, click **Test Connection**, and click **Save & Apply to Lane**.

> **Role Visibility:** Non-admin `Operator` and `Viewer` sessions never see relay mutation buttons or unconfigured WebRelay controls. When a lane has `enabled = true`, operators see read-only `WebRelay (AUTO)` / `Offline` health chips on `/health` so gatehouse staff know immediately if a configured relay module goes offline.

### 3.2 SensorHub Admin (`/sensorhub/admin`)

1. Open `https://oscar.local/sensorhub/admin`, expand **Sensors**, and select a **Lane System**.
2. Locate **RPM Lights & Sound (`WebRelayConfig`)** to edit `enabled`, `operatingMode`, `host`, `port`, `username`, `password`, `pulseDurationSeconds`, `pollIntervalSeconds`, `suppressExtendedOccupancyGamma`, and optional secondary unit fields, plus live commissioning buttons (**Return to AUTO**, **Test Gamma Light + Sound**, **Test Neutron Blue Light**, **Silence / Re-Arm**, **Pass-Through `0,0,0,0`**).
3. Click **Apply Changes** and **Save** in the top toolbar to persist to `config.json`.

### 3.3 Bulk Multi-Lane Spreadsheet (`config.csv` `#WEBRELAY` Directives)

`SpreadsheetParser` supports round-trip `#WEBRELAY` metadata lines alongside standard lane rows so multi-lane deployments can version-control relay topology in `config.csv`:

```csv
#WEBRELAY,Lane01,true,AUTO,198.51.100.21,80,admin,5,5,true,false,,80,true
```

*(Plaintext passwords are never written when exporting `config.csv`; if HTTP Basic Auth is used on the relay hardware, supply credentials in the UI or optional trailing import column and save to `config.json`.)*

---

## 4. Related Documentation

- [Status of Health Guide](STATUS_OF_HEALTH.md)
- [EML Integration & Custom Alarm Assessment Guide](EML_INTEGRATION.md)
- [Hands-On Training Sandbox & Guided Walkthrough Guide (`Lab 3.5`)](TRAINING_SANDBOX_GUIDE.md)
- [How-To Video Guides (`#29`)](VIDEO_GUIDES.md)
