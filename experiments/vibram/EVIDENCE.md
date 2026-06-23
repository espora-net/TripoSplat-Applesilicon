# EVIDENCE — Vibram/Merrell, reconstrucción a máxima calidad

Registro reproducible de la ejecución: comandos exactos, parámetros, métricas y
decisiones. Hardware: **Apple M3 Pro, 36 GB, macOS, sin CUDA**. COLMAP 4.0.4
(Homebrew), OpenMVS (Homebrew), Python 3 + OpenCV 4.13 + rembg + trimesh.

---

## 0. Entrada — 5 vídeos de móvil (captura propia)

5 clips de WhatsApp, H.264, 30 fps. **No** se versionan (privados del usuario y
bloqueados por el ACL `com.apple.macl` de macOS); especificaciones tomadas de la
extracción:

| Clip | Fichero | Resolución | Dur. | Toma |
|---|---|---|---|---|
| v0 | `…14.11.39.mp4` | 848×478 | 9,6 s | suela |
| v1 | `…14.11.42.mp4` | **478×850 (vertical)** | 16,7 s | interior |
| v2 | `…14.11.57 (1).mp4` | 848×478 | 23,3 s | talón |
| v3 | `…14.11.57 (2).mp4` | 848×478 | 40,2 s | lateral (la más larga) |
| v4 | `…14.11.57.mp4` | 848×478 | 22,6 s | empeine |

≈ 3.370 fotogramas brutos en total.

---

## 1. Extracción de fotogramas — `extract_frames.py`

```bash
TOTAL=320 python3 extract_frames.py
```

- **Nitidez** = varianza del laplaciano. Cada clip se divide en `TOTAL·(dur_clip/dur_total)`
  segmentos temporales y se conserva **solo el fotograma más nítido** de cada
  segmento ⇒ se descartan automáticamente los tramos movidos (`SHARP_FLOOR=0.55`
  respecto a la nitidez mediana del clip).
- El clip **vertical v1** se **transpone** a horizontal y todos se recortan a
  **848×478 uniforme** (requisito de `--single_camera`).

**Resultado: 266 fotogramas** en `recon/images_orig/` (de 320 pedidos; el resto
cae por el filtro de nitidez):

| Clip | v0 | v1 | v2 | v3 | v4 | **Total** |
|---|---|---|---|---|---|---|
| Fotogramas | 20 | 44 | 63 | 96 | 43 | **266** |

---

## 2. Máscaras de primer plano — `make_masks_u2net.py`

```bash
python3 make_masks_u2net.py
```

- **Primario: rembg `u2net`** (`u2net.onnx`) a resolución original.
- **Fallback por color de suelo** (`make_masks_color.py`, Mahalanobis en espacio
  LAB) cuando u2net devuelve una máscara implausible (cobertura < 0,07 o > 0,85).
- **Limpieza morfológica**: cierre → mayor componente conexa central → relleno de
  huecos (con *padding* + *flood* desde la esquina, para no rellenar el 100 % si la
  máscara toca el píxel (0,0)) → dilatación ligera.
- Salida: `recon/masks/<stem>.png` (canónica para OpenMVS) +
  `recon/masks_colmap/<name>.jpg.png` (enlaces duros, convención de COLMAP).

**Resultado: 260/266 máscaras buenas** (máx. cobertura 76 %, **0 fugas al suelo**).
Solo **6** fotogramas de interior muy picado (v1) quedan implausibles — no pasa
nada: sus máscaras casi vacías hacen que esos fotogramas **no registren** y caigan
solos en COLMAP.

> **Por qué u2net y no BiRefNet:** BiRefNet (el del repo) devolvía mattes casi
> vacíos sobre esta zapatilla oscura en suelo de madera (p. ej. solo el logo en un
> fotograma de interior). u2net acierta en ~7/8 y el *fallback* por color cubre el
> resto.

---

## 3. SfM COLMAP enmascarado — `run_colmap_vibram.sh`

```bash
bash run_colmap_vibram.sh
```

Diferencias clave frente al preset `run_colmap_photos.sh`:

- **`--ImageReader.mask_path recon/masks_colmap`** ⇒ SIFT solo extrae sobre la
  zapatilla. **Esta es la pieza que fusiona los 5 clips**: como el suelo se ignora,
  COLMAP no "ve" moverse el fondo y trata la zapatilla como **un único objeto
  rígido** aunque entre clips se haya recolocado.
- `SIMPLE_RADIAL`, `--ImageReader.single_camera 1` (una sola cámara compartida).
- **Matcher exhaustivo** con `--FeatureMatching.guided_matching 1` (encuentra
  correspondencias entre clips, no solo dentro de cada uno).
