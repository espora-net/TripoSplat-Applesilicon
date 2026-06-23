# Pipeline de máxima calidad — sneaker `full2` (COLMAP → OpenMVS, Apple Silicon)

Carpeta **autocontenida** con los **pasos exactos, los scripts, los parámetros y las
decisiones** que produjeron el mejor resultado 3D de la zapatilla en este proyecto:
el preset **`full2`** (108 vistas, máxima cobertura + anillos "mirando dentro" del
cuello), con calidad **`QUALITY=max`** de OpenMVS, sin CUDA, en un Mac (M3 Pro, 36 GB).

> **Lo que valida este experimento (y lo que no).** La malla y la textura las
> **generó el pipeline desde imágenes 2D** (COLMAP estima las cámaras y OpenMVS
> reconstruye la geometría; **nunca** se lee el GLB de referencia). **No** es una
> reconstrucción del zapato físico a partir de fotos reales: las imágenes de entrada
> son **renders del modelo 3D de retail** (captura idealizada). Es una validación del
> **pipeline**, no una adquisición independiente. La prueba completa, con números y el
> veredicto del rubber-duck (**TRUE-WITH-CAVEATS**), está en [`EVIDENCE.md`](./EVIDENCE.md).

Versión congelada de los scripts: commit **`7558658`**. Los scripts de `scripts/` son
**copias fijadas** de los que se mantienen en `../colmap_sneaker/` y `../openmvs/`
(incluido `run_colmap_photos.sh`, para replicar el proceso con **tus propias fotos** —
ver [`REPLICAR_CON_TUS_FOTOS.md`](./REPLICAR_CON_TUS_FOTOS.md)).

---

## 1. Resultado y cómo verlo en el visor

El modelo 3D resultado está **dentro de esta carpeta**, en **`result_model/`** (copia
autocontenida, *gitignored* por copyright):

```
result_model/full2.glb                              ← GLB listo para web (el que usa el visor)
result_model/scene_textured.obj (+ .mtl + atlas)    ← malla texturizada (MeshLab/Blender)
```

(Es una copia de la salida del pipeline `../colmap_sneaker/synthetic_ref/full2/openmvs/`.)

**Abrir el visor interactivo** (girar / zoom / desplazar), desde esta carpeta:

```bash
bash scripts/serve_viewer.sh           # sirve result_model/ en http://127.0.0.1:8779/viewer.html y lo abre
# (Ctrl-C para parar el servidor al terminar)
```

Alternativas sin servidor: `open -a meshlab result_model/scene_textured.obj`, o arrastrar
`result_model/full2.glb` a <https://modelviewer.dev/editor/> o a Blender (*File ▸ Import ▸ glTF*).

El visor usa `<model-viewer>` (incluido en `../colmap_sneaker/openmvs/model-viewer.min.js`).
Controles: **arrastrar = girar · rueda = zoom · clic derecho / dos dedos = desplazar**.

Capturas de evidencia (en local, no se commitean por copyright) en `evidence_local/`:
- `synth_reference_vs_full2.png` — referencia profesional vs lo nuestro.
- `synth_collar_full_vs_full2_clay.png` — antes/después de la cúpula del cuello (malla).
- `synth_full2_hero_textured.png`, `synth_full2_textured_turntable.png` — resultado texturizado.
- `full2_viewer_shot.png` — captura del visor.

---

## 2. ¿Dónde están las imágenes que se usaron?

Las **108 imágenes de entrada** del proceso completo están en:

```
../colmap_sneaker/synthetic_ref/full2/images/   →  view_0000.jpg … view_0107.jpg  (1280×1280)
../colmap_sneaker/synthetic_ref/full2/masks/    →  máscaras de silueta (z-buffer), 1 por vista
```

Esa carpeta `synthetic_ref/` está **gitignored** (material derivado del GLB de retail con
copyright; uso estrictamente local como referencia privada). Se regeneran con el paso 3.1.

Para tenerlo todo junto, esas mismas imágenes (y el GLB de referencia) están **copiadas
dentro de esta carpeta** (local, gitignored por copyright):

```
input_images/images/        → 108 JPG (las mismas que usó COLMAP)
input_images/masks/         → 108 PNG (máscaras de primer plano)
input_images/cameras.json   → poses del rig VTK (registro; el pipeline NO lo usa)
reference_glb/              → el GLB de retail de referencia (origen de los renders)
```

> **¿Qué es `cameras.json`?** Lo escribe `render_synthetic.py` (el rig de cámaras VTK) al
> renderizar: guarda, por vista, la posición de la cámara, el punto al que mira y el `up`,
> más el `fov_deg` y el tamaño. Son las poses **con las que se renderizó**, un simple
> registro: **ningún script del pipeline lo lee** (COLMAP estima sus propias cámaras desde
> las imágenes; por eso registra 97/108, no 108/108).

