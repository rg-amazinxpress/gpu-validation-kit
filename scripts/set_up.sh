#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# GPU Validation Kit - Production Setup
# =============================================================================

# Paths
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGS_DIR="$BASE_DIR/logs"
mkdir -p "$LOGS_DIR"

# Timestamped log file
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="$LOGS_DIR/setup_$TIMESTAMP.log"

# Logging function
log_step() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$LOG_FILE"
}

echo "============================================" | tee -a "$LOG_FILE"
echo "GPU Validation Kit - Production Setup" | tee -a "$LOG_FILE"
echo "Started at: $(date)" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "============================================" | tee -a "$LOG_FILE"
echo | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# 0/8 - Normalize APT package state
# -----------------------------------------------------------------------------
log_step "[0/8] Normalizing APT package state..."
sudo apt update -y | tee -a "$LOG_FILE"
sudo apt upgrade -y | tee -a "$LOG_FILE"
sudo apt --fix-broken install -y | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# 1/8 - Install base dependencies
# -----------------------------------------------------------------------------
log_step "[1/8] Installing base dependencies..."
sudo apt install -y \
    build-essential libvulkan1 pkg-config vulkan-tools nvtop cmake curl git \
    linux-headers-$(uname -r) wget | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# 2/8 - Disable Nouveau (if present)
# -----------------------------------------------------------------------------
log_step "[2/8] Disabling Nouveau (if present)..."
if ! grep -q "blacklist nouveau" /etc/modprobe.d/blacklist.conf; then
    echo "blacklist nouveau" | sudo tee -a /etc/modprobe.d/blacklist.conf
    echo "options nouveau modeset=0" | sudo tee -a /etc/modprobe.d/blacklist.conf
    sudo update-initramfs -u | tee -a "$LOG_FILE"
fi

# -----------------------------------------------------------------------------
# 3/8 - Reset NVIDIA stack (fix conflicts)
# -----------------------------------------------------------------------------
log_step "[3/8] Resetting NVIDIA stack (may disrupt display)"

# Detect broken NVIDIA packages safely
BROKEN_PKGS=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null \
    | awk '$1 ~ /^(iU|iF|rc)/ && $2 ~ /nvidia/ {print $2}')

if [[ -n "$BROKEN_PKGS" ]]; then
    log_step "Removing broken NVIDIA packages..."
    echo "$BROKEN_PKGS" | tee -a "$LOG_FILE"
    echo "$BROKEN_PKGS" | xargs -r sudo dpkg --remove --force-remove-reinstreq | tee -a "$LOG_FILE"
fi

# Stop display manager ONLY if SSH session
if [[ -n "${SSH_CONNECTION:-}" ]]; then
    log_step "Stopping display manager (SSH session detected)"
    sudo systemctl stop gdm3 2>/dev/null || true
    sudo systemctl stop lightdm 2>/dev/null || true
else
    log_step "Skipping display manager stop (local session detected)"
fi

# -----------------------------------------------------------------------------
# 4/8 - Install NVIDIA drivers
# -----------------------------------------------------------------------------
log_step "[4/8] Installing NVIDIA drivers..."
sudo apt install -y nvidia-driver-535 nvidia-utils-535 | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# 5/8 - Install CUDA toolkit
# -----------------------------------------------------------------------------
log_step "[5/8] Installing CUDA toolkit..."
sudo apt install -y nvidia-cuda-toolkit | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# 6/8 - Post-install checks
# -----------------------------------------------------------------------------
log_step "[6/8] Verifying NVIDIA driver installation..."
nvidia-smi | tee -a "$LOG_FILE"

log_step "[6/8] Verifying CUDA installation..."
nvcc --version | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# 7/8 - Optional utilities
# -----------------------------------------------------------------------------
log_step "[7/8] Installing optional utilities..."
sudo apt install -y nvtop vulkan-tools | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# 8/8 - Completion
# -----------------------------------------------------------------------------
log_step "[8/8] Setup completed successfully!"
echo "============================================" | tee -a "$LOG_FILE"
echo "Setup finished at: $(date)" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"