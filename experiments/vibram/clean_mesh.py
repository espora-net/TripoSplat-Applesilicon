#!/usr/bin/env python3
"""Remove small disconnected 'floater' fragments (mask-edge specks) from the
OpenMVS textured mesh while preserving the UV texture, then write a clean OBJ.

Memory-light + UV-safe: the OBJ has per-corner (unwelded) vertices, so naive
split() treats every face as its own component.  We instead WELD vertices by
rounding coordinates purely to compute connectivity, label each original face by
its connected component, keep the main body plus any component >= FRAC of the
largest, and slice with submesh() so the original per-face UVs are preserved.
"""
import os
import sys
import numpy as np
import trimesh
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

src = sys.argv[1]
dst = sys.argv[2]
FRAC = float(os.environ.get("FRAC", "0.02"))
DECIMALS = int(os.environ.get("DECIMALS", "5"))

m = trimesh.load(src, process=False)
if isinstance(m, trimesh.Scene):
    m = trimesh.util.concatenate([g for g in m.geometry.values()])
F = m.faces
print(f"loaded: {len(m.vertices)} verts {len(F)} faces  "
      f"has_uv={getattr(m.visual, 'uv', None) is not None}")

# weld vertices by rounded position -> connectivity labels (does NOT modify mesh)
q = np.round(m.vertices.astype(np.float64), DECIMALS)
_, weld = np.unique(q, axis=0, return_inverse=True)
weld = weld.reshape(-1)
wf = weld[F]                                   # (nF,3) welded vertex ids
nv = int(weld.max()) + 1
e = np.vstack([wf[:, [0, 1]], wf[:, [1, 2]], wf[:, [2, 0]]])
g = coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(nv, nv))
ncomp, vlabel = connected_components(g, directed=False)
flabel = vlabel[wf[:, 0]]                       # component per face
counts = np.bincount(flabel)
biggest = counts.max()
keep_comps = np.where(counts >= FRAC * biggest)[0]
fmask = np.isin(flabel, keep_comps)
print(f"{ncomp} components; top5 face-counts={sorted(counts)[-5:]}; "
      f"keep {len(keep_comps)} comps -> {int(fmask.sum())} faces "
      f"(removed {int((~fmask).sum())})")

keep = m.submesh([fmask], append=True, repair=False)
keep.export(dst)
print("wrote", dst, os.path.getsize(dst), "bytes; uv preserved=",
      getattr(keep.visual, "uv", None) is not None)
