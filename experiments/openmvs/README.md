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
> full textured mesh — **masked + refined + smoothed** — in **~2 min** at
> `QUALITY=medium` (~75k clean faces, 8.3 MB `.obj`) or **~5.5 min** at
> `QUALITY=high` (full-res, ~279k faces for maximum micro-detail), viewable
> interactively in the browser. See "Quality presets" and "Results" below.

---

## TL;DR — run it whenever you want

```bash
cd experiments/openmvs

# 1) Get OpenMVS (once). Apple Silicon has an OFFICIAL prebuilt -> seconds.
bash get_openmvs.sh

# 2) Build the textured mesh from a COLMAP model.
bash run_openmvs.sh sneaker        # the 91-view Adidas Tokyo model
#   bash run_openmvs.sh tripopoor  # the TripoPoor capture (once its COLMAP is ready)
#   QUALITY=high  bash run_openmvs.sh sneaker   # full-res, 4× faces, more micro-detail
#   QUALITY=low   bash run_openmvs.sh sneaker   # quarter-res, fast preview

# 3) Move the model around in an interactive 3D viewer (browser).
bash view_mesh.sh sneaker          # drag = rotate · scroll = zoom · right-drag = pan
```

That's the whole flow. Steps 2–3 are repeatable; step 1 is one-time.

### Quality presets (`QUALITY=max|high|medium|low`, default `medium`)

Two independent axes drive the result, and they **trade off**:

| `QUALITY` | densify `--resolution-level` | refine `--max-face-area` / `--scales` | smooth / remove-spurious / regularity / mask-erode | extras | sneaker faces |
|---|---|---|---|---|---|
| `max`    | 0 (full res) | 6 / 3  | 3 / 50 / 0.25 / 3 | `COLOR_NORM=1`, `--virtual-face-images 3`, `--close-holes 12` | ~241k |
| `high`   | 0 (full res) | 8 / 2  | 4 / 40 / 0.35 / 4 | — | ~279k |
| `medium` | 1 (half res) | 16 / 2 | 3 / 30 / 0.25 / 3 | — | ~75k  |
| `low`    | 2 (¼ res)    | 32 / 2 | 2 / 20 / 0.20 / 2 | — | ~30k  |

- **DETAIL** scales with `--resolution-level` (full res ⇒ ~4× the points ⇒ many more
  triangles and sharper micro-relief). `max` additionally refines at full image
  resolution with more `--scales` and the finest faces.
- **SMOOTHNESS/CLEANLINESS** comes from `ReconstructMesh --smooth/--remove-spurious`,
  `RefineMesh --regularity-weight`, and eroding the foreground mask to shave
  silhouette slivers ("flaps").
- Full-res depth is **noisier**, so `high`/`max` pair it with stronger smoothing — but for
  a side-biased capture like the sneaker, **`medium` still gives the smoothest,
  cleanest-looking product surface**; `high`/`max` win only when you want maximum
  micro-detail and can tolerate a slightly more crumpled surface. Override any knob
  per run, e.g. `SMOOTH=6`, `MASK_ERODE=6`, `MASKS=none`.

**`QUALITY=max`-only knobs** (also settable on any preset):

- **`COLOR_NORM=1`** — harmonise per-frame exposure/white-balance **before**
  texturing. A two-pass step scales each image's masked-foreground per-channel
  mean toward the global mean (gain clipped [0.5, 2.0]; originals backed up to
  `images_orig/`). This is the **multi-tone-green fix**: OpenMVS' own
  seam-leveling explodes into saturated colour blobs on these video frames (kept
  OFF — see TextureMesh), so `COLOR_NORM` flattens colour at the input instead.
  It is an empirical texture-consistency step, not true colorimetric correction.
- **`CLOSE_HOLES=12`** (vs default 30) — bridge **fewer** small holes so the
  under-shot collar opening is **not** capped by a flat untextured "lid".