- Umbrales de *mapper* robustos para **baja paralaje** (vídeo): `init_min_num_inliers 50`,
  `abs_pose_min_num_inliers 15`, `abs_pose_min_inlier_ratio 0.15`,
  `min_num_matches 12`, `--Mapper.num_threads 1`, `--Mapper.random_seed 42`
  (determinista).
- Nombres de opción de COLMAP 4.x: `--FeatureExtraction.use_gpu`,
  `--FeatureMatching.use_gpu/.guided_matching`, `--Mapper.random_seed`.

**Resultado: 259/266 fotogramas registrados en UN solo modelo.**

| Métrica | Valor |
|---|---|
| Fotogramas registrados | **259 / 266** |
| Puntos 3D (sparse) | **49.174** |
| **Error medio de reproyección** | **0,79 px** |
| Cámara | 1 × SIMPLE_RADIAL, f ≈ 748 px |

Cobertura por clip tras el registro: los 5 clips entran en el modelo (los 7 que
caen son fotogramas de interior muy picado y algún borroso). **Suela + interior +
talón + lateral + empeine fusionados** ⇒ envoltura 360° completa.

---

## 4. Densificado + malla + textura (máxima calidad) — `run_openmvs.sh photos`

```bash
PHOTOS_WS="$PWD/recon/colmap_ws" \
  COLMAP_IMAGES="$PWD/recon/images_orig" \
  MASKS="$PWD/recon/masks" \
  QUALITY=max COLOR_NORM=1 \
  bash ../openmvs/run_openmvs.sh photos
```

- `QUALITY=max` ⇒ `--resolution-level 0` (resolución nativa) en densificado y
  `RefineMesh` a resolución completa; `--max-resolution 2000`.
- `COLOR_NORM=1` ⇒ armoniza exposición/balance de blancos entre fotogramas (clave
  con vídeo a mano y luz variable; reduce el "verde a varios tonos").
- Máscaras propagadas a OpenMVS (`<stem>.mask.png` junto a las imágenes
  *undistorted*) ⇒ no se densifica el suelo.

| Etapa | Resultado | Tiempo |
|---|---|---|
| DensifyPointCloud | 49.174 → **1.872.650** puntos densos | 3 m 25 s |
| ReconstructMesh | 54.701 v / 109.418 f (malla base) | ~30 s |
| RefineMesh (full-res) | subdivide → **205.828 v / 411.672 f** | 1 m 45 s |
| TextureMesh | atlas **4096²**, 37.313 parches, 1 textura | 41 s |
| **Total OpenMVS** | `scene_textured.obj` (48 MB) | **~6,5 min** |

---

## 5. Limpieza de *floaters* + GLB — `clean_mesh.py`

```bash
python3 clean_mesh.py recon/colmap_ws/openmvs/scene_textured.obj result_model/vibram.glb
```

- Suelda vértices por redondeo (`DECIMALS=5`), etiqueta componentes conexas
  (scipy) y **descarta las menores al 2 %** (`FRAC=0.02`) del componente mayor,
  preservando los UV por cara (`submesh(..., repair=False)`).
- Eliminó **1 fragmento de 350 caras** (resto de borde de máscara) ⇒
  **411.322 caras**. Export GLB con **textura embebida** (verificado).

**Entregable:** `result_model/vibram.glb` — **30 MB**, 411.322 caras, atlas 4096².

---

## 6. Validación

- **Render turntable** (`evidence/03_result_turntable.jpg`, 10 vistas): zapatilla
  completa y reconocible — suela con octógono *Vibram* y **M** de Merrell, malla del
  empeine, cordones, puntera, talón e interior; 360° sin agujeros grandes.
- Reproyección **0,79 px** y **259/266** fotogramas en un único modelo ⇒ fusión
  real de los 5 clips, no mitades cosidas.

### Limitaciones honestas
- Origen **848×478 + compresión WhatsApp + grabado a mano** ⇒ fidelidad de textura
  **por debajo** de los renders sintéticos 1280². El detalle fino (microtextura de la
  malla, serigrafías pequeñas) está al límite de la resolución de origen.
- **Interior profundo** parcial: 6–7 fotogramas verticales muy picados no
  registraron; la cavidad se reconstruye pero con menos densidad.
- **Mediasuela especular**: algún brillo quemado pese a `COLOR_NORM`.

### Cómo subir la calidad (si se desea)
Regrabar a **1080p/4K**, orbitar lento y estable, pasada dedicada de **suela** e
**interior** con buena luz difusa, y mantener el objeto **quieto dentro de cada
pasada**. Detalle en **[CAPTURA_VIDEO.md](CAPTURA_VIDEO.md)**.
