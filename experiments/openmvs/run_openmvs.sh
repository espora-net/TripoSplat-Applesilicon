#!/usr/bin/env bash
#
# Full COLMAP -> OpenMVS dense pipeline, producing a TEXTURED 3D MESH you can
# open in Preview / QuickLook / MeshLab / Blender. CPU-only -- no CUDA -- so it
# runs natively on Apple Silicon (OpenMVS does the dense MVS that COLMAP itself
# can only do with CUDA).
#
# Stages (GPT-5.5 rubber-duck validated, official-doc aligned):
#   1.  colmap image_undistorter -> PINHOLE images + model (InterfaceCOLMAP
#       requires undistorted PINHOLE input; do NOT feed SIMPLE_RADIAL directly).
#   2.  InterfaceCOLMAP          -> scene.mvs
#   3.  DensifyPointCloud        -> scene_dense.mvs (+ .ply dense cloud)
#   4.  ReconstructMesh          -> scene_dense_mesh.ply (rough surface)
#   4b. RefineMesh (REFINE=1)    -> scene_dense_mesh_refine.ply (recovers detail +
#       cleans background flaps; the official "fine detail" step). REFINE=0 skips.
#   5.  TextureMesh              -> *_textured.obj/.ply (the viewable asset),
#       textured from the FULL-RES scene.mvs for a sharper atlas.
#
# Get the OpenMVS binaries first (Apple Silicon -> official prebuilt, seconds):
#       bash ../openmvs/get_openmvs.sh
# (fallback, from source, ~1-2 h:  bash ../openmvs/build_openmvs.sh)
#
# Usage:
#   bash run_openmvs.sh sneaker      # the 91-view Adidas Tokyo COLMAP model
#   bash run_openmvs.sh tripopoor    # the TripoPoor capture (largest HQ model)
#   OPENMVS_BIN=/path bash run_openmvs.sh <preset>
#   REFINE=0 bash run_openmvs.sh <preset>          # skip RefineMesh (faster)
#   SEAM_LEVELING=1 bash run_openmvs.sh <preset>   # restore OpenMVS seam leveling
set -uo pipefail

PRESET="${1:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
EXP="$REPO/experiments"

# ---- locate the OpenMVS binaries ------------------------------------------
# Preference: explicit OPENMVS_BIN > official prebuilt (get_openmvs.sh) >
#             from-source vcpkg build (build_openmvs.sh).
BUILD_ROOT="${OPENMVS_BUILD_ROOT:-$HOME/.cache/openmvs-build}"
OPENMVS_BIN="${OPENMVS_BIN:-$HERE/prebuilt}"
if [ ! -x "$OPENMVS_BIN/DensifyPointCloud" ]; then
  for cand in "$HERE/prebuilt" "$BUILD_ROOT/openMVS/build-arm64/bin/OpenMVS"; do
    [ -x "$cand/DensifyPointCloud" ] && { OPENMVS_BIN="$cand"; break; }
  done
fi
if [ ! -x "$OPENMVS_BIN/DensifyPointCloud" ]; then
  found="$(find "$HERE/prebuilt" "$BUILD_ROOT" -name DensifyPointCloud -type f 2>/dev/null | head -1)"
  [ -n "$found" ] && OPENMVS_BIN="$(dirname "$found")"
fi

# ---- per-dataset presets ---------------------------------------------------
case "$PRESET" in
  sneaker)
    COLMAP_MODEL="$EXP/colmap_sneaker/ws_all/sparse/2"
    COLMAP_IMAGES="$EXP/colmap_sneaker/frames_all"
    OUT="$EXP/colmap_sneaker/openmvs"
    UNDISTORT_MAX=1600      # frames are 720x1280; keep near native
    DENSIFY_MAX=1600
    RES_LEVEL=1
    ;;
  tripopoor)
    # Prefer the high-quality model; fall back to the fast one.
    COLMAP_MODEL="$EXP/TripoPoor/colmap_hq/sparse/0"
    [ -d "$COLMAP_MODEL" ] || COLMAP_MODEL="$EXP/TripoPoor/colmap/sparse/0"
    COLMAP_IMAGES="$EXP/TripoPoor/images"
    OUT="$EXP/TripoPoor/openmvs"
    UNDISTORT_MAX=2400      # photos are 4000x3000; 2400 caps RAM/time on CPU
    DENSIFY_MAX=2400
    RES_LEVEL=1
    ;;
  *)
    echo "usage: bash run_openmvs.sh {sneaker|tripopoor}"; exit 2 ;;
esac

LOG_DIR="$OUT"; mkdir -p "$OUT"
LOG="$OUT/openmvs.log"; : > "$LOG"
log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "preset=$PRESET"
log "OpenMVS bin: $OPENMVS_BIN"
[ -x "$OPENMVS_BIN/DensifyPointCloud" ] || { log "OpenMVS binaries not found -> run ../openmvs/get_openmvs.sh (prebuilt) or build_openmvs.sh"; exit 1; }
command -v colmap >/dev/null || { log "colmap missing"; exit 1; }
[ -d "$COLMAP_MODEL" ] || { log "COLMAP model not found: $COLMAP_MODEL"; exit 1; }
log "COLMAP model: $COLMAP_MODEL   images: $COLMAP_IMAGES"

UND="$OUT/undistorted"
SCENE="$OUT/scene.mvs"

# ---------------------------------------------------------------------------
# 1) Undistort to PINHOLE (required by InterfaceCOLMAP).
# ---------------------------------------------------------------------------
log "step 1/5  colmap image_undistorter (max_image_size=$UNDISTORT_MAX)"
rm -rf "$UND"; mkdir -p "$UND"
colmap image_undistorter \
  --image_path "$COLMAP_IMAGES" \
  --input_path "$COLMAP_MODEL" \
  --output_path "$UND" \
  --output_type COLMAP \
  --max_image_size "$UNDISTORT_MAX" \
  >> "$LOG" 2>&1
