
Worked for 29s
Yes. For your four tools, I would divide them this way:

Environment assignment
Tool	Native Ubuntu	WSL Ubuntu	Main purpose
memtest_vulkan	Primary test	Skip for certification	Cross-vendor VRAM testing through Vulkan
gpu-burn	Primary test	Optional supplemental test	NVIDIA compute, power and thermal stress
cuda_memtest	Primary test	Optional quick check	NVIDIA VRAM pattern and bandwidth-error testing
cuda-samples	Initial validation	Initial WSL validation	Confirm CUDA initialization and basic kernel execution
Native Ubuntu should produce the official pass/fail results. WSL results should only confirm that the card can execute CUDA through the Windows/WSL stack. WSL uses the Windows host driver through GPU paravirtualization, and NVIDIA documents limited management/telemetry support there. WSL GPU support is officially aimed at Pascal and newer cards. 

Native Ubuntu production test
Run the tests sequentially, not simultaneously.

1. CUDA Samples: initial smoke test
Run these first:

./deviceQuery
./deviceQueryDrv
./vectorAdd
Expected:

Result = PASS
Use these to confirm:

Correct GPU model and VRAM

CUDA driver/runtime communication

Compute capability

Basic kernel execution

Basic host-to-device and device-to-host operation

deviceQuery enumerates CUDA hardware properties, while the CUDA samples are primarily development demonstrations—not comprehensive hardware diagnostics. 

Do not spend substantial time running every CUDA sample. Many test specific programming features rather than card health.

Bandwidth testing
Recent CUDA Samples removed the old bandwidthTest because NVIDIA considered its results outdated and inaccurate. Use NVIDIA NVBandwidth instead when you want PCIe and memory-transfer measurements. 

2. memtest_vulkan: VRAM screening
Run:

./memtest_vulkan
The developer recommends at least six minutes. For commercial refurbishment, I suggest:

Test level	Runtime
Receiving/quick screening	10 minutes
Normal refurbished-card test	15–20 minutes
Suspected VRAM problem	45–60 minutes
Stop with:

Ctrl+C
Pass requirement:

0 errors
No Vulkan device loss
No application crash
No driver reset
The test uses nearly all available VRAM and reports detected errors immediately. It requires Vulkan 1.1 and at least approximately 1 GB of available GPU memory. 

Where to use it
NVIDIA: yes

AMD: yes

Intel discrete graphics: potentially, when supported by the Vulkan driver

Native Ubuntu: yes

WSL: do not use for your official result

In WSL, graphics APIs can travel through the WSLg/Mesa/D3D12 virtualization path instead of the card’s native Linux Vulkan driver. That adds another layer and makes failures or performance results harder to attribute specifically to the GPU. 

3. gpu-burn: compute, power and thermal stress
For a single NVIDIA GPU:

./gpu_burn -m 90% 900
This uses 90% of available VRAM for 900 seconds, or 15 minutes.

Recommended durations:

# Quick screening: 5 minutes
./gpu_burn -m 90% 300

# Standard production test: 15 minutes
./gpu_burn -m 90% 900

# Extended diagnostic: 30 minutes
./gpu_burn -m 90% 1800

# Suspected intermittent failure: 60 minutes
./gpu_burn -m 90% 3600
GPU-Burn supports selecting memory percentage, individual GPUs, double precision and Tensor Cores. 

My production recommendation
Use:

./gpu_burn -m 90% 900
Do not use -d for your standard baseline. Double-precision performance varies dramatically by GPU family and is intentionally restricted on many consumer cards.

Do not use -tc as the universal baseline either. Tensor Core support varies by generation. You could add a separate Tensor Core test for RTX cards:

./gpu_burn -tc -m 90% 300
Pass requirement:

0 calculation errors
No GPU reset
No Xid errors
No crash
Stable clocks after temperature stabilizes
Temperature within your model-specific threshold
For cards with multiple GPUs installed:

./gpu_burn -l
./gpu_burn -i 0 -m 90% 900
Change 0 to the desired CUDA device number.

4. cuda_memtest: warm VRAM verification
Run this after GPU-Burn so the memory and memory controller are already warm.

Quick check
./cuda_memtest --stress --num_passes 1 --num_iterations 100
This is the project’s documented quick sanity-check configuration. 

Standard production check
./cuda_memtest --stress --num_passes 1 --num_iterations 1000
Suspected VRAM failure
./cuda_memtest --stress --num_passes 3 --num_iterations 1000
The --stress option runs test 10, which repeatedly writes, checks and complements memory patterns while attempting to maximize global-memory bandwidth. The project describes it as useful for exposing hardware errors. 

Pass requirement:

0 memory errors
0 mismatches
No CUDA allocation errors
No GPU reset
No application crash
The full default test suite includes multiple memory patterns, but it runs indefinitely unless you limit its passes. Test 9, the bit-fade test, is disabled by default and takes approximately three hours because it holds all-zero and all-one patterns for 90 minutes each. That test is better reserved for difficult intermittent VRAM cases. 

Recommended native Ubuntu sequence
For a normal refurbished NVIDIA card:

# 1. Identification and CUDA initialization
./deviceQuery
./deviceQueryDrv
./vectorAdd

# 2. Initial VRAM test
timeout 15m ./memtest_vulkan

# 3. Compute, temperature and power stress
./gpu_burn -m 90% 900

# 4. Warm VRAM verification
./cuda_memtest --stress --num_passes 1 --num_iterations 1000
This gives you:

CUDA initialization validation

Vulkan VRAM validation

Sustained compute and thermal load

VRAM testing after the card is heated

For AMD cards, use memtest_vulkan as the main tool. The current cuda_memtest fork can also be compiled with a HIP backend, although it continues to call the resulting binary cuda_memtest. 

What to run under WSL
For WSL, run a smaller supplemental test:

./deviceQuery
./vectorAdd
./cuda_memtest --stress --num_passes 1 --num_iterations 100
./gpu_burn -m 80% 300
I would not run hour-long WSL qualification tests. WSL is useful for confirming:

CUDA works through the installed Windows driver

Basic Linux CUDA applications launch

Compute kernels execute correctly

A CUDA workload can allocate substantial VRAM

But do not use WSL for:

Your authoritative temperature measurement

Fan-control validation

Linux-driver certification

PCIe/AER kernel-error diagnosis

Vulkan certification

Final GPU pass/fail status

NVIDIA specifically instructs WSL users to install only the Windows NVIDIA driver and not a Linux display driver inside WSL. The Windows driver exposes CUDA into WSL through libcuda.so. 

Final recommended test policy
For an NVIDIA card, I would require:

CUDA Samples: PASS
memtest_vulkan: 0 errors for 15 minutes
gpu-burn: 0 errors for 15 minutes
cuda_memtest: 0 errors, 1 pass/1000 iterations
Native Windows graphics benchmark: PASS
All physical video outputs: PASS
Any single calculated or memory error should fail the card. Do not allow an “acceptable error count,” even when the card otherwise finishes the test.



Pasted text.txt
Document
this is the native linux script I use to test the gpu:


Worked for 50s
I reviewed the native Ubuntu script. It has a strong overall sequence—cold PCIe check, compute heat soak, hot PCIe check, CUDA VRAM testing, Vulkan VRAM testing, and kernel-log review—but I would not yet trust its final PASS as a commercial certification result. Several conditions can currently produce a false pass or test the wrong GPU. 


Most important problems
1. The selected GPU is not consistently enforced
Your script prompts for GPU_INDEX, but:

Preflight checks GPU 0 before prompting.

gpu_burn does not include -i "$GPU_INDEX".

cuda_memtest runs without GPU restriction.

memtest_vulkan is not explicitly verified against the selected PCI bus address.

GPU-Burn runs all visible GPUs unless -i N is supplied. CUDA Memtest’s documented default is also to test all available GPUs indefinitely. 

A reliable approach is to mask every CUDA tool to one GPU:

export CUDA_VISIBLE_DEVICES="$GPU_INDEX"
After doing that, the selected physical GPU appears as CUDA device 0, so use:

./gpu_burn -i 0 -m 90% "$GPU_BURN_SECONDS"
Alternatively, place it on each command:

CUDA_VISIBLE_DEVICES="$GPU_INDEX" ./gpu_burn -i 0 -m 90% "$GPU_BURN_SECONDS"
For memtest_vulkan, record and validate the GPU name, device ID, and PCI bus shown in its startup output against:

nvidia-smi -i "$GPU_INDEX" --query-gpu=name,pci.bus_id,uuid --format=csv,noheader
2. CUDA Memtest does not complete a defined test
You currently run:

timeout "$CUDA_MEMTEST_TIMEOUT" ./cuda_memtest
That means CUDA Memtest starts its default infinite, all-tests/all-GPUs behavior and is killed after 30 minutes. It has not necessarily completed a pass, so “no errors before timeout” is not the same as “completed and passed.”

For a predictable production test, use:

CUDA_VISIBLE_DEVICES="$GPU_INDEX" \
timeout --signal=INT --kill-after=15s "$CUDA_MEMTEST_TIMEOUT" \
./cuda_memtest \
  --stress \
  --num_iterations 1000 \
  --num_passes 1
--stress runs test 10 and enables exit-on-error. The project describes test 10 as a repeated, high-bandwidth global-memory stress test intended to expose hardware errors. 

You could also run two stages:

# Defined stress test
./cuda_memtest --stress --num_iterations 1000 --num_passes 1

# Broader pattern test
./cuda_memtest --num_passes 1
The first is more practical for every card. The broader test is useful for suspected VRAM issues.

3. Errors written to stderr may not reach your logs
Your test commands generally use:

command | tee logfile
That captures stdout only. CUDA, Vulkan, loader, allocation, and initialization errors may be written to stderr.

Use:

command |& tee logfile
or:

command 2>&1 | tee logfile
This should be changed for:

gpu_burn

cuda_memtest

memtest_vulkan

Bandwidth tests

Build commands

4. || true discards critical test status
These sections deliberately ignore the command result:

... cuda_memtest ... | tee ... || true
timeout ... memtest_vulkan ... | tee ... || true
The summary then relies only on text matching. Therefore, the following can incorrectly pass:

Segmentation fault

Initialization failure

Vulkan runtime error

CUDA process killed unexpectedly

Missing shared library

Allocation failure

Unsupported device

Test exits before exercising VRAM

Timeout occurs before meaningful progress

A real memtest_vulkan initialization failure can contain phrases such as Runtime error and INIT OR FIRST testing failed; neither phrase is included in your current failure regex. 

Capture the actual exit status:

set +e

timeout --signal=INT --kill-after=15s \
  "$VULKAN_SECONDS" "$VULKAN_BIN" \
  |& tee "$VULKAN_LOG"

VULKAN_RC=${PIPESTATUS[0]}

set -e
Do the same for every major test. Record both:

Exit status

Parsed output result

Your final result should distinguish:

PASS
FAIL
INCOMPLETE
INFRASTRUCTURE ERROR
A missing or empty log should be INCOMPLETE, never a warning followed by PASS.

5. Your failure patterns need expansion
Current Vulkan pattern:

FAIL_PATTERNS_VULKAN='(ERROR_DEVICE_LOST|VkResult: -[1-9][0-9]*|Error found|early exit|FAILED)'
I would add:

FAIL_PATTERNS_VULKAN='(
ERROR_DEVICE_LOST|
VK_ERROR_|
VkResult:[[:space:]]*-[1-9][0-9]*|
Error found|
errors:[[:space:]]*[1-9][0-9]*|
Runtime error|
INIT OR FIRST testing failed|
allocation failed|
Failed determining memory budget|
panic|
segmentation fault|
core dumped|
FAILED
)'
Similarly, expand CUDA patterns:

FAIL_PATTERNS_MEMTEST='(
FAIL|
Mismatch|
Data mismatch|
CUDA error|
cudaError|
uncorrectable|
ERROR SUMMARY:[[:space:]]*[1-9]|
segmentation fault|
core dumped|
out of memory|
initialization error
)'
Avoid relying on \b with grep -E; its handling is not as portable as expected. Use surrounding character classes or simpler wording.

6. GPU-Burn is only built for the first architecture encountered
Your script builds GPU-Burn only when its binary is missing:

if [[ ! -x "$BURN_DIR/gpu_burn" ]]; then
    COMPUTE=...
    make COMPUTE="$COMPUTE"
fi
Once built, that same binary is reused for every subsequent GPU model—even when the compute capability changes.

The GPU-Burn project documents that COMPUTE selects a single architecture. It recommends explicit -gencode options when building a binary for multiple architectures. 

For a refurbishing environment, choose one of these:

Build separate binaries by compute capability.

Rebuild whenever the detected compute capability differs.

Build one fleet-compatible fat binary containing all architectures you accept.

At minimum, store the build target:

echo "$COMPUTE" > "$BURN_DIR/.built_compute"
Then compare it before each run.

7. Run standard GPU-Burn separately from Tensor Core testing
Your production command is:

./gpu_burn -m 90% -tc "$GPU_BURN_SECONDS"
The project describes -tc as “try to use Tensor cores if available.” 

For comparable results across GTX, Quadro, and RTX generations, I recommend:

# Universal baseline
./gpu_burn -i 0 -m 90% "$GPU_BURN_SECONDS"
Then, as a separate supplemental stage for compatible cards:

# Tensor-specific supplemental test
./gpu_burn -i 0 -m 90% -tc 600
That prevents your primary baseline from changing based on whether Tensor Cores are present.

8. bandwidthTest is legacy and has no pass/fail threshold
You correctly preserve a CUDA 11-era copy, so it can still run. However, NVIDIA removed bandwidthTest from CUDA Samples beginning with 12.9 because it considered the tool outdated, and recommends NVBandwidth instead. 

More importantly, your script does not compare cold and hot results. It collects them but never checks:

Minimum H2D bandwidth

Minimum D2H bandwidth

Percentage decline after heat soak

Expected PCIe generation

Expected PCIe link width

PCIe replay/error counters

Therefore, the bandwidth stage currently cannot fail a card unless the application itself crashes.

A useful policy could be:

Cold and hot test must complete.
Hot bandwidth must not fall more than 15% below cold.
Measured result must be consistent with the negotiated PCIe link.
No PCIe AER, Xid, or fallen-off-bus event.
NVBandwidth should eventually replace the sample, but first establish model- and rig-specific baselines.

9. No continuous thermal or throttling log
The script saves nvidia-smi only near the beginning. It does not preserve what happened during the 60-minute burn.

Run background telemetry every one or two seconds:

nvidia-smi \
  --query-gpu=timestamp,index,name,uuid,pci.bus_id,pstate,temperature.gpu,fan.speed,power.draw,power.limit,utilization.gpu,utilization.memory,memory.used,clocks.current.graphics,clocks.current.memory \
  --format=csv \
  --loop=2 \
  > "$RUN_DIR/GPU_TELEMETRY_${TS}.csv" &
TELEMETRY_PID=$!
Stop it in cleanup().

This provides evidence for:

Maximum temperature

Power-limit behavior

Clock collapse

Unexpected fan behavior

GPU utilization dropping during the test

Thermal throttling symptoms

10. Dmesg capture has two weaknesses
First, this pipeline:

sudo dmesg -wT | tee -a logfile >/dev/null &
DMESG_PID="$!"
may assign $! to the last pipeline process rather than cleanly managing the entire capture pipeline. Killing it can leave another process behind.

Use:

sudo dmesg -wT > "$DMESG_LOG" 2>&1 &
DMESG_PID=$!
Second, you scope AER errors to lines containing NVIDIA wording. Some PCIe AER messages identify only the PCI bus address or root port. Capture the tested GPU’s BDF and search both:

GPU_BDF="$(nvidia-smi -i "$GPU_INDEX" \
  --query-gpu=pci.bus_id \
  --format=csv,noheader | tr '[:upper:]' '[:lower:]')"
Also save a pre-run kernel snapshot because dmesg -w sees only new messages after it starts.

Native Ubuntu versus WSL for this exact script
Component	Native Ubuntu	WSL
nvidia-smi identity check	Primary	Supplemental
CUDA deviceQuery	Primary	Useful
GPU-Burn	Primary	Supplemental
CUDA Memtest	Primary	Supplemental
memtest_vulkan	Primary	Do not use for official certification
Cold/hot PCIe bandwidth	Primary	Do not compare against native baselines
Kernel Xid/NVRM review	Primary	WSL cannot replace host-driver logs
PCIe AER review	Primary	Not authoritative
Thermal/fan qualification	Primary	Use native Windows or Linux telemetry
Physical HDMI/DP validation	Separate native test	Not covered
Recommended production sequence
1. Bind all tools to the intended GPU
2. Record GPU UUID, PCI bus, VBIOS and driver version
3. CUDA initialization smoke test
4. Cold PCIe/NVBandwidth test
5. GPU-Burn standard mode
6. Optional Tensor Core GPU-Burn
7. Hot PCIe/NVBandwidth test
8. CUDA Memtest with a defined pass and iteration count
9. memtest_vulkan with captured exit status
10. Stop telemetry and kernel logging
11. Evaluate exit statuses, test completion, error text and thermal limits
12. Output PASS, FAIL, INCOMPLETE or INFRASTRUCTURE ERROR
The existing script should remain your native Ubuntu qualification script. A WSL version should be a smaller supplemental script containing CUDA initialization, a shorter GPU-Burn run, and a defined CUDA Memtest run—not a direct copy of this full workflow.


give me a separate and complete WSL script

Worked for 3m 2s
WSL2 GPU validation script
wsl_gpu_validation.sh

The script keeps your native script’s run-ID, per-run folder, telemetry, logging, and s
 but limits testing to functions that are meaningful inside WSL. 


It runs:

CUDA deviceQuery

CUDA vectorAdd

Standard GPU-Burn, restricted to one GPU

Optional Tensor Core GPU-Burn

cuda_memtest --stress with defined iterations and passes

WSL-visible nvidia-smi telemetry

Windows driver information through powershell.exe, when available

It intentionally excludes memtest_vulkan, PCIe cold/hot qualification, and Linux dmesg/AER/Xid certification. CUDA in WSL uses the Windows host driver through WSL2 GPU virtualization, and NVIDIA documents limitations in WSL’s management and monitoring functionality. 

Installation
Place it in the same type of kit structure as your native script:

GPU-KIT/
├── scripts/
│   └── wsl_gpu_validation.sh
├── src/
│   ├── gpu-burn/
│   │   └── gpu_burn
│   ├── cuda_memtest/
│   │   └── build/
│   │       └── cuda_memtest
│   └── cuda-samples/
└── logs-wsl/
Then run:

chmod +x ~/GPU-KIT/scripts/wsl_gpu_validation.sh
~/GPU-KIT/scripts/wsl_gpu_validation.sh
The script searches under $KIT/src for the required binaries and attempts to build missing tools when the source and build dependencies are available.

Default test settings
gpu-burn duration:          900 seconds
gpu-burn VRAM allocation:   90%
cuda_memtest iterations:    1000
cuda_memtest passes:        1
cuda_memtest timeout:       1800 seconds
Tensor Core test:           disabled by default
Tensor test duration:       300 seconds
GPU-Burn officially supports single-GPU selection with -i, percentage-based memory allocation with -m N%, and optional Tensor Core testing with -tc. 
A Memtest documents --stress --num_iterations 100 --num_passes 1 as a quick sanity test; this script increases the default to 1,000 iterations for a stronger supplemental run. 
Noninteractive example

