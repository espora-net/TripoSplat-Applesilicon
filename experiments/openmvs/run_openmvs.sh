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
#   QUALITY=high bash run_openmvs.sh <preset>      # full-res densify+refine (most detail)
#   QUALITY=low  bash run_openmvs.sh <preset>      # quarter-res (fastest, coarse)
#   MASKS=<dir>  bash run_openmvs.sh <preset>      # drop background via fg masks
#   MASKS=none   bash run_openmvs.sh <preset>      # disable the preset's default masks
#   SMOOTH=6 bash run_openmvs.sh <preset>          # smoother surface (more Laplacian iters)
#   MASK_ERODE=6 bash run_openmvs.sh <preset>      # shave more silhouette "flaps"
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
    MASKS_DEFAULT="$EXP/colmap_sneaker/gsplat_dataset/masks"   # BiRefNet fg masks (96)
    ;;
  tripopoor)
    # Prefer the high-quality model; fall back to the fast one.
    COLMAP_MODEL="$EXP/TripoPoor/colmap_hq/sparse/0"
    [ -d "$COLMAP_MODEL" ] || COLMAP_MODEL="$EXP/TripoPoor/colmap/sparse/0"
    COLMAP_IMAGES="$EXP/TripoPoor/images"
    OUT="$EXP/TripoPoor/openmvs"
    UNDISTORT_MAX=2400      # photos are 4000x3000; 2400 caps RAM/time on CPU
    DENSIFY_MAX=2400
    MASKS_DEFAULT=""        # no foreground masks for this capture (yet)
    ;;
  *)
    echo "usage: bash run_openmvs.sh {sneaker|tripopoor}"; exit 2 ;;
esac

# ---- quality preset --------------------------------------------------------
# QUALITY=high|medium|low (default medium = the rubber-duck-validated baseline).
# Two independent axes matter for a product render:
#   * DETAIL  -> DensifyPointCloud --resolution-level (0=full res, 1=half, 2=quarter)
#               and RefineMesh --max-face-area (smaller = more, finer triangles).
#   * SMOOTHNESS/CLEANLINESS -> ReconstructMesh --smooth / --remove-spurious and
#               RefineMesh --regularity-weight, plus eroding the foreground mask
#               to shave the silhouette slivers ("flaps") off the outline.
# Full-resolution densification (high) yields the most triangles but also the
# noisiest depth, so high pairs it with stronger smoothing + spurious removal +
# regularization so the extra detail does not just become a crumpled surface.
# Knobs below can be overridden per-run (e.g. SMOOTH=6 QUALITY=high ...).
QUALITY="${QUALITY:-medium}"
case "$QUALITY" in
  high)   RES_LEVEL=0; REFINE_RES=1; MAX_FACE_AREA=8;  SMOOTH_DEF=4; SPURIOUS_DEF=40; REGULARITY_DEF=0.35; ERODE_DEF=4 ;;
  medium) RES_LEVEL=1; REFINE_RES=1; MAX_FACE_AREA=16; SMOOTH_DEF=3; SPURIOUS_DEF=30; REGULARITY_DEF=0.25; ERODE_DEF=3 ;;
  low)    RES_LEVEL=2; REFINE_RES=2; MAX_FACE_AREA=32; SMOOTH_DEF=2; SPURIOUS_DEF=20; REGULARITY_DEF=0.20; ERODE_DEF=2 ;;
  *) echo "QUALITY must be high|medium|low (got '$QUALITY')"; exit 2 ;;
esac
# Mesh-cleanup knobs (per-quality defaults, overridable per run):
SMOOTH="${SMOOTH:-$SMOOTH_DEF}"               # ReconstructMesh Laplacian smoothing iterations
REMOVE_SPURIOUS="${REMOVE_SPURIOUS:-$SPURIOUS_DEF}"  # drop faces with over-long edges / isolated bits (kills flaps)
REGULARITY="${REGULARITY:-$REGULARITY_DEF}"   # RefineMesh regularity weight (higher = smoother)

# ---- foreground masking (optional but recommended) -------------------------
# MASKS=<dir> with one foreground mask per source image (black=background,
# white=object). They are staged as '<image>.jpg.mask.png' next to the
# undistorted images and DensifyPointCloud is told to drop background with
# --ignore-mask-label 0, so the dense cloud (hence the mesh) contains only the
# object -- no floor/backdrop flaps. This is the single biggest cleanliness win
# and it is what keeps the full-resolution (QUALITY=high, ROI-off) mesh from
# pulling in background geometry. The mask is also ERODED by MASK_ERODE pixels
# (preset default) so the soft BiRefNet silhouette fringe does not survive as
# thin boundary slivers/"flaps" around the outline. Set MASKS=none to disable,
# MASK_ERODE=0 to keep the raw silhouette. Requires Python + Pillow.
MASKS="${MASKS:-$MASKS_DEFAULT}"
[ "$MASKS" = "none" ] && MASKS=""
MASK_ERODE="${MASK_ERODE:-$ERODE_DEF}"

