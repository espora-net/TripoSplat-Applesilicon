# COLMAP → OpenMVS dense pipeline + interactive viewer (Apple Silicon, CUDA-free)

Turn COLMAP camera poses into a **dense, textured 3D mesh** and **spin it in an
interactive viewer** — all running **natively on Apple Silicon, CPU-only**.

This is the classic photogrammetry counterpart to the Gaussian splat (Part C):
where the splat is a point-based radiance field, this is an actual **surface
mesh with a texture atlas** — a more "traditional" 3D asset (`.obj` / `.glb`).

Why OpenMVS: COLMAP's *own* dense stage (`patch_match_stereo` / `stereo_fusion`)
needs CUDA and is unavailable on the Mac, so we hand COLMAP's sparse poses to
**OpenMVS**, whose multi-view stereo runs on CPU/OpenMP.

> **Status: WORKING end-to-end on this M3 Pro.** The sneaker dataset produces a
> full textured mesh (233k dense points → rough 210k-face mesh → **RefineMesh →
> 73k-face clean mesh**, 8.6 MB `.obj` + 0.8 MB texture) in **~2 min total**,
> viewable interactively in the browser. See "Results" below.

---

## TL;DR — run it whenever you want

```bash
cd experiments/openmvs

# 1) Get OpenMVS (once). Apple Silicon has an OFFICIAL prebuilt -> seconds.
bash get_openmvs.sh

# 2) Build the textured mesh from a COLMAP model.
bash run_openmvs.sh sneaker        # the 91-view Adidas Tokyo model
#   bash run_openmvs.sh tripopoor  # the TripoPoor capture (once its COLMAP is ready)

# 3) Move the model around in an interactive 3D viewer (browser).
bash view_mesh.sh sneaker          # drag = rotate · scroll = zoom · right-drag = pan
```

That's the whole flow. Steps 2–3 are repeatable; step 1 is one-time.

---

## Installing OpenMVS — the official prebuilt (recommended)

OpenMVS ships an **official `OpenMVS_macOS_arm64.zip`** with every release, so on
Apple Silicon there is **no need to compile from source**. `get_openmvs.sh`
downloads it (`v2.4.0`), clears the Gatekeeper quarantine, and verifies the
binaries run. It even bundles the native `Viewer.app`.

```bash
bash get_openmvs.sh        # -> experiments/openmvs/prebuilt/{DensifyPointCloud,...}
```

Verified on this machine: `OpenMVS x64 v2.4.0` runs out of the box, detects the
*Apple M3 Pro (11 cores) / 36 GB*, no missing dylibs.

<details>
<summary>Fallback: build from source via vcpkg (only if the prebuilt ever fails)</summary>

`build_openmvs.sh` builds OpenMVS in an **isolated vcpkg dependency universe**
into `~/.cache/openmvs-build` (outside the repo). This avoids this Mac's
bleeding-edge Homebrew libs (Eigen 5, CGAL 6, Boost 1.90), which OpenMVS
(targets Eigen 3.4 / CGAL 5.x) will not compile against. It is a **long build
(~1–2 h)** and is no longer the default path now that the prebuilt works.
`run_openmvs.sh` auto-discovers binaries from `prebuilt/` first, then this build.
A `colima` + `linux/arm64` Docker container is the documented second fallback.
</details>

---

## Scripts

| Script | What it does |
|---|---|
| `get_openmvs.sh` | Download + de-quarantine the **official** macOS arm64 OpenMVS binaries into `prebuilt/`. One-time, seconds. |
| `run_openmvs.sh {sneaker\|tripopoor}` | Full 6-stage COLMAP→OpenMVS pipeline (incl. RefineMesh) → textured `.obj` + dense/mesh `.ply`. |
| `view_mesh.sh {sneaker\|tripopoor\|/path/to.obj}` | Export a portable `.glb` and serve an interactive `<model-viewer>` page (orbit/zoom/pan). |
| `build_openmvs.sh` | *Fallback only:* compile OpenMVS from source via vcpkg. |

### Pipeline stages (`run_openmvs.sh`)

1. `colmap image_undistorter --output_type COLMAP` — InterfaceCOLMAP only
   ingests **undistorted PINHOLE** models, so SIMPLE_RADIAL is undistorted first.
2. `InterfaceCOLMAP` → `scene.mvs`.
3. `DensifyPointCloud` → `scene_dense.mvs` (+ dense `.ply`). The heavy CPU stage.
   Capped with `--resolution-level 1 --max-resolution N --number-views 5
   --number-views-fuse 3` to bound RAM/time.
4. `ReconstructMesh` → rough mesh `.ply` (`--remove-spurious 20 --close-holes 30
   --smooth 2`).
4b. `RefineMesh` (**on by default**, `REFINE=1`) → `scene_dense_mesh_refine.ply`:
   the official "recover all fine details" step. It also *cleans* the mesh — on the
   sneaker it cut **210k → 73k faces**, dropping the disconnected background
   flaps/spikes and tightening the silhouette (the magenta 3-stripes became
   coherent). ~30 s on the sneaker. `REFINE=0` skips it.