KIT="$HOME/GPU-KIT" \
RUN_ID="SC-ORDER-12345" \
GPU_INDEX=0 \
GPU_BURN_SECONDS=900 \
GPU_BURN_MEMORY_PERCENT=90 \
CUDA_MEMTEST_ITERATIONS=1000 \
CUDA_MEMTEST_PASSES=1 \
CUDA_MEMTEST_TIMEOUT=1800 \
RUN_TENSOR_TEST=1 \
TENSOR_BURN_SECONDS=300 \
"$HOME/GPU-KIT/scripts/wsl_gpu_validation.sh"
Result codes
0 = PASS — all WSL supplemental tests completed
1 = configuration or preflight failure
2 = FAIL — explicit computation or memory error
3 = INCOMPLETE — timeout, abnormal exit, or missing PASS evidence
A missing log, timeout, initialization failure, unsupported binary, or absent final PASS marker cannot produce a PASS.

Do not install a Linux NVIDIA display-driver package inside WSL. NVIDIA’s guidance is to use the Windows NVIDIA driver and install only an appropriate CUDA toolkit package within the WSL distribution. 
 script passed Bash syntax validation and mocked PASS/FAIL control-flow testing; it has not been executed against your specific WSL installation and physical GPU inventory.



Pasted code.sh
File
now improve the native linux script:


Worked for 5m 38s
I rebuilt your native Ubuntu script as a stricter production-oriented version based on the script you provided. 


native_gpu_validation_v2.sh

Major impro
sing its GPU UUID, not just an index.
Adds deviceQuery and vectorAdd smoke tests.

Runs standard GPU-Burn separately from the optional Tensor Core test.

Scans every GPU-Burn progress line for nonzero errors. This is important because GPU-Burn has documented cases where it exits successfully or prints a final GPU 0: OK despite earlier calculation errors. 
-Burn and CUDA Memtest when the selected GPU’s compute capability changes.

Runs CUDA Memtest as a defined test:

./cuda_memtest \
  --device 0 \
  --stress \
  --num_iterations 1000 \
  --num_passes 1
The --stress mode enables memory test 10 and exit-on-error behavior. 
at memtest_vulkan selected the intended GPU by PCI bus or GPU name.

Avoids piping memtest_vulkan directly into tee; it writes to a regular log file while tail displays live output.

Captures stdout, stderr, exit codes, timeouts, empty logs, and missing completion messages.

Continuously records GPU temperature, utilization, clocks, power, fan speed, memory usage, UUID, and PCI bus.

Captures new dmesg events during the test and checks for:

NVIDIA Xid events

Fallen-off-bus errors

RmInitAdapter failures

Fatal or uncorrected PCIe/AER errors

NVIDIA modeset errors

Compares cold and hot H2D/D2H bandwidth.

Creates a reproducibility snapshot containing driver, VBIOS, CUDA version, Vulkan information, PCI device information, script checksum, and tool Git revisions.

Supports these final results:

PASS
FAIL
INCOMPLETE
SKIPPED
INFRASTRUCTURE ERROR
Exit codes
0   PASS
1   Infrastructure or configuration error
2   FAIL — explicit GPU, VRAM, PCIe, or configured thermal fault
3   INCOMPLETE — timeout, crash, missing log, or missing completion evidence
130 Operator interruption
Installation
Back up your current script and place the replacement inside your kit’s scripts directory:

cp /path/to/current/run_gpu_validation.sh \
   /path/to/current/run_gpu_validation.sh.backup

cp native_gpu_validation_v2.sh \
   /path/to/KIT/scripts/run_gpu_validation.sh

chmod +x /path/to/KIT/scripts/run_gpu_validation.sh
Run it normally:

/path/to/KIT/scripts/run_gpu_validation.sh
Or noninteractively:

KIT="$HOME/GPU-KIT" \
RUN_ID="ORDER-12345" \
GPU_INDEX=0 \
GPU_BURN_SECONDS=3600 \
GPU_BURN_MEMORY_PERCENT=90 \
RUN_TENSOR_TEST=1 \
TENSOR_BURN_SECONDS=600 \
CUDA_MEMTEST_ITERATIONS=1000 \
CUDA_MEMTEST_PASSES=1 \
CUDA_MEMTEST_TIMEOUT=1800 \
VULKAN_SECONDS=1800 \
VULKAN_DEVICE_NUMBER=1 \
MAX_GPU_TEMP_C=0 \
BW_MAX_DROP_PERCENT=20 \
"$HOME/GPU-KIT/scripts/run_gpu_validation.sh"
Important configurable settings
MAX_GPU_TEMP_C=0 means temperatures are recorded but do not automatically fail the card. This is the safest default until you establish model-specific temperature limits.

BW_MAX_DROP_PERCENT=20 fails the cold/hot comparison when hot bandwidth drops more than 20%. This is an operational threshold, not a universal NVIDIA specification, so adjust it after collecting results from known-good cards on each test rig.

REQUIRE_DMESG=1 keeps kernel fault monitoring mandatory. Setting it to 0 marks that check as SKIPPED but does not automatically make the run incomplete.

The script retains your legacy CUDA bandwidthTest workflow for compatibility with your existing kit. NVIDIA has since removed that sample as outdated and recommends NVBandwidth for current bandwidth measurement, so that would be the logical next upgrade. 
 script passed Bash syntax validation plus mocked clean-run, calculation-failure, and optional-dmesg control-flow tests. It has not yet been executed against your physical Ubuntu GPU test rig.


Library
/
native_gpu_validation_v2.sh


#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'

# =============================================================================
# Native Ubuntu NVIDIA GPU Validation - Single GPU (Production-Oriented)
#
# Exit codes:
#   0 = PASS
#   1 = INFRASTRUCTURE / CONFIGURATION ERROR
#   2 = FAIL (explicit GPU, memory, PCIe, or configured thermal fault)
#   3 = INCOMPLETE (timeout, abnormal exit, missing completion evidence)
# 130 = interrupted by operator
#
# Test sequence:
#   A) CUDA deviceQuery smoke test
#   B) CUDA vectorAdd smoke test
#   C) PCIe bandwidth cold (legacy bandwidthTest)
#   D) gpu-burn standard CUDA workload
#   E) Optional gpu-burn Tensor Core workload
#   F) PCIe bandwidth hot and cold/hot comparison
#   G) cuda_memtest defined stress pass
#   H) memtest_vulkan timed VRAM test
#   I) NVIDIA/Xid/AER kernel-log review and optional temperature limit
#
# Expected kit layout (paths can be overridden with environment variables):
#   KIT/src/cuda-samples-11x/Samples/1_Utilities/bandwidthTest/bandwidthTest
#   KIT/src/cuda-samples-11x/Samples/1_Utilities/deviceQuery/deviceQuery
#   KIT/src/cuda-samples-11x/Samples/0_Introduction/vectorAdd/vectorAdd
#   KIT/src/gpu-burn/gpu_burn
#   KIT/src/cuda_memtest/build/cuda_memtest
#   KIT/bin/memtest_vulkan
#   KIT/scripts/native_gpu_validation_v2.sh
#
# Common environment overrides:
#   KIT=/path/to/kit
#   RUN_ID=...
#   GPU_INDEX=0
#   GPU_BURN_SECONDS=3600
#   GPU_BURN_MEMORY_PERCENT=90
#   RUN_TENSOR_TEST=0
#   TENSOR_BURN_SECONDS=600
#   CUDA_MEMTEST_ITERATIONS=1000
#   CUDA_MEMTEST_PASSES=1
#   CUDA_MEMTEST_TIMEOUT=1800
#   VULKAN_SECONDS=1800
#   VULKAN_DEVICE_NUMBER=1
#   BW_MAX_DROP_PERCENT=20       # 0 disables cold/hot threshold
#   MAX_GPU_TEMP_C=0             # 0 disables temperature pass/fail
#   REQUIRE_DMESG=1
#   REBUILD_GPU_BURN=auto        # auto, always, never
#   REBUILD_CUDA_MEMTEST=auto    # auto, always, never
#   NVIDIA_VULKAN_ICD=/path/to/nvidia_icd.json
# =============================================================================

# ----------------------------
# Defaults
# ----------------------------
GPU_BURN_SECONDS_DEFAULT="3600"
GPU_BURN_MEMORY_PERCENT_DEFAULT="90"
RUN_TENSOR_TEST_DEFAULT="0"
TENSOR_BURN_SECONDS_DEFAULT="600"
CUDA_MEMTEST_ITERATIONS_DEFAULT="1000"
CUDA_MEMTEST_PASSES_DEFAULT="1"
CUDA_MEMTEST_TIMEOUT_DEFAULT="1800"
VULKAN_SECONDS_DEFAULT="1800"
BANDWIDTH_TIMEOUT_DEFAULT="300"
BW_MAX_DROP_PERCENT_DEFAULT="20"
MAX_GPU_TEMP_C_DEFAULT="0"
REQUIRE_DMESG_DEFAULT="1"
REBUILD_GPU_BURN_DEFAULT="auto"
REBUILD_CUDA_MEMTEST_DEFAULT="auto"

BW_START_DEFAULT="1048576"
BW_END_DEFAULT="134217728"
BW_INC_DEFAULT="1048576"

# ----------------------------
# Paths and runtime state
# ----------------------------
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
AUTO_KIT="$(cd "$SCRIPT_DIR/.." && pwd)"
KIT="${KIT:-$AUTO_KIT}"
LOG_ROOT="${LOG_ROOT:-$KIT/logs}"

RUN_DIR=""
SUMMARY_FILE=""
SYSTEM_FILE=""

BW_BIN_OVERRIDE="${BW_BIN:-}"
DEVICE_QUERY_BIN_OVERRIDE="${DEVICE_QUERY_BIN:-}"
VECTOR_ADD_BIN_OVERRIDE="${VECTOR_ADD_BIN:-}"
GPU_BURN_BIN_OVERRIDE="${GPU_BURN_BIN:-}"
CUDA_MEMTEST_BIN_OVERRIDE="${CUDA_MEMTEST_BIN:-}"
VULKAN_BIN_OVERRIDE="${VULKAN_BIN:-}"
TELEMETRY_FILE=""
DMESG_LOG=""
DMESG_PRE_FILE=""
DMESG_PID=""
TELEMETRY_PID=""
TAIL_PID=""
INTERRUPTED="0"

GPU_NAME=""
GPU_UUID=""
GPU_PCI_BUS_ID=""
GPU_PCI_SHORT=""
GPU_COMPUTE_CAP=""
GPU_COMPUTE_INT=""

BW_BIN=""
DEVICE_QUERY_BIN=""
VECTOR_ADD_BIN=""
GPU_BURN_BIN=""
CUDA_MEMTEST_BIN=""
VULKAN_BIN=""
NVIDIA_VULKAN_ICD="${NVIDIA_VULKAN_ICD:-}"

CUDA_ENV=()
VULKAN_ENV=()

declare -A TEST_RC=()
declare -A TEST_LOG=()
declare -A TEST_STATUS=()
declare -A TEST_REASON=()
declare -A TEST_LABEL=()

# ----------------------------
# Logging and validation helpers
# ----------------------------
log() {
  local line="[$(date +%F_%T)] $*"
  echo "$line"
  if [[ -n "${SUMMARY_FILE:-}" ]]; then
    echo "$line" >> "$SUMMARY_FILE"
  fi
}

warn() {
  log "[WARN] $*"
}

fatal() {
  log "[INFRASTRUCTURE ERROR] $*"
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  native_gpu_validation_v2.sh

The script prompts for settings unless corresponding environment variables are set.

Examples:
  KIT="$HOME/GPU-KIT" RUN_ID="ORDER-123" GPU_INDEX=0 ./native_gpu_validation_v2.sh

  RUN_ID="ORDER-123" GPU_INDEX=0 GPU_BURN_SECONDS=900 \
  CUDA_MEMTEST_ITERATIONS=1000 CUDA_MEMTEST_PASSES=1 \
  VULKAN_SECONDS=900 ./native_gpu_validation_v2.sh

Exit codes:
  0 PASS, 1 infrastructure/configuration error, 2 FAIL, 3 INCOMPLETE, 130 interrupted
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fatal "Missing required command: $1"
}

sanitize_id() {
  printf '%s' "$1" \
    | sed -E 's/[^a-zA-Z0-9_-]+/_/g' \
    | sed -E 's/^_+|_+$//g'
}

is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

is_positive_uint() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

is_rebuild_mode() {
  [[ "$1" == "auto" || "$1" == "always" || "$1" == "never" ]]
}

find_executable() {
  local filename="$1"
  local result=""
  [[ -d "$KIT/src" ]] || return 1
  result="$(find "$KIT/src" "$KIT/bin" -type f -name "$filename" -perm /111 2>/dev/null | sort | head -n 1 || true)"
  [[ -n "$result" ]] || return 1
  printf '%s\n' "$result"
}

resolve_binary() {
  local override="$1"
  local preferred="$2"
  local filename="$3"

  if [[ -n "$override" && -x "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  if [[ -x "$preferred" ]]; then
    printf '%s\n' "$preferred"
    return 0
  fi
  find_executable "$filename"
}

mark_pass() {
  local key="$1"
  local reason="$2"
  TEST_STATUS["$key"]="PASS"
  TEST_REASON["$key"]="$reason"
}

mark_fail() {
  local key="$1"
  local reason="$2"
  TEST_STATUS["$key"]="FAIL"
  TEST_REASON["$key"]="$reason"
}

mark_incomplete() {
  local key="$1"
  local reason="$2"
  TEST_STATUS["$key"]="INCOMPLETE"
  TEST_REASON["$key"]="$reason"
}

mark_skipped() {
  local key="$1"
  local reason="$2"
  TEST_STATUS["$key"]="SKIPPED"
  TEST_REASON["$key"]="$reason"
}

register_test() {
  local key="$1"
  local label="$2"
  local logfile="$3"
  TEST_LABEL["$key"]="$label"
  TEST_LOG["$key"]="$logfile"
}

classify_common_rc() {
  local key="$1"
  local rc="${TEST_RC[$key]:-127}"
  local logfile="${TEST_LOG[$key]:-}"

  if [[ -z "$logfile" || ! -s "$logfile" ]]; then
    mark_incomplete "$key" "Log is missing or empty."
    return 1
  fi

  case "$rc" in
    0)
      return 0
      ;;
    124|137|143)
      mark_incomplete "$key" "Test timed out or was terminated before normal completion (exit $rc)."
      return 1
      ;;
    *)
      mark_incomplete "$key" "Test exited abnormally with code $rc."
      return 1
      ;;
  esac
}

run_logged_test() {
  local key="$1"
  local label="$2"
  local timeout_seconds="$3"
  local workdir="$4"
  local logfile="$5"
  shift 5
  local -a command=("$@")
  local rc=0

  register_test "$key" "$label" "$logfile"
  log "Starting $label"
  log "Log: $logfile"

  if [[ ! -d "$workdir" ]]; then
    TEST_RC["$key"]="127"
    mark_incomplete "$key" "Working directory missing: $workdir"
    return 0
  fi

  pushd "$workdir" >/dev/null || {
    TEST_RC["$key"]="127"
    mark_incomplete "$key" "Could not enter working directory: $workdir"
    return 0
  }

  if (( timeout_seconds > 0 )); then
    timeout --foreground --signal=TERM --kill-after=15s "$timeout_seconds" \
      "${command[@]}" |& tee "$logfile"
    rc=${PIPESTATUS[0]}
  else
    "${command[@]}" |& tee "$logfile"
    rc=${PIPESTATUS[0]}
  fi

  popd >/dev/null || true
  TEST_RC["$key"]="$rc"
  log "$label exited with code $rc"
}

# memtest_vulkan is written to a regular file instead of directly piping its
# stdout to tee. This avoids application-side broken-pipe behavior. tail -F
# provides live console output while the process writes to the file.
run_vulkan_test() {
  local key="vulkan"
  local label="TEST H: memtest_vulkan timed VRAM test"
  local logfile="$RUN_DIR/memtest_vulkan_${VULKAN_SECONDS}s.log"
  local rc=0

  register_test "$key" "$label" "$logfile"
  : > "$logfile"

  log "Starting $label"
  log "Vulkan menu device number: $VULKAN_DEVICE_NUMBER"
  log "Log: $logfile"

  tail -n +1 -F "$logfile" &
  TAIL_PID=$!

  # The delayed newline lets versions that display 'press any key' after
  # Ctrl+C terminate normally after the timed SIGINT.
  {
    printf '%s\n' "$VULKAN_DEVICE_NUMBER"
    sleep "$((VULKAN_SECONDS + 2))"
    printf '\n'
  } | timeout --foreground --preserve-status --signal=INT --kill-after=20s \
      "$VULKAN_SECONDS" \
      "${VULKAN_ENV[@]}" "$VULKAN_BIN" > "$logfile" 2>&1
  rc=${PIPESTATUS[1]}

  kill "$TAIL_PID" >/dev/null 2>&1 || true
  wait "$TAIL_PID" >/dev/null 2>&1 || true
  TAIL_PID=""

  TEST_RC["$key"]="$rc"
  log "$label exited with code $rc"
}

