#!/usr/bin/env python3
"""Aggregate stats for the always-on desktop performance widget:
local desktop (CPU/RAM/disks/RTX 3080), ollama-host (backup drive space,
RX 580 strain), and the Proxmox host + VMs (via the existing
proxmox_stats.py, reused rather than re-implemented).

Always prints a single JSON object on stdout, never raises — any section
that fails just gets an "error" field so the widget can show a partial
view instead of nothing.
"""
import json
import subprocess


def local_stats():
    out = {}
    try:
        free = subprocess.run(["free", "-m"], capture_output=True, text=True, timeout=5).stdout
        mem_line = [l for l in free.splitlines() if l.startswith("Mem:")][0].split()
        total, used = int(mem_line[1]), int(mem_line[2])
        out["ram_pct"] = round(used / total * 100, 1)
        out["ram_used_gb"] = round(used / 1024, 1)
        out["ram_total_gb"] = round(total / 1024, 1)
    except Exception as e:
        out["ram_error"] = str(e)

    try:
        loadavg = open("/proc/loadavg").read().split()[0]
        out["load1"] = float(loadavg)
    except Exception as e:
        out["cpu_error"] = str(e)

    try:
        disks = []
        df = subprocess.run(
            ["df", "-B1", "--output=target,size,used,pcent", "/", "/home"],
            capture_output=True, text=True, timeout=5,
        ).stdout.splitlines()[1:]
        for line in df:
            parts = line.split()
            if len(parts) < 4:
                continue
            target, size, used, pcent = parts[0], int(parts[1]), int(parts[2]), parts[3].rstrip("%")
            disks.append({
                "mount": target,
                "used_gb": round(used / 1e9, 1),
                "total_gb": round(size / 1e9, 1),
                "pct": float(pcent) if pcent.replace(".", "").isdigit() else 0,
            })
        out["disks"] = disks
    except Exception as e:
        out["disks_error"] = str(e)

    try:
        gpu = subprocess.run(
            ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5,
        ).stdout.strip()
        util, mem_used, mem_total, temp = [x.strip() for x in gpu.split(",")]
        out["gpu"] = {
            "name": "RTX 3080", "util_pct": float(util),
            "mem_used_mb": float(mem_used), "mem_total_mb": float(mem_total),
            "temp_c": float(temp),
        }
    except Exception as e:
        out["gpu_error"] = str(e)

    return out


def ollama_host_stats():
    out = {}
    try:
        result = subprocess.run(
            ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "rafael@192.168.1.97",
             "df -B1 --output=target,size,used,pcent /mnt/mass_storage /mnt/backups 2>/dev/null; "
             "echo ---GPU---; cat /sys/class/drm/card0/device/gpu_busy_percent 2>/dev/null"],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            out["error"] = result.stderr.strip() or "ssh failed"
            return out
        text, _, gpu_part = result.stdout.partition("---GPU---")
        disks = []
        for line in text.strip().splitlines()[1:]:
            parts = line.split()
            if len(parts) < 4:
                continue
            target, size, used, pcent = parts[0], int(parts[1]), int(parts[2]), parts[3].rstrip("%")
            disks.append({
                "mount": target,
                "used_gb": round(used / 1e9, 1),
                "total_gb": round(size / 1e9, 1),
                "pct": float(pcent) if pcent.replace(".", "").isdigit() else 0,
            })
        out["backup_disks"] = disks
        gpu_val = gpu_part.strip()
        out["rx580_busy_pct"] = float(gpu_val) if gpu_val.replace(".", "").isdigit() else None
    except Exception as e:
        out["error"] = str(e)
    return out


def proxmox_stats():
    try:
        result = subprocess.run(
            ["python3", "/home/rafael/.local/bin/proxmox_stats.py"],
            capture_output=True, text=True, timeout=10,
        )
        return json.loads(result.stdout)
    except Exception as e:
        return {"status": "error", "message": str(e)}


def main():
    print(json.dumps({
        "local": local_stats(),
        "ollama_host": ollama_host_stats(),
        "proxmox": proxmox_stats(),
    }))


if __name__ == "__main__":
    main()
