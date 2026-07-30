# hyprland-rice

Permanent source of truth for an EndeavourOS + Hyprland rice, plus a
Proxmox dashboard (`eww` widget for VM/CT stats and, later, VM creation).

This repo is dotfiles-only content managed with **GNU Stow**. Each
top-level directory (`hypr/`, `waybar/`, `rofi/`, `eww/`, `swaync/`,
`wlogout/`, `matugen/`) is a Stow package that mirrors the layout of
`$HOME` — e.g. `hypr/.config/hypr/hyprland.conf` symlinks to
`~/.config/hypr/hyprland.conf`. `hyprlock.conf`, `hypridle.conf`, and
`hyprpaper.conf` all live inside the `hypr` package too, since they
conventionally share `~/.config/hypr/`.

Theming is handled by **matugen** (chosen over pywal — see Phase 3):
by default it generates a Material-You color scheme from
`hypr/.config/hypr/wallpaper.png` on every login and writes it into
per-app `colors.*` files that Waybar, rofi, swaync, wlogout, and
Hyprland itself all import. Edit the templates under
`matugen/.config/matugen/templates/`, never the generated `colors.*`
files directly.

The accent color (window borders, Waybar highlights, etc.) can be pinned
manually instead of derived from the wallpaper: `SUPER+SHIFT+T` opens a
rofi picker (`hypr/.config/hypr/scripts/pick-theme-color.sh`) with a few
presets plus free-form hex entry, or run
`~/.config/hypr/scripts/set-theme-color.sh '#ff6a00'` directly.
`set-theme-color.sh wallpaper` reverts to the wallpaper-derived scheme.
The choice is persisted to `~/.config/hyprland-rice/theme.conf` and
re-applied by `theme-init.sh` on every login (the exec-once that used to
call `matugen image` directly), so a manual pin survives reboots.

