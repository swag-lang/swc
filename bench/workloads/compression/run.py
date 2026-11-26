"""Compare Core codecs and system libraries on the same files in memory."""

import argparse
from contextlib import ExitStack
import ctypes as c
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import tempfile
import time


POINTER = c.c_void_p
SIZE = c.c_size_t
INT = c.c_int
SIZE_PTR = c.POINTER(SIZE)
MIB = 1024 * 1024


@dataclass
class Reference:
    bound: object
    encode: object
    decode: object


def bind(library, symbol, result, *arguments):
    function = getattr(library, symbol)
    function.restype = result
    function.argtypes = arguments
    return function


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def references(resources):
    lz4 = c.CDLL("liblz4.so.1")
    lz4_bound = bind(lz4, "LZ4_compressBound", INT, INT)
    lz4_encode = bind(lz4, "LZ4_compress_default", INT, POINTER, POINTER, INT, INT)
    lz4_decode = bind(lz4, "LZ4_decompress_safe", INT, POINTER, POINTER, INT, INT)

    snappy = c.CDLL("libsnappy.so.1")
    snappy_bound = bind(snappy, "snappy_max_compressed_length", SIZE, SIZE)
    snappy_encode = bind(snappy, "snappy_compress", INT, POINTER, SIZE, POINTER, SIZE_PTR)
    snappy_decode = bind(snappy, "snappy_uncompress", INT, POINTER, SIZE, POINTER, SIZE_PTR)

    def snappy_call(operation, source, destination):
        size = SIZE(len(destination))
        require(operation(source, len(source), destination, c.byref(size)) == 0, "Snappy status")
        return size.value

    zlib = c.CDLL("libz.so.1")
    ulong = c.c_ulong
    ulong_ptr = c.POINTER(ulong)
    zlib_bound = bind(zlib, "compressBound", ulong, ulong)
    zlib_encode = bind(zlib, "compress2", INT, POINTER, ulong_ptr, POINTER, ulong, INT)
    zlib_decode = bind(zlib, "uncompress", INT, POINTER, ulong_ptr, POINTER, ulong)

    def zlib_call(operation, source, destination, *args):
        size = ulong(len(destination))
        require(operation(destination, c.byref(size), source, len(source), *args) == 0, "zlib status")
        return size.value

    zstd = c.CDLL("libzstd.so.1")
    zstd_bound = bind(zstd, "ZSTD_compressBound", SIZE, SIZE)
    zstd_encode = bind(zstd, "ZSTD_compress", SIZE, POINTER, SIZE, POINTER, SIZE, INT)
    zstd_decode = bind(zstd, "ZSTD_decompress", SIZE, POINTER, SIZE, POINTER, SIZE)

    def zstd_call(operation, source, destination, *args):
        size = operation(destination, len(destination), source, len(source), *args)
        require(size <= len(destination), "Zstandard status")
        return size

    lib = c.CDLL("libdeflate.so.0")
    compressor = bind(lib, "libdeflate_alloc_compressor", POINTER, INT)(6)
    require(compressor, "libdeflate compressor allocation")
    resources.callback(bind(lib, "libdeflate_free_compressor", None, POINTER), compressor)
    decompressor = bind(lib, "libdeflate_alloc_decompressor", POINTER)()
    require(decompressor, "libdeflate decompressor allocation")
    resources.callback(bind(lib, "libdeflate_free_decompressor", None, POINTER), decompressor)
    deflate_bound = bind(lib, "libdeflate_zlib_compress_bound", SIZE, POINTER, SIZE)
    deflate_encode = bind(lib, "libdeflate_zlib_compress", SIZE, POINTER, POINTER, SIZE, POINTER, SIZE)
    deflate_decode = bind(lib, "libdeflate_zlib_decompress", INT,
                          POINTER, POINTER, SIZE, POINTER, SIZE, SIZE_PTR)

    def decode_libdeflate(source, destination):
        written = SIZE()
        status = deflate_decode(decompressor, source, len(source), destination, len(destination), c.byref(written))
        require(status == 0, "libdeflate status")
        return written.value

    return {
        "lz4": Reference(lz4_bound, lambda src, dst: lz4_encode(src, dst, len(src), len(dst)),
                         lambda src, dst: lz4_decode(src, dst, len(src), len(dst))),
        "snappy": Reference(snappy_bound, lambda src, dst: snappy_call(snappy_encode, src, dst),
                            lambda src, dst: snappy_call(snappy_decode, src, dst)),
        "zlib1": Reference(zlib_bound, lambda src, dst: zlib_call(zlib_encode, src, dst, 1),
                           lambda src, dst: zlib_call(zlib_decode, src, dst)),
        "zlib6": Reference(zlib_bound, lambda src, dst: zlib_call(zlib_encode, src, dst, 6),
                           lambda src, dst: zlib_call(zlib_decode, src, dst)),
        "zstd1": Reference(zstd_bound, lambda src, dst: zstd_call(zstd_encode, src, dst, 1),
                           lambda src, dst: zstd_call(zstd_decode, src, dst)),
        "libdeflate6": Reference(lambda size: deflate_bound(compressor, size),
                                 lambda src, dst: deflate_encode(compressor, src, len(src), dst, len(dst)),
                                 decode_libdeflate),
    }