# ----------------------------
# GPU and build helpers
# ----------------------------
get_compute_capability() {
  local cc=""

  cc="$(nvidia-smi -i "$GPU_INDEX" --query-gpu=compute_cap --format=csv,noheader 2>/dev/null \
    | head -n 1 | tr -d '[:space:]' || true)"
  if [[ "$cc" =~ ^[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "$cc"
    return 0
  fi

  command -v nvcc >/dev/null 2>&1 || return 1

  local tmpdir
  tmpdir="$(mktemp -d)"
  cat > "$tmpdir/compute_cap.cu" <<'CUDAEOF'
#include <cstdio>
#include <cuda_runtime_api.h>
int main() {
    int major = 0;
    int minor = 0;
    cudaError_t e1 = cudaDeviceGetAttribute(&major, cudaDevAttrComputeCapabilityMajor, 0);
    cudaError_t e2 = cudaDeviceGetAttribute(&minor, cudaDevAttrComputeCapabilityMinor, 0);
    if (e1 != cudaSuccess || e2 != cudaSuccess) return 1;
    std::printf("%d.%d\n", major, minor);
    return 0;
}
CUDAEOF

  if "${CUDA_ENV[@]}" nvcc -O2 "$tmpdir/compute_cap.cu" -o "$tmpdir/compute_cap" >/dev/null 2>&1; then
    cc="$("${CUDA_ENV[@]}" "$tmpdir/compute_cap" 2>/dev/null | head -n 1 || true)"
  fi
  rm -rf "$tmpdir"

  if [[ "$cc" =~ ^[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "$cc"
    return 0
  fi
  return 1
}

compute_cap_to_integer() {
  awk -F'.' '{printf "%d%d\n", $1, $2}' <<< "$1"
}

attempt_build_legacy_cuda_sample() {
  local sample_dir="$1"
  local expected_binary="$2"
  local log_name="$3"

  [[ -d "$sample_dir" ]] || return 1
  command -v make >/dev/null 2>&1 || return 1

  log "Building CUDA sample in $sample_dir"
  make -C "$sample_dir" clean |& tee "$RUN_DIR/${log_name}_clean.log"
  local clean_rc=${PIPESTATUS[0]}
  if [[ $clean_rc -ne 0 ]]; then
    warn "Clean step failed for $sample_dir; continuing with build attempt."
  fi

  make -C "$sample_dir" -j"$(nproc)" |& tee "$RUN_DIR/${log_name}_build.log"
  local build_rc=${PIPESTATUS[0]}
  [[ $build_rc -eq 0 && -x "$expected_binary" ]]
}

attempt_build_gpu_burn() {
  local source_dir="$KIT/src/gpu-burn"
  local marker="$source_dir/.rtg_compute_target"
  [[ -d "$source_dir" ]] || return 1
  command -v make >/dev/null 2>&1 || return 1
  command -v nvcc >/dev/null 2>&1 || return 1

  local cuda_path="${CUDA_HOME:-/usr/local/cuda}"
  [[ -d "$cuda_path" ]] || cuda_path="/usr"

  log "Building gpu-burn for compute capability $GPU_COMPUTE_CAP (COMPUTE=$GPU_COMPUTE_INT)"
  (
    cd "$source_dir" || exit 1
    make clean
    make -j"$(nproc)" CUDAPATH="$cuda_path" COMPUTE="$GPU_COMPUTE_INT"
  ) |& tee "$RUN_DIR/build_gpu_burn.log"
  local rc=${PIPESTATUS[0]}

  if [[ $rc -eq 0 && -x "$source_dir/gpu_burn" ]]; then
    printf '%s\n' "$GPU_COMPUTE_INT" > "$marker"
    return 0
  fi
  return 1
}

should_rebuild_for_compute() {
  local mode="$1"
  local binary="$2"
  local marker="$3"

  case "$mode" in
    always)
      return 0
      ;;
    never)
      return 1
      ;;
    auto)
      [[ -x "$binary" ]] || return 0
      [[ -f "$marker" ]] || return 0
      [[ "$(tr -d '[:space:]' < "$marker")" == "$GPU_COMPUTE_INT" ]] || return 0
      return 1
      ;;
  esac
}

attempt_build_cuda_memtest() {
  local source_dir="$KIT/src/cuda_memtest"
  local build_dir="$source_dir/build"
  local marker="$build_dir/.rtg_compute_target"
  [[ -d "$source_dir" ]] || return 1
  command -v cmake >/dev/null 2>&1 || return 1
  command -v nvcc >/dev/null 2>&1 || return 1

  log "Building cuda_memtest for compute capability $GPU_COMPUTE_CAP"
  cmake -S "$source_dir" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_ARCHITECTURES="$GPU_COMPUTE_INT" \
    |& tee "$RUN_DIR/configure_cuda_memtest.log"
  local configure_rc=${PIPESTATUS[0]}
  [[ $configure_rc -eq 0 ]] || return 1

  cmake --build "$build_dir" --parallel "$(nproc)" \
    |& tee "$RUN_DIR/build_cuda_memtest.log"
  local build_rc=${PIPESTATUS[0]}

  if [[ $build_rc -eq 0 && -x "$build_dir/cuda_memtest" ]]; then
    printf '%s\n' "$GPU_COMPUTE_INT" > "$marker"
    return 0
  fi
  return 1
}

attempt_build_memtest_vulkan() {
  local source_dir="$KIT/src/memtest_vulkan"
  [[ -f "$source_dir/Cargo.toml" ]] || return 1
  command -v cargo >/dev/null 2>&1 || return 1

  log "Building memtest_vulkan release binary"
  (cd "$source_dir" && cargo build --release) |& tee "$RUN_DIR/build_memtest_vulkan.log"
  local rc=${PIPESTATUS[0]}
  [[ $rc -eq 0 && -x "$source_dir/target/release/memtest_vulkan" ]]
}

# ----------------------------
# Background capture helpers
# ----------------------------
start_telemetry() {
  TELEMETRY_FILE="$RUN_DIR/NVIDIA_SMI_TELEMETRY.csv"

  local fields="timestamp,index,name,uuid,pci.bus_id,pstate,temperature.gpu,fan.speed,power.draw,power.limit,utilization.gpu,utilization.memory,memory.used,clocks.current.graphics,clocks.current.memory"
  if ! nvidia-smi -i "$GPU_UUID" --query-gpu="$fields" --format=csv,noheader,nounits >/dev/null 2>&1; then
    fields="timestamp,index,name,uuid,pci.bus_id,pstate,temperature.gpu,utilization.gpu,utilization.memory,memory.used"
  fi

  echo "# fields=$fields" > "$TELEMETRY_FILE"
  nvidia-smi -i "$GPU_UUID" --query-gpu="$fields" --format=csv,noheader,nounits --loop=2 \
    >> "$TELEMETRY_FILE" 2>&1 &
  TELEMETRY_PID=$!
  log "Started NVIDIA telemetry (PID $TELEMETRY_PID)."
}

stop_telemetry() {
  if [[ -n "${TELEMETRY_PID:-}" ]]; then
    kill "$TELEMETRY_PID" >/dev/null 2>&1 || true
    wait "$TELEMETRY_PID" >/dev/null 2>&1 || true
    TELEMETRY_PID=""
  fi
}

start_dmesg_capture() {
  DMESG_PRE_FILE="$RUN_DIR/DMESG_BEFORE.log"
  DMESG_LOG="$RUN_DIR/DMESG_DURING.log"

  sudo dmesg -T > "$DMESG_PRE_FILE" 2>&1 || return 1
  echo "# dmesg capture started $(date --iso-8601=seconds)" > "$DMESG_LOG"
  sudo sh -c 'exec dmesg -wT' >> "$DMESG_LOG" 2>&1 &
  DMESG_PID=$!
  sleep 1

  if ! kill -0 "$DMESG_PID" >/dev/null 2>&1; then
    wait "$DMESG_PID" >/dev/null 2>&1 || true
    DMESG_PID=""
    return 1
  fi

  log "Started dmesg capture (PID $DMESG_PID)."
  return 0
}

stop_dmesg_capture() {
  if [[ -n "${DMESG_PID:-}" ]]; then
    sudo kill "$DMESG_PID" >/dev/null 2>&1 || true
    wait "$DMESG_PID" >/dev/null 2>&1 || true
    DMESG_PID=""
  fi
}

cleanup() {
  if [[ -n "${TAIL_PID:-}" ]]; then
    kill "$TAIL_PID" >/dev/null 2>&1 || true
    wait "$TAIL_PID" >/dev/null 2>&1 || true
    TAIL_PID=""
  fi
  stop_telemetry
  stop_dmesg_capture
}

handle_interrupt() {
  INTERRUPTED="1"
  log "Operator interrupted the validation run."
  cleanup
  exit 130
}

# ----------------------------
# Prerequisites before prompting
# ----------------------------
command -v readlink >/dev/null 2>&1 || { echo "ERROR: readlink is required."; exit 1; }
command -v nvidia-smi >/dev/null 2>&1 || { echo "ERROR: nvidia-smi is required."; exit 1; }

if [[ ! -d "$KIT/src" ]]; then
  echo "ERROR: KIT path invalid: $KIT"
  echo "Expected at least: KIT/src and KIT/scripts"
  exit 1
fi

mkdir -p "$LOG_ROOT"

# ----------------------------
# User input
# ----------------------------
echo "============================================================"
echo " Native Ubuntu NVIDIA GPU Validation - Production Run"
echo "============================================================"
echo "Visible NVIDIA GPUs:"
nvidia-smi -L || { echo "ERROR: nvidia-smi cannot enumerate GPUs."; exit 1; }
echo

RUN_ID_RAW="${RUN_ID:-}"
if [[ -z "$RUN_ID_RAW" ]]; then
  read -rp "Enter Run ID (ticket/asset/customer) : " RUN_ID_RAW
fi
[[ -n "$RUN_ID_RAW" ]] || { echo "ERROR: Run ID cannot be empty."; exit 1; }
RUN_ID_SAFE="$(sanitize_id "$RUN_ID_RAW")"
[[ -n "$RUN_ID_SAFE" ]] || { echo "ERROR: Run ID sanitized to empty."; exit 1; }

GPU_INDEX="${GPU_INDEX:-}"
if [[ -z "$GPU_INDEX" ]]; then
  read -rp "NVIDIA GPU index to test (default 0) : " GPU_INDEX
  GPU_INDEX="${GPU_INDEX:-0}"
fi
is_uint "$GPU_INDEX" || { echo "ERROR: GPU index must be a non-negative integer."; exit 1; }

if ! nvidia-smi -i "$GPU_INDEX" >/dev/null 2>&1; then
  echo "ERROR: Cannot access NVIDIA GPU index $GPU_INDEX."
  exit 1
fi

GPU_BURN_SECONDS="${GPU_BURN_SECONDS:-}"
if [[ -z "$GPU_BURN_SECONDS" ]]; then
  read -rp "gpu-burn seconds (default $GPU_BURN_SECONDS_DEFAULT) : " GPU_BURN_SECONDS
  GPU_BURN_SECONDS="${GPU_BURN_SECONDS:-$GPU_BURN_SECONDS_DEFAULT}"
fi
is_positive_uint "$GPU_BURN_SECONDS" || { echo "ERROR: gpu-burn seconds must be positive."; exit 1; }

GPU_BURN_MEMORY_PERCENT="${GPU_BURN_MEMORY_PERCENT:-}"
if [[ -z "$GPU_BURN_MEMORY_PERCENT" ]]; then
  read -rp "gpu-burn VRAM percent (default $GPU_BURN_MEMORY_PERCENT_DEFAULT) : " GPU_BURN_MEMORY_PERCENT
  GPU_BURN_MEMORY_PERCENT="${GPU_BURN_MEMORY_PERCENT:-$GPU_BURN_MEMORY_PERCENT_DEFAULT}"
fi
is_positive_uint "$GPU_BURN_MEMORY_PERCENT" || { echo "ERROR: VRAM percent must be an integer."; exit 1; }
if (( GPU_BURN_MEMORY_PERCENT < 10 || GPU_BURN_MEMORY_PERCENT > 95 )); then
  echo "ERROR: gpu-burn VRAM percent must be between 10 and 95."
  exit 1
fi

RUN_TENSOR_TEST="${RUN_TENSOR_TEST:-}"
if [[ -z "$RUN_TENSOR_TEST" ]]; then
  read -rp "Run separate Tensor Core gpu-burn? [y/N] : " TENSOR_ANSWER
  case "${TENSOR_ANSWER:-N}" in
    y|Y|yes|YES|Yes) RUN_TENSOR_TEST="1" ;;
    *) RUN_TENSOR_TEST="$RUN_TENSOR_TEST_DEFAULT" ;;
  esac
fi
[[ "$RUN_TENSOR_TEST" == "0" || "$RUN_TENSOR_TEST" == "1" ]] \
  || { echo "ERROR: RUN_TENSOR_TEST must be 0 or 1."; exit 1; }

TENSOR_BURN_SECONDS="${TENSOR_BURN_SECONDS:-$TENSOR_BURN_SECONDS_DEFAULT}"
is_positive_uint "$TENSOR_BURN_SECONDS" || { echo "ERROR: Tensor duration must be positive."; exit 1; }

CUDA_MEMTEST_ITERATIONS="${CUDA_MEMTEST_ITERATIONS:-}"
if [[ -z "$CUDA_MEMTEST_ITERATIONS" ]]; then
  read -rp "cuda_memtest iterations (default $CUDA_MEMTEST_ITERATIONS_DEFAULT) : " CUDA_MEMTEST_ITERATIONS
  CUDA_MEMTEST_ITERATIONS="${CUDA_MEMTEST_ITERATIONS:-$CUDA_MEMTEST_ITERATIONS_DEFAULT}"
fi
is_positive_uint "$CUDA_MEMTEST_ITERATIONS" || { echo "ERROR: cuda_memtest iterations must be positive."; exit 1; }

CUDA_MEMTEST_PASSES="${CUDA_MEMTEST_PASSES:-}"
if [[ -z "$CUDA_MEMTEST_PASSES" ]]; then
  read -rp "cuda_memtest passes (default $CUDA_MEMTEST_PASSES_DEFAULT) : " CUDA_MEMTEST_PASSES
  CUDA_MEMTEST_PASSES="${CUDA_MEMTEST_PASSES:-$CUDA_MEMTEST_PASSES_DEFAULT}"
fi
is_positive_uint "$CUDA_MEMTEST_PASSES" || { echo "ERROR: cuda_memtest passes must be positive."; exit 1; }

CUDA_MEMTEST_TIMEOUT="${CUDA_MEMTEST_TIMEOUT:-}"
if [[ -z "$CUDA_MEMTEST_TIMEOUT" ]]; then
  read -rp "cuda_memtest timeout seconds (0=none, default $CUDA_MEMTEST_TIMEOUT_DEFAULT) : " CUDA_MEMTEST_TIMEOUT
  CUDA_MEMTEST_TIMEOUT="${CUDA_MEMTEST_TIMEOUT:-$CUDA_MEMTEST_TIMEOUT_DEFAULT}"
fi
is_uint "$CUDA_MEMTEST_TIMEOUT" || { echo "ERROR: cuda_memtest timeout must be zero or positive."; exit 1; }

VULKAN_SECONDS="${VULKAN_SECONDS:-}"
if [[ -z "$VULKAN_SECONDS" ]]; then
  read -rp "memtest_vulkan seconds (default $VULKAN_SECONDS_DEFAULT) : " VULKAN_SECONDS
  VULKAN_SECONDS="${VULKAN_SECONDS:-$VULKAN_SECONDS_DEFAULT}"
fi
is_positive_uint "$VULKAN_SECONDS" || { echo "ERROR: Vulkan duration must be positive."; exit 1; }

VULKAN_DEVICE_NUMBER="${VULKAN_DEVICE_NUMBER:-}"
if [[ -z "$VULKAN_DEVICE_NUMBER" ]]; then
  VULKAN_DEFAULT=$((GPU_INDEX + 1))
  read -rp "memtest_vulkan menu device number (default $VULKAN_DEFAULT) : " VULKAN_DEVICE_NUMBER
  VULKAN_DEVICE_NUMBER="${VULKAN_DEVICE_NUMBER:-$VULKAN_DEFAULT}"
fi
is_positive_uint "$VULKAN_DEVICE_NUMBER" || { echo "ERROR: Vulkan device number must be positive."; exit 1; }

BW_MAX_DROP_PERCENT="${BW_MAX_DROP_PERCENT:-$BW_MAX_DROP_PERCENT_DEFAULT}"
is_uint "$BW_MAX_DROP_PERCENT" || { echo "ERROR: BW_MAX_DROP_PERCENT must be zero or positive."; exit 1; }

MAX_GPU_TEMP_C="${MAX_GPU_TEMP_C:-$MAX_GPU_TEMP_C_DEFAULT}"
is_uint "$MAX_GPU_TEMP_C" || { echo "ERROR: MAX_GPU_TEMP_C must be zero or positive."; exit 1; }

REQUIRE_DMESG="${REQUIRE_DMESG:-$REQUIRE_DMESG_DEFAULT}"
[[ "$REQUIRE_DMESG" == "0" || "$REQUIRE_DMESG" == "1" ]] \
  || { echo "ERROR: REQUIRE_DMESG must be 0 or 1."; exit 1; }

REBUILD_GPU_BURN="${REBUILD_GPU_BURN:-$REBUILD_GPU_BURN_DEFAULT}"
REBUILD_CUDA_MEMTEST="${REBUILD_CUDA_MEMTEST:-$REBUILD_CUDA_MEMTEST_DEFAULT}"
is_rebuild_mode "$REBUILD_GPU_BURN" || { echo "ERROR: Invalid REBUILD_GPU_BURN mode."; exit 1; }
is_rebuild_mode "$REBUILD_CUDA_MEMTEST" || { echo "ERROR: Invalid REBUILD_CUDA_MEMTEST mode."; exit 1; }

BANDWIDTH_TIMEOUT="${BANDWIDTH_TIMEOUT:-$BANDWIDTH_TIMEOUT_DEFAULT}"
BW_START="${BW_START:-$BW_START_DEFAULT}"
BW_END="${BW_END:-$BW_END_DEFAULT}"
BW_INC="${BW_INC:-$BW_INC_DEFAULT}"
for numeric_value in "$BANDWIDTH_TIMEOUT" "$BW_START" "$BW_END" "$BW_INC"; do
  is_positive_uint "$numeric_value" || { echo "ERROR: Bandwidth settings must be positive integers."; exit 1; }
done

TS="$(date +%F_%H%M%S)"
RUN_DIR="$LOG_ROOT/${RUN_ID_SAFE}_${TS}"
mkdir -p "$RUN_DIR"
SUMMARY_FILE="$RUN_DIR/SUMMARY.txt"
SYSTEM_FILE="$RUN_DIR/SYSTEM_INFO.txt"

trap cleanup EXIT
trap handle_interrupt INT TERM

# ----------------------------
# Full preflight
# ----------------------------
need_cmd tee
need_cmd sed
need_cmd awk
need_cmd grep
need_cmd timeout
need_cmd find
need_cmd tail
need_cmd sha256sum
need_cmd nproc

GPU_NAME="$(nvidia-smi -i "$GPU_INDEX" --query-gpu=name --format=csv,noheader | head -n 1 | sed 's/[[:space:]]*$//')"
GPU_UUID="$(nvidia-smi -i "$GPU_INDEX" --query-gpu=uuid --format=csv,noheader | head -n 1 | tr -d '[:space:]')"
GPU_PCI_BUS_ID="$(nvidia-smi -i "$GPU_INDEX" --query-gpu=pci.bus_id --format=csv,noheader | head -n 1 | tr -d '[:space:]')"

[[ -n "$GPU_NAME" && -n "$GPU_UUID" && -n "$GPU_PCI_BUS_ID" ]] \
  || fatal "Could not obtain selected GPU identity from nvidia-smi."

GPU_PCI_SHORT="$(sed -E 's/^.*:([0-9A-Fa-f]{2}):([0-9A-Fa-f]{2})\.[0-7]$/\1:\2/' <<< "$GPU_PCI_BUS_ID" | tr '[:lower:]' '[:upper:]')"

CUDA_ENV=(env CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES="$GPU_UUID")

GPU_COMPUTE_CAP="$(get_compute_capability || true)"
[[ "$GPU_COMPUTE_CAP" =~ ^[0-9]+\.[0-9]+$ ]] \
  || fatal "Could not determine compute capability for GPU $GPU_INDEX."
GPU_COMPUTE_INT="$(compute_cap_to_integer "$GPU_COMPUTE_CAP")"

log "Run ID: $RUN_ID_RAW"
log "Run directory: $RUN_DIR"
log "Selected GPU index: $GPU_INDEX"
log "Selected GPU: $GPU_NAME"
log "GPU UUID: $GPU_UUID"
log "GPU PCI bus: $GPU_PCI_BUS_ID"
log "Compute capability: $GPU_COMPUTE_CAP"
log "CUDA tests are masked to the selected GPU UUID and see it as local device 0."
log "gpu-burn: ${GPU_BURN_SECONDS}s at ${GPU_BURN_MEMORY_PERCENT}% VRAM"
log "Tensor Core test: $RUN_TENSOR_TEST (${TENSOR_BURN_SECONDS}s when enabled)"
log "cuda_memtest: ${CUDA_MEMTEST_PASSES} pass(es), ${CUDA_MEMTEST_ITERATIONS} iterations, timeout ${CUDA_MEMTEST_TIMEOUT}s"
log "memtest_vulkan: ${VULKAN_SECONDS}s, menu device $VULKAN_DEVICE_NUMBER"
log "Bandwidth hot/cold maximum allowed drop: ${BW_MAX_DROP_PERCENT}% (0=disabled)"
log "Maximum configured GPU temperature: ${MAX_GPU_TEMP_C} C (0=disabled)"

# Select NVIDIA's Vulkan ICD when available to avoid llvmpipe/device-menu noise.
if [[ -z "$NVIDIA_VULKAN_ICD" ]]; then
  for candidate in \
    /usr/share/vulkan/icd.d/nvidia_icd.json \
    /etc/vulkan/icd.d/nvidia_icd.json; do
    if [[ -f "$candidate" ]]; then
      NVIDIA_VULKAN_ICD="$candidate"
      break
    fi
  done
fi

VULKAN_ENV=(env)
if [[ -n "$NVIDIA_VULKAN_ICD" ]]; then
  VULKAN_ENV+=(VK_DRIVER_FILES="$NVIDIA_VULKAN_ICD")
  log "Using NVIDIA Vulkan ICD: $NVIDIA_VULKAN_ICD"
else
  warn "NVIDIA Vulkan ICD JSON was not auto-detected; memtest_vulkan may list non-NVIDIA devices."
fi

# Resolve CUDA sample paths.
CUDA_SAMPLES_ROOT="${CUDA_SAMPLES_ROOT:-$KIT/src/cuda-samples-11x}"
BW_DIR_DEFAULT="$CUDA_SAMPLES_ROOT/Samples/1_Utilities/bandwidthTest"
DEVICE_QUERY_DIR_DEFAULT="$CUDA_SAMPLES_ROOT/Samples/1_Utilities/deviceQuery"
VECTOR_ADD_DIR_DEFAULT="$CUDA_SAMPLES_ROOT/Samples/0_Introduction/vectorAdd"

BW_BIN="$(resolve_binary "$BW_BIN_OVERRIDE" "$BW_DIR_DEFAULT/bandwidthTest" "bandwidthTest" || true)"
if [[ -z "$BW_BIN" || ! -x "$BW_BIN" ]]; then
  attempt_build_legacy_cuda_sample "$BW_DIR_DEFAULT" "$BW_DIR_DEFAULT/bandwidthTest" "bandwidthTest" || true
  BW_BIN="$(resolve_binary "$BW_BIN_OVERRIDE" "$BW_DIR_DEFAULT/bandwidthTest" "bandwidthTest" || true)"
fi

DEVICE_QUERY_BIN="$(resolve_binary "$DEVICE_QUERY_BIN_OVERRIDE" "$DEVICE_QUERY_DIR_DEFAULT/deviceQuery" "deviceQuery" || true)"
if [[ -z "$DEVICE_QUERY_BIN" || ! -x "$DEVICE_QUERY_BIN" ]]; then
  attempt_build_legacy_cuda_sample "$DEVICE_QUERY_DIR_DEFAULT" "$DEVICE_QUERY_DIR_DEFAULT/deviceQuery" "deviceQuery" || true
  DEVICE_QUERY_BIN="$(resolve_binary "$DEVICE_QUERY_BIN_OVERRIDE" "$DEVICE_QUERY_DIR_DEFAULT/deviceQuery" "deviceQuery" || true)"
fi

VECTOR_ADD_BIN="$(resolve_binary "$VECTOR_ADD_BIN_OVERRIDE" "$VECTOR_ADD_DIR_DEFAULT/vectorAdd" "vectorAdd" || true)"
if [[ -z "$VECTOR_ADD_BIN" || ! -x "$VECTOR_ADD_BIN" ]]; then
  attempt_build_legacy_cuda_sample "$VECTOR_ADD_DIR_DEFAULT" "$VECTOR_ADD_DIR_DEFAULT/vectorAdd" "vectorAdd" || true
  VECTOR_ADD_BIN="$(resolve_binary "$VECTOR_ADD_BIN_OVERRIDE" "$VECTOR_ADD_DIR_DEFAULT/vectorAdd" "vectorAdd" || true)"
fi

GPU_BURN_DEFAULT="$KIT/src/gpu-burn/gpu_burn"
GPU_BURN_MARKER="$KIT/src/gpu-burn/.rtg_compute_target"
GPU_BURN_BIN="$(resolve_binary "$GPU_BURN_BIN_OVERRIDE" "$GPU_BURN_DEFAULT" "gpu_burn" || true)"
if [[ -z "$GPU_BURN_BIN_OVERRIDE" || "$REBUILD_GPU_BURN" == "always" ]] \
    && should_rebuild_for_compute "$REBUILD_GPU_BURN" "${GPU_BURN_BIN:-}" "$GPU_BURN_MARKER"; then
  attempt_build_gpu_burn || fatal "gpu-burn rebuild failed. See $RUN_DIR/build_gpu_burn.log"
  GPU_BURN_BIN="$(resolve_binary "$GPU_BURN_BIN_OVERRIDE" "$GPU_BURN_DEFAULT" "gpu_burn" || true)"
fi

CUDA_MEMTEST_DEFAULT="$KIT/src/cuda_memtest/build/cuda_memtest"
CUDA_MEMTEST_MARKER="$KIT/src/cuda_memtest/build/.rtg_compute_target"
CUDA_MEMTEST_BIN="$(resolve_binary "$CUDA_MEMTEST_BIN_OVERRIDE" "$CUDA_MEMTEST_DEFAULT" "cuda_memtest" || true)"
if [[ -z "$CUDA_MEMTEST_BIN_OVERRIDE" || "$REBUILD_CUDA_MEMTEST" == "always" ]] \
    && should_rebuild_for_compute "$REBUILD_CUDA_MEMTEST" "${CUDA_MEMTEST_BIN:-}" "$CUDA_MEMTEST_MARKER"; then
  attempt_build_cuda_memtest || fatal "cuda_memtest rebuild failed. See build logs in $RUN_DIR"
  CUDA_MEMTEST_BIN="$(resolve_binary "$CUDA_MEMTEST_BIN_OVERRIDE" "$CUDA_MEMTEST_DEFAULT" "cuda_memtest" || true)"
fi

VULKAN_BIN="$(resolve_binary "$VULKAN_BIN_OVERRIDE" "$KIT/bin/memtest_vulkan" "memtest_vulkan" || true)"
if [[ -z "$VULKAN_BIN" || ! -x "$VULKAN_BIN" ]]; then
  attempt_build_memtest_vulkan || true
  VULKAN_BIN="$(resolve_binary "$VULKAN_BIN_OVERRIDE" "$KIT/src/memtest_vulkan/target/release/memtest_vulkan" "memtest_vulkan" || true)"
fi

[[ -x "$BW_BIN" ]] || fatal "bandwidthTest binary not found. Set BW_BIN or restore/build the CUDA 11.x sample."
[[ -x "$DEVICE_QUERY_BIN" ]] || fatal "deviceQuery binary not found. Set DEVICE_QUERY_BIN or build CUDA Samples."
[[ -x "$VECTOR_ADD_BIN" ]] || fatal "vectorAdd binary not found. Set VECTOR_ADD_BIN or build CUDA Samples."
[[ -x "$GPU_BURN_BIN" ]] || fatal "gpu_burn binary not found. Set GPU_BURN_BIN or build gpu-burn."
[[ -x "$CUDA_MEMTEST_BIN" ]] || fatal "cuda_memtest binary not found. Set CUDA_MEMTEST_BIN or build cuda_memtest."
[[ -x "$VULKAN_BIN" ]] || fatal "memtest_vulkan binary not found. Set VULKAN_BIN or build memtest_vulkan."

CUDA_MEMTEST_HELP="$($CUDA_MEMTEST_BIN --help 2>&1 || true)"
for required_option in --stress --num_iterations --num_passes --device; do
  grep -q -- "$required_option" <<< "$CUDA_MEMTEST_HELP" \
    || fatal "cuda_memtest binary does not advertise required option $required_option."
done

log "deviceQuery: $DEVICE_QUERY_BIN"
log "vectorAdd: $VECTOR_ADD_BIN"
log "bandwidthTest: $BW_BIN"
log "gpu-burn: $GPU_BURN_BIN"
log "cuda_memtest: $CUDA_MEMTEST_BIN"
log "memtest_vulkan: $VULKAN_BIN"

# dmesg access is part of the production result unless explicitly disabled.
if [[ "$REQUIRE_DMESG" == "1" ]]; then
  need_cmd sudo
  log "Requesting sudo authorization for kernel-log capture..."
  sudo -v || fatal "sudo authorization failed; dmesg capture is required."
  sudo dmesg -T >/dev/null 2>&1 || fatal "sudo cannot read dmesg on this system."
else
  warn "Kernel-log capture is disabled. This reduces fault coverage."
fi

# ----------------------------
# Reproducibility/system snapshot
# ----------------------------
{
  echo "=== NATIVE GPU VALIDATION SYSTEM SNAPSHOT ==="
  echo "Run start: $(date --iso-8601=seconds)"
  echo "Run ID: $RUN_ID_RAW"
  echo "Script: $SCRIPT_PATH"
  echo "Script SHA256: $(sha256sum "$SCRIPT_PATH" | awk '{print $1}')"
  echo
  echo "--- OS / Kernel ---"
  cat /etc/os-release 2>/dev/null || true
  uname -a
  echo
  echo "--- Selected GPU identity ---"
  nvidia-smi -i "$GPU_INDEX" --query-gpu=index,name,uuid,pci.bus_id,serial,vbios_version,driver_version,compute_cap \
    --format=csv 2>&1 || true
  echo
  echo "--- Selected GPU full nvidia-smi query ---"
  nvidia-smi -i "$GPU_INDEX" -q 2>&1 || true
  echo
  echo "--- All NVIDIA GPUs ---"
  nvidia-smi -L 2>&1 || true
  echo
  echo "--- PCI device and driver ---"
  if command -v lspci >/dev/null 2>&1; then
    LSPCI_BDF="$(sed -E 's/^[0-9A-Fa-f]{8}://' <<< "$GPU_PCI_BUS_ID")"
    lspci -nnk -s "$LSPCI_BDF" 2>&1 || true
  else
    echo "lspci not installed"
  fi
  echo
  echo "--- CUDA compiler ---"
  if command -v nvcc >/dev/null 2>&1; then
    command -v nvcc
    nvcc --version
  else
    echo "nvcc not found"
  fi
  echo
  echo "--- Vulkan summary ---"
  if command -v vulkaninfo >/dev/null 2>&1; then
    "${VULKAN_ENV[@]}" vulkaninfo --summary 2>&1 || true
  else
    echo "vulkaninfo not installed"
  fi
  echo
  echo "--- Tool paths ---"
  printf 'deviceQuery=%s\n' "$DEVICE_QUERY_BIN"
  printf 'vectorAdd=%s\n' "$VECTOR_ADD_BIN"
  printf 'bandwidthTest=%s\n' "$BW_BIN"
  printf 'gpu_burn=%s\n' "$GPU_BURN_BIN"
  printf 'cuda_memtest=%s\n' "$CUDA_MEMTEST_BIN"
  printf 'memtest_vulkan=%s\n' "$VULKAN_BIN"
  echo
  echo "--- Git revisions when available ---"
  for repo in "$KIT/src/gpu-burn" "$KIT/src/cuda_memtest" "$KIT/src/memtest_vulkan" "$CUDA_SAMPLES_ROOT"; do
    if [[ -d "$repo/.git" ]] && command -v git >/dev/null 2>&1; then
      printf '%s: ' "$repo"
      git -C "$repo" rev-parse HEAD 2>/dev/null || true
    fi
  done
} > "$SYSTEM_FILE"

# ----------------------------
# Stop competing user-side tests and start captures
# ----------------------------
log "Stopping existing user-side GPU test processes..."
pkill -u "$UID" -x gpu_burn >/dev/null 2>&1 || true
pkill -u "$UID" -x cuda_memtest >/dev/null 2>&1 || true
pkill -u "$UID" -x memtest_vulkan >/dev/null 2>&1 || true
pkill -u "$UID" -x bandwidthTest >/dev/null 2>&1 || true

if [[ "$REQUIRE_DMESG" == "1" ]]; then
  start_dmesg_capture || fatal "Could not start dmesg capture."
fi
start_telemetry

# ----------------------------
# Tests
# ----------------------------
run_logged_test \
  "device_query" \
  "TEST A: CUDA deviceQuery" \
  "120" \
  "$(dirname "$DEVICE_QUERY_BIN")" \
  "$RUN_DIR/deviceQuery.log" \
  "${CUDA_ENV[@]}" "$DEVICE_QUERY_BIN"

run_logged_test \
  "vector_add" \
  "TEST B: CUDA vectorAdd" \
  "120" \
  "$(dirname "$VECTOR_ADD_BIN")" \
  "$RUN_DIR/vectorAdd.log" \
  "${CUDA_ENV[@]}" "$VECTOR_ADD_BIN"

run_logged_test \
  "bw_cold_baseline" \
  "TEST C1: PCIe bandwidth cold baseline" \
  "$BANDWIDTH_TIMEOUT" \
  "$(dirname "$BW_BIN")" \
  "$RUN_DIR/bandwidth_baseline_COLD.log" \
  "${CUDA_ENV[@]}" "$BW_BIN" --device=0

run_logged_test \
  "bw_cold_htod" \
  "TEST C2: PCIe H2D pinned range cold" \
  "$BANDWIDTH_TIMEOUT" \
  "$(dirname "$BW_BIN")" \
  "$RUN_DIR/bandwidth_htod_pinned_COLD.log" \
  "${CUDA_ENV[@]}" "$BW_BIN" --device=0 --memory=pinned --mode=range \
    --start="$BW_START" --end="$BW_END" --increment="$BW_INC" --htod

run_logged_test \
  "bw_cold_dtoh" \
  "TEST C3: PCIe D2H pinned range cold" \
  "$BANDWIDTH_TIMEOUT" \
  "$(dirname "$BW_BIN")" \
  "$RUN_DIR/bandwidth_dtoh_pinned_COLD.log" \
  "${CUDA_ENV[@]}" "$BW_BIN" --device=0 --memory=pinned --mode=range \
    --start="$BW_START" --end="$BW_END" --increment="$BW_INC" --dtoh

GPU_BURN_HARD_TIMEOUT=$((GPU_BURN_SECONDS + 180))
run_logged_test \
  "gpu_burn" \
  "TEST D: gpu-burn standard CUDA workload" \
  "$GPU_BURN_HARD_TIMEOUT" \
  "$(dirname "$GPU_BURN_BIN")" \
  "$RUN_DIR/gpu_burn_${GPU_BURN_SECONDS}s.log" \
  "${CUDA_ENV[@]}" "$GPU_BURN_BIN" -i 0 -m "${GPU_BURN_MEMORY_PERCENT}%" "$GPU_BURN_SECONDS"

if [[ "$RUN_TENSOR_TEST" == "1" ]]; then
  TENSOR_HARD_TIMEOUT=$((TENSOR_BURN_SECONDS + 180))
  run_logged_test \
    "tensor_burn" \
    "TEST E: gpu-burn Tensor Core workload" \
    "$TENSOR_HARD_TIMEOUT" \
    "$(dirname "$GPU_BURN_BIN")" \
    "$RUN_DIR/gpu_burn_tensor_${TENSOR_BURN_SECONDS}s.log" \
    "${CUDA_ENV[@]}" "$GPU_BURN_BIN" -i 0 -m "${GPU_BURN_MEMORY_PERCENT}%" -tc "$TENSOR_BURN_SECONDS"
fi

run_logged_test \
  "bw_hot_baseline" \
  "TEST F1: PCIe bandwidth hot baseline" \
  "$BANDWIDTH_TIMEOUT" \
  "$(dirname "$BW_BIN")" \
  "$RUN_DIR/bandwidth_baseline_HOT.log" \
  "${CUDA_ENV[@]}" "$BW_BIN" --device=0

run_logged_test \
  "bw_hot_htod" \
  "TEST F2: PCIe H2D pinned range hot" \
  "$BANDWIDTH_TIMEOUT" \
  "$(dirname "$BW_BIN")" \
  "$RUN_DIR/bandwidth_htod_pinned_HOT.log" \
  "${CUDA_ENV[@]}" "$BW_BIN" --device=0 --memory=pinned --mode=range \
    --start="$BW_START" --end="$BW_END" --increment="$BW_INC" --htod

run_logged_test \
  "bw_hot_dtoh" \
  "TEST F3: PCIe D2H pinned range hot" \
  "$BANDWIDTH_TIMEOUT" \
  "$(dirname "$BW_BIN")" \
  "$RUN_DIR/bandwidth_dtoh_pinned_HOT.log" \
  "${CUDA_ENV[@]}" "$BW_BIN" --device=0 --memory=pinned --mode=range \
    --start="$BW_START" --end="$BW_END" --increment="$BW_INC" --dtoh

run_logged_test \
  "cuda_memtest" \
  "TEST G: cuda_memtest defined stress pass" \
  "$CUDA_MEMTEST_TIMEOUT" \
  "$(dirname "$CUDA_MEMTEST_BIN")" \
  "$RUN_DIR/cuda_memtest.log" \
  "${CUDA_ENV[@]}" "$CUDA_MEMTEST_BIN" \
    --device 0 \
    --stress \
    --num_iterations "$CUDA_MEMTEST_ITERATIONS" \
    --num_passes "$CUDA_MEMTEST_PASSES" \
    --verbose 1

run_vulkan_test

stop_telemetry
stop_dmesg_capture
sleep 1

# ----------------------------
# Result classification
# ----------------------------
LC_ALL=C

# CUDA Samples
for key in device_query vector_add; do
  logfile="${TEST_LOG[$key]}"
  if [[ ! -s "$logfile" ]]; then
    mark_incomplete "$key" "Log is missing or empty."
  elif grep -Eqi '(Result[[:space:]]*=[[:space:]]*FAIL|CUDA error|no CUDA-capable device|FAILED|segmentation fault|core dumped)' "$logfile"; then
    mark_fail "$key" "CUDA sample reported a failure."
  elif [[ "${TEST_RC[$key]:-127}" -eq 0 ]] && grep -Eqi 'Result[[:space:]]*=[[:space:]]*PASS' "$logfile"; then
    mark_pass "$key" "CUDA sample completed with Result = PASS."
  elif classify_common_rc "$key"; then
    mark_incomplete "$key" "CUDA sample exited normally but did not print Result = PASS."
  fi
done

# bandwidthTest stages
for key in bw_cold_baseline bw_cold_htod bw_cold_dtoh bw_hot_baseline bw_hot_htod bw_hot_dtoh; do
  logfile="${TEST_LOG[$key]}"
  if [[ ! -s "$logfile" ]]; then
    mark_incomplete "$key" "Log is missing or empty."
  elif grep -Eqi '(Result[[:space:]]*=[[:space:]]*FAIL|CUDA error|FAILED|segmentation fault|core dumped)' "$logfile"; then
    mark_fail "$key" "bandwidthTest reported a CUDA or test failure."
  elif [[ "${TEST_RC[$key]:-127}" -eq 0 ]] && grep -Eqi 'Result[[:space:]]*=[[:space:]]*PASS' "$logfile"; then
    mark_pass "$key" "bandwidthTest completed with Result = PASS."
  elif classify_common_rc "$key"; then
    mark_incomplete "$key" "bandwidthTest exited normally but did not print Result = PASS."
  fi
done

# gpu-burn scans every progress line because exit code and final OK alone are
# not sufficient evidence of a clean run.
classify_gpu_burn() {
  local key="$1"
  [[ -v "TEST_LOG[$key]" ]] || return 0

  local logfile="${TEST_LOG[$key]}"
  local hardware_fail_pattern='(errors:[[:space:]]*[1-9][0-9]*|WARNING!|GPU[[:space:]]+[0-9]+:[[:space:]]*FAULTY|FAILURE|mismatch)'
  local runtime_fail_pattern='(CUDA error|Couldn.t init|No clients are alive|Aborting|Error in load module|no kernel image|segmentation fault|core dumped|out of memory)'

  if [[ ! -s "$logfile" ]]; then
    mark_incomplete "$key" "Log is missing or empty."
  elif grep -Eai "$hardware_fail_pattern" "$logfile" >/dev/null; then
    mark_fail "$key" "gpu-burn reported nonzero computation errors or a faulty GPU result."
  elif grep -Eai "$runtime_fail_pattern" "$logfile" >/dev/null; then
    mark_incomplete "$key" "gpu-burn encountered a runtime, build, allocation, or initialization problem."
  elif [[ "${TEST_RC[$key]:-127}" -eq 0 ]] && grep -Eqi 'GPU[[:space:]]+0:[[:space:]]+OK' "$logfile"; then
    mark_pass "$key" "gpu-burn completed with GPU 0: OK and no nonzero error line."
  elif classify_common_rc "$key"; then
    mark_incomplete "$key" "gpu-burn did not provide the expected final GPU 0: OK evidence."
  fi
}
classify_gpu_burn "gpu_burn"
if [[ "$RUN_TENSOR_TEST" == "1" ]]; then
  classify_gpu_burn "tensor_burn"
fi

# cuda_memtest
MEMTEST_LOG="${TEST_LOG[cuda_memtest]}"
MEMTEST_HARDWARE_PATTERN='(Data mismatch|Mismatch|uncorrectable|miscompare|errors found:[[:space:]]*[1-9])'
MEMTEST_RUNTIME_PATTERN='(ERROR:|CUDA error|Some GPU threads are not progressing|no kernel image|segmentation fault|core dumped)'
if [[ ! -s "$MEMTEST_LOG" ]]; then
  mark_incomplete "cuda_memtest" "Log is missing or empty."
elif grep -Eai "$MEMTEST_HARDWARE_PATTERN" "$MEMTEST_LOG" >/dev/null; then
  mark_fail "cuda_memtest" "cuda_memtest reported a memory mismatch or uncorrectable error."
elif grep -Eai "$MEMTEST_RUNTIME_PATTERN" "$MEMTEST_LOG" >/dev/null; then
  mark_incomplete "cuda_memtest" "cuda_memtest encountered a CUDA, allocation, or worker-thread runtime problem."
elif [[ "${TEST_RC[cuda_memtest]:-127}" -eq 0 ]] \
    && grep -Fq 'main thread: Program exits' "$MEMTEST_LOG" \
    && grep -Fq 'Attached to device 0 successfully.' "$MEMTEST_LOG"; then
  mark_pass "cuda_memtest" "Defined stress pass completed and the program exited normally."
elif classify_common_rc "cuda_memtest"; then
  mark_incomplete "cuda_memtest" "cuda_memtest lacked normal completion evidence."
fi

# memtest_vulkan
VULKAN_LOG="${TEST_LOG[vulkan]}"
VULKAN_RC="${TEST_RC[vulkan]:-127}"
if [[ ! -s "$VULKAN_LOG" ]]; then
  mark_incomplete "vulkan" "memtest_vulkan log is missing or empty."
else
  VULKAN_FAIL_PATTERN='(ERROR_DEVICE_LOST|VK_ERROR_|VkResult:[[:space:]]*-[1-9][0-9]*|Error found|errors:[[:space:]]*[1-9][0-9]*|Runtime error|INIT OR FIRST testing failed|allocation failed|Failed determining memory budget|early exit|panic|segmentation fault|core dumped|FAILED)'
  if grep -Eai "$VULKAN_FAIL_PATTERN" "$VULKAN_LOG" >/dev/null; then
    mark_fail "vulkan" "memtest_vulkan reported a memory, device-loss, initialization, or Vulkan failure."
  elif ! grep -Eqi "Bus=0x0*${GPU_PCI_SHORT}" "$VULKAN_LOG" \
      && ! grep -Fqi "$GPU_NAME" "$VULKAN_LOG"; then
    mark_incomplete "vulkan" "Could not verify that memtest_vulkan selected the intended GPU ($GPU_PCI_BUS_ID / $GPU_NAME)."
  elif grep -Fqi 'no any errors, testing PASSed' "$VULKAN_LOG"; then
    case "$VULKAN_RC" in
      0|130)
        mark_pass "vulkan" "Timed Vulkan test ended with its explicit no-error PASS message."
        ;;
      *)
        mark_incomplete "vulkan" "PASS text was present, but process exit code was unexpected: $VULKAN_RC."
        ;;
    esac
  else
    mark_incomplete "vulkan" "memtest_vulkan did not print its explicit no-error PASS message."
  fi
