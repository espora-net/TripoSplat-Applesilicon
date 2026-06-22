#!/usr/bin/env bash
#
# COLMAP Structure-from-Motion on SYNTHETIC views rendered from the reference
# El Corte Ingles / Vyking GLB (the retail-quality 3D model the user set as the
# quality benchmark). This is the FRONT-END of a controlled coverage ablation:
# we render clean, flat-lit, plain-background views from the reference asset and
# push them through our own COLMAP -> OpenMVS pipeline to prove that, GIVEN full
# 360 coverage, the pipeline reaches retail quality -- i.e. the original sneaker
# defects (caved toe, untextured heel, multi-tone green) came from side-biased
# CAPTURE COVERAGE, not from the pipeline.
#
# Two synthetic sets (rendered by render_synthetic.py):
#   full  -> ~90 views, 3 elevation rings x 24 az + high/low rings + top + sole
#   side  -> ~27 views, a limited frontal-left arc (mimics the original video bias)
#
# HONEST FRAMING (rubber-duck-mandated): this is a PIPELINE-VALIDATION / coverage
# ablation on a copyrighted retail asset kept strictly local. It is NOT a claim of
# producing a superior or original asset (we already have the reference GLB), and
# NOT a photogrammetric recovery of the physical shoe.
#
# Apple Silicon notes (COLMAP 4.0.4 via Homebrew, no CUDA):
#   * CPU SIFT extraction (use_gpu=0) -- deterministic.
#   * OpenGL SIFT matcher  (use_gpu=1) -- the CPU matcher crashes (SIGTRAP).
#
# Usage:  bash run_colmap_synth.sh {full|side}
set -uo pipefail

PRESET="${1:-full}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HERE/synthetic_ref/$PRESET"
FRAMES="$ROOT/images"
WORK="$ROOT/ws"
DB="$WORK/database.db"
SPARSE="$WORK/sparse"
LOG="$WORK/colmap_synth.log"

EXTRACT_GPU=0
MATCH_GPU=1

[ -d "$FRAMES" ] || { echo "missing images dir: $FRAMES (run render_synthetic.py first)"; exit 1; }
mkdir -p "$WORK" "$SPARSE"
: > "$LOG"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "$(colmap --help 2>&1 | head -1)"
NF=$(ls -1 "$FRAMES"/*.jpg | wc -l | tr -d ' ')
log "preset=$PRESET  images=$NF  ($FRAMES)"

# Fresh run.
rm -f "$DB"; rm -rf "$SPARSE"; mkdir -p "$SPARSE"

# ---------------------------------------------------------------------------
# 1) Feature extraction. All synthetic views share ONE virtual pinhole camera
#    (identical intrinsics from the renderer) -> single_camera 1. The renders
#    are pinhole with no lens distortion, so SIMPLE_PINHOLE is the exact model.
# ---------------------------------------------------------------------------
log "step 1/4  feature_extractor (CPU SIFT, single shared PINHOLE camera)"
colmap feature_extractor \
  --database_path "$DB" \
  --image_path "$FRAMES" \
  --ImageReader.single_camera 1 \
  --ImageReader.camera_model SIMPLE_PINHOLE \
  --FeatureExtraction.use_gpu $EXTRACT_GPU \
  >> "$LOG" 2>&1
log "       feature_extractor exit=$?"

# ---------------------------------------------------------------------------
# 2) Exhaustive matching across all views (full 360 coverage -> cross-ring and
#    cross-azimuth correspondences fuse into a single model).
# ---------------------------------------------------------------------------
log "step 2/4  exhaustive_matcher (OpenGL SIFT)"
colmap exhaustive_matcher \
  --database_path "$DB" \
  --FeatureMatching.use_gpu $MATCH_GPU \
  >> "$LOG" 2>&1
log "       exhaustive_matcher exit=$?"

python3 - "$DB" <<'PY' 2>&1 | tee -a "$LOG"
import sqlite3, sys
db=sqlite3.connect(sys.argv[1]); c=db.cursor()
rows=[r for (_,r) in c.execute("SELECT pair_id,rows FROM two_view_geometries")]
nz=[r for r in rows if r>0]
print(f"  verified pairs: {len(nz)}/{len(rows)} with inliers, total={sum(rows)}, max={max(rows) if rows else 0}")
db.close()
PY

# ---------------------------------------------------------------------------
# 3) Incremental SfM. Deterministic (num_threads 1 + fixed seed). Clean
#    synthetic renders register easily, so we keep COLMAP's default inlier
#    thresholds (no relaxation needed, unlike the noisy AI video frames).
# ---------------------------------------------------------------------------
log "step 3/4  mapper (incremental SfM, deterministic)"
colmap mapper \
  --database_path "$DB" \
  --image_path "$FRAMES" \
  --output_path "$SPARSE" \
  --Mapper.num_threads 1 \
  --Mapper.random_seed 42 \
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
  log "exported point cloud: ${BEST%/}.ply"
fi

log "RESULT: $NF input views ; best model = $BEST_N registered images."
log "Done. Full log: $LOG"
echo "BEST_MODEL=$BEST"