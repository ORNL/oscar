#!/usr/bin/env python3
"""
Kromek D5 RIID simulator (reference implementation).

Emulates the device side of the OSH sensorhub-driver-kromek-d5 protocol:
a TCP *server* speaking the Kromek serial protocol over RFC 1055 SLIP framing.
The driver is a polling TCP client: every second it sends one or more
header-only request frames and BLOCKS reading one response frame each —
so this server is a simple "read one request -> write one response" loop.

Frame layout (logical bytes, before SLIP; ALL integers little-endian):
    [length u16 = 7 + N] [mode 0x00] [componentId] [reportId] [payload N bytes] [crc u16 = 0x0000]
encoded with RFC 1055 SLIP (0xC0 -> 0xDB 0xDC, 0xDB -> 0xDB 0xDD) and wrapped
in 0xC0 ... 0xC0 delimiters. Requests carry N=0.

Reports implemented (the default-enabled ones plus status/identity):
    0x07/0xC2 RadiometricsV1     - dose/counts + 4096 x u16 spectrum (payload 8246 B)
    0x08/0x82 RadiometricStatus  - alarm flags + GPS lat/lon (used for alarms and location)
    0x07/0xC5 Status             - battery/temperature
    0x07/0xC7 About              - firmware/product/serial strings
Unimplemented reports are answered with reportId 0xFF (ACK_REPORT_ID_ERROR),
which the driver cleanly ignores.

Stdlib only. Usage:
    python3 d5_mock.py [--config cfg.json] [--port 10111]
"""
import argparse
import json
import math
import random
import socket
import struct
import threading
import time

FRAME = 0xC0
ESC = 0xDB
ESC_FRAME = 0xDC
ESC_ESC = 0xDD
ACK_REPORT_ID_ERROR = 0xFF

DEFAULT_CONFIG = {
    "port": 10111,
    "serial": "WALKER2",
    "tick_s": 1.0,
    "speed_mps": 1.4,
    "background_gamma_cps": 900.0,
    "background_neutron_cps": 0.3,
    "alarm_factor": 1.6,
    # The RS-350 mock's loop in the opposite direction, so two walkers separate visually.
    "route": [
        [35.93000, -84.30334],
        [35.92619, -84.30529],
        [35.92461, -84.31000],
        [35.92619, -84.31471],
        [35.93000, -84.31666],
        [35.93381, -84.31471],
        [35.93539, -84.31000],
        [35.93381, -84.30529],
        [35.93000, -84.30334],
    ],
    "hotspots": [
        {"lat": 35.93539, "lon": -84.31000, "intensity_cps_at_1m": 90000.0, "isotope": "Cs-137"},
        {"lat": 35.92619, "lon": -84.31471, "intensity_cps_at_1m": 60000.0, "isotope": "Co-60"},
    ],
}

M_PER_DEG_LAT = 111_320.0


def dist_m(lat1, lon1, lat2, lon2):
    dy = (lat2 - lat1) * M_PER_DEG_LAT
    dx = (lon2 - lon1) * M_PER_DEG_LAT * math.cos(math.radians(lat1))
    return math.hypot(dx, dy)


def poisson(lam):
    if lam > 50:
        return max(0, int(random.gauss(lam, math.sqrt(lam))))
    l, k, p = math.exp(-lam), 0, 1.0
    while True:
        p *= random.random()
        if p <= l:
            return k
        k += 1


class Walker:
    def __init__(self, route, speed_mps):
        self.route, self.speed, self.seg, self.seg_pos = route, speed_mps, 0, 0.0

    def step(self, dt):
        remaining = self.speed * dt
        while remaining > 0:
            a = self.route[self.seg]
            b = self.route[(self.seg + 1) % len(self.route)]
            seg_len = dist_m(a[0], a[1], b[0], b[1])
            if self.seg_pos + remaining < seg_len:
                self.seg_pos += remaining
                remaining = 0
            else:
                remaining -= (seg_len - self.seg_pos)
                self.seg = (self.seg + 1) % len(self.route)
                self.seg_pos = 0.0

    def position(self):
        a = self.route[self.seg]
        b = self.route[(self.seg + 1) % len(self.route)]
        seg_len = max(dist_m(a[0], a[1], b[0], b[1]), 0.01)
        f = min(self.seg_pos / seg_len, 1.0)
        return a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f


