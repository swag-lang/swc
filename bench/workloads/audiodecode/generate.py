#!/usr/bin/env python3
"""Create a deterministic set of audio decode benchmark fixtures."""

import argparse
from array import array
from functools import cache
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import wave

SECONDS = 12
# name, source sample rate, source channel layout, encoder options
CASES = (
    ("aac-lc-32k-mono.aac", 32000, "mono", ("aac", "-b:a", "48k")),
    ("aac-lc-48k-stereo.aac", 48000, "stereo", ("aac", "-b:a", "192k")),
    ("aac-lc-48k-5.1.aac", 48000, "5.1", ("aac", "-b:a", "384k")),
    ("ac3-32k-mono.ac3", 32000, "mono", ("ac3", "-b:a", "96k")),
    ("ac3-44k-stereo.ac3", 44100, "stereo", ("ac3", "-b:a", "192k")),
    ("ac3-48k-5.1.ac3", 48000, "5.1", ("ac3", "-b:a", "448k")),
    ("dts-48k-5.1.dts", 48000, "5.1", ("dca", "-strict", "experimental", "-b:a", "768k")),
    ("eac3-48k-5.1.eac3", 48000, "5.1", ("eac3", "-b:a", "448k")),
    ("flac-44k-stereo-16.flac", 44100, "stereo", ("flac", "-sample_fmt", "s16")),
    ("flac-96k-stereo-24.flac", 96000, "stereo", ("flac", "-sample_fmt", "s32", "-bits_per_raw_sample", "24")),
    ("flac-48k-5.1-16.flac", 48000, "5.1", ("flac", "-sample_fmt", "s16")),
    ("mp3-8k-mono.mp3", 8000, "mono", ("libmp3lame", "-b:a", "16k")),
    ("mp3-24k-mono.mp3", 24000, "mono", ("libmp3lame", "-q:a", "5")),
    ("mp3-48k-stereo.mp3", 48000, "stereo", ("libmp3lame", "-q:a", "2")),
    ("ogg-flac-48k-mono-16.oga", 48000, "mono", ("flac", "-sample_fmt", "s16", "-f", "ogg")),
    ("opus-voip-48k-mono.opus", 48000, "mono", ("libopus", "-b:a", "16k", "-application", "voip")),
    ("opus-5ms-48k-stereo.opus", 48000, "stereo", ("libopus", "-b:a", "96k", "-application", "lowdelay", "-frame_duration", "5")),
    ("opus-20ms-48k-stereo.opus", 48000, "stereo", ("libopus", "-b:a", "128k", "-frame_duration", "20")),
    ("vorbis-32k-mono.ogg", 32000, "mono", ("libvorbis", "-q:a", "2")),
    ("vorbis-48k-stereo.ogg", 48000, "stereo", ("libvorbis", "-q:a", "5")),
    ("vorbis-48k-5.1.ogg", 48000, "5.1", ("libvorbis", "-q:a", "5")),
    ("wav-48k-stereo-24.wav", 48000, "stereo", ("pcm_s24le",)),
)
CHANNELS = {"mono": 1, "stereo": 2, "5.1": 6}
PHASE_BITS = 16


@cache
def sine_table():
    # Quantizing upfront leaves all sample generation in integer arithmetic.
    return tuple(round(math.sin(math.tau * i / 4096) * 32767) for i in range(4096))


def write_pcm(path, rate, layout):
    channels = CHANNELS[layout]
    sine = sine_table()
    # Conventional 5.1 order is FL, FR, FC, LFE, BL, BR.
    pitches = (167, 199, 241, 51, 337, 439)
    steps = [(hz << PHASE_BITS) // rate for hz in pitches[:channels]]
    phases = [2779 * c for c in range(channels)]
    state = 0x3C6EF372
    with wave.open(str(path), "wb") as wav:
        wav.setparams((channels, 4, rate, 0, "NONE", "not compressed"))
        for second in range(SECONDS):
            samples = array("i")
            for frame in range(rate):
                # Vary the transients and running envelope across packet boundaries.
                pulse = max(0, rate // 70 - (frame + second * 41) % (rate // 7))
                gain = 10 + (frame * (6 + second % 4) // rate) % 6
                if second % 6 == 5:
                    gain //= 2
                for channel, step in enumerate(steps):
                    phase = phases[channel]
                    phases[channel] += step + ((frame >> 11) & 3)
                    fundamental = sine[(phase >> 4) & 4095]
                    harmonic = sine[(3 * phase >> 4) & 4095]
                    state = (1664525 * state + 1013904223) & 0xFFFFFFFF
                    noise = (state >> 16) - 32768
                    value = fundamental * gain + harmonic * (0 if channel == 3 else 3)
                    value += noise * pulse * (0 if channel == 3 else 8) // (rate // 70)
                    samples.append(value * 1536)
            if sys.byteorder != "little":
                samples.byteswap()
            wav.writeframesraw(samples.tobytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    version = subprocess.check_output([args.ffmpeg, "-version"], text=True).splitlines()[0]
    manifest = {"ffmpeg": version, "seconds": SECONDS, "fixtures": []}
    with tempfile.TemporaryDirectory(dir=args.output) as temp:
        sources = {}
        for name, rate, layout, options in CASES:
            source = sources.get((rate, layout))
            if source is None:
                source = Path(temp) / f"{rate}-{layout}.wav"
                write_pcm(source, rate, layout)
                sources[rate, layout] = source
            path = args.output / name
            command = [
                args.ffmpeg, "-nostdin", "-v", "error", "-fflags", "+bitexact",
                "-channel_layout", layout, "-i", str(source), "-map", "0:a:0",
                "-map_metadata", "-1", "-fflags", "+bitexact", "-threads", "1", "-flags:a", "+bitexact",
                "-c:a", *options, str(path),
            ]
            subprocess.run(command, check=True)
            manifest["fixtures"].append({
                "fixture": name,
                "source_rate": rate,
                "source_layout": layout,
                "encoder_options": list(options),
                "size_bytes": path.stat().st_size,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            })
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
