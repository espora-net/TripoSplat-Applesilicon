# Pipeline de máxima calidad v2 — sneaker `full3` (corrige TALÓN + INTERIOR)

Carpeta **autocontenida** con la **segunda ejecución de máxima calidad**, que parte de y
**valida** la ejecución documentada en [`../max_quality_pipeline/`](../max_quality_pipeline)
(preset **`full2`**) y la mejora para **corregir dos defectos** que quedaban:

1. **El talón** (contrafuerte) salía con un **agujero rasgado** / geometría rota.
2. **El interior** (la boca del pie, vista desde arriba) reconstruía un **"hueco" en blanco
   sin textura** porque las paredes internas tenían muy pocos píxeles.

La solución es el preset **`full3`** (161 vistas): `full2` (108) **+ 53 vistas nuevas de
máxima calidad** que se **acercan (zoom)** a las dos zonas difíciles — anillos cercanos
asomándose al **cuello** y anillos cercanos al **talón** — para multiplicar la densidad de
píxeles ahí. Misma calidad **`QUALITY=max`** de OpenMVS, sin CUDA, en un Mac (M3 Pro, 36 GB).

> **Lo que valida este experimento (y lo que no).** La malla y la textura las **generó el
> pipeline desde imágenes 2D** (COLMAP estima las cámaras y OpenMVS reconstruye la geometría;
> **nunca** se lee el GLB de referencia). **No** es una reconstrucción del zapato físico a
> partir de fotos reales: las imágenes de entrada son **renders del modelo 3D de retail**
> (captura idealizada). Es una validación del **pipeline**, no una adquisición independiente.
> La prueba del antes/después (talón + interior), con números y framing honesto, está en
> [`EVIDENCE.md`](./EVIDENCE.md).

> **Guía nueva:** [`CAPTURA_ZONAS_COMPLEJAS.md`](./CAPTURA_ZONAS_COMPLEJAS.md) — la **mejor
> técnica para fotografiar zonas complejas** (cóncavas, ocultas, de poca textura: talón e
> interior) para obtener la máxima calidad. Es la traducción a **fotos reales** de lo que los
> anillos cercanos de `full3` emulan en la captura sintética.

---

## 1. Resultado y cómo verlo en el visor

El modelo 3D resultado está **dentro de esta carpeta**, en **`result_model/`** (copia
autocontenida, *gitignored* por copyright):

```
result_model/full3.glb                              ← GLB listo para web (el que usa el visor, 85 MB)
result_model/scene_textured.obj (+ .mtl + atlas)    ← malla texturizada (MeshLab/Blender, 129 MB)
```

(Es una copia de la salida del pipeline `../colmap_sneaker/synthetic_ref/full3/openmvs/`.)

**Abrir el visor interactivo** (girar / zoom / desplazar), desde esta carpeta:

```bash
bash scripts/serve_viewer.sh           # sirve result_model/ en http://127.0.0.1:8780/viewer.html y lo abre
# (Ctrl-C para parar el servidor al terminar; puerto 8780 para no chocar con full2 en 8779)
```

Alternativas sin servidor: `open -a meshlab result_model/scene_textured.obj`, o arrastrar
`result_model/full3.glb` a <https://modelviewer.dev/editor/> o a Blender (*File ▸ Import ▸ glTF*).

Capturas de evidencia **antes/después** (en local, no se commitean por copyright) en
`evidence_local/`:
- `antes_talon_full2.png` / `despues_talon_full3.png` — el agujero del contrafuerte se cierra.
- `antes_interior_az180_full2.png` / `despues_interior_az180_full3.png` — desaparece el
  artefacto flotante y la pared interior queda continua.
- `antes_interior_az000_full2.png` / `despues_interior_az000_full3.png` — el borde rasgado del
  apoyo del pie (footbed) queda liso.
- `antes_interior_cenital_full2.png` / `despues_interior_cenital_full3.png` — vista cenital de la cavidad.

---

## 2. ¿Dónde están las imágenes que se usaron?

Las **161 imágenes de entrada** del proceso completo están en:

```
../colmap_sneaker/synthetic_ref/full3/images/   →  view_0000.jpg … view_0160.jpg  (1280×1280)
../colmap_sneaker/synthetic_ref/full3/masks/    →  máscaras de silueta (z-buffer), 1 por vista
```

