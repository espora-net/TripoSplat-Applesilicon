#!/usr/bin/env bash
#
# Fetch the OFFICIAL prebuilt OpenMVS binaries for Apple Silicon (macOS arm64).
#
# OpenMVS ships an official `OpenMVS_macOS_arm64.zip` with every release, so on
# Apple Silicon there is NO need to compile from source: this is the fast path
# (seconds vs the ~1-2 h vcpkg build in build_openmvs.sh). The binaries are
# self-contained and run on M-series out of the box; they even include the
# native OpenMVS `Viewer.app`.
#
# Usage:  bash get_openmvs.sh            # downloads v2.4.0 into ./prebuilt
#         OPENMVS_TAG=v2.4.0 bash get_openmvs.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAG="${OPENMVS_TAG:-v2.4.0}"
DEST="$HERE/prebuilt"
ASSET="OpenMVS_macOS_arm64.zip"

mkdir -p "$DEST"; cd "$DEST"
echo "[get_openmvs] downloading $ASSET from $TAG"
gh release download "$TAG" -R cdcseacave/openMVS -p "$ASSET" --clobber

echo "[get_openmvs] unzipping"
unzip -o -q "$ASSET"

# macOS Gatekeeper: clear quarantine + make executable.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
chmod +x "$DEST"/InterfaceCOLMAP "$DEST"/DensifyPointCloud "$DEST"/ReconstructMesh \
         "$DEST"/RefineMesh "$DEST"/TextureMesh "$DEST"/TransformScene 2>/dev/null || true

echo "[get_openmvs] verifying"
"$DEST/DensifyPointCloud" --help >/dev/null 2>&1
# --help returns nonzero by design; check the binary actually ran instead:
if "$DEST/DensifyPointCloud" --help 2>&1 | grep -q "OpenMVS"; then
  echo "[get_openmvs] OK -> OpenMVS binaries ready in $DEST"
  echo "[get_openmvs] run the pipeline:  bash run_openmvs.sh {sneaker|tripopoor}"
else
  echo "[get_openmvs] ERROR: binary did not run; see Gatekeeper/quarantine"; exit 1
fi
