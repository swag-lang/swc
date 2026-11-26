"""Benchmark native Swag Core and byte-equivalent library calls with a fixed Linux CPU affinity."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from stats import estimate, paired_ratio

REFERENCES = {
    "adler32": {"libdeflate": "adler32-libdeflate", "zlib": "adler32-zlib"},
    "crc32": {"libdeflate": "crc32-libdeflate", "zlib": "crc32-zlib"},
    "crc64-ecma": {"ISA-L": "crc64-ecma"},
    "crc64-iso": {"ISA-L": "crc64-iso"},
    "crc64-xz": {"ISA-L": "crc64-xz", "liblzma": "crc64-xz-liblzma"},
    "md5": {"OpenSSL": "md5"},
    "sha1": {"OpenSSL": "sha1"},
    "sha224": {"OpenSSL": "sha224"},
    "sha256": {"OpenSSL": "sha256"},
    "sha384": {"OpenSSL": "sha384"},
    "sha512": {"OpenSSL": "sha512"},
    "sha3-256": {"OpenSSL": "sha3-256"},
    "blake2b-512": {"OpenSSL": "blake2b-512"},
    "blake2s-256": {"OpenSSL": "blake2s-256"},
    "blake3": {"BLAKE3 C": "blake3"},
    "poly1305": {"OpenSSL": "poly1305"},
    "chacha20": {"OpenSSL": "chacha20"},
    "chacha20-poly1305": {"OpenSSL": "chacha20-poly1305"},
    "aes-256-ctr": {"OpenSSL": "aes-256-ctr"},
    "aes-256-gcm": {"OpenSSL": "aes-256-gcm"},
    "aes-256-gcm-aad": {"OpenSSL": "aes-256-gcm-aad"},
    "aes-256-ccm": {"OpenSSL": "aes-256-ccm"},
    "aes-256-xts-encrypt": {"OpenSSL": "aes-256-xts-encrypt"},
    "aes-256-xts-decrypt": {"OpenSSL": "aes-256-xts-decrypt"},
}
DEFAULT_ALGORITHMS = tuple(REFERENCES)
BLAKE2_REFERENCES = {
    "blake2b-512": {"libb2": "blake2b-libb2", "libsodium": "blake2b-libsodium"},
    "blake2s-256": {"libb2": "blake2s-libb2"},
}
REFERENCES.update({name: {"OpenSSL": name} for name in ("hmac-sha384", "hmac-sha512")})
PUBLIC_KEY_SIZES = {
    "x25519-public": (32,),
    "x25519-shared": (32,),
    "ed25519-public": (32,),
    "ed25519-sign": (64, 4096),
    "p256-public": (32,),
    "p256-sign": (64, 4096),
}
HKDF_DIGEST_BYTES = {f"hkdf-sha{bits}": bits // 8 for bits in (224, 256, 384, 512)}
HKDF_SIZES = {name: (size, 4 * size, 32 * size, 255 * size)
              for name, size in HKDF_DIGEST_BYTES.items()}
OPERATION_SIZES = {**PUBLIC_KEY_SIZES, **HKDF_SIZES}
REFERENCES.update({name: {"OpenSSL": name} for name in OPERATION_SIZES})


def program(value):
    label, separator, filename = value.partition("=")
    if not separator or not label or not filename:
        raise argparse.ArgumentTypeError("use LABEL=PATH")
    executable = Path(filename).resolve()
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise argparse.ArgumentTypeError(f"cannot execute {executable}")
    return label, executable


def worker_count(value):
    label, separator, text = value.partition("=")
    try:
        count = int(text)
    except ValueError:
        count = 0
    if not separator or not label or not 0 < count <= 0xFFFFFFFF:
        raise argparse.ArgumentTypeError("use LABEL=COUNT with a positive 32-bit worker count")
    return label, count


def invoke(runner, fixture, output, iterations, offset):
    executable, algorithm, workers = runner
    output.unlink(missing_ok=True)
    command = [executable, algorithm, fixture, output, str(iterations), str(offset)]
    environment = {**os.environ, "SWAG_RUNTIME_THREADS": str(workers)}
    try:
        stdout = subprocess.check_output(command, text=True, timeout=120, env=environment)
    except subprocess.CalledProcessError as error:
        raise RuntimeError(f"{executable} exited with status {error.returncode}\n{error.output}") from error
    wall, cpu, frequency = map(int, stdout.split())
    if wall < 0 or cpu < 0 or frequency <= 0:
        raise RuntimeError(f"invalid clock result from {executable}")
    return {"wall": wall / frequency, "cpu": cpu / frequency}, output.read_bytes()


def require_output(result, expected, label, algorithm, size, offset):
    if result != expected:
        position = next((i for i, pair in enumerate(zip(result, expected))
                         if pair[0] != pair[1]), min(len(result), len(expected)))
        raise RuntimeError(f"{label} differs for {algorithm}, size {size}, offset {offset}, "
                           f"output byte {position} (lengths {len(result)}, {len(expected)})")


def compare(work, name, size, offset, runners, rounds, target_ms, clock, verify_only, order):
    fixture, output = work / "input.bin", work / "output.bin"
    source = random.Random(0x5A6D_2026).randbytes(size + offset)
    fixture.write_bytes(source)
    reference = next(iter(runners.values()))
    _, expected = invoke(reference, fixture, output, 1, offset)
    samples = {}
    for label, runner in runners.items():
        elapsed, result = invoke(runner, fixture, output, 1, offset)
        require_output(result, expected, label, name, size, offset)
        if not verify_only:
            # Bring the calibration itself above timer noise before choosing the fixed sample size.
            probe = max(1, min(10_000_000, int(0.005 / max(elapsed[clock], 1e-9))))
            elapsed, result = invoke(runner, fixture, output, probe, offset)
            require_output(result, expected, label, name, size, offset)
            samples[label] = {"iterations": max(1, min(10_000_000,
                             round(probe * target_ms / (1000 * max(elapsed[clock], 1e-9))))),
                             "wall": [], "cpu": []}

    paired_order = []
    if not verify_only:
        for _ in range(rounds):
            labels = list(runners)
            order.shuffle(labels)
            paired_order.append(labels)
            for label in labels:
                runner = runners[label]
                series = samples[label]
                elapsed, result = invoke(runner, fixture, output,
                                         series["iterations"], offset)
                require_output(result, expected, label, name, size, offset)
                if elapsed[clock] <= 0:
                    raise RuntimeError(f"clock resolution too low for {label}, {name}")
                for clock_name, seconds in elapsed.items():
                    series[clock_name].append(seconds)
    return {"algorithm": name, "bytes": size, "offset": offset,
            "input_sha256": hashlib.sha256(source[offset:]).hexdigest(),
            "output_sha256": hashlib.sha256(expected).hexdigest(),
            "samples": samples, "round_order": paired_order}


def summarize(rows, swag_labels, clock):
    lines = ["| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | "
             "Comparator rate | Paired speed ratio (95% CI) |",
             "| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |"]
    for row in rows:
        operation_rate = row["algorithm"] in OPERATION_SIZES
        unit, scale = ("ops/s", 1) if operation_rate else ("GB/s", row["bytes"] / 1e9)
        rates = {label: [scale * series["iterations"] / elapsed
                        for elapsed in series[clock]]
                 for label, series in row["samples"].items()}
        if not rates:
            continue
        reference = max((label for label in rates if label not in swag_labels),
                        key=lambda label: estimate(rates[label]).value)
        reference_rate = estimate(rates[reference]).value
        for label in swag_labels:
            ratio = paired_ratio(rates[label], rates[reference])
            lines.append(f"| {row['algorithm']} | {row['bytes']} | {row['offset']} | "
                         f"{label} | {reference} | {unit} | {estimate(rates[label]).value:.3g} | "
                         f"{reference_rate:.3g} | {ratio.value:.3g} "
                         f"[{ratio.low:.3g}, {ratio.high:.3g}] |")
            if label == swag_labels[0]:
                continue
            baseline = swag_labels[0]
            gain = paired_ratio(rates[label], rates[baseline])
            lines.append(f"| {row['algorithm']} | {row['bytes']} | {row['offset']} | "
                         f"{label} | {baseline} | {unit} | {estimate(rates[label]).value:.3g} | "
                         f"{estimate(rates[baseline]).value:.3g} | {gain.value:.3g} "
                         f"[{gain.low:.3g}, {gain.high:.3g}] |")
    return "\n".join(lines) + "\n"


def cpu_features():
    record = {}
    for line in Path("/proc/cpuinfo").read_text().split("\n\n", 1)[0].splitlines():
        key, separator, value = line.partition(":")
        if separator and key.strip() in ("model name", "flags", "microcode"):
            record[key.strip()] = value.strip()
    return record


def main(references=REFERENCES, default_algorithms=DEFAULT_ALGORITHMS):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swag", action="append", type=program, required=True,
                        help="LABEL=PATH, with baseline first when comparing multiple Swag builds")
    parser.add_argument("--reference", required=True, type=lambda value: Path(value).resolve())
    parser.add_argument("--cpu", action="append", type=int, required=True,
                        help="CPU in the common affinity mask, repeat to allow several CPUs")
    parser.add_argument("--workers", action="append", type=worker_count, default=[],
                        help="LABEL=COUNT for one Swag build, defaults to one worker")
    parser.add_argument("--algorithm", action="append", choices=references)
    parser.add_argument("--blake2-references", action="store_true",
                        help="include libb2 and libsodium with a matching reference build")
    parser.add_argument("--size", action="append", type=int)
    parser.add_argument("--offset", action="append", type=int)
    parser.add_argument("--rounds", type=int, default=11)
    parser.add_argument("--target-ms", type=int, default=50)
    parser.add_argument("--clock", choices=("cpu", "wall"), default="cpu")
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--scratch", type=Path, required=True, help="existing external scratch directory")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--markdown", type=Path)
    args = parser.parse_args()
    if args.blake2_references:
        references = {name: {**libraries, **BLAKE2_REFERENCES.get(name, {})}
                      for name, libraries in references.items()}

    algorithms = args.algorithm or default_algorithms
    offsets = args.offset or [0]
    sizes = {name: args.size or OPERATION_SIZES.get(name, (64, 4096, 65536, 1048576))
             for name in algorithms}
    labels = [label for label, _ in args.swag]
    if (len(set(labels)) != len(labels) or
        any(label in refs for refs in references.values() for label in labels)):
        parser.error("Swag labels must be unique and distinct from reference labels")
    requested_workers = dict(args.workers)
    if len(requested_workers) != len(args.workers) or any(label not in labels for label in requested_workers):
        parser.error("worker counts must name distinct Swag build labels")
    workers = {label: requested_workers.get(label, 1) for label in labels}
    if any(size < 0 or (size == 0 and not args.verify_only)
           for row in sizes.values() for size in row):
        parser.error("sizes must be positive for timing and nonnegative for verification")
    for name in PUBLIC_KEY_SIZES:
        if name in sizes and not name.endswith("-sign") and any(size != 32 for size in sizes[name]):
            parser.error(f"{name} requires a 32-byte input")
    for name, digest_bytes in HKDF_DIGEST_BYTES.items():
        if name in sizes and any(size > 255 * digest_bytes for size in sizes[name]):
            parser.error(f"{name} output exceeds 255 digest blocks")
    for name in ("aes-256-xts-encrypt", "aes-256-xts-decrypt"):
        if name in sizes and any(not 16 <= size <= 1 << 24 for size in sizes[name]):
            parser.error(f"{name} requires a 16-byte to 16-MiB data unit")
    if "aes-256-ccm" in sizes and any(size >= 1 << 24 for size in sizes["aes-256-ccm"]):
        parser.error("aes-256-ccm requires a payload below 16 MiB with its 12-byte nonce")
    if any(offset < 0 for offset in offsets):
        parser.error("offsets must be nonnegative")
    if args.rounds < 6 or args.target_ms < 1:
        parser.error("timed campaigns need at least six positive-duration rounds")
    affinity = list(dict.fromkeys(args.cpu))
    if not set(affinity).issubset(os.sched_getaffinity(0)):
        parser.error("CPU is outside the current affinity mask")
    os.sched_setaffinity(0, set(affinity))

    version = subprocess.check_output([args.reference, "--version"], text=True).strip()
    report = {"utc": datetime.now(timezone.utc).isoformat(), "system": platform.platform(),
              "cpu": affinity[0], "affinity": affinity, "workers": workers,
              "processor": cpu_features(), "reference_build": version,
              "reference_sha256": hashlib.sha256(args.reference.read_bytes()).hexdigest(),
              "swag_builds": {label: hashlib.sha256(executable.read_bytes()).hexdigest()
                              for label, executable in args.swag},
              "rounds": 0 if args.verify_only else args.rounds,
              "target_ms": args.target_ms, "clock": args.clock, "rows": []}
    order = random.Random(0xC0DEC0DE)
    with tempfile.TemporaryDirectory(dir=args.scratch, prefix="crypto-") as directory:
        for name in algorithms:
            runners = {label: (args.reference, algorithm, 1)
                       for label, algorithm in references[name].items()}
            runners.update({label: (executable, name, workers[label]) for label, executable in args.swag})
            for size in sizes[name]:
                for offset in offsets:
                    row = compare(Path(directory), name, size, offset, runners, args.rounds,
                                  args.target_ms, args.clock, args.verify_only, order)
                    report["rows"].append(row)
            print(f"Verified {name} ({len(sizes[name]) * len(offsets)} inputs)", flush=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if args.markdown:
        args.markdown.write_text(summarize(report["rows"], labels, args.clock), encoding="utf-8")


if __name__ == "__main__":
    main()
