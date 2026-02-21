#!/usr/bin/env bash
# cachyos-poweruser — setup.sh
# One-liner entry: curl -fsSL https://raw.githubusercontent.com/lifersafety/cachyos-poweruser/main/setup.sh | bash
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_URL="https://github.com/lifersafety/cachyos-poweruser"
RAW_URL="https://raw.githubusercontent.com/lifersafety/cachyos-poweruser/main"
WORK_DIR="${HOME}/.cachyos-poweruser"
LOG="${WORK_DIR}/setup.log"

# ── Colors ──────────────────────────────────────────────────────────────────
R='\e[1;31m' G='\e[1;32m' Y='\e[1;33m' B='\e[1;34m' C='\e[1;36m'
W='\e[1;37m' NC='\e[0m'

die()  { echo -e "${R}[✗] $*${NC}" >&2; exit 1; }
log()  { echo -e "${G}[+]${NC} $*" | tee -a "$LOG"; }
info() { echo -e "${C}[i]${NC} $*"; }

# ── Banner ───────────────────────────────────────────────────────────────────
clear
cat << 'BANNER'

  ██████╗ ██████╗ ██╗    ██╗███████╗██████╗ ██╗   ██╗███████╗███████╗██████╗
 ██╔══██╗██╔═══██╗██║    ██║██╔════╝██╔══██╗██║   ██║██╔════╝██╔════╝██╔══██╗
 ██████╔╝██║   ██║██║ █╗ ██║█████╗  ██████╔╝██║   ██║███████╗█████╗  ██████╔╝
 ██╔═══╝ ██║   ██║██║███╗██║██╔══╝  ██╔══██╗██║   ██║╚════██║██╔══╝  ██╔══██╗
 ██║     ╚██████╔╝╚███╔███╔╝███████╗██║  ██║╚██████╔╝███████║███████╗██║  ██║
 ╚═╝      ╚═════╝  ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝

BANNER
echo -e "  ${W}cachyos-poweruser${NC} — KDE Plasma · Offline & Online Installer"
echo -e "  ${C}https://github.com/lifersafety/cachyos-poweruser${NC}"
echo ""
echo -e "  ${Y}Solve the CachyOS online installer issue — works with or without internet${NC}"
echo ""

mkdir -p "$WORK_DIR"
: > "$LOG"

# ── Dependency check ─────────────────────────────────────────────────────────
log "Checking dependencies..."

need_tool() {
  if ! command -v "$1" &>/dev/null; then
    info "Installing $1 ..."
    if command -v pacman &>/dev/null; then
      sudo pacman -S --noconfirm --needed "$2" 2>>"$LOG" || die "Failed to install $2"
    elif command -v apt-get &>/dev/null; then
      sudo apt-get install -y "$2" 2>>"$LOG" || die "Failed to install $2"
    elif command -v dnf &>/dev/null; then
      sudo dnf install -y "$2" 2>>"$LOG" || die "Failed to install $2"
    else
      die "$1 required but not found and cannot auto-install on this distro"
    fi
  fi
}

need_tool git   git
need_tool curl  curl
need_tool dialog dialog

# ── Clone or update project ───────────────────────────────────────────────────
if [[ ! -d "${WORK_DIR}/repo" ]]; then
  log "Cloning cachyos-poweruser..."
  git clone --depth=1 "${REPO_URL}" "${WORK_DIR}/repo" 2>>"$LOG" || {
    # Fallback: download tui.sh directly and run it
    log "Full clone failed, downloading TUI only..."
    mkdir -p "${WORK_DIR}/repo/tui"
    curl -fsSL "${RAW_URL}/tui/tui.sh" -o "${WORK_DIR}/repo/tui/tui.sh" 2>>"$LOG" \
      || die "Cannot reach GitHub. Check internet connection."
  }
else
  log "Updating cachyos-poweruser..."
  git -C "${WORK_DIR}/repo" pull --ff-only 2>>"$LOG" || log "Could not update; using cached version"
fi

# ── Launch TUI ───────────────────────────────────────────────────────────────
TUI="${WORK_DIR}/repo/tui/tui.sh"
[[ -f "$TUI" ]] || die "TUI script not found at $TUI"
chmod +x "$TUI"
bash "$TUI"
