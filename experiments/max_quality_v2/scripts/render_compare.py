#!/usr/bin/env python3
"""Render matched diagnostic views of a textured OpenMVS OBJ to compare two
reconstructions (e.g. full2 vs full3) on the two hard zones: the HEEL counter
and the INTERIOR cavity.

Orientation is recovered per-model because each SfM reconstruction lives in its
own arbitrary gauge:
  * up      -> from the COLMAP camera centres (mean(high-el) - mean(low-el));
              this is the robust sole->collar vertical.
  * length  -> toe<->heel axis from PCA of the MESH vertices, projected into the
              plane perpendicular to up (camera-centre PCA was unreliable).
  * width   -> up x length.
+length is flipped to point toward the foot OPENING (heel half).

It then renders an exterior ring (to locate/inspect the heel counter) and a set
of oblique into-cavity views on white bg (to expose any untextured "white hole"
through the foot opening).

Usage: render_compare.py <set:full2|full3> <outdir> [size=1100]
"""
import sys, os, json, math
import numpy as np, vtk
from vtk.util.numpy_support import vtk_to_numpy
from PIL import Image

SET = sys.argv[1]
OUTD = sys.argv[2]; os.makedirs(OUTD, exist_ok=True)
SIZE = int(sys.argv[3]) if len(sys.argv) > 3 else 1100
BASE = os.path.dirname(os.path.abspath(__file__))
ROOT = f"{BASE}/synthetic_ref/{SET}"
OBJ  = f"{ROOT}/openmvs/scene_textured.obj"
MTL  = f"{ROOT}/openmvs/scene_textured.mtl"
TEXD = f"{ROOT}/openmvs"
IMTXT= f"{ROOT}/ws/sparse/0/images.txt"
CAMJ = f"{ROOT}/cameras.json"


def qvec2R(w, x, y, z):
    return np.array([
        [1-2*(y*y+z*z), 2*(x*y-w*z),   2*(x*z+w*y)],
        [2*(x*y+w*z),   1-2*(x*x+z*z), 2*(y*z-w*x)],
        [2*(x*z-w*y),   2*(y*z+w*x),   1-2*(x*x+y*y)]])


# ---- up vector from COLMAP camera centres ----
el_of = {v["file"]: v["el"] for v in json.load(open(CAMJ))["views"]}
centers = {}
with open(IMTXT) as f:
    lines = [l for l in f if not l.startswith("#")]
for i in range(0, len(lines), 2):
    p = lines[i].split()
    if len(p) < 10:
        continue
    qw, qx, qy, qz, tx, ty, tz = map(float, p[1:8]); name = p[9]
    R = qvec2R(qw, qx, qy, qz); C = -R.T @ np.array([tx, ty, tz])
    centers[name] = C
hi = [C for n, C in centers.items() if el_of.get(n, 0) >= 50]
lo = [C for n, C in centers.items() if el_of.get(n, 0) <= -25]
up = (np.mean(hi, 0) - np.mean(lo, 0)); up = up / np.linalg.norm(up)

# ---- length axis from MESH-vertex PCA (perp to up) ----
verts = []
with open(OBJ) as f:
    for ln in f:
        if ln.startswith("v "):
            verts.append([float(x) for x in ln.split()[1:4]])
V = np.array(verts)
ctr = V.mean(0)
Q = V - ctr
Q = Q - np.outer(Q @ up, up)               # remove the up component
_, _, Vt = np.linalg.svd(Q, full_matrices=False)
length = Vt[0] / np.linalg.norm(Vt[0])
width = np.cross(up, length); width = width / np.linalg.norm(width)
# disambiguate the heel end: the foot OPENING is on the heel half, so the upper
# rim vertices (high along +up) skew toward the heel.  Flip length so +length
# points toward the heel (the opening side).
s = (V - ctr) @ up
rim = V[s > np.percentile(s, 75)]
if ((rim - ctr) @ length).mean() < 0:
    length = -length
print(f"{SET}: {len(centers)} cams  {len(V)} verts  up={np.round(up,3)}  length={np.round(length,3)}")