class D5State:
    def __init__(self, cfg):
        self.cfg = cfg
        self.walker = Walker(cfg["route"], cfg["speed_mps"])
        self.t0 = time.time()
        self.seq = 0
        self.dose_total = 0.0
        self.battery = 100.0
        self.alarming = False
        self.lock = threading.Lock()
        self.gamma_cps = cfg["background_gamma_cps"]
        self.neutron_counts_tick = 0
        threading.Thread(target=self._ticker, daemon=True).start()

    def _expected_gamma(self, lat, lon):
        cps = self.cfg["background_gamma_cps"]
        for h in self.cfg["hotspots"]:
            d = dist_m(lat, lon, h["lat"], h["lon"])
            cps += h["intensity_cps_at_1m"] / max(d * d, 1.0)
        return cps

    def _ticker(self):
        while True:
            with self.lock:
                self.walker.step(self.cfg["tick_s"])
                lat, lon = self.walker.position()
                exp = self._expected_gamma(lat, lon)
                self.gamma_cps = poisson(exp)
                self.neutron_counts_tick = poisson(self.cfg["background_neutron_cps"])
                self.dose_total += exp / 12000.0 / 3600.0  # uSv accrued this second
                self.battery = max(5.0, self.battery - 0.002)
                self.seq += 1
                self.alarming = exp > self.cfg["background_gamma_cps"] * self.cfg["alarm_factor"]
                if self.alarming:
                    print(f"[d5-sim] ALARM at {lat:.5f},{lon:.5f}", flush=True)
            time.sleep(self.cfg["tick_s"])

    def radiometrics_v1(self):
        with self.lock:
            gamma_counts = max(0, min(0xFFFFFFFF, int(self.gamma_cps)))
            neutron_counts = max(0, min(0xFFFFFFFF, int(self.neutron_counts_tick)))
            elapsed_ms = max(0, min(0xFFFFFFFF, int((time.time() - self.t0) * 1000)))
            dose_rate = self._expected_gamma(*self.walker.position()) / 12000.0
            header = struct.pack(
                "<IIIfffIIhfIIhfBB",
                0,                    # status
                elapsed_ms,           # realTimeMs
                self.seq & 0xFFFFFFFF,  # sequenceNumber
                float(self.dose_total),  # dose (uSv)
                float(dose_rate),     # doseRate (uSv/h)
                float(self.dose_total),  # doseUserAccumulated
                1000,                 # neutronLiveTime
                neutron_counts,       # neutronCounts (per interval)
                2500,                 # neutronTemperature (x100 C)
                0.0,                  # neutronReserved
                1000,                 # gammaLiveTime
                gamma_counts,         # gammaCounts
                2500,                 # gammaTemperature (x100 C)
                0.0,                  # gammaReserved
                12,                   # spectrumBitsSize
                0,                    # reserved
            )
            decay = 4096 / 6.0
            total = max(gamma_counts, 1)
            bins = bytearray()
            wsum = sum(math.exp(-i / decay) for i in range(0, 4096, 16)) * 16
            for i in range(4096):
                v = min(0xFFFF, int(total * math.exp(-i / decay) / wsum * 16))
                bins += struct.pack("<H", v)
            payload = header + bytes(bins)
        assert len(payload) == 8246, len(payload)
        return payload

    def radiometric_status(self):
        with self.lock:
            lat, lon = self.walker.position()
            alarming = self.alarming
            return struct.pack(
                "<BBBffIH",
                0,                      # doseAlarmActive
                1 if alarming else 0,   # gammaCpsAlarmActive
                0,                      # neutronCpsAlarmActive
                float(lat),             # latitude (deg)
                float(lon),             # longitude (deg)
                int(time.time()) & 0xFFFFFFFF,  # deviceTimestamp (epoch s)
                0,                      # numNuclideResults
            )

    def status(self):
        with self.lock:
            return struct.pack(
                "<BBBBBBBBBBB",
                0,                                  # appStatus
                1,                                  # power source: BATTERY
                25,                                 # temperature C
                0, 0,                               # detectorStatus0/1
                max(0, min(100, int(self.battery))),  # batteryLevel %
                0,                                  # batteryChargeRate
                25,                                 # batteryTemperature
                0, 0,                               # usbStatus, btStatus
                0,                                  # detectorStatus2
            )

    def about(self):
        name = b"Kromek D5 (sim)".ljust(50, b"\x00")[:50]
        serial = self.cfg["serial"].encode().ljust(50, b"\x00")[:50]
        return bytes([1, 0, 1, 0]) + name + serial


