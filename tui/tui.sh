#!/usr/bin/env bash
# cachyos-poweruser — tui/tui.sh
# Main TUI interface launched by setup.sh
# Requires: dialog, git, pacman (for building), curl
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG="${HOME}/.cachyos-poweruser/build.log"
WORK_DIR="${HOME}/.cachyos-poweruser/work"
OUT_DIR="${HOME}/.cachyos-poweruser/out"

mkdir -p "$WORK_DIR" "$OUT_DIR"
: >> "$LOG"

# ── TUI helpers ───────────────────────────────────────────────────────────────
D="dialog --backtitle 'cachyos-poweruser — CachyOS KDE Installer Builder' --colors"

msg()      { eval "$D --msgbox '\Z6$*\Zn' 8 60"; }
info_box() { eval "$D --infobox '$*' 5 60"; sleep 1; }
err_box()  { eval "$D --msgbox '\Z1[ERROR]\Zn $*' 8 70"; }
yesno()    { eval "$D --yesno '$*' 7 60"; }

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }

# ── Detect environment ────────────────────────────────────────────────────────
detect_env() {
  if command -v pacman &>/dev/null && [[ -f /etc/cachyos-release ]]; then
    echo "cachyos"
  elif command -v pacman &>/dev/null; then
    echo "arch"
  elif [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
    echo "wsl"
  elif command -v docker &>/dev/null; then
    echo "docker"
  else
    echo "unsupported"
  fi
}

# ── Main menu ─────────────────────────────────────────────────────────────────
main_menu() {
  local ENV; ENV=$(detect_env)
  local env_label

  case "$ENV" in
    cachyos) env_label="CachyOS (native — optimal)" ;;
    arch)    env_label="Arch Linux (native)" ;;
    wsl)     env_label="WSL2 — Docker required for building" ;;
    docker)  env_label="Linux + Docker available" ;;
    *)       env_label="Unsupported — building not available" ;;
  esac

  CHOICE=$(eval "$D --title ' cachyos-poweruser ' \
    --menu '\nEnvironment: \Z3${env_label}\Zn\n\nWhat would you like to do?' 20 70 7 \
    '1' 'Build KDE ISO  (offline + online Calamares installer)' \
    '2' 'Install CachyOS now  (live ISO / running on target)' \
    '3' 'Open Web UI  (browser-based configurator)' \
    '4' 'Download pre-built ISO  (from GitHub Releases)' \
    '5' 'View build log' \
    '6' 'About / Help' \
    '7' 'Exit' \
    3>&1 1>&2 2>&3") || exit 0

  case "$CHOICE" in
    1) menu_build_iso ;;
    2) menu_install ;;
    3) menu_webui ;;
    4) menu_download ;;
    5) show_log ;;
    6) show_about ;;
    7) clear; exit 0 ;;
  esac
}

