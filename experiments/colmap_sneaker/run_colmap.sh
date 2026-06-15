#!/usr/bin/env bash
#
# COLMAP Structure-from-Motion experiment on the 8 Adidas Tokyo product stills.
#
# Follows the official COLMAP tutorial (https://colmap.github.io/tutorial.html)
# Structure-from-Motion stage: feature extraction -> matching -> incremental
# mapping -> model analysis.
#
# Purpose: empirically test whether the 8 retail product photos can be posed
# (registered) by classic SfM -- the prerequisite for an optimisation-based
# 3DGS reconstruction. This is the "other paradigm" alternative to TripoSplat's
# single-image feed-forward generation.
#
# Dense MVS (patch_match_stereo / stereo_fusion) is intentionally skipped: it
# requires CUDA, which is unavailable on Apple Silicon. The sparse stage is the
# decisive diagnostic anyway -- if the views don't even match, dense is moot.
#
# Apple Silicon notes (COLMAP 4.0.4 via Homebrew, built WITHOUT CUDA):
#   * Feature extraction: CPU SIFT (use_gpu=0) -- deterministic, always works.
#   * Feature matching:   GPU SIFT via OpenGL (use_gpu=1). The CPU matcher
#     (use_gpu=0) crashes with SIGTRAP / "Trace/BPT trap: 5" on this build, so
#     we use the OpenGL matcher, which runs fine under the user's GUI session.
#
# Usage:  bash run_colmap.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES="$HERE/images"
WORK="$HERE/workspace"
DB="$WORK/database.db"
SPARSE="$WORK/sparse"
LOG="$WORK/colmap_run.log"

EXTRACT_GPU=0   # CPU SIFT extraction (deterministic)
MATCH_GPU=1     # OpenGL SIFT matcher (CPU matcher crashes on this build)

mkdir -p "$WORK" "$SPARSE"
: > "$LOG"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "$(colmap --help 2>&1 | head -1)"
log "images: $(ls -1 "$IMAGES"/*.jpg 2>/dev/null | wc -l | tr -d ' ')   workspace: $WORK"

# Fresh run: COLMAP refuses to re-extract into an existing database.
rm -f "$DB"; rm -rf "$SPARSE"; mkdir -p "$SPARSE"

# ---------------------------------------------------------------------------
# 1) Feature detection and extraction
# ---------------------------------------------------------------------------
# Heterogeneous web photos (unknown/variable intrinsics, different crops/zoom),
# so every image gets its OWN camera (no shared intrinsics) with SIMPLE_RADIAL,
# COLMAP's default for unknown cameras.
log "step 1/5  feature_extractor (CPU SIFT)"
colmap feature_extractor \
  --database_path "$DB" \
  --image_path "$IMAGES" \
  --ImageReader.single_camera 0 \
  --ImageReader.camera_model SIMPLE_RADIAL \
  --FeatureExtraction.use_gpu $EXTRACT_GPU \
  >> "$LOG" 2>&1
log "       feature_extractor exit=$?"

# ---------------------------------------------------------------------------
# 2) Feature matching and geometric verification
# ---------------------------------------------------------------------------
# Only 8 images -> exhaustive matching (all 28 pairs) is cheap and thorough.
log "step 2/5  exhaustive_matcher (OpenGL SIFT)"
colmap exhaustive_matcher \
  --database_path "$DB" \
  --FeatureMatching.use_gpu $MATCH_GPU \
  >> "$LOG" 2>&1
log "       exhaustive_matcher exit=$?"

# ---------------------------------------------------------------------------
# 3) Report matches straight from the database (the decisive diagnostic).
#    If raw/verified matches are ~0, SfM cannot possibly register the views.
# ---------------------------------------------------------------------------
log "step 3/5  match report (raw vs geometrically verified)"
python3 - "$DB" <<'PY' 2>&1 | tee -a "$LOG"
import sqlite3, sys
db=sqlite3.connect(sys.argv[1]); c=db.cursor()
names={r[0]:r[1] for r in c.execute("SELECT image_id,name FROM images")}
# COLMAP pair_id = image_id1 * 2147483647 + image_id2
pair=lambda pid:(pid//2147483647, pid%2147483647)
def summarize(table):
    rows=list(c.execute(f"SELECT pair_id,rows FROM {table}"))
    nz=[(p,r) for p,r in rows if r>0]
    tot=sum(r for _,r in rows)
    print(f"  {table:20s}: {len(rows)} pairs total, {len(nz)} with >0, sum={tot}")
    for pid,r in sorted(nz,key=lambda x:-x[1])[:10]:
        a,b=pair(pid); print(f"      {names.get(a,a)} <-> {names.get(b,b)} : {r}")
summarize("matches")
summarize("two_view_geometries")
db.close()
PY

# ---------------------------------------------------------------------------
# 4) Sparse 3D reconstruction (incremental SfM)
# ---------------------------------------------------------------------------
log "step 4/5  mapper (incremental SfM)"
colmap mapper \
  --database_path "$DB" \
  --image_path "$IMAGES" \
  --output_path "$SPARSE" \
  >> "$LOG" 2>&1
log "       mapper exit=$?"

# ---------------------------------------------------------------------------
# 5) Analysis / report. COLMAP may produce several disconnected sub-models
#    (sparse/0, sparse/1, ...) or none at all.
# ---------------------------------------------------------------------------
log "step 5/5  model_analyzer"
NUM_MODELS=0
for M in "$SPARSE"/*/; do
  [ -d "$M" ] || continue
  NUM_MODELS=$((NUM_MODELS+1))
  log "---- sub-model: $M ----"
  colmap model_analyzer --path "$M" 2>&1 | tee -a "$LOG"
  colmap model_converter --input_path "$M" --output_path "$M" --output_type TXT >> "$LOG" 2>&1
  colmap model_converter --input_path "$M" --output_path "${M%/}.ply" --output_type PLY >> "$LOG" 2>&1
done

TOTAL_IMAGES=$(ls -1 "$IMAGES"/*.jpg 2>/dev/null | wc -l | tr -d ' ')
log "RESULT: input images = $TOTAL_IMAGES ; COLMAP produced $NUM_MODELS sparse sub-model(s)."
log "Done. Full log: $LOG"