# ---- VTK scene from textured OBJ ----
ren = vtk.vtkRenderer()
renWin = vtk.vtkRenderWindow(); renWin.SetOffScreenRendering(1); renWin.AddRenderer(ren); renWin.SetSize(SIZE, SIZE)
imp = vtk.vtkOBJImporter(); imp.SetFileName(OBJ); imp.SetFileNameMTL(MTL); imp.SetTexturePath(TEXD)
imp.SetRenderWindow(renWin); imp.Update()
ren.UseImageBasedLightingOff(); ren.AutomaticLightCreationOff()
for lx, ly, lz, it in [(1,1,1,0.85),(-1,1,1,0.7),(1,1,-1,0.7),(-1,1,-1,0.6),(0,-1,0.3,0.5),(0,1,-0.3,0.5)]:
    L = vtk.vtkLight(); L.SetPosition(lx, ly, lz); L.SetFocalPoint(0,0,0); L.SetIntensity(it); L.SetLightTypeToSceneLight(); ren.AddLight(L)
# one-sided lighting so a genuine hole reads as background, not a back-lit surface
ren.SetTwoSidedLighting(0)
b = ren.ComputeVisiblePropBounds()
C3 = np.array([(b[0]+b[1])/2, (b[2]+b[3])/2, (b[4]+b[5])/2])
rad = 0.5*math.sqrt((b[1]-b[0])**2 + (b[3]-b[2])**2 + (b[5]-b[4])**2)
cam = ren.GetActiveCamera()


def shot(name, eye_dir, vup, dist, bg, focal=None, va=30):
    ren.SetBackground(*bg)
    fp = C3 if focal is None else focal
    pos = fp + eye_dir*dist
    cam.SetFocalPoint(*fp); cam.SetPosition(*pos); cam.SetViewUp(*vup)
    cam.SetViewAngle(va); ren.ResetCameraClippingRange(); renWin.Render()
    w2i = vtk.vtkWindowToImageFilter(); w2i.SetInput(renWin); w2i.SetInputBufferTypeToRGB(); w2i.ReadFrontBufferOff(); w2i.Update()
    im = w2i.GetOutput(); d = im.GetDimensions()
    a = vtk_to_numpy(im.GetPointData().GetScalars()).reshape(d[1], d[0], -1); a = np.flipud(a)[..., :3].astype(np.uint8)
    Image.fromarray(a).save(f"{OUTD}/{SET}_{name}.png"); print("  wrote", f"{SET}_{name}.png")


def dir_azel(az, el):
    a = math.radians(az); e = math.radians(el)
    return math.cos(e)*(math.cos(a)*length + math.sin(a)*width) + math.sin(e)*up


# HEEL exterior ring: low elevation, dark bg.  az=0 looks from the heel end.
for az in range(0, 360, 45):
    shot(f"ext_az{az:03d}", dir_azel(az, 12), up, 1.9*rad, (0.10, 0.11, 0.13))

# HEEL close-up from directly behind the counter (slightly above), dark bg.
shot("heel_behind", dir_azel(0, 18), up, 1.5*rad, (0.10, 0.11, 0.13), va=26)

# ---- locate the collar OPENING (the ankle hole): heel half (+length) + top ----
# It is offset from the mesh centre toward the heel and high along +up.  Use the
# centroid of the upper-rim vertices on the heel half as a robust aim point.
pl = (V - ctr) @ length
pu = (V - ctr) @ up
sel = (pl > 0.08*rad) & (pu > np.percentile(pu, 80))
opening = V[sel].mean(0) if sel.any() else (C3 + 0.30*rad*length + 0.20*rad*up)
print(f"  opening offset from centre: length={float((opening-C3)@length/rad):+.2f}rad"
      f"  up={float((opening-C3)@up/rad):+.2f}rad")
foc_in = opening - 0.06*rad*up                          # drop just below the rim

# INTERIOR straight down the opening (camera directly above, looking -up), white
# bg.  Aimed at the OPENING (not the forefoot) so we see into the ankle cavity.
shot("interior_top", up, length, 1.30*rad, (1, 1, 1), focal=foc_in, va=34)

# INTERIOR oblique sweep AROUND the opening looking down into the cavity (el~52).
# Orbiting the azimuth in the (length,width) plane exposes a gap on ANY inner
# wall as a white show-through; az=180 looks from the toe toward the heel-side
# inner wall (the wall that showed the white hole in full2).  White bg.
for az in (0, 90, 180, 270):
    a = math.radians(az); el = math.radians(52)
    horiz = math.cos(a)*length + math.sin(a)*width
    eye = math.cos(el)*horiz + math.sin(el)*up
    shot(f"interior_obl_az{az:03d}", eye, up, 1.35*rad, (1, 1, 1), focal=foc_in, va=36)
