from __future__ import annotations

import argparse
import asyncio
import errno
import json
import logging
import os
import signal
import urllib.request
from pathlib import Path

from . import __version__
from .config import ConfigError, load_config
from .csv_tool import generate_proxy_config_from_csv
from .http_status import StatusServer
from .network import create_service
from .state import Registry
from .watchdog import EventLoopWatchdog


LOGGER = logging.getLogger("oscar_rpm_proxy")


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="OSCAR real-time multi-lane Rapiscan RPM TCP fan-out proxy for side-by-side CAS deployments"
    )
    parser.add_argument("--config", default="/config/config.json", help="path to JSON configuration")
    parser.add_argument("--validate", action="store_true", help="validate configuration and exit")
    parser.add_argument("--check", metavar="URL", help="HTTP health check URL and exit")
    parser.add_argument("--generate-from-csv", metavar="CSV", help="generate proxy config.json from lane CSV and exit")
    parser.add_argument("--mode", choices=["port-map", "virtual-ip"], default="port-map")
    parser.add_argument("--listen-host", default="0.0.0.0")
    parser.add_argument("--base-port", type=int, default=11601)
    parser.add_argument("--vip-start-ip", default=None)
    parser.add_argument("--vip-port", type=int, default=1600)
    parser.add_argument("--no-loopback-listener", action="store_true")
    parser.add_argument("--oscar-target-host", default="127.0.0.1")
    parser.add_argument("--upstream-interface", default=None)
    parser.add_argument("--source-ip", default=None)
    parser.add_argument("--allowed-client", action="append", default=[])
    parser.add_argument("--primary-write-client", action="append", default=[])
    parser.add_argument("--client-writes", choices=["discard", "allow_primary", "forward"], default="discard")
    parser.add_argument("--idle-timeout-seconds", type=float, default=4.0)
    parser.add_argument("--first-line-timeout-seconds", type=float, default=4.0)
    parser.add_argument("--status-listen", default="127.0.0.1:9090")
    parser.add_argument("--emit-oscar-csv", default=None)
    parser.add_argument("--emit-vip-list", default=None)
    parser.add_argument("--version", action="version", version=__version__)
    return parser.parse_args()


def _health_check(url: str) -> int:
    try:
        with urllib.request.urlopen(url, timeout=3) as response:
            return 0 if response.status == 200 else 1
    except Exception:
        return 1


async def run(config_path: Path) -> None:
    config = load_config(config_path)
    logging.getLogger().setLevel(config.log_level)
    registry = Registry()
    services = []
    for service_config in config.services:
        if not service_config.enabled:
            continue
        stats = registry.register(service_config)
        services.append(create_service(service_config, stats))
    status = StatusServer(config.status_listen, registry)
    started = []
    watchdog_timeout = float(os.environ.get("OSCAR_RPM_PROXY_WATCHDOG_SECONDS", "30"))
    watchdog = EventLoopWatchdog(watchdog_timeout)
    watchdog.start()
    watchdog_task = asyncio.create_task(watchdog.pulse(), name="event-loop-watchdog-pulse")
    try:
        while True:
            started.clear()
            try:
                for service in services:
                    try:
                        await service.start()
                    except Exception:
                        await service.stop()
                        raise
                    started.append(service)
                await status.start()
                break
            except OSError as exc:
                for service in reversed(started):
                    await service.stop()
                if exc.errno != errno.EADDRNOTAVAIL:
                    raise
                LOGGER.warning("listener address is not assigned yet; waiting for host network: %s", exc)
                await asyncio.sleep(2)
    except Exception:
        watchdog_task.cancel()
        await asyncio.gather(watchdog_task, return_exceptions=True)
        watchdog.stop()
        for service in reversed(started):
            await service.stop()
        raise

    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop_event.set)
        except NotImplementedError:
            pass
    LOGGER.info("OSCAR RPM Edge Proxy %s started with %d lane service(s)", __version__, len(services))
    await stop_event.wait()
    LOGGER.info("shutdown requested")
    await status.stop()
    for service in reversed(services):
        await service.stop()
    watchdog_task.cancel()
    await asyncio.gather(watchdog_task, return_exceptions=True)
    watchdog.stop()


def main() -> None:
    args = _arguments()
    if args.check:
        raise SystemExit(_health_check(args.check))
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    try:
        if args.generate_from_csv:
            summary = generate_proxy_config_from_csv(
                Path(args.generate_from_csv),
                output_config_path=Path(args.config),
                mode=args.mode,
                listen_host=args.listen_host,
                base_port=args.base_port,
                vip_start_ip=args.vip_start_ip,
                vip_port=args.vip_port,
                include_loopback_listener=not args.no_loopback_listener,
                oscar_target_host=args.oscar_target_host,
                upstream_interface=args.upstream_interface,
                source_ip=args.source_ip,
                allowed_clients=args.allowed_client or None,
                primary_write_clients=args.primary_write_client or None,
                client_writes=args.client_writes,
                idle_timeout_seconds=args.idle_timeout_seconds,
                first_line_timeout_seconds=args.first_line_timeout_seconds,
                status_listen=args.status_listen,
                emit_oscar_csv_path=Path(args.emit_oscar_csv) if args.emit_oscar_csv else None,
                emit_vip_list_path=Path(args.emit_vip_list) if args.emit_vip_list else None,
            )
            print(json.dumps(summary, indent=2))
            return
        config = load_config(args.config)
        if args.validate:
            enabled = sum(1 for service in config.services if service.enabled)
            print(f"configuration valid: {enabled} enabled service(s)")
            return
        asyncio.run(run(Path(args.config)))
    except ConfigError as exc:
        LOGGER.error("configuration error: %s", exc)
        raise SystemExit(2) from exc
    except KeyboardInterrupt:
        return
    except Exception as exc:
        LOGGER.error("fatal error: %s", exc, exc_info=True)
        raise SystemExit(1) from exc
