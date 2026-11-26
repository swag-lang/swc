#!/usr/bin/env python3
"""Compare native audio encoding on identical interleaved PCM16 input."""

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


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codec", choices=("aac", "flac", "wav"), required=True)
    parser.add_argument("--rate", type=int, required=True)
    parser.add_argument("--channels", type=int, required=True)
    parser.add_argument("--bandwidth", choices=("full", "voice"), default="full")
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--library-bin", type=Path, default=WORKLOAD.parents[2] / "bin")
    parser.add_argument("--baseline-bin", type=Path)
    parser.add_argument("--exact-baseline", action="store_true")
    parser.add_argument("--reference", type=Path, help="prebuilt native FFmpeg encoder benchmark")
    parser.add_argument("--reference-setting", type=int, help="AAC bitrate or FFmpeg FLAC compression level")
    parser.add_argument("--libflac", type=int, choices=range(9), metavar="LEVEL",
                        help="also compare the system libFLAC stream encoder at this compression level")
    parser.add_argument("--ffmpeg", default="ffmpeg", help="FFmpeg CLI used for untimed quality checks")
    parser.add_argument("--rounds", type=int, default=6)
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("input", type=Path, help="interleaved signed 16-bit little-endian PCM")
    args = parser.parse_args()
    max_channels = 8 if args.codec == "flac" else 2
    if not 1 <= args.channels <= max_channels or args.rate <= 0:
        parser.error("Unsupported channel count or sample rate")
    if args.codec == "aac" and args.rate not in (44100, 48000):
        parser.error("AAC needs 44.1 or 48 kHz")
    if args.rounds < 1 or args.repetitions < 1:
        parser.error("--rounds and --repetitions must be positive")
    if args.exact_baseline and not args.baseline_bin:
        parser.error("--exact-baseline needs --baseline-bin")
    if args.libflac is not None and args.codec != "flac":
        parser.error("--libflac applies to FLAC")
    if args.codec != "aac" and args.bandwidth != "full":
        parser.error("--bandwidth applies to AAC")
    if sys.byteorder != "little":
        parser.error("This workload expects a little-endian host")
    args.input = args.input.resolve()
    args.output = args.output.resolve()
    roots = [WORKLOAD, args.library_bin.resolve()]
    if args.baseline_bin:
        roots.append(args.baseline_bin.resolve())
    if any(args.output.is_relative_to(root) for root in roots):
        parser.error("--output must be outside the source trees")
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
        process = subprocess.run(command, env=env, stdout=capture, stderr=subprocess.STDOUT)
    if process.returncode:
        raise RuntimeError(f"{name} build failed. See {log}")
    return build / "bin" / WORKLOAD.name


def build_reference(output):
    options = subprocess.check_output([
        "pkg-config", "--cflags", "--libs", "libavformat", "libavcodec", "libavutil",
    ], text=True)
    executable = output / "ffmpeg_native"
    subprocess.run(["cc", "-O2", WORKLOAD / "ffmpeg_native.c", "-o", executable,
                    *shlex.split(options)], check=True)
    return executable


