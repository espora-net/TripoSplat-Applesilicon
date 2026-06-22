# COLMAP experiment — can this sneaker be reconstructed by photogrammetry?

A **self-contained, reproducible experiment** that asks, empirically: can the
Adidas Tokyo sneaker be reconstructed with classic photogrammetry (COLMAP
Structure-from-Motion), following the official
[COLMAP tutorial](https://colmap.github.io/tutorial.html)?

It has **three parts**, the first two reaching opposite conclusions about
photogrammetry, and the third turning the successful reconstruction into an
actual, viewable Gaussian splat:

| input | script | result | verdict |
|-------|--------|--------|---------|
| **8 retail product stills** | `run_colmap.sh` | **0** verified pairs / 28 → **0 models** | ❌ photogrammetry fails |
| **96 frames from 2 motion videos** | `run_colmap_video.sh` | **91/96 registered**, 1 sparse model | ✅ sparse SfM works |
| **those 91 poses + masks** | `run_brush_splat.sh` | **62 k-Gaussian 3DGS `.ply`**, full-frame eval **32.5 dB** | ✅ real splat, native on Metal |

**TL;DR.** Photogrammetry doesn't fail because the *object* is hard — it fails
when the *capture* has no multi-view overlap (the 8 gallery stills). Give it a
real motion sequence (video frames) and the very same object reconstructs into a
single, coherent, sub-pixel-accurate sparse model — which **brush** then optimises
into a genuine, viewable 3D Gaussian Splat **natively on Apple Silicon (Metal)**,
no CUDA.

## Why this experiment exists

TripoSplat is a **single-image, feed-forward** generator: it hallucinates a full
3D Gaussian-splat object from **one** photo. It has **no camera-pose input** and
no multi-view correspondence mechanism, so feeding it several photos at once
produces an incoherent blob (the "amasijo sin forma"). See the main `README.md`
and `plan.md`.

The natural question was: *would COLMAP help?* COLMAP is the front-end of the
**other** 3D paradigm — **optimisation-based 3D Gaussian Splatting** (Inria /
gsplat / nerfstudio). That pipeline needs SfM to first recover **camera poses**
for many **overlapping** views. This experiment checks, empirically, what kind of
capture clears that first bar.

---

# Part A — the 8 product stills (`run_colmap.sh`)  ❌

Mirrors the tutorial's SfM stage: `feature_extractor` (CPU SIFT) →
`exhaustive_matcher` (OpenGL SIFT) → a match report read straight from
`database.db` → `mapper` → `model_analyzer`. Dense MVS is intentionally skipped
(needs CUDA; the sparse stage is decisive anyway).

```bash
bash run_colmap.sh        # full log: workspace/colmap_run.log
```

### Result — COLMAP cannot reconstruct these images

Feature extraction succeeds (every image yields hundreds–thousands of SIFT
features), but **matching finds nothing**:

| stage | outcome |
|-------|---------|
| SIFT features / image | 877, 1660, 3664, 827, 1166, 5108, **21901**, 8064 |
| image pairs attempted | 28 (all C(8,2) combinations) |
| pairs with ≥1 **raw** match | **0** |
| pairs with ≥1 **geometrically-verified** inlier | **0** |
| sparse models reconstructed | **0** (`mapper`: *"No images with matches"*) |

### Sanity checks — the matcher is *not* broken

Three independent controls all pass, proving the zero-match result is **genuine
lack of overlap**, not a tooling artefact or an over-strict threshold:

1. **Warped self-match.** One photo vs. a perspective-warped copy of itself →
   COLMAP finds **4535 verified inliers**.
2. **Exact-duplicate match.** An exact copy of a real photo → **16355 verified
   inliers** on the identical pair, vs. **0** between two *different* real photos.
3. **Relaxed thresholds.** Re-running with the ratio test wide open
   (`max_ratio 0.95`, `max_distance 0.9`, `cross_check 0`, `min_num_inliers 8`)
   still gives **0 raw matches on all 28 pairs**. With **0 raw descriptor matches
   *before* geometric verification**, no RANSAC/inlier threshold can change the
   outcome.

### Why these photos fail

The 8 stills are a **product gallery**, not a **multi-view capture**: almost no
visual overlap (each shot a different aspect — side, top, sole, detail), a
textureless white background (no scene context to lock onto), and inconsistent
intrinsics / crop / zoom / lighting (every image effectively a different camera).

---

# Part B — frames from two motion videos (`run_colmap_video.sh`)  ✅

The user then supplied **two short videos** of the same sneaker in motion. Frames
sampled from them *are* a genuine multi-view capture with high frame-to-frame
overlap — exactly what SfM needs.

> ⚠️ **Important caveat — the videos are AI-generated.** Both clips
> ("Animate Keyframes …") are **image-to-video keyframe interpolations**, not
> real camera footage. So what follows shows that COLMAP can reconstruct a sparse
> model **from these synthetic frames** — i.e. that the generated sequence is
> internally multi-view-consistent enough for SfM. It does **not** prove that
> photographing the *physical* shoe would succeed; it supports that a **real**
> capture with comparable overlap, parallax, rigidity and coverage would be a
> viable strategy.

**Source.** `static/example_inputs/multiview/adidas_tokyo_sneaker/` (gitignored):
a *zoom* clip (smooth dolly/zoom toward the shoe — high overlap, small baseline)
and a *side* clip (larger viewpoint changes). Each 8 s, 24 fps, 720×1280.

```bash
bash run_colmap_video.sh [FPS]     # default FPS=6 ; log: ws_all/colmap_video.log
python3 visualize_model.py ws_all/sparse/2 renders/recon   # optional previews
```

### Pipeline & the choices that matter

1. **Frame extraction** — ffmpeg @ 6 fps from each clip → 48 + 48 = **96 frames**
   in `frames_all/` (`zoom_*`, `side_*`).
2. **`feature_extractor`** — CPU SIFT, `--ImageReader.single_camera 1`,
   `SIMPLE_RADIAL`. *(Caveat: the two clips are independently AI-generated and the
   zoom may imply a changing focal length, so a single shared intrinsic model is
   an approximation; it nonetheless reconstructs cleanly.)*
3. **`exhaustive_matcher` (OpenGL SIFT)** — **not** `sequential_matcher`.
   Sequential matching only links temporally-adjacent frames, so it matches
   *within* each clip but never *across* the two → fragmented models (we measured
   ≤19-image fragments per clip). **Exhaustive** finds the cross-clip
   correspondences that **fuse both videos into one model**. Result:
   **1075 / 4560 pairs verified** (total 194 681 inliers, max 3613/pair).
4. **`mapper` (incremental SfM) — made deterministic & robust.** COLMAP's mapper
   is **non-deterministic** by default (RANSAC + multithreading + initial-pair
   choice); on this low-parallax data plain runs sometimes fragment (best
   sub-model ~15 images) and sometimes grow to ~90. We therefore:
   - fix `--Mapper.num_threads 1` and `--Mapper.random_seed 42` for
     **reproducibility** (seed set once, **not** searched), and
   - **relax registration thresholds** for the low-parallax / high-overlap video
     regime: `init_min_num_inliers 100→50`, `abs_pose_min_num_inliers 30→15`,
     `abs_pose_min_inlier_ratio 0.25→0.15`, `min_num_matches 15→12`. This is
     deliberate **parameter tuning** (not "defaults just got unlucky"), and it
     makes pose-quality diagnostics (below) necessary to confirm the extra
     registrations are real.

   This configuration is stable: repeated runs yield sub-models of **6/11/91**
   (and a clean end-to-end re-run **8/10/91**). The script always exports the
   **largest** sub-model.

### Result — one coherent sparse model, 91/96 frames

```
colmap model_analyzer  (largest sub-model)
  Registered images : 91   (all 48 zoom + 43/48 side)
  Points            : 8007
  Mean track length : 7.14
  Mean reproj error : 0.65 px   (median 0.52, p95 1.63)
```

A low reprojection error alone is *not* proof of correct geometry (weak baselines
or AI morphing can yield plausible-but-wrong structure), so we report stronger
diagnostics computed from the model itself:

| diagnostic | value | what it tells us |
|------------|-------|------------------|
| **Cross-clip shared 3D points** | **1277 / 8007 (15.9%)** seen in **both** zoom *and* side | the two videos are **genuinely fused** — one rigid reconstruction, not two stitched halves |
| track-length distribution | median 5, **1820 points ≥10 obs**, max 55 | many well-constrained, multiply-observed points |
| per-image observations | **min 22**, median 416, max 2275; **0 images < 20** | even the weakest pose is solidly constrained — the relaxed thresholds did **not** pad the count with garbage |
| reproj error | mean 0.65 / median 0.52 / p95 1.63 px | sub-pixel internal consistency after BA |
| bbox extent ratio | ≈ [0.89, 0.14, 1.0] | **side-biased** coverage (both clips mostly see the outer side) — a recognisable partial reconstruction, **not** full 360° coverage |

The recovered camera centres (`C = -Rᵀt`) trace a clean, smooth arc, and the
colored point cloud is a recognisable sneaker — green body, magenta three-stripes,
gum sole (`renders/recon_object.png`, `renders/recon_cameras.png`; gitignored).

### What this does and does **not** claim

> COLMAP successfully reconstructs a sparse, self-consistent SfM model from
> **91/96 frames** sampled from **two AI-generated** sneaker videos, fusing both
> clips into **one** model (1277 cross-clip points) with sub-pixel reprojection
> error and no weakly-registered poses. This shows the synthetic sequence carries
> enough multi-view consistency for sparse SfM and could serve as the **pose +
> sparse-point front-end** for a later optimisation-based **3DGS** reconstruction
> (gsplat / nerfstudio). Because the source videos are **AI-generated** rather
> than real rigid-camera footage, this does **not** prove physical photogrammetric
> recoverability of the real sneaker; it supports that **real** footage with
> comparable overlap, parallax, rigidity and coverage would likely be viable.

It is **not** itself a finished Gaussian-splat asset, and dense MVS
(`patch_match_stereo` / `stereo_fusion`) is unavailable here (needs CUDA), so
**sparse SfM is the ceiling on macOS**.

---

# Part C — an actual Gaussian splat, native on Apple Silicon (`run_brush_splat.sh`)  ✅

Part B produced **camera poses + a sparse point cloud**. That is the *front-end*
of optimisation-based **3D Gaussian Splatting** — not yet a splat. Part C runs the
optimiser to turn those poses into a **real, viewable 3DGS `.ply`**, at the highest
quality this machine can produce.

### Why `brush` (and not gsplat / nerfstudio)

The reference 3DGS optimisers (Inria, **gsplat**, **nerfstudio**) ship **CUDA-only**
rasterisers → they **do not run on Apple Silicon**. The Metal-native option is
[**brush**](https://github.com/ArthurBrussee/brush): a from-scratch 3DGS
trainer **and** viewer built on `wgpu`/`Burn` that runs on **Metal**, ingests a
COLMAP model directly, and exports a standard 3DGS `.ply` (SH degree 3). We use
the prebuilt `aarch64-apple-darwin` binary (release v0.3.0). So this is the
**best practical Apple-Silicon-local** 3DGS path, *not* a CUDA gsplat/nerfstudio
run.

```bash
bash run_brush_splat.sh            # masks -> black-bg dataset -> 30k-step train
# view it (native Metal viewer):
tools/brush/.../brush_app tools/brush/out/black/sneaker_black_30000.ply --with-viewer
```

### Pipeline & the choices that matter

1. **Foreground masks (`make_masks.py`, BiRefNet).** The repo's background-removal
   model produces a sneaker silhouette **at the original frame resolution** (using
   `remove_background`, **not** `preprocess_image` — the latter crops/recenters,
   which would break alignment with the COLMAP poses). 96 masks, mean foreground
   coverage 24 %.
2. **Clean cut-out via BLACK-background compositing (`make_black_dataset.py`).**
   This is the single most important quality choice, and it was driven by a
   measured failure (below). Each frame is composited onto **black** (`rgb*alpha`)
   and brush trains with its **normal full-image photometric loss**. That forces
   the renderer to reproduce a black background everywhere, so background
   "floater" Gaussians are **actively penalised**.
3. **brush on Metal**, max-quality knobs: `--sh-degree 3` (brush max),
   `--max-resolution 1920` (frames are 720×1280 → **full native resolution**),
   `--total-steps 30000` (densification → 15 k, the standard 3DGS schedule),
   `--eval-split-every 8` (**hold out 12 of 91 views**, stratified across both
   clips), `--seed 42`. 79 train / 12 eval. Runtime **≈ 20 min** on an M3 Pro;
   peak RSS < 1 GB; final model **62 246 Gaussians**, 14.7 MB.

### The floater finding (why "just mask the background" is not enough)

brush also supports a `masks/` folder (`AlphaMode::Masked`), which **ignores** the
background in the loss. We tried it first — and it produces a great-looking shoe
but **bad floaters**: because the busy, animated, light-streak backgrounds of the
(AI-generated) source frames are merely *ignored*, nothing stops Gaussians from
drifting into them. They look fine from the captured views but are garbage from
novel angles. Compositing onto **black + full-image loss** fixes this by
*penalising* any non-black background. We measured both on the **same 12 held-out
views** (`eval_fg_psnr.py`):

| approach | foreground PSNR ↑ | brush full-frame PSNR ↑ | out-of-mask leakage ↓ (floaters) |
|----------|------------------:|------------------------:|---------------------------------:|
| `masks/` folder (`Masked`) | **28.5 dB** | 5.4 dB¹ | **62 %** of bg pixels lit, mean lum 80/255 |
| **black-bg + full loss** *(shipped)* | 26.6 dB² | **32.5 dB** | **0.18 %** of bg pixels lit, mean lum 0.1/255 |

¹ The masked run's full-frame PSNR is *meaningless*: it renders a **black**
background while brush's built-in PSNR compares against the **original** frames,
whose backgrounds are bright animated light streaks. (This is why we report
foreground PSNR + leakage instead of trusting brush's headline number.)
² Slightly lower **only because** it is scored against those same original frames,
whose shoe edges carry a bloom halo the clean model deliberately doesn't
reproduce; against its own (black-bg) eval target brush reports **32.5 dB**. The
**floater leakage drops ~340×** — a clean, viewable asset.

### Honest framing (what this is, and is not)

> A **genuine, viewable, optimised 3D Gaussian Splat** (`.ply`, SH degree 3, 62 k
> Gaussians) **trained locally on Apple Silicon with brush/Metal** — not a CUDA
> gsplat/nerfstudio run — from the COLMAP poses recovered in Part B. It is best
> validated for the **captured side/zoom views**; the **far side, top and sole are
> incomplete or inferred** because the input coverage is side-biased
> (bbox ≈ [0.89, 0.14, 1.0]). Quality is reported as **foreground-mask PSNR on
> held-out source views** (≈ 27 dB) plus an **out-of-mask leakage** floater check —
> **not** full-frame PSNR, **not** metric-scan accuracy, and **not** validated
> against arbitrary real-world viewpoints. The foreground-mask metric only scores
> appearance *inside* the estimated silhouette; the leakage row is what guards
> against floaters/background spill *outside* it.
>
> The source videos are **AI-generated**: COLMAP registering 91/96 frames shows
> the generated frames are self-consistent enough for pose recovery, **not** that
> the physical sneaker was metrically captured.

Caveats and methodology validated by a GPT-5.5 rubber-duck review
(verdict: *sound, with caveats* — all of which are reflected above: the
practical-vs-absolute "max quality" wording, the narrowness of foreground PSNR,
the floater/leakage check, and the AI-source disclosure).

---

```
experiments/colmap_sneaker/
├── README.md              # this file                                  (committed)
├── run_colmap.sh          # Part A — 8 stills pipeline                  (committed)
├── run_colmap_video.sh    # Part B — video-frames pipeline              (committed)
├── visualize_model.py     # render a sparse model (cameras + points)    (committed)
├── run_brush_splat.sh     # Part C — COLMAP -> brush 3DGS pipeline       (committed)
├── make_masks.py          # Part C — BiRefNet foreground masks           (committed)
├── make_black_dataset.py  # Part C — composite frames onto black         (committed)
├── eval_fg_psnr.py        # Part C — foreground PSNR + floater leakage    (committed)
├── images/                # the 8 stills          (gitignored — © adidas / ECI)
├── frames_*/              # extracted video frames (gitignored — derived/©)
├── ws_*/                  # COLMAP workspaces: db, sparse/, logs         (gitignored)
├── renders/               # point-cloud preview PNGs                     (gitignored)
├── gsplat_dataset/        # masked brush dataset: images/masks/sparse    (gitignored)
└── tools/                 # brush binary, black-bg dataset, splats, evals (gitignored)
```

The trained splat itself (`tools/brush/out/black/sneaker_black_30000.ply`,
62 k Gaussians, 14.7 MB) is **gitignored** (heavy/derived); regenerate it with
`bash run_brush_splat.sh`.

# Part D — coverage ablation against a retail benchmark (`run_colmap_synth.sh` + `synth` preset)  🔬

**Question this answers:** *how far can our local COLMAP→OpenMVS pipeline get
toward the quality of a professional retail 3D model, and what actually limits
it?* The user pointed at the interactive 3D sneaker on the El Corte Inglés
product page (a Vyking AR `<model-viewer>` asset) as the quality target.

**Method — a controlled, idealised synthetic ablation.** That retail asset is a
Draco-compressed GLB with a 4096×4096 PBR texture. We decode it locally
(`@gltf-transform` + `draco3dgltf`; trimesh and `gltf-pipeline` both fail to
decode Draco — they silently return all-zero vertices) and use it **only as a
private measuring stick**. `render_synthetic.py` (VTK, offscreen) renders
flat-lit, plain-grey-background views of the GLB plus **exact alpha masks** (from
the z-buffer), in two sets that differ **mainly in pose coverage / view
diversity**:

| set    | views | trajectory                                                     |
|--------|------:|----------------------------------------------------------------|
| `full` |    90 | 3 elevation rings (−25/0/+25°) × 24 az + ±50° rings + top + sole |
| `side` |    27 | a limited frontal-left arc (mimics the original video's bias)  |

Both go through the **same** pipeline: `run_colmap_synth.sh` (COLMAP SfM,
`SIMPLE_PINHOLE`, single camera, exhaustive match, deterministic mapper) then
`QUALITY=max COLOR_NORM=0 run_openmvs.sh synth` (full-res densify L0 +
RefineMesh L0 `--scales 3` + TextureMesh, exact masks staged).

```bash
# 1) render the two synthetic sets from the (local, gitignored) decoded GLB:
#    node decode: @gltf-transform/core + draco3dgltf  ->  eci_tokyo_plain.glb
python3 render_synthetic.py eci_tokyo_plain.glb synthetic_ref/full full 1280
python3 render_synthetic.py eci_tokyo_plain.glb synthetic_ref/side side 1280
# 2) SfM + dense MVS for each:
bash run_colmap_synth.sh full   &&  SYNTH_SET=full QUALITY=max COLOR_NORM=0 bash ../openmvs/run_openmvs.sh synth
bash run_colmap_synth.sh side   &&  SYNTH_SET=side QUALITY=max COLOR_NORM=0 bash ../openmvs/run_openmvs.sh synth
# 3) inspect (turntable + clay):
python3 render_obj_turntable.py synthetic_ref/full/openmvs/scene_textured.obj  /tmp/full.png
python3 render_geo_turntable.py synthetic_ref/full/openmvs/scene_dense_mesh_refine.ply /tmp/full_geo.png
```

### Result

- **COLMAP registration:** `full` = **76/90** images, mean reproj **0.44 px**;
  `side` = **27/27**, 0.44 px. The **14 dropped** `full` views are almost all the
  **underside ring** (el = −50°: 7/8 dropped; plus the straight-up sole) — the
  low-angle sole views carry the least distinctive geometry/texture. The
  collar/top views (el = +25/+50/+82°) **did** register.
- **`full` reconstruction** (~490 k-face refined mesh): complete silhouette;
  **uniform** green (no multi-tone); magenta stripes, gold “adidas Tokyo” text
  legible; suede toe/heel correct; **laces, eyelets, stitching and the 3-stripes
  in genuine 3D relief** (clay render confirms the fine surface).
- **`side` reconstruction:** the captured face looks fine, but the far side /
  heel / back are **hollow with large holes** — the same incomplete-shell failure
  the original side-biased *video* capture produced.
- **Residual `full` defect:** the foot-opening / collar (a **concave cavity**
  walled by the **low-texture green upper**) is **bridged into a smooth dome**;
  the tan footbed reads over the top. Two cheap diagnostics localise the cause:
  (1) `CLOSE_HOLES=0` vs `12` → **identical** geometry, so it is **not** final
  hole-closing; (2) clay render **pre- vs post-RefineMesh** → the dome is
  **already present in the dense `ReconstructMesh` output** and unchanged by
  refinement, so it is **not** refinement smoothing. The dome is therefore
  **dense-MVS / surface-reconstruction interpolation over weak photometric
  evidence** on the textureless concave opening.

### What this does and does **not** claim

- ✅ In this synthetic ablation, **broader pose coverage / view diversity is the
  main changed capture condition**, and it strongly explains the missing-heel /
  hollow-shell failures: same GLB, same pipeline, coverage differs → `full` is
  complete where `side` is holed.
- ✅ Under **idealised** synthetic capture (exact masks, uniform lighting,
  `COLOR_NORM=0`, no sensor/compression noise), the pipeline **preserves
  high-frequency visible texture and recovers fine surface relief approaching the
  visual benchmark**.
- ⚠️ **Same-source circularity:** the synthetic views are rendered from the
  **same** retail texture we compare against, so the colour/texture agreement is
  **not** an independent real-world acquisition result. It does **not** prove the
  local pipeline could match the retail asset from real photos.
- ⚠️ The uniform-green result also benefits from **uniform synthetic lighting**;
  this does not prove coverage *alone* fixed the original multi-tone green (the
  AI-video frames also carried lighting/generation artifacts).
- ⚠️ The domed collar is a **characteristic MVS failure mode on low-texture,
  concave/open geometry** — *likely* improvable (more inward/collar views,
  different meshing/regularisation, manual cleanup), **not proven inherent**. The
  retail asset avoids it because it is **artist-modelled / artist-cleaned**, not
  photogrammetric.
- ⚠️ The comparison is **visual**, not metric (no mesh-to-mesh distance / matched-
  view image diff), and “max quality” here means the practical pipeline maximum,
  not an absolute optimum.

> **Provenance / copyright.** The reference GLB and **all** derived renders,
> masks, COLMAP/OpenMVS outputs under `synthetic_ref/` are **copyrighted retail
> assets**, kept strictly **local and gitignored**, used **only** as a private
> research benchmark — never committed, redistributed or shipped. Only the
> original tooling (`render_synthetic.py`, `run_colmap_synth.sh`, the
> `render_*_turntable.py` viewers, the `synth` preset) is committed.

## Apple Silicon notes — the brush 3DGS step (Part C)

- Prebuilt binary: `gh release download v0.3.0 -R ArthurBrussee/brush -p
  'brush-app-aarch64-apple-darwin.tar.xz'`; then `chmod +x brush_app` and
  `xattr -dr com.apple.quarantine` to clear Gatekeeper. `run_brush_splat.sh`
  downloads + de-quarantines it automatically if missing.
- Runs on **Metal** via `wgpu` (logs `AdapterInfo { name: "Apple M3 Pro", …
  backend: Metal }`). It is both the trainer and a live viewer (`--with-viewer`).
- `make_masks.py` runs BiRefNet on **MPS** (the `deform_conv2d` op falls back to
  CPU, ≈ 8 s/frame, ≈ 12 min for 96 frames — see the main repo's MPS notes).

## Apple Silicon notes (COLMAP 4.0.4, Homebrew, no CUDA)

- Installed via `brew install colmap`. If `colmap` aborts at launch with a
  `dyld: Library not loaded … libabsl_log_internal_check_op…` error, an `abseil`
  upgrade broke `re2`'s linkage — fix with `brew reinstall re2`.
- **Feature extraction** runs on CPU SIFT (`use_gpu=0`) — deterministic.
- **Feature matching**: the **CPU** matcher (`use_gpu=0`) crashes with
  `Trace/BPT trap: 5` (SIGTRAP) on this build, so both scripts use the **OpenGL**
  matcher (`use_gpu=1`), which works under the user's GUI session.
- **Dense MVS** is unavailable without CUDA; only sparse SfM runs on macOS.
