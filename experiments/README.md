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

**Elige la calidad** con `QUALITY` (por defecto `medium`, el equilibrio recomendado):

```bash
QUALITY=high   bash openmvs/run_openmvs.sh sneaker   # máximo detalle (4× triángulos, más lento)
QUALITY=medium bash openmvs/run_openmvs.sh sneaker   # equilibrio: superficie suave y limpia ⭐
QUALITY=low    bash openmvs/run_openmvs.sh sneaker   # vista rápida (más basto)
```

> En la zapatilla, `medium` da la **superficie más suave y la silueta más limpia**;
> `high` añade muchísimo más detalle fino, pero a resolución completa la superficie
> sale algo más "arrugada" (ver la sección sobre la suavidad, más abajo).

### 3) Verlo y moverlo en el navegador

```bash
bash openmvs/view_mesh.sh sneaker
```

Se abre el navegador con el modelo. **Arrastra** para girar, **rueda del ratón**
para acercar/alejar, **click derecho + arrastrar** para desplazar.

---

## ¿Por qué la zapatilla se reconoce, pero la superficie no es lisa?

Ya se identifica perfectamente la zapatilla (cuero verde, franjas magenta, el
trébol, los cordones). El programa **ahora aplica automáticamente varios pasos de
limpieza** que han mejorado mucho el resultado:

- **Refinado** de la malla contra las fotos (recupera detalle).
- **Recorte del fondo con máscaras**: quita de raíz los trozos blancos del fondo
  que antes sobresalían (la silueta queda mucho más ajustada).
- **Suavizado y eliminación de picos**, más un pequeño *recorte de la silueta* para
  que no queden "solapas" finas en el contorno.

Con esto la **cara exterior** de la zapatilla (la del logo y las franjas) sale
**suave y limpia**. Aun así, hay zonas que **no quedan perfectamente lisas**: sobre
todo el **interior** de la zapatilla y el **lado opuesto**, porque las fotos del
ejemplo giran casi siempre por el mismo lado.

Esto **no es un fallo del programa**: la calidad del modelo 3D depende casi por
completo de **las fotos de entrada**. Donde **no** hubo fotos (interior, parte de
atrás, suela), el programa tiene que "inventar" y salen bultos o huecos. La buena
noticia es que se puede mejorar mucho, y casi todo está en cómo se capturan las
fotos.

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

Casi todos **ya se aplican solos** en el pipeline (`run_openmvs.sh`):

- ✅ **Refinado** (RefineMesh) → afina la superficie contra las fotos. Activado por
  defecto (desactívalo con `REFINE=0`).
- ✅ **Recorte del fondo con máscaras** → en la zapatilla ya está activado: el
  programa sabe qué es zapatilla y qué es fondo, y **no reconstruye el fondo**. Es
  la mayor mejora de limpieza, y ahora es automática.
- ✅ **Suavizado + eliminación de picos + recorte de la silueta** → para que la
  superficie quede lisa y sin "solapas" en el borde. Se ajusta solo según la calidad.
- ✅ **Textura a máxima resolución** → la foto se pega desde la imagen completa, no
  desde una versión reducida.

Y puedes **subir o bajar la intensidad** cuando quieras:

```bash
QUALITY=high  bash openmvs/run_openmvs.sh sneaker   # más detalle
SMOOTH=6      bash openmvs/run_openmvs.sh sneaker   # superficie aún más suave
MASK_ERODE=6  bash openmvs/run_openmvs.sh sneaker   # recortar más el contorno
MASKS=none    bash openmvs/run_openmvs.sh sneaker   # no recortar el fondo
```

> La regla práctica: **`medium` = la superficie más suave y limpia** (recomendado
> para un render de producto); **`high` = el máximo detalle fino**, a costa de una
> superficie un poco más rugosa porque trabaja a resolución completa.

---

## 🔬 La prueba que lo demuestra: ¿cuánta calidad alcanzamos con cobertura completa?

Para responder a *"¿podemos llegar a la calidad de una zapatilla 3D profesional?"*
hicimos un experimento controlado. Como **vara de medir** (en privado, sin
publicar nada) usamos el **modelo 3D profesional de esta misma zapatilla** que se
puede girar en la web de El Corte Inglés. A partir de él generamos fotos limpias
y **lo pasamos por nuestro propio proceso** en dos versiones:

- **Cobertura COMPLETA**: 90 fotos dando toda la vuelta (por arriba, por los
  lados, por debajo, puntera y talón).
- **Cobertura SESGADA**: solo 27 fotos de un lado (como hacían los vídeos de
  antes).

**Lo que salió:**

- Con **cobertura completa**, el resultado da un salto enorme: el **verde queda
  uniforme** (sin manchas de varios tonos), las **franjas magenta y el texto
  dorado "adidas Tokyo" se leen nítidos**, la puntera y el talón de ante salen
  bien, y aparecen en relieve real los **cordones, los ojales y las costuras**. La
  forma está **completa por los cuatro costados**.
- Con **solo un lado**, la zapatilla sale **hueca y con agujeros** por la parte de
  atrás y el lado contrario — exactamente los mismos fallos que veíamos antes con
  los vídeos.

**La conclusión (lo más importante):** la **cobertura de las fotos es lo que más
decide la calidad**. Dar toda la vuelta elimina los huecos del talón y la parte
trasera. Es justo lo que explica la sección A de arriba, ahora comprobado.

