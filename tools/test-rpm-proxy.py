#!/usr/bin/env python3
"""End-to-end unit, protocol, disconnect-detection, write-policy, slow-consumer,
and 50-lane fan-out test suite for oscar_rpm_proxy."""

from __future__ import annotations

import asyncio
import json
import pathlib
import socket
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request

REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
PROXY_PKG_ROOT = REPO_ROOT / "dist" / "release" / "docker" / "rpm-proxy"
sys.path.insert(0, str(PROXY_PKG_ROOT))

from oscar_rpm_proxy.config import ConfigError, load_config  # noqa: E402
from oscar_rpm_proxy.csv_tool import generate_proxy_config_from_csv  # noqa: E402
from oscar_rpm_proxy.http_status import StatusServer  # noqa: E402
from oscar_rpm_proxy.network import create_service  # noqa: E402
from oscar_rpm_proxy.state import Registry  # noqa: E402

_ALLOCATED_PORTS: set[int] = set()


def _free_port() -> int:
    held: list[socket.socket] = []
    try:
        while True:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.bind(("127.0.0.1", 0))
            port = int(s.getsockname()[1])
            if port not in _ALLOCATED_PORTS:
                _ALLOCATED_PORTS.add(port)
                s.close()
                return port
            held.append(s)
    finally:
        for sock in held:
            sock.close()


def _http_get(url: str) -> tuple[int, str]:
    try:
        with urllib.request.urlopen(url, timeout=3) as resp:
            return resp.status, resp.read().decode("utf-8")
    except urllib.error.HTTPError as err:
        try:
            return err.code, err.read().decode("utf-8", "replace")
        finally:
            err.close()


