#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# COLORS
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==============================================================================
# LOGGING
# ==============================================================================

log() {
    echo -e "\n${BLUE}==================================================${NC}"
    echo -e "${GREEN}>>> $1${NC}"
    echo -e "${BLUE}==================================================${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ==============================================================================
# ROOT CHECK
# ==============================================================================

if [[ $EUID -ne 0 ]]; then
    error "Please run this script with sudo"
    echo "sudo $0"
    exit 1
fi

# ==============================================================================
# ARCH LINUX CHECK
# ==============================================================================

if ! grep -qi arch /etc/os-release; then
    error "This script only supports Arch Linux"
    exit 1
fi

# ==============================================================================
# VARIABLES & HELPERS
# ==============================================================================

REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~${REAL_USER}")

# Helper to run commands as the non-root user
run_as_user() {
    sudo -u "${REAL_USER}" env HOME="${USER_HOME}" "$@"
}

# ==============================================================================
# PRIORITY 1: PACMAN (OFFICIAL REPOSITORIES)
# ==============================================================================

log "Updating system & installing official Pacman packages"

# Full system upgrade
pacman -Syu --noconfirm

# Install packages available in the official Arch repositories
# - base-devel: Required for building AUR packages later
# - curl, wget, git, vim: Standard development tools
# - flatpak: Flatpak manager
# - docker, docker-compose: Container platform
# - fastfetch, btop: System monitors and info
# - lazydocker: Docker TUI dashboard (available in Arch Extra repo)
pacman -S --needed --noconfirm \
    base-devel \
    curl \
    wget \
    git \
    vim \
    flatpak \
    docker \
    docker-compose \
    fastfetch \
    btop \
    lazydocker

# ==============================================================================
# PRIORITY 2: YAY (ARCH USER REPOSITORY - AUR)
# ==============================================================================

# 1. Install yay (AUR Helper) if not already installed
if ! command -v yay &> /dev/null; then
    log "Installing yay (AUR helper)..."
    
    build_dir="${USER_HOME}/.cache/yay-build"
    run_as_user mkdir -p "${build_dir}"
    run_as_user git clone https://aur.archlinux.org/yay-bin.git "${build_dir}/yay-bin"
    run_as_user bash -c "cd ${build_dir}/yay-bin && makepkg -si --noconfirm"
    run_as_user rm -rf "${build_dir}"
fi

# 2. Install packages via yay
# - visual-studio-code-bin: Official Microsoft proprietary VS Code release
# - google-chrome: Proprietary web browser
# - ibus-bamboo: Vietnamese keyboard engine
# - tabby-bin: Modern terminal emulator
# - antigravity-bin: Antigravity app
log "Installing AUR packages via yay"

run_as_user yay -S --needed --noconfirm \
    visual-studio-code-bin \
    google-chrome \
    ibus-bamboo \
    tabby-bin \
    antigravity-bin

# ==============================================================================
# PRIORITY 3: FLATPAK (FLATHUB)
# ==============================================================================

log "Configuring Flatpak & Flathub"

flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo

log "Installing Navicat Premium (Flatpak)"

flatpak install -y \
    https://dn.navicat.com/flatpak/flatpakref/navicat17/com.navicat.premium.en.flatpakref || true

# ==============================================================================
# SERVICES CONFIGURATION
# ==============================================================================

log "Configuring services"

systemctl enable --now docker
usermod -aG docker "${REAL_USER}"

# ==============================================================================
# RESTART IBUS
# ==============================================================================

log "Restarting ibus"

# Restart Ibus targeting the user's DBus session bus specifically
run_as_user bash -c "DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u ${REAL_USER})/bus ibus restart" 2>/dev/null || true

# ==============================================================================
# SHELL ALIASES
# ==============================================================================

log "Adding shell aliases"

grep -qxF "alias vi='vim'" "${USER_HOME}/.bashrc" || \
echo "alias vi='vim'" >> "${USER_HOME}/.bashrc"

grep -qxF "alias docker-compose='docker compose'" "${USER_HOME}/.bashrc" || \
echo "alias docker-compose='docker compose'" >> "${USER_HOME}/.bashrc"

# ==============================================================================
# CLEANUP
# ==============================================================================

log "Cleaning system"

# Clean pacman cache
pacman -Sc --noconfirm

# Remove orphaned packages
if pacman -Qtdq &>/dev/null; then
    pacman -Rns --noconfirm $(pacman -Qtdq)
fi

flatpak uninstall --unused -y || true

journalctl --vacuum-time=2d || true

# ==============================================================================
# DONE
# ==============================================================================

log "Installation completed successfully"

echo -e "${GREEN}Installed packages:${NC}"
echo "- Visual Studio Code (via Yay)"
echo "- Google Chrome (via Yay)"
echo "- Docker & Docker Compose (via Pacman)"
echo "- Tabby (via Yay)"
echo "- Antigravity (via Yay)"
echo "- Navicat Premium (via Flatpak)"
echo "- ibus-bamboo (Vietnamese keyboard, via Yay)"
echo "- fastfetch (via Pacman)"
echo "- btop (via Pacman)"
echo "- lazydocker (via Pacman)"

echo
echo -e "${YELLOW}IMPORTANT:${NC}"
echo "1. Please log out and log back in to apply docker group changes."
echo "2. Configure Vietnamese keyboard:"
echo "   Go to: Settings -> Keyboard -> Input Sources -> Add (+)"
echo "   Select: Vietnamese -> Vietnamese (Bamboo (US layout))"
echo "   Swap keyboard with: Super + Space"

echo
echo "Useful commands:"
echo "  docker ps"
echo "  lazydocker"
echo "  btop"
echo "  fastfetch"
