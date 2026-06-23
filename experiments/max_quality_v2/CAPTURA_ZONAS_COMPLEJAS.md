# Cómo fotografiar zonas COMPLEJAS para máxima calidad (talón + interior)

Guía práctica para **capturar las fotos** de modo que el pipeline (COLMAP → OpenMVS) reconstruya
bien las zonas que normalmente **fallan**: las **cóncavas** (interior / boca del pie), las
**ocultas** (talón, lengüeta) y las de **poca textura** (ante, gamuza, charol liso).

Es la traducción a **fotos reales** de lo que el preset sintético **`full3`** hace con cámaras
virtuales. La idea central, en una frase:

> **La calidad de una zona = cuántos píxeles nítidos la ven, desde cuántos ángulos distintos, con
> suficiente solape.** Las zonas complejas fallan porque reciben **pocos píxeles** (están lejos,
> en sombra o tapadas) o **poco paralaje** (siempre desde el mismo lado).

---

## 0. Por qué fallan estas zonas (y qué lo arregla)

| Síntoma típico | Causa | Lo que lo corrige (y qué hace `full3`) |
|---|---|---|
| **Interior = "hueco" blanco sin textura** | la boca se fotografía con el **zapato entero en cuadro** → el interior son 200–300 px → la nube densa queda vacía ahí | **Acercarse** a la abertura: planos cortos asomándose dentro → ×5–10 píxeles. `full3`: anillos `dist_scale 0.58–0.60`, foco subido `+0.12R` |
| **Talón roto / agujero rasgado** | el contrafuerte de ante se ve **de lejos y desde pocos ángulos** → MVS sobre-suaviza y rompe | **Anillo cercano** al talón a la altura y en contrapicado. `full3`: `el 2°`/`−16°`, `dist_scale 0.72` + `RefineMesh` |
| **Pared interior grumosa / trozo "flotando"** | una sola altura mira dentro → la pared opuesta no se ve | **Dos alturas** sobre la abertura (paredes + fondo). `full3`: `el 60°` y `74°`/`86°` |
| **Color del interior en varios tonos** | exposición distinta entre fotos del hueco (más oscuro) y del exterior | **Luz difusa constante** + `COLOR_NORM=1` al procesar |

---

## 1. Base que SIEMPRE debe cumplirse (todo el objeto)

Antes de las zonas difíciles, la captura general tiene que ser sólida (ver detalle en
`REPLICAR_CON_TUS_FOTOS.md`):

- **40–120 fotos**, dando **toda la vuelta** en **2–3 alturas** (a la altura, picado, contrapicado).
- **Solape 70–80 %** entre fotos consecutivas (pasos pequeños).
- **Objeto quieto, muévete tú** (o mesa giratoria con fondo y luz fijos).
- **Misma cámara y misma focal** (no hagas zoom óptico: para acercarte, **acércate físicamente**).
- **Nitidez**: nada de *motion blur*; ISO bajo; buena luz. El desenfoque mata los *features*.
- **Luz difusa y uniforme**; fondo liso y mate (ayuda al enmascarado).

> Las zonas complejas se cubren con **tandas adicionales de primeros planos** ENCIMA de esta base
> 360°, no en lugar de ella. Primero el barrido completo; luego te acercas a cada zona difícil.

---

## 2. INTERIOR (boca del pie / cavidad cóncava) — la técnica

**Objetivo:** que las paredes internas, la lengüeta, el footbed y la copa del talón reciban
**muchos píxeles desde varios ángulos**, sin que tu propia cámara/cuerpo dé sombra.

1. **Acércate a la abertura.** Llena el encuadre con la **boca**, no con el zapato entero. Regla
   práctica: que la abertura ocupe **≥60 %** del fotograma. *(Equivale a `dist_scale ≈ 0.6`.)*
2. **Haz un anillo asomándote, a unos 55–65° sobre el plano de la boca.** Da la vuelta alrededor
   de la abertura en **10–15 posiciones** (cada ~25–30°), siempre **mirando hacia dentro y hacia
   abajo**. Cada foto ve una porción distinta de la pared interior. *(= anillo `el 60°`, 15 az.)*
3. **Repite un segundo anillo más cenital (~75°),** un poco más cerca, para el **fondo** de la
   cavidad (footbed + zona de los dedos). *(= anillo `el 74°`, `dist_scale 0.58`, 12 az.)*
4. **Una o dos cenitales casi verticales** mirando recto hacia el apoyo del pie. *(= `el 86°`.)*
5. **Apunta al BORDE de la abertura, no al centro del zapato.** Si enfocas el centro de la suela,
   la boca se va de cuadro. Mantén el **punto de enfoque en el labio del cuello**. *(= `focal_rise
   +0.12R`.)*
6. **Ilumina el interior.** Es lo más oscuro del objeto: usa **luz difusa frontal** (un panel LED
   suave, o luz de ventana) para que el hueco no quede en sombra. **No** uses flash directo (crea
   reflejos especulares y sombras duras). Mantén **la misma exposición** que en el resto (o procesa
   con `COLOR_NORM=1`) para que el interior no salga de otro tono.
7. **Cuida no tapar la luz con tu cámara.** Al asomarte, tu mano/teléfono puede ensombrecer la
   cavidad: ilumina desde un lado distinto al que disparas.

