#!/usr/bin/env python3
"""BiRefNet foreground masks for the Vibram frames.

Two consumers, two naming conventions, one matte:
  * COLMAP  --ImageReader.mask_path expects  masks_colmap/<image_name>.png
            (full filename + .png); value 0 => SIFT ignores that pixel.  This is
            what removes the wood floor so COLMAP treats the shoe as one rigid
            object across all 5 clips (the shoe is repositioned between clips, so
            without masking the static floor would dominate SfM).
  * OpenMVS run_openmvs.sh matches  masks/<stem>.*  -> stages <stem>.mask.png.

We write the matte once to masks/<stem>.png (white=shoe) and hard-link it into
masks_colmap/<stem>.jpg.png.  Masks are at ORIGINAL frame resolution (no crop /
recenter) so they stay pixel-aligned with the poses.
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

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMES = os.path.join(HERE, "recon", "images_orig")
MASKS = os.path.join(HERE, "recon", "masks")
MASKS_COLMAP = os.path.join(HERE, "recon", "masks_colmap")
CKPT = f"{REPO}/ckpts/background_removal/birefnet.safetensors"


def main():
    os.makedirs(MASKS, exist_ok=True)
    os.makedirs(MASKS_COLMAP, exist_ok=True)
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    print(f"device={device}  loading BiRefNet...")
    rmbg = load_rmbg(CKPT, device=device, dtype=torch.float16)

    frames = sorted(glob.glob(f"{FRAMES}/*.jpg"))
    print(f"{len(frames)} frames -> {MASKS}")
    cov = []
    for i, f in enumerate(frames, 1):
        base = os.path.basename(f)                 # v0_0000.jpg
        stem = os.path.splitext(base)[0]           # v0_0000
        img = Image.open(f).convert("RGB")
        rgba = rmbg.remove_background(img)
        alpha = rgba.getchannel("A")               # L, white=shoe
        png = os.path.join(MASKS, stem + ".png")
        alpha.save(png)
        # COLMAP wants <fullname>.png (i.e. v0_0000.jpg.png)
        link = os.path.join(MASKS_COLMAP, base + ".png")
        if os.path.lexists(link):
            os.remove(link)
        try:
            os.link(png, link)
        except OSError:
            alpha.save(link)
        frac = np.asarray(alpha).mean() / 255.0
        cov.append(frac)
        if i % 20 == 0 or i == len(frames):
            print(f"  {i:3d}/{len(frames)}  {base}  fg={frac:.2%}")
    cov = np.array(cov)
    print(f"done. fg coverage: mean={cov.mean():.2%} min={cov.min():.2%} max={cov.max():.2%}")
    bad = [(os.path.basename(frames[i]), f"{cov[i]:.2%}")
           for i in range(len(cov)) if cov[i] < 0.03 or cov[i] > 0.97]
    print(f"suspicious masks (fg<3% or >97%): {bad if bad else 'none'}")


if __name__ == "__main__":
    main()
