# Replicar el pipeline con TUS PROPIAS FOTOS

Esta guía reproduce **el mismo proceso de máxima calidad** (COLMAP → OpenMVS, sin CUDA, en
Mac Apple Silicon) pero partiendo de **fotografías reales** que tú captures — no de los
renders sintéticos. Es la validación **independiente del objeto físico**: aquí **no** se usa
ningún GLB de referencia.

> TL;DR
> ```bash
> cd experiments
> bash colmap_sneaker/run_colmap_photos.sh /ruta/a/tus/fotos /ruta/al/ws
> PHOTOS_WS=/ruta/al/ws QUALITY=max bash openmvs/run_openmvs.sh photos
> # resultado: /ruta/al/ws/openmvs/scene_textured.obj  (+ .mtl + atlas .jpg)
> ```

---

## 0. Requisitos (una vez)

- **COLMAP** (4.x, Homebrew, sin CUDA): `brew install colmap`. Si ves un fallo de `re2`,
  `brew reinstall re2`.
- **OpenMVS**: binarios en `experiments/openmvs/prebuilt/` (ver `openmvs/get_openmvs.sh`).
- Para exportar a GLB y ver en el visor: **Node** (`npx obj2gltf`) — opcional, también vale
  MeshLab para abrir el OBJ directamente.

---

## 1. Cómo capturar (ESTO es lo que decide la calidad)

La geometría y la textura no pueden ser mejores que la cobertura de tus fotos. Objetivo:
**rodear el objeto por completo y dejar que cada zona se vea desde varios ángulos**.

| Recomendación | Detalle |
|---|---|
| **Nº de fotos** | **40–120**. Menos de ~25 suele salir hueco. Más no estorba (solo tarda más). |
| **Cobertura 360°** | Da **toda la vuelta** en **2–3 alturas** (a la altura del objeto, picado y contrapicado). |
| **Solape** | **~70–80 %** entre fotos consecutivas (pasos pequeños). Es lo que permite emparejar. |
| **Huecos / interior** | Haz **varias fotos asomándote a las cavidades** (en la zapatilla: el cuello/empeine desde arriba). Es el equivalente real a los anillos `full2` que evitaron la "cúpula". |
| **Objeto quieto** | No muevas el objeto entre fotos; **muévete tú** alrededor (o gira una **mesa giratoria** con fondo y luz fijos). |
| **Enfoque nítido** | Evita el *motion blur*. Buena luz, ISO bajo. El desenfoque mata los *features*. |
| **Luz y fondo uniformes** | Luz difusa (sin sombras duras ni reflejos especulares fuertes). Fondo liso y mate ayuda al enmascarado. |
| **Misma cámara** | Todas las fotos con **el mismo móvil/cámara y misma focal** (no hagas zoom). Así `single_camera 1` es válido. |
| **Formato** | JPG o PNG. No recortes ni edites unas sí y otras no; mantén EXIF si puedes (ayuda a la focal inicial). |

> Si en vez de fotos tienes un **vídeo orbital**, extrae fotogramas con
> `ffmpeg -i video.mp4 -vf fps=4 fotos/frame_%04d.jpg` y úsalos como carpeta de fotos.
> En ese caso, prueba `MATCHER=sequential_matcher` (más rápido para secuencias ordenadas).

---

## 2. Paso 1 — COLMAP sobre tus fotos (estima las cámaras reales)

```bash
cd experiments
bash colmap_sneaker/run_colmap_photos.sh /ruta/a/tus/fotos /ruta/al/ws
```

Qué hace: extrae *features* SIFT, empareja **todas las fotos contra todas**
(`exhaustive_matcher`, GPU OpenGL) y corre `mapper` (SfM incremental). Elige el sub-modelo
con **más imágenes registradas** y lo deja en `/ruta/al/ws/sparse/0/`. Crea también el enlace
`/ruta/al/ws/images` a tus fotos.

**Modelo de cámara:** por defecto `OPENCV` (lentes reales tienen distorsión). Overrides:

```bash
CAMERA_MODEL=SIMPLE_RADIAL  SINGLE_CAMERA=1  MATCHER=exhaustive_matcher \
  bash colmap_sneaker/run_colmap_photos.sh /ruta/a/tus/fotos /ruta/al/ws
```

**Qué mirar al terminar** (lo imprime el script y queda en `ws/colmap_photos.log`):
- `RESULT: best model = N/M imágenes registradas`. Quieres **N alto** (idealmente >80 % de M)
  y, en SfM, error de reproyección **< ~1 px**.
- Si **N es bajo** o no reconstruye nada: casi siempre es **falta de solape o fotos
  movidas/desenfocadas** → captura más fotos, más juntas y más nítidas. Verifica también que
  no mezclaste focales distintas.

---

