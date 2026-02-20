#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# GPU Validation Script (Tech Run) - Single GPU
#
# Tests:
#   A) PCIe bandwidth (cold) via bandwidthTest (H2D/D2H pinned range)
#   B) CUDA core burn-in via gpu-burn (-m N% and -tc)
#   C) PCIe bandwidth (hot) via bandwidthTest (repeat)
#   D) VRAM correctness via cuda_memtest
#   E) Vulkan VRAM correctness/load via memtest_vulkan (timed with timeout -s INT)
#
# Tool intent:
#   - bandwidthTest measures host↔device and device↔device memcpy bandwidth, including PCIe transfers,
#     and supports pinned/pageable memory and range mode. 
#   - gpu-burn is a CUDA stress test; -m N% uses VRAM%, -tc tries tensor cores, TIME is seconds. 
#   - cuda_memtest tests GPU memory for hardware/soft errors using CUDA/OpenCL patterns. 
#   - memtest_vulkan is a Vulkan compute VRAM test; run ≥6 min; stop with Ctrl+C; errors show during run. [3](https://gist.github.com/omerfsen/8ecb620675525ac724a92bdf5a31a4b3)
#   - nvtop is an interactive GPU monitor (run in another terminal). 
# =============================================================================

# ----------------------------
# Auto-detect KIT location
# ----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_KIT="$(cd "$SCRIPT_DIR/.." && pwd)"
KIT="${KIT:-$AUTO_KIT}"

LOG_ROOT="$KIT/logs"
mkdir -p "$LOG_ROOT"

# ----------------------------
# Defaults (can be overridden in prompt)
# ----------------------------
#GPU_BURN_SECONDS_DEFAULT="3600"    # 1 hour meaningful burn-in
GPU_BURN_SECONDS_DEFAULT="120"
VULKAN_SECONDS_DEFAULT="120"
#VULKAN_SECONDS_DEFAULT="1800"      # 30 minutes meaningful; >=360 sec is minimum guidance [3](https://gist.github.com/omerfsen/8ecb620675525ac724a92bdf5a31a4b3)
CUDA_MEMTEST_TIMEOUT_DEFAULT="0"   # 0 = no timeout

# bandwidthTest range: 1MB -> 128MB in 1MB increments
BW_START="1048576"
BW_END="134217728"
BW_INC="1048576"

