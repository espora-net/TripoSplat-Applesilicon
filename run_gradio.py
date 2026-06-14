"""TripoSplat Gradio demo with Spark.js in-browser viewer.
Usage: python run_gradio.py
"""
import os
os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")

import time
from pathlib import Path
from uuid import uuid4

import gradio as gr

from triposplat import TripoSplatPipeline, quality_preset_names


# ----------------------------------------------------------------------------
# Pipeline (loaded once at startup)
# ----------------------------------------------------------------------------

PIPE = TripoSplatPipeline(
    ckpt_path              = "ckpts/diffusion_models/triposplat_fp16.safetensors",
    decoder_path           = "ckpts/vae/triposplat_vae_decoder_fp16.safetensors",
    dinov3_path            = "ckpts/clip_vision/dino_v3_vit_h.safetensors",
    flux2_vae_encoder_path = "ckpts/vae/flux2-vae.safetensors",
    rmbg_path              = "ckpts/background_removal/birefnet.safetensors",
    device                 = "auto",
)

OUT_ROOT     = Path("gradio_outputs").resolve()
OUT_ROOT.mkdir(parents=True, exist_ok=True)
VIEWER_HTML  = Path("static/viewer/viewer.html").resolve()
EXAMPLES_DIR = Path("static/example_inputs").resolve()
EXAMPLES = [
    str(EXAMPLES_DIR / "creature_butterfly.webp"),
    str(EXAMPLES_DIR / "building_stone_house.webp"),
    str(EXAMPLES_DIR / "vehicle_pirate_ship.webp"),
    str(EXAMPLES_DIR / "plant_water_lily.webp"),
]

PLACEHOLDER_HTML = (
    "<div style='display:flex;align-items:center;justify-content:center;height:520px;"
    "color:#94a3b8;font:16px system-ui;background:#111318;border-radius:12px'>"
    "3D viewer will appear here after generation</div>"
)


def _gr_file(path: Path) -> str:
    """Gradio serves any file under `allowed_paths` at `/gradio_api/file=<abspath>`."""
    return f"/gradio_api/file={path.as_posix()}"


def _viewer_iframe(ply_path: Path) -> str:
    ts = time.time()  # cache-bust so the iframe reloads each generation
    src = f"{_gr_file(VIEWER_HTML)}?ply={_gr_file(ply_path)}&ts={ts}"
    return (
        f"<iframe src='{src}' "
        "style='width:100%;height:520px;border:0;border-radius:12px;background:#0a0b0e'></iframe>"
    )


# ----------------------------------------------------------------------------
# Event handlers
# ----------------------------------------------------------------------------

QUALITY_CHOICES = ["custom"] + quality_preset_names()


def _collect_views(image, extra_files):
    """Build the ordered list of input views from the single image + extra uploads."""
    views = []
    if image is not None:
        views.append(image)
    for f in extra_files or []:
        # gr.File(type="filepath") yields paths (or objects exposing `.name`).
        views.append(getattr(f, "name", f))
    return views


def generate(image, extra_files, seed: int, quality: str, steps: int,
             guidance_scale: float, num_gaussians: int, output_format: str,
             multiview_experimental: bool = False,
             progress=gr.Progress(track_tqdm=True)):
    """Run the full pipeline (preprocess + encode + sample + decode).

    TripoSplat is a single-image model. By default only the main image is used;
    tick ``multiview_experimental`` to fuse the extra views (out-of-distribution
    for this model — often degrades quality). When `quality` is ``"custom"`` the
    manual sliders drive the run; otherwise the chosen preset fills in steps +
    gaussian count.
    """
    views = _collect_views(image, extra_files)
    if not views:
        raise gr.Error("Please upload at least one image first.")

    if quality == "custom":
        run_kwargs = dict(steps=int(steps), guidance_scale=float(guidance_scale),
                          num_gaussians=int(num_gaussians))
    else:
        run_kwargs = dict(quality=quality)

    progress(0, desc="Generating...")
    t0 = time.time()
    payload = views if len(views) > 1 else views[0]
    try:
        gaussian, prepared = PIPE.run(payload, seed=int(seed), show_progress=True,
                                      multiview=bool(multiview_experimental), **run_kwargs)
    except RuntimeError as e:
        raise gr.Error(str(e))
    gen_dt = time.time() - t0

    prepared_list = prepared if isinstance(prepared, list) else [prepared]

    out_dir = OUT_ROOT / uuid4().hex[:12]
    out_dir.mkdir(parents=True, exist_ok=True)
    ply_path = out_dir / "splat.ply"
    gaussian.save_ply(str(ply_path))

    fmt = output_format.lower()
    if fmt == "ply":
        download_path = ply_path
    elif fmt == "splat":
        download_path = out_dir / "splat.splat"
        gaussian.save_splat(str(download_path))
    else:
        raise gr.Error(f"Unknown output format: {output_format}")

    if len(views) > 1 and multiview_experimental:
        views_note = f"{len(views)} views fused (experimental)  ·  "
    elif len(views) > 1:
        views_note = f"1 of {len(views)} views used (multi-view off)  ·  "
    else:
        views_note = ""
    info = (f"{views_note}{gaussian.get_xyz.shape[0]:,} gaussians  ·  "
            f"generation: {gen_dt:.1f}s  ·  saved: {download_path.name}")
    return (prepared_list, _viewer_iframe(ply_path),
            gr.update(value=str(download_path), interactive=True), info)


