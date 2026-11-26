"""Compare decoded video pictures and processing time with FFmpeg."""

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
    parser.add_argument("--lanes", type=int, default=1, help="decoder thread budget for Swag and FFmpeg")
    parser.add_argument("--repetitions", type=int, default=5)
    parser.add_argument("--warmup", type=int, default=WARMUP,
                        help=f"pictures decoded before the timed window (default {WARMUP})")
    parser.add_argument("--quality-only", action="store_true")
    parser.add_argument("--rgb", action="store_true", help="compare RGB24 output for Y4M, raw AVI and Motion JPEG")
    parser.add_argument("--mpeg4-max-sample-difference", type=int, default=0,
                        help="allow this per-sample difference from FFmpeg for MPEG-4 Part 2")
    parser.add_argument("--reference", type=Path, help="prebuilt ffmpeg_native executable")
    parser.add_argument("--jpeg-reference", type=Path, help="prebuilt libjpeg-turbo decoder for Motion JPEG RGB timings")
    parser.add_argument("input", type=Path, nargs="+")
    args = parser.parse_args()
    if not 0 < args.lanes <= 0x7FFFFFFF:
        parser.error("--lanes must be positive and fit in a signed 32-bit integer")
    if args.repetitions < 1:
        parser.error("--repetitions must be positive")
    if not 0 < args.warmup <= 0xFFFFFFFF:
        parser.error("--warmup must be positive and fit in 32 bits")
    if not 0 <= args.mpeg4_max_sample_difference <= 255:
        parser.error("--mpeg4-max-sample-difference must be in 0 through 255")
    if args.jpeg_reference and not args.rgb:
        parser.error("--jpeg-reference requires --rgb")
    if args.jpeg_reference:
        args.jpeg_reference = args.jpeg_reference.resolve()
    args.output = args.output.resolve()
    roots = [REPO, args.library_bin.resolve()]
    if args.baseline_bin:
        roots.append(args.baseline_bin.resolve())
    if any(root in args.output.parents or root == args.output for root in roots):
        parser.error("--output must be outside the source trees")
    return args