The `hyprglass` plugin (liquid-glass blur/lens effects on top of
Hyprland's native blur — https://github.com/hyprnux/hyprglass) is
installed and enabled via `hyprpm` in `bootstrap.sh`, configured in the
`plugin:hyprglass { ... }` block in `hyprland.conf`, and loaded on every
login via `exec-once = hyprpm reload -n`.

`hyprland.conf` configures two monitors: an auto-detected primary
(`monitor = , preferred, auto, 1`, kept first — Hyprland's `auto-*`
positions misbehave on a named rule if it's the very first rule parsed,
hyprwm/Hyprland#8529), plus a second 1920x1080 panel on `HDMI-A-1`
mounted vertically to the left of the primary and rotated 90° clockwise
(`transform, 1`). If that output is ever renamed (different port/cable/
dock), update the connector name in the `monitor =` line — find the
current name with `hyprctl monitors all`.

`agent-scripts/` holds Claude Code / homelab automation scripts (Phase 6+),
not dotfiles, so it isn't a Stow package — `bootstrap.sh` copies its
contents to `~/agent-scripts/` instead of symlinking them, so that
directory stays stable and freely editable regardless of where this repo
happens to be cloned.

## Secrets

The Proxmox API token and dashboard config (host, node, token) live in
`~/.config/hyprland-rice/proxmox.conf` (mode 600), generated interactively
by `bootstrap.sh` on first run. It lives outside this repo entirely, so
it can never be accidentally committed — the `.gitignore` entries are
just a belt-and-suspenders backstop.

Use a scoped, non-root API token. The `dashboard@pve!dashboard-token`
token (role `DashboardViewer`) started read-only in Phase 4 (`VM.Audit`
+ `Sys.Audit` — `VM.Monitor` from the original build plan no longer
exists as of Proxmox VE 9.x) and was expanded in Phase 5 for VM
create/delete. The final privilege set, found by actually testing each
step rather than guessing from the plan's suggested list:
`VM.Allocate`, `VM.Clone`, `Datastore.AllocateSpace` (as the plan said),
plus `VM.PowerMgmt` (to start a newly-cloned VM and stop one before
delete — not in the plan's list but required for "list+delete" to
actually work), `SDN.Use` (this Proxmox instance registers `vmbr0` as
an SDN zone, so attaching a NIC during clone needs it), and
`VM.Config.CPU` / `VM.Config.Memory` / `VM.Config.Options` (to set
cores/memory/tags on the clone), `VM.GuestAgent.Audit` (Phase 6, IP
lookup via the guest agent), and `VM.Snapshot` (Phase 7, the MCP
snapshot tool). Still far short of admin — no `VM.Migrate`, no
`Datastore.Allocate`, no access to VMs outside what's explicitly scoped.
Delete/destroy is *not* exposed via the Proxmox MCP server (Phase 7) —
only through the dashboard's confirm-gated `delete_vm.sh` (Phase 5).

## Running the bootstrap

On a fresh EndeavourOS install (or the disposable Proxmox test VM used
for iteration):

```bash
git clone <this-repo-url> ~/hyprland-rice
cd ~/hyprland-rice
./bootstrap.sh
```

Installs base packages, the rice configs, and stows everything into
`$HOME` (Phases 2–3). The Proxmox dashboard is added in Phase 4 — see
`proxmox-build-plan.md` for the full phase breakdown.

## Status

- [x] Phase 0 — decisions: secrets via bootstrap-generated `.gitignore`'d
      `proxmox.conf`; test VM created and managed by the user directly.
- [x] Phase 1 — repo skeleton.
- [x] Phase 2 — bootstrap script: base packages + stow + clock-skew fix.
      Verified end-to-end in the test VM.
- [x] Phase 3 — core rice polish. Hyprland, Waybar, rofi, swaync,
      hyprlock/hypridle, wlogout, hyprpaper, and matugen theming all
      configured and verified end-to-end in the test VM: every
      `exec-once` component (hyprpaper, waybar, swaync, hypridle,
      eww daemon, nwg-dock-hyprland) actually launches and stays up
      inside a real Hyprland session (software-rendered via llvmpipe,
      since this VM has no GPU passthrough — real hardware will use
      the Nvidia driver instead). Needed a Proxmox-side fix along the
      way: the VM's display had to be switched to VirtIO-GPU (3D accel)
      to get a `/dev/dri/renderD128` node at all, and `seatd` had to be
      enabled for Hyprland to acquire the DRM seat when launched
      without a display manager.
- [x] Phase 4 — Proxmox dashboard: stats view. `proxmox_stats.py`
      (`scripts/` package, installed to `~/.local/bin/`) polls
      `/cluster/resources` via a scoped API token and is shared by both
      consumers: the Waybar `custom/proxmox` module (compact summary,
      click to toggle the dashboard) and a new `eww` window
      (`SUPER+X`), styled via matugen. All 4 failure states verified
      live against the real Proxmox host: `config_error` (missing
      config), `auth_error` (bad token, real 401), `unreachable`
      (no route to host), and `timeout` (blackholed address) — each
      renders distinctly instead of a silent/blank widget. Confirmed
      the `eww` window actually opens with zero parse errors inside a
      real Hyprland session and shows live node/guest data from the
      Proxmox host. Two real eww quirks found by testing: its `.scss`
      files run through an actual SCSS compiler that doesn't understand
      GTK's `@color` syntax (fixed by using plain `eww.css` instead,
      same as Waybar/swaync), and a broken ternary in `eww.yuck` needed
      simplifying.
- [x] Phase 5 — "New VM" button. Prerequisite template (cloud-init +
      SSH keys, flagged by the plan as needing to exist first) built
      from scratch: Proxmox VMID 9000, Ubuntu 24.04 LTS cloud image,
      cloud-init user `ubuntu`, a dedicated SSH keypair generated just
      for these dashboard-created VMs (private key kept at
      `hyprland-rice-secrets/proxmox-guest-key`, outside the repo, never
      committed) — smoke-tested end to end (clone → boot → cloud-init →
      SSH login actually worked) before building anything on top of it.
      `create_vm.sh` (rofi prompt → explicit "Create/Cancel" confirm →
      clone via `vm_ops.py` → auto-start) and `delete_vm.sh` (same
      confirm pattern) both wired into the `eww` dashboard. **Safety
      invariant, tested against the real host, not just asserted**: only
      VMs the dashboard creates get tagged `dashboard-managed`, and
      `vm_ops.py destroy` refuses anything without that tag — verified
      it correctly refused to delete the pre-existing `mineserver` VM
      (id 100) even when asked to directly. Full create → start → stop →
      destroy cycle run for real against the Proxmox host (not simulated).
- [x] Phase 6 — AI integration, Tier 1. `claude-code` (AUR) installed —
      it wasn't in the package list at all until this phase, a real gap
      since nothing in Phases 1–5 actually needed the CLI present.
      `agent-scripts/toggle-claude-scratchpad.sh` (bound to `SUPER+grave`,
      confirmed unclaimed by any other bind) spawns a `kitty --class
      claude-scratchpad -e claude` and toggles it on Hyprland's
      `special:claude` workspace — verified working across every test
      run. `ssh-vm.sh` picks a Proxmox guest via `fzf` and SSHes in:
      dashboard-managed VMs automatically (IP via the QEMU guest agent +
      the dedicated key from Phase 5), anything else via a
      user-maintained `~/.config/hyprland-rice/vm-ssh-hosts.conf`. Getting
      this actually working surfaced a real template bug: the Ubuntu
      cloud image doesn't ship `qemu-guest-agent` running by default, so
      IP auto-discovery silently failed — fixed with a cloud-init
      vendor-data snippet on the template (`packages: [qemu-guest-agent]`
      + enable it), then verified end-to-end: create VM → agent responds
      in ~30s → IP discovered via the API → SSH with the dedicated key
      succeeds. `ai-status.sh` (aliased in `~/.bashrc`) feeds local +
      Proxmox stats into `claude -p` for a one-shot health summary.
      **Known gap, found by testing and not chased further per explicit
      guidance not to over-invest in polish**: the `float`/`size`/`center`
      window rules for the scratchpad are flaky/inconsistent across
      identical test runs in this VM (the `workspace special:claude`
      pinning itself works reliably) — possibly a race condition or
      something specific to software-rendered `llvmpipe`. Worth
      rechecking on real hardware in Phase 9 before spending more time on
      it here.
- [x] Phase 7 — AI integration, Tier 2 (MCP servers). Filesystem MCP
      (official `@modelcontextprotocol/server-filesystem`) and a custom
      Proxmox MCP server (`agent-scripts/proxmox_mcp_server.py`, using
      the `mcp` Python SDK) both registered via `claude mcp add` and
      confirmed **✔ Connected** via `claude mcp list`. The Proxmox MCP
      server's `list_vms`/`vm_status` tools were called directly (not
      just handshake-tested) and returned real data from the host.
      **Filesystem scope note**: the plan's "$HOME minus a denylist"
      model isn't something the standard filesystem MCP server
      supports — it's allow-list only, no exclusion mechanism. Instead
      of that shape, it's granted an explicit list of normal working
      directories (this repo, `agent-scripts/`, and any of
      Documents/Downloads/Pictures/Desktop/Videos/Music that exist) —
      `.ssh`, `.config`, `.mozilla`, `.gnupg` etc. are never on the list
      to begin with, same safety outcome via a different mechanism.
      Phase 8 (Tier 3) explicitly skipped per instruction.
- [~] Phase 9 — real bare-metal install. **Storage prerequisite done**:
      the 4TB HDD is physically in the Proxmox server, wiped and
      repartitioned (GPT, ext4), mounted at `/mnt/bulkstorage`, and
      registered as Proxmox directory storage (`backup,iso,vztmpl`).
      Both an SMB share (`\\<host>\bulkstorage`, user `rafael`) and an
      NFS export (`/mnt/bulkstorage/shared`, LAN-restricted) are live —
      SMB tested with an actual read/write from the Windows desktop, not
      just service-status checks. Found and fixed a real Proxmox config
      issue along the way: the host's enterprise apt repos require a
      paid subscription and were returning 401s, blocking all package
      installs — switched to the free `pve-no-subscription` repo.
      Remaining: the actual dual-boot install onto the desktop itself
      (Windows partition shrink, install media, EndeavourOS install) —
      deliberately not automated solo; needs to happen as a live,
      hands-on walkthrough given how hard to reverse it is.