## 3. Paso 2 (opcional pero recomendado) — máscaras de primer plano

Las máscaras (silueta del objeto, fondo en negro) limpian el fondo en la malla y la textura.
Crea una PNG por foto, **mismo nombre de archivo**, en `/ruta/al/ws/masks/`
(p. ej. `frame_0007.jpg` → `frame_0007.png`), blanco = objeto, negro = fondo.

Formas de generarlas:
- **rembg** (rápido): `pip install rembg` y, por cada foto, guarda el alfa como máscara.
- **BiRefNet** (lo que usa este repo, alta calidad): ver `tools/.../make_masks.py` (Parte C
  del README de `colmap_sneaker`) — genera máscaras a **resolución nativa** sin recortar
  (importante para no romper el alineado con las poses).

Si no creas la carpeta `masks/`, el pipeline simplemente la **omite** (sin error).

---

## 4. Paso 3 — OpenMVS: densificado, malla, refinado y textura (máxima calidad)

```bash
PHOTOS_WS=/ruta/al/ws QUALITY=max bash openmvs/run_openmvs.sh photos
#   -> /ruta/al/ws/openmvs/scene_textured.obj  (+ .mtl + atlas *_map_Kd.jpg)
#   -> + scene_dense.ply (nube densa) y scene_dense_mesh_refine.ply (malla)
```

El preset `photos` toma de `PHOTOS_WS`: `sparse/0` (modelo COLMAP), `images/` (tus fotos) y,
si existe, `masks/`. Salida en `PHOTOS_WS/openmvs/`.

**Calidad vs tiempo** (env overrides):
- `QUALITY=max` → resolución completa, máximo detalle (más lento). `QUALITY=high` es un buen
  equilibrio si vas con prisa.
- `COLOR_NORM=1` (**por defecto en fotos reales**) corrige variaciones de exposición/balance
  de blancos entre fotos (evita el "verde multitono"). Ponlo a `0` solo si tu luz es perfecta.
- `UNDISTORT_MAX` / `DENSIFY_MAX` (por defecto **2000** px) limitan la resolución para no
  disparar RAM/tiempo en CPU. Súbelos (p. ej. 3000) si tienes margen y quieres más detalle;
  bájalos si se queda sin memoria.

Rutas explícitas (si no usas `PHOTOS_WS`):
```bash
COLMAP_MODEL=/ruta/sparse/0  COLMAP_IMAGES=/ruta/images  OUT=/ruta/salida \
  MASKS=/ruta/masks  QUALITY=max  bash openmvs/run_openmvs.sh photos
```

---

## 5. Paso 4 — Ver el resultado

- **Rápido**: abre `scene_textured.obj` en **MeshLab** (`open -a meshlab scene_textured.obj`).
- **Visor web** (como la sección 1 del README): convierte a GLB y ábrelo con `<model-viewer>`:
  ```bash
  cd /ruta/al/ws/openmvs
  npx --yes obj2gltf -i scene_textured.obj -o mi_modelo.glb
  # luego apunta un visor model-viewer a mi_modelo.glb (puedes copiar scripts/viewer.html
  # y cambiar el src, o arrastrarlo a https://modelviewer.dev/editor/)
  ```

---

## 6. Resolución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| COLMAP registra pocas/0 imágenes | poco solape, fotos movidas/desenfocadas, focales mezcladas | más fotos y más juntas; nítidas; misma cámara/focal |
| Malla con agujeros en una zona | esa zona se vio desde pocos ángulos | añade fotos rodeando ese lado |
| Zona cóncava tapada por una "cúpula" | ninguna foto miraba dentro | fotos **asomándose** a esa cavidad (caso `full2`) |
| Textura con manchas de color | exposición variable entre fotos | `COLOR_NORM=1` (por defecto); mejora la luz al capturar |
| Fondo "pegado" al objeto / velos | sin máscaras | genera `masks/` (paso 3) |
| Se queda sin memoria / muy lento | resolución alta en CPU | baja `DENSIFY_MAX`/`UNDISTORT_MAX` o usa `QUALITY=high` |

---

## 7. Expectativas honestas

- Con fotos reales tendrás **distorsión de lente, ruido y máscaras imperfectas** (el
  experimento sintético las tenía ideales). Por eso el preset usa modelo `OPENCV` y
  `COLOR_NORM=1`. La calidad final dependerá, sobre todo, de **tu cobertura y nitidez**.
- Esto **sí** es una reconstrucción del **objeto físico desde imágenes** (a diferencia del
  experimento sintético, que validaba el *pipeline* sobre renders del GLB de retail).
- Sigue siendo **MVS clásico** (malla + textura), no un Gaussian Splatting. Para 3DGS sobre
  Apple Silicon, ver la Parte C del README de `colmap_sneaker` (`brush` sobre Metal).
