#!/usr/bin/env python3
"""Claude-Code-style terminal chat UI for qwen2.5:3b, with an agentic
coding mode (file/bash tools) and a live GPU-strain readout. Runs locally;
talks to Ollama on ollama-host over an SSH tunnel (set up by
launch-qwen-session.sh), and routes tool calls to whichever host was
picked at session start (env QWEN_TARGET_HOST: "local" or "user@host")."""
import base64
import json
import os
import queue
import random
import re
import shlex
import subprocess
import sys
import threading
import time
import urllib.request

from pyfiglet import Figlet
from prompt_toolkit import prompt as pt_prompt
from prompt_toolkit.styles import Style as PTStyle
from rich.align import Align
from rich.console import Console
from rich.live import Live
from rich.markdown import Markdown
from rich.panel import Panel
from rich.spinner import Spinner
from rich.text import Text

BLUE = "#00afff"
MODEL = "qwen2.5:3b"
OLLAMA_URL = "http://localhost:11434/api/chat"
GPU_HOST = "rafael@192.168.1.97"  # ollama-host — where the RX 580 lives
TARGET = os.environ.get("QWEN_TARGET_HOST", "local")

THINKING_VERBS = [
    "Pondering", "Percolating", "Noodling", "Ruminating", "Synthesizing",
    "Deliberating", "Composing", "Untangling", "Calculating", "Musing",
    "Contemplating", "Brewing",
]

console = Console()
auto_mode = True
gpu_pct = None


# --- tool execution: routes to $TARGET (local exec, or single-hop ssh) ----

def _run_local(cmd, input_bytes=None):
    result = subprocess.run(
        cmd, shell=True, input=input_bytes,
        capture_output=True, timeout=60,
    )
    return result.returncode, result.stdout.decode(errors="replace"), result.stderr.decode(errors="replace")


def _run_remote(cmd, input_bytes=None):
    result = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", TARGET, cmd],
        input=input_bytes, capture_output=True, timeout=60,
    )
    return result.returncode, result.stdout.decode(errors="replace"), result.stderr.decode(errors="replace")


def run_on_target(cmd, input_bytes=None):
    if TARGET == "local":
        return _run_local(cmd, input_bytes)
    return _run_remote(cmd, input_bytes)


def tool_read_file(path):
    rc, out, err = run_on_target(f"cat {shlex.quote(path)}")
    if rc != 0:
        return f"ERROR: {err.strip() or 'file not readable'}"
    return out


def tool_write_file(path, content):
    b64 = base64.b64encode(content.encode()).decode()
    cmd = f"mkdir -p $(dirname {shlex.quote(path)}) && base64 -d > {shlex.quote(path)}"
    rc, out, err = run_on_target(cmd, input_bytes=b64.encode())
    if rc != 0:
        return f"ERROR: {err.strip()}"
    return f"wrote {len(content)} bytes to {path}"


def tool_edit_file(path, old_string, new_string):
    current = tool_read_file(path)
    if current.startswith("ERROR:"):
        return current
    if old_string not in current:
        return "ERROR: old_string not found in file — no changes made"
    if current.count(old_string) > 1:
        return "ERROR: old_string is not unique in file — no changes made, provide more context"
    updated = current.replace(old_string, new_string, 1)
    return tool_write_file(path, updated)


def tool_run_bash(command):
    rc, out, err = run_on_target(command)
    combined = (out or "") + (("\n" + err) if err else "")
    combined = combined[:8000]
    return f"(exit {rc})\n{combined}"


TOOLS_SCHEMA = [
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Read the full contents of a text file.",
            "parameters": {
                "type": "object",
                "properties": {"path": {"type": "string", "description": "Absolute or ~-relative path"}},
                "required": ["path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "write_file",
            "description": "Create a file or overwrite it entirely with new content.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string"},
                    "content": {"type": "string"},
                },
                "required": ["path", "content"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "edit_file",
            "description": "Replace one exact occurrence of old_string with new_string in an existing file.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string"},
                    "old_string": {"type": "string"},
                    "new_string": {"type": "string"},
                },
                "required": ["path", "old_string", "new_string"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "run_bash",
            "description": "Run a shell command and return its stdout/stderr/exit code.",
            "parameters": {
                "type": "object",
                "properties": {"command": {"type": "string"}},
                "required": ["command"],
            },
        },
    },
]

TOOL_FUNCS = {
    "read_file": lambda a: tool_read_file(a["path"]),
    "write_file": lambda a: tool_write_file(a["path"], a["content"]),
    "edit_file": lambda a: tool_edit_file(a["path"], a["old_string"], a["new_string"]),
    "run_bash": lambda a: tool_run_bash(a["command"]),
}


def system_prompt():
    where = "your local machine" if TARGET == "local" else f"the remote host {TARGET}"
    return (
        "You are a terminal coding assistant (like Claude Code) running qwen2.5:3b. "
        f"When the user asks you to read, write, edit, or run something, use the provided "
        f"tools — they operate on {where}. Use run_bash for anything not covered by the "
        "file tools (listing directories, git, package managers, etc). Be direct: use tools "
        "rather than describing what you would do. Keep prose replies concise."
    )


# --- GPU strain polling (background thread, ollama-host's RX 580) ---------

def poll_gpu():
    global gpu_pct
    while True:
        try:
            result = subprocess.run(
                ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", GPU_HOST,
                 "cat /sys/class/drm/card0/device/gpu_busy_percent"],
                capture_output=True, timeout=10,
            )
            if result.returncode == 0:
                gpu_pct = result.stdout.decode().strip()
        except Exception:
            pass
        time.sleep(4)


# --- UI ---------------------------------------------------------------

