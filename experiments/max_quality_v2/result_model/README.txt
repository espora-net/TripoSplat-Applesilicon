MODELO 3D RESULTADO (preset full3) — corrige TALÓN + INTERIOR sobre full2.

Contenido (copiado aquí para que la carpeta sea autocontenida y se pueda visualizar):
- full3.glb                              85 MB  GLB listo para web (<model-viewer>)  ← el que usa el visor
- scene_textured.obj                    129 MB  malla texturizada (para MeshLab/Blender)
- scene_textured.mtl                            material que referencia el atlas
- scene_textured_material_00_map_Kd.jpg 9.5 MB  atlas de textura (8192 px)
- viewer.html, model-viewer.min.js              visor web interactivo autocontenido

CÓMO VERLO
- Visor web interactivo (girar/zoom/desplazar), desde la carpeta padre:
    bash scripts/serve_viewer.sh            # http://127.0.0.1:8780/viewer.html
  (el script sirve directamente este result_model/)
- O abrir el OBJ en MeshLab:   open -a meshlab scene_textured.obj
- O arrastrar full3.glb a https://modelviewer.dev/editor/  (o a Blender: File > Import > glTF).

ORIGEN
- Generado por OpenMVS (QUALITY=max) sobre el modelo COLMAP de las 161 vistas full3.
  NO es el GLB de retail: es NUESTRA malla (549.933 v / 1.099.589 caras, 2x full2). Ver EVIDENCE.md.
- Se regenera con los pasos 3.1-3.4 del README. full3.glb = obj2gltf de scene_textured.obj.

IMPORTANTE (copyright): derivado del modelo de retail con copyright -> gitignored,
estrictamente local. Solo se versiona este README.txt.
