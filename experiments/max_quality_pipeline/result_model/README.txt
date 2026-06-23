MODELO 3D RESULTADO (preset full2) — lo que genera el pipeline desde las imágenes.

Contenido (copiado aquí para que la carpeta sea autocontenida y se pueda visualizar):
- full2.glb                              42 MB  GLB listo para web (<model-viewer>)  ← el que usa el visor
- scene_textured.obj                     64 MB  malla texturizada (para MeshLab/Blender)
- scene_textured.mtl                            material que referencia el atlas
- scene_textured_material_00_map_Kd.jpg  4.7 MB atlas de textura (8192 px)

CÓMO VERLO
- Visor web interactivo (girar/zoom/desplazar), desde la carpeta padre:
    bash scripts/serve_viewer.sh            # http://127.0.0.1:8779/viewer.html
  (el script sirve directamente este result_model/)
- O abrir el OBJ en MeshLab:   open -a meshlab scene_textured.obj
- O arrastrar full2.glb a https://modelviewer.dev/editor/  (o a Blender: File > Import > glTF).

ORIGEN
- Generado por OpenMVS (QUALITY=max) sobre el modelo COLMAP de las 108 vistas full2.
  NO es el GLB de retail: es NUESTRA malla (274.500 v / 548.803 caras). Ver EVIDENCE.md.
- Se regenera con los pasos 3.1–3.4 del README. full2.glb = obj2gltf de scene_textured.obj.

IMPORTANTE (copyright): derivado del modelo de retail con copyright → gitignored,
estrictamente local. Solo se versiona este README.txt.
