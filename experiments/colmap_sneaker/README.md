# COLMAP experiment — can the 8 product stills be reconstructed?

This folder is a **self-contained, reproducible experiment** that tests whether the
8 Adidas Tokyo retail product photos can be reconstructed with classic
photogrammetry (COLMAP Structure-from-Motion), following the official
[COLMAP tutorial](https://colmap.github.io/tutorial.html).

## Why this experiment exists

TripoSplat is a **single-image, feed-forward** generator: it hallucinates a full
3D Gaussian-splat object from **one** photo. It has **no camera-pose input** and no
multi-view correspondence mechanism, so feeding it several photos at once produces
an incoherent blob (the "amasijo sin forma"). See the main `README.md` and
`plan.md` for that analysis.

The natural question was: *would COLMAP help?* COLMAP is the front-end of the
**other** 3D paradigm — **optimisation-based 3D Gaussian Splatting** (Inria /
gsplat / nerfstudio). That pipeline needs SfM to first recover **camera poses** for
many **overlapping** photos. This experiment checks, empirically, whether the 8
product stills can clear that very first bar.

## What the script does (`run_colmap.sh`)

Mirrors the tutorial's Structure-from-Motion stage:

1. **`feature_extractor`** — detect & describe SIFT keypoints (CPU SIFT).
2. **`exhaustive_matcher`** — match all 28 image pairs + geometric verification
   (OpenGL SIFT — see Apple Silicon notes below).
3. **Match report** — read raw vs. geometrically-verified matches straight from
   `database.db`. This is the decisive diagnostic.
4. **`mapper`** — incremental SfM (only meaningful if matches exist).
5. **`model_analyzer`** — report each sparse sub-model; export `.txt` + `.ply`.

Dense MVS (`patch_match_stereo` / `stereo_fusion`) is **intentionally skipped**: it
requires CUDA, unavailable on Apple Silicon. The sparse stage is decisive anyway.

```bash
bash run_colmap.sh
# full log: workspace/colmap_run.log
```

## Result — COLMAP cannot reconstruct these images

Feature extraction succeeds (every image yields hundreds–thousands of SIFT
features), but **matching finds nothing**:

| stage | outcome |
|-------|---------|
| SIFT features / image | 877, 1660, 3664, 827, 1166, 5108, **21901**, 8064 |
| image pairs attempted | 28 (all C(8,2) combinations) |
| pairs with ≥1 **raw** match | **0** |
| pairs with ≥1 **geometrically-verified** inlier | **0** |
| sparse models reconstructed | **0** (`mapper`: *"No images with matches"*) |

**Across all 28 pairs, COLMAP finds zero correspondences.** No matches → no
relative poses → no SfM model → no input for optimisation-based 3DGS. The
photogrammetry route is a dead end for these specific images.

### Sanity checks — the matcher is *not* broken

To rule out a broken/silent matcher, three independent controls all pass:

1. **Warped self-match.** Match one photo (`adidas_tokyo_06`) against a
   perspective-warped copy of itself (simulating a viewpoint change):
   COLMAP finds **4535 verified inliers**.
2. **Exact-duplicate match.** Add an exact copy of a real photo to the set.
   The identical pair yields **16355 verified inliers**, while that same real
   photo vs. a *different* real photo (`00` vs `06`) yields **0**. So the matcher
   produces thousands of matches on these exact sneaker descriptors *when overlap
   exists* — it just doesn't between the 8 distinct stills.
3. **Relaxed thresholds.** Re-running the 28-pair match with the ratio test wide
   open (`SiftMatching.max_ratio 0.95`, `max_distance 0.9`, `cross_check 0`,
   `min_num_inliers 8`) still gives **0 raw matches on all 28 pairs**. Since there
   are **0 raw descriptor matches** *before* geometric verification, no
   verification/RANSAC threshold could change the outcome — the descriptors simply
   have no common ground.

Together these prove the zero-match result on the 8 photos is **genuine lack of
overlap**, not a tooling artefact or an over-strict threshold.

## Why these photos fail (and what *would* work)

The 8 stills are a **product gallery**, not a **multi-view capture**:

- **Almost no visual overlap** — each shot is a different aspect (side, top, sole,
  detail close-ups). SIFT descriptors of a side view and a top-down view simply
  don't correspond.
- **Textureless white background** — nothing in the background to match against;
  studio cut-outs remove all scene context that SfM relies on.
- **Inconsistent intrinsics / crop / zoom / lighting** — every image is a different
  (often retouched) camera; metric consistency is gone.

For optimisation-based 3DGS to work you would need a **different capture**:

- An **orbit video** or **30–100+ photos** going *around* the object, each with
  **high overlap with its neighbours** (each surface point seen in ≥3 images).
- **Consistent camera & lighting**, matte (non-specular) surface, and ideally some
  **textured background / markers** so SfM has features to lock onto.

## Conclusion

This experiment **empirically confirms** the earlier (rubber-duck-validated)
analysis: **COLMAP does not help here.** For TripoSplat, the correct path is
**single-image** generation (pick the photo with the clearest silhouette, use the
`high` quality preset). True multi-photo reconstruction is a **separate pipeline**
(SfM + optimisation-based 3DGS) that requires a **proper multi-view capture** the
product gallery does not provide.

## Files

```
experiments/colmap_sneaker/
├── README.md          # this file (committed)
├── run_colmap.sh      # reproducible pipeline (committed)
├── images/            # the 8 stills (gitignored — © adidas / El Corte Inglés)
└── workspace/         # COLMAP outputs: database.db, sparse/, logs (gitignored)
```

## Apple Silicon notes (COLMAP 4.0.4, Homebrew, no CUDA)

- Installed via `brew install colmap`. If `colmap` aborts at launch with a
  `dyld: Library not loaded … libabsl_log_internal_check_op…` error, an `abseil`
  upgrade broke `re2`'s linkage — fix with `brew reinstall re2`.
- **Feature extraction** runs on CPU SIFT (`use_gpu=0`) — deterministic.
- **Feature matching**: the **CPU** matcher (`use_gpu=0`) crashes with
  `Trace/BPT trap: 5` (SIGTRAP) on this build, so the script uses the **OpenGL**
  matcher (`use_gpu=1`), which works under the user's GUI session. (The OpenGL
  SiftGPU matcher clamps to 16384 features/image — irrelevant here, since the
  result is zero matches regardless.)
- **Dense MVS** is unavailable without CUDA; only sparse SfM runs on macOS.
