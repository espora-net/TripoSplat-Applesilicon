EVIDENCIA VISUAL — antes (full2) / después (full3), zonas TALÓN e INTERIOR.

Renders de diagnóstico generados con scripts/render_compare.py (VTK offscreen, misma
escena/luz/cámara para los dos modelos; iluminación de una cara para que un agujero real
se vea como fondo). Pares antes/después:

TALÓN (fondo oscuro; vista desde detrás del contrafuerte):
- antes_talon_full2.png       full2: agujero RASGADO magenta en el contrafuerte (geometría rota).
- despues_talon_full3.png     full3: contrafuerte CONTINUO, costura en zigzag completa, sin agujero.

INTERIOR oblicuo az180 (fondo blanco; mira hacia la pared interior del lado del talón):
- antes_interior_az180_full2.png   full2: ARTEFACTO flotante teal/magenta en la boca + pared interior grumosa.
- despues_interior_az180_full3.png full3: cavidad limpia y continua, lengüeta con trébol adidas, sin artefacto.

INTERIOR oblicuo az000 (fondo blanco; mira hacia la puntera/empeine):
- antes_interior_az000_full2.png   full2: borde RASGADO del apoyo del pie (footbed) tostado.
- despues_interior_az000_full3.png full3: transición footbed/forro suave y continua.

INTERIOR cenital (fondo blanco; cámara directamente encima mirando hacia abajo):
- antes_interior_cenital_full2.png / despues_interior_cenital_full3.png
  Ambos ya muestran la cavidad real (insole con marca adidas); full3 con paredes más completas.

IMPORTANTE (copyright): derivados del modelo de retail con copyright -> gitignored,
estrictamente local. Solo se versiona este README.txt.

Se regeneran con (desde experiments/colmap_sneaker/):
  python3 render_compare.py full2 /tmp/cmp3
  python3 render_compare.py full3 /tmp/cmp3
