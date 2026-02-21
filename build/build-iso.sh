#!/usr/bin/env bash
# cachyos-poweruser — build/build-iso.sh
# Clones official CachyOS-Live-ISO, applies minimal offline patch, builds ISO.
#
# Usage:
#   sudo bash build/build-iso.sh --profile kde-offline --method native --outdir ./out
#   sudo bash build/build-iso.sh --profile kde-online  --method docker  --outdir ./out
#
# --profile  kde-offline  →  KDE + bundled offline repo (Calamares shows offline option)
#            kde-online   →  KDE standard (identical to official CachyOS, no patch)
# --method   native       →  run directly on Arch/CachyOS host
#            docker       →  run inside archlinux Docker container
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG="${HOME}/.cachyos-poweruser/build.log"
WORK_DIR="${HOME}/.cachyos-poweruser/work"

# Official upstream repos — we clone these and patch minimally
CACHYOS_LIVE_ISO_REPO="https://github.com/CachyOS/CachyOS-Live-ISO.git"
CACHYOS_CALAMARES_REPO="https://github.com/CachyOS/cachyos-calamares.git"

# Defaults
PROFILE="kde-offline"
METHOD="native"
OUTDIR="${HOME}/.cachyos-poweruser/out"

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --method)  METHOD="$2";  shift 2 ;;
    --outdir)  OUTDIR="$2";  shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$WORK_DIR" "$OUTDIR"
: >> "$LOG"