**Errores que producen el "hueco" blanco:**
- Fotografiar la boca **solo de lejos** (pocos píxeles dentro).
- Mirar dentro **desde un único lado** (la pared opuesta nunca se ve → boquete/artefacto flotante).
- Interior **en sombra** (sin textura que emparejar → densify vacío).

---

## 3. TALÓN / CONTRAFUERTE (oculto + poca textura) — la técnica

**Objetivo:** que el contrafuerte (a menudo **ante/gamuza** liso) tenga píxeles suficientes y
ángulos rasantes que revelen su forma y costuras, para que MVS no lo sobre-suavice en un pegote.

1. **Anillo cercano centrado en el talón**, **a la altura** del contrafuerte (elevación ~0–5°,
   casi de perfil). Da un arco **por detrás** del talón, ~12–15 fotos, **acercándote** (que el
   talón llene el cuadro). *(= anillo `el 2°`, `dist_scale 0.72`, 15 az.)*
2. **Segundo anillo en contrapicado (~ −15°),** mirando el talón **desde abajo** hacia arriba,
   para resolver la **unión talón↔suela** (otra zona que suele quedar pegada). *(= `el −16°`, 10 az.)*
3. **Ángulos rasantes (luz lateral suave).** En superficies de poca textura, una **luz lateral
   difusa** hace que las **costuras, el grano del ante y los paneles** proyecten micro-sombras →
   da *features* que emparejar. Evita luz frontal plana (borra el relieve) y evita el especular
   fuerte (charol con brillos move el "color" entre fotos).
4. **Cubre las transiciones de material** (donde el ante se une al textil/charol): son las que más
   se rompen; encuádralas explícitamente desde 2–3 lados.

**Caveat honesto:** el ante de muy poca textura tiene un **límite físico** en fotogrametría —
aunque hagas todo bien, su microrrelieve quedará algo más suave que un material con patrón. La
captura correcta **elimina el agujero/rotura**; la nitidez del grano es inherentemente limitada.

---

## 4. Otras zonas complejas (mismo principio)

- **Lengüeta y debajo de los cordones:** levanta/separa ligeramente la lengüeta y fotografíala
  aparte; el cruce de cordones crea oclusiones — cúbrelo desde varios lados.
- **Suela y galga (perfil):** apoya el zapato sobre un soporte transparente o captúralo elevado
  para ver la **suela** y la unión con el upper en una tanda dedicada en contrapicado.
- **Superficies brillantes/charol:** son el peor caso (el brillo se "mueve" con la cámara y
  confunde el emparejado). Usa **luz muy difusa** (softbox, día nublado, difusor), evita reflejos
  especulares, y si puedes, **polarizador** cruzado para matarlos.
- **Detalles diminutos (logos, troquelados):** una tanda de **macro** cercana, pero **con la misma
  cámara/focal** que el resto si vas a fusionarlo en un único modelo (cambiar de cámara rompe el
  `single_camera`).

---

## 5. Checklist de captura (imprimible)

```
[ ] Barrido 360° base: 40–120 fotos, 2–3 alturas, solape 70–80 %, nítidas, misma focal
[ ] INTERIOR: anillo ~60° asomándose (10–15 fotos) + anillo ~75° más cerca (10–12) + 1–2 cenitales
[ ] INTERIOR: encuadre = la boca llena ≥60 % del cuadro; enfoque en el LABIO del cuello
[ ] INTERIOR: bien iluminado (luz difusa), sin tu sombra, misma exposición que el resto
[ ] TALÓN: anillo cercano a la altura (12–15) + anillo en contrapicado (8–10), talón llena el cuadro
[ ] TALÓN: luz LATERAL difusa para sacar costuras y grano del ante
[ ] Transiciones de material y lengüeta cubiertas desde 2–3 lados
[ ] Sin flash directo; sin reflejos especulares fuertes; objeto quieto
```

---

## 6. De la captura al modelo (recordatorio)

Una vez tengas las fotos (base + tandas de zonas complejas en la **misma carpeta**):

```bash
cd experiments
bash colmap_sneaker/run_colmap_photos.sh /ruta/a/tus/fotos /ruta/al/ws
PHOTOS_WS=/ruta/al/ws QUALITY=max COLOR_NORM=1 bash openmvs/run_openmvs.sh photos
#   -> /ruta/al/ws/openmvs/scene_textured.obj  (+ atlas)  -> exporta a GLB y abre el visor
```

- Mira el log de COLMAP: quieres **>80 % de imágenes registradas** y **<1 px** de error medio.
- Si una zona sigue con agujero: te **faltan fotos cercanas mirándola** desde varios ángulos →
  añade una tanda más a esa zona y reprocesa. Es exactamente lo que diferenció `full2` de `full3`.
- Mantén `COLOR_NORM=1` en fotos reales (corrige el "multitono" por exposición variable).

> Resumen: **`full3` no cambió el algoritmo, cambió lo que las cámaras miran.** Con fotos reales,
> la palanca es la misma — **acércate a las cavidades y al talón, cúbrelos desde varios ángulos
> con buena luz difusa** — y obtendrás esa misma subida de calidad.
