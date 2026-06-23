#!/usr/bin/env bash
#
# COLMAP Structure-from-Motion on YOUR OWN PHOTOS, so you can REPLICATE and
# VALIDATE the same COLMAP -> OpenMVS pipeline on a real capture (not the
# synthetic renders). Output is a self-contained workspace ready for OpenMVS:
#
#   <ws>/images        -> your photos (symlink to the input folder)
#   <ws>/sparse/0      -> the best COLMAP model (cameras + poses + sparse points)
#
# Then run the dense/mesh/texture stage at max quality:
#   PHOTOS_WS=<ws> QUALITY=max bash ../openmvs/run_openmvs.sh photos
#
# CAPTURE TIPS for good quality (see max_quality_pipeline/REPLICAR_CON_TUS_FOTOS.md):
#   * 40-120 fotos dando toda la vuelta (varias alturas), y unas cuantas
#     ASOMÁNDOSE al interior/huecos (eso es lo que evita la "cúpula").
#   * Objeto quieto, fondo y luz uniformes, mucho solape (~70-80%) entre fotos,
#     enfoque nítido (evita motion blur). Misma cámara/móvil para todas.
#
# Apple Silicon (COLMAP 4.x via Homebrew, no CUDA):
#   * SIFT matcher on GPU (OpenGL); the CPU matcher can crash (SIGTRAP).
#
# Usage:  bash run_colmap_photos.sh /ruta/a/tus/fotos [/ruta/al/workspace]
# Env overrides: CAMERA_MODEL=OPENCV|SIMPLE_RADIAL  SINGLE_CAMERA=1|0
#                MATCHER=exhaustive_matcher|sequential_matcher  EXTRACT_GPU=1 MATCH_GPU=1
set -uo pipefail

PHOTOS="${1:?usage: bash run_colmap_photos.sh /ruta/a/tus/fotos [/ruta/al/workspace]}"
[ -d "$PHOTOS" ] || { echo "no existe la carpeta de fotos: $PHOTOS"; exit 1; }
PHOTOS_ABS="$(cd "$PHOTOS" && pwd)"
WS="${2:-$PHOTOS_ABS/../colmap_ws}"
mkdir -p "$WS"
WS="$(cd "$WS" && pwd)"

CAMERA_MODEL="${CAMERA_MODEL:-OPENCV}"     # lentes reales tienen distorsión (OPENCV o SIMPLE_RADIAL)
SINGLE_CAMERA="${SINGLE_CAMERA:-1}"        # 1 si todas las fotos son del mismo móvil/cámara
EXTRACT_GPU="${EXTRACT_GPU:-1}"
MATCH_GPU="${MATCH_GPU:-1}"                # OpenGL SIFT; el matcher CPU puede petar en macOS
MATCHER="${MATCHER:-exhaustive_matcher}"   # robusto para fotos sin orden; usa sequential_matcher si son un vídeo/orbital

DB="$WS/database.db"
SPARSE_RAW="$WS/sparse_raw"
SPARSE="$WS/sparse"
LOG="$WS/colmap_photos.log"
log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

: > "$LOG"
# images/ as a symlink to your photos (keeps the workspace self-contained, no copy).
[ -e "$WS/images" ] || ln -s "$PHOTOS_ABS" "$WS/images"
NF=$(find -L "$WS/images" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | wc -l | tr -d ' ')
log "fotos=$NF  camera_model=$CAMERA_MODEL single_camera=$SINGLE_CAMERA matcher=$MATCHER  ws=$WS"
[ "$NF" -ge 8 ] || { log "necesitas al menos ~8 fotos con solape (tienes $NF)"; exit 1; }

log "step 1/4  feature_extractor ($CAMERA_MODEL)"
colmap feature_extractor \
  --database_path "$DB" \
  --image_path "$WS/images" \
  --ImageReader.single_camera "$SINGLE_CAMERA" \
  --ImageReader.camera_model "$CAMERA_MODEL" \
  --SiftExtraction.use_gpu "$EXTRACT_GPU" \
  >> "$LOG" 2>&1
log "       feature_extractor exit=$?"

log "step 2/4  $MATCHER"
colmap "$MATCHER" \
  --database_path "$DB" \
  --SiftMatching.use_gpu "$MATCH_GPU" \
  >> "$LOG" 2>&1
log "       $MATCHER exit=$?"

log "step 3/4  mapper (incremental SfM)"
rm -rf "$SPARSE_RAW"; mkdir -p "$SPARSE_RAW"
colmap mapper \
  --database_path "$DB" \
  --image_path "$WS/images" \
  --output_path "$SPARSE_RAW" \
  >> "$LOG" 2>&1
log "       mapper exit=$?"

# Pick the sub-model with the most registered images and place it at sparse/0.
log "step 4/4  selecting best sub-model -> $SPARSE/0"
best=""; best_n=-1
for d in "$SPARSE_RAW"/*/; do
  [ -f "$d/cameras.bin" ] || continue
  n=$(colmap model_analyzer --path "$d" 2>&1 | grep -oE "Registered images: [0-9]+" | grep -oE "[0-9]+$" | head -1)
  n="${n:-0}"
  log "       sub-model $(basename "$d"): $n images"
  if [ "$n" -gt "$best_n" ]; then best_n="$n"; best="$d"; fi
done
[ -n "$best" ] || { log "ERROR: COLMAP no reconstruyó ningún modelo. Revisa solape/enfoque de las fotos y $LOG"; exit 1; }
rm -rf "$SPARSE"; mkdir -p "$SPARSE/0"
cp "$best"cameras.bin "$best"images.bin "$best"points3D.bin "$SPARSE/0/"
[ -f "$best"rigs.bin ] && cp "$best"rigs.bin "$SPARSE/0/" 2>/dev/null || true
[ -f "$best"frames.bin ] && cp "$best"frames.bin "$SPARSE/0/" 2>/dev/null || true

log "RESULT: best model = $best_n/$NF imágenes registradas -> $SPARSE/0"
log "Siguiente paso (malla densa + textura a máxima calidad):"
log "   PHOTOS_WS=\"$WS\" QUALITY=max bash $(cd "$(dirname "${BASH_SOURCE[0]}")/../openmvs" && pwd)/run_openmvs.sh photos"
log "   (opcional) genera máscaras de primer plano en $WS/masks (una <nombre>.png por foto) para limpiar el fondo."
echo "PHOTOS_WS=$WS"
