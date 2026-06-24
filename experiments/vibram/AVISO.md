# AVISO DE USO ACADÉMICO Y REFERENCIAS

Este directorio (`experiments/vibram/`) y su **conjunto de datos** —los 5 vídeos de
origen, los fotogramas extraídos, las máscaras, el modelo SfM de COLMAP, los logs de
ejecución y el modelo 3D resultado— se publican **exclusivamente con fines
académicos, docentes y de investigación**. **No se autoriza su uso comercial.**

## Referencia explícita y atribución

- **Proyecto:** *TripoSplat-Applesilicon* — optimización del pipeline de
  reconstrucción 3D (TripoSR/TripoSplat y fotogrametría) para ejecución **nativa en
  Apple Silicon** (Apple M3 Pro, 36 GB, sin CUDA).
- **Objeto reconstruido:** zapatilla **Vibram/Merrell** propiedad del autor.
- **Captura:** **5 vídeos grabados por el propio autor** con teléfono móvil. Material
  **original y propio**, sin derechos de terceros.
- **Autoría de la captura y de la reconstrucción:** titular del repositorio
  (`espora-net` / `carloshm`).
- **Software de terceros utilizado** (cada uno bajo su propia licencia):
  - **COLMAP** — Structure-from-Motion / MVS. J. L. Schönberger & J.-M. Frahm,
    *Structure-from-Motion Revisited*, CVPR 2016.
  - **OpenMVS** — Multi-View Stereo (densificado, malla y textura).
  - **rembg / U²-Net** — segmentación de primer plano (Qin et al., *U²-Net*, 2020).
  - **Google `<model-viewer>`** (Apache-2.0) — visor web incluido en `result_model/`.

## Referencia de calidad (solo inspiración — NO incluida ni utilizada)

El objetivo de calidad se inspiró en la experiencia 3D interactiva de la zapatilla
**Adidas Tokyo** disponible en el visor de *Sneaker Room* de El Corte Inglés:

  https://www.elcorteingles.es/sneaker-room/A54441838-verde-pr-adidas-tokyo-para-mujer/

**Aclaración importante:** ese contenido (modelos GLB, texturas o imágenes de dicha
web/marca) es propiedad de sus respectivos titulares; **no se incluye en este
repositorio y NO se utilizó** para generar el modelo aquí publicado. Sirvió
únicamente como **referencia visual** del nivel de calidad a alcanzar. El modelo de
esta carpeta se generó **al 100 % a partir de los vídeos propios del autor**.

## Resumen de uso

- ✅ Uso **académico**, docente, de investigación y de evaluación/reproducción del método.
- ✅ **Cita requerida:** referenciar este repositorio y el proyecto *TripoSplat-Applesilicon*.
- ❌ Uso **comercial** o redistribución del conjunto de datos con fines lucrativos.
