#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script for the Hyprland rice + Proxmox dashboard setup.
# Run from a fresh EndeavourOS install (or the Proxmox test VM).
#
# Grown incrementally per the build plan:
#   Phase 2 — base package install + stow symlinks + clock-skew fix
#   Phase 3 — rice packages (Waybar/rofi/swaync/wlogout/matugen/eww) +
#             seatd, needed for Hyprland to run without a display manager
#   Phase 4 — proxmox.conf generation (interactive, gitignored)
#   Phase 5 — jq/python/libnotify + create_vm.sh/delete_vm.sh/vm_ops.py
#   Phase 6 — fzf + agent-scripts/ (copied, not stowed) + guest SSH key +
#             ai-status alias
#   Phase 7 — python-pip + `mcp` SDK + filesystem/Proxmox MCP servers
#             registered with `claude mcp add` (user scope)
#   Phase 8 — Spotify (spotify-launcher) + spicetify-cli/spicetify-themes-git,
#             HyprlandRice color scheme tracking the matugen accent + Vesktop
#   Phase 9 — wpaperd replaces hyprpaper (built from source, cargo workspace)
#   later phases add to this as needed
#
# Safe to re-run: package installs and stow are idempotent.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Stow packages in this repo, in the order they should be linked.
# agent-scripts is deliberately excluded — it's not a Stow package.
STOW_PACKAGES=(hypr waybar rofi eww swaync wlogout matugen scripts wpaperd kitty firefox)

PACMAN_PACKAGES=(
  hyprland
  waybar
  rofi
  swaync
  hyprlock
  hypridle
  stow
  rust
  kitty
  thunar
  wl-clipboard
  grim
  slurp
  qt5ct
  polkit-kde-agent
  desktop-file-utils
  xdg-desktop-portal-hyprland
  ttf-jetbrains-mono-nerd
  seatd
  jq
  python
  python-pip
  libnotify
  fzf
  nodejs
  npm
  nvidia-open
  nvidia-utils
  cmake
  meson
  ninja
  pkgconf
  spotify-launcher
)

AUR_PACKAGES=(
  wlogout
  matugen-bin
  eww
  claude-code
  vesktop-bin
  spicetify-cli
  spicetify-themes-git
)

log() { printf '\n==> %s\n' "$1"; }

require_not_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    echo "Do not run bootstrap.sh as root — it uses sudo where needed." >&2
    exit 1
  fi
}

fix_clock_skew() {
  log "Fixing dual-boot clock skew (RTC in local time, matching Windows)"
  sudo timedatectl set-local-rtc 1 --adjust-system-clock
}

enable_seatd() {
  # Hyprland (via libseat) needs a running seat manager to acquire the DRM
  # seat when launched from a bare TTY with no display manager. Without
  # this it fails with "libseat: failed to open a seat" and can't start.
  log "Enabling seatd and adding \$USER to the seat group"
  sudo systemctl enable --now seatd
  sudo usermod -aG seat "${USER}"
}

install_pacman_packages() {
  log "Installing base packages via pacman"
  sudo pacman -Sy --needed --noconfirm "${PACMAN_PACKAGES[@]}"
}

ensure_yay() {
  if command -v yay >/dev/null 2>&1; then
    return
  fi
  log "yay not found — building it from the AUR"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay-bin.git "${tmp_dir}/yay-bin"
  (cd "${tmp_dir}/yay-bin" && makepkg -si --noconfirm)
  rm -rf "${tmp_dir}"
}

install_aur_packages() {
  ensure_yay
  log "Installing AUR packages via yay"
  yay -Sy --needed --noconfirm "${AUR_PACKAGES[@]}"
}

stow_configs() {
  log "Symlinking configs into \$HOME via stow"
  for pkg in "${STOW_PACKAGES[@]}"; do
    stow --dir="${REPO_DIR}" --target="${HOME}" --restow "${pkg}"
  done
  chmod +x "${HOME}/.local/bin/proxmox_stats.py" \
           "${HOME}/.local/bin/vm_ops.py" \
           "${HOME}/.local/bin/create_vm.sh" \
           "${HOME}/.local/bin/delete_vm.sh" \
           "${HOME}/.config/waybar/scripts/proxmox_waybar.sh" \
           "${HOME}/.config/hypr/scripts/show-keybinds.sh" \
           "${HOME}/.config/hypr/scripts/theme-init.sh" \
           "${HOME}/.config/hypr/scripts/set-theme-color.sh" \
           "${HOME}/.config/hypr/scripts/pick-theme-color.sh" 2>/dev/null || true
  # Without this, the firefox package's --new-window override (fixes links
  # from other apps silently reusing an existing Firefox window on a
  # different workspace) sits on disk but isn't picked up by xdg-open
  # until something refreshes the desktop-file cache.
  update-desktop-database "${HOME}/.local/share/applications"
}

