#!/usr/bin/env python3
"""Extract the sharpest, well-spread frames from the 5 handheld WhatsApp clips of
the Vibram shoe, for a COLMAP -> OpenMVS photogrammetric reconstruction.

Why not just dump every frame ("maximo de fotogramas")?  These are 30 fps handheld
clips: consecutive frames are near-duplicates and many are motion-blurred.  Feeding
hundreds of blurry near-dupes to COLMAP hurts SIFT matching and explodes the
exhaustive O(n^2) cost.  So we keep the *maximum useful* set: split each clip into
TARGET segments and keep the SHARPEST frame (max variance-of-Laplacian) in each,
guaranteeing temporal spread + sharp frames.

Mixed orientation: 4 clips are landscape 848x478, one is portrait 478x850.  COLMAP
--single_camera 1 needs uniform dimensions, so portrait frames are transposed to
850x478 and centre-cropped to 848x478 (the camera solves global orientation itself).

Outputs flat, provenance-prefixed JPEGs (v{clip}_{idx:04d}.jpg) into images_orig/.
"""
import os
import sys
import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))

# clip index -> filename (kept in capture order: sole, interior, ?, long-side, side)
VIDEOS = [
    "WhatsApp Video 2026-06-23 at 14.11.39.mp4",
    "WhatsApp Video 2026-06-23 at 14.11.42.mp4",
    "WhatsApp Video 2026-06-23 at 14.11.57 (1).mp4",
    "WhatsApp Video 2026-06-23 at 14.11.57 (2).mp4",
    "WhatsApp Video 2026-06-23 at 14.11.57.mp4",
]

OUT = os.path.join(HERE, "recon", "images_orig")
TARGET_W, TARGET_H = 848, 478          # uniform landscape dimensions
TOTAL = int(os.environ.get("TOTAL", "320"))   # total frames across all clips
SHARP_FLOOR = float(os.environ.get("SHARP_FLOOR", "0.55"))  # drop a segment's pick
#  if its sharpness < SHARP_FLOOR * clip-median (whole segment was too blurry)


def sharpness(gray):
    return cv2.Laplacian(gray, cv2.CV_64F).var()


def to_landscape(frame):
    h, w = frame.shape[:2]
    if h > w:                                   # portrait -> transpose to landscape
        frame = cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
        h, w = frame.shape[:2]
    if (w, h) != (TARGET_W, TARGET_H):          # centre-crop / pad to exact size
        # crop first if larger
        if w > TARGET_W:
            x0 = (w - TARGET_W) // 2
            frame = frame[:, x0:x0 + TARGET_W]
        if h > TARGET_H:
            y0 = (h - TARGET_H) // 2
            frame = frame[y0:y0 + TARGET_H, :]
        h, w = frame.shape[:2]
        if (w, h) != (TARGET_W, TARGET_H):      # pad if smaller (rare)
            frame = cv2.copyMakeBorder(frame, 0, max(0, TARGET_H - h),
                                       0, max(0, TARGET_W - w),
                                       cv2.BORDER_REPLICATE)
            frame = frame[:TARGET_H, :TARGET_W]
    return frame


def probe(path):
    cap = cv2.VideoCapture(path)
    n = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    cap.release()
    return n


def main():
    os.makedirs(OUT, exist_ok=True)
    # remove any prior extraction so re-runs are clean
    for f in os.listdir(OUT):
        if f.endswith(".jpg"):
            os.remove(os.path.join(OUT, f))

    counts = [probe(os.path.join(HERE, v)) for v in VIDEOS]
    total_frames = sum(counts)
    # distribute the TOTAL budget across clips proportionally to their length
    budgets = [max(8, round(TOTAL * c / total_frames)) for c in counts]
    print(f"clip frame counts: {counts}  total={total_frames}")
    print(f"per-clip budgets : {budgets}  (TOTAL~{sum(budgets)})")

    kept_total = 0
    for ci, (vid, nframes, budget) in enumerate(zip(VIDEOS, counts, budgets)):
        path = os.path.join(HERE, vid)
        cap = cv2.VideoCapture(path)
        # first pass: sharpness of every frame (downscaled gray for speed)
        sharps = np.zeros(nframes, dtype=np.float64)
        idx = 0
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            g = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            g = cv2.resize(g, (g.shape[1] // 2, g.shape[0] // 2))
            sharps[idx] = sharpness(g)
            idx += 1
        nframes = idx
        cap.release()
        median = float(np.median(sharps[:nframes])) if nframes else 0.0

        # split into `budget` segments, take the sharpest frame in each
        edges = np.linspace(0, nframes, budget + 1).astype(int)
        picks = []
        for a, b in zip(edges[:-1], edges[1:]):
            if b <= a:
                continue
            seg = sharps[a:b]
            j = a + int(np.argmax(seg))
            if sharps[j] >= SHARP_FLOOR * median:     # skip wholly-blurry segments
                picks.append(j)
        picks = sorted(set(picks))

        # second pass: write the chosen frames
        cap = cv2.VideoCapture(path)
        want = set(picks)
        idx = 0
        seq = 0
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            if idx in want:
                out = to_landscape(frame)
                name = f"v{ci}_{seq:04d}.jpg"
                cv2.imwrite(os.path.join(OUT, name),
                            out, [cv2.IMWRITE_JPEG_QUALITY, 95])
                seq += 1
            idx += 1
        cap.release()
        kept_total += seq
        print(f"  clip v{ci}: {vid[-18:]:>18}  frames={nframes:4d} "
              f"median_sharp={median:8.1f}  kept={seq}")

    print(f"TOTAL kept: {kept_total} frames -> {OUT}")


if __name__ == "__main__":
    sys.exit(main())