# ── BUILD ISO menu ────────────────────────────────────────────────────────────
menu_build_iso() {
  local ENV; ENV=$(detect_env)

  if [[ "$ENV" == "unsupported" ]]; then
    err_box "Building requires an Arch/CachyOS host or Docker.\nInstall Docker and retry."
    main_menu; return
  fi

  # Step 1: What to build
  PROFILE=$(eval "$D --title 'ISO Profile' \
    --menu '\nChoose what to build:' 16 68 4 \
    'kde-offline'  'KDE Plasma — offline+online (recommended, ~4.5GB ISO)' \
    'kde-online'   'KDE Plasma — online only (lighter, standard CachyOS)' \
    3>&1 1>&2 2>&3") || { main_menu; return; }

  # Step 2: Confirm & build
  yesno "Build \Z6${PROFILE}\Zn ISO?\n\nThis will:\n  1. Clone CachyOS-Live-ISO (official)\n  2. Apply minimal offline patch\n  3. Build with archiso\n\nRequires ~10GB disk + 20+ min\nOutput: ${OUT_DIR}/" || { main_menu; return; }

  # Step 3: Choose build method
  local BUILD_CMD
  if [[ "$ENV" == "cachyos" || "$ENV" == "arch" ]]; then
    BUILD_CMD="native"
  elif command -v docker &>/dev/null; then
    BUILD_CMD="docker"
  else
    err_box "No suitable build environment found.\nInstall Docker or run on CachyOS/Arch."
    main_menu; return
  fi

  # Run build with progress dialog
  (
    bash "${PROJECT_ROOT}/build/build-iso.sh" \
      --profile "$PROFILE" \
      --method  "$BUILD_CMD" \
      --outdir  "$OUT_DIR" \
      2>&1
  ) | eval "$D --title 'Building ISO...' --programbox 'Build output (Ctrl+C to abort):' 30 80"

  local ISO; ISO=$(ls "${OUT_DIR}"/*.iso 2>/dev/null | tail -1)
  if [[ -f "${ISO:-/dev/null}" ]]; then
    local SIZE; SIZE=$(du -sh "$ISO" | cut -f1)
    msg "Build complete!\n\nISO: ${ISO}\nSize: ${SIZE}\n\nWrite to USB:\n  sudo dd if=${ISO} of=/dev/sdX bs=4M status=progress oflag=sync"
  else
    err_box "Build failed or no ISO found.\nCheck log: $LOG"
  fi
  main_menu
}

# ── INSTALL menu ──────────────────────────────────────────────────────────────
menu_install() {
  INSTALL_METHOD=$(eval "$D --title 'Install CachyOS' \
    --menu '\nChoose installer:' 16 70 3 \
    'calamares'    'Calamares GUI installer (recommended)' \
    'cli'          'CachyOS CLI installer (New-Cli-Installer)' \
    'back'         'Back to main menu' \
    3>&1 1>&2 2>&3") || { main_menu; return; }

  case "$INSTALL_METHOD" in
    calamares)
      # Check if offline repo is available
      if [[ -d /run/archiso/localrepo ]] || [[ -d /repo/localrepo ]]; then
        REPO_STATUS="\Z2✓ Offline repository detected — offline install available\Zn"
      else
        REPO_STATUS="\Z3⚠ No offline repo found — online install only\Zn"
      fi
      msg "Launching Calamares installer...\n\n${REPO_STATUS}\n\nIn Calamares, choose:\n  - 'Offline (bundled packages)' if you have no internet\n  - 'Online (CachyOS mirrors)' for latest packages"
      if command -v calamares &>/dev/null; then
        sudo calamares &
      else
        err_box "Calamares not found. Are you running from the live ISO?"
      fi
      ;;
    cli)
      bash "${PROJECT_ROOT}/installer/cachyos-cli-install.sh"
      ;;
    back)
      main_menu; return ;;
  esac
  main_menu
}

# ── WEBUI menu ────────────────────────────────────────────────────────────────
menu_webui() {
  local WEBUI="${PROJECT_ROOT}/webui/index.html"
  [[ -f "$WEBUI" ]] || WEBUI="${HOME}/.cachyos-poweruser/repo/webui/index.html"

  if [[ -f "$WEBUI" ]]; then
    info_box "Opening Web UI in browser..."
    if command -v xdg-open &>/dev/null; then
      xdg-open "$WEBUI" &>/dev/null &
    elif command -v firefox &>/dev/null; then
      firefox "$WEBUI" &>/dev/null &
    else
      msg "Web UI is at:\n  ${WEBUI}\n\nOpen it in your browser."
    fi
  else
    err_box "Web UI not found. Ensure project is fully cloned."
  fi
  main_menu
}

# ── DOWNLOAD menu ─────────────────────────────────────────────────────────────
menu_download() {
  info_box "Fetching latest release info from GitHub..."

  local API_URL="https://api.github.com/repos/lifersafety/cachyos-poweruser/releases/latest"
  local REL_INFO
  REL_INFO=$(curl -fsSL "$API_URL" 2>/dev/null || echo '{}')
  local TAG; TAG=$(echo "$REL_INFO" | grep '"tag_name"' | head -1 | cut -d'"' -f4)

  if [[ -z "$TAG" ]]; then
    msg "No releases found yet at github.com/lifersafety/cachyos-poweruser\n\nBuild your own ISO using option 1.\n\nOr download the official CachyOS ISO at:\n  https://cachyos.org/download/"
  else
    DOWNLOAD_CHOICE=$(eval "$D --title 'Download ISO' \
      --menu '\nLatest release: \Z6${TAG}\Zn\n\nChoose ISO to download:' 14 70 3 \
      'kde-offline'  'CachyOS KDE — Offline+Online (recommended)' \
      'kde-online'   'CachyOS KDE — Online only (official)' \
      'back'         'Back' \
      3>&1 1>&2 2>&3") || { main_menu; return; }

    [[ "$DOWNLOAD_CHOICE" == "back" ]] && { main_menu; return; }

    local DL_URL="https://github.com/lifersafety/cachyos-poweruser/releases/download/${TAG}/cachyos-poweruser-${DOWNLOAD_CHOICE}-${TAG}.iso"
    yesno "Download:\n${DL_URL}\n\nTo: ${OUT_DIR}/\n\nProceed?" || { main_menu; return; }

    (curl -L --progress-bar "$DL_URL" -o "${OUT_DIR}/cachyos-poweruser-${DOWNLOAD_CHOICE}-${TAG}.iso" 2>&1) \
      | eval "$D --title 'Downloading...' --progressbox 'Downloading ISO:' 10 70"

    msg "Download complete!\nFile: ${OUT_DIR}/cachyos-poweruser-${DOWNLOAD_CHOICE}-${TAG}.iso\n\nWrite to USB:\n  sudo dd if=<iso> of=/dev/sdX bs=4M status=progress oflag=sync"
  fi
  main_menu
}

# ── SHOW LOG ──────────────────────────────────────────────────────────────────
show_log() {
  eval "$D --title 'Build Log' --tailbox '${LOG}' 30 80"
  main_menu
}

# ── ABOUT ─────────────────────────────────────────────────────────────────────
show_about() {
  eval "$D --title 'About cachyos-poweruser' --msgbox \
'\Z6cachyos-poweruser\Zn — v0.1.0

Solves the most common CachyOS issue: online installer failures
in weak/no internet environments.

\Z3How it works:\Zn
  • Clones OFFICIAL CachyOS-Live-ISO scripts
  • Applies MINIMAL patch: adds local offline repo to Calamares
  • Packages KDE (minus LibreOffice) for offline use
  • Both Calamares GUI + New-Cli-Installer supported
  • Online install path is UNCHANGED — zero regression

\Z3Sources:\Zn
  github.com/CachyOS/CachyOS-Live-ISO
  github.com/CachyOS/New-Cli-Installer
  github.com/lifersafety/cachyos-poweruser

\Z3License:\Zn GPLv3 (matching upstream CachyOS)' 26 72"
  main_menu
}

# ── Entry point ───────────────────────────────────────────────────────────────
main_menu