install_wpaperd() {
  # Not packaged (no official/AUR package used here) — built from source
  # the same way it was done interactively: clone, `cargo install --path
  # daemon` (it's a cargo workspace, not a single-crate build), which
  # lands the binary in ~/.cargo/bin.
  if [[ -x "${HOME}/.cargo/bin/wpaperd" ]]; then
    log "wpaperd already installed"
    return
  fi

  log "Building wpaperd from source"
  local build_dir
  build_dir="$(mktemp -d)"
  git clone https://github.com/danyspin97/wpaperd "${build_dir}"
  (cd "${build_dir}" && cargo install --path daemon)
  rm -rf "${build_dir}"
}

install_hyprland_plugins() {
  # hyprpm ships with the hyprland package. `update` fetches/builds the
  # headers matching the currently installed Hyprland version — required
  # before any plugin can be built against it.
  if ! command -v hyprpm >/dev/null 2>&1; then
    log "hyprpm not found — skipping plugin install (hyprglass)"
    return
  fi

  log "Updating hyprpm plugin headers"
  hyprpm update

  if ! hyprpm list 2>/dev/null | grep -q "hyprglass"; then
    log "Adding hyprglass plugin (https://github.com/hyprnux/hyprglass)"
    hyprpm add https://github.com/hyprnux/hyprglass
  fi

  log "Enabling hyprglass"
  hyprpm enable hyprglass
}

generate_initial_colors() {
  # hyprland.conf has `source = ~/.config/hypr/colors.conf` at the top, but
  # colors.conf is only ever generated by matugen — which itself only runs
  # via an exec-once line INSIDE hyprland.conf. On a truly fresh install
  # Hyprland tries to parse hyprland.conf (needing colors.conf to already
  # exist) before that exec-once has ever had a chance to run, so every
  # color variable comes up undefined and the whole config floods with
  # errors. Generating it once here, before Hyprland is ever launched,
  # breaks that chicken-and-egg problem. The exec-once line stays too, for
  # regenerating colors on future logins/wallpaper changes.
  if [[ -f "${HOME}/.config/hypr/colors.conf" ]]; then
    return
  fi
  if ! command -v matugen >/dev/null 2>&1; then
    log "matugen not found — skipping initial color generation (will run via exec-once instead, but hyprland.conf may show errors on first launch)"
    return
  fi
  log "Generating initial matugen colors so hyprland.conf has something to source on first launch"
  matugen image "${HOME}/.config/hypr/wallpaper.png" -m dark --prefer=saturation
}

setup_proxmox_config() {
  local config_dir="${HOME}/.config/hyprland-rice"
  local config_file="${config_dir}/proxmox.conf"

  if [[ -f "${config_file}" ]]; then
    log "Proxmox config already exists at ${config_file} — leaving it alone"
    return
  fi

  if [[ ! -t 0 ]]; then
    log "No TTY attached — skipping interactive Proxmox config setup. Re-run bootstrap.sh interactively later to configure the dashboard."
    return
  fi

  log "Setting up the Proxmox dashboard config (Phase 4)"
  echo "This is stored in ${config_file} (mode 600), never committed to git."
  echo "Use a scoped, read-only API token — see the build plan for the exact ACL (VM.Audit + Sys.Audit)."
  echo

  local host node token_id token_secret
  read -rp "Proxmox host/IP: " host
  read -rp "Node name (e.g. pve): " node
  read -rp "API token ID (e.g. dashboard@pve!dashboard-token): " token_id
  read -rsp "API token secret: " token_secret
  echo

  mkdir -p "${config_dir}"
  umask 177
  cat > "${config_file}" <<EOF
PROXMOX_HOST=${host}
PROXMOX_PORT=8006
PROXMOX_NODE=${node}
PROXMOX_TOKEN_ID=${token_id}
PROXMOX_TOKEN_SECRET=${token_secret}
PROXMOX_VERIFY_SSL=false
EOF
  chmod 600 "${config_file}"
  log "Wrote ${config_file}"
}

