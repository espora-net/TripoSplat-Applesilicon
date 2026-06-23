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
#   SYNTH_SET=full  QUALITY=max COLOR_NORM=0 bash run_openmvs.sh synth  # coverage-ablation
#   SYNTH_SET=full2 QUALITY=max COLOR_NORM=0 bash run_openmvs.sh synth  # +collar rings (best)
#                                    # synthetic views of the retail GLB (full|side); see
#                                    # ../colmap_sneaker run_colmap_synth.sh + README "Part D"
#   PHOTOS_WS=/path/to/ws QUALITY=max bash run_openmvs.sh photos  # YOUR OWN photos: validate the
#                                    # pipeline on a real capture (build ws with
#                                    # ../colmap_sneaker/run_colmap_photos.sh; see max_quality_pipeline/)
#   OPENMVS_BIN=/path bash run_openmvs.sh <preset>
#   QUALITY=max  bash run_openmvs.sh <preset>      # full-res densify + full-res refine + colour-norm (best)
#   QUALITY=high bash run_openmvs.sh <preset>      # full-res densify+refine (most detail)
#   QUALITY=low  bash run_openmvs.sh <preset>      # quarter-res (fastest, coarse)
#   MASKS=<dir>  bash run_openmvs.sh <preset>      # drop background via fg masks
#   MASKS=none   bash run_openmvs.sh <preset>      # disable the preset's default masks
#   SMOOTH=6 bash run_openmvs.sh <preset>          # smoother surface (more Laplacian iters)
#   MASK_ERODE=6 bash run_openmvs.sh <preset>      # shave more silhouette "flaps"
#   COLOR_NORM=1 bash run_openmvs.sh <preset>      # harmonise frame exposure/white-balance (uniform colour)
#   REFINE=0 bash run_openmvs.sh <preset>          # skip RefineMesh (faster)
#   SEAM_LEVELING=1 bash run_openmvs.sh <preset>   # restore OpenMVS seam leveling (WARNING: blobs on video frames)
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
  synth)
    # Coverage-ablation: synthetic views rendered from the reference El Corte
    # Ingles / Vyking GLB (render_synthetic.py) + COLMAP (run_colmap_synth.sh).
    # SYNTH_SET=full (default, ~90 views, 360 coverage), full2 (~108 views,
    # full + into-the-collar rings -> open laced throat, best surface) or
    # side (limited arc, ablation control).
    # Proves the pipeline reaches retail quality GIVEN full coverage; the masks
    # are exact (z-buffer silhouettes), and lighting is already uniform so
    # COLOR_NORM is unnecessary here (default off via SET below).
    SYNTH_SET="${SYNTH_SET:-full}"
    SROOT="$EXP/colmap_sneaker/synthetic_ref/$SYNTH_SET"
    COLMAP_MODEL="$SROOT/ws/sparse/0"
    COLMAP_IMAGES="$SROOT/images"
    OUT="$SROOT/openmvs"
    UNDISTORT_MAX=1280      # renders are 1280x1280
    DENSIFY_MAX=1280
    MASKS_DEFAULT="$SROOT/masks"   # exact z-buffer silhouettes (one per view)
    ;;
  photos)
    # --- Replicate the pipeline with YOUR OWN photos (validate on a real capture) ---
    # Easiest path: first build a COLMAP workspace from your photos with
    #   bash ../colmap_sneaker/run_colmap_photos.sh /path/to/photos /path/to/ws
    # then point this preset at it:
    #   PHOTOS_WS=/path/to/ws QUALITY=max bash run_openmvs.sh photos
    # $PHOTOS_WS must contain  images/  and  sparse/0/ (the COLMAP model); a
    # masks/ dir (one <stem>.png per image, black=background) is optional and
    # improves results. Or set the paths explicitly with COLMAP_MODEL=,
    # COLMAP_IMAGES=, OUT= (and optionally MASKS=).
    PHOTOS_WS="${PHOTOS_WS:-}"
    if [ -n "$PHOTOS_WS" ]; then
      COLMAP_MODEL="${COLMAP_MODEL:-$PHOTOS_WS/sparse/0}"
      COLMAP_IMAGES="${COLMAP_IMAGES:-$PHOTOS_WS/images}"
      OUT="${OUT:-$PHOTOS_WS/openmvs}"
      MASKS_DEFAULT="$PHOTOS_WS/masks"   # used only if it exists (and MASKS unset)
    else
      : "${COLMAP_MODEL:?photos preset: set PHOTOS_WS=/path/to/ws  OR  COLMAP_MODEL=/path/to/sparse/0}"
      : "${COLMAP_IMAGES:?photos preset: set PHOTOS_WS  OR  COLMAP_IMAGES=/path/to/images}"
      : "${OUT:?photos preset: set PHOTOS_WS  OR  OUT=/path/to/out}"
      MASKS_DEFAULT="${MASKS_DEFAULT:-}"
    fi
    UNDISTORT_MAX="${UNDISTORT_MAX:-2000}"   # real photos can be large; cap RAM/time on CPU
    DENSIFY_MAX="${DENSIFY_MAX:-2000}"
    ;;
  *)
    echo "usage: bash run_openmvs.sh {sneaker|tripopoor|synth|photos}"; exit 2 ;;
