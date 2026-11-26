"""Compare Swag's CPU SVG parse and raster stages with resvg."""

import argparse
import hashlib
import os
from pathlib import Path
import random
import re
import shutil
import statistics
import subprocess
import tempfile


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
FILESAMPLES = (
    ("640×426", 640, 426, "6c080cb0dcdb660db9e2865e0d3349f3263183e58c9345cc6122a4130ea3c8a5"),
    ("1280×853", 1280, 853, "00d622cf6ab0ef73e48d203d90adeab659776b6d3b1958dc71042a836694fa6a"),
    ("1920×1280", 1920, 1280, "d6012d46eab66404f9c2c450942dc8874ba6fe057774a38ba19b9fa570062a2d"),
    ("5184×3456", 2048, 1365, "bf29681a8b952f06b8d5a61a4ac5a18e0194e9f6a207e57ab6ab9b32f4e64801"),
)


def fixtures(scratch, filesamples):
    if filesamples:
        for size, width, height, digest in FILESAMPLES:
            path = filesamples / f"sample_{size}.svg"
            if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                raise ValueError(f"{path} differs from the original benchmark fixture")
            yield path, width, height
        return

    randomizer = random.Random(57)
    for name, count in (("small", 20), ("curves", 500), ("strokes", 800),
                        ("clipped", 320), ("dense", 16_000), ("large", 16_000)):
        width, height = (2048, 1365) if name == "large" else (1280, 853)
        path = scratch / f"{name}.svg"
        with path.open("w", encoding="ascii", newline="\n") as svg:
            svg.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}">\n')
            if name == "dense":
                svg.write('<path fill="#4068a9" fill-rule="evenodd" d="\n')
                for _ in range(count):
                    x = randomizer.randrange(width - 15)
                    y = randomizer.randrange(height - 15)
                    svg.write(f"M{x} {y}l3 1 4 4 -2 5 -6 -2Z\n")
                svg.write('"/>\n')
            else:
                for i in range(count):
                    x, y = randomizer.randrange(width), randomizer.randrange(height)
                    low, high = (100, 400) if name == "strokes" else (6, 96)
                    dx, dy = randomizer.randrange(low, high), randomizer.randrange(low, high)
                    color = f"#{randomizer.randrange(0x1000000):06x}"
                    if name == "clipped":
                        svg.write(f'<defs><clipPath id="c{i}"><circle cx="{x + 8}" cy="{y + 10}" r="18"/>'
                                  f'</clipPath></defs><g clip-path="url(#c{i})">\n')
                    curve = f"M{x} {y}c{dx} 0 0 {dy} {dx} {dy}"
                    if name == "strokes":
                        svg.write(f'<path fill="none" stroke="{color}" stroke-opacity=".86" d="{curve}"/>\n')
                    else:
                        tail = f"l-{dx // 2} -{dy // 2} -{dx // 2} {dy // 3}Z"
                        svg.write(f'<path fill="{color}" fill-opacity=".84" d="{curve}{tail}"/>\n')
                    if name == "clipped":
                        svg.write("</g>\n")
            svg.write("</svg>\n")
        yield path, width, height

    width, height = 2048, 1365
    path = scratch / "sparse-curves.svg"
    sparse_random = random.Random(59)
    with path.open("w", encoding="ascii", newline="\n") as svg:
        svg.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}">\n')
        svg.write('<path fill="#4068a9" d="\n')
        for row in range(192):
            x = sparse_random.randrange(24, width - 48)
            y = 8 + row * 7
            svg.write(f"M{x} {y}c4 -1 15 -1 18 0l-1 2 -15 0Z\n")
        svg.write('"/></svg>\n')
    yield path, width, height

    path = scratch / "thin-edges.svg"
    with path.open("w", encoding="ascii", newline="\n") as svg:
        svg.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}">\n')
        svg.write('<path fill="#4068a9" d="\n')
        for row in range(32):
            y = 16 + row * 39
            for column in range(48):
                x = 28 + ((column * 17) % 48) * 41
                svg.write(f"M{x}.125 {y}.0625h2l.75 .1875h-2Z\n")
        svg.write('"/></svg>\n')
    yield path, width, height

    width, height = 1280, 853
    for name, stroke_width in (("hairline-strokes", "0.5"), ("wide-strokes", "4")):
        stroke_random = random.Random(61)
        path = scratch / f"{name}.svg"
        with path.open("w", encoding="ascii", newline="\n") as svg:
            svg.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}">\n')
            svg.write(f'<g fill="none" stroke-width="{stroke_width}" stroke-opacity=".86">\n')
            for _ in range(384):
                x, y = stroke_random.randrange(width), stroke_random.randrange(height)
                dx, dy = stroke_random.randrange(-300, 301), stroke_random.randrange(-300, 301)
                color = f"#{stroke_random.randrange(0x1000000):06x}"
                svg.write(f'<path stroke="{color}" d="M{x} {y}c{dx} 0 0 {dy} {dx} {dy}"/>\n')
            svg.write('</g></svg>\n')
        yield path, width, height


