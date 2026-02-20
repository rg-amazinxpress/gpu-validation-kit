#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# GPU Validation Script (Single GPU) - Tech Runbook
#
# Prompts for:
#   - Run ID (used to create per-run log folder)
#   - Optional GPU index (default 0)
#
# Tests:
#   A) PCIe bandwidth (cold) via bandwidthTest (H2D/D2H pinned range)
#   B) CUDA core burn-in via gpu-burn (-m N% and -tc)
#   C) PCIe bandwidth (hot) via bandwidthTest (repeat for comparison)
#   D) VRAM correctness via cuda_memtest
#   E) Vulkan VRAM test via memtest_vulkan (timed via timeout -s INT)
#
# Summary:
#   - Greps logs for common failure patterns (Xid/NVRM/AER, "Error found", etc.)
#   - Prints PASS/FAIL and writes SUMMARY.txt
# 
# Notes:
#   - nvtop is interactive; run it in a separate terminal if available.
# =============================================================================

# ----------------------------
# CONFIG (edit if needed)
# ----------------------------

# Resolve script path even if symlinked
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
AUTO_KIT="$(cd "$SCRIPT_DIR/.." && pwd)"

KIT="${KIT:-$AUTO_KIT}"

# Validate kit structure early
if [[ ! -d "$KIT/src" ]]; then
  echo "ERROR: KIT path invalid: $KIT"
  echo "Expected structure: KIT/src, KIT/bin, KIT/scripts"
  exit 1
fi

# Times (seconds) - recommended defaults
GPU_BURN_SECONDS_DEFAULT="3600"   # 60 min (meaningful burn-in)
VULKAN_SECONDS_DEFAULT="1800"     # 30 min (meaningful Vulkan VRAM run); minimum recommended is >= 360s (~6 min)
CUDA_MEMTEST_TIMEOUT_DEFAULT="0"  # 0 = no timeout

# bandwidthTest range settings (1MB -> 128MB in 1MB increments)
BW_START="1048576"
BW_END="134217728"
BW_INC="1048576"

# ----------------------------
# Helpers
# ----------------------------
log() { echo "[$(date +%F_%T)] $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing required command: $1"; exit 1; }
}

sanitize_id() {
  # keep only alnum, underscore, dash; convert others to underscore
  echo "$1" | sed -E 's/[^a-zA-Z0-9_-]+/_/g' | sed -E 's/^_+|_+$//g'
}

