#!/usr/bin/env python3
"""Create/start/stop/destroy VMs cloned from the Phase 5 template.

Shared auth/config logic intentionally kept separate from proxmox_stats.py
(small duplication) rather than refactoring that already-verified script.

Usage:
  vm_ops.py nextid
  vm_ops.py clone <newid> <name>
  vm_ops.py start <vmid>
  vm_ops.py stop <vmid>
  vm_ops.py destroy <vmid>

Prints "OK <message>" or "ERROR <message>" on stdout and exits non-zero on
failure, so create_vm.sh can show the result via a notification either way.
"""
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.request

CONFIG_PATH = os.path.expanduser("~/.config/hyprland-rice/proxmox.conf")

# Defaults per the build plan (Phase 5) — not read from config, since these
# are meant to be simple/fixed rather than another thing to configure.
DEFAULT_CORES = 2
DEFAULT_MEMORY = 2048
TEMPLATE_VMID = 9000


def load_config():
    config = {}
    with open(CONFIG_PATH) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            config[key.strip()] = value.strip()
    return config


def api_request(config, method, path, params=None):
    url = "https://{host}:{port}/api2/json{path}".format(
        host=config["PROXMOX_HOST"], port=config.get("PROXMOX_PORT", "8006"), path=path
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
    with urllib.request.urlopen(req, timeout=15, context=ctx) as resp:
        return json.loads(resp.read().decode())


def wait_for_task(config, node, upid, timeout=60):
    deadline = time.time() + timeout
    while time.time() < deadline:
        result = api_request(config, "GET", f"/nodes/{node}/tasks/{upid}/status")
        status = result.get("data", {})
        if status.get("status") == "stopped":
            if status.get("exitstatus") != "OK":
                raise RuntimeError(f"task failed: {status.get('exitstatus')}")
            return
        time.sleep(1)
    raise RuntimeError("timed out waiting for task to finish")


def cmd_nextid(config):
    result = api_request(config, "GET", "/cluster/nextid")
    print(f"OK {result['data']}")


def cmd_ip(config, vmid):
    node = config["PROXMOX_NODE"]
    result = api_request(config, "GET", f"/nodes/{node}/qemu/{vmid}/agent/network-get-interfaces")
    for iface in result.get("data", {}).get("result", []):
        if iface.get("name") == "lo":
            continue
        for addr in iface.get("ip-addresses", []):
            if addr.get("ip-address-type") == "ipv4":
                print(f"OK {addr['ip-address']}")
                return
    print("ERROR no non-loopback IPv4 address found (guest agent may still be starting)")
    sys.exit(1)


def cmd_clone(config, newid, name):
    node = config["PROXMOX_NODE"]
    result = api_request(
        config, "POST", f"/nodes/{node}/qemu/{TEMPLATE_VMID}/clone",
        {"newid": newid, "name": name, "full": 1},
    )
    upid = result["data"]
    wait_for_task(config, node, upid, timeout=120)
    # Tagged so the dashboard only ever offers to delete VMs it created
    # itself — never pre-existing guests like mineserver or hyprland-test.
    api_request(
        config, "POST", f"/nodes/{node}/qemu/{newid}/config",
        {"cores": DEFAULT_CORES, "memory": DEFAULT_MEMORY, "tags": "dashboard-managed"},
    )
    print(f"OK created VM {newid} ({name}), {DEFAULT_CORES} cores / {DEFAULT_MEMORY}MB")


def cmd_start(config, vmid):
    node = config["PROXMOX_NODE"]
    result = api_request(config, "POST", f"/nodes/{node}/qemu/{vmid}/status/start")
    wait_for_task(config, node, result["data"])
    print(f"OK started VM {vmid}")


def cmd_stop(config, vmid):
    node = config["PROXMOX_NODE"]
    result = api_request(config, "POST", f"/nodes/{node}/qemu/{vmid}/status/stop")
    wait_for_task(config, node, result["data"])
    print(f"OK stopped VM {vmid}")


def cmd_destroy(config, vmid):
    node = config["PROXMOX_NODE"]
    # Defense in depth: only ever destroy VMs this dashboard created and
    # tagged itself — never a pre-existing guest, even if the caller (UI)
    # somehow passed the wrong vmid.
    vm_config = api_request(config, "GET", f"/nodes/{node}/qemu/{vmid}/config")
    tags = vm_config.get("data", {}).get("tags", "")
    if "dashboard-managed" not in tags.split(";"):
        print(f"ERROR refusing to destroy VM {vmid} — not tagged dashboard-managed")
        sys.exit(1)

    # Refuse to force-destroy a running VM silently — caller must stop it first.
    status = api_request(config, "GET", f"/nodes/{node}/qemu/{vmid}/status/current")
    if status["data"]["status"] == "running":
        print(f"ERROR VM {vmid} is still running — stop it first")
        sys.exit(1)
    result = api_request(config, "DELETE", f"/nodes/{node}/qemu/{vmid}?purge=1")
    wait_for_task(config, node, result["data"])
    print(f"OK destroyed VM {vmid}")


def main():
    if len(sys.argv) < 2:
        print("ERROR usage: vm_ops.py <nextid|clone|start|stop|destroy> [args]")
        sys.exit(1)

    config = load_config()
    required = ["PROXMOX_HOST", "PROXMOX_NODE", "PROXMOX_TOKEN_ID", "PROXMOX_TOKEN_SECRET"]
    if not all(k in config and config[k] for k in required):
        print(f"ERROR {CONFIG_PATH} is missing or incomplete — run bootstrap.sh")
        sys.exit(1)

    action = sys.argv[1]
    try:
        if action == "nextid":
            cmd_nextid(config)
        elif action == "clone":
            cmd_clone(config, sys.argv[2], sys.argv[3])
        elif action == "start":
            cmd_start(config, sys.argv[2])
        elif action == "stop":
            cmd_stop(config, sys.argv[2])
        elif action == "destroy":
            cmd_destroy(config, sys.argv[2])
        elif action == "ip":
            cmd_ip(config, sys.argv[2])
        else:
            print(f"ERROR unknown action: {action}")
            sys.exit(1)
    except urllib.error.HTTPError as e:
        print(f"ERROR Proxmox API returned HTTP {e.code}: {e.read().decode()[:200]}")
        sys.exit(1)
    except Exception as e:
        print(f"ERROR {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