esac

# ---- quality preset --------------------------------------------------------
# QUALITY=max|high|medium|low (default medium = the rubber-duck-validated baseline).
# Two independent axes matter for a product render:
#   * DETAIL  -> DensifyPointCloud --resolution-level (0=full res, 1=half, 2=quarter)
#               and RefineMesh --resolution-level / --max-face-area / --scales
#               (smaller face area + lower level + more scales = finer geometry).
#   * SMOOTHNESS/CLEANLINESS -> ReconstructMesh --smooth / --remove-spurious and
#               RefineMesh --regularity-weight, plus eroding the foreground mask
#               to shave the silhouette slivers ("flaps") off the outline.
# Full-resolution densification (high/max) yields the most triangles but also the
# noisiest depth, so they pair it with stronger smoothing + spurious removal +
# regularization so the extra detail does not just become a crumpled surface.
# QUALITY=max additionally refines the mesh at FULL image resolution
# (--resolution-level 0, more --scales) and uses the finest faces, then turns on
# COLOR_NORM (exposure/white-balance harmonisation of the input frames) to fight
# the multi-tone look -- because OpenMVS' own seam-leveling explodes into
# saturated colour blobs on these video frames (kept OFF; see TextureMesh below).
# NOTE: full-res densification produces far more silhouette-boundary points, so
# max needs MORE mask erosion + spurious removal (not less) to suppress the flat
# "sail" flaps that otherwise bridge across the mask edge -- hence ERODE/SPURIOUS
# are higher here, balanced by the finer faces preserving genuine surface relief.
# Knobs below can be overridden per-run (e.g. SMOOTH=6 QUALITY=high ...).
QUALITY="${QUALITY:-medium}"
case "$QUALITY" in
  max)    RES_LEVEL=0; REFINE_RES=0; MAX_FACE_AREA=6;  SMOOTH_DEF=3; SPURIOUS_DEF=50; REGULARITY_DEF=0.25; ERODE_DEF=3; SCALES_DEF=3; CNORM_DEF=1; VF_DEF=3; CLOSE_DEF=12 ;;
  high)   RES_LEVEL=0; REFINE_RES=1; MAX_FACE_AREA=8;  SMOOTH_DEF=4; SPURIOUS_DEF=40; REGULARITY_DEF=0.35; ERODE_DEF=4; SCALES_DEF=2; CNORM_DEF=0; VF_DEF=0; CLOSE_DEF=30 ;;
  medium) RES_LEVEL=1; REFINE_RES=1; MAX_FACE_AREA=16; SMOOTH_DEF=3; SPURIOUS_DEF=30; REGULARITY_DEF=0.25; ERODE_DEF=3; SCALES_DEF=2; CNORM_DEF=0; VF_DEF=0; CLOSE_DEF=30 ;;
  low)    RES_LEVEL=2; REFINE_RES=2; MAX_FACE_AREA=32; SMOOTH_DEF=2; SPURIOUS_DEF=20; REGULARITY_DEF=0.20; ERODE_DEF=2; SCALES_DEF=2; CNORM_DEF=0; VF_DEF=0; CLOSE_DEF=30 ;;
  *) echo "QUALITY must be max|high|medium|low (got '$QUALITY')"; exit 2 ;;
