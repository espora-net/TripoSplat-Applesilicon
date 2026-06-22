#!/usr/bin/env python3
"""Reference-benchmark turntable: flat/diffuse lighting, plain bg, high-res, montaged sheet."""
import sys, math, vtk
from PIL import Image

glb = sys.argv[1]
out_sheet = sys.argv[2] if len(sys.argv) > 2 else "/tmp/ref_sheet.png"
n = int(sys.argv[3]) if len(sys.argv) > 3 else 8
S = int(sys.argv[4]) if len(sys.argv) > 4 else 1100

ren = vtk.vtkRenderer()
ren.SetBackground(0.93, 0.93, 0.93)
renWin = vtk.vtkRenderWindow()
renWin.SetOffScreenRendering(1)
renWin.AddRenderer(ren)
renWin.SetSize(S, S)

imp = vtk.vtkGLTFImporter()
imp.SetFileName(glb)
imp.SetRenderWindow(renWin)
imp.Update()

# Flat, even, low-specular lighting so texture detail reads clearly.
ren.UseImageBasedLightingOff()
ren.AutomaticLightCreationOff()
for lx, ly, lz, inten in [(1,1,1,0.9),(-1,1,1,0.8),(1,1,-1,0.8),(-1,1,-1,0.7),(0,-1,0,0.5),(0,1,0,0.6)]:
    lt = vtk.vtkLight(); lt.SetPosition(lx,ly,lz); lt.SetFocalPoint(0,0,0)
    lt.SetIntensity(inten); lt.SetColor(1,1,1); lt.SetLightTypeToSceneLight()
    ren.AddLight(lt)
ren.SetTwoSidedLighting(1)

# Reduce specular on all imported actors (matte, texture-forward look).
acts = ren.GetActors(); acts.InitTraversal()
for _ in range(acts.GetNumberOfItems()):
    a = acts.GetNextActor(); p = a.GetProperty()
    p.SetSpecular(0.05); p.SetSpecularPower(8); p.SetAmbient(0.30); p.SetDiffuse(1.0)

cam = ren.GetActiveCamera()
cam.Elevation(14)
ren.ResetCamera()
cam.Zoom(1.30)
ren.ResetCameraClippingRange()

tiles = []
for i in range(n):
    if i:
        cam.Azimuth(360.0 / n); cam.OrthogonalizeViewUp(); ren.ResetCameraClippingRange()
    renWin.Render()
    w2i = vtk.vtkWindowToImageFilter(); w2i.SetInput(renWin); w2i.ReadFrontBufferOff(); w2i.Update()
    png = vtk.vtkPNGWriter(); out = f"/tmp/_ref_{i:02d}.png"
    png.SetFileName(out); png.SetInputConnection(w2i.GetOutputPort()); png.Write()
    tiles.append(out)

cols = 4; rows = (n + cols - 1)//cols
sheet = Image.new("RGB", (cols*S, rows*S), (255,255,255))
for idx, t in enumerate(tiles):
    im = Image.open(t).convert("RGB")
    sheet.paste(im, ((idx%cols)*S, (idx//cols)*S))
sheet.save(out_sheet)
print("wrote", out_sheet, sheet.size)
