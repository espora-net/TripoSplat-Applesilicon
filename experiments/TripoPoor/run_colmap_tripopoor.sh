#!/usr/bin/env bash
#
# COLMAP Structure-from-Motion on the TripoPoor capture: ~44 real phone photos
# (Samsung Galaxy S25+, 4000x3000) orbiting a single object.
#
# Unlike the AI-generated sneaker clips, this is a genuine multi-view photo
# capture, so classic SfM should register most/all views and yield a clean,
# metrically-consistent sparse model -- a solid basis for dense MVS (OpenMVS).
#
# Everything stays inside experiments/TripoPoor/:
#   images/            <- the 44 source photos (moved here on first run)
#   colmap/database.db
#   colmap/sparse/0    <- the sparse model (cameras/images/points3D)
#   colmap/colmap.log
#
# Apple Silicon notes (COLMAP via Homebrew, built WITHOUT CUDA):
#   * Feature extraction: CPU SIFT (use_gpu=0) -- deterministic, always works.
#   * Feature matching:   GPU SIFT via OpenGL (use_gpu=1); the CPU matcher
#     crashes with SIGTRAP on this build.
#   * Dense MVS is NOT done here (needs CUDA in COLMAP); we hand the sparse
#     model to OpenMVS (CPU) in run_openmvs.sh.
#
# Usage:  bash run_colmap_tripopoor.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES="$HERE/images"
WORK="$HERE/colmap"
DB="$WORK/database.db"
SPARSE="$WORK/sparse"
LOG="$WORK/colmap.log"

EXTRACT_GPU=0          # CPU SIFT extraction (deterministic)
MATCH_GPU=1            # OpenGL SIFT matcher (CPU matcher crashes on this build)
MAX_IMAGE_SIZE=3200    # SIFT working resolution (photos are 4000 wide)

mkdir -p "$WORK" "$SPARSE"
: > "$LOG"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

command -v colmap >/dev/null || { log "colmap not found (brew install colmap)"; exit 1; }

# ---------------------------------------------------------------------------
# 0) Stage images: move the root-level *.jpg into images/ (idempotent).
# ---------------------------------------------------------------------------
mkdir -p "$IMAGES"
shopt -s nullglob
ROOT_JPGS=("$HERE"/*.jpg "$HERE"/*.JPG)
if [ ${#ROOT_JPGS[@]} -gt 0 ]; then
  log "step 0/5  moving ${#ROOT_JPGS[@]} photos from TripoPoor/ into images/"
  mv -f "${ROOT_JPGS[@]}" "$IMAGES"/ 2>>"$LOG"
fi
shopt -u nullglob
NIMG=$(ls -1 "$IMAGES"/*.jpg "$IMAGES"/*.JPG 2>/dev/null | wc -l | tr -d ' ')
log "       images ready: $NIMG in $IMAGES"
[ "$NIMG" -gt 0 ] || { log "no images found; aborting"; exit 1; }

log "$(colmap --help 2>&1 | head -1)"

# Fresh run: COLMAP refuses to re-extract into an existing database.
rm -f "$DB"; rm -rf "$SPARSE"; mkdir -p "$SPARSE"

# ---------------------------------------------------------------------------
# 1) Feature extraction. All photos come from ONE physical camera (same phone,
#    same lens), so share intrinsics: single_camera 1 + SIMPLE_RADIAL.
# ---------------------------------------------------------------------------
log "step 1/5  feature_extractor (CPU SIFT, single shared camera)"
colmap feature_extractor \
  --database_path "$DB" \
  --image_path "$IMAGES" \
  --ImageReader.single_camera 1 \
  --ImageReader.camera_model SIMPLE_RADIAL \
  --FeatureExtraction.max_image_size $MAX_IMAGE_SIZE \
  --FeatureExtraction.use_gpu $EXTRACT_GPU \
  >> "$LOG" 2>&1
log "       feature_extractor exit=$?"

# ---------------------------------------------------------------------------
# 2) Exhaustive matching (44 images -> ~950 pairs, cheap and most robust).
# ---------------------------------------------------------------------------
log "step 2/5  exhaustive_matcher (OpenGL SIFT)"
colmap exhaustive_matcher \
  --database_path "$DB" \
  --FeatureMatching.use_gpu $MATCH_GPU \
  >> "$LOG" 2>&1
log "       exhaustive_matcher exit=$?"

# ---------------------------------------------------------------------------
# 3) Incremental sparse reconstruction.
# ---------------------------------------------------------------------------
log "step 3/5  mapper (incremental SfM)"
colmap mapper \
  --database_path "$DB" \
  --image_path "$IMAGES" \
  --output_path "$SPARSE" \
  >> "$LOG" 2>&1
log "       mapper exit=$?"

# ---------------------------------------------------------------------------
# 4) Analyse + export each sub-model to TXT and PLY.
# ---------------------------------------------------------------------------
log "step 4/5  model_analyzer + export"
NUM_MODELS=0
for M in "$SPARSE"/*/; do
  [ -d "$M" ] || continue
  NUM_MODELS=$((NUM_MODELS+1))
  log "---- sub-model: $M ----"
  colmap model_analyzer --path "$M" 2>&1 | tee -a "$LOG"
  colmap model_converter --input_path "$M" --output_path "$M" --output_type TXT >> "$LOG" 2>&1
  colmap model_converter --input_path "$M" --output_path "${M%/}.ply" --output_type PLY >> "$LOG" 2>&1
done

# ---------------------------------------------------------------------------
# 5) Result summary.
# ---------------------------------------------------------------------------
log "step 5/5  done"
log "RESULT: input images = $NIMG ; COLMAP produced $NUM_MODELS sparse sub-model(s)."
log "Largest model is the one to feed OpenMVS (see run_openmvs.sh)."
log "Full log: $LOG"
