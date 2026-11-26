#!/usr/bin/env python3
"""Compare Swag audio decoding and PCM16 materialization with native FFmpeg."""

import argparse
from array import array
import hashlib
from itertools import permutations
import json
import math
import os
from pathlib import Path
import platform
import shlex
from statistics import median
import subprocess
import sys

WORKLOAD = Path(__file__).resolve().parent
REPO = WORKLOAD.parents[2]
SAMPLES_PER_ROUND = 7


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--library-bin", type=Path, default=REPO / "bin")
    parser.add_argument("--baseline-bin", type=Path)
    parser.add_argument("--reference", type=Path, help="prebuilt ffmpeg_native executable")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--rounds", type=int, default=6)
    parser.add_argument("--threads", type=int, default=1)
    parser.add_argument("--max-pcm-delta", type=int, help="limit the PCM16 delta from --baseline-bin")
    parser.add_argument("input", type=Path, nargs="+")
    args = parser.parse_args()
    if args.rounds < 1 or not 1 <= args.threads <= 256:
        parser.error("--rounds must be positive and --threads must be between 1 and 256")
    if args.max_pcm_delta is not None and (args.max_pcm_delta < 0 or not args.baseline_bin):
        parser.error("--max-pcm-delta needs a nonnegative limit and --baseline-bin")
    args.output = args.output.resolve()
    roots = [REPO, args.library_bin.resolve()]
    if args.baseline_bin:
        roots.append(args.baseline_bin.resolve())
    if any(args.output.is_relative_to(root) for root in roots):
        parser.error("--output must be outside the source trees")
    if sys.byteorder != "little":
        parser.error("This workload expects native little-endian PCM16")
    return args


def build_swag(args, name, library):
    build = args.output / name
    build.mkdir()
    temp = build / "tmp"
    temp.mkdir()
    command = [args.compiler.resolve(), "build", "-d", WORKLOAD / "src",
               "--module-file", WORKLOAD / "module.swg", "-bc", "release", "-j", "1",
               "--out-dir", build / "bin", "--work-dir", build / "work"]
    env = {**os.environ, "SWAG_PATH": str(library.resolve()),
           "SWAG_RUNTIME_THREADS": "1", "TMPDIR": str(temp)}
    log = build / "build.log"
    with log.open("w") as capture:
        process = subprocess.run(command, cwd=build, env=env, stdout=capture, stderr=subprocess.STDOUT)
    if process.returncode:
        raise RuntimeError(f"{name} build failed. See {log}")
    return build / "bin" / "audiodecode"


def build_reference(output):
    options = subprocess.check_output([
        "pkg-config", "--cflags", "--libs", "libavformat", "libavcodec", "libavutil", "libswresample",
    ], text=True)
    executable = output / "ffmpeg_native"
    subprocess.run(["cc", "-O2", WORKLOAD / "ffmpeg_native.c", "-o", executable,
                    *shlex.split(options)], check=True)
    return executable


def pcm_delta(candidate, baseline):
    if candidate == baseline:
        return {"changed_samples": 0, "max_abs_diff": 0, "rms_diff": 0.0}
    new = array("h", candidate)
    old = array("h", baseline)
    changed = peak = squares = 0
    for new_sample, old_sample in zip(new, old, strict=True):
        delta = abs(new_sample - old_sample)
        changed += bool(delta)
        peak = max(peak, delta)
        squares += delta * delta
    return {"changed_samples": changed, "max_abs_diff": peak,
            "rms_diff": math.sqrt(squares / len(new))}


