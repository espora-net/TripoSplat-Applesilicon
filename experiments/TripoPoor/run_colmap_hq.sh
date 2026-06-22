#!/usr/bin/env bash
#
# HIGH-QUALITY COLMAP pass for TripoPoor, to fix the fragmented first attempt.
#
# First pass (run_colmap_tripopoor.sh, fast defaults) registered only 13/44
# images and split into 2 disconnected sub-models: the object is a white
# reflective leather sneaker shot in DIM light against a plain background, so
# stable SIFT features are scarce and pairwise overlap is weak.
#
# This pass trades time for robustness (GPT-5.5 rubber-duck guidance):
#   * Full native resolution (max_image_size 4000, no downscale).
#   * More features: max_num_features 16384.
#   * Affine-shape estimation + domain-size pooling  -> ASIFT-like, far more
#     robust matches on hard/low-texture/specular surfaces (forces CPU SIFT).
#   * guided_matching during geometric verification.
#   * Slightly more permissive mapper thresholds to connect the orbit.
#
# Writes to a SEPARATE workspace (colmap_hq/) so an open COLMAP GUI on the
# original colmap/ model is left untouched. Camera + matching choices match
# the rubber-duck's advice (single_camera + SIMPLE_RADIAL; exhaustive matching).
#
# Usage:  bash run_colmap_hq.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES="$HERE/images"
WORK="$HERE/colmap_hq"
DB="$WORK/database.db"
SPARSE="$WORK/sparse"
LOG="$WORK/colmap_hq.log"

MAX_IMAGE_SIZE=4000     # full native resolution
MAX_FEATURES=16384      # denser keypoints for a low-texture object
MATCH_GPU=1             # OpenGL matcher (CPU matcher crashes on this build)

mkdir -p "$WORK" "$SPARSE"
: > "$LOG"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

command -v colmap >/dev/null || { log "colmap not found"; exit 1; }
NIMG=$(ls -1 "$IMAGES"/*.jpg "$IMAGES"/*.JPG 2>/dev/null | wc -l | tr -d ' ')
log "images: $NIMG   workspace: $WORK"
[ "$NIMG" -gt 0 ] || { log "no images in $IMAGES (run run_colmap_tripopoor.sh first to stage them)"; exit 1; }

rm -f "$DB"; rm -rf "$SPARSE"; mkdir -p "$SPARSE"

# ---------------------------------------------------------------------------
# 1) High-quality feature extraction (CPU SIFT: affine-shape + DSP need CPU).
# ---------------------------------------------------------------------------
log "step 1/4  feature_extractor (CPU SIFT, full-res, affine-shape + DSP)"
colmap feature_extractor \
  --database_path "$DB" \
  --image_path "$IMAGES" \
  --ImageReader.single_camera 1 \
  --ImageReader.camera_model SIMPLE_RADIAL \
  --FeatureExtraction.max_image_size $MAX_IMAGE_SIZE \
  --FeatureExtraction.use_gpu 0 \
  --SiftExtraction.max_num_features $MAX_FEATURES \
  --SiftExtraction.estimate_affine_shape 1 \
  --SiftExtraction.domain_size_pooling 1 \
  >> "$LOG" 2>&1
log "       feature_extractor exit=$?"

# ---------------------------------------------------------------------------
# 2) Exhaustive matching with guided matching (44 imgs -> ~950 pairs).
# ---------------------------------------------------------------------------
log "step 2/4  exhaustive_matcher (guided_matching)"
colmap exhaustive_matcher \
  --database_path "$DB" \
  --FeatureMatching.use_gpu $MATCH_GPU \
  --FeatureMatching.guided_matching 1 \
  >> "$LOG" 2>&1
log "       exhaustive_matcher exit=$?"

# Match connectivity report (how many pairs actually verified).
python3 - "$DB" <<'PY' 2>&1 | tee -a "$LOG"
import sqlite3, sys, statistics
db=sqlite3.connect(sys.argv[1]); c=db.cursor()
tv=[r for (r,) in c.execute("SELECT rows FROM two_view_geometries") if r and r>0]
print(f"  verified pairs with inliers: {len(tv)}  sum={sum(tv)}  "
      f"mean={statistics.mean(tv):.0f}" if tv else "  no verified pairs")
db.close()
PY

# ---------------------------------------------------------------------------
# 3) Incremental SfM with slightly more permissive thresholds to connect the
#    orbit into a single model.
# ---------------------------------------------------------------------------
log "step 3/4  mapper (permissive thresholds)"
colmap mapper \
  --database_path "$DB" \
  --image_path "$IMAGES" \
  --output_path "$SPARSE" \
  --Mapper.init_min_num_inliers 50 \
  --Mapper.abs_pose_min_num_inliers 20 \
  --Mapper.min_num_matches 10 \
  >> "$LOG" 2>&1
log "       mapper exit=$?"

# ---------------------------------------------------------------------------
# 4) Analyse + export each sub-model (TXT + PLY).
# ---------------------------------------------------------------------------
log "step 4/4  model_analyzer + export"
NUM_MODELS=0; BEST=""; BEST_N=0
for M in "$SPARSE"/*/; do
  [ -d "$M" ] || continue
  NUM_MODELS=$((NUM_MODELS+1))
  log "---- sub-model: $M ----"
  colmap model_analyzer --path "$M" 2>&1 | tee -a "$LOG"
  colmap model_converter --input_path "$M" --output_path "$M" --output_type TXT >> "$LOG" 2>&1
  colmap model_converter --input_path "$M" --output_path "${M%/}.ply" --output_type PLY >> "$LOG" 2>&1
  N=$(grep -c "^" "$M/images.txt" 2>/dev/null || echo 0)
  [ "$N" -gt "$BEST_N" ] && { BEST_N=$N; BEST="$M"; }
done

log "RESULT: input=$NIMG  sub-models=$NUM_MODELS  largest=$BEST"
log "Feed the largest model to OpenMVS (run_openmvs.sh)."
log "Full log: $LOG"