Las vistas **0000–0107 son idénticas a las de `full2`**; las **53 nuevas (0108–0160)** son los
anillos cercanos a cuello y talón. Esa carpeta `synthetic_ref/` está **gitignored** (material
derivado del GLB de retail con copyright; uso estrictamente local). Se regeneran con el paso 3.1.

Para tenerlo todo junto, esas mismas imágenes (y el GLB de referencia) están **copiadas
dentro de esta carpeta** (local, gitignored por copyright):

```
input_images/images/        → 161 JPG (las mismas que usó COLMAP)
input_images/masks/         → 161 PNG (máscaras de primer plano)
input_images/cameras.json   → poses del rig VTK (registro; el pipeline NO lo usa)
reference_glb/              → el GLB de retail de referencia (origen de los renders)
```

> **¿Qué es `cameras.json`?** Lo escribe `render_synthetic.py` (el rig de cámaras VTK) al
> renderizar: guarda, por vista, la posición de la cámara, el punto al que mira y el `up`, más
> el `fov_deg` y el tamaño. Es un simple **registro**: **ningún script del pipeline lo lee**
> (COLMAP estima sus propias cámaras desde las imágenes; por eso registra 153/161, no 161/161).
> En `full3` `render_compare.py` **sí** lo lee, pero solo para **orientar las vistas de
> diagnóstico** (saber qué cámaras miran alto/bajo y deducir el eje vertical); no interviene en
> la reconstrucción.

---

## 3. Pasos exactos (de cero al resultado `full3`)

Todo se ejecuta desde `experiments/`. Los binarios de OpenMVS están en `openmvs/prebuilt/`.
COLMAP 4.0.4 vía Homebrew (sin CUDA).

### 3.1 Renderizar las imágenes sintéticas (rig VTK) — modo `full3`
```bash
cd colmap_sneaker
# eci_tokyo_plain.glb = GLB de retail decodificado (Draco) — LOCAL, gitignored.
python3 render_synthetic.py eci_tokyo_plain.glb synthetic_ref/full3 full3 1280
#   -> synthetic_ref/full3/images/ (161 JPG) + masks/ (161 PNG) + cameras.json (NO se usa)
```

### 3.2 COLMAP — Structure-from-Motion (estima cámaras desde las imágenes)
```bash
bash run_colmap_synth.sh full3
#   feature_extractor (SIMPLE_PINHOLE, single_camera) -> exhaustive_matcher -> mapper
#   -> synthetic_ref/full3/ws/sparse/0/   (153/161 imágenes registradas, error medio 0.371 px)
```

### 3.3 OpenMVS — densificado, malla, refinado y textura (QUALITY=max)
```bash
cd ../openmvs
SYNTH_SET=full3 QUALITY=max COLOR_NORM=0 bash run_openmvs.sh synth
#   image_undistorter -> InterfaceCOLMAP -> [stage masks] -> DensifyPointCloud
#   -> ReconstructMesh -> RefineMesh -> TextureMesh
#   -> synthetic_ref/full3/openmvs/scene_textured.obj  (+ dense/refine .ply)
```

### 3.4 (Opcional) Exportar GLB para el visor web
```bash
cd ../colmap_sneaker/synthetic_ref/full3/openmvs
NODE_OPTIONS="--max-old-space-size=12288" npx --yes obj2gltf -i scene_textured.obj -o full3.glb
#   (el OBJ de full3 son 129 MB; conviene subir el heap de Node para la conversión)
```

### 3.5 (Opcional) Verificar el antes/después con renders de diagnóstico
```bash
cd ../../..                      # experiments/colmap_sneaker
python3 render_compare.py full2 /tmp/cmp3      # antes
python3 render_compare.py full3 /tmp/cmp3      # después
#   -> /tmp/cmp3/{full2,full3}_{heel_behind,interior_top,interior_obl_az###}.png
```

Tiempo total aprox. en M3 Pro: **~24–25 min** (COLMAP ~1 min; densify L0 ~10 min,
ReconstructMesh ~6 min, RefineMesh ~6 min, textura ~1 min). Es ~2× el de `full2` por las 53
vistas extra y la malla del doble de tamaño.

---

## 4. Parámetros que dan la máxima calidad

### 4.1 Captura sintética (`render_synthetic.py`, modo `full3`)

