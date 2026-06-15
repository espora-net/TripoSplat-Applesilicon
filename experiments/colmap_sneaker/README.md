# COLMAP experiment — can this sneaker be reconstructed by photogrammetry?

A **self-contained, reproducible experiment** that asks, empirically: can the
Adidas Tokyo sneaker be reconstructed with classic photogrammetry (COLMAP
Structure-from-Motion), following the official
[COLMAP tutorial](https://colmap.github.io/tutorial.html)?

It has **two parts** that reach opposite conclusions, and the contrast is the
whole point:

| input | script | matcher result | sparse model | verdict |
|-------|--------|----------------|--------------|---------|
| **8 retail product stills** | `run_colmap.sh` | **0** verified pairs / 28 | **0 models** | ❌ photogrammetry fails |
| **96 frames from 2 motion videos** | `run_colmap_video.sh` | **1075** verified pairs / 4560 | **91/96 registered, 1 model** | ✅ sparse SfM works |

**TL;DR.** Photogrammetry doesn't fail because the *object* is hard — it fails
when the *capture* has no multi-view overlap (the 8 gallery stills). Give it a
real motion sequence (video frames) and the very same object reconstructs into a
single, coherent, sub-pixel-accurate sparse model.

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

## Files

```
experiments/colmap_sneaker/
├── README.md             # this file                                  (committed)
├── run_colmap.sh         # Part A — 8 stills pipeline                  (committed)
├── run_colmap_video.sh   # Part B — video-frames pipeline              (committed)
├── visualize_model.py    # render a sparse model (cameras + points)    (committed)
├── images/               # the 8 stills          (gitignored — © adidas / ECI)
├── frames_*/             # extracted video frames (gitignored — derived/©)
├── ws_*/                 # COLMAP workspaces: db, sparse/, logs         (gitignored)
└── renders/              # point-cloud preview PNGs                     (gitignored)
```

## Apple Silicon notes (COLMAP 4.0.4, Homebrew, no CUDA)

- Installed via `brew install colmap`. If `colmap` aborts at launch with a
  `dyld: Library not loaded … libabsl_log_internal_check_op…` error, an `abseil`
  upgrade broke `re2`'s linkage — fix with `brew reinstall re2`.
- **Feature extraction** runs on CPU SIFT (`use_gpu=0`) — deterministic.
- **Feature matching**: the **CPU** matcher (`use_gpu=0`) crashes with
  `Trace/BPT trap: 5` (SIGTRAP) on this build, so both scripts use the **OpenGL**
  matcher (`use_gpu=1`), which works under the user's GUI session.
- **Dense MVS** is unavailable without CUDA; only sparse SfM runs on macOS.