esac
# Mesh-cleanup / refinement knobs (per-quality defaults, overridable per run):
SMOOTH="${SMOOTH:-$SMOOTH_DEF}"               # ReconstructMesh Laplacian smoothing iterations
REMOVE_SPURIOUS="${REMOVE_SPURIOUS:-$SPURIOUS_DEF}"  # drop faces with over-long edges / isolated bits (kills flaps)
REGULARITY="${REGULARITY:-$REGULARITY_DEF}"   # RefineMesh regularity weight (higher = smoother)
REFINE_SCALES="${REFINE_SCALES:-$SCALES_DEF}" # RefineMesh multi-scale optimization iterations
COLOR_NORM="${COLOR_NORM:-$CNORM_DEF}"        # 1 = harmonise exposure/white-balance across frames before texturing
VIRTUAL_FACES="${VIRTUAL_FACES:-$VF_DEF}"     # TextureMesh: merge coplanar faces seen by >= N views into one patch (0=off)
CLOSE_HOLES="${CLOSE_HOLES:-$CLOSE_DEF}"      # max bridges fewer-pixel holes so the under-shot top opening is not capped by a flat untextured "lid"
# Colour for faces no camera ever textured (the under-captured concave top/heel).
# A near-black (#1A1A1A=1710618) reads as natural interior shadow instead of the
# jarring bright-grey/white patch the user flagged ("la parte de atras en blanco").
EMPTY_COLOR="${EMPTY_COLOR:-1710618}"

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

log "preset=$PRESET  quality=$QUALITY  (resolution-level=$RES_LEVEL refine-level=$REFINE_RES max-face-area=$MAX_FACE_AREA scales=$REFINE_SCALES smooth=$SMOOTH remove-spurious=$REMOVE_SPURIOUS regularity=$REGULARITY mask-erode=$MASK_ERODE color-norm=$COLOR_NORM)"
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
#     DensifyPointCloud can drop the background. OpenMVS (v2.x) looks for a file
#     named '<image-stem>.mask.png' beside each image -- i.e. it REPLACES the
#     image extension, so for 'zoom_027.jpg' it reads 'zoom_027.mask.png' (NOT
#     'zoom_027.jpg.mask.png'). Getting this name wrong silently disables masking:
#     DensifyPointCloud then keeps the background, which at resolution-level 0
#     (ROI estimation disabled to avoid the v2.4.0 segfault) shows up as large flat
#     "sail" flaps of ground/backdrop fused onto the shoe. black(0)=ignored,
#     white=object. Masks are resampled to each image's size and binarized.
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
    # OpenMVS wants '<stem>.mask.png' (extension REPLACED), e.g. zoom_027.mask.png
    m.save(os.path.join(os.path.dirname(img), stem + ".mask.png"))
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
# DensifyPointCloud caches per-view depthNNNN.dmap files in the working folder and
# reuses any it finds. Those depth maps are computed at a specific resolution-level
# and against specific (e.g. masked) images, so reusing maps from a previous run at
# a DIFFERENT level/mask silently produces stale geometry (a level-0 run that finds
# level-1 maps "finishes" in seconds with wrong data). Track the level/mask combo
# the cached maps belong to and wipe them whenever it changes.
DMAP_TAG="L${RES_LEVEL}${MASK_LABEL// /_}"
if [ -f "$OUT/.densify_tag" ] && [ "$(cat "$OUT/.densify_tag")" = "$DMAP_TAG" ]; then
  log "       reusing cached depth maps (tag=$DMAP_TAG)"
