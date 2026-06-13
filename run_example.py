"""TripoSplat minimal examples.
Usage: python run_example.py
"""
import os
os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")

from pathlib import Path

from triposplat import TripoSplatPipeline


pipe = TripoSplatPipeline(
    ckpt_path              = "ckpts/diffusion_models/triposplat_fp16.safetensors",
    decoder_path           = "ckpts/vae/triposplat_vae_decoder_fp16.safetensors",
    dinov3_path            = "ckpts/clip_vision/dino_v3_vit_h.safetensors",
    flux2_vae_encoder_path = "ckpts/vae/flux2-vae.safetensors",
    rmbg_path              = "ckpts/background_removal/birefnet.safetensors",
    device                 = "auto",
)

INPUT = "static/example_inputs/building_stone_house.webp"


# ---------------------------------------------------------------------------
# Example 1 — one image → PLY + SPLAT
# ---------------------------------------------------------------------------

gaussian, prepared = pipe.run(INPUT, num_gaussians=262144, show_progress=True)

prepared.save("preprocessed_image.webp")
gaussian.save_ply("output.ply")
gaussian.save_splat("output.splat")


# ---------------------------------------------------------------------------
# Example 2 — one image → Gaussians at several densities (denoiser runs once,
# decoder is replayed per count) → one PLY per count
# ---------------------------------------------------------------------------

counts = [32768, 65536, 131072, 262144]
gaussians, _ = pipe.run(INPUT, num_gaussians=counts, show_progress=True)

for n, g in zip(counts, gaussians):
    g.save_ply(f"output_{n}.ply")


# ---------------------------------------------------------------------------
# Example 3 — quality presets ("low" / "medium" / "high", or ES aliases such as
# "baja" / "media" / "alta"). A preset fills in steps + gaussian count in one go.
# ---------------------------------------------------------------------------

gaussian, _ = pipe.run(INPUT, quality="high", show_progress=True)
gaussian.save_ply("output_high.ply")


# ---------------------------------------------------------------------------
# Example 4 — multi-view fusion for maximum quality. Pass several photos of the
# *same* object as a list; the model attends to every view at once for more
# complete geometry. Get the sample sneaker photos with:
#     python download_example_images.py
# (they're copyrighted catalogue images, downloaded locally, never committed).
# ---------------------------------------------------------------------------

SNEAKER_DIR = Path("static/example_inputs/multiview/adidas_tokyo_sneaker")
views = sorted(str(p) for p in SNEAKER_DIR.glob("*.jpg"))

if views:
    print(f"Multi-view: fusing {len(views)} views for maximum quality")
    gaussian, prepared_views = pipe.run(views, quality="high", show_progress=True)
    for i, pv in enumerate(prepared_views):
        pv.save(f"preprocessed_view_{i}.webp")
    gaussian.save_ply("output_multiview.ply")
    gaussian.save_splat("output_multiview.splat")
else:
    print("Multi-view example skipped — run `python download_example_images.py` first.")

