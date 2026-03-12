#!/usr/bin/env bash

set -e

# ============================================================
# GPU Validation Kit - Environment Setup
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
timeout \
nvidia-cuda-toolkit

# ------------------------------------------------------------
# Verify GPU driver
# ------------------------------------------------------------
echo ""
echo "Checking NVIDIA driver..."

if ! command -v nvidia-smi &> /dev/null; then
    echo "ERROR: NVIDIA driver not detected"
    exit 1
fi

nvidia-smi || true

# ------------------------------------------------------------
# Verify nvcc
# ------------------------------------------------------------
echo ""
echo "Checking CUDA compiler..."

if command -v nvcc &> /dev/null; then
    nvcc -V
else
    echo "WARNING: nvcc not found"
fi

# ------------------------------------------------------------
# Verify Vulkan
# ------------------------------------------------------------
echo ""
echo "Checking Vulkan..."

if command -v vulkaninfo &> /dev/null; then
    vulkaninfo --summary | head -n 20
else
    echo "WARNING: Vulkan tools missing"
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

if [ ! -d "$SRC_DIR/cuda-samples-11x" ]; then
    echo ""
    echo "Cloning CUDA samples..."
    git clone https://github.com/NVIDIA/cuda-samples.git cuda-samples-11x
fi

cd cuda-samples-11x
git checkout v11.5

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
make

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