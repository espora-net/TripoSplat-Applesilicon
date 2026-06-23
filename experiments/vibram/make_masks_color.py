#!/usr/bin/env python3
"""Robust foreground masks for "dark shoe on uniform light-wood floor".

BiRefNet (salient-object) is unreliable here: on several frames it returned a
near-empty matte (just the orange logo) or only half the shoe.  An empty/partial
mask is catastrophic for COLMAP (no SIFT on that frame -> frame won't register).

This segmenter is purpose-built for the scene geometry instead of a learned prior:
  1. Model the FLOOR colour from a border ring (border pixels are ~always floor)
     as a Gaussian in LAB.  The shoe (neutral/olive/grey) is chromatically far
     from the warm wood tan, even where brightness is similar.
  2. Foreground = pixels whose Mahalanobis distance to the floor model exceeds a
     threshold -> a rough but COMPLETE shoe blob.
  3. GrabCut, initialised from that rough blob (sure-FG eroded, sure-BG = the
     low-distance ring), to snap to crisp edges.
  4. Keep the largest central connected component, fill holes, light close.

Writes masks/<stem>.png (white=shoe) + hard-links masks_colmap/<name>.jpg.png.
"""
import os
import sys
import glob
import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMES = os.path.join(HERE, "recon", "images_orig")
MASKS = os.path.join(HERE, "recon", "masks")
MASKS_COLMAP = os.path.join(HERE, "recon", "masks_colmap")

DIST = float(os.environ.get("DIST", "3.2"))     # Mahalanobis FG threshold (LAB)
ONLY = os.environ.get("ONLY", "")               # substring filter for quick tests


def floor_model(lab):
    h, w = lab.shape[:2]
    b = max(6, h // 16)
    ring = np.concatenate([
        lab[:b].reshape(-1, 3), lab[-b:].reshape(-1, 3),
        lab[:, :b].reshape(-1, 3), lab[:, -b:].reshape(-1, 3),
    ]).astype(np.float64)
    mu = ring.mean(0)
    cov = np.cov(ring.T) + np.eye(3) * 1e-3
    return mu, np.linalg.inv(cov)


def _fill_holes(m):
    """Fill enclosed holes robustly even when the object touches image corners.

    Pad with a 1px background ring and flood from the padded corner (guaranteed
    background), so the outer region is never mistaken for a hole."""
    h, w = m.shape
    pad = cv2.copyMakeBorder(m, 1, 1, 1, 1, cv2.BORDER_CONSTANT, value=0)
    ff = pad.copy()
    cv2.floodFill(ff, np.zeros((h + 4, w + 4), np.uint8), (0, 0), 1)
    ff = ff[1:-1, 1:-1]
    return (m | (1 - ff)).astype(np.uint8)


def _largest_central_cc(m, w, h):
    n, cc, stats, cents = cv2.connectedComponentsWithStats(m, 8)
    if n <= 1:
        return m
    cx, cy = w / 2, h / 2
    best, bestscore = 0, -1.0
    for i in range(1, n):
        area = stats[i, cv2.CC_STAT_AREA]
        if area < 0.01 * h * w:
            continue
        dc = ((cents[i][0] - cx) ** 2 + (cents[i][1] - cy) ** 2) ** 0.5
        score = area - 5.0 * dc
        if score > bestscore:
            bestscore, best = score, i
    return (cc == best).astype(np.uint8) if bestscore >= 0 else m


def segment(bgr):
    """Floor-colour Mahalanobis blob + morphology (NO GrabCut -> no floor leak).

    The breathable mesh shows the (floor-coloured) ground through it, so those
    pixels read as background; a large CLOSE bridges them and fill-holes recovers
    the interior, giving a COMPLETE shoe silhouette with minimal floor."""
    h, w = bgr.shape[:2]
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB).astype(np.float64)
    mu, icov = floor_model(lab)
    d = lab.reshape(-1, 3) - mu
    maha = np.sqrt(np.einsum("ij,jk,ik->i", d, icov, d)).reshape(h, w)

    m = (maha > DIST).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))   # despeckle
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((21, 21), np.uint8))  # bridge mesh holes
    m = _largest_central_cc(m, w, h)
    m = _fill_holes(m)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    m = _largest_central_cc(m, w, h)
    m = _fill_holes(m)
    m = cv2.dilate(m, np.ones((3, 3), np.uint8))   # ensure full shoe coverage
    return (m * 255).astype(np.uint8)


def main():
    os.makedirs(MASKS, exist_ok=True)
    os.makedirs(MASKS_COLMAP, exist_ok=True)
    frames = sorted(glob.glob(f"{FRAMES}/*.jpg"))
    if ONLY:
        frames = [f for f in frames if ONLY in os.path.basename(f)]
    print(f"{len(frames)} frames  DIST={DIST}")
    cov = []
    for i, f in enumerate(frames, 1):
        base = os.path.basename(f)
        stem = os.path.splitext(base)[0]
        bgr = cv2.imread(f)
        m = segment(bgr)
        png = os.path.join(MASKS, stem + ".png")
        cv2.imwrite(png, m)
        link = os.path.join(MASKS_COLMAP, base + ".png")
        if os.path.lexists(link):
            os.remove(link)
        try:
            os.link(png, link)
        except OSError:
            cv2.imwrite(link, m)
        frac = m.mean() / 255.0
        cov.append(frac)
        if i % 20 == 0 or i == len(frames):
            print(f"  {i:3d}/{len(frames)}  {base}  fg={frac:.2%}")
    cov = np.array(cov)
    print(f"done. fg coverage: mean={cov.mean():.2%} min={cov.min():.2%} max={cov.max():.2%}")
    bad = [(os.path.basename(frames[i]), f"{cov[i]:.2%}")
           for i in range(len(cov)) if cov[i] < 0.04 or cov[i] > 0.9]
    print(f"suspicious masks (fg<4% or >90%): {bad if bad else 'none'}")


if __name__ == "__main__":
    main()