def benchmark(args, path, index, binaries):
    fixture_output = args.output / f"{index:03d}-{path.name}"
    fixture_output.mkdir()
    gathered = {engine: [] for engine in binaries}
    orders = list(permutations(binaries))
    env = {**os.environ, "SWAG_RUNTIME_THREADS": str(args.threads)}
    for round_index in range(args.rounds):
        for engine in orders[round_index % len(orders)]:
            command = [binaries[engine], path]
            if engine == "ffmpeg":
                command.append(str(args.threads))
            if round_index == 0:
                command.append(fixture_output / f"{engine}.pcm16")
            process = subprocess.run(command, env=env, capture_output=True, text=True)
            log = fixture_output / f"{engine}-{round_index + 1}.log"
            log.write_text(process.stdout + process.stderr)
            if process.returncode:
                raise RuntimeError(f"{engine} failed on {path}. See {log}")
            rows = [list(map(int, line.split())) for line in process.stdout.splitlines()]
            width = 6 if engine == "ffmpeg" else 7
            if len(rows) != SAMPLES_PER_ROUND or any(len(row) != width for row in rows):
                raise ValueError(f"Unexpected {engine} timing format on {path}. See {log}")
            gathered[engine].extend(rows)

    with path.open("rb") as fixture:
        digest = hashlib.file_digest(fixture, "sha256").hexdigest()
    result = {"fixture": path.name, "size_bytes": path.stat().st_size,
              "sha256": digest, "engines": {}}
    pcm = {}
    dimensions = set()
    for engine, rows in gathered.items():
        first = rows[0]
        if any(row[3:] != first[3:] or row[0] + row[1] != row[2] for row in rows):
            raise ValueError(f"Inconsistent {engine} samples on {path}")
        dimensions.add(tuple(first[3:6]))
        frames, channels, rate = first[3:6]
        pcm[engine] = (fixture_output / f"{engine}.pcm16").read_bytes()
        if len(pcm[engine]) != frames * channels * 2:
            raise ValueError(f"Incorrect {engine} PCM size on {path}")
        samples = [row[:3] for row in rows]
        data = {"frames": frames, "channels": channels, "sample_rate": rate,
                "pcm_sha256": hashlib.sha256(pcm[engine]).hexdigest(),
                "median_us": list(map(median, zip(*samples))), "samples_us": samples}
        if engine != "ffmpeg":
            data["pcm_crc64"] = first[6]
        result["engines"][engine] = data
    if len(dimensions) != 1:
        raise ValueError(f"Engine output dimensions differ on {path}: {sorted(dimensions)}")
    if "baseline" in pcm:
        result["pcm_vs_baseline"] = pcm_delta(pcm["candidate"], pcm["baseline"])
        peak = result["pcm_vs_baseline"]["max_abs_diff"]
        if args.max_pcm_delta is not None and peak > args.max_pcm_delta:
            raise ValueError(f"PCM16 difference {peak} exceeds {args.max_pcm_delta} on {path}")
    return result


def main():
    args = arguments()
    args.output.mkdir(parents=True, exist_ok=False)
    binaries = {}
    if args.baseline_bin:
        binaries["baseline"] = build_swag(args, "baseline", args.baseline_bin)
    binaries["candidate"] = build_swag(args, "candidate", args.library_bin)
    binaries["ffmpeg"] = args.reference.resolve() if args.reference else build_reference(args.output)
    version = subprocess.check_output([binaries["ffmpeg"], "--version"], text=True).strip()
    results = {
        "protocol": {
            "units": "microseconds", "sample_fields": ["open", "decode", "total"],
            "rounds": args.rounds, "samples_per_round": SAMPLES_PER_ROUND, "seconds": 10,
            "threads": args.threads, "affinity": sorted(os.sched_getaffinity(0)),
            "system": platform.platform(), "ffmpeg": version,
        },
        "fixtures": [],
    }
    for index, path in enumerate(args.input, 1):
        result = benchmark(args, path.resolve(), index, binaries)
        results["fixtures"].append(result)
        times = " ".join(f"{name} {data['median_us'][2] / 1000:.3f} ms"
                         for name, data in result["engines"].items())
        print(f"{path.name}  {times}", flush=True)
        (args.output / "results.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
