# TripoSplat
TripoSplat converts a single 2D image into high-quality and variable number of 3D Gaussians, developed by [TripoAI](https://www.tripo3d.ai/). It can serve as a powerful pipeline tool for asset creation, AR/VR, game development, simulation environments, and beyond.

<a href="https://arxiv.org/abs/2605.16355"><img src="https://img.shields.io/badge/Read%20Paper-B31B1B?style=for-the-badge&logo=arxiv" alt="Paper"></a>
<a href="https://www.tripo3d.ai/research/triposplat"><img src="https://img.shields.io/badge/Technical%20Blog-grey?style=for-the-badge&logo=data:image/svg%2bxml;base64,PHN2ZyB3aWR0aD0iNjUiIGhlaWdodD0iNjUiIHZpZXdCb3g9IjAgMCA2NSA2NSIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHBhdGggZD0iTTkuNDk5MSA5LjYzNDc3TDE2LjQzNzQgMjEuNDU1NkMxNi40MzkzIDIxLjQ1ODkgMTYuNDQxMiAyMS40NjIyIDE2LjQ0MzEgMjEuNDY1NUwzMC4yNjU4IDQ1LjA1NDhDMzEuNTMyNyA0Ny4yMTY3IDM0LjcwNDUgNDcuMjE2NyAzNS45NzE0IDQ1LjA1NDhMNDkuMzg2MiAyMi4xNjE2SDU5LjQ2MThMNDEuMjY2IDUzLjE2MkMzNy42NDQ5IDU5LjMzMTMgMjguNTkyMyA1OS4zMzEzIDI0Ljk3MTIgNTMuMTYyTDYuNjM5NjcgMjEuOTMwMkM0LjAyNCAxNy40NzM5IDUuNjU5NTYgMTIuMjEyNyA5LjQ5OTEgOS42MzQ3N1oiIGZpbGw9IndoaXRlIi8+CjxwYXRoIGQ9Ik0yMC4xMTIxIDE2LjYwODdIMzQuNjkyNkwyOC42MjIgMjcuMDQ0MkMyOC4yMDMzIDI3Ljc2NCAyOC4yMDgzIDI4LjY0OTIgMjguNjM1MSAyOS4zNjQ0TDMxLjA1MjcgMzMuNDE1MUMzMS45NjU0IDM0Ljk0NDUgMzQuMjE2MyAzNC45MzY1IDM1LjExNzggMzMuNDAwNkw0NC45NzM5IDE2LjYwODdINDYuOTQyTDQ2Ljk0NTUgMTYuNjA4N0g2MC44NDQ2QzYwLjQ4MzIgMTIuMDU4NyA1Ni42NzMxIDguMDQ4ODMgNTEuNDUwOSA4LjA0ODgzTDE1LjA4NzkgOC4wNDg4M0wyMC4xMTIxIDE2LjYwODdaIiBmaWxsPSIjRjhDRjAwIi8+Cjwvc3ZnPgo=" alt="Technical Blog"></a>
<a href="https://huggingface.co/spaces/VAST-AI/TripoSplat"><img src="https://img.shields.io/badge/Huggingface%20Demo-grey?style=for-the-badge&logo=huggingface" alt="HuggingFace Demo"></a>

| ![](static/doc/001.webp) | ![](static/doc/002.webp) |
|---|---|
| ![](static/doc/003.webp) | ![](static/doc/004.webp) |

## Highlights
- **High-quality, versatile generation** that handles a wide range of image styles.
- **Single- or multi-view input**: fuse several photos of the same object (front / side / back) for more complete, higher-quality geometry — or keep using a single image.
- **General quality presets** (`low` / `medium` / `high`, plus Spanish aliases `baja` / `media` / `alta`) that tune sampler steps and Gaussian count in one switch.
- **Runs natively on Apple Silicon (M-series) via the MPS GPU backend** — no CUDA required. The same code auto-selects CUDA, MPS, or CPU.
- **Arbitrary Gaussian count** (up to 262,144) — trade off visual quality against rendering cost according to your need.
- **Optional web/AR export**: convert the output to compressed `.sog` / `.spz` / `.glb` for delivery via [splat-transform](https://github.com/playcanvas/splat-transform) (no hard dependency).
- **Minimal, readable code**: two files (`triposplat.py` and `model.py`), ~2,000 LOC total. Easy to customize and integrate into other ecosystems.
- **Near-zero dependencies**: no `transformers`, no `diffusers`, no version-conflict hell. Runs on any platform.
- **Official ComfyUI support**: drop the [official workflow template](https://github.com/Comfy-Org/workflow_templates/blob/main/templates/3d_triposplat_image_to_gaussian_splat.json) into ComfyUI and start playing with TripoSplat right away.

## Quickstart
Download model weights to `ckpts/` from [HuggingFace](https://huggingface.co/VAST-AI/TripoSplat). 
```bash
# Use one of the following ways to download model weights.

# 1. Use HuggingFace CLI
hf download VAST-AI/TripoSplat --local-dir ckpts/

# 2. Use huggingface_hub
pip install huggingface_hub
python -c "from huggingface_hub import snapshot_download; snapshot_download(repo_id='VAST-AI/TripoSplat', local_dir='ckpts/')"

# 3. Use ModelScope CLI
pip install modelscope
modelscope download VAST-AI-Research/TripoSplat --local_dir ckpts/

# 4. Use modelscope Python SDK
pip install modelscope
python -c "from modelscope import snapshot_download; snapshot_download('VAST-AI-Research/TripoSplat', local_dir='ckpts/')"

# 5. Manual download from HuggingFace / ModelScope.
```

Setup the environment and run the example inference script.
```bash
# install torch and torchvision according to your environment
pip install numpy safetensors pillow tqdm
python run_example.py
```

The exported `.ply` / `.splat` files can be visualized in any 3D Gaussian
viewer — e.g. [SparkJS](https://sparkjs.dev) or
[SuperSplat](https://superspl.at/editor).


## Apple Silicon (MPS)

TripoSplat runs natively on Apple-Silicon Macs (M1/M2/M3/M4) using PyTorch's
**MPS** GPU backend — no CUDA needed. Device selection is automatic:

```python
from triposplat import TripoSplatPipeline
pipe = TripoSplatPipeline(..., device="auto")   # cuda → mps → cpu
```

`device="auto"` (the default) prefers CUDA, then Apple-Silicon MPS, then CPU, so
the same script runs unchanged on an NVIDIA box or a Mac. fp16/bf16 weights are
kept on CUDA and MPS and promoted to fp32 on CPU.

Notes:
- Install the standard macOS PyTorch wheels (`pip install torch torchvision`);
  MPS support is built in.
- A couple of ops have no MPS kernel yet (`deform_conv2d`, `index_copy_`). These
  are handled directly in the code, and `PYTORCH_ENABLE_MPS_FALLBACK=1` is set at
  import time as a safety net for any other gap (export `=0` to opt out).
- **Attention is tiled to fit unified memory.** MPS has no fused/flash-attention
  kernel, so PyTorch would materialise the full `(heads, tokens, tokens)` score
  tensor — several GB for the flow DiT's ~12k-token sequence — and OOM. On MPS
  the pipeline transparently query-tiles attention (numerically identical) and
  flushes the allocator pool between stages. Tune the per-attention score budget
  with `TRIPOSPLAT_SDPA_BUDGET_MB` (default `1536`): raise it (e.g. `4096`) for
  marginally fewer tiles, lower it (e.g. `768`) if a very large multi-view job
  still OOMs. It does **not** materially change speed — see below.
- A 16 GB+ unified-memory Mac is recommended; 36 GB comfortably runs single-image
  and 2–3 view multi-view generation at full resolution.

### Performance on Apple Silicon

The flow-matching DiT is the same fixed-cost transformer regardless of Gaussian
count, and it is genuinely compute-heavy (~12k tokens × tens of layers × two
guidance passes per step). On an M3 Pro the GPU runs near its **practical
ceiling (~4–5 TFLOP/s sustained)** — it is compute-bound, not idle — so a single
sampler step takes tens of seconds. Treat this as an **offline asset tool**, not
a real-time one. Rough single-image wall-clock on an M3 Pro (36 GB), plus a
one-time ~1–2 min encode:

| Preset   | Steps | ≈ time on M3 Pro |
|----------|-------|------------------|
| `low`    | 10    | ~10–12 min       |
| `medium` | 20    | ~20–22 min       |
| `high`   | 30    | ~30–33 min       |

M-series **Max/Ultra** chips have several times the GPU throughput and scale down
proportionally. The cheapest way to go faster is **fewer sampler steps** (cost is
linear — pick a lower preset or pass `steps=`); multi-view adds conditioning
tokens and grows the per-step cost too.



## Multi-view input & quality presets

Pass **several photos of the same object** as a list to fuse them into one model
— the denoiser attends to every view at once, producing more complete geometry
than a single image. Combine with a quality preset for a one-switch quality/cost
trade-off:

```python
# Single image (unchanged behaviour)
gaussian, prepared = pipe.run("photo.png", quality="high")

# Multi-view fusion for maximum quality (front / side / back / rear …)
views = ["front.jpg", "side.jpg", "back.jpg"]
gaussian, prepared = pipe.run(views, quality="high")   # `prepared` is a list here
```

Quality presets (`quality=`):

| Preset | Aliases (EN / ES)            | Steps | Gaussians |
|--------|------------------------------|-------|-----------|
| `low`    | `min`, `fast`, `draft` / `baja`   | 10  | 32,768  |
| `medium` | `normal`, `balanced` / `media`    | 20  | 131,072 |
| `high`   | `max`, `best`, `ultra` / `alta`   | 30  | 262,144 |

Any explicit argument (`steps`, `guidance_scale`, `shift`, `num_gaussians`)
overrides the preset; omitting `quality` keeps the original defaults. Multi-view
attention cost grows with the number of views — on a 36 GB Mac prefer 2–3
full-resolution views; reduce the view count, lower the preset, or downscale the
inputs if you hit an out-of-memory error.

### Example: multi-view sneaker

A ready-made multi-view example uses the catalogue photos of the green
**adidas Tokyo** sneaker. The images are copyrighted (© adidas / El Corte
Inglés), so they are **not** committed — download them locally on demand:

```bash
python download_example_images.py        # whole-shoe views → static/example_inputs/multiview/...
python run_example.py                    # picks up the downloaded views automatically
```

The downloaded folder is git-ignored and includes an `ATTRIBUTION.txt`; use the
images for local testing only and respect the original copyright.


## Gradio Demo

```bash
pip install gradio
python run_gradio.py
```

The demo exposes the **quality preset** dropdown and an **extra-views** uploader
for multi-view fusion, alongside the existing single-image controls.


## Export & compression (web / AR)

The generated `.ply` can be converted to compact, web/AR-friendly formats with
[splat-transform](https://github.com/playcanvas/splat-transform) (MIT). It runs
on Node, so it's optional and kept entirely separate from the model pipeline —
`postprocess_splat.py` shells out to it (or to `npx`) only when you ask:

```bash
# one-off, no install needed (uses npx under the hood)
python postprocess_splat.py output.ply output.sog                 # super-compressed for the web
python postprocess_splat.py output.ply output.glb                 # glTF (KHR_gaussian_splatting) for AR
python postprocess_splat.py output.ply mobile.ply --decimate 50% --clean
```

```python
from postprocess_splat import export_splat, splat_transform_available
if splat_transform_available():
    export_splat("output.ply", "output.sog")                      # web
    export_splat("output.ply", "mobile.ply", decimate="100000")   # lighter for mobile/AR
```

`run_example.py` calls this automatically at the end **if** splat-transform is
reachable, emitting `output.sog` / `output.glb` next to the `.ply`. Install Node
(for `npx`) or `npm install -g @playcanvas/splat-transform` to enable it; without
it, the rest of the pipeline is unaffected.

## License
TripoSplat code and weight models are released under the [MIT License](https://github.com/VAST-AI-Research/TripoSplat/blob/main/LICENSE).

## Citation
If you find TripoSplat useful, please cite:
```bibtex
@misc{yan2026generative3dgaussianslearned,
    title={Generative 3D Gaussians with Learned Density Control}, 
    author={Runjie Yan and Yan-Pei Cao and Peng Wang and Ding Liang and Yuan-Chen Guo},
    year={2026},
    eprint={2605.16355},
    archivePrefix={arXiv},
    primaryClass={cs.GR},
    url={https://arxiv.org/abs/2605.16355}, 
}
```