else
  log "       densify settings changed (tag=$DMAP_TAG) -> clearing cached *.dmap"
  rm -f "$OUT"/*.dmap
fi
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
printf '%s' "$DMAP_TAG" > "$OUT/.densify_tag"

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
  --close-holes "$CLOSE_HOLES" \
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
    --scales "$REFINE_SCALES" \
    --max-face-area "$MAX_FACE_AREA" \
    --regularity-weight "$REGULARITY" \
    --close-holes "$CLOSE_HOLES" \
    >> "$LOG" 2>&1
  log "       RefineMesh exit=$?"
  if [ -f "$OUT/scene_dense_mesh_refine.ply" ]; then
    MESH="$OUT/scene_dense_mesh_refine.ply"
  else
    log "       RefineMesh produced no mesh -> texturing the raw dense mesh instead"
  fi
fi

# ---------------------------------------------------------------------------
# 4c) Colour/exposure harmonisation (COLOR_NORM=1) of the undistorted frames.
#     Why: TextureMesh picks the best single view per face, so neighbouring faces
#     sourced from frames shot under slightly different auto-exposure/white-balance
#     show visible colour jumps (e.g. the green leather drifting between teal and
#     grass-green). OpenMVS' own global/local seam-leveling is the textbook fix BUT
#     on these video frames it diverges into saturated primary-colour blobs (kept
#     OFF below). Instead we equalise the frames ourselves: scale each image's
#     per-channel mean (measured INSIDE the foreground mask, so the background does
#     not skew it) to the global mean across all frames. That removes the inter-
#     frame exposure/white-balance drift while preserving real texture detail, so
#     the untouched seam-leveling-off texture comes out far more uniform.
#     A one-time backup (images_orig/) lets repeated runs start from the originals.
# ---------------------------------------------------------------------------
if [ "$COLOR_NORM" = "1" ]; then
  log "step 4c/6 colour/exposure harmonisation of $UND/images (COLOR_NORM=1)"
  IMG_DIR="$UND/images" python3 - <<'PY' 2>>"$LOG"
import os, glob, numpy as np
from PIL import Image
d = os.environ["IMG_DIR"]
orig = os.path.join(os.path.dirname(d), "images_orig")
os.makedirs(orig, exist_ok=True)
imgs = [p for p in sorted(glob.glob(os.path.join(d, "*")))
        if not p.endswith(".mask.png")
        and p.lower().endswith((".jpg", ".jpeg", ".png"))]
# restore-from-backup (so re-runs are idempotent) or seed the backup
for p in imgs:
    b = os.path.join(orig, os.path.basename(p))
    if os.path.exists(b):
        Image.open(b).save(p)
    else:
        Image.open(p).save(b)
# pass 1: global foreground per-channel mean
gsum = np.zeros(3); gcnt = 0.0
stats = {}
for p in imgs:
    im = np.asarray(Image.open(p).convert("RGB"), dtype=np.float64)
    mp = os.path.splitext(p)[0] + ".mask.png"   # OpenMVS '<stem>.mask.png'
    if os.path.exists(mp):
        m = np.asarray(Image.open(mp).convert("L")) > 127
    else:
        m = np.ones(im.shape[:2], dtype=bool)
    if m.sum() < 50:
        m = np.ones(im.shape[:2], dtype=bool)
    fg = im[m]
    stats[p] = (fg.mean(axis=0), m)
    gsum += fg.sum(axis=0); gcnt += m.sum()
gmean = gsum / max(gcnt, 1.0)
# pass 2: per-image multiplicative gain so its fg mean matches the global mean
n = 0
for p in imgs:
    imean, _ = stats[p]
    gain = gmean / np.clip(imean, 1e-3, None)
    gain = np.clip(gain, 0.5, 2.0)            # avoid extreme corrections
    im = np.asarray(Image.open(p).convert("RGB"), dtype=np.float64)
    im = np.clip(im * gain, 0, 255).astype(np.uint8)
    Image.fromarray(im).save(p, quality=95)
    n += 1
print(f"harmonised {n} frames; global fg mean = {gmean.round(1)}")
PY
  log "       colour harmonisation done"
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
  --virtual-face-images "$VIRTUAL_FACES" \
  --global-seam-leveling "$SEAM" \
  --local-seam-leveling "$SEAM" \
  --empty-color "$EMPTY_COLOR" \
  --export-type obj \
  >> "$LOG" 2>&1
log "       TextureMesh exit=$?"

log "DONE. Artifacts in $OUT:"
ls -lh "$OUT"/*.ply "$OUT"/*.obj 2>/dev/null | tee -a "$LOG"
log "View: open the textured .obj in Preview/QuickLook, MeshLab or Blender;"
log "      or the dense .ply in MeshLab. Full log: $LOG"
