#!/usr/bin/env python3
"""Time the installed libFLAC streaming encoder on PCM16 input."""

import argparse
from array import array
import ctypes as c
from ctypes.util import find_library
import os
from pathlib import Path
import sys
from time import perf_counter_ns


def micros():
    return perf_counter_ns() // 1000


def library():
    path = find_library("FLAC")
    if not path:
        raise RuntimeError("The libFLAC runtime is unavailable")
    api = c.CDLL(path)

    def bind(name, result, *arguments):
        function = getattr(api, f"FLAC__stream_encoder_{name}")
        function.restype = result
        function.argtypes = arguments
        return function

    def setter(name, value_type=c.c_uint):
        return bind(name, c.c_int, c.c_void_p, value_type)

    return {
        "version": c.c_char_p.in_dll(api, "FLAC__VERSION_STRING").value.decode(),
        "new": bind("new", c.c_void_p),
        "delete": bind("delete", None, c.c_void_p),
        "level": setter("set_compression_level"),
        "channels": setter("set_channels"),
        "rate": setter("set_sample_rate"),
        "bits": setter("set_bits_per_sample"),
        "samples": setter("set_total_samples_estimate", c.c_uint64),
        "start": bind("init_file", c.c_int, c.c_void_p, c.c_char_p, c.c_void_p, c.c_void_p),
        "submit": bind("process_interleaved", c.c_int, c.c_void_p, c.POINTER(c.c_int32), c.c_uint),
        "finish": bind("finish", c.c_int, c.c_void_p),
    }


def encode(api, samples, frames, rate, channels, level, path):
    started = micros()
    encoder = api["new"]()
    if not encoder:
        raise RuntimeError("Cannot allocate libFLAC encoder")
    try:
        for key, value in (("level", level), ("channels", channels), ("rate", rate),
                           ("bits", 16), ("samples", frames)):
            if not api[key](encoder, value):
                raise ValueError(f"libFLAC rejected {key} {value}")
        status = api["start"](encoder, os.fsencode(path), None, None)
        if status:
            raise RuntimeError(f"libFLAC could not open the output (status {status})")
        opened = micros()
        for offset in range(0, frames, 4096):
            count = min(4096, frames - offset)
            pointer = c.cast(c.byref(samples, offset * channels * c.sizeof(c.c_int32)),
                             c.POINTER(c.c_int32))
            if not api["submit"](encoder, pointer, count):
                raise RuntimeError("libFLAC rejected PCM frames")
        fed = micros()
        if not api["finish"](encoder):
            raise RuntimeError("libFLAC finalization failed")
    finally:
        api["delete"](encoder)
    finished = micros()
    return opened - started, fed - opened, finished - fed, finished - started, frames, 0


def main():
    api = library()
    if sys.argv[1:] == ["--version"]:
        print(api["version"])
        return
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("codec", choices=("flac",))
    parser.add_argument("input", type=Path)
    parser.add_argument("rate", type=int)
    parser.add_argument("channels", type=int)
    parser.add_argument("setting", type=int, choices=range(9))
    parser.add_argument("output", type=Path)
    parser.add_argument("repetitions", type=int)
    args = parser.parse_args()
    if args.rate < 1 or not 1 <= args.channels <= 8 or args.repetitions < 1:
        parser.error("Invalid rate, channel count, or repetitions")
    if sys.byteorder != "little" or array("i").itemsize != c.sizeof(c.c_int32):
        parser.error("This reference expects little-endian PCM with native 32-bit integers")
    pcm16 = array("h", args.input.read_bytes())
    frames, remainder = divmod(len(pcm16), args.channels)
    if not frames or remainder:
        parser.error("PCM input must contain whole, nonempty frames")
    pcm32 = array("i", pcm16)
    samples = (c.c_int32 * len(pcm32)).from_buffer(pcm32)
    for repeat in range(args.repetitions + 1):
        row = encode(api, samples, frames, args.rate, args.channels, args.setting, args.output)
        if repeat:
            print(*row)


if __name__ == "__main__":
    main()
