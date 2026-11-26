#!/usr/bin/env python3
"""Generate AAC attack fixtures and measure pre-attack energy in the outputs."""
import argparse
from array import array
import json
import math
from pathlib import Path
import subprocess
import sys

RATE = 48000
BLOCK = 1024
PHASES = (0, 64, 192, 320, 448, 576, 704, 832, 960)
ATTACKS = tuple((9 + 14 * index) * BLOCK + phase for index, phase in enumerate(PHASES))
FRAMES = (9 + 14 * len(PHASES)) * BLOCK


def generate(directory):
    directory.mkdir(parents=True, exist_ok=False)
    impulses = [0] * FRAMES
    for index, attack in enumerate(ATTACKS):
        impulses[attack] = 20000 if index % 2 == 0 else -20000
    background = []
    for frame in range(FRAMES):
        step = math.tau * frame / RATE
        tones = sum(level * math.sin(step * hertz)
                    for hertz, level in ((405, 3200), (880, 1700), (2333, 1040), (11019, 360)))
        background.append(round(tones * (0.75 + 0.25 * math.sin(step * 2.41))))
    mixed = (tone + attack for tone, attack in zip(background, impulses, strict=True))
    for label, values in (("isolated", impulses), ("background", background), ("mixed", mixed)):
        raw = array("h", values)
        if sys.byteorder != "little":
            raw.byteswap()
        (directory / f"{label}.pcm").write_bytes(raw.tobytes())


def measurements(pcm):
    def power(window):
        return sum(sample * sample for sample in window)

    rows = []
    for phase, index in zip(PHASES, ATTACKS, strict=True):
        early = pcm[index - 1536:index - 256]
        before = pcm[index - 512:index]
        after = pcm[index:index + 512]
        denominator = power(after)
        if not denominator:
            raise ValueError(f"Missing decoded attack at phase {phase}")
        onset = next((sample - 1536 for sample, value in enumerate(pcm[index - 1536:index])
                      if abs(value) >= 64), None)
        rows.append({"phase": phase, "peak_offset_frames": max(range(-512, 512), key=lambda delta: abs(pcm[index + delta])),
                     "early_peak_pcm16": max(map(abs, early)),
                     "early_pre_to_post_db": 10 * math.log10(power(early) / denominator) if power(early) else None,
                     "local_pre_to_post_db": 10 * math.log10(power(before) / denominator) if power(before) else None,
                     "first_pre_sample_above_64_frames": onset})
    return rows


def decode(directory, engine, ffmpeg):
    report = json.loads((directory / "results.json").read_text())
    if (report["input"]["rate"], report["input"]["channels"], report["input"]["frames"]) != (RATE, 1, FRAMES):
        raise ValueError("Expected a generated mono attack fixture")
    data = report["engines"][engine]
    pcm = array("h", subprocess.check_output([
        ffmpeg, "-v", "error", "-nostdin", "-threads", "1", "-i", directory / f"{engine}.aac",
        "-map", "0:a:0", "-f", "s16le", "-c:a", "pcm_s16le", "pipe:1",
    ]))
    if sys.byteorder != "little":
        pcm.byteswap()
    delay = data["quality"]["leading_trim_frames"]
    result = pcm[delay:delay + FRAMES]
    if len(result) != FRAMES:
        raise ValueError("Decoded AAC output is shorter than the fixture")
    return result, data


def analyze(directory, background, ffmpeg):
    report = json.loads((directory / "results.json").read_text())
    result = {}
    for engine in report["engines"]:
        pcm, data = decode(directory, engine, ffmpeg)
        if background:
            background_pcm, _ = decode(background, engine, ffmpeg)
            pcm = [sample - tone for sample, tone in zip(pcm, background_pcm, strict=True)]
        result[engine] = {"payload_bps": data["payload_bps"], "waveform_snr_db": data["quality"]["snr_db"],
                          "phases": measurements(pcm)}
    print(json.dumps(result, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare = commands.add_parser("generate")
    prepare.add_argument("output", type=Path)
    check = commands.add_parser("analyze")
    check.add_argument("results", type=Path)
    check.add_argument("--background", type=Path, help="corresponding output directory for the signal without impulses")
    check.add_argument("--ffmpeg", default="ffmpeg", help="decoder for untimed PCM analysis")
    args = parser.parse_args()
    if args.command == "generate":
        generate(args.output)
    else:
        analyze(args.results, args.background, args.ffmpeg)


if __name__ == "__main__":
    main()
