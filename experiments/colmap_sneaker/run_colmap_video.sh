#!/usr/bin/env bash
#
# COLMAP Structure-from-Motion on FRAMES EXTRACTED FROM TWO ORBIT/ZOOM VIDEOS
# of the Adidas Tokyo sneaker.
#
# This is the follow-up to run_colmap.sh (which ran on 8 disparate product
# stills and FAILED: 0 matches across all 28 pairs). Here we instead use frames
# sampled from two short videos where the sneaker is seen in motion -- i.e. an
# actual multi-view capture with high frame-to-frame overlap, which is exactly
# what Structure-from-Motion needs.
#
# Result (see README.md): COLMAP registers 91 of 96 frames into ONE coherent
# sparse model (1277 cross-clip points fuse the two videos) with sub-pixel
# reprojection error and a clean recovered camera arc -- a usable posed
# multi-view dataset, the prerequisite for an optimisation-based 3D Gaussian
# Splatting reconstruction.
#
# HONEST CAVEAT: both videos are AI-GENERATED ("Animate Keyframes" keyframe
# interpolations), not real camera footage. This shows the synthetic frames are
# internally multi-view-consistent enough for SfM; it does NOT prove the physical
# shoe is photogrammetrically recoverable. See README.md "Part B".
#
# Apple Silicon notes (COLMAP 4.0.4 via Homebrew, no CUDA):
#   * CPU SIFT extraction (use_gpu=0) -- deterministic.
#   * OpenGL SIFT matcher  (use_gpu=1) -- the CPU matcher crashes (SIGTRAP).
#   * Dense MVS is unavailable without CUDA; sparse SfM is the ceiling on macOS.
#
# Usage:  bash run_colmap_video.sh [FPS]      (default FPS=6)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIDEO_DIR="$HERE/../../static/example_inputs/multiview/adidas_tokyo_sneaker"
SIDE="$VIDEO_DIR/Animate Keyframes - a side iew of adidas sneaker.mp4"
ZOOM="$VIDEO_DIR/Animate Keyframes - a zoom into addidas sneaker.mp4"
FPS="${1:-6}"

FRAMES="$HERE/frames_all"
WORK="$HERE/ws_all"
DB="$WORK/database.db"
SPARSE="$WORK/sparse"
LOG="$WORK/colmap_video.log"

EXTRACT_GPU=0
MATCH_GPU=1

mkdir -p "$FRAMES" "$WORK" "$SPARSE"
: > "$LOG"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

command -v ffmpeg >/dev/null || { log "ffmpeg not found (brew install ffmpeg)"; exit 1; }
[ -f "$SIDE" ] || { log "missing video: $SIDE"; exit 1; }
[ -f "$ZOOM" ] || { log "missing video: $ZOOM"; exit 1; }

log "$(colmap --help 2>&1 | head -1)"

