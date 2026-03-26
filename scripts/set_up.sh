#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# GPU Validation Kit - Production Setup Script
# Target: Ubuntu 22.04 + NVIDIA 535 + CUDA 12.2
# ============================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_ROOT/src"
BIN_DIR="$REPO_ROOT/bin"

echo "============================================"
echo "GPU Validation Kit - Production Setup"
echo "============================================"

# ------------------------------------------------------------
# OS Check
# ------------------------------------------------------------
if ! grep -q "22.04" /etc/os-release; then
    echo "WARNING: This script is validated for Ubuntu 22.04"
fi

# ------------------------------------------------------------
# Base Dependencies
# ------------------------------------------------------------
echo ""
echo "[1/8] Installing base dependencies..."

sudo apt update

sudo apt install -y \
    build-essential \
    cmake \
    git \
    curl \
    wget \
    pkg-config \
    libvulkan1 \
    vulkan-tools \
    nvtop \
    linux-headers-$(uname -r)

# ------------------------------------------------------------
# Disable Nouveau (prevent conflicts)
# ------------------------------------------------------------
echo ""
echo "[2/8] Disabling Nouveau (if present)..."

if lsmod | grep -q nouveau; then
    echo "Blacklisting nouveau..."
    echo "blacklist nouveau" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
    echo "options nouveau modeset=0" | sudo tee -a /etc/modprobe.d/blacklist-nouveau.conf
    sudo update-initramfs -u
fi

# ------------------------------------------------------------
# Install NVIDIA Driver 535
# ------------------------------------------------------------
echo ""
echo "[3/8] Installing NVIDIA driver 535..."

if ! dpkg -l | grep -q nvidia-driver-535; then
    sudo apt install -y nvidia-driver-535
else
    echo "Driver already installed."
fi

# ------------------------------------------------------------
# Add NVIDIA CUDA Repository (12.2)
# ------------------------------------------------------------
echo ""
echo "[4/8] Adding NVIDIA CUDA repository..."

CUDA_KEYRING="/tmp/cuda-keyring.deb"

if [ ! -f /usr/share/keyrings/cuda-archive-keyring.gpg ]; then
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb -O "$CUDA_KEYRING"
    sudo dpkg -i "$CUDA_KEYRING"
fi

sudo apt update

# ------------------------------------------------------------
# Install CUDA Toolkit 12.2
# ------------------------------------------------------------
echo ""
echo "[5/8] Installing CUDA Toolkit 12.2..."

if ! dpkg -l | grep -q cuda-toolkit-12-2; then
    sudo apt install -y cuda-toolkit-12-2
else
    echo "CUDA Toolkit 12.2 already installed."
fi

# ------------------------------------------------------------
# Environment Variables
# ------------------------------------------------------------
echo ""
echo "[6/8] Configuring environment variables..."

CUDA_PATH="/usr/local/cuda-12.2"

if ! grep -q "$CUDA_PATH" ~/.bashrc; then
    cat <<EOF >> ~/.bashrc

# CUDA 12.2
export PATH=$CUDA_PATH/bin:\$PATH
export LD_LIBRARY_PATH=$CUDA_PATH/lib64:\$LD_LIBRARY_PATH
EOF
fi

export PATH=$CUDA_PATH/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_PATH/lib64:$LD_LIBRARY_PATH

# ------------------------------------------------------------
# Keep Display ON (GUI + TTY)
# ------------------------------------------------------------
echo ""
echo "[7/8] Disabling display sleep..."

mkdir -p ~/.config/autostart

cat <<EOF > ~/.config/autostart/keep_display_on.desktop
[Desktop Entry]
Type=Application
Exec=bash -c "xset s off; xset s noblank; xset -dpms"
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Keep Display On
EOF

if ! grep -q "consoleblank=0" /etc/default/grub; then
    sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="consoleblank=0 /' /etc/default/grub
    sudo update-grub
fi

# ------------------------------------------------------------
# Build Validation Tools
# ------------------------------------------------------------
echo ""
echo "[8/8] Building validation tools..."

mkdir -p "$SRC_DIR" "$BIN_DIR"
cd "$SRC_DIR"

# CUDA Samples (12.x compatible)
if [ ! -d cuda-samples ]; then
    git clone https://github.com/NVIDIA/cuda-samples.git
fi

cd cuda-samples
git checkout v12.2

cd Samples/1_Utilities/bandwidthTest
make -j"$(nproc)"
cp bandwidthTest "$BIN_DIR/"

# gpu-burn
cd "$SRC_DIR"
if [ ! -d gpu-burn ]; then
    git clone https://github.com/wilicc/gpu-burn.git
fi

cd gpu-burn
make
cp gpu_burn "$BIN_DIR/"

# cuda_memtest
cd "$SRC_DIR"
if [ ! -d cuda_memtest ]; then
    git clone https://github.com/ComputationalRadiationPhysics/cuda_memtest.git
fi

mkdir -p cuda_memtest/build
cd cuda_memtest/build
cmake ..
make -j"$(nproc)"
cp cuda_memtest "$BIN_DIR/"

# memtest_vulkan
cd "$SRC_DIR"

if ! command -v cargo &> /dev/null; then
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    source "$HOME/.cargo/env"
fi

if [ ! -d memtest_vulkan ]; then
    git clone https://github.com/GpuZelenograd/memtest_vulkan.git
fi

cd memtest_vulkan
cargo build --release
cp target/release/memtest_vulkan "$BIN_DIR/"

# ------------------------------------------------------------
# Final Validation Check
# ------------------------------------------------------------
echo ""
echo "============================================"
echo "Final Validation Check"
echo "============================================"

if ! nvidia-smi &> /dev/null; then
    echo "WARNING: NVIDIA driver not active yet."
    echo ""
    echo ">>> REBOOT REQUIRED <<<"
    echo "Run after reboot:"
    echo "nvidia-smi"
    exit 0
fi

echo ""
echo "NVIDIA-SMI:"
nvidia-smi

echo ""
echo "NVCC:"
nvcc -V || true

echo ""
echo "Vulkan:"
vulkaninfo --summary | head -n 20 || true

echo ""
echo "============================================"
echo "SETUP COMPLETE"
echo "============================================"
echo ""
echo "Binaries located in:"
echo "$BIN_DIR"
echo ""
echo "Run validation with:"
echo "./scripts/run_gpu_validation.sh"
echo ""