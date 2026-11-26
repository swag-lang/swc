"""Compare planar H.264 and HEVC pictures and serial decode time with FFmpeg."""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shlex
import statistics
import subprocess
from fractions import Fraction

import numpy as np


WORKLOAD = Path(__file__).resolve().parent
REPO = WORKLOAD.parents[2]
WARMUP = 30
SWAG_TIMING = re.compile(r"^video frames=(\d+) ticks=(\d+) frequency=(\d+)$", re.M)
FFMPEG_TIMING = re.compile(r"^video frames=(\d+) wall=(\d+\.\d+) cpu=(\d+\.\d+)$", re.M)


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--library-bin", type=Path, default=REPO / "bin")
    parser.add_argument("--baseline-bin", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repetitions", type=int, default=5)
    parser.add_argument("--quality-only", action="store_true")
    parser.add_argument("--reference", type=Path, help="prebuilt ffmpeg_native executable")
    parser.add_argument("input", type=Path, nargs="+")
    args = parser.parse_args()
    if args.repetitions < 1:
        parser.error("--repetitions must be positive")
    args.output = args.output.resolve()
    roots = [REPO, args.library_bin.resolve()]
    if args.baseline_bin:
        roots.append(args.baseline_bin.resolve())
    if any(root in args.output.parents or root == args.output for root in roots):
        parser.error("--output must be outside the source trees")
    return args


def build_reference(output):
    options = subprocess.check_output(
        ["pkg-config", "--cflags", "--libs", "libavformat", "libavcodec", "libavutil"], text=True
    )
    executable = output / "ffmpeg_native"
    subprocess.run(["cc", "-O2", WORKLOAD / "ffmpeg_native.c", "-o", executable,
                    *shlex.split(options)], check=True)
    return executable


def run(command, log, *, env=None):
    with log.open("w") as capture:
        subprocess.run(command, cwd=log.parent, env=env, stdout=capture,
                       stderr=subprocess.STDOUT, check=True)
    return log.read_text()


def swag(args, name, library, log, *values):
    output = args.output / name
    command = [args.compiler.resolve(), "run", "-f", WORKLOAD / "src/videodecode.swg",
               "--module-file", WORKLOAD / "module.swg", "-bc", "release", "--num-cores", "4",
               "--out-dir", output / "bin", "--work-dir", output / "work"]
    for value in values:
        command += ["--run-arg", str(value)]
    return run(command, log, env={**os.environ, "SWAG_PATH": str(library.resolve()),
                                  "SWAG_RUNTIME_THREADS": "1"})


def fixture_timeline(path):
    probe = subprocess.check_output([
        "ffprobe", "-v", "error", "-threads", "1", "-select_streams", "v:0", "-show_streams",
        "-show_frames", "-show_packets", "-show_entries",
        "stream=codec_name,width,height,pix_fmt,time_base:stream_disposition=:stream_tags=:"
        "frame=best_effort_timestamp:packet=pts",
        "-of", "json", path,
    ])
    metadata = json.loads(probe)
    stream, = metadata["streams"]
    pixel_format = stream["pix_fmt"]
    if stream["codec_name"] not in ("h264", "hevc") or pixel_format not in (
        "yuv420p", "yuv444p", "yuv420p10le"
    ):
        raise ValueError(f"{path} has an unsupported codec or planar layout")
    scale = Fraction(stream["time_base"])
    records = metadata["packets_and_frames"]
    # Reader's clock starts at the earliest sample, which may precede FFmpeg's first picture.
    origin = min(record["pts"] for record in records if record["type"] == "packet" and "pts" in record)
    times = [(record["best_effort_timestamp"] - origin) * scale
             for record in records if record["type"] == "frame"]
    if not times or any(a >= b for a, b in zip(times, times[1:])):
        raise ValueError(f"{path} needs unique increasing presentation timestamps")
    return stream, times


def compare_planes(path, stream, frames, planes):
    width, height, fmt = (stream[key] for key in ("width", "height", "pix_fmt"))
    luma = width * height
    chroma = luma if fmt == "yuv444p" else ((width + 1) // 2) * ((height + 1) // 2)
    samples = luma + 2 * chroma
    main10 = fmt == "yuv420p10le"
    native_bytes = samples * (2 if main10 else 1)
    digest = hashlib.sha256()
    differing_frames = different = greatest = squares = 0

    command = ["ffmpeg", "-nostdin", "-v", "error", "-xerror", "-threads", "1",
               "-i", path, "-map", "0:v:0", "-an", "-sn", "-dn", "-fps_mode", "passthrough",
               "-c:v", "rawvideo", "-threads", "1", "-f", "rawvideo", "-pix_fmt", fmt, "pipe:1"]
    with subprocess.Popen(command, stdout=subprocess.PIPE) as ffmpeg, planes.open("rb") as decoded:
        for index in range(frames):
            reference = ffmpeg.stdout.read(native_bytes)
            actual = decoded.read(samples)
            if len(reference) != native_bytes or len(actual) != samples:
                raise ValueError(f"{path} has incomplete planes at reference frame {index}")
            if main10:
                # Reader publishes 8-bit planes with rounding and saturation.
                values = np.frombuffer(reference, dtype="<u2")
                reference = np.minimum((values + 2) >> 2, 255).astype(np.uint8).tobytes()
            digest.update(actual)
            if actual != reference:
                differing_frames += 1
                delta = (np.frombuffer(actual, dtype=np.uint8).astype(np.int32)
                         - np.frombuffer(reference, dtype=np.uint8))
                different += int(np.count_nonzero(delta))
                greatest = max(greatest, int(np.abs(delta).max()))
                squares += int(np.sum(delta * delta, dtype=np.int64))
        if ffmpeg.stdout.read(1) or decoded.read(1):
            raise ValueError(f"{path} has more decoded pictures than reference timestamps")
        if ffmpeg.wait():
            raise RuntimeError(f"FFmpeg failed while decoding {path}")

    return {"sha256": digest.hexdigest(), "different_samples": different,
            "different_frames": differing_frames, "max_difference": greatest,
            "psnr_db": 10 * math.log10(255**2 * samples * frames / squares) if squares else "inf"}


def benchmark_fixture(args, reference, path, prefix):
    stream, times = fixture_timeline(path)
    timeline = prefix.with_suffix(".pts")
    timeline.write_text("".join(f"{float(time):.12f}\n" for time in times))
    libraries = {"candidate": args.library_bin}
    if args.baseline_bin:
        libraries["baseline"] = args.baseline_bin

    quality = {}
    for name, library in libraries.items():
        planes = prefix.with_suffix(f".{name}.yuv")
        swag(args, name, library, prefix.with_suffix(f".{name}.planes.log"),
             "planes", path, timeline, planes)
        quality[name] = compare_planes(path, stream, len(times), planes)
        planes.unlink()

    with path.open("rb") as file:
        digest = hashlib.file_digest(file, "sha256").hexdigest()
    result = {"path": str(path), "fixture_sha256": digest,
              "stream": stream, "frames": len(times), "quality": quality}
    if args.quality_only:
        return result

    frames = len(times) - WARMUP
    if frames <= 0:
        raise ValueError(f"{path} needs more than {WARMUP} frames for timing")
    timing = {name: [] for name in (*libraries, "ffmpeg", "ffmpeg_no_simd")}
    native_cpu = {"ffmpeg": [], "ffmpeg_no_simd": []}
    order = list(timing)
    for repetition in range(args.repetitions):
        for name in order:
            log = prefix.with_suffix(f".{name}.{repetition + 1}.log")
            if name in libraries:
                text = swag(args, name, libraries[name], log, "time", path, 1)
                count, ticks, frequency = map(int, SWAG_TIMING.findall(text)[0])
                elapsed = ticks / frequency
            else:
                text = run([reference, path, "1", str(int(name == "ffmpeg_no_simd"))], log)
                count_text, wall, cpu = FFMPEG_TIMING.findall(text)[0]
                count, elapsed = int(count_text), float(wall)
                native_cpu[name].append(float(cpu) * 1000 / frames)
            if count != frames:
                raise ValueError(f"{name} decoded {count} timed pictures from {path}, expected {frames}")
            timing[name].append(elapsed * 1000 / frames)
        order = order[1:] + order[:1]

    result["timed_frames"] = frames
    result["wall_ms_per_frame"] = {name: {"samples": samples, "median": statistics.median(samples)}
                                   for name, samples in timing.items()}
    result["ffmpeg_cpu_ms_per_frame"] = native_cpu
    return result


def main():
    args = arguments()
    args.output.mkdir(parents=True)
    reference = None
    if not args.quality_only:
        reference = args.reference.resolve() if args.reference else build_reference(args.output)
    results = []
    for index, input_path in enumerate(args.input):
        result = benchmark_fixture(args, reference, input_path.resolve(), args.output / f"fixture-{index}")
        results.append(result)
        print(json.dumps(result), flush=True)
    version = subprocess.check_output(["ffmpeg", "-version"], text=True).splitlines()[0]
    (args.output / "report.json").write_text(json.dumps({"ffmpeg": version, "results": results}, indent=2) + "\n")
    return int(any(quality["different_frames"] for result in results for quality in result["quality"].values()))


if __name__ == "__main__":
    raise SystemExit(main())
