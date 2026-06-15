#!/usr/bin/env bash
#
# Part C — turn the COLMAP poses+points (Part B) into an ACTUAL, viewable,
# optimised 3D Gaussian Splat (.ply) that runs NATIVELY on Apple Silicon.
#
# Why brush (https://github.com/ArthurBrussee/brush) and not gsplat/nerfstudio:
# the Inria/gsplat/nerfstudio CUDA rasterisers are CUDA-only and do NOT run on
# Apple Silicon. brush is a from-scratch 3DGS trainer+viewer built on wgpu/Burn
# that runs on Metal, ingests a COLMAP model directly, and exports a standard
# 3DGS .ply (SH degree 3) — i.e. the real thing, on this M3.
#
# Pipeline:
#   ws_all/sparse/2  (COLMAP model, Part B)  +  frames_all/*.jpg
#        -> gsplat_dataset/{images,masks,sparse/0}
#        -> brush (Metal)  ->  out/full/sneaker_{iter}.ply   (viewable 3DGS)
#
# MAX-QUALITY choices (see README.md "Part C"):
#   * Foreground masks (make_masks.py, BiRefNet) define the sneaker silhouette.
#   * CLEAN cut-out via BLACK-background compositing (make_black_dataset.py):
#     each frame is composited onto black (rgb*alpha) and brush trains with its
#     normal FULL-image photometric loss. This forces the renderer to reproduce a
#     black background everywhere, so background "floater" Gaussians are actively
#     penalised -> a clean object splat. (A plain masks/ folder only *ignores* the
#     background, leaving floaters: measured ~62% of bg pixels lit vs ~0.2% here.)
#   * SH degree 3 (brush max), full native resolution (frames are 720x1280 < 1920),
#     full 30k-step schedule with densification to 15k (standard 3DGS recipe).
#   * Hold out every 8th view for HONEST eval (PSNR on unseen-during-training
#     frames, renders saved to disk; see eval_fg_psnr.py).
#
# HONEST FRAMING: the result is a genuine optimised 3DGS .ply, best from the
# captured side; the far side / top / sole are under-constrained by the input
# (side-biased coverage, AI-generated source video — see Parts B & C) and will be
# incomplete or inferred. It is a viewable 3D asset, NOT a metric scan.
#
# Usage:  bash run_brush_splat.sh [TOTAL_STEPS]      (default 30000)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
STEPS="${1:-30000}"

SRC_MODEL="$HERE/ws_all/sparse/2"     # COLMAP model from Part B (largest sub-model)
FRAMES="$HERE/frames_all"             # 96 video frames from Part B
DS="$HERE/gsplat_dataset"             # masked dataset (images + masks + sparse)
DS_BLACK="$HERE/tools/brush/ds_black" # CLEAN black-bg dataset (what we train on)
OUT="$HERE/tools/brush/out/black"     # exported splats + eval renders
BRUSH_DIR="$HERE/tools/brush/brush-app-aarch64-apple-darwin"
BRUSH="$BRUSH_DIR/brush_app"

# ---------------------------------------------------------------------------
# 0. brush binary (prebuilt macOS arm64 release; Metal). Download if missing.
# ---------------------------------------------------------------------------
if [[ ! -x "$BRUSH" ]]; then
  echo "==> brush binary not found; downloading prebuilt macOS arm64 release..."
  mkdir -p "$HERE/tools/brush"
  ( cd "$HERE/tools/brush" \
    && gh release download v0.3.0 -R ArthurBrussee/brush \
         -p 'brush-app-aarch64-apple-darwin.tar.xz' --clobber \
    && mkdir -p brush-app-aarch64-apple-darwin \
    && tar -xf brush-app-aarch64-apple-darwin.tar.xz -C brush-app-aarch64-apple-darwin )
  chmod +x "$BRUSH"
  xattr -dr com.apple.quarantine "$BRUSH_DIR" 2>/dev/null || true   # Gatekeeper
fi
[[ -x "$BRUSH" ]] || { echo "ERROR: brush binary missing at $BRUSH"; exit 1; }

# ---------------------------------------------------------------------------
# 1. Assemble the brush dataset from the COLMAP Part-B outputs.
#    brush reads a COLMAP model under sparse/0 and images under images/.
# ---------------------------------------------------------------------------
[[ -d "$SRC_MODEL" ]] || { echo "ERROR: COLMAP model missing — run run_colmap_video.sh first"; exit 1; }
[[ -d "$FRAMES" ]]    || { echo "ERROR: frames missing — run run_colmap_video.sh first"; exit 1; }

echo "==> assembling brush dataset at $DS"
mkdir -p "$DS/images" "$DS/sparse/0"
cp -f "$FRAMES"/*.jpg "$DS/images/"
cp -f "$SRC_MODEL"/*.bin "$DS/sparse/0/"   # cameras/images/points3D (+rigs/frames on COLMAP 4.x)
echo "    images: $(ls "$DS/images" | wc -l | tr -d ' ')   sparse: $(ls "$DS/sparse/0")"

# ---------------------------------------------------------------------------
# 2. Foreground masks (BiRefNet) — define the sneaker silhouette. Skip if done.
# ---------------------------------------------------------------------------
if [[ ! -d "$DS/masks" ]] || [[ "$(ls "$DS/masks" 2>/dev/null | wc -l | tr -d ' ')" -lt "$(ls "$DS/images" | wc -l | tr -d ' ')" ]]; then
  echo "==> generating BiRefNet foreground masks (MPS)..."
  python3 "$HERE/make_masks.py"
else
  echo "==> masks already present ($(ls "$DS/masks" | wc -l | tr -d ' ')); skipping"
fi

# ---------------------------------------------------------------------------
# 3. CLEAN black-background dataset (frames composited onto black via the masks).
#    Training on these with the normal full-image loss penalises background
#    floaters -> a clean cut-out splat (see make_black_dataset.py).
# ---------------------------------------------------------------------------
echo "==> building clean black-bg dataset..."
python3 "$HERE/make_black_dataset.py"

# ---------------------------------------------------------------------------
# 4. Train the Gaussian splat on Metal — clean, max quality.
# ---------------------------------------------------------------------------
mkdir -p "$OUT"
echo "==> training 3DGS with brush on Metal: $STEPS steps -> $OUT"
RUST_LOG="${RUST_LOG:-brush_cli=info,info}" \
"$BRUSH" "$DS_BLACK" \
  --total-steps "$STEPS" \
  --sh-degree 3 \
  --max-resolution 1920 \
  --eval-split-every 8 \
  --eval-every 2000 \
  --eval-save-to-disk \
  --export-every 10000 \
  --export-path "$OUT" \
  --export-name "sneaker_black_{iter}.ply" \
  --seed 42

echo "==> done. Exported splats:"
ls -la "$OUT"/*.ply 2>/dev/null
echo "==> held-out eval (foreground PSNR + floater leakage):"
python3 "$HERE/eval_fg_psnr.py" "$OUT/eval_$STEPS" 2>/dev/null | tail -4

cat <<EOF

View the result (any of):
  * brush viewer (native, Metal):
      "$BRUSH" "$OUT/sneaker_black_${STEPS}.ply" --with-viewer
  * the repo's web viewer (Spark.js):  static/viewer/  (load the .ply)
  * SuperSplat / splat-transform / any 3DGS .ply viewer
EOF
