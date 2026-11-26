"""Compare complete Release raster image loads with an in-process MagickWand export."""

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time


def bind(library, name, arguments, result):
    function = getattr(library, name)
    function.argtypes = arguments
    function.restype = result
    return function


class MagickWand:
    def __init__(self, library):
        os.environ["MAGICK_THREAD_LIMIT"] = "1"
        lib = ctypes.CDLL(str(library))
        ptr, size = ctypes.c_void_p, ctypes.c_size_t
        self.genesis = bind(lib, "MagickWandGenesis", [], None)
        self.terminate = bind(lib, "MagickWandTerminus", [], None)
        self.new = bind(lib, "NewMagickWand", [], ptr)
        self.destroy = bind(lib, "DestroyMagickWand", [ptr], ptr)
        self.read = bind(lib, "MagickReadImage", [ptr, ctypes.c_char_p], ctypes.c_int)
        self.width = bind(lib, "MagickGetImageWidth", [ptr], size)
        self.height = bind(lib, "MagickGetImageHeight", [ptr], size)
        self.export = bind(lib, "MagickExportImagePixels",
                           [ptr, ctypes.c_ssize_t, ctypes.c_ssize_t, size, size,
                            ctypes.c_char_p, ctypes.c_int, ptr], ctypes.c_int)
        self.version = bind(lib, "MagickGetVersion", [ctypes.POINTER(size)], ctypes.c_char_p)

    def __enter__(self):
        self.genesis()
        return self

    def __exit__(self, *_):
        self.terminate()

    def prepare(self, fixture, width, height, channels, bits, floating):
        layout = {1: b"I", 2: b"IA", 3: b"RGB", 4: b"RGBA"}[channels]
        if floating:
            storage, sample = 3, ctypes.c_float  # FloatPixel
        elif bits == 16:
            storage, sample = 7, ctypes.c_uint16  # ShortPixel
        elif bits == 8:
            storage, sample = 1, ctypes.c_uint8  # CharPixel
        else:
            raise ValueError(f"{fixture}: unsupported sample depth {bits}")

        # Select the first image, retaining ImageMagick's own container and palette handling.
        path = os.fsencode(f"{fixture}[0]")
        pixels = (sample * (width * height * channels))()

        def measure():
            wand = self.new()
            if not wand:
                raise RuntimeError("NewMagickWand failed")
            try:
                started = time.perf_counter_ns()
                if not self.read(wand, path):
                    raise ValueError(f"{fixture}: MagickWand could not read the first image")
                if (self.width(wand), self.height(wand)) != (width, height):
                    raise ValueError(f"{fixture}: reference and Swag output dimensions differ")
                if not self.export(wand, 0, 0, width, height, layout, storage, pixels):
                    raise ValueError(f"{fixture}: MagickWand could not export {layout.decode()} pixels")
                return (time.perf_counter_ns() - started) / 1000
            finally:
                self.destroy(wand)

        return measure


def measure_swag(executable, fixture):
    fields = subprocess.check_output([executable, fixture], text=True).split()
    elapsed, *output = map(int, fields)
    return elapsed, tuple(output)


class LibWebP:
    def __init__(self, library):
        lib = ctypes.CDLL(library)
        ptr, size = ctypes.c_void_p, ctypes.c_size_t
        self.decode = bind(lib, "WebPDecodeRGBAInto", [ctypes.c_char_p, size, ptr, size, ctypes.c_int], ptr)
        self.version = bind(lib, "WebPGetDecoderVersion", [], ctypes.c_int)()

    def prepare(self, fixture, width, height):
        with fixture.open("rb") as stream:
            header = stream.read(21)
        if len(header) == 21 and header[12:16] == b"VP8X" and header[20] & 2:
            return None
        pixels = ctypes.create_string_buffer(width * height * 4)

        def measure():
            started = time.perf_counter_ns()
            encoded = fixture.read_bytes()
            if not self.decode(encoded, len(encoded), pixels, len(pixels), width * 4):
                raise ValueError(f"{fixture}: libwebp could not decode the image")
            return (time.perf_counter_ns() - started) / 1000

        return measure


class PngImage(ctypes.Structure):
    # Public png_image ABI from png.h (simplified API, PNG_IMAGE_VERSION 1).
    _fields_ = [("opaque", ctypes.c_void_p)] + [
        (name, ctypes.c_uint32)
        for name in ("version", "width", "height", "format", "flags", "colormap_entries", "warning_or_error")
    ] + [("message", ctypes.c_char * 64)]


class LibPng:
    def __init__(self, library):
        lib = ctypes.CDLL(library)
        image, ptr = ctypes.POINTER(PngImage), ctypes.c_void_p
        self.begin = bind(lib, "png_image_begin_read_from_file", [image, ctypes.c_char_p], ctypes.c_int)
        self.finish = bind(lib, "png_image_finish_read", [image, ptr, ptr, ctypes.c_int32, ptr], ctypes.c_int)
        self.free = bind(lib, "png_image_free", [image], None)
        self.version = bind(lib, "png_get_libpng_ver", [ptr], ctypes.c_char_p)(None).decode()

    def prepare(self, fixture, width, height, channels):
        path = os.fsencode(fixture)
        pixels = ctypes.create_string_buffer(width * height * channels)

        def measure():
            image = PngImage(version=1)
            started = time.perf_counter_ns()
            try:
                if not self.begin(ctypes.byref(image), path):
                    raise ValueError(f"{fixture}: libpng could not read the header: {image.message.decode()}")
                if (image.width, image.height) != (width, height):
                    raise ValueError(f"{fixture}: libpng and Swag output dimensions differ")
                # Channels minus one encodes PNG_FORMAT_FLAG_COLOR and PNG_FORMAT_FLAG_ALPHA.
                image.format = channels - 1
                if not self.finish(ctypes.byref(image), None, pixels, 0, None):
                    raise ValueError(f"{fixture}: libpng could not export pixels: {image.message.decode()}")
                return (time.perf_counter_ns() - started) / 1000
            finally:
                self.free(ctypes.byref(image))

        return measure


