"""Download the multi-view product photos used by the multi-image example.

The example object is the **green adidas Tokyo women's sneaker** sold by El Corte
Inglés / Sneaker Room. Its catalogue photos show the shoe from several angles,
which makes it a perfect multi-view input for TripoSplat:

    https://www.elcorteingles.es/sneaker-room/A54441838-verde-pr-adidas-tokyo-para-mujer/

These photos are © adidas / El Corte Inglés. They are **not** redistributed with
this repository — this script downloads them on demand, straight from the
retailer's CDN, into a git-ignored folder so you can try the multi-view pipeline.
Use them for local testing only and respect the original copyright.

Usage:
    python download_example_images.py            # whole-shoe views (recommended)
    python download_example_images.py --all      # every catalogue photo
    python download_example_images.py --out DIR  # custom destination
"""
import argparse
import sys
from pathlib import Path
from urllib.request import Request, urlopen

PRODUCT_URL = (
    "https://www.elcorteingles.es/sneaker-room/"
    "A54441838-verde-pr-adidas-tokyo-para-mujer/"
)
ATTRIBUTION = "adidas Tokyo (green) — © adidas / El Corte Inglés. For local testing only."

# Catalogue images live on the El Corte Inglés DAM CDN as `...-NN.jpg` (NN 00-07).
_CDN = "https://dam.elcorteingles.es/producto/www-001017731151217-{:02d}.jpg"
ALL_VIEWS = list(range(8))
# Curated whole-shoe angles (lateral / 3-4 front / opposite side / 3-4 rear).
# The rest are a top-down, a sole shot and macro detail crops — handy to see but
# weaker as fusion views, so they're opt-in via --all.
WHOLE_SHOE_VIEWS = [0, 1, 3, 4]

DEFAULT_OUT = Path("static/example_inputs/multiview/adidas_tokyo_sneaker")

_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    ),
    "Accept": "image/avif,image/webp,image/png,image/*,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9,es;q=0.8",
}


def _download(idx: int, out_dir: Path) -> Path:
    url = _CDN.format(idx)
    dst = out_dir / f"adidas_tokyo_{idx:02d}.jpg"
    req = Request(url, headers=_HEADERS)
    with urlopen(req, timeout=60) as resp:
        data = resp.read()
    dst.write_bytes(data)
    return dst


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--all", action="store_true",
                        help="download every catalogue photo, not just whole-shoe views")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT,
                        help=f"destination folder (default: {DEFAULT_OUT})")
    args = parser.parse_args(argv)

    views = ALL_VIEWS if args.all else WHOLE_SHOE_VIEWS
    out_dir = args.out
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Source : {PRODUCT_URL}")
    print(f"License: {ATTRIBUTION}")
    print(f"Output : {out_dir}")
    print(f"Views  : {views}\n")

    saved = []
    for idx in views:
        try:
            dst = _download(idx, out_dir)
        except Exception as exc:  # noqa: BLE001 - report and keep going
            print(f"  ✗ view {idx:02d}: {exc}")
            continue
        print(f"  ✓ {dst.name}  ({dst.stat().st_size // 1024} KB)")
        saved.append(dst)

    # Drop an attribution note next to the images so their origin is never lost.
    if saved:
        (out_dir / "ATTRIBUTION.txt").write_text(
            f"{ATTRIBUTION}\nSource: {PRODUCT_URL}\n", encoding="utf-8"
        )

    if not saved:
        print("\nNo images downloaded. The retailer may be rate-limiting; retry later.")
        return 1
    print(f"\nDone — {len(saved)} image(s) in {out_dir}")
    print("Pass them as a list to pipe.run([...]) for a multi-view, max-quality run.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