# ----------------------------------------------------------------------------
# Gradio UI
# ----------------------------------------------------------------------------

with gr.Blocks(title="TripoSplat") as demo:
    gr.Markdown("# TripoSplat")
    gr.Markdown(
        "TripoSplat converts a single 2D image into high-quality and variable number of 3D Gaussians developed by [TripoAI](https://www.tripo3d.ai/). "
        "It can serve as a powerful pipeline tool for asset creation, AR/VR, game development, simulation environments, and beyond.\n\n"
        "[Read Paper](https://arxiv.org/abs/2605.16355) | [Research Blog](https://www.tripo3d.ai/research/triposplat)"
    )

    with gr.Row():
        with gr.Column(scale=1):
            image_in = gr.Image(label="Input image", type="pil", image_mode="RGBA",
                                height=320)
            extra_files_in = gr.File(
                label="Extra views (single-image model — used only if you tick fusion below)",
                file_count="multiple", file_types=["image"], type="filepath",
            )
            multiview_in = gr.Checkbox(
                label="⚠️ Experimental: fuse extra views",
                value=False,
                info="TripoSplat is single-image; fusing several unposed views is "
                     "out-of-distribution and usually degrades quality. Prefer one clean main view.",
            )

            gr.Examples(
                examples=[[p] for p in EXAMPLES],
                inputs=[image_in],
                label="Examples (click to load)",
                examples_per_page=10,
                cache_examples=False,
            )

            quality_in = gr.Dropdown(
                label="Quality preset",
                choices=QUALITY_CHOICES,
                value="high",
                info="Presets set steps + gaussian count. Pick 'custom' to use the sliders below.",
            )

            with gr.Accordion("Sampling settings (used when quality = custom)", open=False):
                seed_in = gr.Number(label="Seed", value=42, precision=0)
                steps_in = gr.Slider(label="Inference steps", minimum=1, maximum=50, step=1, value=20)
                cfg_in = gr.Slider(label="Guidance scale", minimum=1.0, maximum=10.0, step=0.5, value=3.0)
                num_g_in = gr.Dropdown(
                    label="Number of gaussians",
                    choices=["32768", "65536", "131072", "262144"],
                    value="262144",
                )
                fmt_in = gr.Dropdown(label="Download format", choices=["ply", "splat"], value="ply")

            run_btn = gr.Button("Generate", variant="primary")
            prepared_out = gr.Gallery(label="Preprocessed input(s)", interactive=False,
                                      height=240, columns=4)
            info_out = gr.Markdown()

        with gr.Column(scale=2):
            viewer_out = gr.HTML(value=PLACEHOLDER_HTML, label="Spark.js viewer")
            file_out = gr.DownloadButton(label="Download", value=None, interactive=False)

    run_btn.click(
        fn=generate,
        inputs=[image_in, extra_files_in, seed_in, quality_in, steps_in, cfg_in, num_g_in, fmt_in, multiview_in],
        outputs=[prepared_out, viewer_out, file_out, info_out],
    )


if __name__ == "__main__":
    demo.launch(
        server_name="0.0.0.0",
        server_port=7860,
        allowed_paths=[
            str(VIEWER_HTML.parent),
            str(OUT_ROOT),
            str(EXAMPLES_DIR),
        ],
    )