log "       image_undistorter exit=$?"

# ---------------------------------------------------------------------------
# 2) COLMAP -> OpenMVS scene.
# ---------------------------------------------------------------------------
log "step 2/5  InterfaceCOLMAP"
"$OPENMVS_BIN/InterfaceCOLMAP" \
  -i "$UND" \
  -o "$SCENE" \
  -w "$OUT" \
  --image-folder "$UND/images" \
  >> "$LOG" 2>&1
log "       InterfaceCOLMAP exit=$?  -> $(ls -la "$SCENE" 2>/dev/null | awk '{print $5}') bytes"

# ---------------------------------------------------------------------------
# 3) Dense point cloud (the heavy CPU stage).
# ---------------------------------------------------------------------------
log "step 3/5  DensifyPointCloud (resolution-level=$RES_LEVEL max-resolution=$DENSIFY_MAX)"
"$OPENMVS_BIN/DensifyPointCloud" "$SCENE" \
  -w "$OUT" \
  -o "$OUT/scene_dense.mvs" \
  --resolution-level "$RES_LEVEL" \
  --max-resolution "$DENSIFY_MAX" \
  --number-views 5 \
  --number-views-fuse 3 \
  >> "$LOG" 2>&1
log "       DensifyPointCloud exit=$?"

# ---------------------------------------------------------------------------
# 4) Surface mesh from the dense cloud.
# ---------------------------------------------------------------------------
log "step 4/6  ReconstructMesh"
"$OPENMVS_BIN/ReconstructMesh" "$OUT/scene_dense.mvs" \
  -p "$OUT/scene_dense.ply" \
  -w "$OUT" \
  -o "$OUT/scene_dense_mesh.mvs" \
  --decimate 1 \
  --remove-spurious 20 \
  --close-holes 30 \
  --smooth 2 \
  >> "$LOG" 2>&1
log "       ReconstructMesh exit=$?"

# ---------------------------------------------------------------------------
# 4b) RefineMesh (optional, ON by default) -- the official "recover all fine
#     details" step (https://github.com/cdcseacave/openMVS/wiki/Usage). It
#     optimizes the mesh against the images AND cleans it: on the sneaker it took
#     the dense mesh from 210k -> ~73k faces, removing the disconnected
#     background flaps/spikes and tightening the silhouette while keeping the
#     shoe, and the magenta 3-stripes became coherent. Set REFINE=0 to skip
#     (faster; textures the raw dense mesh instead).
# ---------------------------------------------------------------------------
REFINE="${REFINE:-1}"
MESH="$OUT/scene_dense_mesh.ply"
if [ "$REFINE" = "1" ]; then
  log "step 4b/6 RefineMesh (REFINE=1; set REFINE=0 to skip)"
  "$OPENMVS_BIN/RefineMesh" \
    -i "$OUT/scene.mvs" \
    -m "$OUT/scene_dense_mesh.ply" \
    -o "$OUT/scene_dense_mesh_refine.mvs" \
    --resolution-level 1 \
    --scales 1 \
    --max-face-area 16 \
    --close-holes 60 \
    >> "$LOG" 2>&1
  log "       RefineMesh exit=$?"
  [ -f "$OUT/scene_dense_mesh_refine.ply" ] && MESH="$OUT/scene_dense_mesh_refine.ply"
fi

# ---------------------------------------------------------------------------
# 5) Texture the mesh -> viewable .obj (+ .mtl + texture) and .ply.
#    Texture from the FULL-RES scene.mvs (NOT the half-res scene_dense.mvs):
#    DensifyPointCloud downscales the working images (level 1 -> ~1/4 the
#    pixels), so pulling the texture from scene.mvs gives a noticeably sharper
#    atlas. ReconstructMesh/RefineMesh only write the mesh .ply, so the mesh is
#    fed explicitly with -m (= the refined mesh when REFINE=1).
#
#    SEAM LEVELING OFF (SEAM_LEVELING=0, the default here): OpenMVS' global +
#    local seam-leveling blew up to vivid saturated color blobs (pure
#    red/blue/green/cyan/magenta) painted over the real photographic patches --
#    on BOTH the AI-frame and the real-photo datasets. Disabling it yields the
#    true photographic texture (visible patch seams instead). Set
#    SEAM_LEVELING=1 to restore OpenMVS' default leveling.
# ---------------------------------------------------------------------------
SEAM="${SEAM_LEVELING:-0}"
log "step 5/6  TextureMesh (from full-res scene.mvs; mesh=$(basename "$MESH"); seam-leveling=$SEAM)"
"$OPENMVS_BIN/TextureMesh" \
  -i "$OUT/scene.mvs" \
  -m "$MESH" \
  -w "$OUT" \
  -o "$OUT/scene_textured.mvs" \
  --resolution-level 0 \
  --max-texture-size 8192 \
  --global-seam-leveling "$SEAM" \
  --local-seam-leveling "$SEAM" \
  --empty-color 8421504 \
  --export-type obj \
  >> "$LOG" 2>&1
log "       TextureMesh exit=$?"

log "DONE. Artifacts in $OUT:"
ls -lh "$OUT"/*.ply "$OUT"/*.obj 2>/dev/null | tee -a "$LOG"
log "View: open the textured .obj in Preview/QuickLook, MeshLab or Blender;"
log "      or the dense .ply in MeshLab. Full log: $LOG"