---

## 3. Pasos exactos (de cero al resultado `full2`)

Todo se ejecuta desde `experiments/`. Los binarios de OpenMVS están en
`openmvs/prebuilt/` (ver `openmvs/get_openmvs.sh`). COLMAP 4.0.4 vía Homebrew (sin CUDA).

### 3.1 Renderizar las imágenes sintéticas (rig VTK)
```bash
cd colmap_sneaker
# eci_tokyo_plain.glb = GLB de retail decodificado (Draco) — LOCAL, gitignored.
python3 render_synthetic.py eci_tokyo_plain.glb synthetic_ref/full2 full2 1280
#   -> synthetic_ref/full2/images/ (108 JPG) + masks/ (108 PNG) + cameras.json (NO se usa)
```

### 3.2 COLMAP — Structure-from-Motion (estima cámaras desde las imágenes)
```bash
bash run_colmap_synth.sh full2
#   feature_extractor (SIMPLE_PINHOLE, single_camera) -> exhaustive_matcher -> mapper
#   -> synthetic_ref/full2/ws/sparse/0/   (97/108 imágenes registradas, error medio 0.49 px)
```

### 3.3 OpenMVS — densificado, malla, refinado y textura (QUALITY=max)
```bash
cd ../openmvs
SYNTH_SET=full2 QUALITY=max COLOR_NORM=0 bash run_openmvs.sh synth
#   image_undistorter -> InterfaceCOLMAP -> [stage masks] -> DensifyPointCloud
#   -> ReconstructMesh -> RefineMesh -> TextureMesh
#   -> synthetic_ref/full2/openmvs/scene_textured.obj  (+ dense/refine .ply)
```

### 3.4 (Opcional) Exportar GLB para el visor web
```bash
cd ../colmap_sneaker/synthetic_ref/full2/openmvs
npx --yes obj2gltf -i scene_textured.obj -o full2.glb
```

Tiempo total aprox. en M3 Pro: **~10–11 min** (densify L0 ~4 min, ReconstructMesh ~3 min,
RefineMesh ~2,5 min, textura ~40 s).

---

## 4. Parámetros que dan la máxima calidad

### 4.1 Captura sintética (`render_synthetic.py`, modo `full2`)
| Parámetro | Valor | Por qué |
|---|---|---|
| Resolución | 1280×1280 | nitidez sin disparar el tiempo de densify |
| Iluminación | 8 luces de escena, especular bajo | plana y uniforme → verde sin manchas |
| Fondo / máscara | gris 0.5 / silueta de z-buffer (`z < 0.999`) | máscara exacta del primer plano |
| Vistas base (`full`) | 3 anillos elev. (−25/0/+25)×24az + (±50)×8az + cenital + suela = **90** | cobertura 360° |
| **Anillos al cuello (`full2`)** | **elev. 60°×12az + 72°×6az = +18 → 108** | **dan evidencia del hueco del pie → no se tapa con cúpula** |

### 4.2 COLMAP (`run_colmap_synth.sh`)
| Etapa | Parámetros clave | Por qué |
|---|---|---|
| `feature_extractor` | `--ImageReader.camera_model SIMPLE_PINHOLE`, `--single_camera 1`, CPU SIFT | los renders son pinhole sin distorsión; una sola cámara compartida |
| `exhaustive_matcher` | OpenGL SIFT (`use_gpu 1`) | el matcher CPU peta (SIGTRAP) en este Mac |
| `mapper` | `--Mapper.num_threads 1`, `--Mapper.random_seed 42` | **determinista/reproducible**; umbrales por defecto (los renders limpios registran bien) |

### 4.3 OpenMVS `QUALITY=max` (`run_openmvs.sh`)
| Etapa | Flags (valores `max`) | Por qué |
|---|---|---|
| `image_undistorter` | `--max_image_size 1280` | resolución nativa de los renders |
| `DensifyPointCloud` | `--resolution-level 0` `--max-resolution 1280` `--number-views 5` `--number-views-fuse 3` `--ignore-mask-label 0` | **resolución completa** (máximo de triángulos) + máscara de primer plano |
| `ReconstructMesh` | `--decimate 1` `--remove-spurious 50` `--close-holes 12` `--smooth 3` | sin diezmado; limpia picos; no tapa el cuello con una "tapa" plana |
| `RefineMesh` | `--resolution-level 0` `--scales 3` `--max-face-area 6` `--regularity-weight 0.25` `--close-holes 12` | **recupera el detalle fino** (cordones, costuras, franjas en relieve) |
| `TextureMesh` | `--resolution-level 0` `--max-texture-size 8192` `--virtual-face-images 3` `--global/local-seam-leveling 0` `--empty-color #1A1A1A` | textura a resolución completa; **seam-leveling OFF** (si no, manchas saturadas); caras sin textura en sombra, no en blanco |
| `COLOR_NORM` | **0** para `full2` | la luz sintética ya es uniforme (en fotos reales ruidosas se usa **1**) |