def print_banner():
    fig = Figlet(font="small")
    banner = fig.renderText("QWEN 2.5").rstrip("\n")
    console.print(Align.center(Text(banner, style=f"bold {BLUE}")))
    console.print(Align.center(Text("qwen2.5:3b · via Ollama on ollama-host · Vulkan/RX580 accelerated", style=f"dim {BLUE}")))
    console.print()
    target_label = "local machine" if TARGET == "local" else TARGET
    console.print(Align.center(Text(f"working on: {target_label}  ·  auto mode: {'ON' if auto_mode else 'off'}", style=f"dim {BLUE}")))
    console.print(Align.center(Text('Type a message  ·  "/auto" toggles auto mode  ·  "exit" or Ctrl+C to quit', style="dim")))
    console.print()


def status_line():
    gpu_str = f"{gpu_pct}%" if gpu_pct is not None else "…"
    target_label = "local" if TARGET == "local" else TARGET
    return Text(f"  {target_label}  ·  auto:{'on' if auto_mode else 'off'}  ·  RX580 {gpu_str}", style=f"dim {BLUE}")


def box_width():
    return max(20, min(console.width - 2, 100))


def box_line(left, mid, right):
    return Text(left + mid * box_width() + right, style=BLUE)


def get_user_input():
    console.print(status_line())
    console.print(box_line("╭", "─", "╮"))
    style = PTStyle.from_dict({"prompt": f"fg:{BLUE} bold"})
    try:
        text = pt_prompt([("class:prompt", "│ > ")], style=style)
    finally:
        console.print(box_line("╰", "─", "╯"))
    return text.strip()


def confirm_tool_call(name, args):
    console.print(Panel(Text(json.dumps(args, indent=2)), title=f"[bold]{name}[/bold] — run this?", border_style="yellow", padding=(0, 1)))
    answer = pt_prompt("  Allow? [y/N] ").strip().lower()
    return answer in ("y", "yes")


def ollama_chat(messages, stream_final=False):
    payload = {"model": MODEL, "messages": messages, "tools": TOOLS_SCHEMA, "stream": False}
    req = urllib.request.Request(
        OLLAMA_URL, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode())


def run_thinking_spinner(fn):
    """Run fn() in a background thread while showing a spinner; return its result."""
    verb = random.choice(THINKING_VERBS)
    start = time.time()
    result_box = {}

    def work():
        try:
            result_box["value"] = fn()
        except Exception as e:
            result_box["error"] = e

    t = threading.Thread(target=work, daemon=True)
    t.start()

    with Live(console=console, refresh_per_second=12, transient=True) as live:
        spinner = Spinner("dots", style=BLUE)
        while t.is_alive():
            elapsed = time.time() - start
            spinner.text = Text(f" {verb}… ({elapsed:.0f}s)", style=f"dim {BLUE}")
            live.update(spinner)
            time.sleep(0.08)

    if "error" in result_box:
        raise result_box["error"]
    return result_box["value"]


def agent_turn(messages):
    """Runs the tool-calling loop until the model returns a plain text reply."""
    for _ in range(12):  # hard cap so a confused small model can't loop forever
        response = run_thinking_spinner(lambda: ollama_chat(messages))
        msg = response.get("message", {})
        tool_calls = msg.get("tool_calls") or []

        if not tool_calls:
            content = msg.get("content", "")
            console.print(
                Panel(
                    Markdown(content) if content.strip() else Text("(empty response)", style="dim"),
                    border_style=BLUE, padding=(0, 1), title="qwen2.5", title_align="left",
                )
            )
            console.print()
            messages.append({"role": "assistant", "content": content})
            return

        messages.append(msg)
        for call in tool_calls:
            fn = call.get("function", {})
            name = fn.get("name")
            args = fn.get("arguments", {})
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except Exception:
                    args = {}

            console.print(Text(f"  → {name}({', '.join(f'{k}=' + repr(v)[:60] for k, v in args.items())})", style=f"dim {BLUE}"))

            if not auto_mode:
                if not confirm_tool_call(name, args):
                    result = "user declined to run this tool"
                    messages.append({"role": "tool", "content": result})
                    continue

            func = TOOL_FUNCS.get(name)
            if func is None:
                result = f"ERROR: unknown tool {name}"
            else:
                try:
                    result = func(args)
                except Exception as e:
                    result = f"ERROR: {e}"
            messages.append({"role": "tool", "content": str(result)})

    console.print(Text("  (stopped after 12 tool-call rounds — ask me to continue if needed)", style="dim yellow"))


def main():
    global auto_mode
    console.clear()
    threading.Thread(target=poll_gpu, daemon=True).start()
    print_banner()

    messages = [{"role": "system", "content": system_prompt()}]

    while True:
        try:
            user_text = get_user_input()
        except (EOFError, KeyboardInterrupt):
            console.print()
            console.print(Text("Goodbye!", style=f"bold {BLUE}"))
            break

        if not user_text:
            continue
        if user_text.lower() in ("exit", "quit", ":q"):
            console.print(Text("Goodbye!", style=f"bold {BLUE}"))
            break
        if user_text.lower() == "/auto":
            auto_mode = not auto_mode
            console.print(Text(f"  auto mode: {'ON' if auto_mode else 'off'}", style=f"bold {BLUE}"))
            continue

        console.print()
        messages.append({"role": "user", "content": user_text})
        try:
            agent_turn(messages)
        except KeyboardInterrupt:
            console.print(Text("\n(interrupted)", style="dim"))
        except Exception as e:
            console.print(Text(f"Error: {e}", style="bold red"))


if __name__ == "__main__":
    main()
