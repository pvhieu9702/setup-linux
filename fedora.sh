#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# CONFIG
# ==============================================================================

TABBY_VERSION="1.0.233"
TABBY_RPM="tabby-${TABBY_VERSION}-linux-x64.rpm"

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
# CLEANUP
# ==============================================================================

cleanup() {
    rm -f "/tmp/${TABBY_RPM}" 2>/dev/null || true
}

trap cleanup EXIT

# ==============================================================================
# ROOT CHECK
# ==============================================================================

if [[ $EUID -ne 0 ]]; then
    error "Please run this script with sudo"
    echo "sudo $0"
        exit 1
    fi

# ==============================================================================
# FEDORA CHECK
# ==============================================================================

if ! grep -qi fedora /etc/os-release; then
    error "This script only supports Fedora"
    exit 1
fi

# ==============================================================================
# VARIABLES
# ==============================================================================

REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~${REAL_USER}")

# ==============================================================================
# PRE-REQUISITES & INITIAL SYSTEM UPDATE
# ==============================================================================

log "Updating system & installing pre-requisites"

dnf -y upgrade

# Install basic packages required for repo setups and downloads
dnf install -y \
    curl \
    wget \
    git \
    vim \
    flatpak \
    dnf-plugins-core

# ==============================================================================
# PARALLEL DOWNLOAD & REPO SETUP
# ==============================================================================

log "Setting up repositories and pre-fetching assets in parallel"

# 1. Download Tabby RPM in the background using curl
log "Starting background download of Tabby RPM..."
curl -L \
    "https://github.com/Eugeny/tabby/releases/download/v${TABBY_VERSION}/${TABBY_RPM}" \
    -o "/tmp/${TABBY_RPM}" &
TABBY_DOWNLOAD_PID=$!

# 2. VSCode Repository Configuration
rpm --import https://packages.microsoft.com/keys/microsoft.asc

cat >/etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# 3. Lazydocker COPR Repository
dnf copr enable atim/lazydocker -y

# 4. Enable Flathub
flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo

# Wait for Tabby download to finish completely
log "Waiting for background Tabby RPM download to finish..."
wait $TABBY_DOWNLOAD_PID

# ==============================================================================
# UNIFIED SINGLE-TRANSACTION INSTALLATION
# ==============================================================================

log "Installing all applications in a single fast DNF transaction"

# Running a single dnf transaction is faster, resolves all dependencies together,
# and avoids concurrent DNF database lock errors.
dnf install -y --nogpgcheck \
    code \
    https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm \
    docker \
    ibus-bamboo \
    fastfetch \
    btop \
    lazydocker \
    antigravity \
    "/tmp/${TABBY_RPM}"

# ==============================================================================
# SERVICES CONFIGURATION
# ==============================================================================

log "Configuring services"

systemctl enable --now docker
usermod -aG docker "${REAL_USER}"

# ==============================================================================
# FLATPAK APPS
# ==============================================================================

log "Installing Navicat Premium (Flatpak)"

flatpak install -y \
    https://dn.navicat.com/flatpak/flatpakref/navicat17/com.navicat.premium.en.flatpakref || true

# ==============================================================================
# RESTART IBUS
# ==============================================================================

log "Restarting ibus"

# Restart Ibus targeting the user's DBus session bus specifically
su - "${REAL_USER}" -c "DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u ${REAL_USER})/bus ibus restart" 2>/dev/null || true

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

dnf autoremove -y
dnf clean all

flatpak uninstall --unused -y || true

journalctl --vacuum-time=2d || true

# ==============================================================================
# DONE
# ==============================================================================

log "Installation completed successfully"

echo -e "${GREEN}Installed packages:${NC}"
echo "- Visual Studio Code"
echo "- Google Chrome"
echo "- Docker"
echo "- Tabby"
echo "- Antigravity"
echo "- Navicat Premium (Flatpak)"
echo "- ibus-bamboo (Vietnamese keyboard)"
echo "- fastfetch"
echo "- btop"
echo "- lazydocker"

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
