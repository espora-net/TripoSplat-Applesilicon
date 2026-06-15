#!/usr/bin/env python3
"""Generate foreground (sneaker) masks for the COLMAP frames using the repo's
BiRefNet background-removal model, for brush's masked 3DGS training.

brush convention (from its source, formats/mod.rs):
  images/<name>  ->  masks/<name>   (sibling 'masks' dir, SAME filename)
With the default AlphaMode::Masked, the training loss is multiplied by the
mask alpha, so background pixels (value 0 / black) are IGNORED. We therefore
write a grayscale mask where the sneaker is white (255) and the background black.

Crucially we use BiRefNet.remove_background (which returns an alpha matte at the
ORIGINAL frame resolution) and DO NOT crop/recenter — the masks must stay pixel-
aligned with the frames COLMAP was posed on.
"""
import os
import sys
import glob

os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")

import numpy as np
import torch
from PIL import Image

REPO = "/Users/carloshm/personal-projects/copilot-worktrees/TripoSplat-Applesilicon/carloshm-legendary-train"
sys.path.insert(0, REPO)
from triposplat import load_rmbg  # noqa: E402

FRAMES = f"{REPO}/experiments/colmap_sneaker/frames_all"
MASKS = f"{REPO}/experiments/colmap_sneaker/gsplat_dataset/masks"
CKPT = f"{REPO}/ckpts/background_removal/birefnet.safetensors"


def main():
    os.makedirs(MASKS, exist_ok=True)
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    print(f"device={device}  loading BiRefNet...")
    rmbg = load_rmbg(CKPT, device=device, dtype=torch.float16)

    frames = sorted(glob.glob(f"{FRAMES}/*.jpg"))
    print(f"{len(frames)} frames -> {MASKS}")
    cov = []
    for i, f in enumerate(frames, 1):
        name = os.path.basename(f)
        img = Image.open(f).convert("RGB")
        rgba = rmbg.remove_background(img)          # RGBA, alpha matte @ orig res
        alpha = rgba.getchannel("A")                # L, white=foreground(shoe)
        alpha.save(f"{MASKS}/{name}", quality=95)   # masks/<same name>.jpg
        frac = np.asarray(alpha).mean() / 255.0
        cov.append(frac)
        if i % 16 == 0 or i == len(frames):
            print(f"  {i:3d}/{len(frames)}  {name}  fg={frac:.2%}")
    cov = np.array(cov)
    print(f"done. foreground coverage: mean={cov.mean():.2%} "
          f"min={cov.min():.2%} max={cov.max():.2%}")
    # Sanity: if any mask is ~empty or ~full, BiRefNet likely failed on it.
    bad = [(os.path.basename(frames[i]), f"{cov[i]:.2%}")
           for i in range(len(cov)) if cov[i] < 0.02 or cov[i] > 0.95]
    print(f"suspicious masks (fg<2% or >95%): {bad if bad else 'none'}")


if __name__ == "__main__":
    main()