def build(compiler, bin_root, build_root, *, scope=False):
    build_root.mkdir()
    executable = build_root / compiler.name
    shutil.copy2(compiler, executable)
    shutil.copytree(compiler.parent / "runtime", build_root / "runtime")
    shutil.copytree(bin_root / "std", build_root / "std", ignore=shutil.ignore_patterns(".output", ".tmp"))
    output = build_root / "out"
    environment = dict(os.environ, SWAG_PATH=str(build_root), TMPDIR=str(build_root))
    command = [executable, "build", "-d", HERE / "src", "--module-file", HERE / "module.swg",
               "-bc", "release", "--out-dir", output, "--work-dir", build_root / "work"]
    if scope:
        command += ["--tag", "Benchmark.SvgScope"]
    subprocess.run(command, cwd=build_root, env=environment, check=True)
    return output / ("svgraster.exe" if os.name == "nt" else "svgraster")


def measure_swag(command, fixture, width, height, workers, scratch):
    output = subprocess.check_output([command, fixture, str(width), str(height), str(workers)],
                                     cwd=scratch, env=dict(os.environ, SWAG_RUNTIME_THREADS=str(workers)),
                                     text=True)
    parse, raster, total, checksum = map(int, output.split())
    return parse / 1000, raster / 1000, total / 1000, checksum


def measure_resvg(command, fixture, width, height, scratch):
    run = subprocess.run([command, "--skip-system-fonts", "--perf", "-w", str(width),
                          "-h", str(height), fixture, scratch / "resvg.png"],
                         cwd=scratch, text=True, capture_output=True, check=True)
    phases = dict(re.findall(r"^(XML Parsing|SVG Parsing|Rendering):\s+([0-9.]+)ms$",
                             run.stdout + "\n" + run.stderr, re.MULTILINE))
    parse = float(phases["XML Parsing"]) + float(phases["SVG Parsing"])
    raster = float(phases["Rendering"])
    return parse, raster, parse + raster


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swc", type=Path, required=True)
    parser.add_argument("--resvg", type=Path, required=True)
    parser.add_argument("--against-bin", type=Path, help="baseline bin/ directory with matching std sources")
    parser.add_argument("--report-raster-differences", action="store_true",
                        help="report both checksums when comparing different antialiasing implementations")
    parser.add_argument("--filesamples", type=Path, help="directory containing the four original SVGs")
    parser.add_argument("--reps", type=int, default=7)
    parser.add_argument("--workers", type=int, default=1)
    parser.add_argument("--scope", action="store_true", help="use Swag Scope's SVG bitmap parse options")
    args = parser.parse_args()
    if args.reps < 1 or args.workers < 1:
        parser.error("--reps and --workers must be positive")
    if args.report_raster_differences and not args.against_bin:
        parser.error("--report-raster-differences requires --against-bin")

    compiler, resvg = args.swc.resolve(), args.resvg.resolve()
    print(subprocess.check_output([resvg, "--version"], text=True).strip(), flush=True)
    with tempfile.TemporaryDirectory(prefix="swc-svgraster-") as directory:
        scratch = Path(directory)
        programs = {}
        if args.against_bin:
            programs["baseline"] = build(compiler, args.against_bin.resolve(), scratch / "baseline", scope=args.scope)
        programs["swag"] = build(compiler, ROOT / "bin", scratch / "swag", scope=args.scope)

        mode = "Scope bitmap" if args.scope else "default SVG"
        print(f"Release, {mode}, {args.workers} Swag workers, {args.reps} repetitions", flush=True)
        print("fixture                engine    parse ms   raster ms    total ms     vs resvg", flush=True)
        for fixture, width, height in fixtures(scratch, args.filesamples):
            samples = {engine: [] for engine in (*programs, "resvg")}
            for i in range(args.reps):
                order = list(programs.items())
                if i % 2:
                    order.reverse()
                for engine, program in order:
                    samples[engine].append(measure_swag(program, fixture, width, height, args.workers, scratch))
                samples["resvg"].append(measure_resvg(resvg, fixture, width, height, scratch))

            checksums = {}
            for engine in programs:
                observed = {sample[3] for sample in samples[engine]}
                if len(observed) != 1:
                    raise ValueError(f"{engine} output differs between runs for {fixture.name}")
                checksums[engine] = observed.pop()
            if len(set(checksums.values())) > 1:
                if not args.report_raster_differences:
                    raise ValueError(f"Swag output differs from the baseline for {fixture.name}")
                print(f"{fixture.stem:<22} CRC-64 baseline={checksums['baseline']:016x} "
                      f"swag={checksums['swag']:016x}", flush=True)
            competitor = statistics.median(sample[2] for sample in samples["resvg"])
            for engine, runs in samples.items():
                parse, raster, total = (statistics.median(values) for values in list(zip(*runs))[:3])
                print(f"{fixture.stem:<22} {engine:<8} {parse:>8.3f} {raster:>11.3f} {total:>11.3f}"
                      f" {total / competitor:>10.2f}x", flush=True)


if __name__ == "__main__":
    main()
