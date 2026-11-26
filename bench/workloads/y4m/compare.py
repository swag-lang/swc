"""Compare the Y4M writer and FFmpeg's libswscale on the same RGB pictures."""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess

import numpy as np


WORKLOAD = Path(__file__).resolve().parent
LAYOUTS = {"411": (0, 4, 1), "420": (1, 2, 2), "422": (2, 2, 1), "444": (3, 1, 1)}
TIMING = re.compile(r"^Y4M frames=(\d+) us=(\d+) cpu_us=(\d+) bytes=(\d+)$", re.M)


def run(command, log, env=None):
    with log.open("w") as stream:
        subprocess.run(command, cwd=log.parent, env=env, stdout=stream, stderr=subprocess.STDOUT, check=True)
    return log.read_text()


def build_swag(args, name, library):
    output = args.output / name
    env = {**os.environ, "SWAG_PATH": str(library), "SWAG_RUNTIME_THREADS": "1"}
    exe = output / "bin" / "y4m"
    run([args.compiler.resolve(), "build", "-f", WORKLOAD / "src/y4m.swg", "--module-file", WORKLOAD / "module.swg",
         "-bc", "release", "--num-cores", "1", "--out-dir", exe.parent, "--work-dir", output / "work"],
        args.output / f"{name}.build.log", env)
    shared = (library / "std/.output").glob("*/shared-library/release/x86_64/*.so")
    paths = [str(p.parent) for p in sorted(shared)]
    if env.get("LD_LIBRARY_PATH"):
        paths.append(env["LD_LIBRARY_PATH"])
    env["LD_LIBRARY_PATH"] = ":".join(paths)
    return exe, env


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def compare_planes(candidate, reference, args, step_x, step_y):
    luma = args.width * args.height
    chroma = luma // (step_x * step_y)
    sizes = (luma, chroma, chroma)
    differences = [0, 0, 0]
    maxima = [0, 0, 0]
    squared = [0, 0, 0]
    with candidate.open("rb") as swag, reference.open("rb") as external:
        geometry = f"YUV4MPEG2 W{args.width} H{args.height} F30:1 Ip".encode()
        if any(not stream.readline().startswith(geometry) for stream in (swag, external)):
            raise ValueError("Y4M geometry or cadence differs from the requested input")
        for _ in range(args.frames):
            if any(stream.readline() != b"FRAME\n" for stream in (swag, external)):
                raise ValueError("missing expected Y4M frame marker")
            for index, size in enumerate(sizes):
                a = np.frombuffer(swag.read(size), dtype=np.uint8)
                b = np.frombuffer(external.read(size), dtype=np.uint8)
                if len(a) != size or len(b) != size:
                    raise ValueError("incomplete Y4M picture")
                delta = a.astype(np.int32) - b
                differences[index] += int(np.count_nonzero(delta))
                maxima[index] = max(maxima[index], int(np.abs(delta).max()))
                squared[index] += int(np.sum(delta * delta, dtype=np.int64))
        if swag.read(1) or external.read(1):
            raise ValueError("unexpected trailing data in the output")
    return {plane: dict(max_difference=maxima[i], differing_samples=differences[i],
                        psnr=10 * math.log10(255**2 * sizes[i] * args.frames / squared[i]) if squared[i] else "inf")
            for i, plane in enumerate(("y", "cb", "cr"))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True, help="prebuilt y4m_native")
    parser.add_argument("--library-bin", type=Path, help="candidate bin tree, defaulting to this checkout")
    parser.add_argument("--baseline-bin", type=Path, help="bin tree from an earlier Swag source snapshot")
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--frames", type=int, default=30)
    parser.add_argument("--repetitions", type=int, default=7)
    parser.add_argument("--layout", action="append", choices=LAYOUTS, help="chroma layout to measure, defaulting to all")
    parser.add_argument("--output", type=Path, required=True, help="new evidence directory outside the source trees")
    parser.add_argument("input", type=Path, help="bottom-up, tightly packed RGB8 pictures")
    args = parser.parse_args()
    args.output = args.output.resolve()
    repo = WORKLOAD.parents[2]
    library = (args.library_bin or repo / "bin").resolve()
    roots = [repo, library]
    if args.baseline_bin:
        roots.append(args.baseline_bin.resolve())
    if args.output.exists() or any(root == args.output or root in args.output.parents for root in roots):
        parser.error("--output must be a new directory outside the source trees")
    if not all(v > 0 for v in (args.width, args.height, args.frames, args.repetitions)):
        parser.error("dimensions, picture count and repetitions must be positive")
    source = args.input.resolve()
    if source.stat().st_size != args.width * args.height * args.frames * 3:
        parser.error("input size differs from the dimensions and picture count")
    layouts = args.layout or LAYOUTS
    if any(args.width % LAYOUTS[name][1] or args.height % LAYOUTS[name][2] for name in layouts):
        parser.error("input geometry does not fit the selected chroma layouts")
    args.output.mkdir(parents=True)
    implementations = {"candidate": build_swag(args, "candidate", library)}
    if args.baseline_bin:
        implementations["baseline"] = build_swag(args, "baseline", args.baseline_bin.resolve())
    native = args.native.resolve()
    shape = [str(v) for v in (args.width, args.height, args.frames)]
    results = []
    for layout in layouts:
        number, step_x, step_y = LAYOUTS[layout]
        for channel_order in ("rgb", "bgra"):
            cases = {}
            for name, (exe, env) in implementations.items():
                path = args.output / f"{layout}-{channel_order}-{name}.y4m"
                cases[name] = (path, [exe, source, *shape, str(number), channel_order, path], env)
            if channel_order == "rgb":
                path = args.output / f"{layout}-ffmpeg.y4m"
                cases["ffmpeg"] = (path, [native, source, path, *shape, str(number)], None)
            samples = {name: [] for name in cases}
            hashes = {}
            order = list(cases)
            for repeat in range(args.repetitions):
                for name in order:
                    path, command, env = cases[name]
                    log = run(command, path.with_suffix(f".{repeat}.log"), env)
                    match = TIMING.search(log)
                    if not match or int(match[1]) != args.frames:
                        raise ValueError(f"missing or incomplete timing for {path}")
                    samples[name].append((int(match[2]), int(match[3])))
                    checksum = digest(path)
                    if hashes.setdefault(name, checksum) != checksum:
                        raise ValueError(f"unstable encoded bytes for {path}")
                order = order[1:] + order[:1]
            if "baseline" in hashes and hashes["candidate"] != hashes["baseline"]:
                raise ValueError(f"Swag bitstreams differ at {layout}/{channel_order}")
            matched = (compare_planes(cases["candidate"][0], cases["ffmpeg"][0], args, step_x, step_y)
                       if "ffmpeg" in cases else None)
            times = {}
            for name, runs in samples.items():
                wall, cpu = zip(*runs)
                times[name] = dict(wall_us=wall, cpu_us=cpu, median_wall_us=statistics.median(wall),
                                   median_cpu_us=statistics.median(cpu))
            result = dict(layout=layout, channel_order=channel_order, hashes=hashes, comparison=matched, times=times)
            print(json.dumps(result), flush=True)
            results.append(result)
            for path, _, _ in cases.values():
                path.unlink()
    (args.output / "report.json").write_text(json.dumps(dict(input=source.name, input_sha256=digest(source),
                                                            width=args.width, height=args.height, frames=args.frames,
                                                            results=results), indent=2) + "\n")


if __name__ == "__main__":
    main()
