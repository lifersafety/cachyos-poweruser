# cachyos-poweruser

> **Solve the CachyOS online installer issue** — works fully offline AND online.  
> Based 100% on official CachyOS scripts. Minimal, surgical changes only.

## The Problem

Many users can't complete the standard CachyOS installation because:
- Slow/unstable internet causes package download failures mid-install
- Corporate networks block CachyOS mirrors
- No internet access at all on the target machine

## The Solution

This project takes the **official CachyOS ISO build system** and **official Calamares config** and adds a single offline capability:

1. **Packages are bundled** inside the ISO (KDE Plasma minus LibreOffice, ~4.5 GB)
2. **At live boot**, a systemd service activates the bundled local repo in `pacman.conf`
3. **Two shellprocess steps** are added to Calamares (before/after `packages`)
4. **After install**, the local repo is removed — target system gets standard CachyOS mirrors
5. **Online fallback** — any package not in the bundle downloads from official mirrors

**Zero regression on the online path.** The official install experience is unchanged.

---

## Quick Start

### One-liner (opens TUI menu)
```bash
curl -fsSL https://raw.githubusercontent.com/lifersafety/cachyos-poweruser/main/setup.sh | bash
```

### Build ISO manually (CachyOS/Arch host)
```bash
sudo pacman -S --needed archiso git dialog

git clone https://github.com/lifersafety/cachyos-poweruser
cd cachyos-poweruser

# Build offline ISO (clones official CachyOS-Live-ISO, applies patch, builds)
sudo bash build/build-iso.sh --profile kde-offline --method native

# Result: ~/.cachyos-poweruser/out/cachyos-poweruser-kde-offline-YYYYMMDD.iso
```

### Build on non-Arch Linux (Docker)
```bash
# Any Linux with Docker — no pacman/archiso needed on host
sudo bash build/build-iso.sh --profile kde-offline --method docker
```

### Write to USB
```bash
sudo dd if=~/.cachyos-poweruser/out/*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

---

## Install from live ISO

### Option A — Calamares GUI (recommended)
Boot the ISO → click the install icon. Calamares auto-detects offline repo.  
Choose between **Offline** and **Online** in the first screen.

### Option B — CLI installer
Boot the ISO → open terminal:
```bash
sudo bash /usr/local/bin/cachyos-cli-install.sh
```
This wraps the **official CachyOS New-Cli-Installer** with offline repo setup.

---

## What Changes vs Official CachyOS

| File | Change |
|------|--------|
| `packages.x86_64` | `libreoffice-fresh` and `libreoffice-fresh-en-US` removed |
| `airootfs/etc/calamares/settings.conf` | +2 shellprocess steps added to exec sequence |
| `airootfs/etc/systemd/system/` | +1 service: `cachyos-localrepo.service` |
| `airootfs/usr/local/bin/` | +3 scripts: setup, detect, restore |
| `airootfs/var/cache/localrepo/` | +packages downloaded at build time (offline only) |

**Everything else is the official CachyOS ISO unchanged.**

---

## Project Structure

```
cachyos-poweruser/
├── setup.sh                          # curl | bash entry point
├── build/
│   ├── build-iso.sh                  # clones CachyOS-Live-ISO, patches, builds
│   └── apply-calamares-patch.sh      # the Calamares patch logic
├── installer/
│   └── cachyos-cli-install.sh        # wraps New-Cli-Installer with offline support
├── tui/
│   └── tui.sh                        # dialog-based TUI menu
├── webui/
│   └── index.html                    # web UI
└── .github/
    └── workflows/
        └── build.yml                 # CI: build ISOs for releases
```

---

## Upstream Sources

| Project | Role |
|---------|------|
| [CachyOS/CachyOS-Live-ISO](https://github.com/CachyOS/CachyOS-Live-ISO) | ISO build system (cloned by `build-iso.sh`) |
| [CachyOS/New-Cli-Installer](https://github.com/CachyOS/New-Cli-Installer) | CLI installer (wrapped by `cachyos-cli-install.sh`) |
| [CachyOS/cachyos-calamares](https://github.com/CachyOS/cachyos-calamares) | Calamares config (patched in the ISO) |

---

## License

GPLv3 — matching upstream CachyOS licensing.  
Not affiliated with the CachyOS project.

## Contributing

- **Add a desktop variant** — create a profile and open a PR
- **Report bugs** — open an issue
- **Test builds** — test in QEMU before hardware
