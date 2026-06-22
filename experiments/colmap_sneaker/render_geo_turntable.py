#!/usr/bin/env python3
"""Clay-render a PLY mesh (no texture) from N turntable angles -> montage."""
import sys, vtk
from PIL import Image

ply = sys.argv[1]
out_sheet = sys.argv[2] if len(sys.argv) > 2 else "/tmp/geo_sheet.png"
n = int(sys.argv[3]) if len(sys.argv) > 3 else 6
S = int(sys.argv[4]) if len(sys.argv) > 4 else 900

reader = vtk.vtkPLYReader(); reader.SetFileName(ply); reader.Update()
norms = vtk.vtkPolyDataNormals(); norms.SetInputConnection(reader.GetOutputPort())
norms.SplittingOff(); norms.ConsistencyOn(); norms.AutoOrientNormalsOn(); norms.Update()
mapper = vtk.vtkPolyDataMapper(); mapper.SetInputConnection(norms.GetOutputPort()); mapper.ScalarVisibilityOff()
actor = vtk.vtkActor(); actor.SetMapper(mapper)
p = actor.GetProperty(); p.SetColor(0.80,0.80,0.82); p.SetSpecular(0.15); p.SetSpecularPower(20); p.SetDiffuse(0.9); p.SetAmbient(0.18)

ren = vtk.vtkRenderer(); ren.SetBackground(0.12,0.12,0.14); ren.AddActor(actor)
renWin = vtk.vtkRenderWindow(); renWin.SetOffScreenRendering(1); renWin.AddRenderer(ren); renWin.SetSize(S,S)
ren.AutomaticLightCreationOff()
for lx,ly,lz,inten in [(1,1,1,1.0),(-1,0.5,1,0.7),(0,1,-1,0.6),(0,-1,0.5,0.4)]:
    lt=vtk.vtkLight(); lt.SetPosition(lx,ly,lz); lt.SetFocalPoint(0,0,0); lt.SetIntensity(inten); lt.SetLightTypeToSceneLight(); ren.AddLight(lt)
ren.SetTwoSidedLighting(1)
cam=ren.GetActiveCamera(); cam.Elevation(14); ren.ResetCamera(); cam.Zoom(1.3); ren.ResetCameraClippingRange()

tiles=[]
for i in range(n):
    if i: cam.Azimuth(360.0/n); cam.OrthogonalizeViewUp(); ren.ResetCameraClippingRange()
    renWin.Render()
    w2i=vtk.vtkWindowToImageFilter(); w2i.SetInput(renWin); w2i.ReadFrontBufferOff(); w2i.Update()
    out=f"/tmp/_geo_{i:02d}.png"; png=vtk.vtkPNGWriter(); png.SetFileName(out); png.SetInputConnection(w2i.GetOutputPort()); png.Write(); tiles.append(out)

cols=3; rows=(n+cols-1)//cols
sheet=Image.new("RGB",(cols*S,rows*S),(255,255,255))
for idx,t in enumerate(tiles): sheet.paste(Image.open(t).convert("RGB"),((idx%cols)*S,(idx//cols)*S))
sheet.save(out_sheet); print("wrote",out_sheet,sheet.size)
