#!/usr/bin/env python3
"""Synthetic capture rig: render flat-lit, plain-bg RGB + alpha masks from a GLB.

Usage: render_synthetic.py <plain.glb> <outdir> <mode:full|full2|side> [size=1280]

Modes:
  full   ~90 views  : 3 elevation rings x 24 az + high/low rings + top + sole.
  full2  ~108 views : full + two dense "looking-into-the-collar" rings
                      (el 60 x12, el 72 x6). These give dense MVS photo-consistent
                      evidence of the concave foot-opening so the textureless upper
                      is NOT bridged into a smooth dome (recovers the laced throat
                      and open collar). Use this for the best surface quality.
  full3  ~161 views : full2 + CLOSE-UP (zoomed) into-cavity rings + a near-overhead
                      footbed view + a CLOSE heel/quarter ring. full2's into-collar
                      views frame the WHOLE shoe, so the interior gets few pixels and
                      reconstructs as an untextured "hole"; full3 zooms onto the
                      opening (dist scale ~0.6, focal raised onto the rim) so the
                      inner walls + footbed + heel-cup densify and get TEXTURE, and a
                      closer low-texture heel ring de-blobs the suede heel counter.
  side   ~27 views  : limited frontal-left arc (mimics the original video bias).

Each view is (az_deg, el_deg, dist_scale, focal_rise_in_R): dist_scale<1 zooms in
(more pixels on the target); focal_rise lifts the look-at point by that fraction of
the object radius along +Y (onto the foot-opening rim).

Emits:
  <outdir>/images/view_####.jpg     (object on neutral gray, flat lighting)
  <outdir>/masks/view_####.png       (white silhouette on black, from z-buffer)
  <outdir>/cameras.json              (intrinsics + per-view world->cam, for optional known poses)
"""
import sys, os, json, math
import numpy as np
import vtk
from vtk.util.numpy_support import vtk_to_numpy
from PIL import Image

glb, outdir, mode = sys.argv[1], sys.argv[2], sys.argv[3]
S = int(sys.argv[4]) if len(sys.argv) > 4 else 1280
os.makedirs(os.path.join(outdir, "images"), exist_ok=True)
os.makedirs(os.path.join(outdir, "masks"), exist_ok=True)

ren = vtk.vtkRenderer()
ren.SetBackground(0.5, 0.5, 0.5)
renWin = vtk.vtkRenderWindow()
renWin.SetOffScreenRendering(1)
renWin.AddRenderer(ren)
renWin.SetSize(S, S)

imp = vtk.vtkGLTFImporter()
imp.SetFileName(glb)
imp.SetRenderWindow(renWin)
imp.Update()

ren.UseImageBasedLightingOff()
ren.AutomaticLightCreationOff()
for lx, ly, lz, inten in [(1,1,1,0.8),(-1,1,1,0.7),(1,1,-1,0.7),(-1,1,-1,0.6),
                          (0,-1,0.3,0.5),(0,1,-0.3,0.5),(1,-0.3,0,0.4),(-1,-0.3,0,0.4)]:
    lt = vtk.vtkLight(); lt.SetPosition(lx,ly,lz); lt.SetFocalPoint(0,0,0)
    lt.SetIntensity(inten); lt.SetColor(1,1,1); lt.SetLightTypeToSceneLight()
    ren.AddLight(lt)
ren.SetTwoSidedLighting(1)

acts = ren.GetActors(); acts.InitTraversal()
for _ in range(acts.GetNumberOfItems()):
    a = acts.GetNextActor(); p = a.GetProperty()
    p.SetSpecular(0.04); p.SetSpecularPower(8); p.SetAmbient(0.32); p.SetDiffuse(1.0)

ren.ResetCamera()
b = ren.ComputeVisiblePropBounds()
C = np.array([(b[0]+b[1])/2,(b[2]+b[3])/2,(b[4]+b[5])/2])
R = 0.5*math.sqrt((b[1]-b[0])**2+(b[3]-b[2])**2+(b[5]-b[4])**2)
cam = ren.GetActiveCamera()
fov = cam.GetViewAngle()  # degrees, vertical
dist = R / math.sin(math.radians(fov/2)) * 0.72  # frame with margin (no edge clipping)

