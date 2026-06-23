IMÁGENES DE ENTRADA del proceso (las 161 vistas que consume el pipeline `full3`).

Contenido (copiado aquí en local para tenerlo todo junto):
- images/       161 JPG, 1280x1280  (view_0000.jpg … view_0160.jpg)  ← entrada de COLMAP
- masks/        161 PNG  (siluetas de z-buffer, 1 por vista)         ← usadas por OpenMVS (DensifyPointCloud --ignore-mask-label 0)
- cameras.json  poses de render del rig VTK  ← NO la usa el pipeline (COLMAP estima las cámaras desde cero)

Las vistas 0000-0107 son IDÉNTICAS a las de full2 (mismo orden). Las 53 vistas nuevas
(0108-0160) son las de máxima calidad para las zonas difíciles:
- 15 + 12  anillos CERCANOS asomándose al cuello (zoom dist_scale ~0.6, foco subido +0.12R)
- 1        cenital al apoyo del pie (footbed)
- 15 + 10  anillos CERCANOS al talón/cuarto (zoom dist_scale 0.72)

IMPORTANTE (copyright): estas imágenes son RENDERS del modelo 3D de retail (GLB con
derechos de autor). Están gitignored y NO se commitean ni se redistribuyen; uso
estrictamente local como referencia privada. Ver ../.gitignore.

Se regeneran con (desde experiments/colmap_sneaker/):
  python3 render_synthetic.py eci_tokyo_plain.glb synthetic_ref/full3 full3 1280

Fuente original en el repo de trabajo (también gitignored):
  ../../colmap_sneaker/synthetic_ref/full3/{images,masks,cameras.json}
