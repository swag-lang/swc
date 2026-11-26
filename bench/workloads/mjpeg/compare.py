"""Compare the Swag, FFmpeg and libjpeg-turbo 4:4:4 Motion JPEG encoders."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess


WORKLOAD = Path(__file__).resolve().parent
MEASUREMENT = re.compile(r"^MJPEG frames=(\d+) us=(\d+) cpu_us=(\d+) bytes=(\d+)$", re.M)


def run(command, log, env=None):
    with log.open("w") as stream:
        subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT, check=True)
    return log.read_text()


def raw_options(width, height):
    return ["-f", "rawvideo", "-pixel_format", "rgb24", "-video_size", f"{width}x{height}", "-framerate", "30"]


def quality(source, encoded, output, width, height, frames):
    decoded = output.with_suffix(".rgb")
    run(["ffmpeg", "-v", "error", "-xerror", "-nostdin", "-threads", "1", "-i", encoded,
         "-pix_fmt", "rgb24", "-fps_mode", "passthrough", "-threads", "1", "-f", "rawvideo",
         decoded], output.with_suffix(".decode.log"))
    if decoded.stat().st_size != width * height * frames * 3:
        raise RuntimeError(f"picture count or dimensions differ for {encoded}")
    raw = raw_options(width, height)
    results = {}
    for metric, key in (("psnr", "average"), ("ssim", "All")):
        graph = f"[0:v]vflip,format=gbrp[reference];[1:v]format=gbrp[decoded];[decoded][reference]{metric}"
        log = run(["ffmpeg", "-hide_banner", "-nostdin", *raw, "-i", source, *raw, "-i", decoded,
                   "-filter_complex_threads", "1", "-lavfi", graph, "-f", "null", "-"],
                  output.with_suffix(f".{metric}.log"))
        match = re.search(rf"\b{key}:([0-9.]+|inf)", log)
        if not match:
            raise RuntimeError(f"missing {metric} for {encoded}")
        results[metric] = match[1] if match[1] == "inf" else float(match[1])
    with decoded.open("rb") as stream:
        results["decoded_sha256"] = hashlib.file_digest(stream, "sha256").hexdigest()
    decoded.unlink()
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--library-bin", type=Path, help="bin tree of an external source snapshot")
    parser.add_argument("--reference", type=Path, required=True, help="prebuilt mjpeg_native")
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--frames", type=int, default=30)
    parser.add_argument("--repetitions", type=int, default=5)
    parser.add_argument("--output", type=Path, required=True, help="new evidence directory outside the checkout")
    parser.add_argument("input", type=Path, nargs="+", help="bottom-up packed RGB8 clips of equal dimensions and length")
    args = parser.parse_args()
    repo = WORKLOAD.parents[2]
    library = (args.library_bin or repo / "bin").resolve()
    output = args.output.resolve()
    if output.exists() or any(root == output or root in output.parents for root in (repo, library)):
        parser.error("--output must be a new directory outside the source trees")
    if not all(v > 0 for v in (args.width, args.height, args.frames, args.repetitions)):
        parser.error("dimensions, picture count and repetitions must be positive")
    inputs = [path.resolve() for path in args.input]
    if any(path.stat().st_size != args.width * args.height * args.frames * 3 for path in inputs):
        parser.error("input size differs from the dimensions and picture count")
    output.mkdir(parents=True)
    env = {**os.environ, "SWAG_PATH": str(library), "SWAG_RUNTIME_THREADS": "1"}
    compiler = args.compiler.resolve()
    binary = output / "bin" / "mjpeg"
    run([compiler, "build", "-f", WORKLOAD / "src/mjpeg.swg", "--module-file", WORKLOAD / "module.swg",
         "-bc", "release", "--num-cores", "1", "--out-dir", binary.parent, "--work-dir", output / "work"],
        output / "swag.build.log", env)
    shared = (library / "std/.output").glob("*/shared-library/release/x86_64/*.so")
    paths = [str(p.parent) for p in sorted(shared)]
    if env.get("LD_LIBRARY_PATH"):
        paths.append(env["LD_LIBRARY_PATH"])
    env["LD_LIBRARY_PATH"] = ":".join(paths)
    dimensions = [str(n) for n in (args.width, args.height, args.frames)]
    ref = args.reference.resolve()
    control = output / "lossless.mkv"
    run(["ffmpeg", "-v", "error", "-nostdin", *raw_options(args.width, args.height), "-i", inputs[0],
         "-vf", "vflip,setpts=PTS+5/TB", "-c:v", "ffv1", "-pix_fmt", "bgr0", "-threads", "1", control],
        output / "lossless.encode.log")
    checked = quality(inputs[0], control, output / "lossless", args.width, args.height, args.frames)
    if checked["psnr"] != "inf" or checked["ssim"] != 1:
        raise RuntimeError("lossless RGB reference differs after decoding")
    encoders = [("swag", (40, 60, 80, 95)), ("turbo", (70, 80, 90, 95)), ("ffmpeg", (3, 5, 8, 12))]
    rows = []
    for index, source in enumerate(inputs):
        for settings in zip(*(values for _, values in encoders)):
            cases = []
            for (encoder, _), setting in zip(encoders, settings):
                prefix = output / f"clip{index}-{encoder}-{setting}"
                movie = prefix.with_suffix(".mjpg")
                if encoder == "swag":
                    command = [binary, source, *dimensions, str(setting), movie]
                else:
                    command = [ref, encoder, source, movie, *dimensions, str(setting)]
                cases.append((encoder, setting, prefix, movie, command))
            metrics = {encoder: [] for encoder, _ in encoders}
            hashes = {}
            for repeat in range(args.repetitions):
                first = repeat % len(cases)
                for encoder, setting, prefix, movie, command in cases[first:] + cases[:first]:
                    match = MEASUREMENT.search(run(command, prefix.with_suffix(f".run{repeat}.log"), env if encoder == "swag" else None))
                    if not match or int(match[1]) != args.frames or int(match[4]) != movie.stat().st_size:
                        raise RuntimeError(f"missing or inconsistent timing for {movie}")
                    metrics[encoder].append(tuple(map(int, match.groups()[1:])))
                    with movie.open("rb") as stream:
                        digest = hashlib.file_digest(stream, "sha256").hexdigest()
                    if hashes.setdefault(encoder, digest) != digest:
                        raise RuntimeError(f"encoded bytes changed across repetitions for {movie}")
            for encoder, setting, prefix, movie, _ in cases:
                wall, cpu, sizes = zip(*metrics[encoder])
                if len(set(sizes)) != 1:
                    raise RuntimeError(f"encoded size changed across repetitions for {movie}")
                row = dict(input=source.name, encoder=encoder, quality_setting=setting,
                           encode_us=dict(median=statistics.median(wall), runs=wall),
                           cpu_us=dict(median=statistics.median(cpu), runs=cpu), packet_bytes=sizes[0],
                           encoded_sha256=hashes[encoder],
                           **quality(source, movie, prefix, args.width, args.height, args.frames))
                rows.append(row)
                print(json.dumps(row), flush=True)
    ffmpeg = subprocess.check_output(["ffmpeg", "-version"], text=True).splitlines()[0]
    inputs = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    (output / "report.json").write_text(json.dumps(dict(ffmpeg=ffmpeg, width=args.width, height=args.height,
                                                       frames=args.frames, inputs=inputs, metric_self_check=checked,
                                                       results=rows), indent=2) + "\n")


if __name__ == "__main__":
    main()