Malla resultante `full2`: densa **658.601 v / 1.317.166 caras** → refinada **274.500 v / 548.803 caras**.

---

## 5. Decisiones tomadas (y su porqué)

1. **Múltiples imágenes con cobertura 360°** (vs un solo lado). El control `side` (27 vistas)
   sale **hueco y con agujeros** en talón/lado opuesto; `full` los cierra. → la **cobertura
   de fotos es el factor que más decide la calidad**.
2. **Preset `full2` (anillos asomándose al cuello).** El cuello salía tapado por una **cúpula
   lisa** porque casi ninguna vista miraba dentro. Añadir vistas hacia el interior lo
   **abre** (cordones en relieve, forro magenta visible). → la cúpula era **falta de
   cobertura/evidencia, no un límite del proceso**.
3. **`QUALITY=max` (densify y refine a `resolution-level 0`).** Máximo de triángulos y de
   detalle de superficie; es lo que pasa de "se reconoce" a "relieve real".
4. **Arreglo del nombre de máscara `<stem>.mask.png`** (OpenMVS reemplaza la extensión).
   Con el nombre antiguo el enmascarado se desactivaba en silencio y, a nivel 0, el fondo
   se fundía como "velas" planas sobre el zapato.
5. **`RefineMesh` ACTIVADO.** Paso oficial para "recuperar todos los detalles finos";
   además limpia las solapas/picos del fondo.
6. **Seam-leveling DESACTIVADO.** El seam-leveling de OpenMVS pintaba **manchas de color
   saturado** sobre los parches reales; desactivado se ve la textura fotográfica auténtica.
7. **`COLOR_NORM` según la fuente.** ON para frames reales ruidosos (arregla el verde
   multitono); OFF para `full2` (la luz sintética ya es uniforme).
8. **`close-holes 12` + `empty-color` oscuro.** El cuello no se tapa con una tapa plana y
   las caras sin textura leen como sombra, no como blanco.
9. **COLMAP determinista** (`num_threads 1`, `seed 42`) + **`SIMPLE_PINHOLE`**: resultados
   reproducibles y modelo de cámara exacto para renders sin distorsión.

---

## 6. Replicar con tus propias fotos (validar con una captura real)

Esta carpeta incluye el camino para **reproducir el mismo pipeline con fotos reales**
tuyas, no con renders. Guía paso a paso en
[`REPLICAR_CON_TUS_FOTOS.md`](./REPLICAR_CON_TUS_FOTOS.md). Resumen:

```bash
cd experiments
# 1) COLMAP sobre TUS fotos (estima cámaras reales con distorsión) -> workspace listo
bash colmap_sneaker/run_colmap_photos.sh /ruta/a/tus/fotos /ruta/al/ws
# 2) Malla densa + textura a máxima calidad (mismo OpenMVS, preset nuevo "photos")
PHOTOS_WS=/ruta/al/ws QUALITY=max bash openmvs/run_openmvs.sh photos
# 3) Ver el resultado (OBJ -> GLB y abrir el visor, como en la sección 1)
```

La **clave de la calidad es la captura**: 40–120 fotos dando toda la vuelta, varias alturas,
mucho solape y **unas cuantas asomándose al interior/huecos** (el equivalente real a los
anillos `full2` que cierran la cúpula del cuello). Máscaras de primer plano opcionales pero
recomendadas (`<ws>/masks/<nombre>.png`). Esto **sí** es una adquisición independiente del
objeto físico (a diferencia del experimento sintético de las secciones anteriores).

---

## 7. Honestidad / copyright

- El GLB de referencia (`reference_glb/`) y **todo** lo derivado (`synthetic_ref/`,
  `input_images/`, `evidence_local/`, `full2.glb`) son **material de retail con copyright**:
  **estrictamente local y gitignored**, solo como referencia privada de investigación. Solo
  se commitea **herramienta original** (scripts y documentación).
- Comparación **visual**, no métrica. Captura **idealizada** (máscaras exactas, luz
  uniforme). **Circularidad de misma fuente**: las imágenes salen de la misma textura con
  la que comparamos. Ver [`EVIDENCE.md`](./EVIDENCE.md) para el detalle.
