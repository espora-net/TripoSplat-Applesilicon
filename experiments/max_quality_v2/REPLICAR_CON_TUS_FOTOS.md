# Replicar el pipeline con TUS PROPIAS FOTOS (validación con objeto real)

Esta guía reproduce **el mismo proceso de máxima calidad** que `full3` (COLMAP → OpenMVS, sin
CUDA, en Mac Apple Silicon) pero partiendo de **fotografías reales** que tú captures — no de los
renders sintéticos. Es la validación **independiente del objeto físico**: aquí **no** se usa
ningún GLB de referencia.

> **Para las zonas difíciles (talón e interior), lee primero
> [`CAPTURA_ZONAS_COMPLEJAS.md`](./CAPTURA_ZONAS_COMPLEJAS.md).** Es la técnica concreta que, en
> `full3`, marcó la diferencia frente a `full2`.

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
| **Nº de fotos** | **40–120** (para igualar `full3`, hacia el alto del rango). Menos de ~25 sale hueco. |
| **Cobertura 360°** | Da **toda la vuelta** en **2–3 alturas** (a la altura del objeto, picado y contrapicado). |
| **Solape** | **~70–80 %** entre fotos consecutivas (pasos pequeños). Es lo que permite emparejar. |
| **Zonas complejas (talón + interior)** | **Tandas extra de primeros planos** acercándote a las cavidades y al talón. → **Detalle completo en [`CAPTURA_ZONAS_COMPLEJAS.md`](./CAPTURA_ZONAS_COMPLEJAS.md).** Es el equivalente real de los anillos cercanos de `full3`. |
| **Objeto quieto** | No muevas el objeto entre fotos; **muévete tú** (o gira una **mesa giratoria** con fondo y luz fijos). |
| **Enfoque nítido** | Evita el *motion blur*. Buena luz, ISO bajo. El desenfoque mata los *features*. |
| **Luz y fondo uniformes** | Luz difusa (sin sombras duras ni reflejos especulares fuertes). Fondo liso y mate ayuda al enmascarado. |
| **Misma cámara** | Todas las fotos con **el mismo móvil/cámara y misma focal** (no hagas zoom; para acercarte, **acércate físicamente**). Así `single_camera 1` es válido. |
| **Formato** | JPG o PNG. No recortes ni edites unas sí y otras no; mantén EXIF si puedes (ayuda a la focal inicial). |

> Si en vez de fotos tienes un **vídeo orbital**, extrae fotogramas con
> `ffmpeg -i video.mp4 -vf fps=4 fotos/frame_%04d.jpg` y úsalos como carpeta de fotos. Graba
> también **clips cortos acercándote al talón y asomándote a la boca** (zonas complejas).

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
  y, en SfM, error de reproyección **< ~1 px**. (`full3` logró 153/161 a 0.371 px, pero con
  captura idealizada; con fotos reales un >80 % ya es muy bueno.)
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
si existe, `masks/`. Salida en `PHOTOS_WS/openmvs/`. Son **los mismos flags `QUALITY=max`** que
usó `full3` (ver `README.md` §4.3).

**Calidad vs tiempo** (env overrides):
- `QUALITY=max` → resolución completa, máximo detalle (más lento). `QUALITY=high` es un buen
  equilibrio si vas con prisa.
- `COLOR_NORM=1` (**por defecto en fotos reales**) corrige variaciones de exposición/balance
  de blancos entre fotos (evita el "verde multitono" y el interior de otro tono). Ponlo a `0`
  solo si tu luz es perfecta.
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
  # luego copia scripts/viewer.html junto al GLB y cambia el src a "./mi_modelo.glb",
  # o arrástralo a https://modelviewer.dev/editor/
  ```

---

## 6. Resolución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| COLMAP registra pocas/0 imágenes | poco solape, fotos movidas/desenfocadas, focales mezcladas | más fotos y más juntas; nítidas; misma cámara/focal |
| Malla con agujeros en una zona | esa zona se vio desde pocos ángulos | añade fotos rodeando ese lado |
| **Interior como "hueco" sin textura** | ninguna foto **cercana** miraba dentro | **anillos cercanos asomándose a la boca** (ver `CAPTURA_ZONAS_COMPLEJAS.md` §2; caso `full3`) |
| **Talón roto / pegote** | talón visto de lejos y de poca textura | **anillo cercano al talón** + luz lateral difusa (`CAPTURA_ZONAS_COMPLEJAS.md` §3) |
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