log() { echo "[$(date +%F_%T)] $*"; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
sanitize_id() { echo "$1" | sed -E 's/[^a-zA-Z0-9_-]+/_/g' | sed -E 's/^_+|_+$//g'; }

need_cmd nvidia-smi
need_cmd nvcc
need_cmd timeout
need_cmd tee
need_cmd sed
need_cmd awk

# ----------------------------
# Dynamic compute capability detection
# ----------------------------
# NVIDIA docs: compute capability can be obtained via nvidia-smi query or cudaDeviceGetAttribute. [1](https://docs.nvidia.com/cuda/cuda-programming-guide/05-appendices/compute-capabilities.html)[2](https://lindevs.com/get-compute-capability-of-nvidia-gpu-using-nvidia-smi)
get_compute_cap_smi() {
  local gpu_index="$1"
  local cc
  cc="$(nvidia-smi -i "$gpu_index" --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ -n "$cc" && "$cc" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "$cc"; return 0
  fi
  cc="$(nvidia-smi -i "$gpu_index" --query-gpu=name,compute_cap --format=csv,noheader 2>/dev/null \
       | awk -F',' '{gsub(/ /,"",$2); print $2}' | head -n1 || true)"
  [[ -n "$cc" ]] && echo "$cc" && return 0
  return 1
}

get_compute_cap_nvcc() {
  local gpu_index="$1"
  local tmpdir
  tmpdir="$(mktemp -d)"
  cat >"$tmpdir/cc.cu" <<'EOF'
#include <cstdio>
#include <cstdlib>
#include <cuda_runtime_api.h>
int main(int argc, char** argv) {
  int dev = 0; if (argc > 1) dev = std::atoi(argv[1]);
  int maj=0, min=0;
  cudaDeviceGetAttribute(&maj, cudaDevAttrComputeCapabilityMajor, dev);
  cudaDeviceGetAttribute(&min, cudaDevAttrComputeCapabilityMinor, dev);
  std::printf("%d.%d\n", maj, min);
  return 0;
}
EOF
  nvcc -O2 "$tmpdir/cc.cu" -o "$tmpdir/cc" >/dev/null 2>&1 || { rm -rf "$tmpdir"; return 1; }
  "$tmpdir/cc" "$gpu_index" 2>/dev/null | head -n1
  rm -rf "$tmpdir"
}

compute_to_gpu_burn_flag() {
  local cc="$1"
  echo "$cc" | awk -F'.' '{maj=$1; min=$2; if(min=="") min=0; printf("%d%d\n", maj, min)}'
}

get_compute_for_gpu_burn() {
  local gpu_index="$1"
  local cc
  if cc="$(get_compute_cap_smi "$gpu_index")"; then
    compute_to_gpu_burn_flag "$cc"; return 0
  fi
  cc="$(get_compute_cap_nvcc "$gpu_index")"
  [[ -n "$cc" ]] && compute_to_gpu_burn_flag "$cc" && return 0
  return 1
}

# ----------------------------
# Prompt inputs
# ----------------------------
echo "============================================================"
echo " GPU Validation - Tech Run"
echo " KIT: $KIT"
echo "============================================================"

read -rp "Enter Run ID (ticket/asset/customer) : " RUN_ID_RAW
RUN_ID_RAW="${RUN_ID_RAW:-}"
[[ -z "$RUN_ID_RAW" ]] && { echo "ERROR: Run ID cannot be empty."; exit 1; }
RUN_ID="$(sanitize_id "$RUN_ID_RAW")"
[[ -z "$RUN_ID" ]] && { echo "ERROR: Run ID sanitized to empty."; exit 1; }

read -rp "GPU index to test (default 0)       : " GPU_INDEX
GPU_INDEX="${GPU_INDEX:-0}"

read -rp "gpu-burn seconds (default ${GPU_BURN_SECONDS_DEFAULT}) : " GPU_BURN_SECONDS
GPU_BURN_SECONDS="${GPU_BURN_SECONDS:-$GPU_BURN_SECONDS_DEFAULT}"

read -rp "memtest_vulkan seconds (default ${VULKAN_SECONDS_DEFAULT}) : " VULKAN_SECONDS
VULKAN_SECONDS="${VULKAN_SECONDS:-$VULKAN_SECONDS_DEFAULT}"

read -rp "cuda_memtest timeout seconds (0 = none, default ${CUDA_MEMTEST_TIMEOUT_DEFAULT}) : " CUDA_MEMTEST_TIMEOUT
CUDA_MEMTEST_TIMEOUT="${CUDA_MEMTEST_TIMEOUT:-$CUDA_MEMTEST_TIMEOUT_DEFAULT}"

TS="$(date +%F_%H%M%S)"
RUN_DIR="$LOG_ROOT/${RUN_ID}_${TS}"
mkdir -p "$RUN_DIR"

SUMMARY_FILE="$RUN_DIR/SUMMARY.txt"
SYSTEM_FILE="$RUN_DIR/SYSTEM_INFO.txt"

log "Run ID: $RUN_ID_RAW (sanitized: $RUN_ID)" | tee -a "$SUMMARY_FILE"
log "Run folder: $RUN_DIR" | tee -a "$SUMMARY_FILE"
log "GPU index: $GPU_INDEX" | tee -a "$SUMMARY_FILE"
log "gpu-burn: ${GPU_BURN_SECONDS}s | memtest_vulkan: ${VULKAN_SECONDS}s | cuda_memtest timeout: ${CUDA_MEMTEST_TIMEOUT}s" | tee -a "$SUMMARY_FILE"

# ----------------------------
# Stop competing processes
# ----------------------------
log "Stopping any existing GPU tests..." | tee -a "$SUMMARY_FILE"
pkill -f cuda_memtest   >/dev/null 2>&1 || true
pkill -f memtest_vulkan >/dev/null 2>&1 || true
pkill -f gpu_burn       >/dev/null 2>&1 || true
pkill -f bandwidthTest  >/dev/null 2>&1 || true

# ----------------------------
# Start dmesg capture
# ----------------------------
log "Starting dmesg capture in background (sudo required)..." | tee -a "$SUMMARY_FILE"
sudo -v
sudo dmesg -wT | tee -a "$RUN_DIR/DMESG_${TS}.log" >/dev/null &
DMESG_PID="$!"
log "dmesg PID: $DMESG_PID" | tee -a "$SUMMARY_FILE"
cleanup() { sudo kill "$DMESG_PID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# ----------------------------
# System snapshot
# ----------------------------
{
  echo "=== RUN START: $TS ==="
  echo "--- OS ---"
  (cat /etc/os-release || true)
  echo "--- NVIDIA-SMI ---"
  nvidia-smi -i "$GPU_INDEX" || true
  echo "--- NVIDIA-SMI (PCIe excerpt) ---"
  nvidia-smi -q -i "$GPU_INDEX" | sed -n '/PCI/,/FB Memory Usage/p' || true
  echo "--- NVCC ---"
  (command -v nvcc && nvcc -V) || true
  echo "--- DATE ---"
  date
} | tee -a "$SYSTEM_FILE"

echo
echo "TIP: In another terminal, run: nvtop  (interactive GPU monitor) "
echo

# ----------------------------
# Paths
# ----------------------------
BW_DIR="$KIT/src/cuda-samples-11x/Samples/bandwidthTest"
BURN_DIR="$KIT/src/gpu-burn"
CUDA_MEMTEST_DIR="$KIT/src/cuda_memtest/build"

VULKAN_BIN=""
[[ -x "$KIT/bin/memtest_vulkan" ]] && VULKAN_BIN="$KIT/bin/memtest_vulkan"
[[ -z "$VULKAN_BIN" && -x "$KIT/src/memtest_vulkan/target/release/memtest_vulkan" ]] && VULKAN_BIN="$KIT/src/memtest_vulkan/target/release/memtest_vulkan"

# ----------------------------
# Ensure binaries exist (build if needed)
# ----------------------------
if [[ ! -x "$BW_DIR/bandwidthTest" ]]; then
  log "bandwidthTest not found. Building with Makefile..." | tee -a "$SUMMARY_FILE"
  need_cmd make
  (cd "$BW_DIR" && make clean && make -j"$(nproc)") | tee -a "$RUN_DIR/build_bandwidthTest_${TS}.log"
fi

if [[ ! -x "$BURN_DIR/gpu_burn" ]]; then
  log "gpu_burn not found. Building with dynamic compute capability..." | tee -a "$SUMMARY_FILE"
  need_cmd make
  COMPUTE="$(get_compute_for_gpu_burn "$GPU_INDEX")" || { echo "ERROR: Cannot determine compute capability."; exit 1; }
  log "gpu-burn COMPUTE target: $COMPUTE (dynamic)" | tee -a "$SUMMARY_FILE"
  (cd "$BURN_DIR" && make clean && make CUDAPATH=/usr COMPUTE="$COMPUTE") | tee -a "$RUN_DIR/build_gpu_burn_${TS}.log"
fi

if [[ ! -x "$CUDA_MEMTEST_DIR/cuda_memtest" ]]; then
  echo "ERROR: cuda_memtest binary not found at: $CUDA_MEMTEST_DIR/cuda_memtest" | tee -a "$SUMMARY_FILE"
  exit 1
fi

if [[ -z "$VULKAN_BIN" ]]; then
  echo "ERROR: memtest_vulkan binary not found in KIT/bin or Rust target/release" | tee -a "$SUMMARY_FILE"
  exit 1
fi

# =============================================================================
# TEST A: PCIe bandwidth (cold)
# =============================================================================
log "TEST A: PCIe bandwidth (cold) - baseline + pinned range" | tee -a "$SUMMARY_FILE"
log "Purpose: Validate host↔device transfer stability/throughput across PCIe (pinned memory)." | tee -a "$SUMMARY_FILE"

(cd "$BW_DIR" && ./bandwidthTest) \
  | tee -a "$RUN_DIR/bandwidthTest_baseline_COLD_${TS}.log"

(cd "$BW_DIR" && ./bandwidthTest --memory=pinned --mode=range --start="$BW_START" --end="$BW_END" --increment="$BW_INC" --htod) \
  | tee -a "$RUN_DIR/bandwidthTest_htod_pinned_COLD_${TS}.log"

(cd "$BW_DIR" && ./bandwidthTest --memory=pinned --mode=range --start="$BW_START" --end="$BW_END" --increment="$BW_INC" --dtoh) \
  | tee -a "$RUN_DIR/bandwidthTest_dtoh_pinned_COLD_${TS}.log"

# =============================================================================
# TEST B: CUDA core burn-in (gpu-burn)
# =============================================================================
log "TEST B: CUDA core burn-in (gpu-burn)" | tee -a "$SUMMARY_FILE"
log "Purpose: Stress CUDA compute under sustained load to expose thermal/power/compute instability." | tee -a "$SUMMARY_FILE"
log "Duration: ${GPU_BURN_SECONDS}s" | tee -a "$SUMMARY_FILE"

(cd "$BURN_DIR" && ./gpu_burn -m 90% -tc "$GPU_BURN_SECONDS") \
  | tee -a "$RUN_DIR/gpu_burn_${GPU_BURN_SECONDS}s_${TS}.log"

# =============================================================================
# TEST C: PCIe bandwidth (hot)
# =============================================================================
log "TEST C: PCIe bandwidth (hot) - baseline + pinned range" | tee -a "$SUMMARY_FILE"
log "Purpose: Compare PCIe transfer stability after heat soak (cold vs hot)." | tee -a "$SUMMARY_FILE"

(cd "$BW_DIR" && ./bandwidthTest) \
  | tee -a "$RUN_DIR/bandwidthTest_baseline_HOT_${TS}.log"

(cd "$BW_DIR" && ./bandwidthTest --memory=pinned --mode=range --start="$BW_START" --end="$BW_END" --increment="$BW_INC" --htod) \
  | tee -a "$RUN_DIR/bandwidthTest_htod_pinned_HOT_${TS}.log"

(cd "$BW_DIR" && ./bandwidthTest --memory=pinned --mode=range --start="$BW_START" --end="$BW_END" --increment="$BW_INC" --dtoh) \
  | tee -a "$RUN_DIR/bandwidthTest_dtoh_pinned_HOT_${TS}.log"

# =============================================================================
# TEST D: VRAM correctness (cuda_memtest)  <-- FIXED timeout logic
# =============================================================================
log "TEST D: VRAM correctness (cuda_memtest)" | tee -a "$SUMMARY_FILE"
log "Purpose: Detect VRAM errors/silent corruption using CUDA/OpenCL memory test patterns." | tee -a "$SUMMARY_FILE"

if [[ "$CUDA_MEMTEST_TIMEOUT" != "0" ]]; then
  timeout "$CUDA_MEMTEST_TIMEOUT" bash -lc "cd '$CUDA_MEMTEST_DIR' && ./cuda_memtest" \
    | tee -a "$RUN_DIR/cuda_memtest_${TS}.log" || true
else
  (cd "$CUDA_MEMTEST_DIR" && ./cuda_memtest) \
    | tee -a "$RUN_DIR/cuda_memtest_${TS}.log"
fi

# =============================================================================
# TEST E: Vulkan VRAM test (memtest_vulkan) - timed Ctrl+C emulation
# =============================================================================
log "TEST E: Vulkan VRAM test (memtest_vulkan)" | tee -a "$SUMMARY_FILE"
log "Purpose: Cross-check VRAM stability/correctness using Vulkan compute path." | tee -a "$SUMMARY_FILE"
log "Duration: ${VULKAN_SECONDS}s (minimum recommended >= 360s / ~6 min)" | tee -a "$SUMMARY_FILE"

timeout -s INT "$VULKAN_SECONDS" "$VULKAN_BIN" \
  | tee -a "$RUN_DIR/memtest_vulkan_${VULKAN_SECONDS}s_${TS}.log" || true

# =============================================================================
# SUMMARY (PASS/FAIL)
# =============================================================================
log "Generating PASS/FAIL summary..." | tee -a "$SUMMARY_FILE"

DMESG_LOG="$RUN_DIR/DMESG_${TS}.log"
VULKAN_LOG="$RUN_DIR/memtest_vulkan_${VULKAN_SECONDS}s_${TS}.log"
MEMTEST_LOG="$RUN_DIR/cuda_memtest_${TS}.log"
BURN_LOG="$RUN_DIR/gpu_burn_${GPU_BURN_SECONDS}s_${TS}.log"
BW_COLD="$RUN_DIR/bandwidthTest_baseline_COLD_${TS}.log"
BW_HOT="$RUN_DIR/bandwidthTest_baseline_HOT_${TS}.log"

FAIL_COUNT=0

echo "" | tee -a "$SUMMARY_FILE"
echo "==================== SUMMARY CHECKS ====================" | tee -a "$SUMMARY_FILE"

# Hard-fail patterns in dmesg
if grep -Eai '(NVRM|Xid|XID|AER:|pcie.*error|GPU has fallen off the bus)' "$DMESG_LOG" >/dev/null 2>&1; then
  echo "[FAIL] dmesg shows driver/PCIe errors (Xid/NVRM/AER)." | tee -a "$SUMMARY_FILE"
  grep -Eai '(NVRM|Xid|XID|AER:|pcie.*error|GPU has fallen off the bus)' "$DMESG_LOG" | tail -n 30 | tee -a "$SUMMARY_FILE"
  FAIL_COUNT=$((FAIL_COUNT+1))
else
  echo "[OK] dmesg: no common driver/PCIe error patterns detected." | tee -a "$SUMMARY_FILE"
fi

# bandwidthTest should include "Result = PASS"
if grep -q "Result = PASS" "$BW_COLD" && grep -q "Result = PASS" "$BW_HOT"; then
  echo "[OK] bandwidthTest: Result = PASS (cold and hot baseline)." | tee -a "$SUMMARY_FILE"
else
  echo "[FAIL] bandwidthTest: missing 'Result = PASS' in cold/hot baseline logs." | tee -a "$SUMMARY_FILE"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi

# gpu-burn should end with GPU 0: OK
if grep -q "GPU 0: OK" "$BURN_LOG"; then
  echo "[OK] gpu-burn: GPU 0: OK" | tee -a "$SUMMARY_FILE"
else
  echo "[FAIL] gpu-burn: missing 'GPU 0: OK' in log (review log)." | tee -a "$SUMMARY_FILE"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi

# memtest_vulkan hard-fail if it reports "Error found" or device lost
if grep -Eai '(Error found|ERROR_DEVICE_LOST|early exit|ERROR_)' "$VULKAN_LOG" >/dev/null 2>&1; then
  echo "[FAIL] memtest_vulkan reported errors/device loss." | tee -a "$SUMMARY_FILE"
  grep -Eai '(Error found|ERROR_DEVICE_LOST|early exit|ERROR_)' "$VULKAN_LOG" | tail -n 30 | tee -a "$SUMMARY_FILE"
  FAIL_COUNT=$((FAIL_COUNT+1))
else
  echo "[OK] memtest_vulkan: no error patterns detected." | tee -a "$SUMMARY_FILE"
fi

# cuda_memtest: flag if it prints obvious errors
if grep -Eai '(FAIL|error|mismatch)' "$MEMTEST_LOG" >/dev/null 2>&1; then
  echo "[REVIEW] cuda_memtest: found error-like strings; review log for true errors." | tee -a "$SUMMARY_FILE"
  grep -Eai '(FAIL|error|mismatch)' "$MEMTEST_LOG" | tail -n 30 | tee -a "$SUMMARY_FILE"
else
  echo "[OK] cuda_memtest: no obvious error strings detected." | tee -a "$SUMMARY_FILE"
fi

echo "" | tee -a "$SUMMARY_FILE"
echo "==================== FINAL RESULT ====================" | tee -a "$SUMMARY_FILE"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo "RESULT: FAIL (see checks above). Run folder: $RUN_DIR" | tee -a "$SUMMARY_FILE"
  exit 2
else
  echo "RESULT: PASS (no critical failures detected). Run folder: $RUN_DIR" | tee -a "$SUMMARY_FILE"
  exit 0
fi