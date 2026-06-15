#!/usr/bin/env python3
"""Render a COLMAP sparse model (cameras + colored point cloud) to PNGs.

Reads a COLMAP text model (cameras.txt / images.txt / points3D.txt) and writes
two figures next to it:
  * <out>_cameras.png : camera centers + the point cloud from 3 angles
  * <out>_object.png  : the point cloud only, from 3 angles, colored

Usage:
  python visualize_model.py ws_all/sparse/2 /tmp/recon
"""
import sys
import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


def quat_to_R(qw, qx, qy, qz):
    n = (qw * qw + qx * qx + qy * qy + qz * qz) ** 0.5
    qw, qx, qy, qz = qw / n, qx / n, qy / n, qz / n
    return np.array(
        [
            [1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw)],
            [2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw)],
            [2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy)],
        ]
    )


def read_images(path):
    """Return camera centers C = -R^T t (world coords), one per registered image."""
    centers = []
    with open(path) as f:
        lines = [ln for ln in f if not ln.startswith("#")]
    # Each image = 2 lines: pose line, then keypoints line (skip the latter).
    for i in range(0, len(lines), 2):
        p = lines[i].split()
        if len(p) < 8:
            continue
        qw, qx, qy, qz = map(float, p[1:5])
        tx, ty, tz = map(float, p[5:8])
        R = quat_to_R(qw, qx, qy, qz)
        C = -R.T @ np.array([tx, ty, tz])
        centers.append(C)
    return np.array(centers)


def read_points(path):
    xyz, rgb = [], []
    with open(path) as f:
        for ln in f:
            if ln.startswith("#"):
                continue
            p = ln.split()
            if len(p) < 7:
                continue
            xyz.append([float(p[1]), float(p[2]), float(p[3])])
            rgb.append([int(p[4]), int(p[5]), int(p[6])])
    return np.array(xyz), np.array(rgb) / 255.0


def main():
    model = sys.argv[1] if len(sys.argv) > 1 else "ws_all/sparse/2"
    out = sys.argv[2] if len(sys.argv) > 2 else "recon"
    centers = read_images(f"{model}/images.txt")
    xyz, rgb = read_points(f"{model}/points3D.txt")

    # Robust center/scale on the points (ignore outliers via percentiles).
    lo, hi = np.percentile(xyz, 2, 0), np.percentile(xyz, 98, 0)
    mid = (lo + hi) / 2
    span = (hi - lo).max() * 0.6
    keep = np.all((xyz > lo - span) & (xyz < hi + span), axis=1)
    xyz_k, rgb_k = xyz[keep], rgb[keep]
    print(f"points={len(xyz)} (kept {len(xyz_k)}) cameras={len(centers)}")
    print(f"extent ratio={np.round((hi - lo) / (hi - lo).max(), 2)}")

    angles = [(20, -60), (20, 30), (80, -90)]

    fig = plt.figure(figsize=(15, 5))
    for k, (el, az) in enumerate(angles, 1):
        ax = fig.add_subplot(1, 3, k, projection="3d")
        ax.scatter(xyz_k[:, 0], xyz_k[:, 1], xyz_k[:, 2], c=rgb_k, s=2)
        if len(centers):
            ax.scatter(centers[:, 0], centers[:, 1], centers[:, 2],
                       c="red", marker="^", s=18, label="cameras")
        ax.set_title(f"cameras+points  el={el} az={az}")
        ax.view_init(el, az)
        ax.set_xlim(mid[0] - span, mid[0] + span)
        ax.set_ylim(mid[1] - span, mid[1] + span)
        ax.set_zlim(mid[2] - span, mid[2] + span)
        if k == 1:
            ax.legend(loc="upper right")
    fig.tight_layout()
    fig.savefig(f"{out}_cameras.png", dpi=110)
    print(f"wrote {out}_cameras.png")

    fig = plt.figure(figsize=(15, 5))
    for k, (el, az) in enumerate(angles, 1):
        ax = fig.add_subplot(1, 3, k, projection="3d")
        ax.scatter(xyz_k[:, 0], xyz_k[:, 1], xyz_k[:, 2], c=rgb_k, s=3)
        ax.set_title(f"point cloud  el={el} az={az}")
        ax.view_init(el, az)
        ax.set_xlim(mid[0] - span, mid[0] + span)
        ax.set_ylim(mid[1] - span, mid[1] + span)
        ax.set_zlim(mid[2] - span, mid[2] + span)
        ax.set_axis_off()
    fig.tight_layout()
    fig.savefig(f"{out}_object.png", dpi=110)
    print(f"wrote {out}_object.png")


if __name__ == "__main__":
    main()
