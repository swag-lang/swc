"""Compare Swag RSA with OpenSSL EVP on the same pinned Linux CPU."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import struct
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "crypto"))
from run import invoke, program
from stats import estimate, paired_ratio


def sample_row(fixture, output, operation, engines, rounds, rng):
    file = fixture.read_bytes()
    width, message_length, exponent_length = struct.unpack_from("<III", file)
    message_offset = 12 + 4 * width + exponent_length
    message = file[message_offset:message_offset + message_length]
    expected = b"\x01" if operation == "rsa-pss-verify" else message
    samples = {}
    for label, runner in engines.items():
        times, value = invoke(runner, fixture, output, 1, 0)
        if value != expected:
            raise ValueError(f"{fixture.name}, {operation}, {label}: exact output mismatch")
        samples[label] = {"iterations": max(1, min(10000, round(0.025 / times["cpu"]))),
                          "cpu": [], "wall": []}

    order = []
    for _ in range(rounds):
        labels = list(engines)
        rng.shuffle(labels)
        order.append(labels)
        for label in labels:
            sample = samples[label]
            times, value = invoke(engines[label], fixture, output, sample["iterations"], 0)
            if value != expected:
                raise ValueError(f"{fixture.name}, {operation}, {label}: exact output mismatch")
            for clock in ("cpu", "wall"):
                sample[clock].append(times[clock])

    return {"operation": operation, "bits": width * 8, "message_bytes": message_length,
            "fixture_sha256": hashlib.sha256(file).hexdigest(),
            "output_sha256": hashlib.sha256(expected).hexdigest(),
            "samples": samples, "round_order": order}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swag", action="append", type=program, required=True,
                        help="LABEL=PATH, baseline first")
    parser.add_argument("--openssl", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, action="append", required=True)
    parser.add_argument("--cpu", type=int, required=True)
    parser.add_argument("--rounds", type=int, default=13)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--markdown", type=Path, required=True)
    args = parser.parse_args()
    if args.rounds < 6 or len(args.swag) < 2:
        parser.error("provide at least six rounds and two Swag builds")
    os.sched_setaffinity(0, {args.cpu})
    rng = random.Random(0x5253412026)
    rows = []
    with tempfile.TemporaryDirectory(prefix="rsa-comparison-") as directory:
        output = Path(directory) / "output.bin"
        for fixture in args.fixture:
            for operation in ("rsa-pss-verify", "rsa-oaep-decrypt"):
                engines = {label: (path, operation, 1) for label, path in args.swag}
                engines["OpenSSL"] = (args.openssl.resolve(), operation, 1)
                if operation == "rsa-oaep-decrypt":
                    engines["OpenSSL d-only"] = (args.openssl.resolve(), operation + "-d-only", 1)
                rows.append(sample_row(fixture, output, operation, engines, args.rounds, rng))
                print(f"Verified {fixture.name} {operation}", flush=True)

    args.output.write_text(json.dumps({"cpu": args.cpu, "rounds": args.rounds, "rows": rows},
                                      indent=2) + "\n")
    lines = ["| Operation | Key bits | Swag build | Ops/s | OpenSSL ops/s | OpenSSL d-only ops/s | Speed over initial (95% CI) |",
             "| --- | ---: | --- | ---: | ---: | ---: | ---: |"]
    initial = args.swag[0][0]
    for row in rows:
        rates = {label: [sample["iterations"] / seconds for seconds in sample["cpu"]]
                 for label, sample in row["samples"].items()}
        openssl = estimate(rates["OpenSSL"]).value
        direct = f"{estimate(rates['OpenSSL d-only']).value:.4g}" if "OpenSSL d-only" in rates else "—"
        for label, _ in args.swag:
            gain = paired_ratio(rates[label], rates[initial])
            interval = f"{gain.value:.3g} [{gain.low:.3g}, {gain.high:.3g}]" if label != initial else "—"
            lines.append(f"| {row['operation']} | {row['bits']} | {label} | {estimate(rates[label]).value:.4g} | "
                         f"{openssl:.4g} | {direct} | {interval} |")
    args.markdown.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