fi

# Cold/hot bandwidth comparison at the largest transfer size.
extract_last_bandwidth() {
  awk '
    $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+([.][0-9]+)?$/ { value=$2 }
    END { if (value != "") print value }
  ' "$1"
}

compare_bandwidth_pair() {
  local key="$1"
  local label="$2"
  local cold_log="$3"
  local hot_log="$4"
  local cold=""
  local hot=""
  local drop=""

  register_test "$key" "$label" "$RUN_DIR/bandwidth_comparison.log"
  cold="$(extract_last_bandwidth "$cold_log" || true)"
  hot="$(extract_last_bandwidth "$hot_log" || true)"

  if [[ -z "$cold" || -z "$hot" ]]; then
    mark_incomplete "$key" "Could not extract cold/hot bandwidth values."
    return
  fi

  drop="$(awk -v c="$cold" -v h="$hot" 'BEGIN { if (c <= 0) print "nan"; else printf "%.2f", ((c-h)/c)*100 }')"
  printf '%s: cold=%s GB/s hot=%s GB/s drop=%s%%\n' "$label" "$cold" "$hot" "$drop" \
    >> "$RUN_DIR/bandwidth_comparison.log"

  if [[ "$drop" == "nan" ]]; then
    mark_incomplete "$key" "Invalid zero cold bandwidth value."
  elif (( BW_MAX_DROP_PERCENT == 0 )); then
    mark_pass "$key" "Cold/hot values recorded; automatic drop threshold disabled."
  elif awk -v d="$drop" -v m="$BW_MAX_DROP_PERCENT" 'BEGIN { exit !(d > m) }'; then
    mark_fail "$key" "Hot bandwidth dropped ${drop}% from cold, exceeding ${BW_MAX_DROP_PERCENT}%."
  else
    mark_pass "$key" "Hot bandwidth change (${drop}%) is within the configured ${BW_MAX_DROP_PERCENT}% limit."
  fi
}

