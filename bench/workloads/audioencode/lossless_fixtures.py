#!/usr/bin/env python3
"""Generate dual-mono and reduced-resolution PCM16 encoder fixtures."""
import argparse
from array import array
from hashlib import sha256
import json
from pathlib import Path
import sys


# Each shift gives the number of bits to clear in one PCM16 input channel.
QUANTIZED = (
    ("noise48", "noise48-12bit", 48000, (4, 4)),
    ("surround48", "surround48-mixed-depth", 48000, (0, 0, 8, 3, 4, 1)),
    ("filesamples44", "filesamples44-8bit", 44100, (8, 8)),
    ("mono48", "mono48-1bit", 48000, (15,)),
)


def load_pcm(directory, name, rate, channels):
    path = directory / f"{name}.pcm"
    source = array("h", path.read_bytes())
    if len(source) != rate * channels * 10:
        raise ValueError(f"{path} must contain ten seconds of {channels}-channel PCM16 at {rate} Hz")
    if sys.byteorder != "little":
        source.byteswap()
    return source


def create(input_dir, output_dir):
    output_dir.mkdir(parents=True, exist_ok=False)
    manifest = []

    def save(name, source, samples, rate, channels, clear_bits=None):
        if sys.byteorder != "little":
            samples.byteswap()
        payload = samples.tobytes()
        path = output_dir / f"{name}.pcm"
        path.write_bytes(payload)
        record = {
            "input": path.name, "source": f"{source}.pcm",
            "sample_rate": rate, "channels": channels, "frames": len(samples) // channels,
            "sha256": sha256(payload).hexdigest(),
        }
        if clear_bits is not None:
            record["cleared_low_bits"] = clear_bits
        manifest.append(record)

    for name, output_name, rate, clear_bits in QUANTIZED:
        channels = len(clear_bits)
        samples = load_pcm(input_dir, name, rate, channels)
        for channel, bits in enumerate(clear_bits):
            if bits:
                mask = ~((1 << bits) - 1)
                samples[channel::channels] = array("h", (sample & mask for sample in samples[channel::channels]))
        save(output_name, name, samples, rate, channels, clear_bits)

    mono = load_pcm(input_dir, "mono48", 48000, 1)
    stereo = array("h", [0]) * (len(mono) * 2)
    stereo[::2] = mono
    stereo[1::2] = mono
    save("dualmono48", "mono48", stereo, 48000, 2)
    (output_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    create(args.input_dir, args.output_dir)
