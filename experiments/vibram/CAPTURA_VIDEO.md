# CAPTURA_VIDEO — cómo grabar para máxima calidad

Guía para grabar **tus propios vídeos** y obtener la mejor reconstrucción posible
con este pipeline. La calidad final depende **mucho más** de la captura que de los
parámetros. Resumen: *resolución alta + nitidez + solape + cobertura de las zonas
difíciles*.

---

## Lo esencial (5 reglas)

1. **Resolución alta y sin recorte agresivo.** Graba en **1080p mínimo, 4K mejor**.
   Cada milímetro de la zapatilla debe ocupar muchos píxeles. (Estos vídeos eran
   848×478 → ese fue el techo de calidad.)
2. **Nitidez por encima de todo.** Mueve la cámara **despacio**; el desenfoque de
   movimiento es veneno para el *matching*. Buena luz = exposición más corta = menos
   borrosidad. El script ya descarta los fotogramas movidos, pero no puede inventar
   nitidez que no hay.
3. **Solape generoso.** Avanza en pasos pequeños: cada fotograma debe compartir
   **~70–80 %** de contenido con el anterior. Órbitas continuas y lentas, no saltos.
4. **Objeto quieto dentro de cada pasada.** Puedes recolocar la zapatilla **entre**
   clips (las máscaras lo absorben), pero **durante** una pasada el objeto no se
   mueve: mueves la **cámara** alrededor.
5. **Luz difusa y constante.** Nublado, sombra abierta o dos focos con difusor.
   Evita sol duro y reflejos. Luz uniforme ⇒ textura de color homogénea (menos
   "verde a varios tonos") y menos brillos quemados.

---

## Plan de pasadas (cubre todo el objeto)

Graba **varias órbitas a distintas alturas**; cada órbita = vuelta completa de 360°
alrededor del eje vertical:

| Pasada | Altura de cámara | Qué captura |
|---|---|---|
| 1 | a la altura del objeto (0°) | silueta lateral, cordones |
| 2 | picado 30–45° | empeine, lengüeta, transición empeine-suela |
| 3 | contrapicado −30° | flancos bajos, costura suela-empeine |
| 4 | cenital (90°) | vista superior, apertura |
| 5 | **suela** (objeto de lado o boca arriba) | dibujo Vibram, logos |
| 6 | **interior** (ver abajo) | cavidad, forro, talón por dentro |

Mejor **2–4 vídeos cortos** (20–40 s) que uno larguísimo: facilita estabilizar y
recolocar entre tomas. Apunta a **150–300 fotogramas útiles** tras el filtro.

---

## Zonas complejas (las que fallan si no las cuidas)

Las zonas cóncavas, oscuras o brillantes son las que estropean una reconstrucción.
Trátalas con pasadas dedicadas:

### Interior / cavidad (el "hueco" que sale en blanco)
- Es **cóncavo y oscuro** ⇒ poca textura para el *matching* y autosombras.
- **Ilumina dentro**: acerca un flexo/linancia difusa para que el forro reciba luz.
- Graba el interior **desde varios ángulos picados** girando alrededor de la boca,
  no solo perpendicular. Acércate para que el interior llene el encuadre.
- Si está muy picado y profundo, algunos fotogramas no registrarán (nos pasó con 6
  fotogramas de v1): compénsalo con **más** ángulos del interior, no con uno solo.

### Talón
- Curvatura cerrada que tiende a quedar liso. Dedícale una **mini-órbita** propia
  alrededor del contrafuerte, a altura media, con solape alto.

### Suela
- Pon la zapatilla **de lado o boca arriba** y orbita el dibujo. El relieve (tacos
  Vibram) reconstruye muy bien si hay luz rasante suave que marque el relieve sin
  crear sombras duras.

### Superficies brillantes (mediasuela, charol, plásticos)
- Los reflejos especulares "se mueven" con la cámara y confunden al *matching*.
- **Luz difusa** (nunca flash directo). Un polarizador en el móvil/cámara ayuda.
- `COLOR_NORM=1` (ya activado) reduce diferencias de exposición, pero no arregla un
  brillo quemado: evítalo en captura.

---

## Fondo y soporte

- Fondo **mate y sin textura repetitiva** (una tela lisa). El pipeline enmascara el
  fondo, así que su color da igual mientras **contraste** con la zapatilla y no
  tenga patrones que confundan a las máscaras.
- Evita superficies **reflectantes o con vetas muy marcadas** (cristal, mármol
  pulido): pueden filtrarse en la máscara.
- Un **plato giratorio** es cómodo, pero si lo usas, **gira tú la cámara** o asegura
  que el fondo gira con el objeto; si el objeto gira y el fondo no, las máscaras son
  obligatorias (este pipeline ya las usa).

---

## Checklist rápido antes de grabar

- [ ] ¿Cámara a 1080p/4K y enfoque bloqueado?
- [ ] ¿Luz difusa, uniforme, sin sol duro ni flash?
- [ ] ¿Movimiento lento y continuo (sin tirones)?
- [ ] ¿Solape ~70–80 % entre fotogramas?
- [ ] ¿Varias alturas + pasada de suela + pasada de interior iluminado?
- [ ] ¿Objeto quieto dentro de cada pasada?
- [ ] ¿Fondo mate y contrastado?

Cumpliendo esto, el mismo pipeline (`extract_frames.py` → `make_masks_u2net.py` →
`run_colmap_vibram.sh` → `run_openmvs.sh photos` → `clean_mesh.py`) rinde
notablemente por encima de este ejemplo, limitado por su origen 848×478.
