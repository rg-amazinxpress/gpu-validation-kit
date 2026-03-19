#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# GPU Validation Kit - Environment Setup (Ubuntu 22.04)
# ============================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_ROOT/src"
BIN_DIR="$REPO_ROOT/bin"

echo "============================================"
echo "GPU Validation Kit - Setup"
echo "============================================"

# ------------------------------------------------------------
# OS Check
# ------------------------------------------------------------
if ! grep -q "Ubuntu 22.04" /etc/os-release 2>/dev/null; then
    echo "WARNING: This toolkit was validated on Ubuntu 22.04"
fi

# ------------------------------------------------------------
# Install base dependencies
# ------------------------------------------------------------
echo ""
echo "Installing system dependencies..."

sudo add-apt-repository -y multiverse
sudo apt update

sudo apt install -y \
git \
build-essential \
cmake \
pkg-config \
libvulkan1 \
vulkan-tools \
nvtop \
curl \
wget \
timeout

# ------------------------------------------------------------
# Install NVIDIA Driver 535.x
# ------------------------------------------------------------
echo ""
echo "Installing NVIDIA driver 535..."

sudo apt install -y nvidia-driver-535
sudo apt-mark hold nvidia-driver-535

# Verify driver
if ! command -v nvidia-smi &> /dev/null; then
    echo "ERROR: NVIDIA driver not detected"
    exit 1
fi

nvidia-smi

# ------------------------------------------------------------
# Install CUDA 12.2
# ------------------------------------------------------------
CUDA_VERSION="12.2"

echo ""
echo "Installing CUDA $CUDA_VERSION..."

wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update
sudo apt install -y cuda-toolkit-12-2
sudo apt-mark hold cuda-toolkit-12-2

# Set environment variables
echo ""
echo "Configuring CUDA environment variables..."
export CUDA_HOME=/usr/local/cuda-$CUDA_VERSION
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH

# Persist in bashrc for future sessions
grep -qxF "export CUDA_HOME=/usr/local/cuda-$CUDA_VERSION" ~/.bashrc || echo "export CUDA_HOME=/usr/local/cuda-$CUDA_VERSION" >> ~/.bashrc
grep -qxF "export PATH=\$CUDA_HOME/bin:\$PATH" ~/.bashrc || echo "export PATH=\$CUDA_HOME/bin:\$PATH" >> ~/.bashrc
grep -qxF "export LD_LIBRARY_PATH=\$CUDA_HOME/lib64:\$LD_LIBRARY_PATH" ~/.bashrc || echo "export LD_LIBRARY_PATH=\$CUDA_HOME/lib64:\$LD_LIBRARY_PATH" >> ~/.bashrc

# ------------------------------------------------------------
# Keep display on (X session + TTY)
# ------------------------------------------------------------
echo ""
echo "Configuring display to stay on..."

# Disable DPMS and screensaver in X sessions (immediate effect)
if command -v xset &> /dev/null; then
    xset s off
    xset s noblank
    xset -dpms
fi

# Add autostart for GUI sessions
AUTOSTART_DIR="$HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/keep_display_on.desktop" <<EOF
[Desktop Entry]
Type=Application
Exec=bash -c "xset s off; xset s noblank; xset -dpms"
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Keep Display On
Comment=Disable screen blanking and DPMS on startup
EOF

# Disable TTY console blanking (persistent)
if ! grep -q "consoleblank=0" /etc/default/grub; then
    sudo sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 consoleblank=0"/' /etc/default/grub
    sudo update-grub
fi

# ------------------------------------------------------------
# Create directories
# ------------------------------------------------------------
mkdir -p "$SRC_DIR"
mkdir -p "$BIN_DIR"
cd "$SRC_DIR"

# ============================================================
# CUDA Samples (bandwidthTest)
# ============================================================
if [ ! -d "$SRC_DIR/cuda-samples" ]; then
    echo ""
    echo "Cloning CUDA samples..."
    git clone https://github.com/NVIDIA/cuda-samples.git cuda-samples
fi

cd cuda-samples
# Checkout latest compatible tag for CUDA 12.x (optional)
git checkout master

echo "Building bandwidthTest..."
cd Samples/bandwidthTest
make -j"$(nproc)"

# ============================================================
# gpu-burn
# ============================================================
cd "$SRC_DIR"
if [ ! -d "$SRC_DIR/gpu-burn" ]; then
    echo ""
    echo "Cloning gpu-burn..."
    git clone https://github.com/wilicc/gpu-burn.git
fi

cd gpu-burn
make -j"$(nproc)"

# ============================================================
# cuda_memtest
# ============================================================
cd "$SRC_DIR"
if [ ! -d "$SRC_DIR/cuda_memtest" ]; then
    echo ""
    echo "Cloning cuda_memtest..."
    git clone https://github.com/ComputationalRadiationPhysics/cuda_memtest.git
fi

mkdir -p cuda_memtest/build
cd cuda_memtest/build
cmake ..
make -j"$(nproc)"

# ============================================================
# Rust + memtest_vulkan
# ============================================================
if ! command -v cargo &> /dev/null; then
    echo ""
    echo "Installing Rust toolchain..."
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    source "$HOME/.cargo/env"
fi

cd "$SRC_DIR"
if [ ! -d "$SRC_DIR/memtest_vulkan" ]; then
    echo ""
    echo "Cloning memtest_vulkan..."
    git clone https://github.com/GpuZelenograd/memtest_vulkan.git
fi

cd memtest_vulkan
cargo build --release
cp target/release/memtest_vulkan "$BIN_DIR/"

# ============================================================
# Final validation
# ============================================================
echo ""
echo "============================================"
echo "Environment Validation"
echo "============================================"

echo ""
echo "NVIDIA-SMI"
nvidia-smi || true

echo ""
echo "NVCC"
nvcc -V || true

echo ""
echo "Vulkan"
vulkaninfo --summary | head -n 20 || true

echo ""
echo "============================================"
echo "Setup Complete"
echo "============================================"
echo ""
echo "Run validation with:"
echo ""
echo "./scripts/run_gpu_validation.sh"
echo ""
echo "Display will now stay on in GUI and TTY sessions."