LOG_DIR="$OUT"; mkdir -p "$OUT"
LOG="$OUT/openmvs.log"; : > "$LOG"
log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "preset=$PRESET  quality=$QUALITY  (resolution-level=$RES_LEVEL refine-level=$REFINE_RES max-face-area=$MAX_FACE_AREA smooth=$SMOOTH remove-spurious=$REMOVE_SPURIOUS regularity=$REGULARITY mask-erode=$MASK_ERODE)"
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
# 2b) Stage foreground masks (optional) next to the undistorted images so
#     DensifyPointCloud can drop the background. OpenMVS looks for a file named
#     '<image>.mask.png' beside each image; black(0)=ignored, white=object.
#     Masks are resampled to each undistorted image's exact size and binarized.
# ---------------------------------------------------------------------------
MASK_ARGS=()
MASK_LABEL=""
if [ -n "$MASKS" ] && [ -d "$MASKS" ]; then
  log "step 2b   staging foreground masks from $MASKS"
  staged="$(MASKS_DIR="$MASKS" IMG_DIR="$UND/images" ERODE="$MASK_ERODE" python3 - <<'PY' 2>>"$LOG"
import os, glob
from PIL import Image, ImageFilter
imgdir = os.environ["IMG_DIR"]; maskdir = os.environ["MASKS_DIR"]
erode = int(os.environ.get("ERODE", "0"))
n = 0
for img in sorted(glob.glob(os.path.join(imgdir, "*"))):
    if img.endswith(".mask.png"):
        continue
    stem = os.path.splitext(os.path.basename(img))[0]
    cands = glob.glob(os.path.join(maskdir, stem + ".*"))
    if not cands:
        continue
    W, H = Image.open(img).size
    m = Image.open(cands[0]).convert("L").resize((W, H), Image.NEAREST)
    m = m.point(lambda v: 255 if v > 127 else 0)   # binarize: object=255, bg=0
    if erode > 0:
        # shrink the foreground so the soft silhouette fringe does not survive
        # as thin boundary slivers ("flaps") in the dense cloud/mesh.
        m = m.filter(ImageFilter.MinFilter(2 * erode + 1))
    m.save(img + ".mask.png")
    n += 1
print(n)
PY
)"
  log "       staged ${staged:-0} masks -> DensifyPointCloud --ignore-mask-label 0"
  if [ "${staged:-0}" -gt 0 ] 2>/dev/null; then MASK_ARGS=(--ignore-mask-label 0); MASK_LABEL=" masked"; fi
fi

# ---------------------------------------------------------------------------
# 3) Dense point cloud (the heavy CPU stage).
#    NOTE: at resolution-level 0 (QUALITY=high) the prebuilt v2.4.0 binary
#    SEGFAULTS inside its new ROI-estimation/cropping step (added in v2.4.0).
#    Disabling --estimate-roi / --crop-to-roi side-steps the crash and lets the
#    full-resolution densification run to completion (verified: 8k -> ~800k
#    points on the sneaker). At level 1+ the ROI step is fine, so we only disable
#    it for level 0. Background that ROI would have cropped is instead handled by
#    masking (MASKS=..., see step 2b).
# ---------------------------------------------------------------------------
ROI_ARGS=()
ROI_LABEL=""
if [ "$RES_LEVEL" = "0" ]; then ROI_ARGS=(--estimate-roi 0 --crop-to-roi 0); ROI_LABEL=" roi-off"; fi
log "step 3/5  DensifyPointCloud (resolution-level=$RES_LEVEL max-resolution=$DENSIFY_MAX$ROI_LABEL$MASK_LABEL)"
"$OPENMVS_BIN/DensifyPointCloud" "$SCENE" \
  -w "$OUT" \
  -o "$OUT/scene_dense.mvs" \
  --resolution-level "$RES_LEVEL" \
  --max-resolution "$DENSIFY_MAX" \
  --number-views 5 \
  --number-views-fuse 3 \
  "${ROI_ARGS[@]+"${ROI_ARGS[@]}"}" \
  "${MASK_ARGS[@]+"${MASK_ARGS[@]}"}" \
  >> "$LOG" 2>&1
log "       DensifyPointCloud exit=$?"

# ---------------------------------------------------------------------------
# 4) Surface mesh from the dense cloud.
# ---------------------------------------------------------------------------
log "step 4/6  ReconstructMesh (smooth=$SMOOTH remove-spurious=$REMOVE_SPURIOUS)"
"$OPENMVS_BIN/ReconstructMesh" "$OUT/scene_dense.mvs" \
  -p "$OUT/scene_dense.ply" \
  -w "$OUT" \
  -o "$OUT/scene_dense_mesh.mvs" \
  --decimate 1 \
  --remove-spurious "$REMOVE_SPURIOUS" \
  --close-holes 30 \
  --smooth "$SMOOTH" \
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
# Always clear any stale refined mesh from a previous run so that, if RefineMesh
# fails, we fall back to THIS run's raw dense mesh -- never an old leftover.
rm -f "$OUT/scene_dense_mesh_refine.ply" "$OUT/scene_dense_mesh_refine.mvs"
if [ "$REFINE" = "1" ]; then
  log "step 4b/6 RefineMesh (REFINE=1; set REFINE=0 to skip)"
  "$OPENMVS_BIN/RefineMesh" \
    -i "$OUT/scene.mvs" \
    -m "$OUT/scene_dense_mesh.ply" \
    -w "$OUT" \
    -o "$OUT/scene_dense_mesh_refine.mvs" \
    --resolution-level "$REFINE_RES" \
    --scales 1 \
    --max-face-area "$MAX_FACE_AREA" \
    --regularity-weight "$REGULARITY" \
    --close-holes 60 \
    >> "$LOG" 2>&1
  log "       RefineMesh exit=$?"
  if [ -f "$OUT/scene_dense_mesh_refine.ply" ]; then
    MESH="$OUT/scene_dense_mesh_refine.ply"
  else
    log "       RefineMesh produced no mesh -> texturing the raw dense mesh instead"
  fi
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