log()  { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
die()  { echo "[ERROR] $*" | tee -a "$LOG" >&2; exit 1; }
step() { echo "" | tee -a "$LOG"; echo "═══ $* ═══" | tee -a "$LOG"; }

# ── Docker wrapper ────────────────────────────────────────────────────────────
if [[ "$METHOD" == "docker" ]]; then
  log "Launching build inside Arch Linux Docker container..."
  docker run --rm --privileged \
    -v "${PROJECT_ROOT}:/workspace:ro" \
    -v "${WORK_DIR}:/work" \
    -v "${OUTDIR}:/out" \
    archlinux:latest /bin/bash -lc "
      set -euo pipefail
      pacman -Syu --noconfirm 2>/dev/null
      pacman -S --noconfirm --needed archiso squashfs-tools xorriso git rsync python 2>/dev/null
      bash /workspace/build/build-iso.sh --profile ${PROFILE} --method native --outdir /out
    "
  log "Docker build finished. ISO in ${OUTDIR}/"
  exit 0
fi

# ── Native build ──────────────────────────────────────────────────────────────
[[ "$EUID" -eq 0 ]] || die "Native build must run as root (sudo)"
command -v archiso &>/dev/null || die "archiso not installed. Run: pacman -S archiso"

step "Fetching upstream CachyOS-Live-ISO"
LIVE_ISO_DIR="${WORK_DIR}/CachyOS-Live-ISO"
if [[ ! -d "${LIVE_ISO_DIR}/.git" ]]; then
  log "Cloning ${CACHYOS_LIVE_ISO_REPO} ..."
  git clone --depth=1 "${CACHYOS_LIVE_ISO_REPO}" "${LIVE_ISO_DIR}" >> "$LOG" 2>&1
else
  log "Updating CachyOS-Live-ISO ..."
  git -C "${LIVE_ISO_DIR}" fetch --depth=1 origin main >> "$LOG" 2>&1
  git -C "${LIVE_ISO_DIR}" reset --hard origin/main    >> "$LOG" 2>&1
fi

# Discover the KDE desktop profile directory
# CachyOS-Live-ISO uses profiles like: desktop/kde or similar
PROFILE_DIR=""
for d in "${LIVE_ISO_DIR}/desktop-kde" "${LIVE_ISO_DIR}/profiles/kde" \
          "${LIVE_ISO_DIR}/kde" "${LIVE_ISO_DIR}"; do
  if [[ -f "${d}/profiledef.sh" ]]; then
    PROFILE_DIR="$d"; break
  fi
done
[[ -n "$PROFILE_DIR" ]] || die "Cannot find KDE archiso profile in CachyOS-Live-ISO. Layout may have changed."
log "Found profile at: ${PROFILE_DIR}"

# ── Copy profile to work dir ──────────────────────────────────────────────────
BUILD_PROFILE="${WORK_DIR}/build-profile-${PROFILE}"
rm -rf "$BUILD_PROFILE"
cp -a "${PROFILE_DIR}" "$BUILD_PROFILE"

step "Applying cachyos-poweruser patches to profile"

# ── Patch 1: Remove LibreOffice from packages list ────────────────────────────
PKGLIST=""
for p in "${BUILD_PROFILE}/packages.x86_64" "${BUILD_PROFILE}/packages"; do
  [[ -f "$p" ]] && PKGLIST="$p" && break
done

if [[ -n "$PKGLIST" ]]; then
  log "Removing LibreOffice from package list..."
  sed -i '/^libreoffice/d' "$PKGLIST"
  log "LibreOffice entries removed."
fi

# ── Patch 2: Offline profile — embed packages + patch Calamares ───────────────
if [[ "$PROFILE" == "kde-offline" ]]; then
  step "Setting up offline repository"

  OFFLINE_REPO_DIR="${BUILD_PROFILE}/airootfs/var/cache/localrepo"
  mkdir -p "$OFFLINE_REPO_DIR"

  # Download all packages listed in the profile's package list
  # We use pacman -Syw (download without installing) into a temp cache,
  # then copy everything into the ISO's airootfs as a local repo.
  PKG_DOWNLOAD_DIR="${WORK_DIR}/pkg-cache"
  mkdir -p "$PKG_DOWNLOAD_DIR"

  if [[ -n "$PKGLIST" ]]; then
    log "Downloading packages for offline bundling (this takes a while)..."
    # Read non-comment, non-empty package names
    mapfile -t PKGS < <(grep -vE '^\s*#|^\s*$' "$PKGLIST")
    if [[ ${#PKGS[@]} -gt 0 ]]; then
      pacman -Syw --noconfirm --cachedir "$PKG_DOWNLOAD_DIR" "${PKGS[@]}" >> "$LOG" 2>&1 \
        || log "WARNING: Some packages failed to download. They will fall back to online."
    fi

    # Copy downloaded packages into the ISO airootfs local repo
    find "$PKG_DOWNLOAD_DIR" -name "*.pkg.tar.*" -exec cp -n {} "${OFFLINE_REPO_DIR}/" \;
    local_count=$(ls "${OFFLINE_REPO_DIR}"/*.pkg.tar.* 2>/dev/null | wc -l || echo 0)
    log "Bundled ${local_count} packages into offline repo"

    # Build the pacman database for the local repo
    if [[ "$local_count" -gt 0 ]]; then
      log "Building local repo database..."
      repo-add "${OFFLINE_REPO_DIR}/cachyos-local.db.tar.gz" \
        "${OFFLINE_REPO_DIR}"/*.pkg.tar.* >> "$LOG" 2>&1
      log "Local repo database created."
    fi
  fi

  # ── Patch Calamares: add offline detection + local repo ─────────────────────
  source "${PROJECT_ROOT}/build/apply-calamares-patch.sh"
  apply_calamares_patch "$BUILD_PROFILE"

  # ── Patch systemd service: auto-mount localrepo at boot ─────────────────────
  SYSTEMD_DIR="${BUILD_PROFILE}/airootfs/etc/systemd/system"
  mkdir -p "$SYSTEMD_DIR"

  cat > "${SYSTEMD_DIR}/cachyos-localrepo.service" << 'SVC'
[Unit]
Description=Mount CachyOS local offline repository
DefaultDependencies=no
Before=pacman-init.service calamares.service cachyos-installer.service
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/cachyos-localrepo-setup

[Install]
WantedBy=multi-user.target
SVC

  # Script that runs at boot to activate the local repo
  mkdir -p "${BUILD_PROFILE}/airootfs/usr/local/bin"
  cat > "${BUILD_PROFILE}/airootfs/usr/local/bin/cachyos-localrepo-setup" << 'SETUP'
#!/usr/bin/env bash
# Activates the bundled offline repository if present.
# Runs at live-ISO boot via cachyos-localrepo.service
set -euo pipefail

LOCALREPO="/var/cache/localrepo"
PACMAN_CONF="/etc/pacman.conf"
FLAG="/run/cachyos-poweruser/offline-available"

mkdir -p /run/cachyos-poweruser

# Check if local repo is present and has packages
if [[ -f "${LOCALREPO}/cachyos-local.db.tar.gz" ]] && \
   ls "${LOCALREPO}"/*.pkg.tar.* &>/dev/null 2>&1; then

  # Inject local repo at top of pacman.conf (before any [core] etc.)
  if ! grep -q '\[cachyos-local\]' "$PACMAN_CONF"; then
    # Insert after [options] section
    sed -i '/^\[options\]/,/^\[/{/^\[cachyos\|^\[core\|^\[extra/{
      i [cachyos-local]
      i SigLevel = Optional TrustAll
      i Server = file:///var/cache/localrepo
      i
    }}' "$PACMAN_CONF" 2>/dev/null || {
      # Fallback: append at end
      cat >> "$PACMAN_CONF" << 'EOF'

[cachyos-local]
SigLevel = Optional TrustAll
Server = file:///var/cache/localrepo
EOF
    }
  fi

  # Refresh local repo metadata
  pacman -Sy cachyos-local 2>/dev/null || true

  # Write flag file for Calamares to detect
  echo "1" > "$FLAG"
  echo "offline-repo-path=${LOCALREPO}" >> "$FLAG"
  echo "[cachyos-poweruser] Offline repository activated at ${LOCALREPO}"
else
  echo "0" > "$FLAG"
  echo "[cachyos-poweruser] No offline repository found — online mode only"
fi
SETUP
  chmod +x "${BUILD_PROFILE}/airootfs/usr/local/bin/cachyos-localrepo-setup"

  # Enable the service in the live system
  mkdir -p "${SYSTEMD_DIR}/multi-user.target.wants"
  ln -sf "../cachyos-localrepo.service" \
    "${SYSTEMD_DIR}/multi-user.target.wants/cachyos-localrepo.service" 2>/dev/null || true

  log "Offline setup complete."
fi  # end kde-offline block

step "Building ISO with archiso"
WORK_ISO="${WORK_DIR}/archiso-work-${PROFILE}"
rm -rf "$WORK_ISO"

mkarchiso -v -w "$WORK_ISO" -o "$OUTDIR" "$BUILD_PROFILE" >> "$LOG" 2>&1

# Rename output ISO clearly
PRODUCED_ISO=$(ls "${OUTDIR}"/cachyos-*.iso 2>/dev/null | tail -1 \
              || ls "${OUTDIR}"/*.iso 2>/dev/null | tail -1 || echo "")

if [[ -n "$PRODUCED_ISO" ]]; then
  TIMESTAMP=$(date +%Y%m%d)
  NEW_NAME="${OUTDIR}/cachyos-poweruser-${PROFILE}-${TIMESTAMP}.iso"
  mv "$PRODUCED_ISO" "$NEW_NAME"
  sha256sum "$NEW_NAME" > "${NEW_NAME}.sha256"
  log "ISO ready: ${NEW_NAME}"
  log "SHA256:    $(cut -d' ' -f1 "${NEW_NAME}.sha256")"
  ISO_SIZE=$(du -sh "$NEW_NAME" | cut -f1)
  log "Size:      ${ISO_SIZE}"
else
  die "Build finished but no ISO found in ${OUTDIR}"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  cachyos-poweruser BUILD COMPLETE                        ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  ISO: ${NEW_NAME}"
echo "║  Write to USB:"
echo "║    sudo dd if=${NEW_NAME} of=/dev/sdX bs=4M status=progress oflag=sync"
echo "╚══════════════════════════════════════════════════════════╝"