- **`EMPTY_COLOR=1710618`** (#1A1A1A) — colour for faces no camera textured;
  near-black reads as natural interior shadow instead of the jarring bright-grey
  patch the user flagged ("la parte de atrás en blanco"). OpenMVS' default is
  orange (16744231).

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
| `run_openmvs.sh {sneaker\|tripopoor\|synth}` | Full 6-stage COLMAP→OpenMVS pipeline (incl. RefineMesh) → textured `.obj` + dense/mesh `.ply`. `synth` = the coverage-ablation set (see `../colmap_sneaker` README "Part D"). |
| `view_mesh.sh {sneaker\|tripopoor\|/path/to.obj}` | Export a portable `.glb` and serve an interactive `<model-viewer>` page (orbit/zoom/pan). |
| `build_openmvs.sh` | *Fallback only:* compile OpenMVS from source via vcpkg. |

### Pipeline stages (`run_openmvs.sh`)

1. `colmap image_undistorter --output_type COLMAP` — InterfaceCOLMAP only
   ingests **undistorted PINHOLE** models, so SIMPLE_RADIAL is undistorted first.
2. `InterfaceCOLMAP` → `scene.mvs`.
2b. **Foreground masks (optional, on for the sneaker).** Each source mask is
   resampled to its undistorted image size, binarized, **eroded by `MASK_ERODE` px**
   (to drop the soft silhouette fringe), and written as **`<stem>.mask.png`** next to
   the image. Needs Python + Pillow. Pass your own with `MASKS=<dir>`; disable with
   `MASKS=none`.

   > **Mask-naming bug (fixed — important).** OpenMVS v2.x reads each mask as
   > `<image-stem>.mask.png` — it **replaces** the image extension, so `zoom_027.jpg`
   > → `zoom_027.mask.png` (**not** `zoom_027.jpg.mask.png`). The previous code
   > appended instead of replacing, so masking was **silently disabled**: at
   > `QUALITY=medium` (level 1) ROI auto-crop hid it, but at `high`/`max` (level 0,
   > ROI off) the background fused into large flat "sail" flaps. Now staged with the
   > extension replaced — 0 mask-load warnings, flaps gone.
3. `DensifyPointCloud` → `scene_dense.mvs` (+ dense `.ply`). The heavy CPU stage.
   Capped with `--resolution-level {0|1|2} --max-resolution N --number-views 5
   --number-views-fuse 3`. When masks are staged it adds **`--ignore-mask-label 0`**
   so the background is never densified. At `--resolution-level 0` it also adds
   **`--estimate-roi 0 --crop-to-roi 0`** (see the level-0 gotcha below).
4. `ReconstructMesh` → rough mesh `.ply` (`--remove-spurious $REMOVE_SPURIOUS
   --close-holes 30 --smooth $SMOOTH`; both scale with the quality preset).
4b. `RefineMesh` (**on by default**, `REFINE=1`) → `scene_dense_mesh_refine.ply`:
   the official "recover all fine details" step, now with
   **`--regularity-weight $REGULARITY`** (higher = smoother). It also *cleans* the
   mesh — on the sneaker `medium` lands at **~75k faces**, dropping disconnected
   background flaps/spikes and tightening the silhouette. ~30–45 s. `REFINE=0` skips.
5. `TextureMesh --export-type obj` → `scene_textured.obj` (+ `.mtl` + texture
   `.jpg`): **the viewable asset**. Textured from the **full-res `scene.mvs`**
   (not the half-res `scene_dense.mvs`) for a sharper atlas.

> **Level-0 gotcha (full-res densify):** the prebuilt v2.4.0 `DensifyPointCloud`
> **segfaults** inside its new ROI estimation/cropping when run at
> `--resolution-level 0`. Disabling it (`--estimate-roi 0 --crop-to-roi 0`) lets
> full-res densification finish (sneaker: 8k → ~800k points). Because ROI no longer
> crops the scene, **foreground masking does the background removal instead** — which
> is why `QUALITY=high` leans on the masks. Only applied at level 0; level 1+ ROI is
> fine.

> **RefineMesh `-w` gotcha:** RefineMesh resolves image paths relative to its working
> folder, so it needs **`-w "$OUT"`** just like Densify/Texture; without it, it fails
> with "failed loading image header". `run_openmvs.sh` passes `-w` to all stages.

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

**Sneaker — 91 × 720×1280, max-res 1600, masked.** Two presets, same machine:

| Stage | `medium` (level 1) | `high` (level 0, ROI-off) |
|---|---|---|
| undistort + InterfaceCOLMAP + stage masks | ~10 s | ~12 s |
| DensifyPointCloud | ~46 s · 210k pts | ~3 min · ~800k pts |
| ReconstructMesh | ~7 s | ~16 s |
| RefineMesh (`REFINE=1`) | ~30 s · **~75k faces** | ~46 s · **~279k faces** |
| TextureMesh (from `scene.mvs`) | ~24 s · 8.3 MB obj | ~83 s · 32 MB obj |
| **Total** | **~2 min** · `.glb` 5.8 MB | **~5.5 min** · `.glb` 21 MB |

`medium` is the recommended canonical for the sneaker: the **mask erosion + stronger
smoothing/regularity** give a visibly smoother outer surface and a tighter silhouette
(z-extent 0.84 → 0.75) than the previous defaults, while `high` quadruples the face
count for micro-detail at the cost of a slightly noisier (full-res depth) surface.

Larger inputs scale up:

| Dataset | Settings | Est. densify | Est. peak RAM |
|---|---|---:|---:|
| TripoPoor — 44 × 4000×3000 | max-res 2400, level 1 | ~1–4 h | ~12–28 GB |

Levers if RAM/time blow up: raise `--resolution-level` (use `QUALITY=low`), lower
`--max-resolution` (e.g. 1800), keep `--number-views 5`, and avoid `QUALITY=high`.

---

## Status & honest caveats

- **Sneaker (best input):** 91 registered views → a complete textured mesh of
  the captured side; the elongated shoe profile is clearly recovered. The outer
  surface (green leather, magenta 3-stripes, gold "adidas TOKYO") is **smooth and
  clean** now that foreground **masking is wired in by default**
  (`DensifyPointCloud … --ignore-mask-label 0`, masks staged as `<stem>.mask.png`
  next to the undistorted images, reusing the BiRefNet masks from Part C) together
  with `RefineMesh` + mesh smoothing/erosion. What is **not** smooth is the shoe's
  **interior cavity and far side** — those were barely photographed (the AI-source
  capture orbits mostly one side), so they stay hollow/inferred. That is a
  **capture-coverage** limit, not a pipeline bug: more overlapping views (incl. the
  inside, the sole and the opposite side) are the only real fix. **This is now
  demonstrated** by a controlled synthetic coverage ablation (same pipeline, full
  360° vs side-biased views rendered from a retail reference) — see
  `../colmap_sneaker/README.md` **"Part D"**: full coverage closes the hollow far
  side/heel; the one residual is the textureless concave collar (a dense-MVS
  interpolation limit, not coverage).
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
