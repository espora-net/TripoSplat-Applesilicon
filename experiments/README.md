# De fotos a un modelo 3D que puedes girar 🥿➡️🧊

Esta carpeta convierte **un montón de fotos** (o fotogramas de un vídeo) de un
objeto en un **modelo 3D con color y textura** que puedes mover, girar y ampliar
en el navegador.

Todo funciona **de forma nativa en tu Mac con Apple Silicon (M3 Pro, 36 GB)**, sin
necesidad de una tarjeta gráfica NVIDIA ni de la nube.

---

## ¿Cómo funciona? (en 3 pasos sencillos)

1. **Mira todas las fotos** y averigua desde qué ángulo se tomó cada una (es como
   reconstruir dónde estaba la cámara en cada disparo).
2. **Calcula la forma del objeto** en 3D a partir de esos ángulos: crea una
   "escultura" hecha de muchos triángulos (lo que se llama una *malla*).
3. **Pega las fotos encima** de esa forma para darle color realista.

El resultado es un archivo 3D que abres en un visor y giras con el ratón.

---

## Cómo usarlo

Abre el Terminal y sitúate en esta carpeta:

```bash
cd experiments
```

### 1) Instalar las herramientas (solo la primera vez)

```bash
bash openmvs/get_openmvs.sh
```

Descarga el motor 3D (OpenMVS) ya preparado para Mac. Tarda unos segundos.

### 2) Generar el modelo 3D

```bash
bash openmvs/run_openmvs.sh sneaker      # la zapatilla Adidas Tokyo (ejemplo)
# o
bash openmvs/run_openmvs.sh tripopoor    # el otro ejemplo (49 fotos reales)
```

Tarda entre un par de minutos (zapatilla) y unos minutos más (fotos grandes).

### 3) Verlo y moverlo en el navegador

```bash
bash openmvs/view_mesh.sh sneaker
```

Se abre el navegador con el modelo. **Arrastra** para girar, **rueda del ratón**
para acercar/alejar, **click derecho + arrastrar** para desplazar.

---

## ¿Por qué la zapatilla se reconoce, pero la superficie no es lisa?

Ya se identifica perfectamente la zapatilla (cuero verde, franjas magenta, el
trébol, los cordones). El programa **ahora aplica automáticamente un paso de
"refinado"** que ha limpiado bastante el resultado: ha quitado los trozos blancos
del fondo que antes sobresalían y ha dejado la silueta más ajustada. Aun así, la
superficie **no queda perfectamente lisa**.

Esto **no es un fallo del programa**: la calidad del modelo 3D depende casi por
completo de **las fotos de entrada**. Con pocas fotos, reflejos, o fondo incluido,
la "escultura" sale con bultos y huecos. La buena noticia es que se puede mejorar
mucho, y casi todo está en cómo se capturan las fotos.

---

## Cómo conseguir MAYOR calidad (una superficie más suave) ⭐

Ordenado de lo que **más** ayuda a lo que menos:

### A. Al hacer las fotos (es lo que más influye, con diferencia)

- **Muchas fotos** (entre 60 y 150). Cuantas más, más suave y completo sale.
- **Gira alrededor del objeto** y que cada foto **se solape bastante** con la
  anterior (avanza poco a poco, sin saltos grandes).
- **Cubre todos los ángulos**: por arriba, por los lados, agachándote para ver la
  parte de abajo, de cerca y de lejos. Los agujeros aparecen donde **no** hubo fotos.
- **Objeto quieto y bien enfocado**: nada de fotos movidas o borrosas.
- **Luz suave y uniforme**, sin reflejos fuertes ni sombras duras. Los materiales
  muy brillantes (charol, metal, plástico reflectante) son los más difíciles.
- **Fondo liso y de color distinto** al objeto, y que **el objeto ocupe gran parte
  del encuadre**. Un fondo neutro ayuda a que no se "cuele" en el modelo.
- **No cambies el objeto** entre fotos (no muevas cordones, no lo deformes).

> Truco práctico: coloca el objeto sobre una mesa giratoria (o gira tú alrededor),
> con luz difusa, y haz una vuelta completa por cada altura (abajo, media, arriba).

### B. Ajustes del proceso

Algunos **ya se aplican solos** en el pipeline (`run_openmvs.sh`):

- ✅ **Refinado** (RefineMesh) → afina la superficie contra las fotos y elimina los
  trozos de fondo sueltos. **Activado por defecto** (desactívalo con `REFINE=0`).
- ✅ **Textura a máxima resolución** → la foto se pega desde la imagen completa, no
  desde una versión reducida. Ya activado.

Y otros se pueden **activar a mano** cuando quieras más calidad:

- 🔲 **Recortar el fondo ("máscaras")** → la mayor mejora de limpieza pendiente:
  le decimos al programa qué es zapatilla y qué es fondo, para que **no reconstruya
  nada del fondo**. Requiere rehacer la parte densa.
- 🔲 **Limpieza más fuerte de la malla** → cierra más agujeros y elimina más picos.

