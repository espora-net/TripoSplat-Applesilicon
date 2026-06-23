#!/usr/bin/env bash
#
# Abre la reconstrucción de la zapatilla Vibram/Merrell (generada desde 5 vídeos
# propios por COLMAP→OpenMVS en Apple Silicon) en un visor web interactivo
# (girar / zoom / desplazar). Sirve result_model/ (copia autocontenida) por HTTP.
#
# Uso:  bash serve_viewer.sh [puerto]      (por defecto 8781; Ctrl-C para parar)
set -uo pipefail

PORT="${1:-8781}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"     # .../vibram
RESULT="$HERE/result_model"
MVS="$HERE/recon/colmap_ws/openmvs"
mkdir -p "$RESULT"

# Asegurar el GLB dentro de result_model/ (se regenera de NUESTRA malla limpia).
if [ ! -f "$RESULT/vibram.glb" ]; then
  if [ -f "$MVS/scene_clean.glb" ]; then
    cp -f "$MVS/scene_clean.glb" "$RESULT/vibram.glb"
  elif [ -f "$MVS/scene_textured.obj" ]; then
    echo "Generando vibram.glb (limpieza de 'floaters' + GLB)…"
    python3 "$HERE/clean_mesh.py" "$MVS/scene_textured.obj" "$RESULT/vibram.glb"
  else
    echo "No encuentro el modelo. Ejecuta run_colmap_vibram.sh + run_openmvs.sh photos."; exit 1
  fi
fi
if [ ! -f "$RESULT/model-viewer.min.js" ]; then
  if [ -f "$HERE/../colmap_sneaker/openmvs/model-viewer.min.js" ]; then
    cp -f "$HERE/../colmap_sneaker/openmvs/model-viewer.min.js" "$RESULT/model-viewer.min.js"
  else
    echo "Descargando model-viewer.min.js…"
    curl -fsSL "https://unpkg.com/@google/model-viewer/dist/model-viewer.min.js" \
      -o "$RESULT/model-viewer.min.js" \
      || { echo "No pude obtener model-viewer.min.js (¿sin internet?)."; exit 1; }
  fi
fi

URL="http://127.0.0.1:$PORT/viewer.html"
echo "Sirviendo $RESULT"
echo "Visor:    $URL"
echo "(arrastrar = girar · rueda = zoom · clic derecho / dos dedos = desplazar · Ctrl-C para parar)"
( sleep 1; (command -v open >/dev/null && open "$URL") || (command -v xdg-open >/dev/null && xdg-open "$URL") ) >/dev/null 2>&1 &
cd "$RESULT" && exec python3 -m http.server "$PORT" --bind 127.0.0.1