# --- Dynamic compute capability detection -----------------------------------
# Returns compute capability as "M.m" (e.g., "7.5", "8.6") using nvidia-smi if possible.
# NVIDIA docs say nvidia-smi can query compute capability with --query-gpu=name,compute_cap. [1](https://docs.nvidia.com/cuda/cuda-programming-guide/05-appendices/compute-capabilities.html)[2](https://lindevs.com/get-compute-capability-of-nvidia-gpu-using-nvidia-smi)
get_compute_cap_smi() {
  local gpu_index="$1"
  # Try with and without "name," in case some builds differ
  local cc
  cc="$(nvidia-smi -i "$gpu_index" --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ -n "$cc" && "$cc" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "$cc"
    return 0
  fi

  cc="$(nvidia-smi -i "$gpu_index" --query-gpu=name,compute_cap --format=csv,noheader 2>/dev/null \
        | awk -F',' '{gsub(/ /,"",$2); print $2}' | head -n1 || true)"
  if [[ -n "$cc" && "$cc" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "$cc"
    return 0
  fi

  return 1
}

# Fallback: compile and run a tiny CUDA program to print CC as "M.m".
# NVIDIA docs show compute capability can be obtained via cudaDeviceGetAttribute(). [1](https://docs.nvidia.com/cuda/cuda-programming-guide/05-appendices/compute-capabilities.html)
get_compute_cap_nvcc() {
  local gpu_index="$1"
  local tmpdir
  tmpdir="$(mktemp -d)"
  cat >"$tmpdir/cc.cu" <<'EOF'
#include <cstdio>
#include <cuda_runtime_api.h>

int main(int argc, char** argv) {
    int dev = 0;
    if (argc > 1) dev = atoi(argv[1]);

    int maj=0, min=0;
    cudaDeviceGetAttribute(&maj, cudaDevAttrComputeCapabilityMajor, dev);
    cudaDeviceGetAttribute(&min, cudaDevAttrComputeCapabilityMinor, dev);
    printf("%d.%d\n", maj, min);
    return 0;
}
EOF

  nvcc -O2 "$tmpdir/cc.cu" -o "$tmpdir/cc" >/dev/null 2>&1 || { rm -rf "$tmpdir"; return 1; }
  "$tmpdir/cc" "$gpu_index" 2>/dev/null | head -n1
  rm -rf "$tmpdir"
}

# Convert "M.m" to gpu-burn COMPUTE format "Mm" (e.g., 7.5 -> 75, 8.6 -> 86).
compute_to_gpu_burn_flag() {
  local cc="$1"
  # Normalize (7.5 -> 75, 8.0 -> 80)
  echo "$cc" | awk -F'.' '{maj=$1; min=$2; if(min=="") min=0; printf("%d%d\n", maj, min)}'
}

# One function to rule them all: prefer nvidia-smi, fallback to nvcc.
get_compute_for_gpu_burn() {
  local gpu_index="$1"
  local cc
  if cc="$(get_compute_cap_smi "$gpu_index")"; then
    compute_to_gpu_burn_flag "$cc"
    return 0
  fi

  cc="$(get_compute_cap_nvcc "$gpu_index")"
  if [[ -n "$cc" ]]; then
    compute_to_gpu_burn_flag "$cc"
    return 0
  fi

  return 1
}

# ----------------------------
# Preflight commands
# ----------------------------
need_cmd tee
need_cmd sed
need_cmd awk
need_cmd timeout
need_cmd nvidia-smi

# Optional but recommended (won't fail script if missing)
HAVE_NVTOTIP="1"
command -v nvtop >/dev/null 2>&1 || HAVE_NVTOTIP="0"

# ----------------------------
# Prompt user for Run ID
# ----------------------------
echo "============================================================"
echo " GPU Validation - Tech Run"
echo "============================================================"
read -rp "Enter Run ID (ticket/asset/customer) : " RUN_ID_RAW
RUN_ID_RAW="${RUN_ID_RAW:-}"
if [[ -z "$RUN_ID_RAW" ]]; then
  echo "ERROR: Run ID cannot be empty."
  exit 1
fi

RUN_ID="$(sanitize_id "$RUN_ID_RAW")"
if [[ -z "$RUN_ID" ]]; then
  echo "ERROR: Run ID sanitized to empty. Use letters/numbers/_/-"
  exit 1
fi

read -rp "GPU index to test (default 0)       : " GPU_INDEX
GPU_INDEX="${GPU_INDEX:-0}"

read -rp "gpu-burn seconds (default ${GPU_BURN_SECONDS_DEFAULT}) : " GPU_BURN_SECONDS
GPU_BURN_SECONDS="${GPU_BURN_SECONDS:-$GPU_BURN_SECONDS_DEFAULT}"

read -rp "memtest_vulkan seconds (default ${VULKAN_SECONDS_DEFAULT}) : " VULKAN_SECONDS
VULKAN_SECONDS="${VULKAN_SECONDS:-$VULKAN_SECONDS_DEFAULT}"

read -rp "cuda_memtest timeout seconds (0 = none, default ${CUDA_MEMTEST_TIMEOUT_DEFAULT}) : " CUDA_MEMTEST_TIMEOUT
CUDA_MEMTEST_TIMEOUT="${CUDA_MEMTEST_TIMEOUT:-$CUDA_MEMTEST_TIMEOUT_DEFAULT}"

TS="$(date +%F_%H%M%S)"
LOG_ROOT="$KIT/logs"
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
# Start dmesg capture (background)
# ----------------------------
log "Starting dmesg capture in background (sudo required)..." | tee -a "$SUMMARY_FILE"
sudo -v
sudo dmesg -wT | tee -a "$RUN_DIR/DMESG_${TS}.log" >/dev/null &
DMESG_PID="$!"
log "dmesg PID: $DMESG_PID" | tee -a "$SUMMARY_FILE"

cleanup() {
  if [[ -n "${DMESG_PID:-}" ]]; then
    sudo kill "$DMESG_PID" >/dev/null 2>&1 || true
  fi
}
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
  nvidia-smi -i "$GPU_INDEX" -q 2>/dev/null | \
  awk '/PCI/{flag=1} /FB Memory Usage/{print; flag=0} flag'
  echo "--- NVCC ---"
  (command -v nvcc && nvcc -V) || echo "nvcc not found"
  echo "--- DATE ---"
  date
} | tee -a "$SYSTEM_FILE"

if [[ "$HAVE_NVTOTIP" == "1" ]]; then
  echo
  echo "TIP: In another terminal, run: nvtop  (interactive GPU monitor)"
  echo
fi

# ----------------------------
# Paths
# ----------------------------
BW_DIR="$KIT/src/cuda-samples-11x/Samples/bandwidthTest"
BURN_DIR="$KIT/src/gpu-burn"
CUDA_MEMTEST_DIR="$KIT/src/cuda_memtest/build"

VULKAN_BIN=""
if [[ -x "$KIT/bin/memtest_vulkan" ]]; then
  VULKAN_BIN="$KIT/bin/memtest_vulkan"
elif [[ -x "$KIT/src/memtest_vulkan/target/release/memtest_vulkan" ]]; then
  VULKAN_BIN="$KIT/src/memtest_vulkan/target/release/memtest_vulkan"
fi

# ----------------------------
# Helper: Build bandwidthTest if missing
# ----------------------------
if [[ ! -x "$BW_DIR/bandwidthTest" ]]; then
  log "bandwidthTest binary not found. Attempting build with Makefile..." | tee -a "$SUMMARY_FILE"
  need_cmd make
  (cd "$BW_DIR" && make clean && make -j"$(nproc)") | tee -a "$RUN_DIR/build_bandwidthTest_${TS}.log"
fi

# Helper: Build gpu-burn if missing
if [[ ! -x "$BURN_DIR/gpu_burn" ]]; then
  log "gpu_burn not found; building..."

  need_cmd make
  need_cmd nvcc

  COMPUTE="$(get_compute_for_gpu_burn "$GPU_INDEX")" || {
    echo "ERROR: Could not determine GPU compute capability via nvidia-smi or nvcc fallback."
    exit 1
  }

  log "Detected compute target for gpu-burn: COMPUTE=$COMPUTE (from GPU index $GPU_INDEX)"
  (cd "$BURN_DIR" && make clean && make CUDAPATH=/usr COMPUTE="$COMPUTE") \
    | tee -a "$RUN_DIR/build_gpu_burn_${TS}.log"
fi

# ----------------------------
# TEST A: PCIe baseline (cold)
# ----------------------------
log "TEST A: PCIe bandwidth (cold) - baseline + pinned range" | tee -a "$SUMMARY_FILE"
log "Purpose: Validate host↔device transfer stability/throughput across PCIe and pinned memory behavior." | tee -a "$SUMMARY_FILE"

(cd "$BW_DIR" && ./bandwidthTest) \
  | tee -a "$RUN_DIR/bandwidthTest_baseline_COLD_${TS}.log"

(cd "$BW_DIR" && ./bandwidthTest --memory=pinned --mode=range --start="$BW_START" --end="$BW_END" --increment="$BW_INC" --htod) \
  | tee -a "$RUN_DIR/bandwidthTest_htod_pinned_COLD_${TS}.log"

(cd "$BW_DIR" && ./bandwidthTest --memory=pinned --mode=range --start="$BW_START" --end="$BW_END" --increment="$BW_INC" --dtoh) \
  | tee -a "$RUN_DIR/bandwidthTest_dtoh_pinned_COLD_${TS}.log"

# ----------------------------
# TEST B: CUDA core burn-in
# ----------------------------
log "TEST B: CUDA core burn-in (gpu-burn)" | tee -a "$SUMMARY_FILE"
log "Purpose: Stress CUDA compute under sustained load to expose thermal/power/compute instability." | tee -a "$SUMMARY_FILE"
log "Duration: ${GPU_BURN_SECONDS}s" | tee -a "$SUMMARY_FILE"

(cd "$BURN_DIR" && ./gpu_burn -m 90% -tc "$GPU_BURN_SECONDS") \
  | tee -a "$RUN_DIR/gpu_burn_${GPU_BURN_SECONDS}s_${TS}.log"

# ----------------------------
# TEST C: PCIe re-check (hot)
# ----------------------------
log "TEST C: PCIe bandwidth (hot) - baseline + pinned range" | tee -a "$SUMMARY_FILE"
log "Purpose: Compare PCIe transfer stability after heat soak (cold vs hot)." | tee -a "$SUMMARY_FILE"

(cd "$BW_DIR" && ./bandwidthTest) \
  | tee -a "$RUN_DIR/bandwidthTest_baseline_HOT_${TS}.log"

(cd "$BW_DIR" && ./bandwidthTest --memory=pinned --mode=range --start="$BW_START" --end="$BW_END" --increment="$BW_INC" --htod) \
  | tee -a "$RUN_DIR/bandwidthTest_htod_pinned_HOT_${TS}.log"

(cd "$BW_DIR" && ./bandwidthTest --memory=pinned --mode=range --start="$BW_START" --end="$BW_END" --increment="$BW_INC" --dtoh) \
  | tee -a "$RUN_DIR/bandwidthTest_dtoh_pinned_HOT_${TS}.log"

# ----------------------------
# TEST D: VRAM correctness (cuda_memtest)
# ----------------------------
log "TEST D: VRAM correctness (cuda_memtest)" | tee -a "$SUMMARY_FILE"
log "Purpose: Detect VRAM errors/silent corruption using CUDA/OpenCL memory patterns." | tee -a "$SUMMARY_FILE"

if [[ ! -x "$CUDA_MEMTEST_DIR/cuda_memtest" ]]; then
  log "cuda_memtest binary not found at $CUDA_MEMTEST_DIR/cuda_memtest" | tee -a "$SUMMARY_FILE"
  exit 1
fi

if [[ "$CUDA_MEMTEST_TIMEOUT" != "0" ]]; then
  (
    cd "$CUDA_MEMTEST_DIR"
    timeout "$CUDA_MEMTEST_TIMEOUT" ./cuda_memtest
  ) | tee -a "$RUN_DIR/cuda_memtest_${TS}.log" || true
else
  (
    cd "$CUDA_MEMTEST_DIR"
    ./cuda_memtest
  ) | tee -a "$RUN_DIR/cuda_memtest_${TS}.log"
fi

# ----------------------------
# TEST E: Vulkan VRAM test (memtest_vulkan)
# ----------------------------
log "TEST E: Vulkan VRAM test (memtest_vulkan)" | tee -a "$SUMMARY_FILE"
log "Purpose: Cross-check VRAM stability/correctness through Vulkan compute path; timed run." | tee -a "$SUMMARY_FILE"
log "Duration: ${VULKAN_SECONDS}s (minimum recommended ~6 minutes)" | tee -a "$SUMMARY_FILE"

if [[ -z "$VULKAN_BIN" ]]; then
  log "ERROR: memtest_vulkan binary not found in $KIT/bin or Rust target/release." | tee -a "$SUMMARY_FILE"
  exit 1
fi

# Use timeout -s INT to emulate Ctrl+C after duration
timeout -s INT "$VULKAN_SECONDS" "$VULKAN_BIN" \
  | tee -a "$RUN_DIR/memtest_vulkan_${VULKAN_SECONDS}s_${TS}.log" || true

# =============================================================================
# SUMMARY / PASS-FAIL
# =============================================================================
log "Generating PASS/FAIL summary..." | tee -a "$SUMMARY_FILE"

LC_ALL=C   # deterministic grep behavior

# ================== STRICT FAILURE PATTERNS ==================

# ----- NVIDIA SCOPING (Stage 1 Filter) -----
# Only process lines clearly tied to NVIDIA
NVIDIA_SCOPE_PATTERN='(NVRM:|nvidia|NVIDIA)'

# ----- Real NVIDIA GPU / PCIe faults (Stage 2 Filter) -----
FAIL_PATTERNS_DMESG='(NVRM: Xid [0-9]+|NVRM: GPU .* has fallen off the bus|GPU has fallen off the bus|nvidia.*Xid [0-9]+|AER:.*(Uncorrected|Fatal).*nvidia|nvidia.*PCIe.*(error|fault|fatal))'

# memtest_vulkan: explicit device loss or Vulkan failures only
FAIL_PATTERNS_VULKAN='(ERROR_DEVICE_LOST|VkResult: -[1-9][0-9]*|Error found|early exit|FAILED)'

# cuda_memtest: only real failures (avoid lowercase "error")
FAIL_PATTERNS_MEMTEST='(FAIL\b|Mismatch|Data mismatch|CUDA error|ERROR SUMMARY: [1-9])'

# gpu_burn: avoid matching "errors: 0"
FAIL_PATTERNS_BURN='(FAILURE|mismatch|CUDA error|FAULT)'

DMESG_LOG="$RUN_DIR/DMESG_${TS}.log"
VULKAN_LOG="$RUN_DIR/memtest_vulkan_${VULKAN_SECONDS}s_${TS}.log"
MEMTEST_LOG="$RUN_DIR/cuda_memtest_${TS}.log"
BURN_LOG="$RUN_DIR/gpu_burn_${GPU_BURN_SECONDS}s_${TS}.log"

FAIL_COUNT=0

echo "" | tee -a "$SUMMARY_FILE"
echo "==================== SUMMARY CHECKS ====================" | tee -a "$SUMMARY_FILE"

# =============================================================================
# DMESG (Two-stage filtering for NVIDIA accuracy)
# =============================================================================
if [[ -s "$DMESG_LOG" ]]; then

  # Stage 1: isolate NVIDIA-related lines only
  NVIDIA_LINES=$(grep -Eai "$NVIDIA_SCOPE_PATTERN" "$DMESG_LOG")

  if [[ -n "$NVIDIA_LINES" ]] && echo "$NVIDIA_LINES" | grep -Eai "$FAIL_PATTERNS_DMESG" >/dev/null; then
    echo "[FAIL] dmesg contains confirmed NVIDIA GPU/PCIe fault signatures." | tee -a "$SUMMARY_FILE"
    echo "$NVIDIA_LINES" | grep -Eai "$FAIL_PATTERNS_DMESG" | tail -n 20 | tee -a "$SUMMARY_FILE"
    FAIL_COUNT=$((FAIL_COUNT+1))
  else
    echo "[OK] dmesg: no confirmed NVIDIA GPU/PCIe fault events detected." | tee -a "$SUMMARY_FILE"
  fi

else
  echo "[WARN] dmesg log missing or empty." | tee -a "$SUMMARY_FILE"
fi

# =============================================================================
# memtest_vulkan
# =============================================================================
if [[ -s "$VULKAN_LOG" ]]; then
  if grep -Eai "$FAIL_PATTERNS_VULKAN" "$VULKAN_LOG" >/dev/null; then
    echo "[FAIL] memtest_vulkan reported device loss or Vulkan errors." | tee -a "$SUMMARY_FILE"
    grep -Eai "$FAIL_PATTERNS_VULKAN" "$VULKAN_LOG" | tail -n 20 | tee -a "$SUMMARY_FILE"
    FAIL_COUNT=$((FAIL_COUNT+1))
  else
    echo "[OK] memtest_vulkan: no device loss or Vulkan failure signatures detected." | tee -a "$SUMMARY_FILE"
  fi
else
  echo "[WARN] memtest_vulkan log missing or empty." | tee -a "$SUMMARY_FILE"
fi

# =============================================================================
# cuda_memtest
# =============================================================================
if [[ -s "$MEMTEST_LOG" ]]; then
  if grep -Eai "$FAIL_PATTERNS_MEMTEST" "$MEMTEST_LOG" >/dev/null; then
    echo "[FAIL] cuda_memtest reported explicit mismatches or CUDA failures." | tee -a "$SUMMARY_FILE"
    grep -Eai "$FAIL_PATTERNS_MEMTEST" "$MEMTEST_LOG" | tail -n 20 | tee -a "$SUMMARY_FILE"
    FAIL_COUNT=$((FAIL_COUNT+1))
  else
    echo "[OK] cuda_memtest: no explicit mismatch or CUDA failure signatures detected." | tee -a "$SUMMARY_FILE"
  fi
else
  echo "[WARN] cuda_memtest log missing or empty." | tee -a "$SUMMARY_FILE"
fi

# =============================================================================
# gpu_burn
# =============================================================================
if [[ -s "$BURN_LOG" ]]; then
  if grep -Eai "$FAIL_PATTERNS_BURN" "$BURN_LOG" >/dev/null; then
    echo "[FAIL] gpu_burn reported computation mismatches or CUDA faults." | tee -a "$SUMMARY_FILE"
    grep -Eai "$FAIL_PATTERNS_BURN" "$BURN_LOG" | tail -n 20 | tee -a "$SUMMARY_FILE"
    FAIL_COUNT=$((FAIL_COUNT+1))
  else
    echo "[OK] gpu_burn: no mismatch or CUDA fault signatures detected." | tee -a "$SUMMARY_FILE"
  fi
else
  echo "[WARN] gpu_burn log missing or empty." | tee -a "$SUMMARY_FILE"
fi

# =============================================================================
# FINAL RESULT
# =============================================================================
echo "" | tee -a "$SUMMARY_FILE"
echo "==================== RESULT ====================" | tee -a "$SUMMARY_FILE"

if (( FAIL_COUNT > 0 )); then
  echo "RESULT: FAIL (confirmed NVIDIA GPU, PCIe, or memory fault signatures detected)." | tee -a "$SUMMARY_FILE"
  echo "Run folder: $RUN_DIR" | tee -a "$SUMMARY_FILE"
  exit 2
else
  echo "RESULT: PASS (no confirmed NVIDIA GPU, PCIe, or memory fault signatures detected)." | tee -a "$SUMMARY_FILE"
  echo "Run folder: $RUN_DIR" | tee -a "$SUMMARY_FILE"
  exit 0
fi