def build_reference(output):
    options = subprocess.check_output(
        ["pkg-config", "--cflags", "--libs", "libavformat", "libavcodec", "libavutil", "libswscale"], text=True
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


def build_swag(args, name, library):
    output = args.output / name
    command = [args.compiler.resolve(), "build", "-f", WORKLOAD / "src/videodecode.swg",
               "--module-file", WORKLOAD / "module.swg", "-bc", "release", "--num-cores", "4",
               "--out-dir", output / "bin", "--work-dir", output / "work"]
    run(command, args.output / f"{name}.build.log",
        env={**os.environ, "SWAG_PATH": str(library.resolve())})
    return output / "bin" / WORKLOAD.name


def swag(executable, log, lanes, *values):
    return run([executable, *(str(value) for value in values)], log,
               env={**os.environ, "SWAG_RUNTIME_THREADS": str(lanes)})


def fixture_timeline(path, rgb=False):
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
    if rgb:
        raw = stream["codec_name"] == "rawvideo" and path.suffix.lower() in (".avi", ".y4m")
        if not raw and stream["codec_name"] != "mjpeg":
            raise ValueError(f"{path} needs Y4M, uncompressed AVI or Motion JPEG for RGB comparison")
    elif stream["codec_name"] not in ("h264", "hevc", "mpeg4", "rv40") or pixel_format not in (
        "yuv420p", "yuv444p", "yuv420p10le"
    ):
        raise ValueError(f"{path} has an unsupported codec or planar layout")
    scale = Fraction(stream["time_base"])
    records = metadata["packets_and_frames"]
    # Reader's clock starts at the earliest sample, which may precede FFmpeg's first picture.
    packet_pts = [record["pts"] for record in records if record["type"] == "packet" and "pts" in record]
    picture_pts = [record.get("best_effort_timestamp") for record in records if record["type"] == "frame"]
    if not packet_pts or not picture_pts or None in picture_pts:
        raise ValueError(f"{path} needs packet and picture presentation timestamps")
    origin = min(packet_pts)
    times = [(pts - origin) * scale for pts in picture_pts]
    if any(a >= b for a, b in zip(times, times[1:])):
        raise ValueError(f"{path} needs unique increasing presentation timestamps")
    return stream, times


def compare_pictures(path, stream, frames, pictures, rgb):
    width, height, fmt = (stream[key] for key in ("width", "height", "pix_fmt"))
    luma = width * height
    chroma = luma if fmt == "yuv444p" else ((width + 1) // 2) * ((height + 1) // 2)
    samples = 3 * luma if rgb else luma + 2 * chroma
    main10 = not rgb and fmt == "yuv420p10le"
    native_bytes = samples * (2 if main10 else 1)
    digest = hashlib.sha256()
    differing_frames = different = greatest = squares = 0

    command = ["ffmpeg", "-nostdin", "-v", "error", "-xerror", "-threads", "1",
               "-i", path, "-map", "0:v:0", "-an", "-sn", "-dn", "-fps_mode", "passthrough"]
    if rgb:
        command.extend(["-filter_threads", "1", "-vf", "scale=flags=neighbor:in_color_matrix=bt601"])
    command.extend(["-c:v", "rawvideo", "-threads", "1", "-f", "rawvideo", "-pix_fmt",
                    "rgb24" if rgb else fmt, "pipe:1"])
    with subprocess.Popen(command, stdout=subprocess.PIPE) as ffmpeg, pictures.open("rb") as decoded:
        for index in range(frames):
            reference = ffmpeg.stdout.read(native_bytes)
            actual = decoded.read(samples)
            if len(reference) != native_bytes or len(actual) != samples:
                raise ValueError(f"{path} has an incomplete picture at reference frame {index}")
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


def benchmark_fixture(args, reference, executables, path, prefix):
    rgb = args.rgb
    stream, times = fixture_timeline(path, rgb)
    frames = len(times) - args.warmup
    if not args.quality_only and frames <= 0:
        raise ValueError(f"{path} needs more than {args.warmup} frames for timing")

    timeline = prefix.with_suffix(".pts")
    timeline.write_text("".join(f"{float(time):.12f}\n" for time in times))
    quality = {}
    picture_mode = "rgb" if rgb else "planes"
    if not args.quality_only:
        picture_mode += "-dense"
    suffix = "rgb" if rgb else "yuv"
    for name, executable in executables.items():
        pictures = prefix.with_suffix(f".{name}.{suffix}")
        swag(executable, prefix.with_suffix(f".{name}.{picture_mode}.log"),
             args.lanes, picture_mode, path, timeline, pictures)
        quality[name] = compare_pictures(path, stream, len(times), pictures, rgb)
        pictures.unlink()

    with path.open("rb") as file:
        digest = hashlib.file_digest(file, "sha256").hexdigest()
    result = {"path": str(path), "fixture_sha256": digest,
              "stream": stream, "frames": len(times), "quality": quality}
    if args.quality_only:
        return result

    native = ["ffmpeg", "ffmpeg_no_simd"]
    if args.jpeg_reference and stream["codec_name"] == "mjpeg":
        native.append("jpeg_turbo")
    timing = {name: [] for name in (*executables, *native)}
    native_cpu = {name: [] for name in native}
    order = list(timing)
    for repetition in range(args.repetitions):
        for name in order:
            log = prefix.with_suffix(f".{name}.{repetition + 1}.log")
            if name in executables:
                text = swag(executables[name], log, args.lanes, "time-rgb" if rgb else "time",
                            path, 1, len(times), args.warmup)
                count, ticks, frequency = map(int, SWAG_TIMING.findall(text)[0])
                elapsed = ticks / frequency
            else:
                if name == "jpeg_turbo":
                    command = [args.jpeg_reference, path, "1", str(args.warmup)]
                else:
                    command = [reference, path, "1", str(int(name == "ffmpeg_no_simd"))]
                    if args.warmup != WARMUP or args.lanes != 1 or rgb:
                        command.append(str(args.warmup))
                    if args.lanes != 1 or rgb:
                        command.append(str(args.lanes))
                    if rgb:
                        command.append("rgb")
                text = run(command, log)
                count_text, wall, cpu = FFMPEG_TIMING.findall(text)[0]
                count, elapsed = int(count_text), float(wall)
                native_cpu[name].append(float(cpu) * 1000 / frames)
            if count != frames:
                raise ValueError(f"{name} decoded {count} timed pictures from {path}, expected {frames}")
            timing[name].append(elapsed * 1000 / frames)
        order = order[1:] + order[:1]

    result["timed_frames"] = frames
    result["warmup_frames"] = args.warmup
    result["wall_ms_per_frame"] = {name: {"samples": samples, "median": statistics.median(samples)}
                                   for name, samples in timing.items()}
    if "jpeg_turbo" in native_cpu:
        result["jpeg_turbo_cpu_ms_per_frame"] = native_cpu.pop("jpeg_turbo")
    result["ffmpeg_cpu_ms_per_frame"] = native_cpu
    return result


def main():
    args = arguments()
    args.output.mkdir(parents=True)
    reference = None
    if not args.quality_only:
        reference = args.reference.resolve() if args.reference else build_reference(args.output)
    executables = {"candidate": build_swag(args, "candidate", args.library_bin)}
    if args.baseline_bin:
        executables["baseline"] = build_swag(args, "baseline", args.baseline_bin)
    results = []
    for index, input_path in enumerate(args.input):
        result = benchmark_fixture(args, reference, executables, input_path.resolve(), args.output / f"fixture-{index}")
        results.append(result)
        print(json.dumps(result), flush=True)
    version = subprocess.check_output(["ffmpeg", "-version"], text=True).splitlines()[0]
    report = {"ffmpeg": version, "lanes": args.lanes, "rgb": args.rgb,
              "mpeg4_max_sample_difference": args.mpeg4_max_sample_difference,
              "results": results}
    if reference:
        native_version = subprocess.run([reference, "--version"], capture_output=True, text=True)
        if native_version.returncode == 0:
            report["ffmpeg_native"] = native_version.stdout.strip()
    if not args.quality_only and args.jpeg_reference:
        report["jpeg_reference"] = subprocess.check_output([args.jpeg_reference, "--version"], text=True).strip()
    (args.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    if not args.rgb:
        for result in results:
            limit = args.mpeg4_max_sample_difference if result["stream"]["codec_name"] == "mpeg4" else 0
            if any(quality["max_difference"] > limit for quality in result["quality"].values()):
                return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