setup_spicetify_theme() {
  # spicetify-themes-git installs Sleek system-wide under
  # /opt/spicetify-cli/Themes, which is root-owned — copy it into
  # ~/.config/spicetify/Themes so spicetify-sync-theme.sh can maintain a
  # "HyprlandRice" color scheme in it that tracks the matugen accent.
  local sleek_src="/opt/spicetify-cli/Themes/Sleek"
  local sleek_dst="${HOME}/.config/spicetify/Themes/Sleek"

  if [[ ! -d "${sleek_src}" ]]; then
    log "spicetify-themes-git not installed — skipping Spotify theme setup"
    return
  fi
  if [[ ! -f "${HOME}/.config/spotify/prefs" ]]; then
    log "Spotify not logged in yet — run spotify once, log in, then re-run" \
        "${REPO_DIR}/hypr/.config/hypr/scripts/spicetify-sync-theme.sh"
    return
  fi

  mkdir -p "${HOME}/.config/spicetify/Themes"
  rm -rf "${sleek_dst}"
  cp -r "${sleek_src}" "${sleek_dst}"

  log "Applying spicetify theme"
  spicetify config current_theme Sleek color_scheme HyprlandRice
  "${HOME}/.config/hypr/scripts/spicetify-sync-theme.sh"
  spicetify apply
}

copy_agent_scripts() {
  # Copied, not stowed: agent-scripts/ is meant to be a stable, freely
  # editable location independent of wherever this repo happens to live,
  # not a symlink back into it.
  log "Copying agent-scripts/ to ~/agent-scripts/"
  mkdir -p "${HOME}/agent-scripts"
  cp -f "${REPO_DIR}"/agent-scripts/*.sh "${REPO_DIR}"/agent-scripts/*.py "${HOME}/agent-scripts/"
  chmod +x "${HOME}"/agent-scripts/*.sh "${HOME}"/agent-scripts/*.py
}

setup_guest_ssh_key() {
  local key_dest="${HOME}/.ssh/proxmox-guest-key"

  if [[ -f "${key_dest}" ]]; then
    log "Guest SSH key already present at ${key_dest}"
    return
  fi

  if [[ ! -t 0 ]]; then
    log "No TTY attached — skipping guest SSH key setup. Re-run bootstrap.sh interactively later."
    return
  fi

  echo
  echo "agent-scripts/ssh-vm.sh needs the private key matching the Proxmox"
  echo "template's cloud-init public key (dashboard-created VMs only)."
  local src
  read -rp "Path to that private key file (blank to skip): " src
  if [[ -z "${src}" ]]; then
    log "Skipped guest SSH key setup"
    return
  fi

  mkdir -p "${HOME}/.ssh"
  cp "${src}" "${key_dest}"
  chmod 600 "${key_dest}"
  log "Installed guest SSH key at ${key_dest}"
}

setup_ai_status_alias() {
  local marker="# hyprland-rice: ai-status alias"
  if grep -qF "${marker}" "${HOME}/.bashrc" 2>/dev/null; then
    return
  fi
  log "Adding ai-status alias to ~/.bashrc"
  cat >> "${HOME}/.bashrc" <<EOF

${marker}
alias ai-status='~/agent-scripts/ai-status.sh'
EOF
}

setup_mcp_servers() {
  if ! command -v claude >/dev/null 2>&1; then
    log "claude CLI not found — skipping MCP server setup"
    return
  fi

  log "Installing the mcp Python SDK (for the Proxmox MCP server)"
  python3 -m pip install --user --break-system-packages --quiet mcp

  # Filesystem MCP (Phase 7): allow-list only, no denylist support in the
  # standard server — so instead of "$HOME minus sensitive dirs" we grant an
  # explicit list of normal working directories and simply never include
  # dotfiles/config/credential dirs (~/.ssh, ~/.config, ~/.mozilla, ~/.gnupg,
  # etc.) in the first place. Same practical safety outcome.
  local fs_dirs=("${REPO_DIR}" "${HOME}/agent-scripts")
  for d in Documents Downloads Pictures Desktop Videos Music; do
    if [[ -d "${HOME}/${d}" ]]; then
      fs_dirs+=("${HOME}/${d}")
    fi
  done

  if ! claude mcp list 2>/dev/null | grep -q '^filesystem'; then
    log "Registering filesystem MCP server"
    claude mcp add filesystem -s user -- npx -y @modelcontextprotocol/server-filesystem "${fs_dirs[@]}"
  fi

  if ! claude mcp list 2>/dev/null | grep -q '^proxmox'; then
    log "Registering Proxmox MCP server"
    claude mcp add proxmox -s user -- python3 "${HOME}/agent-scripts/proxmox_mcp_server.py"
  fi
}

main() {
  require_not_root
  install_pacman_packages
  install_aur_packages
  fix_clock_skew
  enable_seatd
  stow_configs
  install_wpaperd
  install_hyprland_plugins
  generate_initial_colors
  setup_spicetify_theme
  "${HOME}/.config/hypr/scripts/vesktop-sync-theme.sh" || true
  setup_proxmox_config
  copy_agent_scripts
  setup_guest_ssh_key
  setup_ai_status_alias
  setup_mcp_servers
  log "Bootstrap complete. Log out/in (or reboot) to pick up Hyprland."
}

main "$@"
