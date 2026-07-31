# Menu house style

Every dismissible popup menu (power menu, volume popup, Proxmox dashboard,
and anything added later) should look and behave like the Claude/Qwen
scratchpads: translucent + blurred, dims the background, closes on
Escape, closes on an outside click. This is the checklist for adding a
new one — see `menu-style.conf` for the full technical writeup behind
each piece.

## Checklist for a new menu

1. **Pick the right pattern.**
   - If it's a real window (like the scratchpads): put it on its own
     `special:<name>` workspace via `windowrule` in `hyprland.conf`.
     Opacity, blur, rounding, border, pop-in animation, and background
     dimming all come free from the global `decoration{}`/`animations{}`
     blocks — nothing else to do.
   - If it's a layer-shell popup (eww, rofi, wlogout, a waybar-triggered
     script): run `hyprctl layers` while it's open to find its real
     namespace, then add `layerrule` blur/dim lines for that namespace
     to `menu-style.conf`. Manually match opacity 0.92 / rounding 12px /
     2px border in the menu's own stylesheet — layerrule can't set those.

2. **Wire it through the shared scripts, not raw eww calls.** Whatever
   triggers the menu (a Hyprland `bind`, a waybar `on-click`) should call:
   ```
   ~/.config/hypr/scripts/toggle-menu.sh <eww-window-name>
   ```
   instead of `eww open --toggle <name>` directly — this is what enters
   the Escape-to-close submap correctly (and avoids re-entering it if the
   same trigger is what closes the menu).

3. **Add it to the `POPUPS` array** in `scripts/close-all-menus.sh` —
   that's the single source of truth for "what counts as a menu,"
   used by both the Escape submap and the outside-click watcher.

4. **If the menu has its own internal action buttons** (like power-menu's
   Logout/Restart/Lock row) that close the menu before doing something,
   call `~/.config/hypr/scripts/close-all-menus.sh` from them instead of
   `eww close <name>` directly, so the submap resets too.

That's it — outside-click-to-close (`eww-outside-click-watcher.sh`,
already exec-once'd) and Escape-to-close (the `menu` submap in
`menu-style.conf`) both work automatically from there.

## Why eww windows share one namespace

eww 0.5 has no per-window layer-shell namespace option — every eww
window (power-menu, volume-popup, proxmox-dashboard, and the always-on
system-dashboard) shows up as `gtk-layer-shell` in `hyprctl layers`.
That's why `menu-style.conf` enables `dim_around` on that whole
namespace rather than per-window: verified live (via `grim` screenshots
on both monitors) that this is safe — `system-dashboard` sits at the
`bg` layer, so its own dim request only darkens the wallpaper behind it
(never visible), while the actual toggle popups sit at `top`/`overlay`
and so their dim genuinely darkens the desktop, which is the effect we
want.

## Why the Escape submap is minimal

The `menu` submap (`menu-style.conf`) only rebinds Escape — every other
keybind is briefly unavailable while a menu is open. This is intentional
modal-style behavior. Closing the menu by *any* path (Escape, an outside
click, or one of its own buttons) resets the submap immediately, since
all three routes funnel through `close-all-menus.sh`.