compare_bandwidth_pair \
  "bw_compare_htod" \
  "H2D cold/hot comparison" \
  "${TEST_LOG[bw_cold_htod]}" \
  "${TEST_LOG[bw_hot_htod]}"

compare_bandwidth_pair \
  "bw_compare_dtoh" \
  "D2H cold/hot comparison" \
  "${TEST_LOG[bw_cold_dtoh]}" \
  "${TEST_LOG[bw_hot_dtoh]}"

# Kernel-log review
register_test "kernel_log" "Kernel NVIDIA/Xid/AER review" "$DMESG_LOG"
if [[ "$REQUIRE_DMESG" == "0" ]]; then
  mark_skipped "kernel_log" "Kernel-log review was disabled by configuration."
elif [[ ! -s "$DMESG_LOG" ]]; then
  mark_incomplete "kernel_log" "dmesg capture is missing or empty."
else
  DMESG_FAIL_PATTERN='(NVRM:.*Xid[[:space:]]*\(|NVRM:.*Xid[[:space:]]+[0-9]+|GPU .* has fallen off the bus|RmInitAdapter failed|nvidia.*PCIe.*(error|fault|fatal)|nvidia-modeset:.*ERROR|PCIe Bus Error: severity=(Uncorrected|Fatal)|AER:.*(Uncorrected|Fatal))'
  if grep -Eai "$DMESG_FAIL_PATTERN" "$DMESG_LOG" >/dev/null; then
    mark_fail "kernel_log" "Kernel log contains NVIDIA Xid, fallen-off-bus, fatal PCIe/AER, or NVIDIA driver fault signatures."
  else
    mark_pass "kernel_log" "No strict NVIDIA/Xid/fatal PCIe fault signature appeared during the run."
  fi
fi

# Optional temperature threshold. Telemetry format places temperature.gpu at
# field 7 in both the full and fallback field sets used by this script.
register_test "temperature" "Configured GPU temperature limit" "$TELEMETRY_FILE"
if [[ ! -s "$TELEMETRY_FILE" ]]; then
  mark_incomplete "temperature" "NVIDIA telemetry is missing or empty."
else
  MAX_OBSERVED_TEMP="$(awk -F',' '
    /^#/ { next }
    {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $7)
      if ($7 ~ /^[0-9]+([.][0-9]+)?$/ && ($7+0) > max) max=$7+0
    }
    END { if (max != "") print max }
  ' "$TELEMETRY_FILE")"

  if [[ -z "$MAX_OBSERVED_TEMP" ]]; then
    mark_incomplete "temperature" "Could not parse GPU temperature from telemetry."
  elif (( MAX_GPU_TEMP_C == 0 )); then
    mark_pass "temperature" "Maximum observed GPU temperature was ${MAX_OBSERVED_TEMP} C; automatic limit disabled."
  elif awk -v observed="$MAX_OBSERVED_TEMP" -v limit="$MAX_GPU_TEMP_C" 'BEGIN { exit !(observed > limit) }'; then
    mark_fail "temperature" "Maximum observed GPU temperature ${MAX_OBSERVED_TEMP} C exceeded the configured ${MAX_GPU_TEMP_C} C limit."
  else
    mark_pass "temperature" "Maximum observed GPU temperature ${MAX_OBSERVED_TEMP} C was within the configured limit."
  fi
fi

# ----------------------------
# Final summary
# ----------------------------
FAIL_COUNT=0
INCOMPLETE_COUNT=0
PASS_COUNT=0
SKIPPED_COUNT=0

{
  echo
  echo "==================== TEST RESULTS ===================="
} | tee -a "$SUMMARY_FILE"

RESULT_KEYS=(
  device_query
  vector_add
  bw_cold_baseline
  bw_cold_htod
  bw_cold_dtoh
  gpu_burn
)
if [[ "$RUN_TENSOR_TEST" == "1" ]]; then
  RESULT_KEYS+=(tensor_burn)
fi
RESULT_KEYS+=(
  bw_hot_baseline
  bw_hot_htod
  bw_hot_dtoh
  bw_compare_htod
  bw_compare_dtoh
  cuda_memtest
  vulkan
  kernel_log
  temperature
)

for key in "${RESULT_KEYS[@]}"; do
  status="${TEST_STATUS[$key]:-INCOMPLETE}"
  label="${TEST_LABEL[$key]:-$key}"
  reason="${TEST_REASON[$key]:-No classification was generated.}"
  printf '[%-10s] %s - %s\n' "$status" "$label" "$reason" | tee -a "$SUMMARY_FILE"

  case "$status" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    SKIPPED) SKIPPED_COUNT=$((SKIPPED_COUNT + 1)) ;;
    *) INCOMPLETE_COUNT=$((INCOMPLETE_COUNT + 1)) ;;
  esac
done

{
  echo
  echo "==================== RESULT ===================="
  echo "PASS checks: $PASS_COUNT"
  echo "FAIL checks: $FAIL_COUNT"
  echo "INCOMPLETE checks: $INCOMPLETE_COUNT"
  echo "SKIPPED checks: $SKIPPED_COUNT"
  echo "Run directory: $RUN_DIR"
} | tee -a "$SUMMARY_FILE"

if (( FAIL_COUNT > 0 )); then
  echo "RESULT: FAIL" | tee -a "$SUMMARY_FILE"
  exit 2
elif (( INCOMPLETE_COUNT > 0 )); then
  echo "RESULT: INCOMPLETE" | tee -a "$SUMMARY_FILE"
  exit 3
else
  echo "RESULT: PASS" | tee -a "$SUMMARY_FILE"
  exit 0
fi
Library
/
native_gpu_validation_v2.sh


#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'

# =============================================================================
# Native Ubuntu NVIDIA GPU Validation - Single GPU (Production-Oriented)
#
# Exit codes:
#   0 = PASS
#   1 = INFRASTRUCTURE / CONFIGURATION ERROR
#   2 = FAIL (explicit GPU, memory, PCIe, or configured thermal fault)
#   3 = INCOMPLETE (timeout, abnormal exit, missing completion evidence)
# 130 = interrupted by operator
#
# Test sequence:
#   A) CUDA deviceQuery smoke test
#   B) CUDA vectorAdd smoke test
#   C) PCIe bandwidth cold (legacy bandwidthTest)
#   D) gpu-burn standard CUDA workload
#   E) Optional gpu-burn Tensor Core workload
#   F) PCIe bandwidth hot and cold/hot comparison
#   G) cuda_memtest defined stress pass
#   H) memtest_vulkan timed VRAM test
#   I) NVIDIA/Xid/AER kernel-log review and optional temperature limit
#
# Expected kit layout (paths can be overridden with environment variables):
#   KIT/src/cuda-samples-11x/Samples/1_Utilities/bandwidthTest/bandwidthTest
#   KIT/src/cuda-samples-11x/Samples/1_Utilities/deviceQuery/deviceQuery
#   KIT/src/cuda-samples-11x/Samples/0_Introduction/vectorAdd/vectorAdd
#   KIT/src/gpu-burn/gpu_burn
#   KIT/src/cuda_memtest/build/cuda_memtest
#   KIT/bin/memtest_vulkan
#   KIT/scripts/native_gpu_validation_v2.sh
#
# Common environment overrides:
#   KIT=/path/to/kit
#   RUN_ID=...
#   GPU_INDEX=0
#   GPU_BURN_SECONDS=3600
#   GPU_BURN_MEMORY_PERCENT=90
#   RUN_TENSOR_TEST=0
#   TENSOR_BURN_SECONDS=600
#   CUDA_MEMTEST_ITERATIONS=1000
#   CUDA_MEMTEST_PASSES=1
#   CUDA_MEMTEST_TIMEOUT=1800
#   VULKAN_SECONDS=1800
#   VULKAN_DEVICE_NUMBER=1
#   BW_MAX_DROP_PERCENT=20       # 0 disables cold/hot threshold
#   MAX_GPU_TEMP_C=0             # 0 disables temperature pass/fail
#   REQUIRE_DMESG=1
#   REBUILD_GPU_BURN=auto        # auto, always, never
#   REBUILD_CUDA_MEMTEST=auto    # auto, always, never
#   NVIDIA_VULKAN_ICD=/path/to/nvidia_icd.json
# =============================================================================

# ----------------------------
# Defaults
# ----------------------------
GPU_BURN_SECONDS_DEFAULT="3600"
GPU_BURN_MEMORY_PERCENT_DEFAULT="90"
RUN_TENSOR_TEST_DEFAULT="0"
TENSOR_BURN_SECONDS_DEFAULT="600"
CUDA_MEMTEST_ITERATIONS_DEFAULT="1000"
CUDA_MEMTEST_PASSES_DEFAULT="1"
CUDA_MEMTEST_TIMEOUT_DEFAULT="1800"
VULKAN_SECONDS_DEFAULT="1800"
BANDWIDTH_TIMEOUT_DEFAULT="300"
BW_MAX_DROP_PERCENT_DEFAULT="20"
MAX_GPU_TEMP_C_DEFAULT="0"
REQUIRE_DMESG_DEFAULT="1"
REBUILD_GPU_BURN_DEFAULT="auto"
REBUILD_CUDA_MEMTEST_DEFAULT="auto"

BW_START_DEFAULT="1048576"
BW_END_DEFAULT="134217728"
BW_INC_DEFAULT="1048576"

# ----------------------------
# Paths and runtime state
# ----------------------------
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
AUTO_KIT="$(cd "$SCRIPT_DIR/.." && pwd)"
KIT="${KIT:-$AUTO_KIT}"
LOG_ROOT="${LOG_ROOT:-$KIT/logs}"

RUN_DIR=""
SUMMARY_FILE=""
SYSTEM_FILE=""

BW_BIN_OVERRIDE="${BW_BIN:-}"
DEVICE_QUERY_BIN_OVERRIDE="${DEVICE_QUERY_BIN:-}"
VECTOR_ADD_BIN_OVERRIDE="${VECTOR_ADD_BIN:-}"
GPU_BURN_BIN_OVERRIDE="${GPU_BURN_BIN:-}"
CUDA_MEMTEST_BIN_OVERRIDE="${CUDA_MEMTEST_BIN:-}"
VULKAN_BIN_OVERRIDE="${VULKAN_BIN:-}"
TELEMETRY_FILE=""
DMESG_LOG=""
DMESG_PRE_FILE=""
DMESG_PID=""
TELEMETRY_PID=""
TAIL_PID=""
INTERRUPTED="0"

GPU_NAME=""
GPU_UUID=""
GPU_PCI_BUS_ID=""
GPU_PCI_SHORT=""
GPU_COMPUTE_CAP=""
GPU_COMPUTE_INT=""

BW_BIN=""
DEVICE_QUERY_BIN=""
VECTOR_ADD_BIN=""
GPU_BURN_BIN=""
CUDA_MEMTEST_BIN=""
VULKAN_BIN=""
NVIDIA_VULKAN_ICD="${NVIDIA_VULKAN_ICD:-}"

CUDA_ENV=()
VULKAN_ENV=()

declare -A TEST_RC=()
declare -A TEST_LOG=()
declare -A TEST_STATUS=()
declare -A TEST_REASON=()
declare -A TEST_LABEL=()

# ----------------------------
# Logging and validation helpers
# ----------------------------
log() {
  local line="[$(date +%F_%T)] $*"
  echo "$line"
  if [[ -n "${SUMMARY_FILE:-}" ]]; then
    echo "$line" >> "$SUMMARY_FILE"
  fi
}

warn() {
  log "[WARN] $*"
}

fatal() {
  log "[INFRASTRUCTURE ERROR] $*"
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  native_gpu_validation_v2.sh

The script prompts for settings unless corresponding environment variables are set.

Examples:
  KIT="$HOME/GPU-KIT" RUN_ID="ORDER-123" GPU_INDEX=0 ./native_gpu_validation_v2.sh

  RUN_ID="ORDER-123" GPU_INDEX=0 GPU_BURN_SECONDS=900 \
  CUDA_MEMTEST_ITERATIONS=1000 CUDA_MEMTEST_PASSES=1 \
  VULKAN_SECONDS=900 ./native_gpu_validation_v2.sh

Exit codes:
  0 PASS, 1 infrastructure/configuration error, 2 FAIL, 3 INCOMPLETE, 130 interrupted
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fatal "Missing required command: $1"
}

sanitize_id() {
  printf '%s' "$1" \
    | sed -E 's/[^a-zA-Z0-9_-]+/_/g' \
    | sed -E 's/^_+|_+$//g'
}

is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

is_positive_uint() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