**El único fallo que quedaba — y cómo lo hemos cerrado:** la **boca de la
zapatilla** (por donde entra el pie) salía tapada por una **cúpula lisa** en lugar
de quedar abierta. La causa: con la cobertura "completa" casi ninguna foto se
**asomaba al interior**, así que el programa no tenía pistas de que ahí hay un
hueco y lo rellenaba. **La solución fue añadir fotos mirando hacia dentro de la
boca** (dos anillos de cámaras desde arriba; el preset **`full2`**, 108 fotos en
total). El forro magenta y la plantilla del interior **sí tienen detalle**, así
que con esas vistas el programa ya reconstruye bien el hueco:

- Ahora la **boca queda abierta**, con los **cordones y ojales en relieve real** y
  se ve el **forro magenta por dentro** de la zapatilla — justo como en el modelo
  profesional. La cúpula lisa **desaparece**.
- Es decir, aquel defecto **tampoco era un límite del proceso**: era, otra vez,
  cuestión de **cobertura de fotos** (faltaban vistas asomándose al interior).

Con esto el resultado **alcanza el carácter del modelo profesional de referencia**
(forma completa, textura nítida y boca abierta con cordones). La diferencia que
aún queda es de acabado fino y propia de comparar una captura idealizada con un
modelo hecho a mano por un artista; es una comparación **visual**, no métrica.

> **Nota.** Este modelo profesional y todas las imágenes derivadas son material
> con derechos de autor: se usaron **solo en local como referencia privada**, no
> se suben al repositorio ni se redistribuyen. Lo que sí queda guardado son
> **nuestras herramientas** para repetir la prueba (`colmap_sneaker/render_synthetic.py`,
> `colmap_sneaker/run_colmap_synth.sh` y el preset `synth` de `run_openmvs.sh`).

---

## 🔧 Pasos concretos para mejorar el modelo que ya tenemos (avanzado)

> Basado en la [documentación oficial de OpenMVS](https://github.com/cdcseacave/openMVS/wiki/Usage)
> y revisado con un *rubber-duck* (GPT-5.5). Parten del material **ya calculado**
> (`scene_dense.mvs` + `scene_dense_mesh.ply`), así que **no hay que volver a
> capturar ni rehacer lo más pesado**.

Lo que el pipeline **ya hace por ti** (no tienes que ejecutarlo a mano):

1. **Refinar la malla** (RefineMesh) — recupera detalle y limpia el fondo.
2. **Recortar el fondo con máscaras** (en la zapatilla) — elimina de raíz los restos
   de fondo antes de reconstruir.
3. **Suavizar + quitar picos + recortar la silueta** — para una superficie lisa.
4. **Texturizar desde la foto a máxima resolución** (usando `scene.mvs`).

Los comandos de abajo son la **referencia** de lo que ocurre por dentro (y cómo
ajustarlo aún más a mano). Primero define la ruta a los programas y entra en la
carpeta del ejemplo:

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

### 2) Recortar el fondo con máscaras — ya integrado ✅

> **En la zapatilla esto ya se hace solo.** El pipeline coge las máscaras del objeto
> (las que generamos en la *Parte C* con BiRefNet), las ajusta al tamaño de cada
> imagen, **recorta un poco la silueta** (`MASK_ERODE`) para que no queden solapas, y
> densifica **ignorando el fondo**. Aquí queda como referencia de cómo funciona.

Cada máscara va **junto a su imagen** (en `openmvs/undistorted/images/`), con el
nombre de la imagen **+ `.mask.png`** (blanco = objeto, negro = fondo):

```
undistorted/images/00001.jpg
undistorted/images/00001.jpg.mask.png
```

Después se densifica **ignorando el fondo** (lo que hace el pipeline por ti):

```bash
"$BIN/DensifyPointCloud" scene.mvs -w . -o scene_dense.mvs \
  --resolution-level 1 --max-resolution 1600 \
  --number-views 5 --number-views-fuse 3 --ignore-mask-label 0
# (TripoPoor: --max-resolution 2400)
```

> Para reutilizarlo en tus propias fotos: pasa la carpeta de máscaras con
> `MASKS=/ruta/a/masks bash openmvs/run_openmvs.sh <preset>`.

### 3) Aún más detalle (solo si hace falta y hay tiempo)

Densificar a resolución completa con `QUALITY=high` (≈4× píxeles, ≈4–8× CPU/RAM).
Ya combina el recorte del fondo y un suavizado más fuerte. Da muchísimo más detalle
fino, pero la superficie sale algo más rugosa que en `medium`.

### ¿Por dónde empezar?

El **refinado, las máscaras y el suavizado ya están aplicados** en la zapatilla. Si
quieres una superficie aún más lisa, sube `SMOOTH`; si quieres más detalle, usa
`QUALITY=high`. El **mayor salto de calidad** real ya no está en los ajustes, sino
en **hacer más fotos y mejor iluminadas**, cubriendo también el interior y el lado
que ahora no se ve.

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
bash openmvs/get_openmvs.sh                 # 1) instalar (una vez)
bash openmvs/run_openmvs.sh sneaker         # 2) generar el modelo 3D (calidad media)
QUALITY=high bash openmvs/run_openmvs.sh sneaker   # …o con el máximo detalle
bash openmvs/view_mesh.sh sneaker           # 3) verlo y girarlo
```

¿Quieres más nitidez y una superficie aún más suave? El **recorte de fondo, el
refinado y el suavizado ya van activados**. El siguiente salto está en la captura:
haz **más fotos, bien iluminadas y solapadas**, cubriendo también el interior y el
lado opuesto.

> Detalle técnico completo (etapas, parámetros, tiempos medidos, soluciones a
> problemas): [`openmvs/README.md`](openmvs/README.md).
