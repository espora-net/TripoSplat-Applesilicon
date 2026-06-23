#!/usr/bin/env bash
#
# Abre el resultado `full2` en un visor web interactivo (girar / zoom / desplazar).
# Sirve la carpeta de salida de OpenMVS por HTTP y abre viewer.html en el navegador.
#
# Uso:  bash scripts/serve_viewer.sh [puerto]      (por defecto 8779; Ctrl-C para parar)
set -uo pipefail

PORT="${1:-8779}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"            # .../max_quality_pipeline/scripts
EXP="$(cd "$HERE/../.." && pwd)"                                # .../experiments
OUT="$EXP/colmap_sneaker/synthetic_ref/full2/openmvs"          # malla texturizada + glb (gitignored)

[ -d "$OUT" ] || { echo "No existe $OUT — ejecuta antes los pasos 3.1–3.3 del README."; exit 1; }

# 1) Asegurar el GLB para el visor (se genera de NUESTRA malla, no del GLB de retail).
if [ ! -f "$OUT/full2.glb" ]; then
  [ -f "$OUT/scene_textured.obj" ] || { echo "Falta scene_textured.obj — ejecuta el paso 3.3."; exit 1; }
  echo "Generando full2.glb desde scene_textured.obj (obj2gltf)…"
  ( cd "$OUT" && npx --yes obj2gltf -i scene_textured.obj -o full2.glb )
fi

# 2) Asegurar viewer.html + librería model-viewer junto al GLB.
cp -f "$HERE/viewer.html" "$OUT/viewer.html"
[ -f "$OUT/model-viewer.min.js" ] || cp -f "$EXP/colmap_sneaker/openmvs/model-viewer.min.js" "$OUT/model-viewer.min.js"

URL="http://127.0.0.1:$PORT/viewer.html"
echo "Sirviendo $OUT"
echo "Visor:    $URL"
echo "(arrastrar = girar · rueda = zoom · clic derecho / dos dedos = desplazar · Ctrl-C para parar)"

# 3) Abrir el navegador (macOS 'open'; Linux 'xdg-open' si existe) y servir en primer plano.
( sleep 1; (command -v open >/dev/null && open "$URL") || (command -v xdg-open >/dev/null && xdg-open "$URL") ) >/dev/null 2>&1 &
cd "$OUT" && exec python3 -m http.server "$PORT" --bind 127.0.0.1