is_rebuild_mode() {
  [[ "$1" == "auto" || "$1" == "always" || "$1" == "never" ]]
}

find_executable() {
  local filename="$1"
  local result=""
  [[ -d "$KIT/src" ]] || return 1
  result="$(find "$KIT/src" "$KIT/bin" -type f -name "$filename" -perm /111 2>/dev/null | sort | head -n 1 || true)"
  [[ -n "$result" ]] || return 1
  printf '%s\n' "$result"
}

resolve_binary() {
  local override="$1"
  local preferred="$2"
  local filename="$3"

  if [[ -n "$override" && -x "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  if [[ -x "$preferred" ]]; then
    printf '%s\n' "$preferred"
    return 0
  fi
  find_executable "$filename"
}

mark_pass() {
  local key="$1"
  local reason="$2"
  TEST_STATUS["$key"]="PASS"
  TEST_REASON["$key"]="$reason"
}

mark_fail() {
  local key="$1"
  local reason="$2"
  TEST_STATUS["$key"]="FAIL"
  TEST_REASON["$key"]="$reason"
}

mark_incomplete() {
  local key="$1"
  local reason="$2"
  TEST_STATUS["$key"]="INCOMPLETE"
  TEST_REASON["$key"]="$reason"
}

mark_skipped() {
  local key="$1"
  local reason="$2"
  TEST_STATUS["$key"]="SKIPPED"
  TEST_REASON["$key"]="$reason"
}

register_test() {
  local key="$1"
  local label="$2"
  local logfile="$3"
  TEST_LABEL["$key"]="$label"
  TEST_LOG["$key"]="$logfile"
}

classify_common_rc() {
  local key="$1"
  local rc="${TEST_RC[$key]:-127}"
  local logfile="${TEST_LOG[$key]:-}"

  if [[ -z "$logfile" || ! -s "$logfile" ]]; then
    mark_incomplete "$key" "Log is missing or empty."
    return 1
  fi

  case "$rc" in
    0)
      return 0
      ;;
    124|137|143)
      mark_incomplete "$key" "Test timed out or was terminated before normal completion (exit $rc)."
      return 1
      ;;
    *)
      mark_incomplete "$key" "Test exited abnormally with code $rc."
      return 1
      ;;
  esac
}

run_logged_test() {
  local key="$1"
  local label="$2"
  local timeout_seconds="$3"
  local workdir="$4"
  local logfile="$5"
  shift 5
  local -a command=("$@")
  local rc=0

  register_test "$key" "$label" "$logfile"
  log "Starting $label"
  log "Log: $logfile"

  if [[ ! -d "$workdir" ]]; then
    TEST_RC["$key"]="127"
    mark_incomplete "$key" "Working directory missing: $workdir"
    return 0
  fi

  pushd "$workdir" >/dev/null || {
    TEST_RC["$key"]="127"
    mark_incomplete "$key" "Could not enter working directory: $workdir"
    return 0
  }

  if (( timeout_seconds > 0 )); then
    timeout --foreground --signal=TERM --kill-after=15s "$timeout_seconds" \
      "${command[@]}" |& tee "$logfile"
    rc=${PIPESTATUS[0]}
  else
    "${command[@]}" |& tee "$logfile"
    rc=${PIPESTATUS[0]}
  fi

  popd >/dev/null || true
  TEST_RC["$key"]="$rc"
  log "$label exited with code $rc"
}

# memtest_vulkan is written to a regular file instead of directly piping its
# stdout to tee. This avoids application-side broken-pipe behavior. tail -F
# provides live console output while the process writes to the file.
run_vulkan_test() {
  local key="vulkan"
  local label="TEST H: memtest_vulkan timed VRAM test"
  local logfile="$RUN_DIR/memtest_vulkan_${VULKAN_SECONDS}s.log"
  local rc=0

  register_test "$key" "$label" "$logfile"
  : > "$logfile"

  log "Starting $label"
  log "Vulkan menu device number: $VULKAN_DEVICE_NUMBER"
  log "Log: $logfile"

  tail -n +1 -F "$logfile" &
  TAIL_PID=$!

  # The delayed newline lets versions that display 'press any key' after
  # Ctrl+C terminate normally after the timed SIGINT.
  {
    printf '%s\n' "$VULKAN_DEVICE_NUMBER"
    sleep "$((VULKAN_SECONDS + 2))"
    printf '\n'
  } | timeout --foreground --preserve-status --signal=INT --kill-after=20s \
      "$VULKAN_SECONDS" \
      "${VULKAN_ENV[@]}" "$VULKAN_BIN" > "$logfile" 2>&1
  rc=${PIPESTATUS[1]}

  kill "$TAIL_PID" >/dev/null 2>&1 || true
  wait "$TAIL_PID" >/dev/null 2>&1 || true
  TAIL_PID=""

  TEST_RC["$key"]="$rc"
  log "$label exited with code $rc"
}