def run(args, binary, setting, output, log, repetitions, frames):
    command = [sys.executable, binary] if binary.suffix == ".py" else [binary]
    command += [args.codec, args.input, str(args.rate), str(args.channels),
                str(setting), output, str(repetitions)]
    env = {**os.environ, "SWAG_RUNTIME_THREADS": "1"}
    env.pop("AUDIO_ENCODE_CUTOFF", None)
    if isinstance(setting, int) and args.codec == "aac" and args.bandwidth == "voice":
        env["AUDIO_ENCODE_CUTOFF"] = str(176 * args.rate // 2048)
    process = subprocess.run(command, env=env, capture_output=True, text=True)
    log.write_text(process.stdout + process.stderr)
    if process.returncode:
        raise RuntimeError(f"{binary.name} failed. See {log}")
    rows = [list(map(int, line.split())) for line in process.stdout.splitlines()]
    if len(rows) != repetitions or any(len(row) != 6 for row in rows):
        raise ValueError(f"Unexpected timing output. See {log}")
    if any(sum(row[:3]) != row[3] or row[4] != frames for row in rows):
        raise ValueError(f"Unexpected timing or frame count. See {log}")
    return rows


def adts_payload_bytes(data):
    offset = payload = 0
    while offset < len(data):
        header = data[offset:offset + 7]
        if len(header) != 7 or header[0] != 255 or header[1] & 0xF6 != 0xF0:
            raise ValueError("Invalid ADTS header")
        head_bytes = 7 if header[1] & 1 else 9
        frame_bytes = ((header[3] & 3) << 11) | (header[4] << 3) | (header[5] >> 5)
        if head_bytes > frame_bytes or offset + frame_bytes > len(data):
            raise ValueError("Invalid ADTS frame size")
        payload += frame_bytes - head_bytes
        offset += frame_bytes
    return payload


def bitrate(args, output, frames):
    return adts_payload_bytes(output.read_bytes()) * 8 * args.rate / frames


def reference_setting(args, candidate, reference, frames):
    if args.reference_setting is not None:
        return args.reference_setting, []
    if args.codec != "aac":
        return (5 if args.codec == "flac" else 0), []

    target = args.output / "calibration-swag.aac"
    run(args, candidate, args.bandwidth, target, args.output / "calibration-swag.log", 1, frames)
    target_bitrate = bitrate(args, target, frames)
    maximum = args.channels * args.rate * 6
    requested = min(maximum, max(8000, round(target_bitrate)))
    trial_file = args.output / "calibration-ffmpeg.aac"
    trials = []
    for attempt in range(8):
        run(args, reference, requested, trial_file,
            args.output / f"calibration-ffmpeg-{attempt + 1}.log", 1, frames)
        actual = bitrate(args, trial_file, frames)
        trials.append({"requested_bps": requested, "actual_bps": actual})
        if abs(actual - target_bitrate) <= target_bitrate * 0.01:
            break
        lower = max((trial for trial in trials if trial["actual_bps"] < target_bitrate),
                    key=lambda trial: trial["actual_bps"], default=None)
        upper = min((trial for trial in trials if trial["actual_bps"] > target_bitrate),
                    key=lambda trial: trial["actual_bps"], default=None)
        if lower and upper:
            ratio = (target_bitrate - lower["actual_bps"]) / (upper["actual_bps"] - lower["actual_bps"])
            estimate = lower["requested_bps"] + ratio * (upper["requested_bps"] - lower["requested_bps"])
        else:
            estimate = requested * target_bitrate / actual
        requested = min(maximum, max(8000, round(estimate)))
        if any(trial["requested_bps"] == requested for trial in trials):
            break
    best = min(trials, key=lambda trial: abs(trial["actual_bps"] - target_bitrate))
    return best["requested_bps"], trials


def quality(args, path, input_pcm, delay):
    decoded = subprocess.check_output([
        args.ffmpeg, "-nostdin", "-v", "error", "-threads", "1", "-i", str(path),
        "-map", "0:a:0", "-c:a", "pcm_s16le", "-f", "s16le", "pipe:1",
    ])
    frame_bytes = args.channels * 2
    trimmed = decoded[delay * frame_bytes: delay * frame_bytes + len(input_pcm)]
    if len(trimmed) != len(input_pcm):
        raise ValueError(f"Too few decoded samples in {path}")
    result = {"decoded_frames": len(decoded) // frame_bytes, "leading_trim_frames": delay}
    if args.codec != "aac":
        if decoded != input_pcm:
            raise ValueError(f"Lossless PCM changed in {path}")
        result["pcm_exact"] = True
        return result

    original = array("h", input_pcm)
    roundtrip = array("h", trimmed)
    signal = error = peak = 0
    for expected, actual in zip(original, roundtrip, strict=True):
        delta = expected - actual
        peak = max(peak, abs(delta))
        signal += expected * expected
        error += delta * delta
    result.update({"snr_db": ("inf" if not error else 10 * math.log10(signal / error)) if signal else None,
                   "rms_delta_pcm16": math.sqrt(error / len(original)), "max_delta_pcm16": peak})
    return result


def main():
    args = arguments()
    input_pcm = args.input.read_bytes()
    frames, remainder = divmod(len(input_pcm), 2 * args.channels)
    if not frames or remainder:
        raise ValueError("PCM input must contain complete, nonempty frames")
    args.output.mkdir(parents=True, exist_ok=False)
    candidate = build_swag(args, "candidate", args.library_bin)
    reference = args.reference.resolve() if args.reference else build_reference(args.output)
    setting, calibration = reference_setting(args, candidate, reference, frames)
    binaries = {}
    settings = {}
    if args.baseline_bin:
        binaries["baseline"] = build_swag(args, "baseline", args.baseline_bin)
        settings["baseline"] = args.bandwidth
    binaries.update(candidate=candidate, ffmpeg=reference)
    settings.update(candidate=args.bandwidth, ffmpeg=setting)
    if args.libflac is not None:
        binaries["libflac"] = WORKLOAD / "libflac_native.py"
        settings["libflac"] = args.libflac
    outputs = {engine: args.output / f"{engine}.{args.codec}" for engine in binaries}
    rows = {engine: [] for engine in binaries}
    orders = list(permutations(binaries))
    for round_index in range(args.rounds):
        for engine in orders[round_index % len(orders)]:
            log = args.output / f"{engine}-{round_index + 1}.log"
            rows[engine].extend(run(args, binaries[engine], settings[engine], outputs[engine],
                                    log, args.repetitions, frames))

    report = {
        "protocol": {
            "units": "microseconds", "sample_fields": ["open", "feed", "finish", "total"],
            "rounds": args.rounds, "repetitions": args.repetitions, "threads": 1,
            "affinity": sorted(os.sched_getaffinity(0)), "system": platform.platform(),
            "ffmpeg": subprocess.check_output([reference, "--version"], text=True).strip(),
            "codec": args.codec, "calibration": calibration,
        },
        "input": {"name": args.input.name, "frames": frames, "rate": args.rate, "channels": args.channels,
                  "sha256": hashlib.sha256(input_pcm).hexdigest()},
        "engines": {},
    }
    if args.libflac is not None:
        report["protocol"]["libflac"] = subprocess.check_output(
            [sys.executable, binaries["libflac"], "--version"], text=True,
        ).strip()
    for engine, stages in rows.items():
        delay = stages[0][5]
        if any(row[5] != delay for row in stages):
            raise ValueError(f"Inconsistent encoder delay for {engine}")
        data = outputs[engine].read_bytes()
        samples = [row[:4] for row in stages]
        result = {"setting": settings[engine], "size_bytes": len(data),
                  "sha256": hashlib.sha256(data).hexdigest(),
                  "median_us": list(map(median, zip(*samples))), "samples_us": samples,
                  "quality": quality(args, outputs[engine], input_pcm, delay)}
        if args.codec == "aac":
            result["payload_bytes"] = adts_payload_bytes(data)
            result["payload_bps"] = result["payload_bytes"] * 8 * args.rate / frames
        report["engines"][engine] = result
        print(f"{engine} {result['median_us'][3] / 1000:.3f} ms, {result['size_bytes']} bytes", flush=True)
    if args.exact_baseline and report["engines"]["baseline"]["sha256"] != report["engines"]["candidate"]["sha256"]:
        raise ValueError("Encoded output differs from the Swag baseline")
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