`full3` = `full2` (108 vistas) **+ 53 vistas nuevas**. El formato de vista pasa a 4-tupla
`(az, el, dist_scale, focal_rise_R)`: `dist_scale < 1` **acerca** la cámara (más píxeles en el
objetivo); `focal_rise` **sube** el punto al que mira esa fracción del radio `R` (lo apunta al
borde del cuello, no al centro de la malla).

| Bloque nuevo (`full3`) | Vistas | Parámetros | Por qué |
|---|---:|---|---|
| **Anillo cercano al cuello (bajo)** | 15 | `el 60°`, **`dist_scale 0.60`**, **`focal_rise +0.12R`**, az cada 24° | acerca la cámara a la boca → multiplica los píxeles del **interior** → densify rellena las paredes |
| **Anillo cercano al cuello (alto)** | 12 | `el 74°`, **`dist_scale 0.58`**, **`focal_rise +0.12R`**, az cada 30° | ángulo más cenital, aún más cerca → cubre el fondo de la cavidad (footbed) |
| **Cenital al apoyo del pie** | 1 | `el 86°`, `dist_scale 0.60` | mira el footbed casi en vertical → evita el "hueco" central |
| **Anillo cercano al talón (a la altura)** | 15 | `el 2°`, **`dist_scale 0.72`**, az cada 24° | el ante del contrafuerte es de poca textura; más píxeles + ángulos rasantes definen el borde |
| **Anillo cercano al talón (contrapicado)** | 10 | `el −16°`, **`dist_scale 0.72`**, az cada 36° | cierra la transición talón↔suela por debajo |

Las 108 vistas base (`full2`) no cambian: 3 anillos elev. (−25/0/+25)×24az + (±50)×8az +
cenital + suela = 90, **+** anillos al cuello elev. 60°×12az + 72°×6az = 108. El resto de
parámetros de captura (1280×1280, 8 luces de escena, máscara por z-buffer) es idéntico a `full2`.

### 4.2 COLMAP (`run_colmap_synth.sh full3`)
| Etapa | Parámetros clave | Por qué |
|---|---|---|
| `feature_extractor` | `--ImageReader.camera_model SIMPLE_PINHOLE`, `--single_camera 1`, CPU SIFT | los renders son pinhole sin distorsión; una sola cámara compartida |
| `exhaustive_matcher` | OpenGL SIFT (`use_gpu 1`) | el matcher CPU peta (SIGTRAP) en este Mac |
| `mapper` | `--Mapper.num_threads 1`, `--Mapper.random_seed 42` | **determinista/reproducible** |

Resultado: **153/161** imágenes registradas, **error medio de reproyección 0.371 px** (mejor
que el 0.49 px de `full2`: más vistas y más solape ⇒ poses más finas).

### 4.3 OpenMVS `QUALITY=max` (`run_openmvs.sh synth`, `SYNTH_SET=full3`)

**Mismos flags `QUALITY=max` que `full2`** (no se tocó ningún parámetro de OpenMVS): la mejora
del talón y el interior viene **solo de la captura** (las 53 vistas cercanas), no de cambiar la
malla/textura. Recordatorio de los flags `max`:

| Etapa | Flags (valores `max`) |
|---|---|
| `image_undistorter` | `--max_image_size 1280` |
| `DensifyPointCloud` | `--resolution-level 0` `--max-resolution 1280` `--number-views 5` `--number-views-fuse 3` `--ignore-mask-label 0` |
| `ReconstructMesh` | `--decimate 1` `--remove-spurious 50` `--close-holes 12` `--smooth 3` |
| `RefineMesh` | `--resolution-level 0` `--scales 3` `--max-face-area 6` `--regularity-weight 0.25` `--close-holes 12` |
| `TextureMesh` | `--resolution-level 0` `--max-texture-size 8192` `--virtual-face-images 3` `--global/local-seam-leveling 0` `--empty-color #1A1A1A` |
| `COLOR_NORM` | **0** (la luz sintética ya es uniforme) |

Malla resultante `full3`: densa **1.374.941 v / 2.749.837 caras** → refinada/texturizada
**549.933 v / 1.099.589 caras**. Es **2× la de `full2`** (274.500 v / 548.803 caras): los
anillos cercanos aportan mucha más evidencia fotométrica → densify genera el doble de puntos.

---

## 5. Decisiones tomadas (y su porqué)

Sobre la base de las 9 decisiones de `../max_quality_pipeline` (que se mantienen), `full3` añade:

