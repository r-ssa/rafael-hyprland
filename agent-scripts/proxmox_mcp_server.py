#!/usr/bin/env python3
"""Proxmox MCP server (Phase 7, Tier 2).

Exposes list/status/start/stop/snapshot for Proxmox guests to Claude Code.
Deliberately does NOT expose delete/destroy — that stays behind the eww
dashboard's explicit rofi confirmation (Phase 5), not a one-shot tool call
an ambiguous natural-language request could trigger without that same
confirmation step.

Registered via: claude mcp add proxmox -s user -- python3 ~/agent-scripts/proxmox_mcp_server.py
"""
import json
import os
import ssl
import urllib.error
import urllib.request

from mcp.server.mcpserver import MCPServer

CONFIG_PATH = os.path.expanduser("~/.config/hyprland-rice/proxmox.conf")

mcp = MCPServer("proxmox")


def _load_config():
    config = {}
    with open(CONFIG_PATH) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            config[key.strip()] = value.strip()
    required = ["PROXMOX_HOST", "PROXMOX_NODE", "PROXMOX_TOKEN_ID", "PROXMOX_TOKEN_SECRET"]
    if not all(k in config and config[k] for k in required):
        raise RuntimeError(f"{CONFIG_PATH} is missing or incomplete — run bootstrap.sh")
    config.setdefault("PROXMOX_PORT", "8006")
    config.setdefault("PROXMOX_VERIFY_SSL", "false")
    return config


def _api_request(method, path, params=None):
    config = _load_config()
    url = "https://{host}:{port}/api2/json{path}".format(
        host=config["PROXMOX_HOST"], port=config["PROXMOX_PORT"], path=path
    )
    data = None
    if params is not None:
        data = "&".join(f"{k}={v}" for k, v in params.items()).encode()
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header(
        "Authorization",
        "PVEAPIToken={token_id}={secret}".format(
            token_id=config["PROXMOX_TOKEN_ID"], secret=config["PROXMOX_TOKEN_SECRET"]
        ),
    )
    ctx = ssl.create_default_context()
    if config.get("PROXMOX_VERIFY_SSL", "false").lower() not in ("1", "true", "yes"):
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    try:
        with urllib.request.urlopen(req, timeout=15, context=ctx) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"Proxmox API HTTP {e.code}: {e.read().decode()[:300]}")


@mcp.tool()
def list_vms() -> str:
    """List all VMs/CTs on the Proxmox node with their status, CPU, and memory usage."""
    result = _api_request("GET", "/cluster/resources")
    guests = [item for item in result.get("data", []) if item.get("type") in ("qemu", "lxc")]
    return json.dumps(guests, indent=2)


@mcp.tool()
def vm_status(vmid: int) -> str:
    """Get detailed current status for a specific VM/CT by its vmid."""
    config = _load_config()
    node = config["PROXMOX_NODE"]
    result = _api_request("GET", f"/nodes/{node}/qemu/{vmid}/status/current")
    return json.dumps(result.get("data", {}), indent=2)


@mcp.tool()
def start_vm(vmid: int) -> str:
    """Start a VM by its vmid. Works on any guest, including pre-existing ones."""
    config = _load_config()
    node = config["PROXMOX_NODE"]
    _api_request("POST", f"/nodes/{node}/qemu/{vmid}/status/start")
    return f"Start requested for VM {vmid}"


@mcp.tool()
def stop_vm(vmid: int) -> str:
    """Stop (power off) a VM by its vmid. Works on any guest, including
    pre-existing ones — confirm with the user before calling this on
    anything that looks like a production service."""
    config = _load_config()
    node = config["PROXMOX_NODE"]
    _api_request("POST", f"/nodes/{node}/qemu/{vmid}/status/stop")
    return f"Stop requested for VM {vmid}"


@mcp.tool()
def snapshot_vm(vmid: int, snapshot_name: str) -> str:
    """Create a snapshot of a VM by its vmid, with the given snapshot name."""
    config = _load_config()
    node = config["PROXMOX_NODE"]
    _api_request("POST", f"/nodes/{node}/qemu/{vmid}/snapshot", {"snapname": snapshot_name})
    return f"Snapshot '{snapshot_name}' requested for VM {vmid}"


if __name__ == "__main__":
    mcp.run()
