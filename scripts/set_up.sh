#!/usr/bin/env bash

set -e

echo "============================================"
echo "GPU Validation Kit - Production Setup"
echo "============================================"

#############################################
# [0/8] Normalize APT state
#############################################
echo "[0/8] Normalizing APT package state..."

HELD=$(dpkg --get-selections | grep hold || true)

if [[ -n "$HELD" ]]; then
    echo "Held packages detected:"
    echo "$HELD"
    echo "Removing holds..."
    echo "$HELD" | awk '{print $1}' | xargs -r sudo apt-mark unhold
fi

#############################################
# [1/8] Base dependencies
#############################################
echo "[1/8] Installing base dependencies..."

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
echo "[2/8] Disabling Nouveau (if present)..."

if lsmod | grep -q nouveau; then
    echo "blacklist nouveau" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
    echo "options nouveau modeset=0" | sudo tee -a /etc/modprobe.d/blacklist-nouveau.conf
    sudo update-initramfs -u
    echo "Reboot required to fully disable Nouveau"
fi

#############################################
# [3/8] HARD RESET NVIDIA STACK (FIX)
#############################################
echo "[3/8] Resetting NVIDIA stack (fix conflicts)..."

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
echo "[4/8] Installing NVIDIA driver 535 (Ubuntu repo)..."

# Prevent CUDA repo from overriding driver
sudo mkdir -p /etc/apt/preferences.d
echo "Package: nvidia-*
Pin: release o=developer.download.nvidia.com
Pin-Priority: -1" | sudo tee /etc/apt/preferences.d/nvidia-block-cuda

sudo apt-get update
sudo apt-get install -y nvidia-driver-535

#############################################
# [5/8] Install CUDA Toolkit (no driver)
#############################################
echo "[5/8] Installing CUDA Toolkit (without driver override)..."

# Install CUDA toolkit only (no driver)
sudo apt-get install -y cuda-toolkit-11-5

#############################################
# [6/8] Enable persistence mode
#############################################
echo "[6/8] Enabling NVIDIA persistence mode..."

sudo nvidia-smi -pm 1 || true

#############################################
# [7/8] Prevent display sleep / blanking
#############################################
echo "[7/8] Disabling display sleep and screen blanking..."

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
echo "[8/8] Verifying installation..."

nvidia-smi || {
    echo "ERROR: nvidia-smi failed"
    exit 1
}

echo "============================================"
echo "SETUP COMPLETE"
echo "Reboot required: sudo reboot"
echo "============================================"