👉 Los comandos exactos para aplicar todo esto **sobre el modelo que ya tenemos**
(sin volver a capturar) están más abajo, en
**[Pasos concretos para mejorar el modelo](#-pasos-concretos-para-mejorar-el-modelo-que-ya-tenemos-avanzado)**.

---

## 🔧 Pasos concretos para mejorar el modelo que ya tenemos (avanzado)

> Basado en la [documentación oficial de OpenMVS](https://github.com/cdcseacave/openMVS/wiki/Usage)
> y revisado con un *rubber-duck* (GPT-5.5). Parten del material **ya calculado**
> (`scene_dense.mvs` + `scene_dense_mesh.ply`), así que **no hay que volver a
> capturar ni rehacer lo más pesado**.

Lo que el pipeline **ya hace por ti** (no tienes que ejecutarlo a mano):

1. **Refinar la malla** (RefineMesh) — recupera detalle y limpia el fondo. En la
   zapatilla pasó de 210k a ~73k caras quitando los picos del fondo.
2. **Texturizar desde la foto a máxima resolución** (usando `scene.mvs`).

Si quieres ir más allá, estos son los comandos exactos. Primero define la ruta a
los programas y entra en la carpeta del ejemplo:

```bash
cd experiments
BIN="$PWD/openmvs/prebuilt"
cd colmap_sneaker/openmvs        # o:  cd TripoPoor/openmvs
```

### 1) Limpieza más fuerte de la malla (agujeros y picos)

Si quedan agujeros (p. ej. en la puntera) o picos sueltos, reconstruye la malla
desde la nube densa que ya tienes, con limpieza más agresiva, y vuelve a refinar y
texturizar:

```bash
"$BIN/ReconstructMesh" -i scene_dense.mvs -p scene_dense.ply \
  -o scene_dense_mesh_clean.mvs \
  --decimate 1 --remove-spurious 40 --remove-spikes 1 \
  --close-holes 60 --smooth 4

"$BIN/RefineMesh"  -i scene.mvs -m scene_dense_mesh_clean.ply \
  -o scene_dense_mesh_clean_refine.mvs \
  --resolution-level 1 --scales 1 --max-face-area 16 --close-holes 60

"$BIN/TextureMesh" -i scene.mvs -m scene_dense_mesh_clean_refine.ply \
  -o scene_clean_textured.mvs \
  --resolution-level 0 --max-texture-size 8192 \
  --global-seam-leveling 0 --local-seam-leveling 0 \
  --empty-color 8421504 --export-type obj
```

### 2) Recortar el fondo con máscaras — la mayor mejora pendiente ⭐

Los restos de fondo se eliminan de raíz si le damos una **silueta (máscara)** por
cada foto. Cada máscara va **junto a su imagen** (en
`openmvs/undistorted/images/`), con el nombre de la imagen **+ `.mask.png`**
(blanco = objeto, negro = fondo):

```
undistorted/images/00001.jpg
undistorted/images/00001.jpg.mask.png
```

Después se vuelve a densificar **ignorando el fondo**, y se rehacen malla → refinado
→ textura a partir de `scene_dense_masked.mvs`:

```bash
"$BIN/DensifyPointCloud" scene.mvs -w . -o scene_dense_masked.mvs \
  --resolution-level 1 --max-resolution 1600 \
  --number-views 5 --number-views-fuse 3 --ignore-mask-label 0
# (TripoPoor: --max-resolution 2400)
```

> Ya generamos máscaras del objeto en la *Parte C* (BiRefNet); se pueden reutilizar.

### 3) Aún más detalle (solo si hace falta y hay tiempo)

Densificar a resolución completa con `--resolution-level 0` en `DensifyPointCloud`
(≈4× píxeles, ≈4–8× CPU/RAM). Recomendado **solo después** de aplicar máscaras,
para no amplificar el ruido del fondo.

### ¿Por dónde empezar?

El **refinado + textura nítida ya están aplicados**. El siguiente salto real de
calidad es **(2) las máscaras**, que quitan por completo los restos de fondo.

---

## ¿Dónde quedan los resultados?

| Ejemplo     | Carpeta de resultados                  | Archivo 3D para el visor          |
|-------------|----------------------------------------|-----------------------------------|
| Zapatilla   | `experiments/colmap_sneaker/openmvs/`  | `scene_textured.glb` / `.obj`     |
| TripoPoor   | `experiments/TripoPoor/openmvs/`       | `scene_textured.glb` / `.obj`     |

- El `.glb` es ideal para **verlo y girarlo** (también se abre en Vista Previa de
  macOS, o en webs como [gltf-viewer](https://gltf-viewer.donmccurdy.com)).
- El `.obj` es el mismo modelo en otro formato, por si lo abres en Blender, MeshLab, etc.

---

## Resumen rápido

```bash
cd experiments
bash openmvs/get_openmvs.sh          # 1) instalar (una vez)
bash openmvs/run_openmvs.sh sneaker  # 2) generar el modelo 3D
bash openmvs/view_mesh.sh sneaker    # 3) verlo y girarlo
```

¿Quieres más nitidez y una superficie más suave? Haz **más fotos, bien iluminadas
y solapadas**, y pídenos activar el **recorte de fondo** y el **refinado**.

> Detalle técnico completo (etapas, parámetros, tiempos medidos, soluciones a
> problemas): [`openmvs/README.md`](openmvs/README.md).