def view_list(mode):
    # each entry: (az, el, dist_scale, focal_rise_R)
    vs = []
    if mode in ("full", "full2", "full3"):
        for el in (-25, 0, 25):
            for az in range(0, 360, 15):   # 24 each -> 72
                vs.append((az, el, 1.0, 0.0))
        for el in (-50, 50):
            for az in range(0, 360, 45):   # 8 each -> 16
                vs.append((az, el, 1.0, 0.0))
        vs.append((0, 82, 1.0, 0.0)); vs.append((0, -82, 1.0, 0.0))   # top + sole
        if mode in ("full2", "full3"):
            # Dense "looking-into-the-collar" rings: the foot opening is a concave
            # cavity walled by the (textured) magenta lining + tan footbed. Extra
            # oblique-from-above views give dense MVS photo-consistent evidence of
            # the concavity so the mesher does not bridge it into a smooth dome.
            for az in range(0, 360, 30):   # 12
                vs.append((az, 60, 1.0, 0.0))
            for az in range(0, 360, 60):   # 6
                vs.append((az, 72, 1.0, 0.0))
        if mode == "full3":
            # CLOSE-UP into-cavity rings: same oblique-from-above angles but ZOOMED
            # onto the opening (dist_scale ~0.6) with the focal point lifted onto the
            # rim (+0.12 R). full2's into-collar views frame the whole shoe so the
            # interior is only a few hundred pixels -> reconstructs as an untextured
            # hole; zooming in multiplies the interior pixel density so DensifyPoint-
            # Cloud fills the inner walls + footbed + heel-cup AND TextureMesh gets
            # real texture there.
            for az in range(0, 360, 24):   # 15
                vs.append((az, 60, 0.60, 0.12))
            for az in range(0, 360, 30):   # 12
                vs.append((az, 74, 0.58, 0.12))
            vs.append((0, 86, 0.60, 0.0))  # near-overhead -> footbed straight down
            # CLOSE heel / quarter ring: the suede heel counter is low-texture, so at
            # full distance MVS over-smooths it into a blob. A closer ring (more
            # pixels) + RefineMesh sharpens the heel edge and seams.
            for az in range(0, 360, 24):   # 15
                vs.append((az, 2, 0.72, 0.0))
            for az in range(0, 360, 36):   # 10
                vs.append((az, -16, 0.72, 0.0))
    else:  # side-biased control: limited frontal-left arc, few elevations
        for el in (0, 15, 30):
            for az in list(range(300, 360, 15)) + list(range(0, 75, 15)):  # ~9 az
                vs.append((az, el, 1.0, 0.0))
    return vs

views = view_list(mode)

def cam_dir(az, el):
    a = math.radians(az); e = math.radians(el)
    return np.array([math.cos(e)*math.sin(a), math.sin(e), math.cos(e)*math.cos(a)])

cams = {"fov_deg": fov, "size": S, "views": []}
for i, (az, el, dscale, frise) in enumerate(views):
    d = cam_dir(az, el)
    pos = C + dist * dscale * d
    foc = C + np.array([0.0, frise * R, 0.0])
    cam.SetFocalPoint(*foc)
    cam.SetPosition(*pos)
    up = (0,1,0) if abs(el) < 70 else (0,0,-1 if el > 0 else 1)
    cam.SetViewUp(*up)
    ren.ResetCameraClippingRange()
    renWin.Render()

    # RGB
    w2i = vtk.vtkWindowToImageFilter(); w2i.SetInput(renWin)
    w2i.SetInputBufferTypeToRGB(); w2i.ReadFrontBufferOff(); w2i.Update()
    img = w2i.GetOutput()
    dims = img.GetDimensions()
    arr = vtk_to_numpy(img.GetPointData().GetScalars()).reshape(dims[1], dims[0], -1)
    arr = np.flipud(arr)[..., :3].astype(np.uint8)
    Image.fromarray(arr).save(os.path.join(outdir,"images",f"view_{i:04d}.jpg"), quality=95)

    # Mask from z-buffer (bg z==1.0)
    z2i = vtk.vtkWindowToImageFilter(); z2i.SetInput(renWin)
    z2i.SetInputBufferTypeToZBuffer(); z2i.ReadFrontBufferOff(); z2i.Update()
    zimg = z2i.GetOutput()
    zarr = vtk_to_numpy(zimg.GetPointData().GetScalars()).reshape(dims[1], dims[0])
    zarr = np.flipud(zarr)
    mask = (zarr < 0.999).astype(np.uint8) * 255
    Image.fromarray(mask).save(os.path.join(outdir,"masks",f"view_{i:04d}.png"))

    cams["views"].append({"file": f"view_{i:04d}.jpg", "az": az, "el": el,
                          "pos": pos.tolist(), "focal": foc.tolist(), "up": list(up)})

with open(os.path.join(outdir, "cameras.json"), "w") as f:
    json.dump(cams, f, indent=1)
print(f"mode={mode} wrote {len(views)} views to {outdir}")
