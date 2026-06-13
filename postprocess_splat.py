"""Optional post-processing / export for the splats TripoSplat produces.

This is a thin, dependency-free wrapper around **splat-transform**
(https://github.com/playcanvas/splat-transform, MIT) — an open-source CLI that
converts and edits 3D Gaussian splats. It lets you take the `.ply` TripoSplat
exports and turn it into web/AR-friendly, compressed formats, optionally
decimating or cleaning it first:

    .ply  ->  .sog / meta.json   super-compressed for the web (~4-10x smaller)
          ->  .spz               compact interchange (Niantic)
          ->  .glb               glTF + KHR_gaussian_splatting (AR / engines)
          ->  .compressed.ply    compressed PLY
          ->  .html              standalone SuperSplat web viewer

splat-transform runs on Node. Nothing here is imported by the core pipeline, so
TripoSplat keeps working without Node installed; this module simply shells out
to `splat-transform` (or `npx @playcanvas/splat-transform`) when you ask it to.

Python usage:
    from postprocess_splat import export_splat, splat_transform_available
    if splat_transform_available():
        export_splat("output.ply", "output.sog")                 # web
        export_splat("output.ply", "mobile.ply", decimate="50%") # lighter

CLI usage:
    python postprocess_splat.py output.ply output.sog
    python postprocess_splat.py output.ply mobile.glb --decimate 100000 --clean
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional, Sequence

_PACKAGE = "@playcanvas/splat-transform"


def _resolve_cmd() -> Optional[list]:
    """Return the command prefix used to invoke splat-transform, or ``None``.

    Prefers a directly installed ``splat-transform`` binary; otherwise falls
    back to ``npx -y @playcanvas/splat-transform`` (which fetches the package on
    first use). Returns ``None`` when neither Node's ``npx`` nor the binary is
    available.
    """
    direct = shutil.which("splat-transform")
    if direct:
        return [direct]
    npx = shutil.which("npx")
    if npx:
        return [npx, "-y", _PACKAGE]
    return None


def splat_transform_available() -> bool:
    """True if splat-transform can be invoked (binary on PATH or via ``npx``)."""
    return _resolve_cmd() is not None


def export_splat(
    input_ply,
    output,
    *,
    decimate: Optional[str] = None,
    clean_floaters: bool = False,
    overwrite: bool = True,
    sh_iterations: Optional[int] = None,
    gpu: Optional[str] = None,
    extra_args: Optional[Sequence[str]] = None,
    quiet: bool = False,
    capture: bool = False,
    timeout: Optional[float] = 1800,
) -> Path:
    """Convert/compress a splat with splat-transform.

    Args:
        input_ply: Source splat (any format splat-transform reads, e.g. the
            ``.ply`` TripoSplat writes).
        output: Destination path; the extension selects the format
            (``.sog`` / ``.spz`` / ``.glb`` / ``.compressed.ply`` / ``.html`` …).
        decimate: Optional simplification, e.g. ``"100000"`` (target count) or
            ``"50%"`` (keep a fraction) — reduces Gaussians for mobile/AR.
        clean_floaters: Drop stray Gaussians that don't contribute to any solid
            voxel (splat-transform's ``--filter-floaters``).
        overwrite: Overwrite the output if it already exists.
        sh_iterations: SH-compression iterations for ``.sog`` outputs
            (higher = better quality, slower).
        gpu: GPU selector for GPU-accelerated outputs/filters — an adapter
            index, or ``"cpu"`` to force CPU.
        extra_args: Extra raw CLI flags appended verbatim, for full control.
        quiet: Pass ``--quiet`` to suppress non-error output.
        capture: Capture stdout/stderr instead of inheriting the terminal.
        timeout: Seconds before the call is aborted (the first ``npx`` run may
            need to download the package).

    Returns:
        The output ``Path``.

    Raises:
        RuntimeError: splat-transform is not available.
        FileNotFoundError: the input file does not exist.
        subprocess.CalledProcessError: splat-transform exited non-zero.
    """
    cmd_prefix = _resolve_cmd()
    if cmd_prefix is None:
        raise RuntimeError(
            "splat-transform is not available. Install Node.js (which provides "
            "`npx`), or install the tool globally with "
            "`npm install -g @playcanvas/splat-transform`."
        )

    input_ply = Path(input_ply)
    output = Path(output)
    if not input_ply.exists():
        raise FileNotFoundError(f"input splat not found: {input_ply}")
    output.parent.mkdir(parents=True, exist_ok=True)

    cmd = list(cmd_prefix)
    if overwrite:
        cmd.append("-w")
    if quiet:
        cmd += ["-q", "--no-tty"]
    if gpu is not None:
        cmd += ["-g", str(gpu)]
    if sh_iterations is not None:
        cmd += ["-i", str(sh_iterations)]
    cmd.append(str(input_ply))
    # Per-input actions (applied to the source before it is written out).
    if clean_floaters:
        cmd.append("-G")
    if decimate is not None:
        cmd += ["-F", str(decimate)]
    cmd.append(str(output))
    if extra_args:
        cmd += list(extra_args)

    do_capture = capture or quiet
    result = subprocess.run(
        cmd,
        check=True,
        timeout=timeout,
        text=True,
        capture_output=do_capture,
    )
    if do_capture and not quiet:
        sys.stdout.write(result.stdout or "")
        sys.stderr.write(result.stderr or "")
    return output


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Export/compress a TripoSplat .ply via splat-transform.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("input", help="source splat (e.g. output.ply)")
    parser.add_argument("output", help="destination (.sog/.spz/.glb/.compressed.ply/.html/...)")
    parser.add_argument("--decimate", metavar="N|N%", default=None,
                        help="simplify to N gaussians or keep N%% of them")
    parser.add_argument("--clean", action="store_true",
                        help="remove floater gaussians before export")
    parser.add_argument("--sh-iterations", type=int, default=None,
                        help="SH-compression iterations for .sog outputs")
    parser.add_argument("--gpu", default=None, help="GPU adapter index, or 'cpu'")
    parser.add_argument("-q", "--quiet", action="store_true", help="suppress non-error output")

    args, extra = parser.parse_known_args(argv)

    if not splat_transform_available():
        print(
            "error: splat-transform not found. Install Node.js (for `npx`) or run "
            "`npm install -g @playcanvas/splat-transform`.",
            file=sys.stderr,
        )
        return 2

    try:
        out = export_splat(
            args.input, args.output,
            decimate=args.decimate, clean_floaters=args.clean,
            sh_iterations=args.sh_iterations, gpu=args.gpu,
            quiet=args.quiet, extra_args=extra or None,
        )
    except subprocess.CalledProcessError as exc:
        return exc.returncode or 1
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