5. `TextureMesh --export-type obj` → `scene_textured.obj` (+ `.mtl` + texture
   `.jpg`): **the viewable asset**. Textured from the **full-res `scene.mvs`**
   (not the half-res `scene_dense.mvs`) for a sharper atlas.

> **Note (important gotcha):** the prebuilt `ReconstructMesh` / `RefineMesh` write
> only the mesh `.ply`, **not** a chained `.mvs`. So step 5 feeds `TextureMesh` the
> scene for cameras (`-i scene.mvs`) **plus** the mesh explicitly
> (`-m …mesh_refine.ply`) instead of a positional `.mvs`. `run_openmvs.sh` already
> does this.

> **Texture-blob fix (important):** OpenMVS' default global+local seam-leveling
> exploded into vivid saturated primary-color blobs on our scenes (both AI-frame
> and real-photo). `--global-seam-leveling 0 --local-seam-leveling 0` restores the
> true photographic texture (visible patch seams are the expected tradeoff);
> `--empty-color 8421504` paints uncovered faces gray instead of orange.
> `SEAM_LEVELING=1` re-enables OpenMVS' default leveling.

---

## Viewing the result interactively (`view_mesh.sh`)

The simplest way to **move the model around** is the bundled web viewer:

```bash
bash view_mesh.sh sneaker          # opens http://localhost:8000/viewer.html
PORT=8080 bash view_mesh.sh sneaker
bash view_mesh.sh /path/to/scene_textured.obj
```

It exports a single-file `.glb` (geometry + texture embedded) and serves a
self-contained [`<model-viewer>`](https://modelviewer.dev) page. Controls:

- **drag** = rotate · **scroll / pinch** = zoom · **right-drag / two-finger** = pan
- buttons for auto-rotate, reset view, and background colour.

The `model-viewer` script is cached next to the model on first run, so it works
**offline** afterwards. Stop the server with Ctrl-C (or `kill <PID>` of
`python -m http.server`).

### Other viewers

- **OpenMVS `Viewer.app`** (bundled in `prebuilt/`) — native macOS viewer; opens
  a `.mvs` scene (e.g. `scene_dense.mvs` for the dense cloud).
- **macOS Quick Look / Preview** — `open scene_textured.obj` (SceneKit renders
  `.obj`/`.glb` and lets you rotate).
- **MeshLab** (`brew install --cask meshlab`) / **Blender** (`Import → .obj`).

---

## Results (measured on this M3 Pro, CPU-only)

**Sneaker — 91 × 720×1280, max-res 1600, level 1:**

| Stage | Time | Output |
|---|---:|---|
| image_undistorter + InterfaceCOLMAP | ~2 s | `scene.mvs` |
| DensifyPointCloud | ~48 s | `scene_dense.ply` — 233,331 points (17 MB) |
| ReconstructMesh | ~6 s | rough mesh — 105,306 verts / 210,530 faces |
| RefineMesh (`REFINE=1`) | ~31 s | refined mesh — 36,842 verts / **73,495 faces** (1.3 MB); background flaps removed |
| TextureMesh (from `scene.mvs`) | ~26 s | `scene_textured.obj` 8.6 MB + texture 0.8 MB |
| **Total** | **~2 min** | + `scene_textured.glb` 5.7 MB (for the viewer) |

The small video frames make this far faster than a worst-case estimate. Larger
inputs scale up:

| Dataset | Settings | Est. densify | Est. peak RAM |
|---|---|---:|---:|
| TripoPoor — 44 × 4000×3000 | max-res 2400, level 1 | ~1–4 h | ~12–28 GB |

Levers if RAM/time blow up: raise `--resolution-level`, lower `--max-resolution`
(e.g. 1800), keep `--number-views 5`, and avoid full-res `RefineMesh`.

---

## Status & honest caveats

- **Sneaker (best input):** 91 registered views → a complete textured mesh of
  the captured side; the elongated shoe profile is clearly recovered. The
  AI-generated source frames have busy backgrounds and no masks were applied, so
  the *dense* mesh included background/support flaps around the shoe — **RefineMesh
  (now on by default) removes most of them** and tightens the silhouette. For the
  remainder, the real fix is foreground **masking** before densify
  (`DensifyPointCloud … --ignore-mask-label 0`, masks named `name.ext.mask.png`
  next to the undistorted images), reusing the BiRefNet masks from Part C. See the
  Spanish runbook `../README.md` ("Pasos concretos") for copy-paste commands.
- **TripoPoor (hard input):** a real handheld orbit of a **white, reflective
  leather sneaker in dim light against a plain background**. The first COLMAP
  pass registered only 13/44 images into two fragmented sub-models; a
  high-quality pass (`../TripoPoor/run_colmap_hq.sh`: full-res, affine-shape +
  domain-size-pooling features, guided matching, permissive mapper) is the fix.
  Mesh quality is **input-limited** — better light, more overlap, and a less
  specular/more textured subject help more than any pipeline knob.
- Everything heavy (the prebuilt binaries, undistorted images, depth maps, dense
  clouds, meshes, `.glb`) is **gitignored**; only the scripts + this README are
  committed.
