#!/usr/bin/env bash
# cachyos-poweruser — installer/cachyos-cli-install.sh
#
# Wraps the official CachyOS New-Cli-Installer with offline support.
# Source: https://github.com/CachyOS/New-Cli-Installer
#
# If an offline repo is bundled in the ISO (/var/cache/localrepo),
# it is activated in pacman.conf BEFORE the CLI installer runs.
# The CLI installer then proceeds identically to the official experience.
# After installation, the localrepo entry is removed from the target system.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

LOG="/tmp/cachyos-poweruser-install.log"
OFFLINE_FLAG="/run/cachyos-poweruser/offline-available"
LOCALREPO="/var/cache/localrepo"

# Official CachyOS CLI installer binary name
CLI_INSTALLER_BIN="cachyos-install"
CLI_INSTALLER_FALLBACK_URL="https://github.com/CachyOS/New-Cli-Installer/releases/latest/download/cachyos-install"

R='\e[1;31m' G='\e[1;32m' Y='\e[1;33m' C='\e[1;36m' W='\e[1;37m' NC='\e[0m'

die()  { echo -e "${R}[✗] $*${NC}" | tee -a "$LOG" >&2; exit 1; }
log()  { echo -e "${G}[+]${NC} $*" | tee -a "$LOG"; }
warn() { echo -e "${Y}[!]${NC} $*" | tee -a "$LOG"; }
info() { echo -e "${C}[i]${NC} $*"; }

[[ "$EUID" -eq 0 ]] || die "Must run as root. Use: sudo bash installer/cachyos-cli-install.sh"

: > "$LOG"

clear
echo -e "${W}"
cat << 'BANNER'
  cachyos-poweruser — CLI Installer
  Powered by CachyOS New-Cli-Installer
  ──────────────────────────────────────
BANNER
echo -e "${NC}"

# ── Detect install mode ───────────────────────────────────────────────────────
INSTALL_MODE="online"
OFFLINE_REPO_PATH=""

if [[ -f "$OFFLINE_FLAG" ]] && [[ "$(head -1 "$OFFLINE_FLAG")" == "1" ]]; then
  INSTALL_MODE="offline"
  # Parse repo path from flag file
  OFFLINE_REPO_PATH=$(grep "offline-repo-path=" "$OFFLINE_FLAG" 2>/dev/null \
                      | cut -d= -f2 || echo "$LOCALREPO")
fi

info "Install mode: ${INSTALL_MODE}"
if [[ "$INSTALL_MODE" == "offline" ]]; then
  PKG_COUNT=$(ls "${OFFLINE_REPO_PATH}"/*.pkg.tar.* 2>/dev/null | wc -l || echo 0)
  info "Offline repo: ${OFFLINE_REPO_PATH} (${PKG_COUNT} packages bundled)"
else
  warn "No offline repository found."
  warn "Installation requires internet access to CachyOS mirrors."
  echo ""
  read -rp "  Continue with online install? [y/N] " confirm
  [[ "${confirm,,}" == "y" ]] || { echo "Aborted."; exit 0; }
fi

# ── Setup offline repo in pacman.conf ────────────────────────────────────────
setup_offline_pacman() {
  local PACMAN_CONF="/etc/pacman.conf"
  log "Adding offline repo to pacman.conf..."

  if ! grep -q '\[cachyos-local\]' "$PACMAN_CONF"; then
    # Prepend before the first [cachyos] or [core] section
    python3 -c "
import re, sys
path = '${PACMAN_CONF}'
with open(path) as f:
    content = f.read()
inject = '''[cachyos-local]
SigLevel = Optional TrustAll
Server = file://${OFFLINE_REPO_PATH}

'''
# Insert before first repo section after [options]
content = re.sub(r'(?=^\[(?!options)[a-z])', inject, content, count=1, flags=re.MULTILINE)
with open(path, 'w') as f:
    f.write(content)
print('pacman.conf patched')
" 2>>"$LOG" || {
      # Python fallback: just append
      cat >> "$PACMAN_CONF" << EOF

[cachyos-local]
SigLevel = Optional TrustAll
Server = file://${OFFLINE_REPO_PATH}
EOF
    }
  fi

  # Refresh repo metadata (local only)
  pacman -Sy cachyos-local 2>>"$LOG" || warn "Could not refresh local repo — packages will still install."
  log "Offline repo activated."
}

# ── Locate or fetch the CLI installer ────────────────────────────────────────
find_cli_installer() {
  # Check if already on the live ISO
  for p in /usr/bin/cachyos-install /usr/local/bin/cachyos-install \
            /root/cachyos-install; do
    [[ -x "$p" ]] && { echo "$p"; return; }
  done

  # Try pacman (if online)
  if [[ "$INSTALL_MODE" == "online" ]]; then
    log "Fetching cachyos-install from CachyOS repo..."
    pacman -Sy --noconfirm cachyos-install 2>>"$LOG" || true
    command -v cachyos-install &>/dev/null && { command -v cachyos-install; return; }
  fi

  # Download binary directly as last resort
  log "Downloading cachyos-install binary..."
  curl -fsSL "$CLI_INSTALLER_FALLBACK_URL" -o /tmp/cachyos-install 2>>"$LOG" \
    || die "Cannot obtain cachyos-install. No internet and not on live ISO?"
  chmod +x /tmp/cachyos-install
  echo "/tmp/cachyos-install"
}

# ── Register cleanup to remove localrepo from installed system ───────────────
cleanup_installed_system() {
  # This is called by a trap so it runs after cachyos-install completes.
  # Remove [cachyos-local] from the INSTALLED system (mounted at /mnt by convention).
  local TARGET_PACMAN="${CACHYOS_INSTALL_ROOT:-/mnt}/etc/pacman.conf"
  if [[ -f "$TARGET_PACMAN" ]]; then
    sed -i '/^\[cachyos-local\]/,/^$/d' "$TARGET_PACMAN" 2>/dev/null || true
    log "Removed [cachyos-local] from installed system's pacman.conf"
  fi
}
trap cleanup_installed_system EXIT

# ── Main ─────────────────────────────────────────────────────────────────────
if [[ "$INSTALL_MODE" == "offline" ]]; then
  setup_offline_pacman
fi

CLI_BIN=$(find_cli_installer)
log "Using CLI installer: ${CLI_BIN}"

echo ""
echo -e "  ${G}Launching CachyOS CLI Installer...${NC}"
echo -e "  ${C}(The installer is the official CachyOS experience)${NC}"
echo -e "  ${Y}Offline packages will be preferred when available.${NC}"
echo ""
sleep 1

# Hand off to the official installer — all interaction is handled by it
exec "$CLI_BIN" "$@"