# ----------------------------
# GPU and build helpers
# ----------------------------
get_compute_capability() {
  local cc=""

  cc="$(nvidia-smi -i "$GPU_INDEX" --query-gpu=compute_cap --format=csv,noheader 2>/dev/null \
    | head -n 1 | tr -d '[:space:]' || true)"
  if [[ "$cc" =~ ^[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "$cc"
    return 0
  fi

  command -v nvcc >/dev/null 2>&1 || return 1

  local tmpdir
  tmpdir="$(mktemp -d)"
  cat > "$tmpdir/compute_cap.cu" <<'CUDAEOF'
#include <cstdio>
#include <cuda_runtime_api.h>
int main() {
    int major = 0;
    int minor = 0;
    cudaError_t e1 = cudaDeviceGetAttribute(&major, cudaDevAttrComputeCapabilityMajor, 0);
    cudaError_t e2 = cudaDeviceGetAttribute(&minor, cudaDevAttrComputeCapabilityMinor, 0);
    if (e1 != cudaSuccess || e2 != cudaSuccess) return 1;
    std::printf("%d.%d\n", major, minor);
    return 0;
}
CUDAEOF

  if "${CUDA_ENV[@]}" nvcc -O2 "$tmpdir/compute_cap.cu" -o "$tmpdir/compute_cap" >/dev/null 2>&1; then
    cc="$("${CUDA_ENV[@]}" "$tmpdir/compute_cap" 2>/dev/null | head -n 1 || true)"
  fi
  rm -rf "$tmpdir"

  if [[ "$cc" =~ ^[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "$cc"
    return 0
  fi
  return 1
}

compute_cap_to_integer() {
  awk -F'.' '{printf "%d%d\n", $1, $2}' <<< "$1"
}

attempt_build_legacy_cuda_sample() {
  local sample_dir="$1"
  local expected_binary="$2"
  local log_name="$3"

  [[ -d "$sample_dir" ]] || return 1
  command -v make >/dev/null 2>&1 || return 1

  log "Building CUDA sample in $sample_dir"
  make -C "$sample_dir" clean |& tee "$RUN_DIR/${log_name}_clean.log"
  local clean_rc=${PIPESTATUS[0]}
  if [[ $clean_rc -ne 0 ]]; then
    warn "Clean step failed for $sample_dir; continuing with build attempt."
  fi

  make -C "$sample_dir" -j"$(nproc)" |& tee "$RUN_DIR/${log_name}_build.log"
  local build_rc=${PIPESTATUS[0]}
  [[ $build_rc -eq 0 && -x "$expected_binary" ]]
}

attempt_build_gpu_burn() {
  local source_dir="$KIT/src/gpu-burn"
  local marker="$source_dir/.rtg_compute_target"
  [[ -d "$source_dir" ]] || return 1
  command -v make >/dev/null 2>&1 || return 1
  command -v nvcc >/dev/null 2>&1 || return 1

  local cuda_path="${CUDA_HOME:-/usr/local/cuda}"
  [[ -d "$cuda_path" ]] || cuda_path="/usr"

  log "Building gpu-burn for compute capability $GPU_COMPUTE_CAP (COMPUTE=$GPU_COMPUTE_INT)"
  (
    cd "$source_dir" || exit 1
    make clean
    make -j"$(nproc)" CUDAPATH="$cuda_path" COMPUTE="$GPU_COMPUTE_INT"
  ) |& tee "$RUN_DIR/build_gpu_burn.log"
  local rc=${PIPESTATUS[0]}

  if [[ $rc -eq 0 && -x "$source_dir/gpu_burn" ]]; then
    printf '%s\n' "$GPU_COMPUTE_INT" > "$marker"
    return 0
  fi
  return 1
}

should_rebuild_for_compute() {
  local mode="$1"
  local binary="$2"
  local marker="$3"

  case "$mode" in
    always)
      return 0
      ;;
    never)
      return 1
      ;;
    auto)
      [[ -x "$binary" ]] || return 0
      [[ -f "$marker" ]] || return 0
      [[ "$(tr -d '[:space:]' < "$marker")" == "$GPU_COMPUTE_INT" ]] || return 0
      return 1
      ;;
  esac
}

attempt_build_cuda_memtest() {
  local source_dir="$KIT/src/cuda_memtest"
  local build_dir="$source_dir/build"
  local marker="$build_dir/.rtg_compute_target"
  [[ -d "$source_dir" ]] || return 1
  command -v cmake >/dev/null 2>&1 || return 1
  command -v nvcc >/dev/null 2>&1 || return 1

  log "Building cuda_memtest for compute capability $GPU_COMPUTE_CAP"
  cmake -S "$source_dir" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_ARCHITECTURES="$GPU_COMPUTE_INT" \
    |& tee "$RUN_DIR/configure_cuda_memtest.log"
  local configure_rc=${PIPESTATUS[0]}
  [[ $configure_rc -eq 0 ]] || return 1

  cmake --build "$build_dir" --parallel "$(nproc)" \
    |& tee "$RUN_DIR/build_cuda_memtest.log"
  local build_rc=${PIPESTATUS[0]}

  if [[ $build_rc -eq 0 && -x "$build_dir/cuda_memtest" ]]; then
    printf '%s\n' "$GPU_COMPUTE_INT" > "$marker"
    return 0
  fi
  return 1
}

attempt_build_memtest_vulkan() {
  local source_dir="$KIT/src/memtest_vulkan"
  [[ -f "$source_dir/Cargo.toml" ]] || return 1
  command -v cargo >/dev/null 2>&1 || return 1

  log "Building memtest_vulkan release binary"
  (cd "$source_dir" && cargo build --release) |& tee "$RUN_DIR/build_memtest_vulkan.log"
  local rc=${PIPESTATUS[0]}
  [[ $rc -eq 0 && -x "$source_dir/target/release/memtest_vulkan" ]]
}

# ----------------------------
# Background capture helpers
# ----------------------------
start_telemetry() {
  TELEMETRY_FILE="$RUN_DIR/NVIDIA_SMI_TELEMETRY.csv"

  local fields="timestamp,index,name,uuid,pci.bus_id,pstate,temperature.gpu,fan.speed,power.draw,power.limit,utilization.gpu,utilization.memory,memory.used,clocks.current.graphics,clocks.current.memory"
  if ! nvidia-smi -i "$GPU_UUID" --query-gpu="$fields" --format=csv,noheader,nounits >/dev/null 2>&1; then
    fields="timestamp,index,name,uuid,pci.bus_id,pstate,temperature.gpu,utilization.gpu,utilization.memory,memory.used"
  fi

  echo "# fields=$fields" > "$TELEMETRY_FILE"
  nvidia-smi -i "$GPU_UUID" --query-gpu="$fields" --format=csv,noheader,nounits --loop=2 \
    >> "$TELEMETRY_FILE" 2>&1 &
  TELEMETRY_PID=$!
  log "Started NVIDIA telemetry (PID $TELEMETRY_PID)."
}

stop_telemetry() {
  if [[ -n "${TELEMETRY_PID:-}" ]]; then
    kill "$TELEMETRY_PID" >/dev/null 2>&1 || true
    wait "$TELEMETRY_PID" >/dev/null 2>&1 || true
    TELEMETRY_PID=""
  fi
}

start_dmesg_capture() {
  DMESG_PRE_FILE="$RUN_DIR/DMESG_BEFORE.log"
  DMESG_LOG="$RUN_DIR/DMESG_DURING.log"

  sudo dmesg -T > "$DMESG_PRE_FILE" 2>&1 || return 1
  echo "# dmesg capture started $(date --iso-8601=seconds)" > "$DMESG_LOG"
  sudo sh -c 'exec dmesg -wT' >> "$DMESG_LOG" 2>&1 &
  DMESG_PID=$!
  sleep 1

  if ! kill -0 "$DMESG_PID" >/dev/null 2>&1; then
    wait "$DMESG_PID" >/dev/null 2>&1 || true
    DMESG_PID=""
    return 1
  fi

  log "Started dmesg capture (PID $DMESG_PID)."
  return 0
}

stop_dmesg_capture() {
  if [[ -n "${DMESG_PID:-}" ]]; then
    sudo kill "$DMESG_PID" >/dev/null 2>&1 || true
    wait "$DMESG_PID" >/dev/null 2>&1 || true
    DMESG_PID=""
  fi
}

cleanup() {
  if [[ -n "${TAIL_PID:-}" ]]; then
    kill "$TAIL_PID" >/dev/null 2>&1 || true
    wait "$TAIL_PID" >/dev/null 2>&1 || true
    TAIL_PID=""
  fi
  stop_telemetry
  stop_dmesg_capture
}

handle_interrupt() {
  INTERRUPTED="1"
  log "Operator interrupted the validation run."
  cleanup
  exit 130
}

# ----------------------------
# Prerequisites before prompting
# ----------------------------
command -v readlink >/dev/null 2>&1 || { echo "ERROR: readlink is required."; exit 1; }
command -v nvidia-smi >/dev/null 2>&1 || { echo "ERROR: nvidia-smi is required."; exit 1; }

if [[ ! -d "$KIT/src" ]]; then
  echo "ERROR: KIT path invalid: $KIT"
  echo "Expected at least: KIT/src and KIT/scripts"
  exit 1
fi

mkdir -p "$LOG_ROOT"

# ----------------------------
# User input
# ----------------------------
echo "============================================================"
echo " Native Ubuntu NVIDIA GPU Validation - Production Run"
echo "============================================================"
echo "Visible NVIDIA GPUs:"
nvidia-smi -L || { echo "ERROR: nvidia-smi cannot enumerate GPUs."; exit 1; }
echo

RUN_ID_RAW="${RUN_ID:-}"
if [[ -z "$RUN_ID_RAW" ]]; then
  read -rp "Enter Run ID (ticket/asset/customer) : " RUN_ID_RAW
fi
[[ -n "$RUN_ID_RAW" ]] || { echo "ERROR: Run ID cannot be empty."; exit 1; }
RUN_ID_SAFE="$(sanitize_id "$RUN_ID_RAW")"
[[ -n "$RUN_ID_SAFE" ]] || { echo "ERROR: Run ID sanitized to empty."; exit 1; }

GPU_INDEX="${GPU_INDEX:-}"
if [[ -z "$GPU_INDEX" ]]; then
  read -rp "NVIDIA GPU index to test (default 0) : " GPU_INDEX
  GPU_INDEX="${GPU_INDEX:-0}"
fi
is_uint "$GPU_INDEX" || { echo "ERROR: GPU index must be a non-negative integer."; exit 1; }

if ! nvidia-smi -i "$GPU_INDEX" >/dev/null 2>&1; then
  echo "ERROR: Cannot access NVIDIA GPU index $GPU_INDEX."
  exit 1
fi

GPU_BURN_SECONDS="${GPU_BURN_SECONDS:-}"
if [[ -z "$GPU_BURN_SECONDS" ]]; then
  read -rp "gpu-burn seconds (default $GPU_BURN_SECONDS_DEFAULT) : " GPU_BURN_SECONDS
  GPU_BURN_SECONDS="${GPU_BURN_SECONDS:-$GPU_BURN_SECONDS_DEFAULT}"
fi
is_positive_uint "$GPU_BURN_SECONDS" || { echo "ERROR: gpu-burn seconds must be positive."; exit 1; }

GPU_BURN_MEMORY_PERCENT="${GPU_BURN_MEMORY_PERCENT:-}"
if [[ -z "$GPU_BURN_MEMORY_PERCENT" ]]; then
  read -rp "gpu-burn VRAM percent (default $GPU_BURN_MEMORY_PERCENT_DEFAULT) : " GPU_BURN_MEMORY_PERCENT
  GPU_BURN_MEMORY_PERCENT="${GPU_BURN_MEMORY_PERCENT:-$GPU_BURN_MEMORY_PERCENT_DEFAULT}"
fi
is_positive_uint "$GPU_BURN_MEMORY_PERCENT" || { echo "ERROR: VRAM percent must be an integer."; exit 1; }
if (( GPU_BURN_MEMORY_PERCENT < 10 || GPU_BURN_MEMORY_PERCENT > 95 )); then
  echo "ERROR: gpu-burn VRAM percent must be between 10 and 95."
  exit 1
fi

RUN_TENSOR_TEST="${RUN_TENSOR_TEST:-}"
if [[ -z "$RUN_TENSOR_TEST" ]]; then
  read -rp "Run separate Tensor Core gpu-burn? [y/N] : " TENSOR_ANSWER
  case "${TENSOR_ANSWER:-N}" in
    y|Y|yes|YES|Yes) RUN_TENSOR_TEST="1" ;;
    *) RUN_TENSOR_TEST="$RUN_TENSOR_TEST_DEFAULT" ;;
  esac
fi
[[ "$RUN_TENSOR_TEST" == "0" || "$RUN_TENSOR_TEST" == "1" ]] \
  || { echo "ERROR: RUN_TENSOR_TEST must be 0 or 1."; exit 1; }

TENSOR_BURN_SECONDS="${TENSOR_BURN_SECONDS:-$TENSOR_BURN_SECONDS_DEFAULT}"
is_positive_uint "$TENSOR_BURN_SECONDS" || { echo "ERROR: Tensor duration must be positive."; exit 1; }

CUDA_MEMTEST_ITERATIONS="${CUDA_MEMTEST_ITERATIONS:-}"
if [[ -z "$CUDA_MEMTEST_ITERATIONS" ]]; then
  read -rp "cuda_memtest iterations (default $CUDA_MEMTEST_ITERATIONS_DEFAULT) : " CUDA_MEMTEST_ITERATIONS
  CUDA_MEMTEST_ITERATIONS="${CUDA_MEMTEST_ITERATIONS:-$CUDA_MEMTEST_ITERATIONS_DEFAULT}"
fi
is_positive_uint "$CUDA_MEMTEST_ITERATIONS" || { echo "ERROR: cuda_memtest iterations must be positive."; exit 1; }

CUDA_MEMTEST_PASSES="${CUDA_MEMTEST_PASSES:-}"
if [[ -z "$CUDA_MEMTEST_PASSES" ]]; then
  read -rp "cuda_memtest passes (default $CUDA_MEMTEST_PASSES_DEFAULT) : " CUDA_MEMTEST_PASSES
  CUDA_MEMTEST_PASSES="${CUDA_MEMTEST_PASSES:-$CUDA_MEMTEST_PASSES_DEFAULT}"
fi
is_positive_uint "$CUDA_MEMTEST_PASSES" || { echo "ERROR: cuda_memtest passes must be positive."; exit 1; }

CUDA_MEMTEST_TIMEOUT="${CUDA_MEMTEST_TIMEOUT:-}"
if [[ -z "$CUDA_MEMTEST_TIMEOUT" ]]; then
  read -rp "cuda_memtest timeout seconds (0=none, default $CUDA_MEMTEST_TIMEOUT_DEFAULT) : " CUDA_MEMTEST_TIMEOUT
  CUDA_MEMTEST_TIMEOUT="${CUDA_MEMTEST_TIMEOUT:-$CUDA_MEMTEST_TIMEOUT_DEFAULT}"
fi
is_uint "$CUDA_MEMTEST_TIMEOUT" || { echo "ERROR: cuda_memtest timeout must be zero or positive."; exit 1; }

VULKAN_SECONDS="${VULKAN_SECONDS:-}"
if [[ -z "$VULKAN_SECONDS" ]]; then
  read -rp "memtest_vulkan seconds (default $VULKAN_SECONDS_DEFAULT) : " VULKAN_SECONDS
  VULKAN_SECONDS="${VULKAN_SECONDS:-$VULKAN_SECONDS_DEFAULT}"
fi
is_positive_uint "$VULKAN_SECONDS" || { echo "ERROR: Vulkan duration must be positive."; exit 1; }

VULKAN_DEVICE_NUMBER="${VULKAN_DEVICE_NUMBER:-}"
if [[ -z "$VULKAN_DEVICE_NUMBER" ]]; then
  VULKAN_DEFAULT=$((GPU_INDEX + 1))
  read -rp "memtest_vulkan menu device number (default $VULKAN_DEFAULT) : " VULKAN_DEVICE_NUMBER
  VULKAN_DEVICE_NUMBER="${VULKAN_DEVICE_NUMBER:-$VULKAN_DEFAULT}"
fi
is_positive_uint "$VULKAN_DEVICE_NUMBER" || { echo "ERROR: Vulkan device number must be positive."; exit 1; }

BW_MAX_DROP_PERCENT="${BW_MAX_DROP_PERCENT:-$BW_MAX_DROP_PERCENT_DEFAULT}"
is_uint "$BW_MAX_DROP_PERCENT" || { echo "ERROR: BW_MAX_DROP_PERCENT must be zero or positive."; exit 1; }

MAX_GPU_TEMP_C="${MAX_GPU_TEMP_C:-$MAX_GPU_TEMP_C_DEFAULT}"
is_uint "$MAX_GPU_TEMP_C" || { echo "ERROR: MAX_GPU_TEMP_C must be zero or positive."; exit 1; }

REQUIRE_DMESG="${REQUIRE_DMESG:-$REQUIRE_DMESG_DEFAULT}"
[[ "$REQUIRE_DMESG" == "0" || "$REQUIRE_DMESG" == "1" ]] \
  || { echo "ERROR: REQUIRE_DMESG must be 0 or 1."; exit 1; }

REBUILD_GPU_BURN="${REBUILD_GPU_BURN:-$REBUILD_GPU_BURN_DEFAULT}"
REBUILD_CUDA_MEMTEST="${REBUILD_CUDA_MEMTEST:-$REBUILD_CUDA_MEMTEST_DEFAULT}"
is_rebuild_mode "$REBUILD_GPU_BURN" || { echo "ERROR: Invalid REBUILD_GPU_BURN mode."; exit 1; }
is_rebuild_mode "$REBUILD_CUDA_MEMTEST" || { echo "ERROR: Invalid REBUILD_CUDA_MEMTEST mode."; exit 1; }

BANDWIDTH_TIMEOUT="${BANDWIDTH_TIMEOUT:-$BANDWIDTH_TIMEOUT_DEFAULT}"
BW_START="${BW_START:-$BW_START_DEFAULT}"
BW_END="${BW_END:-$BW_END_DEFAULT}"
BW_INC="${BW_INC:-$BW_INC_DEFAULT}"
for numeric_value in "$BANDWIDTH_TIMEOUT" "$BW_START" "$BW_END" "$BW_INC"; do
  is_positive_uint "$numeric_value" || { echo "ERROR: Bandwidth settings must be positive integers."; exit 1; }
done

TS="$(date +%F_%H%M%S)"
RUN_DIR="$LOG_ROOT/${RUN_ID_SAFE}_${TS}"
mkdir -p "$RUN_DIR"
SUMMARY_FILE="$RUN_DIR/SUMMARY.txt"
SYSTEM_FILE="$RUN_DIR/SYSTEM_INFO.txt"

trap cleanup EXIT
trap handle_interrupt INT TERM

# ----------------------------
# Full preflight
# ----------------------------
need_cmd tee
need_cmd sed
need_cmd awk
need_cmd grep
need_cmd timeout
need_cmd find
need_cmd tail
need_cmd sha256sum
need_cmd nproc

GPU_NAME="$(nvidia-smi -i "$GPU_INDEX" --query-gpu=name --format=csv,noheader | head -n 1 | sed 's/[[:space:]]*$//')"
GPU_UUID="$(nvidia-smi -i "$GPU_INDEX" --query-gpu=uuid --format=csv,noheader | head -n 1 | tr -d '[:space:]')"
GPU_PCI_BUS_ID="$(nvidia-smi -i "$GPU_INDEX" --query-gpu=pci.bus_id --format=csv,noheader | head -n 1 | tr -d '[:space:]')"

[[ -n "$GPU_NAME" && -n "$GPU_UUID" && -n "$GPU_PCI_BUS_ID" ]] \
  || fatal "Could not obtain selected GPU identity from nvidia-smi."

GPU_PCI_SHORT="$(sed -E 's/^.*:([0-9A-Fa-f]{2}):([0-9A-Fa-f]{2})\.[0-7]$/\1:\2/' <<< "$GPU_PCI_BUS_ID" | tr '[:lower:]' '[:upper:]')"

CUDA_ENV=(env CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES="$GPU_UUID")

GPU_COMPUTE_CAP="$(get_compute_capability || true)"
[[ "$GPU_COMPUTE_CAP" =~ ^[0-9]+\.[0-9]+$ ]] \
  || fatal "Could not determine compute capability for GPU $GPU_INDEX."
GPU_COMPUTE_INT="$(compute_cap_to_integer "$GPU_COMPUTE_CAP")"

log "Run ID: $RUN_ID_RAW"
log "Run directory: $RUN_DIR"
log "Selected GPU index: $GPU_INDEX"
log "Selected GPU: $GPU_NAME"
log "GPU UUID: $GPU_UUID"
log "GPU PCI bus: $GPU_PCI_BUS_ID"
log "Compute capability: $GPU_COMPUTE_CAP"
log "CUDA tests are masked to the selected GPU UUID and see it as local device 0."
log "gpu-burn: ${GPU_BURN_SECONDS}s at ${GPU_BURN_MEMORY_PERCENT}% VRAM"
log "Tensor Core test: $RUN_TENSOR_TEST (${TENSOR_BURN_SECONDS}s when enabled)"
log "cuda_memtest: ${CUDA_MEMTEST_PASSES} pass(es), ${CUDA_MEMTEST_ITERATIONS} iterations, timeout ${CUDA_MEMTEST_TIMEOUT}s"
log "memtest_vulkan: ${VULKAN_SECONDS}s, menu device $VULKAN_DEVICE_NUMBER"
log "Bandwidth hot/cold maximum allowed drop: ${BW_MAX_DROP_PERCENT}% (0=disabled)"
log "Maximum configured GPU temperature: ${MAX_GPU_TEMP_C} C (0=disabled)"

# Select NVIDIA's Vulkan ICD when available to avoid llvmpipe/device-menu noise.
if [[ -z "$NVIDIA_VULKAN_ICD" ]]; then
  for candidate in \
    /usr/share/vulkan/icd.d/nvidia_icd.json \
    /etc/vulkan/icd.d/nvidia_icd.json; do
    if [[ -f "$candidate" ]]; then
      NVIDIA_VULKAN_ICD="$candidate"
      break
    fi
  done
fi

VULKAN_ENV=(env)
if [[ -n "$NVIDIA_VULKAN_ICD" ]]; then
  VULKAN_ENV+=(VK_DRIVER_FILES="$NVIDIA_VULKAN_ICD")
  log "Using NVIDIA Vulkan ICD: $NVIDIA_VULKAN_ICD"
else
  warn "NVIDIA Vulkan ICD JSON was not auto-detected; memtest_vulkan may list non-NVIDIA devices."
fi

# Resolve CUDA sample paths.
CUDA_SAMPLES_ROOT="${CUDA_SAMPLES_ROOT:-$KIT/src/cuda-samples-11x}"
BW_DIR_DEFAULT="$CUDA_SAMPLES_ROOT/Samples/1_Utilities/bandwidthTest"
DEVICE_QUERY_DIR_DEFAULT="$CUDA_SAMPLES_ROOT/Samples/1_Utilities/deviceQuery"
VECTOR_ADD_DIR_DEFAULT="$CUDA_SAMPLES_ROOT/Samples/0_Introduction/vectorAdd"

BW_BIN="$(resolve_binary "$BW_BIN_OVERRIDE" "$BW_DIR_DEFAULT/bandwidthTest" "bandwidthTest" || true)"
if [[ -z "$BW_BIN" || ! -x "$BW_BIN" ]]; then
  attempt_build_legacy_cuda_sample "$BW_DIR_DEFAULT" "$BW_DIR_DEFAULT/bandwidthTest" "bandwidthTest" || true
  BW_BIN="$(resolve_binary "$BW_BIN_OVERRIDE" "$BW_DIR_DEFAULT/bandwidthTest" "bandwidthTest" || true)"
fi

DEVICE_QUERY_BIN="$(resolve_binary "$DEVICE_QUERY_BIN_OVERRIDE" "$DEVICE_QUERY_DIR_DEFAULT/deviceQuery" "deviceQuery" || true)"
if [[ -z "$DEVICE_QUERY_BIN" || ! -x "$DEVICE_QUERY_BIN" ]]; then
  attempt_build_legacy_cuda_sample "$DEVICE_QUERY_DIR_DEFAULT" "$DEVICE_QUERY_DIR_DEFAULT/deviceQuery" "deviceQuery" || true
  DEVICE_QUERY_BIN="$(resolve_binary "$DEVICE_QUERY_BIN_OVERRIDE" "$DEVICE_QUERY_DIR_DEFAULT/deviceQuery" "deviceQuery" || true)"
fi

VECTOR_ADD_BIN="$(resolve_binary "$VECTOR_ADD_BIN_OVERRIDE" "$VECTOR_ADD_DIR_DEFAULT/vectorAdd" "vectorAdd" || true)"
if [[ -z "$VECTOR_ADD_BIN" || ! -x "$VECTOR_ADD_BIN" ]]; then
  attempt_build_legacy_cuda_sample "$VECTOR_ADD_DIR_DEFAULT" "$VECTOR_ADD_DIR_DEFAULT/vectorAdd" "vectorAdd" || true
  VECTOR_ADD_BIN="$(resolve_binary "$VECTOR_ADD_BIN_OVERRIDE" "$VECTOR_ADD_DIR_DEFAULT/vectorAdd" "vectorAdd" || true)"
fi

GPU_BURN_DEFAULT="$KIT/src/gpu-burn/gpu_burn"
GPU_BURN_MARKER="$KIT/src/gpu-burn/.rtg_compute_target"
GPU_BURN_BIN="$(resolve_binary "$GPU_BURN_BIN_OVERRIDE" "$GPU_BURN_DEFAULT" "gpu_burn" || true)"
if [[ -z "$GPU_BURN_BIN_OVERRIDE" || "$REBUILD_GPU_BURN" == "always" ]] \
    && should_rebuild_for_compute "$REBUILD_GPU_BURN" "${GPU_BURN_BIN:-}" "$GPU_BURN_MARKER"; then
  attempt_build_gpu_burn || fatal "gpu-burn rebuild failed. See $RUN_DIR/build_gpu_burn.log"
  GPU_BURN_BIN="$(resolve_binary "$GPU_BURN_BIN_OVERRIDE" "$GPU_BURN_DEFAULT" "gpu_burn" || true)"
fi

CUDA_MEMTEST_DEFAULT="$KIT/src/cuda_memtest/build/cuda_memtest"
CUDA_MEMTEST_MARKER="$KIT/src/cuda_memtest/build/.rtg_compute_target"
CUDA_MEMTEST_BIN="$(resolve_binary "$CUDA_MEMTEST_BIN_OVERRIDE" "$CUDA_MEMTEST_DEFAULT" "cuda_memtest" || true)"
if [[ -z "$CUDA_MEMTEST_BIN_OVERRIDE" || "$REBUILD_CUDA_MEMTEST" == "always" ]] \
    && should_rebuild_for_compute "$REBUILD_CUDA_MEMTEST" "${CUDA_MEMTEST_BIN:-}" "$CUDA_MEMTEST_MARKER"; then
  attempt_build_cuda_memtest || fatal "cuda_memtest rebuild failed. See build logs in $RUN_DIR"
  CUDA_MEMTEST_BIN="$(resolve_binary "$CUDA_MEMTEST_BIN_OVERRIDE" "$CUDA_MEMTEST_DEFAULT" "cuda_memtest" || true)"
fi

VULKAN_BIN="$(resolve_binary "$VULKAN_BIN_OVERRIDE" "$KIT/bin/memtest_vulkan" "memtest_vulkan" || true)"
if [[ -z "$VULKAN_BIN" || ! -x "$VULKAN_BIN" ]]; then
  attempt_build_memtest_vulkan || true
  VULKAN_BIN="$(resolve_binary "$VULKAN_BIN_OVERRIDE" "$KIT/src/memtest_vulkan/target/release/memtest_vulkan" "memtest_vulkan" || true)"
fi

[[ -x "$BW_BIN" ]] || fatal "bandwidthTest binary not found. Set BW_BIN or restore/build the CUDA 11.x sample."
[[ -x "$DEVICE_QUERY_BIN" ]] || fatal "deviceQuery binary not found. Set DEVICE_QUERY_BIN or build CUDA Samples."
[[ -x "$VECTOR_ADD_BIN" ]] || fatal "vectorAdd binary not found. Set VECTOR_ADD_BIN or build CUDA Samples."
[[ -x "$GPU_BURN_BIN" ]] || fatal "gpu_burn binary not found. Set GPU_BURN_BIN or build gpu-burn."
[[ -x "$CUDA_MEMTEST_BIN" ]] || fatal "cuda_memtest binary not found. Set CUDA_MEMTEST_BIN or build cuda_memtest."
[[ -x "$VULKAN_BIN" ]] || fatal "memtest_vulkan binary not found. Set VULKAN_BIN or build memtest_vulkan."

CUDA_MEMTEST_HELP="$($CUDA_MEMTEST_BIN --help 2>&1 || true)"
for required_option in --stress --num_iterations --num_passes --device; do
  grep -q -- "$required_option" <<< "$CUDA_MEMTEST_HELP" \
    || fatal "cuda_memtest binary does not advertise required option $required_option."
done

log "deviceQuery: $DEVICE_QUERY_BIN"
log "vectorAdd: $VECTOR_ADD_BIN"
log "bandwidthTest: $BW_BIN"
log "gpu-burn: $GPU_BURN_BIN"
log "cuda_memtest: $CUDA_MEMTEST_BIN"
log "memtest_vulkan: $VULKAN_BIN"

# dmesg access is part of the production result unless explicitly disabled.
if [[ "$REQUIRE_DMESG" == "1" ]]; then
  need_cmd sudo
  log "Requesting sudo authorization for kernel-log capture..."
  sudo -v || fatal "sudo authorization failed; dmesg capture is required."
  sudo dmesg -T >/dev/null 2>&1 || fatal "sudo cannot read dmesg on this system."
else
  warn "Kernel-log capture is disabled. This reduces fault coverage."
fi

# ----------------------------
# Reproducibility/system snapshot
# ----------------------------
{
  echo "=== NATIVE GPU VALIDATION SYSTEM SNAPSHOT ==="
  echo "Run start: $(date --iso-8601=seconds)"
  echo "Run ID: $RUN_ID_RAW"
  echo "Script: $SCRIPT_PATH"
  echo "Script SHA256: $(sha256sum "$SCRIPT_PATH" | awk '{print $1}')"
  echo
  echo "--- OS / Kernel ---"
  cat /etc/os-release 2>/dev/null || true
  uname -a
  echo
  echo "--- Selected GPU identity ---"
  nvidia-smi -i "$GPU_INDEX" --query-gpu=index,name,uuid,pci.bus_id,serial,vbios_version,driver_version,compute_cap \
    --format=csv 2>&1 || true
  echo
  echo "--- Selected GPU full nvidia-smi query ---"
  nvidia-smi -i "$GPU_INDEX" -q 2>&1 || true
  echo
  echo "--- All NVIDIA GPUs ---"
  nvidia-smi -L 2>&1 || true
  echo
  echo "--- PCI device and driver ---"
  if command -v lspci >/dev/null 2>&1; then
    LSPCI_BDF="$(sed -E 's/^[0-9A-Fa-f]{8}://' <<< "$GPU_PCI_BUS_ID")"
    lspci -nnk -s "$LSPCI_BDF" 2>&1 || true
  else
    echo "lspci not installed"
  fi
  echo
  echo "--- CUDA compiler ---"
  if command -v nvcc >/dev/null 2>&1; then
    command -v nvcc
    nvcc --version
  else
    echo "nvcc not found"
  fi
  echo
  echo "--- Vulkan summary ---"
  if command -v vulkaninfo >/dev/null 2>&1; then
    "${VULKAN_ENV[@]}" vulkaninfo --summary 2>&1 || true
  else
    echo "vulkaninfo not installed"
  fi
  echo
  echo "--- Tool paths ---"
  printf 'deviceQuery=%s\n' "$DEVICE_QUERY_BIN"
  printf 'vectorAdd=%s\n' "$VECTOR_ADD_BIN"
  printf 'bandwidthTest=%s\n' "$BW_BIN"
  printf 'gpu_burn=%s\n' "$GPU_BURN_BIN"
  printf 'cuda_memtest=%s\n' "$CUDA_MEMTEST_BIN"
  printf 'memtest_vulkan=%s\n' "$VULKAN_BIN"
  echo
  echo "--- Git revisions when available ---"
  for repo in "$KIT/src/gpu-burn" "$KIT/src/cuda_memtest" "$KIT/src/memtest_vulkan" "$CUDA_SAMPLES_ROOT"; do
    if [[ -d "$repo/.git" ]] && command -v git >/dev/null 2>&1; then
      printf '%s: ' "$repo"
      git -C "$repo" rev-parse HEAD 2>/dev/null || true
    fi
  done
} > "$SYSTEM_FILE"

# ----------------------------
# Stop competing user-side tests and start captures
# ----------------------------
log "Stopping existing user-side GPU test processes..."
pkill -u "$UID" -x gpu_burn >/dev/null 2>&1 || true
pkill -u "$UID" -x cuda_memtest >/dev/null 2>&1 || true
pkill -u "$UID" -x memtest_vulkan >/dev/null 2>&1 || true
pkill -u "$UID" -x bandwidthTest >/dev/null 2>&1 || true

if [[ "$REQUIRE_DMESG" == "1" ]]; then
  start_dmesg_capture || fatal "Could not start dmesg capture."
fi
start_telemetry

# ----------------------------
# Tests
# ----------------------------
run_logged_test \
  "device_query" \
  "TEST A: CUDA deviceQuery" \
  "120" \
  "$(dirname "$DEVICE_QUERY_BIN")" \
  "$RUN_DIR/deviceQuery.log" \
  "${CUDA_ENV[@]}" "$DEVICE_QUERY_BIN"

run_logged_test \
  "vector_add" \
  "TEST B: CUDA vectorAdd" \
  "120" \
  "$(dirname "$VECTOR_ADD_BIN")" \
  "$RUN_DIR/vectorAdd.log" \
  "${CUDA_ENV[@]}" "$VECTOR_ADD_BIN"

run_logged_test \
  "bw_cold_baseline" \
  "TEST C1: PCIe bandwidth cold baseline" \
  "$BANDWIDTH_TIMEOUT" \
  "$(dirname "$BW_BIN")" \
  "$RUN_DIR/bandwidth_baseline_COLD.log" \
  "${CUDA_ENV[@]}" "$BW_BIN" --device=0

run_logged_test \
  "bw_cold_htod" \
  "TEST C2: PCIe H2D pinned range cold" \
  "$BANDWIDTH_TIMEOUT" \
  "$(dirname "$BW_BIN")" \
  "$RUN_DIR/bandwidth_htod_pinned_COLD.log" \
  "${CUDA_ENV[@]}" "$BW_BIN" --device=0 --memory=pinned --mode=range \
    --start="$BW_START" --end="$BW_END" --increment="$BW_INC" --htod

run_logged_test \
  "bw_cold_dtoh" \
  "TEST C3: PCIe D2H pinned range cold" \
  "$BANDWIDTH_TIMEOUT" \
  "$(dirname "$BW_BIN")" \
  "$RUN_DIR/bandwidth_dtoh_pinned_COLD.log" \
  "${CUDA_ENV[@]}" "$BW_BIN" --device=0 --memory=pinned --mode=range \
    --start="$BW_START" --end="$BW_END" --increment="$BW_INC" --dtoh

GPU_BURN_HARD_TIMEOUT=$((GPU_BURN_SECONDS + 180))
run_logged_test \
  "gpu_burn" \
  "TEST D: gpu-burn standard CUDA workload" \
  "$GPU_BURN_HARD_TIMEOUT" \
  "$(dirname "$GPU_BURN_BIN")" \
  "$RUN_DIR/gpu_burn_${GPU_BURN_SECONDS}s.log" \
  "${CUDA_ENV[@]}" "$GPU_BURN_BIN" -i 0 -m "${GPU_BURN_MEMORY_PERCENT}%" "$GPU_BURN_SECONDS"

if [[ "$RUN_TENSOR_TEST" == "1" ]]; then
  TENSOR_HARD_TIMEOUT=$((TENSOR_BURN_SECONDS + 180))
  run_logged_test \
    "tensor_burn" \
    "TEST E: gpu-burn Tensor Core workload" \
    "$TENSOR_HARD_TIMEOUT" \
    "$(dirname "$GPU_BURN_BIN")" \
    "$RUN_DIR/gpu_burn_tensor_${TENSOR_BURN_SECONDS}s.log" \
    "${CUDA_ENV[@]}" "$GPU_BURN_BIN" -i 0 -m "${GPU_BURN_MEMORY_PERCENT}%" -tc "$TENSOR_BURN_SECONDS"
fi

run_logged_test \
  "bw_hot_baseline" \
  "TEST F1: PCIe bandwidth hot baseline" \
  "$BANDWIDTH_TIMEOUT" \
  "$(dirname "$BW_BIN")" \
  "$RUN_DIR/bandwidth_baseline_HOT.log" \
  "${CUDA_ENV[@]}" "$BW_BIN" --device=0

run_logged_test \
  "bw_hot_htod" \
  "TEST F2: PCIe H2D pinned range hot" \
  "$BANDWIDTH_TIMEOUT" \
  "$(dirname "$BW_BIN")" \
  "$RUN_DIR/bandwidth_htod_pinned_HOT.log" \
  "${CUDA_ENV[@]}" "$BW_BIN" --device=0 --memory=pinned --mode=range \
    --start="$BW_START" --end="$BW_END" --increment="$BW_INC" --htod

run_logged_test \
  "bw_hot_dtoh" \
  "TEST F3: PCIe D2H pinned range hot" \
  "$BANDWIDTH_TIMEOUT" \
  "$(dirname "$BW_BIN")" \
  "$RUN_DIR/bandwidth_dtoh_pinned_HOT.log" \
  "${CUDA_ENV[@]}" "$BW_BIN" --device=0 --memory=pinned --mode=range \
    --start="$BW_START" --end="$BW_END" --increment="$BW_INC" --dtoh

run_logged_test \
  "cuda_memtest" \
  "TEST G: cuda_memtest defined stress pass" \
  "$CUDA_MEMTEST_TIMEOUT" \
  "$(dirname "$CUDA_MEMTEST_BIN")" \
  "$RUN_DIR/cuda_memtest.log" \
  "${CUDA_ENV[@]}" "$CUDA_MEMTEST_BIN" \
    --device 0 \
    --stress \
    --num_iterations "$CUDA_MEMTEST_ITERATIONS" \
    --num_passes "$CUDA_MEMTEST_PASSES" \
    --verbose 1

run_vulkan_test

stop_telemetry
stop_dmesg_capture
sleep 1

# ----------------------------
# Result classification
# ----------------------------
LC_ALL=C

# CUDA Samples
for key in device_query vector_add; do
  logfile="${TEST_LOG[$key]}"
  if [[ ! -s "$logfile" ]]; then
    mark_incomplete "$key" "Log is missing or empty."
  elif grep -Eqi '(Result[[:space:]]*=[[:space:]]*FAIL|CUDA error|no CUDA-capable device|FAILED|segmentation fault|core dumped)' "$logfile"; then
    mark_fail "$key" "CUDA sample reported a failure."
  elif [[ "${TEST_RC[$key]:-127}" -eq 0 ]] && grep -Eqi 'Result[[:space:]]*=[[:space:]]*PASS' "$logfile"; then
    mark_pass "$key" "CUDA sample completed with Result = PASS."
  elif classify_common_rc "$key"; then
    mark_incomplete "$key" "CUDA sample exited normally but did not print Result = PASS."
  fi
done

# bandwidthTest stages
for key in bw_cold_baseline bw_cold_htod bw_cold_dtoh bw_hot_baseline bw_hot_htod bw_hot_dtoh; do
  logfile="${TEST_LOG[$key]}"
  if [[ ! -s "$logfile" ]]; then
    mark_incomplete "$key" "Log is missing or empty."
  elif grep -Eqi '(Result[[:space:]]*=[[:space:]]*FAIL|CUDA error|FAILED|segmentation fault|core dumped)' "$logfile"; then
    mark_fail "$key" "bandwidthTest reported a CUDA or test failure."
  elif [[ "${TEST_RC[$key]:-127}" -eq 0 ]] && grep -Eqi 'Result[[:space:]]*=[[:space:]]*PASS' "$logfile"; then
    mark_pass "$key" "bandwidthTest completed with Result = PASS."
  elif classify_common_rc "$key"; then
    mark_incomplete "$key" "bandwidthTest exited normally but did not print Result = PASS."
  fi
done

# gpu-burn scans every progress line because exit code and final OK alone are
# not sufficient evidence of a clean run.
classify_gpu_burn() {
  local key="$1"
  [[ -v "TEST_LOG[$key]" ]] || return 0

  local logfile="${TEST_LOG[$key]}"
  local hardware_fail_pattern='(errors:[[:space:]]*[1-9][0-9]*|WARNING!|GPU[[:space:]]+[0-9]+:[[:space:]]*FAULTY|FAILURE|mismatch)'
  local runtime_fail_pattern='(CUDA error|Couldn.t init|No clients are alive|Aborting|Error in load module|no kernel image|segmentation fault|core dumped|out of memory)'

  if [[ ! -s "$logfile" ]]; then
    mark_incomplete "$key" "Log is missing or empty."
  elif grep -Eai "$hardware_fail_pattern" "$logfile" >/dev/null; then
    mark_fail "$key" "gpu-burn reported nonzero computation errors or a faulty GPU result."
  elif grep -Eai "$runtime_fail_pattern" "$logfile" >/dev/null; then
    mark_incomplete "$key" "gpu-burn encountered a runtime, build, allocation, or initialization problem."
  elif [[ "${TEST_RC[$key]:-127}" -eq 0 ]] && grep -Eqi 'GPU[[:space:]]+0:[[:space:]]+OK' "$logfile"; then
    mark_pass "$key" "gpu-burn completed with GPU 0: OK and no nonzero error line."
  elif classify_common_rc "$key"; then
    mark_incomplete "$key" "gpu-burn did not provide the expected final GPU 0: OK evidence."
  fi
}
classify_gpu_burn "gpu_burn"
if [[ "$RUN_TENSOR_TEST" == "1" ]]; then
  classify_gpu_burn "tensor_burn"
fi

# cuda_memtest
MEMTEST_LOG="${TEST_LOG[cuda_memtest]}"
MEMTEST_HARDWARE_PATTERN='(Data mismatch|Mismatch|uncorrectable|miscompare|errors found:[[:space:]]*[1-9])'
MEMTEST_RUNTIME_PATTERN='(ERROR:|CUDA error|Some GPU threads are not progressing|no kernel image|segmentation fault|core dumped)'
if [[ ! -s "$MEMTEST_LOG" ]]; then
  mark_incomplete "cuda_memtest" "Log is missing or empty."
elif grep -Eai "$MEMTEST_HARDWARE_PATTERN" "$MEMTEST_LOG" >/dev/null; then
  mark_fail "cuda_memtest" "cuda_memtest reported a memory mismatch or uncorrectable error."
elif grep -Eai "$MEMTEST_RUNTIME_PATTERN" "$MEMTEST_LOG" >/dev/null; then
  mark_incomplete "cuda_memtest" "cuda_memtest encountered a CUDA, allocation, or worker-thread runtime problem."
elif [[ "${TEST_RC[cuda_memtest]:-127}" -eq 0 ]] \
    && grep -Fq 'main thread: Program exits' "$MEMTEST_LOG" \
    && grep -Fq 'Attached to device 0 successfully.' "$MEMTEST_LOG"; then
  mark_pass "cuda_memtest" "Defined stress pass completed and the program exited normally."
elif classify_common_rc "cuda_memtest"; then
  mark_incomplete "cuda_memtest" "cuda_memtest lacked normal completion evidence."
fi

# memtest_vulkan
VULKAN_LOG="${TEST_LOG[vulkan]}"
VULKAN_RC="${TEST_RC[vulkan]:-127}"
if [[ ! -s "$VULKAN_LOG" ]]; then
  mark_incomplete "vulkan" "memtest_vulkan log is missing or empty."
else
  VULKAN_FAIL_PATTERN='(ERROR_DEVICE_LOST|VK_ERROR_|VkResult:[[:space:]]*-[1-9][0-9]*|Error found|errors:[[:space:]]*[1-9][0-9]*|Runtime error|INIT OR FIRST testing failed|allocation failed|Failed determining memory budget|early exit|panic|segmentation fault|core dumped|FAILED)'
  if grep -Eai "$VULKAN_FAIL_PATTERN" "$VULKAN_LOG" >/dev/null; then
    mark_fail "vulkan" "memtest_vulkan reported a memory, device-loss, initialization, or Vulkan failure."
  elif ! grep -Eqi "Bus=0x0*${GPU_PCI_SHORT}" "$VULKAN_LOG" \
      && ! grep -Fqi "$GPU_NAME" "$VULKAN_LOG"; then
    mark_incomplete "vulkan" "Could not verify that memtest_vulkan selected the intended GPU ($GPU_PCI_BUS_ID / $GPU_NAME)."
  elif grep -Fqi 'no any errors, testing PASSed' "$VULKAN_LOG"; then
    case "$VULKAN_RC" in
      0|130)
        mark_pass "vulkan" "Timed Vulkan test ended with its explicit no-error PASS message."
        ;;
      *)
        mark_incomplete "vulkan" "PASS text was present, but process exit code was unexpected: $VULKAN_RC."
        ;;
    esac
  else
    mark_incomplete "vulkan" "memtest_vulkan did not print its explicit no-error PASS message."
  fi
