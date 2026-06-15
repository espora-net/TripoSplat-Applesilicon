#!/usr/bin/env python3
"""Build the CLEAN (black-background) brush dataset from the COLMAP frames and
their BiRefNet masks.

Why black-composite instead of just passing a masks/ folder:
  * A masks/ folder makes brush use AlphaMode::Masked -> the background loss is
    *ignored*. The object reconstructs well, but nothing PENALISES Gaussians that
    drift into the (busy, animated, light-streak) background, so you get bright
    "floaters" that look fine from the captured views but are garbage from novel
    angles in the 3D viewer. (Measured: ~62% of background pixels lit.)
  * Compositing each frame onto BLACK (rgb * alpha) and training with the normal
    FULL-image photometric loss (NO masks/ folder) instead forces the renderer to
    reproduce a black background everywhere -> any background Gaussian is actively
    penalised -> a clean cut-out splat. (Measured: ~0.2% of background pixels lit.)

This reuses the masks from make_masks.py (no extra model inference) and keeps the
exact .jpg filenames so the COLMAP model (which references images by name) still
resolves. Output: tools/brush/ds_black/{images,sparse/0}.
"""
import glob
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMES = f"{HERE}/frames_all"
MASKS = f"{HERE}/gsplat_dataset/masks"
SRC_MODEL = f"{HERE}/gsplat_dataset/sparse/0"
DST = f"{HERE}/tools/brush/ds_black"


def main():
    if not os.path.isdir(MASKS) or not os.listdir(MASKS):
        raise SystemExit("masks missing — run make_masks.py first")
    os.makedirs(f"{DST}/images", exist_ok=True)
    os.makedirs(f"{DST}/sparse/0", exist_ok=True)

    frames = sorted(glob.glob(f"{FRAMES}/*.jpg"))
    for f in frames:
        name = os.path.basename(f)
        rgb = np.asarray(Image.open(f).convert("RGB")).astype(np.float32)
        m = np.asarray(Image.open(f"{MASKS}/{name}").convert("L")).astype(np.float32) / 255.0
        out = (rgb * m[..., None]).clip(0, 255).astype(np.uint8)   # soft matte, bg -> black
        Image.fromarray(out).save(f"{DST}/images/{name}", quality=95)

    for b in glob.glob(f"{SRC_MODEL}/*.bin"):
        with open(b, "rb") as src, open(f"{DST}/sparse/0/{os.path.basename(b)}", "wb") as dst:
            dst.write(src.read())

    print(f"composited {len(frames)} black-bg frames -> {DST}/images")
    print(f"copied COLMAP model -> {DST}/sparse/0")


if __name__ == "__main__":
    main()
