# EVIDENCE — antes (`full2`) / después (`full3`): talón e interior corregidos

**Pregunta.** ¿`full3` corrige de verdad los dos defectos de `full2` — el **talón** (agujero
rasgado en el contrafuerte) y el **interior** (la boca del pie con un "hueco" sin textura /
artefactos) — y lo hace **solo** por mejor cobertura de captura, **sin** cambiar OpenMVS?

**Veredicto: SÍ (con matices honestos).** Renders de diagnóstico emparejados (misma escena,
luz y cámara para los dos modelos) muestran que el agujero del talón se cierra y el interior
queda continuo y texturizado. La mejora viene de **53 vistas cercanas nuevas** en `full3`; los
parámetros de OpenMVS son **idénticos** a `full2`. **No** prueba reconstrucción del zapato
físico: las imágenes son renders del GLB de retail (captura idealizada, circular como fuente).

Pinned a la malla `full3` (`scene_textured.obj`, 549.933 v / 1.099.589 caras) y `full2`
(274.500 v / 548.803 caras) de `../colmap_sneaker/synthetic_ref/`.

---

## 1. Cómo se generó la prueba (reproducible)

`scripts/render_compare.py` carga el **OBJ texturizado** de cada modelo con `vtkOBJImporter`,
recupera la orientación de cada reconstrucción (cada SfM vive en su propio sistema de
coordenadas) y renderiza **las mismas vistas** de las dos zonas duras:

- **Vertical (`up`)** = de los centros de cámara de COLMAP: `mean(cámaras de elev. alta) −
  mean(cámaras de elev. baja)`.
- **Eje puntera↔talón (`length`)** = PCA de los vértices de la malla, proyectado perpendicular
  a `up`; se voltea para que `+length` apunte a la **boca** (lado del talón).
- **Iluminación de UNA cara** (`SetTwoSidedLighting(0)`): si hubiera un **agujero real**, el
  interior de la cáscara no se ilumina y se ve como **fondo** — así un hueco no se disimula.

```bash
cd ../colmap_sneaker
python3 render_compare.py full2 /tmp/cmp3      # ANTES
python3 render_compare.py full3 /tmp/cmp3      # DESPUÉS
```

Salida (fondo oscuro para el talón; **fondo blanco** para el interior, para que un hueco se vea
como blanco): `{full2,full3}_heel_behind.png`, `_interior_top.png`, `_interior_obl_az{000,090,180,270}.png`.
Copias curadas en `evidence_local/` (local, gitignored por copyright).

Métricas de orientación recuperadas (registro):
```
full2:  97 cámaras  274.500 verts   boca a length=+0.52R, up=+0.29R del centro
full3: 153 cámaras  549.933 verts   boca a length=+0.44R, up=+0.29R del centro
```

---

## 2. TALÓN (contrafuerte) — `*_heel_behind.png`

| | ANTES (`full2`) | DESPUÉS (`full3`) |
|---|---|---|
| Archivo | `evidence_local/antes_talon_full2.png` | `evidence_local/despues_talon_full3.png` |
| Qué se ve | **Agujero RASGADO** en el ante magenta del contrafuerte: un **vacío en forma de ojo de cerradura** morado oscuro con bordes dentados (la geometría está rota ahí). | Contrafuerte **continuo y completo**: el ante magenta forma el chevrón en "V" con la **costura en zigzag intacta**; **sin agujero ni desgarro**. La boca del cuello, por encima, queda limpia. |
| Por qué | El ante (poca textura) se vio desde lejos → MVS sobre-suaviza y deja un boquete. | 25 vistas **cercanas** al talón (`el 2°` y `−16°`, `dist_scale 0.72`) + `RefineMesh` aportan píxeles y afilan el borde. |

> **Caveat honesto (talón).** El contrafuerte es de **ante de muy poca textura**; `full3`
> **elimina el agujero** y reconstruye una superficie continua, pero su nitidez tiene un límite
> físico: el emparejamiento fotométrico tiene poco a lo que agarrarse en una superficie casi
> lisa, así que el relieve fino del ante es más suave que en un material con patrón. El defecto
> grave (la rotura) se corrige; la microtextura del ante es inherentemente limitada en MVS.

---

## 3. INTERIOR — boca del pie / cavidad del tobillo

### 3.1 Oblicuo az180 — pared interior del lado del talón (`*_interior_obl_az180.png`)