fi

# Cold/hot bandwidth comparison at the largest transfer size.
extract_last_bandwidth() {
  awk '
    $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+([.][0-9]+)?$/ { value=$2 }
    END { if (value != "") print value }
  ' "$1"
}

compare_bandwidth_pair() {
  local key="$1"
  local label="$2"
  local cold_log="$3"
  local hot_log="$4"
  local cold=""
  local hot=""
  local drop=""

  register_test "$key" "$label" "$RUN_DIR/bandwidth_comparison.log"
  cold="$(extract_last_bandwidth "$cold_log" || true)"
  hot="$(extract_last_bandwidth "$hot_log" || true)"

  if [[ -z "$cold" || -z "$hot" ]]; then
    mark_incomplete "$key" "Could not extract cold/hot bandwidth values."
    return
  fi

  drop="$(awk -v c="$cold" -v h="$hot" 'BEGIN { if (c <= 0) print "nan"; else printf "%.2f", ((c-h)/c)*100 }')"
  printf '%s: cold=%s GB/s hot=%s GB/s drop=%s%%\n' "$label" "$cold" "$hot" "$drop" \
    >> "$RUN_DIR/bandwidth_comparison.log"

  if [[ "$drop" == "nan" ]]; then
    mark_incomplete "$key" "Invalid zero cold bandwidth value."
  elif (( BW_MAX_DROP_PERCENT == 0 )); then
    mark_pass "$key" "Cold/hot values recorded; automatic drop threshold disabled."
  elif awk -v d="$drop" -v m="$BW_MAX_DROP_PERCENT" 'BEGIN { exit !(d > m) }'; then
    mark_fail "$key" "Hot bandwidth dropped ${drop}% from cold, exceeding ${BW_MAX_DROP_PERCENT}%."
  else
    mark_pass "$key" "Hot bandwidth change (${drop}%) is within the configured ${BW_MAX_DROP_PERCENT}% limit."
  fi
}

compare_bandwidth_pair \
  "bw_compare_htod" \
  "H2D cold/hot comparison" \
  "${TEST_LOG[bw_cold_htod]}" \
  "${TEST_LOG[bw_hot_htod]}"

compare_bandwidth_pair \
  "bw_compare_dtoh" \
  "D2H cold/hot comparison" \
  "${TEST_LOG[bw_cold_dtoh]}" \
  "${TEST_LOG[bw_hot_dtoh]}"

# Kernel-log review
register_test "kernel_log" "Kernel NVIDIA/Xid/AER review" "$DMESG_LOG"
if [[ "$REQUIRE_DMESG" == "0" ]]; then
  mark_skipped "kernel_log" "Kernel-log review was disabled by configuration."
elif [[ ! -s "$DMESG_LOG" ]]; then
  mark_incomplete "kernel_log" "dmesg capture is missing or empty."
else
  DMESG_FAIL_PATTERN='(NVRM:.*Xid[[:space:]]*\(|NVRM:.*Xid[[:space:]]+[0-9]+|GPU .* has fallen off the bus|RmInitAdapter failed|nvidia.*PCIe.*(error|fault|fatal)|nvidia-modeset:.*ERROR|PCIe Bus Error: severity=(Uncorrected|Fatal)|AER:.*(Uncorrected|Fatal))'
  if grep -Eai "$DMESG_FAIL_PATTERN" "$DMESG_LOG" >/dev/null; then
    mark_fail "kernel_log" "Kernel log contains NVIDIA Xid, fallen-off-bus, fatal PCIe/AER, or NVIDIA driver fault signatures."
  else
    mark_pass "kernel_log" "No strict NVIDIA/Xid/fatal PCIe fault signature appeared during the run."
  fi
fi

# Optional temperature threshold. Telemetry format places temperature.gpu at
# field 7 in both the full and fallback field sets used by this script.
register_test "temperature" "Configured GPU temperature limit" "$TELEMETRY_FILE"
if [[ ! -s "$TELEMETRY_FILE" ]]; then
  mark_incomplete "temperature" "NVIDIA telemetry is missing or empty."
else
  MAX_OBSERVED_TEMP="$(awk -F',' '
    /^#/ { next }
    {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $7)
      if ($7 ~ /^[0-9]+([.][0-9]+)?$/ && ($7+0) > max) max=$7+0
    }
    END { if (max != "") print max }
  ' "$TELEMETRY_FILE")"

  if [[ -z "$MAX_OBSERVED_TEMP" ]]; then
    mark_incomplete "temperature" "Could not parse GPU temperature from telemetry."
  elif (( MAX_GPU_TEMP_C == 0 )); then
    mark_pass "temperature" "Maximum observed GPU temperature was ${MAX_OBSERVED_TEMP} C; automatic limit disabled."
  elif awk -v observed="$MAX_OBSERVED_TEMP" -v limit="$MAX_GPU_TEMP_C" 'BEGIN { exit !(observed > limit) }'; then
    mark_fail "temperature" "Maximum observed GPU temperature ${MAX_OBSERVED_TEMP} C exceeded the configured ${MAX_GPU_TEMP_C} C limit."
  else
    mark_pass "temperature" "Maximum observed GPU temperature ${MAX_OBSERVED_TEMP} C was within the configured limit."
  fi
fi

# ----------------------------
# Final summary
# ----------------------------
FAIL_COUNT=0
INCOMPLETE_COUNT=0
PASS_COUNT=0
SKIPPED_COUNT=0

{
  echo
  echo "==================== TEST RESULTS ===================="
} | tee -a "$SUMMARY_FILE"

RESULT_KEYS=(
  device_query
  vector_add
  bw_cold_baseline
  bw_cold_htod
  bw_cold_dtoh
  gpu_burn
)
if [[ "$RUN_TENSOR_TEST" == "1" ]]; then
  RESULT_KEYS+=(tensor_burn)
fi
RESULT_KEYS+=(
  bw_hot_baseline
  bw_hot_htod
  bw_hot_dtoh
  bw_compare_htod
  bw_compare_dtoh
  cuda_memtest
  vulkan
  kernel_log
  temperature
)

for key in "${RESULT_KEYS[@]}"; do
  status="${TEST_STATUS[$key]:-INCOMPLETE}"
  label="${TEST_LABEL[$key]:-$key}"
  reason="${TEST_REASON[$key]:-No classification was generated.}"
  printf '[%-10s] %s - %s\n' "$status" "$label" "$reason" | tee -a "$SUMMARY_FILE"

  case "$status" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    SKIPPED) SKIPPED_COUNT=$((SKIPPED_COUNT + 1)) ;;
    *) INCOMPLETE_COUNT=$((INCOMPLETE_COUNT + 1)) ;;
  esac
done

{
  echo
  echo "==================== RESULT ===================="
  echo "PASS checks: $PASS_COUNT"
  echo "FAIL checks: $FAIL_COUNT"
  echo "INCOMPLETE checks: $INCOMPLETE_COUNT"
  echo "SKIPPED checks: $SKIPPED_COUNT"
  echo "Run directory: $RUN_DIR"
} | tee -a "$SUMMARY_FILE"

if (( FAIL_COUNT > 0 )); then
  echo "RESULT: FAIL" | tee -a "$SUMMARY_FILE"
  exit 2
elif (( INCOMPLETE_COUNT > 0 )); then
  echo "RESULT: INCOMPLETE" | tee -a "$SUMMARY_FILE"
  exit 3
else
  echo "RESULT: PASS" | tee -a "$SUMMARY_FILE"
  exit 0
fi