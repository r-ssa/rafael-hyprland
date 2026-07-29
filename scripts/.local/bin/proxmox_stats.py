#!/usr/bin/env python3
"""Poll the Proxmox API for node/VM/CT stats.

Shared by the Waybar custom/proxmox module and the eww Proxmox dashboard
window (Phase 4) — both just run this and parse its stdout JSON, so the
API/auth/error-classification logic lives in exactly one place.

Config is read from ~/.config/hyprland-rice/proxmox.conf, generated
interactively by bootstrap.sh and never committed to the repo (see
Phase 0's secrets decision). Format is simple KEY=VALUE lines:

    PROXMOX_HOST=192.168.1.71
    PROXMOX_PORT=8006
    PROXMOX_NODE=pve
    PROXMOX_TOKEN_ID=dashboard@pve!dashboard-token
    PROXMOX_TOKEN_SECRET=...
    PROXMOX_VERIFY_SSL=false

Output is always a single JSON object on stdout with a "status" field:
  ok            - request succeeded, "node" and "guests" are populated
  network_down  - couldn't even reach the local gateway (your network, not Proxmox)
  unreachable   - gateway is fine but the Proxmox host didn't respond (connection refused/reset)
  timeout       - connection was attempted but the host is slow/not responding in time
  auth_error    - got a response but the token was rejected (401/403)
  api_error     - got a response but something else was wrong
  config_error  - proxmox.conf is missing or incomplete
"""
import json
import os
import socket
import ssl
import subprocess
import sys
import urllib.error
import urllib.request

CONFIG_PATH = os.path.expanduser("~/.config/hyprland-rice/proxmox.conf")
CONNECT_TIMEOUT = 3
READ_TIMEOUT = 5


def load_config():
    if not os.path.exists(CONFIG_PATH):
        return None
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
        return None
    config.setdefault("PROXMOX_PORT", "8006")
    config.setdefault("PROXMOX_VERIFY_SSL", "false")
    return config


def default_gateway():
    try:
        out = subprocess.run(
            ["ip", "route", "show", "default"],
            capture_output=True, text=True, timeout=2,
        ).stdout
        parts = out.split()
        if "via" in parts:
            return parts[parts.index("via") + 1]
    except Exception:
        pass
    return None


def local_network_is_up():
    gateway = default_gateway()
    if not gateway:
        return False
    for port in (80, 443, 22):
        try:
            with socket.create_connection((gateway, port), timeout=1.5):
                return True
        except OSError:
            continue
    return False


def fetch(config):
    url = "https://{host}:{port}/api2/json/cluster/resources".format(
        host=config["PROXMOX_HOST"], port=config["PROXMOX_PORT"]
    )
    req = urllib.request.Request(url)
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
        with urllib.request.urlopen(req, timeout=READ_TIMEOUT, context=ctx) as resp:
            body = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            return {"status": "auth_error", "message": f"Proxmox rejected the API token (HTTP {e.code})"}
        return {"status": "api_error", "message": f"Proxmox API returned HTTP {e.code}"}
    except (socket.timeout, TimeoutError):
        return {"status": "timeout", "message": "Proxmox host is not responding (timed out)"}
    except (urllib.error.URLError, OSError) as e:
        reason = getattr(e, "reason", e)
        if isinstance(reason, socket.timeout):
            return {"status": "timeout", "message": "Proxmox host is not responding (timed out)"}
        if local_network_is_up():
            return {"status": "unreachable", "message": f"Proxmox host unreachable: {reason}"}
        return {"status": "network_down", "message": "Local network appears to be down"}

    node_name = config["PROXMOX_NODE"]
    node = None
    guests = []
    for item in body.get("data", []):
        if item.get("type") == "node" and item.get("node") == node_name:
            maxmem = item.get("maxmem") or 1
            maxdisk = item.get("maxdisk") or 1
            node = {
                "cpu_pct": round((item.get("cpu") or 0) * 100, 1),
                "mem_pct": round((item.get("mem") or 0) / maxmem * 100, 1),
                "disk_pct": round((item.get("disk") or 0) / maxdisk * 100, 1),
                "uptime": item.get("uptime", 0),
            }
        elif item.get("type") in ("qemu", "lxc"):
            maxmem = item.get("maxmem") or 1
            tags = (item.get("tags") or "").split(";")
            guests.append({
                "vmid": item.get("vmid"),
                "name": item.get("name"),
                "type": item.get("type"),
                "status": item.get("status"),
                "cpu_pct": round((item.get("cpu") or 0) * 100, 1),
                "mem_pct": round((item.get("mem") or 0) / maxmem * 100, 1),
                # Only VMs the dashboard itself created/tagged are safe to
                # offer a delete button for — never pre-existing guests.
                "dashboard_managed": "dashboard-managed" in tags,
            })

    guests.sort(key=lambda g: (g["status"] != "running", g["name"] or ""))
    return {"status": "ok", "node": node, "guests": guests}


def main():
    config = load_config()
    if config is None:
        print(json.dumps({
            "status": "config_error",
            "message": f"{CONFIG_PATH} is missing or incomplete — run bootstrap.sh",
        }))
        return
    print(json.dumps(fetch(config)))


if __name__ == "__main__":
    main()