def slip_encode(data):
    """Encode logical bytes with RFC 1055 SLIP and wrap in 0xC0 ... 0xC0."""
    out = bytearray([FRAME])
    for b in data:
        if b == FRAME:
            out.append(ESC)
            out.append(ESC_FRAME)
        elif b == ESC:
            out.append(ESC)
            out.append(ESC_ESC)
        else:
            out.append(b)
    out.append(FRAME)
    return bytes(out)


def slip_decode(data):
    """Decode RFC 1055 SLIP frame body (between 0xC0 delimiters)."""
    out = bytearray()
    i = 0
    while i < len(data):
        b = data[i]
        if b == ESC:
            if i + 1 >= len(data):
                raise ValueError("Truncated SLIP escape sequence")
            nxt = data[i + 1]
            if nxt == ESC_FRAME:
                out.append(FRAME)
            elif nxt == ESC_ESC:
                out.append(ESC)
            else:
                raise ValueError(f"Invalid SLIP escape byte: {nxt:#04x}")
            i += 2
        else:
            out.append(b)
            i += 1
    return bytes(out)


def build_frame(component_id, report_id, payload):
    logical = (
        struct.pack("<H", 7 + len(payload))
        + bytes([0x00, component_id & 0xFF, report_id & 0xFF])
        + payload
        + b"\x00\x00"
    )
    return slip_encode(logical)


def dispatch(component_id, report_id, state):
    key = (component_id, report_id)
    if key == (0x07, 0xC2):
        return report_id, state.radiometrics_v1()
    if key == (0x08, 0x82):
        return report_id, state.radiometric_status()
    if key == (0x07, 0xC5):
        return report_id, state.status()
    if key == (0x07, 0xC7):
        return report_id, state.about()
    print(f"[d5-sim] unimplemented report {component_id:#04x}/{report_id:#04x}, "
          f"answering ACK_REPORT_ID_ERROR", flush=True)
    return ACK_REPORT_ID_ERROR, b""


def handle_client(conn, addr, state):
    print(f"[d5-sim] client connected: {addr}", flush=True)
    buf = bytearray()
    try:
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break
            buf += chunk
            while True:
                try:
                    start = buf.index(FRAME)
                except ValueError:
                    buf.clear()
                    break
                end = start + 1
                while end < len(buf) and buf[end] == FRAME:
                    start = end
                    end += 1
                try:
                    end = buf.index(FRAME, start + 1)
                except ValueError:
                    break
                raw = slip_decode(bytes(buf[start + 1:end]))
                del buf[:end]
                if len(raw) < 7:
                    continue
                component_id, report_id = raw[3], raw[4]
                resp_report_id, payload = dispatch(component_id, report_id, state)
                conn.sendall(build_frame(component_id, resp_report_id, payload))
    except OSError:
        pass
    finally:
        conn.close()
        print(f"[d5-sim] client disconnected: {addr}", flush=True)


def serve(cfg):
    state = D5State(cfg)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", cfg["port"]))
    srv.listen(4)
    print(f"[d5-sim] listening on :{cfg['port']}", flush=True)
    while True:
        conn, addr = srv.accept()
        conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        threading.Thread(target=handle_client, args=(conn, addr, state), daemon=True).start()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", help="JSON file overriding DEFAULT_CONFIG keys")
    ap.add_argument("--port", type=int)
    args = ap.parse_args()
    cfg = dict(DEFAULT_CONFIG)
    if args.config:
        with open(args.config) as f:
            cfg.update(json.load(f))
    if args.port:
        cfg["port"] = args.port
    serve(cfg)


if __name__ == "__main__":
    main()