# ---------------------------------------------------------------------------
# 0) Extract frames from both videos at FPS into one folder (a 'zoom_' and a
#    'side_' prefix keeps them distinct; both contribute to a single model).
# ---------------------------------------------------------------------------
log "step 0/4  extracting frames @ ${FPS} fps from both videos"
rm -f "$FRAMES"/*.jpg
ffmpeg -y -i "$ZOOM" -vf "fps=${FPS}" -q:v 2 "$FRAMES/zoom_%03d.jpg" >>"$LOG" 2>&1
ffmpeg -y -i "$SIDE" -vf "fps=${FPS}" -q:v 2 "$FRAMES/side_%03d.jpg" >>"$LOG" 2>&1
NF=$(ls -1 "$FRAMES"/*.jpg | wc -l | tr -d ' ')
log "       extracted $NF frames into $FRAMES"

# Fresh run.
rm -f "$DB"; rm -rf "$SPARSE"; mkdir -p "$SPARSE"

# ---------------------------------------------------------------------------
# 1) Feature extraction. All frames share ONE physical camera (same lens
#    throughout each clip) -> single_camera 1, SIMPLE_RADIAL.
# ---------------------------------------------------------------------------
log "step 1/4  feature_extractor (CPU SIFT, single shared camera)"
colmap feature_extractor \
  --database_path "$DB" \
  --image_path "$FRAMES" \
  --ImageReader.single_camera 1 \
  --ImageReader.camera_model SIMPLE_RADIAL \
  --FeatureExtraction.use_gpu $EXTRACT_GPU \
  >> "$LOG" 2>&1
log "       feature_extractor exit=$?"

# ---------------------------------------------------------------------------
# 2) Exhaustive matching: with ~96 frames this finds BOTH the temporal
#    (within-clip) and the cross-clip correspondences that fuse the two videos
#    into a single model. (sequential_matcher works per-clip but won't bridge
#    the two videos, so it yields fragments; exhaustive ties them together.)
# ---------------------------------------------------------------------------
log "step 2/4  exhaustive_matcher (OpenGL SIFT)"
colmap exhaustive_matcher \
  --database_path "$DB" \
  --FeatureMatching.use_gpu $MATCH_GPU \
  >> "$LOG" 2>&1
log "       exhaustive_matcher exit=$?"

# match report
python3 - "$DB" <<'PY' 2>&1 | tee -a "$LOG"
import sqlite3, sys
db=sqlite3.connect(sys.argv[1]); c=db.cursor()
rows=[r for (_,r) in c.execute("SELECT pair_id,rows FROM two_view_geometries")]
nz=[r for r in rows if r>0]
print(f"  verified pairs: {len(nz)}/{len(rows)} with inliers, total={sum(rows)}, max={max(rows) if rows else 0}")
db.close()
PY

# ---------------------------------------------------------------------------
# 3) Incremental SfM.
#    The mapper is non-deterministic by default (RANSAC + multithreading +
#    initial-pair choice), and on this data it sometimes fragments into small
#    models. We make it reproducible and robust:
#      * num_threads 1 + fixed random_seed  -> deterministic.
#      * lower init / absolute-pose inlier thresholds -> reliably grows ONE big
#        model (the zoom clip has many high-overlap but low-parallax pairs; the
#        laxer thresholds let the cross-video links pull ~90/96 frames in).
# ---------------------------------------------------------------------------
log "step 3/4  mapper (incremental SfM, deterministic)"
colmap mapper \
  --database_path "$DB" \
  --image_path "$FRAMES" \
  --output_path "$SPARSE" \
  --Mapper.num_threads 1 \
  --Mapper.random_seed 42 \
  --Mapper.init_min_num_inliers 50 \
  --Mapper.abs_pose_min_num_inliers 15 \
  --Mapper.abs_pose_min_inlier_ratio 0.15 \
  --Mapper.min_num_matches 12 \
  >> "$LOG" 2>&1
log "       mapper exit=$?"

# ---------------------------------------------------------------------------
# 4) Analyse every sub-model; export the LARGEST as PLY + TXT.
# ---------------------------------------------------------------------------
log "step 4/4  model_analyzer + export"
BEST=""; BEST_N=-1
for M in "$SPARSE"/*/; do
  [ -d "$M" ] || continue
  N=$(colmap model_analyzer --path "$M" 2>&1 | grep -E "Registered images:" | grep -oE "[0-9]+$" | head -1)
  N=${N:-0}
  log "  sub-model $M : $N registered images"
  if [ "$N" -gt "$BEST_N" ]; then BEST_N="$N"; BEST="$M"; fi
done

if [ -n "$BEST" ]; then
  log "BEST sub-model: $BEST ($BEST_N registered images)"
  colmap model_analyzer --path "$BEST" 2>&1 | grep -iE "Cameras:|Registered images:|Points:|Observations:|Mean track|Mean reproj" | tee -a "$LOG"
  colmap model_converter --input_path "$BEST" --output_path "${BEST%/}.ply" --output_type PLY >> "$LOG" 2>&1
  colmap model_converter --input_path "$BEST" --output_path "$BEST" --output_type TXT >> "$LOG" 2>&1
  log "exported point cloud: ${BEST%/}.ply  (+ cameras.txt/images.txt/points3D.txt)"
fi

log "RESULT: $NF input frames ; best model = $BEST_N registered images."
log "Done. Full log: $LOG"