class LibJpegTurbo:
    def __init__(self, executable):
        self.executable = executable
        self.version = subprocess.check_output([executable, "--version"], text=True).strip()

    def prepare(self, fixture, width, height):
        def read_sample():
            return subprocess.check_output([self.executable, fixture], text=True).split()

        if read_sample() == ["unsupported"]:
            return None

        def measure():
            elapsed, actual_width, actual_height, channels = map(int, read_sample())
            if (actual_width, actual_height, channels) != (width, height, 3):
                raise ValueError(f"{fixture}: libjpeg-turbo and Swag output layouts differ")
            return elapsed

        return measure


def compare_fixture(fixture, candidate, baseline, magick, native, repetitions):
    _, expected = measure_swag(candidate, fixture)
    width, height, channels, bits, floating, pixel_format, checksum = expected
    references = {"imagemagick": magick.prepare(fixture, width, height, channels, bits, floating)}
    suffix = fixture.suffix.lower()
    if native.get("libwebp") and suffix == ".webp" and channels == 4 and bits == 8:
        reference = native["libwebp"].prepare(fixture, width, height)
        if reference:
            references["libwebp"] = reference
    if native.get("libpng") and suffix in (".png", ".apng") and bits == 8:
        references["libpng"] = native["libpng"].prepare(fixture, width, height, channels)
    if native.get("libjpeg-turbo") and suffix in (".jpg", ".jpeg", ".jpe", ".jfif") and channels == 3 and bits == 8:
        reference = native["libjpeg-turbo"].prepare(fixture, width, height)
        if reference:
            references["libjpeg-turbo"] = reference
    for measure in references.values():
        measure()
    engines = {"candidate": candidate, **dict.fromkeys(references)}
    if baseline:
        engines = {"baseline": baseline, **engines}
    timings = {name: [] for name in engines}
    for repetition in range(repetitions):
        order = list(engines.items())
        offset = repetition % len(order)
        for name, executable in order[offset:] + order[:offset]:
            if executable:
                elapsed, output = measure_swag(executable, fixture)
                if output != expected:
                    raise ValueError(f"{fixture}: {name} output differs from the candidate")
            else:
                elapsed = references[name]()
            timings[name].append(elapsed)
    with fixture.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    return {
        "fixture": str(fixture),
        "sha256": digest,
        "width": width,
        "height": height,
        "channels": channels,
        "bits_per_channel": bits,
        "floating_point": bool(floating),
        "pixel_format": pixel_format,
        "crc64": str(checksum),
        "samples_us": timings,
        "median_us": {name: statistics.median(values) for name, values in timings.items()},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True, help="Release rasterdecode executable")
    parser.add_argument("--baseline", type=Path, help="optional previous rasterdecode executable")
    parser.add_argument("--magick-wand", required=True, help="MagickWand library name or path")
    parser.add_argument("--libwebp", help="optional libwebp library name or path for still WebP")
    parser.add_argument("--libpng", help="optional libpng library name or path for 8-bit PNG output")
    parser.add_argument("--libjpeg-runner", type=Path, help="optional executable built from jpeg_native.c")
    parser.add_argument("--repetitions", type=int, default=9)
    parser.add_argument("--output", type=Path, required=True, help="JSON results file")
    parser.add_argument("fixtures", type=Path, nargs="+")
    args = parser.parse_args()
    if args.repetitions < 1:
        parser.error("--repetitions must be positive")

    candidate = args.candidate.resolve()
    baseline = args.baseline.resolve() if args.baseline else None
    magick = MagickWand(args.magick_wand)
    webp = LibWebP(args.libwebp) if args.libwebp else None
    native = {
        "libwebp": webp,
        "libpng": LibPng(args.libpng) if args.libpng else None,
        "libjpeg-turbo": LibJpegTurbo(args.libjpeg_runner.resolve()) if args.libjpeg_runner else None,
    }
    with magick:
        versions = {"imagemagick": magick.version(None).decode()}
        if webp:
            versions["libwebp"] = ".".join(str((webp.version >> shift) & 255) for shift in (16, 8, 0))
        for library in ("libpng", "libjpeg-turbo"):
            if native[library]:
                versions[library] = native[library].version
        report = {"references": versions, "results": []}
        for fixture in args.fixtures:
            result = compare_fixture(fixture.resolve(), candidate, baseline, magick, native, args.repetitions)
            report["results"].append(result)
            medians = ", ".join(f"{engine} {elapsed / 1000:.3f} ms" for engine, elapsed in result["median_us"].items())
            print(f"{fixture.name} {medians}", file=sys.stderr, flush=True)
            args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