| | ANTES (`full2`) | DESPUÉS (`full3`) |
|---|---|---|
| Archivo | `evidence_local/antes_interior_az180_full2.png` | `evidence_local/despues_interior_az180_full3.png` |
| Qué se ve | Un **artefacto flotante** teal+magenta **suspendido en mitad de la boca** (un trozo de malla suelta) y la pared interior algo grumosa. | Cavidad **limpia y continua**: la **lengüeta con el trébol adidas** se ve nítida abajo, las paredes internas son suaves y continuas, **sin artefacto flotante**. |

### 3.2 Oblicuo az000 — apoyo del pie / empeine (`*_interior_obl_az000.png`)

| | ANTES (`full2`) | DESPUÉS (`full3`) |
|---|---|---|
| Archivo | `evidence_local/antes_interior_az000_full2.png` | `evidence_local/despues_interior_az000_full3.png` |
| Qué se ve | Borde del **apoyo del pie (footbed) tostado RASGADO** (dentado) y la marca "adidas" de la plantilla solo parcial. | Footbed de borde **liso y completo**; la plantilla muestra el **logotipo "adidas" entero y legible** + el trébol. |

### 3.3 Cenital (`*_interior_cenital_full2/3.png`)

Ambos modelos ya imagen la **cavidad real** (la plantilla con la marca adidas), prueba de que
hay geometría interior reconstruida. En `full3` las paredes que la rodean quedan **más
completas** (no solo el footbed visible).

> **Por qué funciona.** En `full2` las vistas que asomaban al cuello **encuadran el zapato
> entero** → el interior recibía solo unos cientos de píxeles → `DensifyPointCloud` quedaba
> escaso → la malla dejaba un boquete / artefacto en la pared del lado del talón. `full3` añade
> **27 vistas cercanas** asomándose a la boca (`el 60°/74°/86°`, `dist_scale 0.58–0.60`, foco
> subido `+0.12R`) → multiplica los píxeles del interior → densify rellena paredes + footbed +
> copa del talón, y `TextureMesh` les pone textura real.

---

## 4. Números que respaldan la mejora

| Métrica | `full2` | `full3` | Lectura |
|---|---:|---:|---|
| Vistas de entrada | 108 | **161** | +53 vistas cercanas a las zonas duras |
| Imágenes registradas (COLMAP) | 97/108 | **153/161** | más solape ⇒ más poses |
| Error medio de reproyección | 0.49 px | **0.371 px** | poses más finas |
| Nube densa (puntos) | — | **6.093.092** | evidencia densa, también en interior |
| Malla densa | 658.601 v | **1.374.941 v** | el doble de detalle bruto |
| Malla refinada/texturizada | 274.500 v / 548.803 f | **549.933 v / 1.099.589 f** | **2×** |
| Atlas de textura | 4.7 MB (8192 px) | **9.5 MB (8192 px)** | más superficie texturizada |

La malla `full3` **no es el GLB de retail** (65.622 v / 99.999 f): topología, recuento y UVs
distintos; el atlas lo **genera OpenMVS**. (La cadena de identidad-de-malla y procedencia del
GLB es la misma que se documentó en `../max_quality_pipeline/EVIDENCE.md`, secciones 3 y 7.)

---

## 5. Alcance honesto (igual que en `full2`)

1. **Comparación visual, no métrica.** Es inspección de renders emparejados, no un PSNR contra
   un escaneo de referencia.
2. **Captura idealizada.** Máscaras exactas (z-buffer), luz uniforme, cámara pinhole sin
   distorsión. Una captura con fotos reales tendrá ruido, distorsión y máscaras imperfectas.
3. **Circularidad de misma fuente (caveat principal).** Las imágenes de entrada se renderizaron
   del **propio GLB de retail**. Por tanto: ✅ la malla la computó el pipeline desde imágenes 2D
   (no es copia del GLB; topología y recuentos distintos); ⚠️ **no** demuestra que se pudiera
   reconstruir el zapato **físico** desde **fotos reales** — la coincidencia de textura es
   esperable porque la fuente visual es la misma.
4. **El talón de ante** mejora claramente (se cierra el agujero) pero su microtextura tiene un
   límite físico en MVS (sección 2).
5. **"Autónomo"** = las etapas COLMAP/OpenMVS **estiman** la geometría sin importar 3D original;
   el **diseño de captura** sí parte del GLB. Para una validación independiente del objeto
   físico, ver `REPLICAR_CON_TUS_FOTOS.md` (fotos propias) y `CAPTURA_ZONAS_COMPLEJAS.md` (cómo
   fotografiar talón e interior).