1. **El defecto era de COBERTURA, no del proceso.** En `full2`, las vistas que asoman al cuello
   **encuadran el zapato entero** → el interior ocupa solo unos cientos de píxeles → densify
   queda escaso ahí → la pared del lado del talón salía como **"hueco" sin textura** y el
   contrafuerte como un **borde rasgado**. La misma idea que llevó de `full`→`full2` (añadir
   evidencia donde falta), llevada al **detalle de las dos zonas**.
2. **Acercar la cámara (zoom) en vez de subir parámetros.** El factor decisivo es la **densidad
   de píxeles sobre la zona**. Por eso `full3` **no cambia OpenMVS**: añade anillos con
   `dist_scale ~0.58–0.60` (cuello) y `0.72` (talón). Aislar la variable (solo la captura)
   prueba que la mejora es de cobertura.
3. **Apuntar al borde del cuello (`focal_rise +0.12R`), no al centro.** Si la cámara cercana
   sigue mirando al centro de la malla, la boca se va del encuadre. Subir el punto de mira lo
   centra en la **abertura**, que es lo que hay que densificar.
4. **Dos alturas en cada zona.** Cuello a `el 60°` (paredes) **y** `74°`/`86°` (fondo/footbed);
   talón a `el 2°` (borde a la altura) **y** `−16°` (unión con la suela). Una sola altura deja
   sin cubrir parte de la concavidad.
5. **El talón de ante (poca textura) necesita píxeles + RefineMesh.** A distancia normal, MVS
   **sobre-suaviza** el ante en un "pegote". El anillo cercano (`0.72`) le da más muestras y
   `RefineMesh` afila el borde. **Caveat honesto:** sigue siendo una superficie de poca textura;
   queda **mejor y sin agujero**, pero su nitidez tiene un límite físico (ver `EVIDENCE.md`).
6. **Verificación con `render_compare.py` (antes/después).** Para no "creérnoslo", se renderiza
   la **misma** vista de talón e interior para `full2` y `full3` con **iluminación de una cara**
   (`SetTwoSidedLighting(0)`), de modo que un agujero real se vea como **fondo** y no se disimule.

---

## 6. Replicar con tus propias fotos (validar con una captura real)

Igual que en `full2`, esta carpeta incluye el camino para **reproducir el pipeline con fotos
reales** tuyas. Guía paso a paso en [`REPLICAR_CON_TUS_FOTOS.md`](./REPLICAR_CON_TUS_FOTOS.md), y
**la técnica concreta para las zonas difíciles** (talón + interior) en
[`CAPTURA_ZONAS_COMPLEJAS.md`](./CAPTURA_ZONAS_COMPLEJAS.md). Resumen:

```bash
cd experiments
# 1) COLMAP sobre TUS fotos (estima cámaras reales con distorsión) -> workspace listo
bash colmap_sneaker/run_colmap_photos.sh /ruta/a/tus/fotos /ruta/al/ws
# 2) Malla densa + textura a máxima calidad (mismo OpenMVS, preset "photos")
PHOTOS_WS=/ruta/al/ws QUALITY=max bash openmvs/run_openmvs.sh photos
# 3) Ver el resultado (OBJ -> GLB y abrir el visor, como en la sección 1)
```

La **clave de la calidad es la captura**: para igualar `full3`, además de dar toda la vuelta,
haz **tandas de primeros planos acercándote a las cavidades** (boca/cuello desde arriba) y al
**talón** (a la altura y contrapicado). Eso es el equivalente real de los anillos cercanos de
`full3`. Detalle completo en `CAPTURA_ZONAS_COMPLEJAS.md`.

---

## 7. Honestidad / copyright

- El GLB de referencia (`reference_glb/`) y **todo** lo derivado (`synthetic_ref/`,
  `input_images/`, `evidence_local/`, `full3.glb`, OBJ/atlas) son **material de retail con
  copyright**: **estrictamente local y gitignored**, solo como referencia privada de
  investigación. Solo se commitea **herramienta original** (scripts y documentación).
- Comparación **visual**, no métrica. Captura **idealizada** (máscaras exactas, luz uniforme).
  **Circularidad de misma fuente**: las imágenes salen de la misma textura con la que
  comparamos. Ver [`EVIDENCE.md`](./EVIDENCE.md) para el detalle y el framing honesto del talón.