class OscarRpmProxyTestSuite(unittest.IsolatedAsyncioTestCase):
    def test_config_validation_and_20col_csv_generation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = pathlib.Path(tmp)
            oscar_csv = tmp_dir / "site-50-lanes.csv"
            rows = [
                "Name,UniqueID,AutoStart,Latitude,Longitude,OperationalViews,RPMConfigType,RPMHost,RPMPort,"
                "AspectAddressStart,AspectAddressEnd,EMLEnabled,EMLCollimated,LaneWidth,CameraType0,CameraHost0,"
                "CameraPath0,Codec0,Username0,Password0"
            ]
            for i in range(1, 51):
                rows.append(
                    f"Lane{i:02d},lane-{i:02d},true,35.89,-84.19,east-gate;entrance,Rapiscan,"
                    f"192.0.2.{i},1600,,,true,true,4.82,Custom,198.51.100.10:8554,/cam_{i:02d},,,"
                )
            rows.append("#WEBRELAY,lane-01,true,AUTO,198.51.100.50,80,admin,,true,2500")
            oscar_csv.write_text("\n".join(rows) + "\n", encoding="utf-8")

            # 1) Port-mapped 50-lane generation
            cfg_port = tmp_dir / "proxy-portmap.json"
            emitted_csv = tmp_dir / "oscar-proxied.csv"
            summary = generate_proxy_config_from_csv(
                oscar_csv,
                output_config_path=cfg_port,
                mode="port-map",
                listen_host="0.0.0.0",
                base_port=12601,
                oscar_target_host="127.0.0.1",
                emit_oscar_csv_path=emitted_csv,
            )
            self.assertEqual(summary["lane_count"], 50)
            self.assertEqual(summary["port_range"], "12601-12650")
            parsed = load_config(cfg_port)
            self.assertEqual(len(parsed.services), 50)
            self.assertEqual(str(parsed.services[0].listen[0]), "0.0.0.0:12601")
            self.assertEqual(str(parsed.services[49].upstream.endpoint), "192.0.2.50:1600")
            self.assertTrue(parsed.services[0].gate_listener_on_upstream)
            self.assertTrue(parsed.services[0].line_framed)
            self.assertTrue(parsed.services[0].replay_rapiscan_setup)

            emitted_lines = emitted_csv.read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(emitted_lines), 52)
            self.assertIn(",Rapiscan,127.0.0.1,12601,", emitted_lines[1])
            self.assertIn(",Rapiscan,127.0.0.1,12650,", emitted_lines[50])
            self.assertEqual(emitted_lines[51], "#WEBRELAY,lane-01,true,AUTO,198.51.100.50,80,admin,,true,2500")

            # 2) Virtual-IP :1600 + loopback dual-listener generation
            cfg_vip = tmp_dir / "proxy-vip.json"
            emitted_vip_csv = tmp_dir / "oscar-vip-proxied.csv"
            vip_list = tmp_dir / "vips.txt"
            vip_summary = generate_proxy_config_from_csv(
                oscar_csv,
                output_config_path=cfg_vip,
                mode="virtual-ip",
                vip_start_ip="198.51.100.101",
                vip_port=1600,
                base_port=13601,
                emit_oscar_csv_path=emitted_vip_csv,
                emit_vip_list_path=vip_list,
            )
            self.assertEqual(len(vip_summary["allocated_vips"]), 50)
            self.assertEqual(vip_summary["allocated_vips"][0], "198.51.100.101")
            self.assertEqual(vip_summary["allocated_vips"][49], "198.51.100.150")
            parsed_vip = load_config(cfg_vip)
            self.assertEqual(
                [str(ep) for ep in parsed_vip.services[0].listen],
                ["198.51.100.101:1600", "127.0.0.1:13601"],
            )

            # 3) Reject allow_primary without primary_write_clients
            bad_cfg = tmp_dir / "bad.json"
            bad_cfg.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "services": [
                            {
                                "name": "lane-1",
                                "kind": "rpm_broadcast",
                                "listen": ["127.0.0.1:19001"],
                                "upstream": {"address": "127.0.0.1:19002"},
                                "client_writes": "allow_primary",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaises(ConfigError):
                load_config(bad_cfg)

    async def test_setup_replay_midline_framing_and_silent_disconnect_gating(self) -> None:
        rpm_port = _free_port()
        proxy_port = _free_port()
        status_port = _free_port()

        rpm_clients: list[asyncio.StreamWriter] = []
        upstream_received: list[bytes] = []
        send_initial_data = True

        async def rpm_handler(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
            rpm_clients.append(writer)
            if send_initial_data:
                writer.write(
                    b"SG1,40,6.0,10,1,0\r\n"
                    b"SG2,100,100,100,100,0,0\r\n"
                    b"SG3,1,1,1,1,0\r\n"
                    b"SN1,5,20,1,1,1,1\r\n"
                    b"SN2,10,10,10,10\r\n"
                    b"TT,1\r\n"
                    b"GB,0250,0248,0252,0249\r\n"
                )
                await writer.drain()
            try:
                while True:
                    chunk = await reader.read(1024)
                    if not chunk:
                        break
                    upstream_received.append(chunk)
            except Exception:
                pass

        rpm_server = await asyncio.start_server(rpm_handler, "127.0.0.1", rpm_port)

        with tempfile.TemporaryDirectory() as tmp:
            cfg_path = pathlib.Path(tmp) / "config.json"
            cfg_path.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "status": {"listen": f"127.0.0.1:{status_port}"},
                        "services": [
                            {
                                "name": "lane-01",
                                "kind": "rpm_broadcast",
                                "listen": [f"127.0.0.1:{proxy_port}"],
                                "upstream": {"address": f"127.0.0.1:{rpm_port}"},
                                "connect_timeout_seconds": 1.0,
                                "reconnect_delay_seconds": 0.25,
                                "idle_timeout_seconds": 0.7,
                                "first_line_timeout_seconds": 0.6,
                                "client_writes": "discard",
                                "required": True,
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            app_cfg = load_config(cfg_path)

        registry = Registry()
        stats = registry.register(app_cfg.services[0])
        svc = create_service(app_cfg.services[0], stats)
        status_srv = StatusServer(app_cfg.status_listen, registry)
        await svc.start()
        await status_srv.start()

        try:
            deadline = time.monotonic() + 3.0
            while not stats.listener_open and time.monotonic() < deadline:
                await asyncio.sleep(0.02)
            self.assertTrue(stats.listener_open)
            self.assertTrue(stats.upstream_connected)

            # Drip a half-transmitted line BEFORE late CAS & OSCAR connect
            rpm_w = rpm_clients[-1]
            rpm_w.write(b"GA,0800,0810,")
            await rpm_w.drain()
            await asyncio.sleep(0.03)

            cas_r, cas_w = await asyncio.open_connection("127.0.0.1", proxy_port)
            osc_r, osc_w = await asyncio.open_connection("127.0.0.1", proxy_port)

            # Verify consumer writes are discarded in default discard mode
            osc_w.write(b"UNEXPECTED_CLIENT_COMMAND\r\n")
            await osc_w.drain()

            # Complete the GA line + clear tamper (TC)
            rpm_w.write(b"0820,0795\r\nTC,0\r\n")
            await rpm_w.drain()

            expected_lines = [
                b"SG1,40,6.0,10,1,0\r\n",
                b"SG2,100,100,100,100,0,0\r\n",
                b"SG3,1,1,1,1,0\r\n",
                b"SN1,5,20,1,1,1,1\r\n",
                b"SN2,10,10,10,10\r\n",
                b"TT,1\r\n",
                b"GA,0800,0810,0820,0795\r\n",
                b"TC,0\r\n",
            ]
            for consumer_r in (cas_r, osc_r):
                received = [await asyncio.wait_for(consumer_r.readline(), timeout=2.0) for _ in expected_lines]
                self.assertEqual(received, expected_lines)

            self.assertEqual(upstream_received, [])

            # 3rd consumer after TC,0: receives SG1..SN2 WITHOUT stale TT
            late_r, late_w = await asyncio.open_connection("127.0.0.1", proxy_port)
            rpm_w.write(b"NB,0002,0001,0002,0001\r\n")
            await rpm_w.drain()
            late_received = [await asyncio.wait_for(late_r.readline(), timeout=2.0) for _ in range(6)]
            self.assertEqual(
                late_received,
                [
                    b"SG1,40,6.0,10,1,0\r\n",
                    b"SG2,100,100,100,100,0,0\r\n",
                    b"SG3,1,1,1,1,0\r\n",
                    b"SN1,5,20,1,1,1,1\r\n",
                    b"SN2,10,10,10,10\r\n",
                    b"NB,0002,0001,0002,0001\r\n",
                ],
            )
            late_w.close()
            await late_w.wait_closed()
            # Existing consumers also received that live NB broadcast
            self.assertEqual(await asyncio.wait_for(cas_r.readline(), timeout=2.0), b"NB,0002,0001,0002,0001\r\n")
            self.assertEqual(await asyncio.wait_for(osc_r.readline(), timeout=2.0), b"NB,0002,0001,0002,0001\r\n")

            # Check /status and /metrics off the event loop
            code_st, body_st = await asyncio.to_thread(_http_get, f"http://127.0.0.1:{status_port}/status")
            self.assertEqual(code_st, 200)
            status_json = json.loads(body_st)
            self.assertEqual(status_json["status"], "ok")
            self.assertEqual(status_json["connected_lanes"], 1)

            code_m, body_m = await asyncio.to_thread(_http_get, f"http://127.0.0.1:{status_port}/metrics")
            self.assertEqual(code_m, 200)
            self.assertIn("oscar_rpm_proxy_upstream_connected", body_m)

            # Simulate SILENT CABLE PULL / FROZEN RPM: keep RPM TCP socket open, stop sending bytes!
            send_initial_data = False
            t_silence = time.monotonic()
            cas_eof = await asyncio.wait_for(cas_r.read(1024), timeout=2.5)
            osc_eof = await asyncio.wait_for(osc_r.read(1024), timeout=2.5)
            disconnect_elapsed = time.monotonic() - t_silence
            self.assertEqual(cas_eof, b"")
            self.assertEqual(osc_eof, b"")
            self.assertLess(disconnect_elapsed, 1.8)
            self.assertGreaterEqual(stats.idle_timeouts, 1)

            cas_w.close()
            osc_w.close()

            # Listener MUST be closed while RPM is down -> ConnectionRefusedError (zero SYN-ACK flapping!)
            await asyncio.sleep(0.05)
            self.assertFalse(stats.listener_open)
            with self.assertRaises(ConnectionRefusedError):
                await asyncio.open_connection("127.0.0.1", proxy_port)

            code_rz, _ = await asyncio.to_thread(_http_get, f"http://127.0.0.1:{status_port}/readyz")
            self.assertEqual(code_rz, 503)

            # Restore live RPM telemetry and confirm automatic recovery + listener re-open
            send_initial_data = True
            for w in list(rpm_clients):
                w.close()
            deadline = time.monotonic() + 3.0
            while not stats.listener_open and time.monotonic() < deadline:
                await asyncio.sleep(0.05)
            self.assertTrue(stats.listener_open)
            rec_r, rec_w = await asyncio.open_connection("127.0.0.1", proxy_port)
            first_recovered = await asyncio.wait_for(rec_r.readline(), timeout=2.0)
            self.assertEqual(first_recovered, b"SG1,40,6.0,10,1,0\r\n")
            rec_w.close()
            await rec_w.wait_closed()
        finally:
            await status_srv.stop()
            await svc.stop()
            for w in rpm_clients:
                w.close()
            rpm_server.close()
            await rpm_server.wait_closed()

    async def test_allow_primary_writes_and_slow_consumer_eviction(self) -> None:
        rpm_port = _free_port()
        proxy_port = _free_port()
        rpm_clients: list[asyncio.StreamWriter] = []
        upstream_received: list[bytes] = []

        async def rpm_handler(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
            rpm_clients.append(writer)
            writer.write(b"GB,0200,0200,0200,0200\r\n")
            await writer.drain()
            try:
                while True:
                    data = await reader.read(1024)
                    if not data:
                        break
                    upstream_received.append(data)
            except Exception:
                pass

        rpm_server = await asyncio.start_server(rpm_handler, "127.0.0.1", rpm_port)
        with tempfile.TemporaryDirectory() as tmp:
            cfg_path = pathlib.Path(tmp) / "config.json"
            cfg_path.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "services": [
                            {
                                "name": "lane-write-test",
                                "kind": "rpm_broadcast",
                                "listen": [f"127.0.0.1:{proxy_port}"],
                                "upstream": {"address": f"127.0.0.1:{rpm_port}"},
                                "client_writes": "allow_primary",
                                "primary_write_clients": ["127.0.0.1/32"],
                                "idle_timeout_seconds": 5.0,
                                "queue_packets": 4,
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            app_cfg = load_config(cfg_path)

        registry = Registry()
        stats = registry.register(app_cfg.services[0])
        svc = create_service(app_cfg.services[0], stats)
        await svc.start()
        try:
            deadline = time.monotonic() + 3.0
            while not stats.listener_open and time.monotonic() < deadline:
                await asyncio.sleep(0.02)

            fast_r, fast_w = await asyncio.open_connection("127.0.0.1", proxy_port)
            slow_r, slow_w = await asyncio.open_connection("127.0.0.1", proxy_port)

            # Primary allowed IP (127.0.0.1) forwards write to upstream
            fast_w.write(b"SYNC_CLOCK\r\n")
            await fast_w.drain()
            await asyncio.sleep(0.05)
            self.assertEqual(b"".join(upstream_received), b"SYNC_CLOCK\r\n")

            # Shrink slow consumer's OS receive buffer and flood > queue_packets + socket buffer
            slow_sock = slow_w.get_extra_info("socket")
            if slow_sock is not None:
                slow_sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)

            rpm_w = rpm_clients[-1]
            burst_count = 3500
            payload = ("GB," + ("0250," * 400) + "END\r\n").encode("ascii")
            for i in range(burst_count):
                rpm_w.write(payload)
                if i % 50 == 0:
                    await rpm_w.drain()
                # Fast consumer keeps draining simultaneously
                line = await asyncio.wait_for(fast_r.readline(), timeout=2.0)
                self.assertEqual(line, payload)

            self.assertGreaterEqual(stats.dropped_clients, 1)
            fast_w.close()
            slow_w.close()
            _ = slow_r
        finally:
            await svc.stop()
            for w in rpm_clients:
                w.close()
            rpm_server.close()
            await rpm_server.wait_closed()

    async def test_fifty_lane_simultaneous_realtime_fanout_benchmark(self) -> None:
        lane_count = 50
        rpm_servers: list[asyncio.AbstractServer] = []
        rpm_writers: list[list[asyncio.StreamWriter]] = [[] for _ in range(lane_count)]
        services_json = []
        proxy_ports: list[int] = []

        for idx in range(lane_count):
            r_port = _free_port()
            p_port = _free_port()
            proxy_ports.append(p_port)

            def make_handler(lane_idx: int):
                async def _h(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
                    rpm_writers[lane_idx].append(writer)
                    writer.write(f"GB,0200,0200,0200,{lane_idx:04d}\r\n".encode("ascii"))
                    await writer.drain()
                    try:
                        await reader.read(1024)
                    except Exception:
                        pass

                return _h

            srv = await asyncio.start_server(make_handler(idx), "127.0.0.1", r_port)
            rpm_servers.append(srv)
            services_json.append(
                {
                    "name": f"lane-{idx + 1:02d}",
                    "kind": "rpm_broadcast",
                    "listen": [f"127.0.0.1:{p_port}"],
                    "upstream": {"address": f"127.0.0.1:{r_port}"},
                    "idle_timeout_seconds": 5.0,
                    "first_line_timeout_seconds": 2.0,
                }
            )

        with tempfile.TemporaryDirectory() as tmp:
            cfg_p = pathlib.Path(tmp) / "config50.json"
            cfg_p.write_text(json.dumps({"version": 1, "services": services_json}), encoding="utf-8")
            app_cfg = load_config(cfg_p)

        registry = Registry()
        services = [create_service(sc, registry.register(sc)) for sc in app_cfg.services]
        for s in services:
            await s.start()

        cas_conns: list[tuple[asyncio.StreamReader, asyncio.StreamWriter]] = []
        osc_conns: list[tuple[asyncio.StreamReader, asyncio.StreamWriter]] = []
        try:
            deadline = time.monotonic() + 5.0
            while any(not st.listener_open for st in registry.services.values()) and time.monotonic() < deadline:
                await asyncio.sleep(0.02)
            self.assertEqual(sum(1 for st in registry.services.values() if st.listener_open), lane_count)

            # Connect 50 CAS + 50 OSCAR consumers (100 simultaneous TCP consumers)
            for p_port in proxy_ports:
                cas_conns.append(await asyncio.open_connection("127.0.0.1", p_port))
                osc_conns.append(await asyncio.open_connection("127.0.0.1", p_port))

            await asyncio.sleep(0.05)
            self.assertEqual(registry.snapshot()["total_active_clients"], 100)

            # Broadcast simultaneous occupied alarm burst across all 50 lanes and measure latency
            t0 = time.perf_counter()
            for idx in range(lane_count):
                msg = f"GA,0950,0940,0960,{idx:04d}\r\nGX,1,2000\r\n".encode("ascii")
                rpm_writers[idx][-1].write(msg)
            await asyncio.gather(*(rpm_writers[idx][-1].drain() for idx in range(lane_count)))

            async def read_burst(r: asyncio.StreamReader, idx: int) -> None:
                l1 = await asyncio.wait_for(r.readline(), timeout=2.0)
                l2 = await asyncio.wait_for(r.readline(), timeout=2.0)
                self.assertEqual(l1, f"GA,0950,0940,0960,{idx:04d}\r\n".encode("ascii"))
                self.assertEqual(l2, b"GX,1,2000\r\n")

            await asyncio.gather(
                *(read_burst(cas_conns[i][0], i) for i in range(lane_count)),
                *(read_burst(osc_conns[i][0], i) for i in range(lane_count)),
            )
            elapsed_ms = (time.perf_counter() - t0) * 1000.0
            print(f"[50-lane x 2-consumer = 100 sockets] 200 frames delivered in {elapsed_ms:.2f} ms")
            self.assertLess(elapsed_ms, 250.0)
        finally:
            for _, w in [*cas_conns, *osc_conns]:
                w.close()
            await asyncio.gather(*(s.stop() for s in services), return_exceptions=True)
            for group in rpm_writers:
                for w in group:
                    w.close()
            for srv in rpm_servers:
                srv.close()
                await srv.wait_closed()


if __name__ == "__main__":
    unittest.main(verbosity=2)
