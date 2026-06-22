#!/usr/bin/env bash
#
# Build OpenMVS natively on Apple Silicon (arm64) using vcpkg for an ISOLATED,
# OpenMVS-compatible dependency universe.
#
# Why vcpkg and not Homebrew libs: this Mac's Homebrew stack is bleeding-edge
# (Eigen 5.0.1, CGAL 6.2, Boost 1.90) which OpenMVS does NOT support -- it
# targets Eigen 3.4 / CGAL 5.x. vcpkg (manifest mode, driven by OpenMVS's own
# vcpkg.json) fetches and builds a consistent Eigen 3.4 + CGAL + OpenCV + Boost
# + VCG set, side-stepping the whole incompatibility. (GPT-5.5 rubber-duck:
# ranked vcpkg-isolated native build as the most reliable path; container 2nd.)
#
# This is a LONG first build (vcpkg compiles OpenCV/CGAL/Boost from source):
# expect ~1-2 h and several GB under $OPENMVS_BUILD_ROOT. Everything heavy lives
# OUTSIDE the repo (default ~/.cache/openmvs-build) so the worktree stays clean.
#
# Result binaries: $OPENMVS_BUILD_ROOT/openMVS/build-arm64/bin/OpenMVS/
#   InterfaceCOLMAP DensifyPointCloud ReconstructMesh RefineMesh TextureMesh ...
#
# Usage:  bash build_openmvs.sh           # build
#         OPENMVS_BUILD_ROOT=/path bash build_openmvs.sh
set -uo pipefail

BUILD_ROOT="${OPENMVS_BUILD_ROOT:-$HOME/.cache/openmvs-build}"
JOBS="${JOBS:-8}"
mkdir -p "$BUILD_ROOT"
LOG="$BUILD_ROOT/build.log"
: > "$LOG"
log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "OpenMVS build root: $BUILD_ROOT  (jobs=$JOBS)"
command -v cmake >/dev/null || { log "cmake missing"; exit 1; }
command -v ninja >/dev/null || log "warning: ninja not found; install with 'brew install ninja'"

# ---------------------------------------------------------------------------
# 1) vcpkg (dependency manager). Bootstrap once.
# ---------------------------------------------------------------------------
if [ ! -x "$BUILD_ROOT/vcpkg/vcpkg" ]; then
  log "cloning + bootstrapping vcpkg"
  rm -rf "$BUILD_ROOT/vcpkg"
  git clone https://github.com/microsoft/vcpkg.git "$BUILD_ROOT/vcpkg" >>"$LOG" 2>&1
  "$BUILD_ROOT/vcpkg/bootstrap-vcpkg.sh" -disableMetrics >>"$LOG" 2>&1
fi
export VCPKG_ROOT="$BUILD_ROOT/vcpkg"
log "vcpkg ready: $($VCPKG_ROOT/vcpkg version 2>/dev/null | head -1)"

# ---------------------------------------------------------------------------
# 2) OpenMVS source (its vcpkg.json drives manifest-mode dependency install).
# ---------------------------------------------------------------------------
if [ ! -d "$BUILD_ROOT/openMVS/.git" ]; then
  log "cloning openMVS (recursive)"
  git clone --recursive https://github.com/cdcseacave/openMVS.git "$BUILD_ROOT/openMVS" >>"$LOG" 2>&1
fi
cd "$BUILD_ROOT/openMVS"
log "openMVS at $(git rev-parse --short HEAD 2>/dev/null)"

# ---------------------------------------------------------------------------
# 3) Configure. vcpkg manifest mode auto-installs Eigen3.4/CGAL/OpenCV/Boost/
#    VCG/etc into the build. CUDA/SiftGPU/python OFF (CPU-only on Mac); the
#    viewer feature is NOT a default vcpkg feature, so its GUI deps are skipped.
# ---------------------------------------------------------------------------
log "cmake configure (vcpkg manifest install of deps -- the long part)"
cmake -S . -B build-arm64 -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
  -DVCPKG_TARGET_TRIPLET=arm64-osx \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DOpenMVS_USE_CUDA=OFF \
  -DOpenMVS_USE_SIFTGPU=OFF \
  -DOpenMVS_USE_PYTHON=OFF \
  >>"$LOG" 2>&1
cfg=$?
log "configure exit=$cfg"
[ $cfg -eq 0 ] || { log "CONFIGURE FAILED -- inspect $LOG (likely a vcpkg port build error)"; exit 1; }

# ---------------------------------------------------------------------------
# 4) Build.
# ---------------------------------------------------------------------------
log "cmake build -j$JOBS"
cmake --build build-arm64 -j "$JOBS" >>"$LOG" 2>&1
b=$?
log "build exit=$b"
[ $b -eq 0 ] || { log "BUILD FAILED -- inspect $LOG"; exit 1; }

# ---------------------------------------------------------------------------
# 5) Report.
# ---------------------------------------------------------------------------
BIN="$BUILD_ROOT/openMVS/build-arm64/bin/OpenMVS"
[ -d "$BIN" ] || BIN="$(dirname "$(find "$BUILD_ROOT/openMVS/build-arm64" -name DensifyPointCloud -type f 2>/dev/null | head -1)")"
log "OpenMVS binaries in: $BIN"
ls -la "$BIN" 2>&1 | tee -a "$LOG"
log "DONE. Point run_openmvs.sh at OPENMVS_BIN=$BIN"
