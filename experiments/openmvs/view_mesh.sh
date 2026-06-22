#!/usr/bin/env bash
#
# Interactive 3D viewer for an OpenMVS textured mesh -- orbit / zoom / pan in
# your browser (drag = rotate, scroll = zoom, right-drag / two-finger = pan).
#
# It exports a portable .glb (geometry + texture in one file) from the textured
# .obj and serves a self-contained <model-viewer> page. Works offline after the
# first run (the model-viewer script is cached next to the model).
#
# Usage:
#   bash view_mesh.sh sneaker        # the Adidas Tokyo mesh
#   bash view_mesh.sh tripopoor      # the TripoPoor mesh (once built)
#   bash view_mesh.sh /path/to/scene_textured.obj
#   PORT=8080 bash view_mesh.sh sneaker
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
EXP="$REPO/experiments"
ARG="${1:-sneaker}"
PORT="${PORT:-8000}"
MV_VER="3.5.0"
MV_URL="https://unpkg.com/@google/model-viewer@${MV_VER}/dist/model-viewer.min.js"

# ---- resolve the textured .obj ---------------------------------------------
case "$ARG" in
  sneaker)   OBJ="$EXP/colmap_sneaker/openmvs/scene_textured.obj" ;;
  tripopoor) OBJ="$EXP/TripoPoor/openmvs/scene_textured.obj" ;;
  *)         OBJ="$ARG" ;;
esac
[ -f "$OBJ" ] || { echo "textured mesh not found: $OBJ"; echo "run:  bash run_openmvs.sh <preset>  first"; exit 1; }
OUT="$(cd "$(dirname "$OBJ")" && pwd)"
BASE="$(basename "${OBJ%.obj}")"
GLB="$OUT/$BASE.glb"
TITLE="$ARG  -  OpenMVS textured mesh"

# ---- export GLB (geometry + texture embedded) if missing -------------------
if [ ! -f "$GLB" ] || [ "$OBJ" -nt "$GLB" ]; then
  echo "[view_mesh] exporting GLB from $BASE.obj ..."
  python - "$OBJ" "$GLB" <<'PY'
import sys, trimesh
obj, glb = sys.argv[1], sys.argv[2]
m = trimesh.load(obj, process=False)
if isinstance(m, trimesh.Scene):
    m = list(m.geometry.values())[0]
m.export(glb)
print("[view_mesh] wrote", glb)
PY
fi

# ---- fetch model-viewer once (so it also works offline) --------------------
MV_JS="$OUT/model-viewer.min.js"
if [ ! -s "$MV_JS" ]; then
  echo "[view_mesh] downloading model-viewer $MV_VER ..."
  curl -fsSL "$MV_URL" -o "$MV_JS" || { echo "could not fetch model-viewer; need internet once"; exit 1; }
fi

# ---- write the viewer page -------------------------------------------------
cat > "$OUT/viewer.html" <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$TITLE</title>
<script type="module" src="./model-viewer.min.js"></script>
<style>
  html,body{margin:0;height:100%;background:#1b1d22;font-family:-apple-system,system-ui,sans-serif;color:#e8e8ea}
  model-viewer{width:100vw;height:100vh;--poster-color:#1b1d22}
  .bar{position:fixed;top:12px;left:12px;right:12px;display:flex;gap:8px;align-items:center;flex-wrap:wrap;z-index:10}
  .bar h1{font-size:13px;font-weight:600;margin:0 12px 0 0;opacity:.9}
  button{background:#2c2f36;border:1px solid #3a3e47;color:#e8e8ea;border-radius:8px;padding:6px 12px;font-size:12px;cursor:pointer}
  button:hover{background:#363a43}
  .hint{position:fixed;bottom:12px;left:12px;font-size:11px;opacity:.6}
</style></head><body>
<div class="bar">
  <h1>$TITLE</h1>
  <button id="spin">⏯ Auto-rotate</button>
  <button id="reset">⟲ Reset view</button>
  <button id="wire">◳ Background</button>
</div>
<model-viewer id="mv" src="./$BASE.glb" alt="$TITLE"
  camera-controls pan-controls touch-action="none"
  interaction-prompt="none" shadow-intensity="1"
  exposure="1.0" environment-image="neutral" auto-rotate>
</model-viewer>
<div class="hint">drag = rotate · scroll = zoom · right-drag / two-finger = pan</div>
<script>
  const mv=document.getElementById('mv');let bg=0;
  document.getElementById('spin').onclick=()=>mv.toggleAttribute('auto-rotate');
  document.getElementById('reset').onclick=()=>{mv.cameraOrbit='0deg 75deg 105%';mv.fieldOfView='auto';};
  document.getElementById('wire').onclick=()=>{bg=(bg+1)%3;document.body.style.background=mv.style.background=['#1b1d22','#ffffff','#000000'][bg];};
</script>
</body></html>
HTML

echo "[view_mesh] serving $OUT on http://localhost:$PORT/viewer.html"
echo "[view_mesh] (Ctrl-C to stop the server)"
command -v open >/dev/null && ( sleep 1; open "http://localhost:$PORT/viewer.html" ) &
cd "$OUT"
exec python -m http.server "$PORT"
