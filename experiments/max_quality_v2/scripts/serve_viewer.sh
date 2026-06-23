#!/usr/bin/env bash
#
# Abre el resultado `full3` (talón + interior corregidos) en un visor web interactivo
# (girar / zoom / desplazar). Sirve result_model/ (la copia autocontenida dentro de esta
# carpeta) por HTTP y abre viewer.html en el navegador. Si result_model/ está vacío, lo
# rellena desde la salida del pipeline (../colmap_sneaker/synthetic_ref/full3/openmvs).
#
# Uso:  bash scripts/serve_viewer.sh [puerto]      (por defecto 8780; Ctrl-C para parar)
set -uo pipefail

PORT="${1:-8780}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"     # .../max_quality_v2/scripts
MQ="$(cd "$HERE/.." && pwd)"                              # .../max_quality_v2
EXP="$(cd "$MQ/.." && pwd)"                               # .../experiments
RESULT="$MQ/result_model"                                 # copia autocontenida (gitignored)
SRC="$EXP/colmap_sneaker/synthetic_ref/full3/openmvs"     # salida del pipeline (gitignored)
mkdir -p "$RESULT"

# 1) Asegurar full3.glb dentro de result_model/ (se genera de NUESTRA malla, no del retail).
if [ ! -f "$RESULT/full3.glb" ]; then
  if [ -f "$SRC/full3.glb" ]; then
    echo "Copiando full3.glb a result_model/…"; cp -f "$SRC/full3.glb" "$RESULT/full3.glb"
  elif [ -f "$SRC/scene_textured.obj" ]; then
    echo "Generando full3.glb desde scene_textured.obj (obj2gltf)…"
    ( cd "$SRC" && NODE_OPTIONS="--max-old-space-size=12288" npx --yes obj2gltf -i scene_textured.obj -o full3.glb ) && cp -f "$SRC/full3.glb" "$RESULT/full3.glb"
  else
    echo "No encuentro el modelo. Ejecuta los pasos 3.1–3.3 del README o copia el resultado a result_model/."; exit 1
  fi
fi

# 2) Asegurar viewer.html + librería model-viewer junto al GLB.
cp -f "$HERE/viewer.html" "$RESULT/viewer.html"
[ -f "$RESULT/model-viewer.min.js" ] || cp -f "$EXP/colmap_sneaker/openmvs/model-viewer.min.js" "$RESULT/model-viewer.min.js"

URL="http://127.0.0.1:$PORT/viewer.html"
echo "Sirviendo $RESULT"
echo "Visor:    $URL"
echo "(arrastrar = girar · rueda = zoom · clic derecho / dos dedos = desplazar · Ctrl-C para parar)"

# 3) Abrir el navegador (macOS 'open'; Linux 'xdg-open' si existe) y servir en primer plano.
( sleep 1; (command -v open >/dev/null && open "$URL") || (command -v xdg-open >/dev/null && xdg-open "$URL") ) >/dev/null 2>&1 &
cd "$RESULT" && exec python3 -m http.server "$PORT" --bind 127.0.0.1
