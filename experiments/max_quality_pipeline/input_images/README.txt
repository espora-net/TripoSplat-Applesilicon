IMÁGENES DE ENTRADA del proceso (las 108 vistas que consume el pipeline `full2`).

Contenido (copiado aquí en local para tenerlo todo junto):
- images/       108 JPG, 1280×1280  (view_0000.jpg … view_0107.jpg)  ← entrada de COLMAP
- masks/        108 PNG  (siluetas de z-buffer, 1 por vista)         ← usadas por OpenMVS (DensifyPointCloud --ignore-mask-label 0)
- cameras.json  poses de render del rig VTK  ← NO la usa el pipeline (COLMAP estima las cámaras desde cero)

IMPORTANTE (copyright): estas imágenes son RENDERS del modelo 3D de retail (GLB con
derechos de autor). Están gitignored y NO se commitean ni se redistribuyen; uso
estrictamente local como referencia privada. Ver ../.gitignore.

Se regeneran con (desde experiments/colmap_sneaker/):
  python3 render_synthetic.py eci_tokyo_plain.glb synthetic_ref/full2 full2 1280

Fuente original en el repo de trabajo (también gitignored):
  ../../colmap_sneaker/synthetic_ref/full2/{images,masks,cameras.json}
