#!/usr/bin/env bash

set -e

echo "============================================"
echo "GPU Validation Kit - Production Setup"
echo "============================================"

#############################################
# LOGGING SETUP
#############################################

LOG_DIR="$(pwd)/logs"
mkdir -p "$LOG_DIR"

TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
LOG_FILE="$LOG_DIR/setup_${TIMESTAMP}.log"

# Redirect ALL output (stdout + stderr) to log + console
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================"
echo "GPU Validation Kit - Setup Log"
echo "Started at: $(date)"
echo "Log file: $LOG_FILE"
echo "============================================"

log_step() {
    echo ""
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

#############################################
# [0/8] Normalize APT + repair broken state
#############################################
log_step "[0/8] Normalizing APT package state..."

# Fix broken dpkg BEFORE anything else
sudo dpkg --configure -a || true
sudo apt-get -f install -y || true

# Remove any stuck NVIDIA packages (critical for your error)
BROKEN_PKGS=$(dpkg -l | grep -E 'nvidia|libnvidia' | grep -E '^iU|^iF|^rc' | awk '{print $2}' || true)

if [[ -n "$BROKEN_PKGS" ]]; then
    log_step "Removing broken NVIDIA packages..."
    log_step "$BROKEN_PKGS" | xargs -r sudo dpkg --remove --force-remove-reinstreq || true
fi

# Clean again after forced removal
sudo apt-get -f install -y || true

# Handle held packages
HELD=$(dpkg --get-selections | grep hold || true)

if [[ -n "$HELD" ]]; then
    log_step "Held packages detected:"
    log_step "$HELD"
    log_step "$HELD" | awk '{print $1}' | xargs -r sudo apt-mark unhold
fi

#############################################
# [1/8] Base dependencies
#############################################
log_step "[1/8] Installing base dependencies..."

sudo apt-get update

sudo apt-get install -y \
    build-essential \
    cmake \
    pkg-config \
    curl \
    wget \
    git \
    linux-headers-$(uname -r) \
    vulkan-tools \
    libvulkan1 \
    nvtop

#############################################
# [2/8] Disable Nouveau
#############################################
log_step "[2/8] Disabling Nouveau (if present)..."

if lsmod | grep -q nouveau; then
    log_step "blacklist nouveau" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
    log_step "options nouveau modeset=0" | sudo tee -a /etc/modprobe.d/blacklist-nouveau.conf
    sudo update-initramfs -u
    log_step "Reboot required to fully disable Nouveau"
fi

#############################################
# [3/8] HARD RESET NVIDIA STACK (FIX)
#############################################
log_step "[3/8] Resetting NVIDIA stack (fix conflicts)..."

# Stop display manager (prevents file locks)
sudo systemctl stop gdm3 2>/dev/null || true
sudo systemctl stop lightdm 2>/dev/null || true

# Remove ALL NVIDIA packages
sudo apt-get remove --purge -y '^nvidia-.*' '^libnvidia-.*' || true

# Remove CUDA driver remnants
sudo apt-get remove --purge -y cuda-drivers cuda-runtime-* || true

# Remove firmware conflicts
sudo apt-get remove --purge -y nvidia-firmware-535-* || true

# Fix broken dpkg state
sudo dpkg --configure -a
sudo apt-get -f install -y

# Cleanup
sudo apt-get autoremove -y
sudo apt-get clean

#############################################
# [4/8] Install NVIDIA Driver (clean source)
#############################################
log_step "[4/8] Installing NVIDIA driver 535 (Ubuntu repo)..."

# Prevent CUDA repo from overriding driver
sudo mkdir -p /etc/apt/preferences.d
log_step "Package: nvidia-*
Pin: release o=developer.download.nvidia.com
Pin-Priority: -1" | sudo tee /etc/apt/preferences.d/nvidia-block-cuda

sudo apt-get update
sudo apt-get install -y nvidia-driver-535

#############################################
# [5/8] Install CUDA Toolkit (no driver)
#############################################
log_step "[5/8] Installing CUDA Toolkit (without driver override)..."

# Install CUDA toolkit only (no driver)
sudo apt-get install -y cuda-toolkit-11-5

#############################################
# [6/8] Enable persistence mode
#############################################
log_step "[6/8] Enabling NVIDIA persistence mode..."

sudo nvidia-smi -pm 1 || true

#############################################
# [7/8] Prevent display sleep / blanking
#############################################
log_step "[7/8] Disabling display sleep and screen blanking..."

# For X11 sessions
if command -v gsettings &> /dev/null; then
    gsettings set org.gnome.desktop.session idle-delay 0 || true
    gsettings set org.gnome.desktop.screensaver lock-enabled false || true
fi

# Disable DPMS (terminal fallback)
if command -v xset &> /dev/null; then
    xset s off || true
    xset -dpms || true
    xset s noblank || true
fi

#############################################
# [8/8] Final verification
#############################################
log_step "[8/8] Verifying installation..."

nvidia-smi || {
    log_step "ERROR: nvidia-smi failed"
    exit 1
}

log_step "============================================"
log_step "SETUP COMPLETE"
log_step "Reboot required: sudo reboot"
log_step "============================================"