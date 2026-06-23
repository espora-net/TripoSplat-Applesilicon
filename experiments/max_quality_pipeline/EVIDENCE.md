# EVIDENCE — ¿se regeneró de forma autónoma desde imágenes, sin usar el GLB original?

**Pregunta.** ¿La malla texturizada `full2` la calculó el pipeline COLMAP→OpenMVS
**a partir de imágenes 2D**, o se "coló" la geometría del modelo 3D (GLB) de retail?

**Veredicto del rubber-duck (auditoría independiente, GPT-5.5): `TRUE-WITH-CAVEATS`.**
La malla la reconstruyó genuinamente el pipeline desde renders 2D + máscaras; **no** se
importa el GLB, ni poses conocidas, ni `cameras.json`, ni geometría 3D de verdad. El
alcance honesto: valida el **pipeline** sobre renders sintéticos del GLB de retail; **no**
es recuperar el zapato físico desde fotos reales.

Pinned a commit `7558658`.

---

## 1. Flujo de datos: qué ingiere realmente cada herramienta

- **OpenMVS nunca toca un GLB.** `grep -c "\.glb" openmvs/run_openmvs.sh` → **0**.
- **COLMAP solo recibe imágenes.** `run_colmap_synth.sh`:
  - `feature_extractor --image_path "$FRAMES" --ImageReader.camera_model SIMPLE_PINHOLE --single_camera 1`
  - `exhaustive_matcher` ; `mapper --image_path "$FRAMES" --output_path "$SPARSE"`
  - No hay `cameras.json`, ni `point_triangulator`, ni `--import_path`, ni poses previas.
- **OpenMVS solo lee la salida de COLMAP + las imágenes + las máscaras 2D:**
  - `image_undistorter --image_path <images> --input_path <sparse/0>`
  - `InterfaceCOLMAP -i <undistorted> --image-folder <undistorted/images>`
  - `DensifyPointCloud ... --ignore-mask-label 0` → `ReconstructMesh` → `RefineMesh` → `TextureMesh`.

## 2. Las poses se estiman, no se inyectan

- En el log de COLMAP (`synthetic_ref/full2/ws/colmap_synth.log`):
  - `Loading pose priors... 0`  ← no se cargan poses conocidas.
  - `97 registered images` de `108 input views`, `Mean reprojection error: 0.488537px`.
- Si se hubieran inyectado las poses exactas del render, **registrarían las 108**. Que
  fallen 11 y haya error de reproyección **> 0** es propio de un SfM que estima desde cero.
- `mapper` es determinista (`--Mapper.num_threads 1 --Mapper.random_seed 42`).

## 3. La malla NO es el GLB (identidad de malla)

| Modelo | Vértices | Caras |
|---|---:|---:|
| GLB de retail (`eci_tokyo_plain.glb`) | 65.622 | 99.999 |
| Nuestra densa `full2` (`scene_dense_mesh.ply`) | 658.601 | 1.317.166 |
| Nuestra refinada `full2` (`scene_dense_mesh_refine.ply`) | 274.500 | 548.803 |
| Nuestra texturizada `full2` (`scene_textured.obj`) | 274.500 | 548.803 |

Topología, recuento (5,5× más caras en la refinada, 13× en la densa) y UVs **distintos**.
El atlas de textura lo **genera OpenMVS** (empaquetado de islas propio), no es el del GLB.

## 4. Los defectos son prueba positiva de reconstrucción

Si fuese un copiado del GLB (perfecto), no habría defectos. Pero:
- `side` (27 vistas) → **cáscara hueca** con agujeros en talón/lado opuesto.
- `full` (90 vistas, sin anillos al cuello) → **cúpula lisa** tapando la boca del pie.
- `full2` (108) → abre el cuello, pero aún con **pequeñas imperfecciones** en el contrafuerte.

Son fallos **dependientes de la cobertura/evidencia** = reconstrucción real desde imágenes.

## 5. Matización de las máscaras (importante)

Las máscaras se derivan del z-buffer del GLB (`render_synthetic.py`, `zarr < 0.999`). Son
**supervisión sintética**, pero acotada:
- **Sí** aportan: silueta/contorno 2D exacto del primer plano (ayuda al casco visual).
- **No** aportan: profundidad por píxel, normales, topología, vértices, UVs ni geometría
  oculta/trasera. En el pipeline solo sirven para que `DensifyPointCloud` **ignore el fondo**.

→ Por eso **no** se debe decir "fotogrametría solo-RGB". Lo correcto: **"imágenes RGB +
máscaras de primer plano exactas (sintéticas)"**. El relieve real lo da el emparejamiento
fotométrico multi-vista, no las máscaras.

## 6. Circularidad de misma fuente (el caveat principal)

Las imágenes y máscaras de entrada **se renderizaron del propio GLB de retail**. Por tanto:
- ✅ La malla se computó por fotogrametría desde imágenes 2D (no es copia del GLB).
- ⚠️ **No** prueba que pudiéramos reconstruir el zapato físico desde **fotos reales**. La
  coincidencia de textura es esperable porque la fuente visual es la misma.

## 7. Procedencia de `full2.glb` (para no confundirlo con el GLB de retail)

`full2.glb` está en la carpeta de salida, pero **se generó de nuestra malla**, no del retail:
- Origen: `obj2gltf -i scene_textured.obj -o full2.glb` (548.803 caras, las nuestras).
- `sha256` GLB de retail : `9fe4ecdd229c94313a02ba5e41ccf72268b8ed9852d70a7ccfe397184ccb0b5a`
- `sha256` nuestro `full2`: `81042521fb962f69b26e583c089a8397f39ec5539551242099a3c91c8c3486fb`
- Hashes y recuentos **distintos** → no es el archivo de origen.

## 8. Redacción de alcance honesto (recomendada por el rubber-duck)

> La malla `full2` la **reconstruyó** un pipeline COLMAP→OpenMVS desde renders 2D, usando
> máscaras de primer plano para quitar el fondo. El pipeline **no importa** el GLB, ni
> poses conocidas, ni `cameras.json`, ni geometría 3D de verdad; la topología y el recuento
> de vértices/caras difieren claramente del GLB de retail → no es copia ni passthrough.
>
> **Caveat:** esto **no** demuestra reconstrucción del zapato físico desde fotos reales.
> Las imágenes y máscaras se renderizaron del GLB de retail (experimento **circular** como
> fuente de información visual). Valida que el pipeline recupera una malla de alta calidad
> dada una cobertura/iluminación/máscaras ideales; **no** crea un activo original e
> independiente. "Autónomo" se entiende como: **las etapas de COLMAP/OpenMVS estiman la
> geometría sin importar 3D original** (el diseño de captura sí parte del GLB).

## 9. Checks adicionales para ser 100% incontestable (opcionales)

- **Ablación `MASKS=none`** para cuantificar cuánto aportan las siluetas exactas:
  ```bash
  cd ../openmvs
  SYNTH_SET=full2 QUALITY=max COLOR_NORM=0 MASKS=none bash run_openmvs.sh synth
  ```
- **Rebuild limpio** borrando `ws/` y `openmvs/` y repitiendo, para mostrar mismos recuentos
  sin reusar `.dmap` cacheados.
