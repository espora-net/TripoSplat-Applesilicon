result_model/ — Modelo 3D reconstruido (Vibram/Merrell) desde vídeo propio
==========================================================================

QUÉ HAY AQUÍ
  vibram.glb                  Entregable: malla + textura embebida (glTF binario).
                              411.322 caras, atlas 4096². ~30 MB.
  scene_textured.obj/.mtl     Misma malla en OBJ + atlas .jpg (para MeshLab/Blender).
  scene_textured_*_map_Kd.jpg Atlas de textura (4096²).
  model-viewer.min.js         Visor web (Google <model-viewer>, Apache-2.0).
  viewer.html                 Página del visor interactivo (versionada).
  README.txt                  Este archivo.

Esta carpeta se versiona COMPLETA como parte del conjunto de datos para fines
académicos/investigación (ver ../AVISO.md). Los binarios pesados son DERIVADOS y se
pueden regenerar con el pipeline (ver ../README.md y ../EVIDENCE.md).

CÓMO REGENERARLOS
  cd ..                       # experiments/vibram
  python3 clean_mesh.py recon/colmap_ws/openmvs/scene_textured.obj result_model/vibram.glb
  # (o ejecuta el pipeline completo desde cero: ver ../README.md)

CÓMO VERLO
  cd ..
  bash serve_viewer.sh        # http://127.0.0.1:8781/viewer.html
  # serve_viewer.sh regenera vibram.glb y descarga model-viewer.min.js si faltan.
  # Alternativas: arrastrar vibram.glb a https://modelviewer.dev/editor/, o
  #   Blender (File ▸ Import ▸ glTF), o  open -a meshlab scene_textured.obj

ORIGEN (importante)
  Reconstrucción 100 % propia a partir de 5 VÍDEOS del usuario (zapatilla real),
  vía COLMAP→OpenMVS en Apple Silicon (M3 Pro, sin CUDA). NO se usó ningún GLB de
  retail ni modelo de terceros: sin copyright. Calidad acotada por el origen
  (vídeo 848×478 + compresión WhatsApp + grabado a mano) — ver ../EVIDENCE.md.
  USO ACADÉMICO / referencias y atribución: ver ../AVISO.md.
