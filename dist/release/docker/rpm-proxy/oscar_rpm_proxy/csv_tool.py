from __future__ import annotations

import csv
import io
import ipaddress
import json
import re
from pathlib import Path
from typing import Any

from .config import ConfigError, load_config


_SAFE_SERVICE_RE = re.compile(r"[^A-Za-z0-9_.-]+")


def _sanitize_service_name(raw: str, fallback_index: int) -> str:
    cleaned = _SAFE_SERVICE_RE.sub("-", raw.strip()).strip("-.")
    if not cleaned or not cleaned[0].isalnum():
        cleaned = f"lane-{fallback_index:02d}"
    return cleaned[:64]


def generate_proxy_config_from_csv(
    csv_path: Path,
    *,
    output_config_path: Path,
    mode: str = "port-map",
    listen_host: str = "0.0.0.0",
    base_port: int = 11601,
    vip_start_ip: str | None = None,
    vip_port: int = 1600,
    include_loopback_listener: bool = True,
    oscar_target_host: str = "127.0.0.1",
    upstream_interface: str | None = None,
    source_ip: str | None = None,
    allowed_clients: list[str] | None = None,
    primary_write_clients: list[str] | None = None,
    client_writes: str = "discard",
    idle_timeout_seconds: float = 4.0,
    first_line_timeout_seconds: float = 4.0,
    status_listen: str = "127.0.0.1:9090",
    emit_oscar_csv_path: Path | None = None,
    emit_vip_list_path: Path | None = None,
) -> dict[str, Any]:
    """Build an oscar-rpm-proxy config.json (and optional proxied 20-column OSCAR config.csv)
    from either an existing 20-column OSCAR lane CSV or a dedicated proxy lane CSV."""
    if mode not in {"port-map", "virtual-ip"}:
        raise ConfigError("mode must be 'port-map' or 'virtual-ip'")
    if not 1024 <= base_port <= 65000:
        raise ConfigError("base_port must be between 1024 and 65000")
    if not 1 <= vip_port <= 65535:
        raise ConfigError("vip_port must be between 1 and 65535")

    raw_text = csv_path.read_text(encoding="utf-8-sig")
    comment_lines: list[str] = []
    data_lines: list[str] = []
    for raw_line in raw_text.splitlines():
        stripped = raw_line.strip()
        if not stripped:
            continue
        if stripped.startswith("#"):
            comment_lines.append(raw_line)
        else:
            data_lines.append(raw_line)

    if not data_lines:
        raise ConfigError(f"{csv_path} contains no CSV header or rows")

    reader = csv.reader(io.StringIO("\n".join(data_lines)))
    rows = list(reader)
    header = [col.strip() for col in rows[0]]
    col_idx = {name: idx for idx, name in enumerate(header)}

    is_oscar_20col = "RPMConfigType" in col_idx and "RPMHost" in col_idx and "RPMPort" in col_idx
    is_dedicated = ("UpstreamHost" in col_idx or "RPMHost" in col_idx) and (
        "UpstreamPort" in col_idx or "RPMPort" in col_idx
    )
    if not is_oscar_20col and not is_dedicated:
        raise ConfigError(
            f"{csv_path} must be either an OSCAR 20-column lane CSV (Name,UniqueID,...,RPMConfigType,RPMHost,RPMPort,...) "
            "or a proxy CSV (Name,UpstreamHost,UpstreamPort[,ListenHost,ListenPort,UpstreamInterface])"
        )

    vip_cursor: ipaddress.IPv4Address | None = None
    if mode == "virtual-ip" and vip_start_ip:
        addr = ipaddress.ip_address(vip_start_ip)
        if not isinstance(addr, ipaddress.IPv4Address):
            raise ConfigError("vip_start_ip must be an IPv4 address")
        vip_cursor = addr

    services: list[dict[str, Any]] = []
    emitted_oscar_rows: list[list[str]] = [header]
    allocated_vips: list[str] = []
    seen_names: set[str] = set()
    proxy_index = 0

    for row_num, row in enumerate(rows[1:], start=2):
        if not any(cell.strip() for cell in row):
            continue
        padded = list(row) + [""] * max(0, len(header) - len(row))

        if is_oscar_20col:
            rpm_type = padded[col_idx["RPMConfigType"]].strip()
            if rpm_type.lower() != "rapiscan":
                emitted_oscar_rows.append(padded[: len(header)])
                continue
            raw_name = padded[col_idx.get("UniqueID", col_idx.get("Name", 0))].strip() or padded[0].strip()
            upstream_host = padded[col_idx["RPMHost"]].strip()
            upstream_port_str = padded[col_idx["RPMPort"]].strip()
            row_listen_host = ""
            row_listen_port_str = ""
            row_iface = upstream_interface
            row_src_ip = source_ip
        else:
            name_col = col_idx.get("Name", col_idx.get("LaneName", 0))
            raw_name = padded[name_col].strip()
            u_host_col = col_idx.get("UpstreamHost", col_idx.get("RPMHost", -1))
            u_port_col = col_idx.get("UpstreamPort", col_idx.get("RPMPort", -1))
            upstream_host = padded[u_host_col].strip()
            upstream_port_str = padded[u_port_col].strip()
            row_listen_host = padded[col_idx["ListenHost"]].strip() if "ListenHost" in col_idx else ""
            row_listen_port_str = padded[col_idx["ListenPort"]].strip() if "ListenPort" in col_idx else ""
            row_iface = (
                padded[col_idx["UpstreamInterface"]].strip()
                if "UpstreamInterface" in col_idx and padded[col_idx["UpstreamInterface"]].strip()
                else upstream_interface
            )
            row_src_ip = (
                padded[col_idx["SourceIp"]].strip()
                if "SourceIp" in col_idx and padded[col_idx["SourceIp"]].strip()
                else source_ip
            )

        if not upstream_host or not upstream_port_str:
            raise ConfigError(f"{csv_path}:{row_num}: missing upstream RPM host or port")
        try:
            upstream_port = int(upstream_port_str)
        except ValueError as exc:
            raise ConfigError(f"{csv_path}:{row_num}: invalid upstream port {upstream_port_str!r}") from exc

        svc_name = _sanitize_service_name(raw_name, proxy_index + 1)
        if svc_name in seen_names:
            svc_name = f"{svc_name}-{proxy_index + 1}"
        seen_names.add(svc_name)

        mapped_port = int(row_listen_port_str) if row_listen_port_str else (base_port + proxy_index)
        listen_endpoints: list[str] = []

        if mode == "virtual-ip":
            if row_listen_host:
                vip_ip = row_listen_host
            elif vip_cursor is not None:
                vip_ip = str(vip_cursor + proxy_index)
            else:
                raise ConfigError("virtual-ip mode requires --vip-start-ip or a ListenHost CSV column")
            vip_listen_port = int(row_listen_port_str) if row_listen_port_str else vip_port
            listen_endpoints.append(f"{vip_ip}:{vip_listen_port}")
            allocated_vips.append(vip_ip)
            if include_loopback_listener and vip_ip != "127.0.0.1":
                listen_endpoints.append(f"127.0.0.1:{base_port + proxy_index}")
                oscar_port_for_row = base_port + proxy_index
                oscar_host_for_row = oscar_target_host
            else:
                oscar_port_for_row = vip_listen_port
                oscar_host_for_row = vip_ip if oscar_target_host == "127.0.0.1" else oscar_target_host
        else:
            eff_host = row_listen_host or listen_host
            listen_endpoints.append(f"{eff_host}:{mapped_port}")
            oscar_host_for_row = oscar_target_host
            oscar_port_for_row = mapped_port

        upstream_obj: dict[str, Any] = {"address": f"{upstream_host}:{upstream_port}"}
        if row_iface:
            upstream_obj["interface"] = row_iface
        if row_src_ip:
            upstream_obj["source_ip"] = row_src_ip

        svc_entry: dict[str, Any] = {
            "name": svc_name,
            "kind": "rpm_broadcast",
            "listen": listen_endpoints,
            "upstream": upstream_obj,
            "client_writes": client_writes,
            "disconnect_clients_on_upstream_loss": True,
            "gate_listener_on_upstream": True,
            "line_framed": True,
            "replay_rapiscan_setup": True,
            "connect_timeout_seconds": 3.0,
            "reconnect_delay_seconds": 2.0,
            "idle_timeout_seconds": idle_timeout_seconds,
            "first_line_timeout_seconds": first_line_timeout_seconds,
            "drain_timeout_seconds": 5.0,
            "queue_packets": 64,
            "required": False,
        }
        if allowed_clients:
            svc_entry["allowed_clients"] = allowed_clients
        if primary_write_clients:
            svc_entry["primary_write_clients"] = primary_write_clients

        services.append(svc_entry)

        if is_oscar_20col:
            updated_row = list(padded[: len(header)])
            updated_row[col_idx["RPMHost"]] = oscar_host_for_row
            updated_row[col_idx["RPMPort"]] = str(oscar_port_for_row)
            emitted_oscar_rows.append(updated_row)

        proxy_index += 1

    if not services:
        raise ConfigError(f"No Rapiscan RPM rows were found in {csv_path}")

    config_doc = {
        "version": 1,
        "log_level": "INFO",
        "status": {"listen": status_listen},
        "services": services,
    }
    output_config_path.parent.mkdir(parents=True, exist_ok=True)
    output_config_path.write_text(json.dumps(config_doc, indent=2) + "\n", encoding="utf-8")

    # Self-validate generated JSON against strict AppConfig schema
    load_config(output_config_path)

    emitted_oscar_csv: str | None = None
    if emit_oscar_csv_path is not None and is_oscar_20col:
        buf = io.StringIO()
        writer = csv.writer(buf, lineterminator="\n")
        writer.writerows(emitted_oscar_rows)
        csv_out = buf.getvalue()
        if comment_lines:
            csv_out += "\n".join(comment_lines) + "\n"
        emit_oscar_csv_path.parent.mkdir(parents=True, exist_ok=True)
        emit_oscar_csv_path.write_text(csv_out, encoding="utf-8")
        emitted_oscar_csv = str(emit_oscar_csv_path)

    if emit_vip_list_path is not None:
        emit_vip_list_path.parent.mkdir(parents=True, exist_ok=True)
        emit_vip_list_path.write_text("\n".join(allocated_vips) + ("\n" if allocated_vips else ""), encoding="utf-8")

    return {
        "lane_count": len(services),
        "mode": mode,
        "output_config": str(output_config_path),
        "emitted_oscar_csv": emitted_oscar_csv,
        "allocated_vips": allocated_vips,
        "port_range": f"{base_port}-{base_port + len(services) - 1}",
    }
