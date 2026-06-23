#!/usr/bin/env python3
"""Final foreground masks for the Vibram frames: u2net (rembg) primary, with a
floor-colour fallback for the few frames u2net fails on, plus morphological
cleanup. White=shoe.

Why this combo:
  * rembg/u2net segments the centred shoe cleanly on 7/8 test frames (BiRefNet
    and isnet were less consistent on this low-res dark-shoe-on-wood scene).
  * On the hard steep-interior frames u2net occasionally returns a near-empty
    matte; we then try the floor-colour Mahalanobis segmenter.  If BOTH are
    implausible the frame keeps its (tiny) u2net mask -> it simply contributes
    few features and likely won't register, which is fine.
  * Cleanup: largest central connected component + fill holes + small dilate, so
    COLMAP sees a COMPLETE shoe silhouette (the breathable mesh otherwise punches
    floor-coloured holes through the matte).

Outputs masks/<stem>.png and hard-links masks_colmap/<name>.jpg.png.
"""
import os
import sys
import glob
import cv2
import numpy as np

os.environ.setdefault("U2NET_HOME", os.path.expanduser("~/.u2net"))
from rembg import new_session, remove  # noqa: E402
from PIL import Image  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from make_masks_color import floor_model, _fill_holes, _largest_central_cc  # noqa: E402

FRAMES = os.path.join(HERE, "recon", "images_orig")
MASKS = os.path.join(HERE, "recon", "masks")
MASKS_COLMAP = os.path.join(HERE, "recon", "masks_colmap")
LO, HI = 0.07, 0.85          # plausible foreground fraction
DIST = float(os.environ.get("DIST", "3.2"))


def color_mask(bgr):
    h, w = bgr.shape[:2]
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB).astype(np.float64)
    mu, icov = floor_model(lab)
    d = lab.reshape(-1, 3) - mu
    maha = np.sqrt(np.einsum("ij,jk,ik->i", d, icov, d)).reshape(h, w)
    m = (maha > DIST).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8))
    m = _largest_central_cc(m, w, h)
    m = _fill_holes(m)
    return m


def cleanup(m, w, h):
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((13, 13), np.uint8))
    m = _largest_central_cc(m, w, h)
    m = _fill_holes(m)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    m = cv2.dilate(m, np.ones((3, 3), np.uint8))
    return m


def main():
    os.makedirs(MASKS, exist_ok=True)
    os.makedirs(MASKS_COLMAP, exist_ok=True)
    sess = new_session("u2net")
    frames = sorted(glob.glob(f"{FRAMES}/*.jpg"))
    print(f"{len(frames)} frames")
    cov, fellback, dropped = [], [], []
    for i, f in enumerate(frames, 1):
        base = os.path.basename(f)
        stem = os.path.splitext(base)[0]
        bgr = cv2.imread(f)
        h, w = bgr.shape[:2]
        pil = Image.open(f).convert("RGB")
        a = np.asarray(remove(pil, session=sess).getchannel("A"))
        m = cleanup((a >= 128).astype(np.uint8), w, h)
        if not (LO <= m.mean() <= HI):             # cleaned u2net implausible -> colour
            mc = cleanup(color_mask(bgr), w, h)
            if LO <= mc.mean() <= HI:
                m = mc
                fellback.append(stem)
            else:
                dropped.append((stem, f"u2={m.mean():.2%} col={mc.mean():.2%}"))
                if mc.mean() < m.mean():            # keep the less-leaky of the two
                    m = mc
        png = os.path.join(MASKS, stem + ".png")
        cv2.imwrite(png, (m * 255).astype(np.uint8))
        link = os.path.join(MASKS_COLMAP, base + ".png")
        if os.path.lexists(link):
            os.remove(link)
        try:
            os.link(png, link)
        except OSError:
            cv2.imwrite(link, (m * 255).astype(np.uint8))
        cov.append(m.mean())
        if i % 30 == 0 or i == len(frames):
            print(f"  {i:3d}/{len(frames)}  {base}  fg={m.mean():.2%}")
    cov = np.array(cov)
    print(f"done. fg mean={cov.mean():.2%} min={cov.min():.2%} max={cov.max():.2%}")
    print(f"colour-fallback frames ({len(fellback)}): {fellback}")
    print(f"implausible/likely-to-drop ({len(dropped)}): {dropped}")


if __name__ == "__main__":
    main()
