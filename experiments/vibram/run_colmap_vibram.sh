#!/usr/bin/env bash
#
# COLMAP SfM for the Vibram capture (5 handheld WhatsApp clips of ONE shoe that is
# REPOSITIONED between clips).  The critical difference vs run_colmap_photos.sh:
# we pass --ImageReader.mask_path so SIFT only fires on the SHOE, never the wood
# floor.  Without this the static floor dominates SfM and the (apparently moving)
# shoe can't be reconstructed; with it, COLMAP sees one rigid object across all
# clips and can fuse them.
#
# Also tuned for LOW-PARALLAX, LOW-RES handheld video (deterministic, relaxed
# registration thresholds) exactly like the validated run_colmap_video.sh.
#
# Usage:  bash run_colmap_vibram.sh
# Output: recon/colmap_ws/{images-> ,sparse/0}  ready for OpenMVS photos preset.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES="$HERE/recon/images_orig"
MASKS="$HERE/recon/masks_colmap"          # <image_name>.png, 0=ignore (floor)
WS="${WS:-$HERE/recon/colmap_ws}"
mkdir -p "$WS"; WS="$(cd "$WS" && pwd)"

CAMERA_MODEL="${CAMERA_MODEL:-SIMPLE_RADIAL}"  # robust for low-res; OPENCV unstable here
SINGLE_CAMERA="${SINGLE_CAMERA:-1}"            # all frames forced to 848x478, same phone
EXTRACT_GPU="${EXTRACT_GPU:-1}"                # OpenGL SIFT
MATCH_GPU="${MATCH_GPU:-1}"
MATCHER="${MATCHER:-exhaustive_matcher}"       # needed to fuse the 5 separate clips

DB="$WS/database.db"
SPARSE_RAW="$WS/sparse_raw"
SPARSE="$WS/sparse"
LOG="$WS/colmap_vibram.log"
log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

: > "$LOG"
[ -e "$WS/images" ] || ln -s "$IMAGES" "$WS/images"
NF=$(find -L "$WS/images" -type f -iname '*.jpg' | wc -l | tr -d ' ')
NM=$(find -L "$MASKS" -type f -iname '*.png' | wc -l | tr -d ' ')
log "frames=$NF  masks=$NM  camera=$CAMERA_MODEL single_camera=$SINGLE_CAMERA matcher=$MATCHER  ws=$WS"
[ "$NF" -ge 8 ] || { log "too few frames ($NF)"; exit 1; }

log "step 1/4  feature_extractor (masked: floor ignored)"
colmap feature_extractor \
  --database_path "$DB" \
  --image_path "$WS/images" \
  --ImageReader.mask_path "$MASKS" \
  --ImageReader.single_camera "$SINGLE_CAMERA" \
  --ImageReader.camera_model "$CAMERA_MODEL" \
  --FeatureExtraction.use_gpu "$EXTRACT_GPU" \
  --SiftExtraction.max_num_features 16384 \
  >> "$LOG" 2>&1
log "       feature_extractor exit=$?"

log "step 2/4  $MATCHER (GPU/OpenGL SIFT)"
colmap "$MATCHER" \
  --database_path "$DB" \
  --FeatureMatching.use_gpu "$MATCH_GPU" \
  --FeatureMatching.guided_matching 1 \
  >> "$LOG" 2>&1
log "       $MATCHER exit=$?"

log "step 3/4  mapper (deterministic, low-parallax thresholds)"
rm -rf "$SPARSE_RAW"; mkdir -p "$SPARSE_RAW"
colmap mapper \
  --database_path "$DB" \
  --image_path "$WS/images" \
  --output_path "$SPARSE_RAW" \
  --Mapper.random_seed 42 \
  --Mapper.num_threads 1 \
  --Mapper.init_min_num_inliers 50 \
  --Mapper.abs_pose_min_num_inliers 15 \
  --Mapper.abs_pose_min_inlier_ratio 0.15 \
  --Mapper.min_num_matches 12 \
  >> "$LOG" 2>&1
log "       mapper exit=$?"

log "step 4/4  selecting best sub-model -> $SPARSE/0"
best=""; best_n=-1
for d in "$SPARSE_RAW"/*/; do
  [ -f "$d/cameras.bin" ] || continue
  n=$(colmap model_analyzer --path "$d" 2>&1 | grep -oE "Registered images: [0-9]+" | grep -oE "[0-9]+$" | head -1)
  n="${n:-0}"
  log "       sub-model $(basename "$d"): $n images"
  if [ "$n" -gt "$best_n" ]; then best_n="$n"; best="$d"; fi
done
[ -n "$best" ] || { log "ERROR: no model. See $LOG"; exit 1; }
rm -rf "$SPARSE"; mkdir -p "$SPARSE/0"
cp "$best"cameras.bin "$best"images.bin "$best"points3D.bin "$SPARSE/0/"

log "RESULT: best = $best_n/$NF frames registered -> $SPARSE/0"
log "model stats:"; colmap model_analyzer --path "$SPARSE/0" 2>&1 | tee -a "$LOG"
log "Next: PHOTOS_WS=\"$WS\" COLMAP_IMAGES=\"$IMAGES\" MASKS=\"$HERE/recon/masks\" QUALITY=max COLOR_NORM=1 bash $(cd "$HERE/../openmvs" && pwd)/run_openmvs.sh photos"
echo "PHOTOS_WS=$WS"
