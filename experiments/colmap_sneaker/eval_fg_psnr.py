#!/usr/bin/env python3
"""Foreground-only PSNR/SSIM for brush eval renders (Part C).

brush trains with background MASKS (default AlphaMode::Masked), so the model
renders a BLACK background and only reconstructs the masked foreground (the
sneaker). brush's built-in eval PSNR, however, is computed over the FULL image
against the original frames -- whose backgrounds are bright animated light
streaks -- so it reads absurdly low (~5-6 dB) and is meaningless here.

This script reports the metric that actually matters: PSNR computed over the
FOREGROUND pixels only (mask > 127), i.e. how well the reconstructed sneaker
matches the held-out ground-truth views. Run it against any eval_<iter>/ dir
brush wrote with --eval-save-to-disk.

Usage:  python3 eval_fg_psnr.py [eval_dir]
        (default: tools/brush/out/full/eval_<largest iter>)
"""
import glob
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMES = f"{HERE}/frames_all"
MASKS = f"{HERE}/gsplat_dataset/masks"


def latest_eval_dir():
    cands = glob.glob(f"{HERE}/tools/brush/out/full/eval_*")
    if not cands:
        sys.exit("no eval_* dirs found; run training with --eval-save-to-disk")
    return max(cands, key=lambda d: int(d.rsplit("_", 1)[1]))


def psnr(a, b, m=None):
    d = (a - b) ** 2
    d = d[m] if m is not None else d
    mse = float(d.mean())
    return 10 * np.log10(255.0 ** 2 / max(mse, 1e-9))


def main():
    ev_dir = sys.argv[1] if len(sys.argv) > 1 else latest_eval_dir()
    print(f"eval dir: {ev_dir}")
    rows = []
    for ev in sorted(glob.glob(f"{ev_dir}/*.png")):
        name = os.path.splitext(os.path.basename(ev))[0]
        gt = np.asarray(Image.open(f"{FRAMES}/{name}.jpg").convert("RGB")).astype(np.float32)
        pr = np.asarray(Image.open(ev).convert("RGB")).astype(np.float32)
        mimg = Image.open(f"{MASKS}/{name}.jpg").convert("L")
        m = np.asarray(mimg)
        fg = m > 127
        if gt.shape != pr.shape or fg.sum() < 100:
            continue
        # Out-of-mask LEAKAGE / floater check: dilate the foreground mask, then
        # measure how much "ink" the render paints OUTSIDE it (the render bg is
        # black under masked training, so any non-black there = floaters/leakage).
        # This catches what foreground-only PSNR is blind to (rubber-duck caveat).
        dil = np.asarray(mimg.filter(ImageFilter.MaxFilter(15))) > 127
        out = ~dil
        lum = pr.mean(axis=2)
        leak_frac = float((lum[out] > 10).mean())          # % of bg pixels lit
        leak_energy = float(lum[out].mean())               # mean bg brightness (0=clean)
        rows.append((name, psnr(gt, pr), psnr(gt, pr, fg), float(fg.mean()),
                     leak_frac, leak_energy))

    print(f"{'view':12s} {'full':>7s} {'fg':>7s} {'fg%':>6s} {'leak%':>7s} {'leakLum':>7s}")
    for n, pf, pg, fr, lf, le in rows:
        print(f"{n:12s} {pf:7.2f} {pg:7.2f} {fr*100:5.1f}% {lf*100:6.2f}% {le:7.2f}")
    print("-" * 56)
    n = len(rows)
    print(f"MEAN over {n} held-out views:  full={sum(r[1] for r in rows)/n:.2f} dB   "
          f"foreground={sum(r[2] for r in rows)/n:.2f} dB")
    print(f"  out-of-mask leakage: {sum(r[4] for r in rows)/n*100:.2f}% of bg pixels lit, "
          f"mean bg luminance {sum(r[5] for r in rows)/n:.2f}/255 (0 = clean, no floaters)")
    print("(foreground PSNR measures appearance INSIDE the object mask only; the "
          "leakage row measures floaters/background spill OUTSIDE a dilated mask.)")


if __name__ == "__main__":
    main()