def measure(reference, source, size, rounds, samples):
    destination = c.create_string_buffer(size)
    written = reference(source, destination)
    require(0 < written <= size, "reference codec returned an invalid byte count")
    times = []
    for _ in range(samples):
        start = time.process_time_ns()
        for _ in range(rounds):
            written = reference(source, destination)
        times.append((time.process_time_ns() - start) / rounds)
    return destination.raw[:written], times


def run_swag(builds, codec, direction, source, output, size, rounds, samples):
    times = {label: [] for label, _ in builds}
    results = {}
    for sample in range(samples):
        order = builds if sample % 2 == 0 else reversed(builds)
        for label, program in order:
            command = [program, codec, direction, source, output, str(rounds), str(size)]
            elapsed = int(subprocess.check_output(command, cwd=output.parent))
            times[label].append(elapsed / rounds)
            if sample == samples - 1:
                results[label] = output.read_bytes()
    return {label: (results[label], times[label]) for label, _ in builds}


def record(packed, encode, decode):
    return {"packed_bytes": len(packed), "packed_sha256": hashlib.sha256(packed).hexdigest(),
            "encode_ns": encode, "decode_ns": decode}


def benchmark(path, args, libraries, work):
    data = path.read_bytes()
    size = len(data)
    require(0 < size <= 0x7E000000, f"unsupported benchmark input size in {path}")
    rounds = max(3, args.batch_mib * MIB // size)
    result = {"input": str(path), "input_bytes": size, "input_sha256": hashlib.sha256(data).hexdigest(), "codecs": {}}
    output = work / "output"
    reference_file = work / "reference"

    for codec, library in libraries.items():
        ref_packed, encode = measure(library.encode, data, library.bound(size), rounds, args.samples)
        ref_plain, decode = measure(library.decode, ref_packed, size, rounds, args.samples)
        require(ref_plain == data, f"{codec} reference round-trip on {path}")
        result["codecs"][f"reference/{codec}"] = record(ref_packed, encode, decode)

        if codec in {"zstd1", "libdeflate6"}:
            continue
        reference_file.write_bytes(ref_packed)
        builds = [("swag", args.swag)]
        if args.baseline and codec in args.baseline_codecs:
            builds.insert(0, ("baseline", args.baseline))
        encoded = run_swag(builds, codec, "encode", path, output, size, rounds, args.samples)
        decoded = run_swag(builds, codec, "decode", reference_file, output, size, rounds, args.samples)
        for label, (packed, encode) in encoded.items():
            destination = c.create_string_buffer(size)
            written = library.decode(packed, destination)
            require(written == size and destination.raw == data, f"{label}/{codec} to reference on {path}")
            plain, decode = decoded[label]
            require(plain == data, f"reference to {label}/{codec} on {path}")
            result["codecs"][f"{label}/{codec}"] = record(packed, encode, decode)

    return result


def summarize(files):
    size = sum(row["input_bytes"] for row in files)
    print(f"{'Codec':<24} {'Size %':>8} {'Encode MiB/s':>14} {'Decode MiB/s':>14}")
    for name in files[0]["codecs"]:
        rows = [row["codecs"][name] for row in files]
        packed = sum(row["packed_bytes"] for row in rows)
        rates = [size * 1e9 / (MIB * sum(statistics.median(row[key]) for row in rows))
                 for key in ("encode_ns", "decode_ns")]
        print(f"{name:<24} {packed / size:8.2%} {rates[0]:14.1f} {rates[1]:14.1f}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swag", type=Path, required=True)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--baseline-codec", action="append", choices=("lz4", "snappy", "zlib1", "zlib6"),
                        dest="baseline_codecs", help="format available in the baseline executable (repeatable)")
    parser.add_argument("--scratch", type=Path, required=True)
    parser.add_argument("--json", type=Path)
    parser.add_argument("--samples", type=int, default=5)
    parser.add_argument("--batch-mib", type=int, default=4)
    parser.add_argument("inputs", type=Path, nargs="+")
    args = parser.parse_args()
    if args.samples < 1 or args.batch_mib < 1:
        parser.error("--samples and --batch-mib must be positive")
    if args.baseline_codecs is None:
        args.baseline_codecs = ("zlib1", "zlib6")
    args.swag = args.swag.resolve(strict=True)
    if args.baseline:
        args.baseline = args.baseline.resolve(strict=True)

    with ExitStack() as resources:
        work = Path(resources.enter_context(tempfile.TemporaryDirectory(dir=args.scratch.resolve())))
        libraries = references(resources)
        files = [benchmark(path.resolve(strict=True), args, libraries, work) for path in args.inputs]
    if args.json:
        args.json.write_text(json.dumps(files, indent=2) + "\n", encoding="utf-8")
    summarize(files)


if __name__ == "__main__":
    main()
