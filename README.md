# GPU Validation Kit

Automated validation framework for NVIDIA GPUs on Linux. This repository provides an orchestrated set of tests that exercise PCIe transfers, CUDA compute stability, VRAM correctness (CUDA + Vulkan), and kernel/driver health. Each run produces structured logs and a clear PASS/FAIL summary suitable for hardware qualification and technician workflows.

---

## Table of Contents
- [Overview](#overview)
- [Validated Environment](#validated-environment)
- [Tested Hardware](#tested-hardware)
- [Tools & Test Coverage](#tools--test-coverage)
- [Quick Start](#quick-start)
- [Verify Environment](#verify-environment)
- [Running Validation](#running-validation)
- [Output & Logs](#output--logs)
- [How to Run Tests Independently](#how-to-run-tests-independently)
- [Monitoring & Troubleshooting](#monitoring--troubleshooting)
- [Technician Workflow](#technician-workflow)
- [Future Improvements](#future-improvements)
- [Maintainer & License](#maintainer--license)

---

## Overview
This toolkit orchestrates multiple GPU stress and integrity tests to detect transfer/path errors, compute instability, and VRAM corruption across API stacks. It is designed for deterministic test ordering, reproducible logs, and concise PASS/FAIL summaries.

## Validated Environment
- OS: Ubuntu 22.04.5 LTS (Jammy Jellyfish)
- NVIDIA Driver: 535.288.01 (reports CUDA Version: 12.2)
- CUDA Toolkit (nvcc): CUDA 11.5.119 (installed from OS packages: `/usr/bin/nvcc`)

Note: It is normal for `nvidia-smi` to report a newer "CUDA Version" than `nvcc -V`. The driver reports capability; `nvcc` reports the installed compiler/toolkit.

### Example `nvidia-smi` output (abridged)
```
NVIDIA-SMI 535.288.01  Driver Version: 535.288.01   CUDA Version: 12.2
GPU 0  Quadro RTX 6000  227MiB / 24576MiB
Processes: Xorg, xfwm4
```

## Tested Hardware
- NVIDIA Quadro RTX 6000 (Turing)
- Previously validated on Quadro RTX 8000

## Tools & Test Coverage
The repo uses multiple tools, each targeting a failure domain:

- PCIe / Transfer Path: `bandwidthTest`
	- Tests host↔device and device↔device transfer bandwidth (pinned vs pageable).
	- Runs cold baseline and hot (after burn-in) sweeps.

- CUDA Core Burn-in / Stability: `gpu-burn`
	- Sustained compute load to exercise thermal/power stability and correctness.
	- Typical run: `-m 90%` (reserve ~90% VRAM), `-tc` (try Tensor Cores), configurable time (default 3600s).

- VRAM Correctness (CUDA): `cuda_memtest`
	- Memory test patterns via CUDA/OpenCL to detect silent corruption.

- VRAM Correctness (Vulkan): `memtest_vulkan`
	- Cross-API VRAM checks through Vulkan compute to surface driver/ICD edge cases.
	- Recommended run: ~6 minutes; script uses `timeout -s INT` to emulate Ctrl+C.

Monitoring: kernel messages via `dmesg -wT` and optional live monitoring with `nvtop`.

## Quick Start
Install prerequisites, clone the repo, and build tools.

1) Enable multiverse and install base deps

```bash
sudo add-apt-repository -y multiverse
sudo apt update && sudo apt upgrade -y
sudo apt install -y git build-essential cmake pkg-config libvulkan1 vulkan-tools nvtop timeout curl
```

2) Install CUDA compiler (optional from Ubuntu repo)

```bash
sudo apt install -y nvidia-cuda-toolkit
which nvcc && nvcc -V
```

3) Clone repository

```bash
cd ~
git clone https://github.com/rg-amazinxpress/gpu-validation-kit.git
cd gpu-validation-kit
```

4) Build example tools

- CUDA Samples (legacy tag for CUDA 11.5 - contains `bandwidthTest`)

```bash
mkdir -p src && cd src
git clone https://github.com/NVIDIA/cuda-samples.git cuda-samples-11x
cd cuda-samples-11x
git checkout v11.5
cd Samples/bandwidthTest
make -j"$(nproc)"
```

- gpu-burn

```bash
cd ~/gpu-validation-kit/src
git clone https://github.com/wilicc/gpu-burn.git
cd gpu-burn && make
```

- cuda_memtest

```bash
cd ~/gpu-validation-kit/src
git clone https://github.com/ComputationalRadiationPhysics/cuda_memtest.git
mkdir -p cuda_memtest/build && cd cuda_memtest/build
cmake .. && make -j"$(nproc)"
```

- memtest_vulkan (Rust)

```bash
curl https://sh.rustup.rs -sSf | sh
source ~/.cargo/env
cd ~/gpu-validation-kit/src
git clone https://github.com/GpuZelenograd/memtest_vulkan.git
cd memtest_vulkan && cargo build --release
mkdir -p ~/gpu-validation-kit/bin
cp target/release/memtest_vulkan ~/gpu-validation-kit/bin/
```

## Verify Environment
Run these before executing the validation script:

```bash
nvidia-smi
nvcc -V
vulkaninfo --summary
```

Optional: `nvtop` for live monitoring of utilization, thermals, and VRAM.

## Running Validation
Make the orchestrator script executable and run it interactively:

```bash
chmod +x scripts/run_gpu_validation.sh
./scripts/run_gpu_validation.sh
```

The script will prompt for a `Run ID`, GPU index, and test durations. Each run writes a dedicated log folder under `logs/`.

## Output & Logs
Each run creates:

```
logs/<RUN_ID>_<YYYY-MM-DD_HHMMSS>/
```

Typical files:
- `SYSTEM_INFO.txt` (OS, driver, toolkit)
- `DMESG_<timestamp>.log` (kernel messages captured during run)
- `bandwidthTest_*_COLD_*.log`, `bandwidthTest_*_HOT_*.log`
- `gpu_burn_*.log`
- `cuda_memtest_*.log`
- `memtest_vulkan_*.log`
- `SUMMARY.txt` (final PASS/FAIL and review items)

Open `SUMMARY.txt` to see `RESULT: PASS` or `RESULT: FAIL` and review notes.

## How to Run Tests Independently

### PCIe bandwidth test (bandwidthTest)

```bash
cd ~/gpu-validation-kit/src/cuda-samples-11x/Samples/bandwidthTest
./bandwidthTest --memory=pinned --mode=range --start=1048576 --end=134217728 --increment=1048576 --htod
./bandwidthTest --memory=pinned --mode=range --start=1048576 --end=134217728 --increment=1048576 --dtoh
```

### GPU-BURN

```bash
cd ~/gpu-validation-kit/src/gpu-burn
./gpu_burn -m 90% -tc 300
```

### Vulkan memtest

```bash
~/gpu-validation-kit/bin/memtest_vulkan
# Press Ctrl+C to stop or run under timeout
```

## Monitoring & Troubleshooting

Capture kernel messages and watch for driver/GPU errors:

```bash
dmesg -wT | tee DMESG_<timestamp>.log
```

Common failure signals in logs:

- Driver / Hardware Faults: `NVRM: Xid`, `GPU has fallen off the bus`
- PCIe Errors: `PCIe Bus Error`, `AER: Corrected`, `AER: Uncorrected`
- Vulkan Device Loss: `VK_ERROR_DEVICE_LOST`

If build or permission issues occur:

```bash
# Ensure CUDA samples are the v11.5 tag for compatibility with nvcc 11.5
sudo chown -R $USER:$USER logs
```

Notes on CUDA samples compatibility:
Modern `cuda-samples` main branches may target newer CUDA toolkits (e.g., 13.x). Use the legacy `cuda-samples-11x` tag `v11.5` for compatibility with CUDA 11.x environments.

## Technician Workflow
1. Prepare system (Ubuntu + drivers + toolchain)
2. Clone repo and build required tools
3. Run `./scripts/run_gpu_validation.sh` and monitor via `nvtop` and `dmesg`
4. Collect logs from `logs/<RUN_ID>_<timestamp>/` and review `SUMMARY.txt`

Typical runtime: 15–30 minutes (depends on configured durations).

## Future Improvements
- HTML report generation
- Grafana metrics export
- Multi-GPU parallel testing
- Burn-in automation and manufacturing mode

## Maintainer & License
Maintained by the hardware validation team. Internal validation tool — usage subject to organizational policy.
- PCIe Errors: `PCIe Bus Error`, `AER: Corrected`, `AER: Uncorrected`
- Vulkan Device Loss: `VK_ERROR_DEVICE_LOST`

If build or permission issues occur:

```bash
# Ensure CUDA samples are the v11.5 tag for compatibility with nvcc 11.5
sudo chown -R $USER:$USER logs
```

Notes on CUDA samples compatibility:
Modern `cuda-samples` main branches may target newer CUDA toolkits (e.g., 13.x). Use the legacy `cuda-samples-11x` tag `v11.5` for compatibility with CUDA 11.x environments.

## Technician Workflow
1. Prepare system (Ubuntu + drivers + toolchain)
2. Clone repo and build required tools
3. Run `./scripts/run_gpu_validation.sh` and monitor via `nvtop` and `dmesg`
4. Collect logs from `logs/<RUN_ID>_<timestamp>/` and review `SUMMARY.txt`

Typical runtime: 15–30 minutes (depends on configured durations).

## Future Improvements
- HTML report generation
- Grafana metrics export
- Multi-GPU parallel testing
- Burn-in automation and manufacturing mode

## Maintainer & License
Maintained by the hardware validation team. Internal validation tool — usage subject to organizational policy.