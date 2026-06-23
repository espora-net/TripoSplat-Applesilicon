# GLB de referencia (origen de los renders) — LOCAL, no se commitea

Este es el modelo 3D **profesional de retail** que sirve como **referencia de calidad** y,
en este experimento, como **fuente de los renders** sintéticos que alimentan el pipeline.

## Archivos (gitignored por copyright)

| Archivo | Tamaño | Qué es |
|---|---|---|
| `eci_tokyo_plain.glb`  | ~10 MB | GLB **decodificado** (geometría sin compresión Draco). **Es el que usa `render_synthetic.py`.** |
| `eci_tokyo_draco.glb`  | ~9 MB  | GLB **original** tal cual se sirve en la web (mallas comprimidas con **Draco**). |

## Procedencia

- Modelo interactivo 3D de la ficha de producto de **El Corte Inglés / Sneaker Room**
  (adidas Tokyo, mujer, verde). Visor web propietario (tipo *Vyking*).
- El `.glb` original viene con geometría comprimida en **Draco**; VTK no la lee. Se
  **decodifica** una vez a `eci_tokyo_plain.glb` con `@gltf-transform` + `draco3dgltf`.

## Cómo lo usa el pipeline

`render_synthetic.py` carga **solo** `eci_tokyo_plain.glb` para **renderizar** las 161
vistas (`input_images/`). A partir de ahí, COLMAP + OpenMVS reconstruyen **desde las
imágenes**; el GLB **no** vuelve a leerse (ver `EVIDENCE.md`).

> **Importante:** este GLB es **material de retail con copyright**. Está **gitignored** y se
> conserva **solo en local** como referencia privada de investigación. Para replicar el
> proceso de forma limpia con material propio, usa **tus propias fotos**
> (ver `../REPLICAR_CON_TUS_FOTOS.md`) — ahí no se necesita este GLB para nada.

## SHA256 (trazabilidad)

```
eci_tokyo_draco.glb  cb959e949863ea16bdd00bf493b42acd0d8f94dbe38855ec2e743b9f25a9487a
eci_tokyo_plain.glb  9fe4ecdd229c94313a02ba5e41ccf72268b8ed9852d70a7ccfe397184ccb0b5a
```
(Verifícalos con `shasum -a 256 reference_glb/*.glb`. El `plain` es el que consume
`render_synthetic.py`; es el mismo GLB de referencia que usó `max_quality_pipeline` (full2).)
