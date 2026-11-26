import argparse
from pathlib import Path
import itertools
import json
import os
import random
import statistics
import subprocess
import sys

suite = Path(__file__).resolve()
sys.path.insert(0, str(suite.parents[3] / "scripts"))
from stats import paired_ratio

parser = argparse.ArgumentParser(description="Compare the BLAKE3 leaf compression kernel at SIMD widths 4 and 8")
parser.add_argument("--binary", type=Path, required=True)
parser.add_argument("--cpu", type=int, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
os.sched_setaffinity(0, {args.cpu})
program = args.binary.resolve()
algorithms = ("sse4", "avx4", "avx8", "official")

def run(algorithm, chunks, iterations, offset=0, flag=0):
    command = [str(program), algorithm, *map(str, (chunks, iterations, offset, flag))]
    cpu, wall, width = map(int, subprocess.check_output(command, text=True, timeout=30).split())
    return {"cpu": cpu, "wall": wall, "official_width": width}

fixtures = list(itertools.product((8, 16, 24, 64, 1024), (0, 1, 15), (0, 16)))
for chunks, offset, flag in fixtures:
    for algorithm in algorithms:
        run(algorithm, chunks, 1, offset, flag)
print(f"{len(fixtures)} byte-equal fixtures across all four builds", flush=True)

rounds = 11
target = 20e6
rng = random.Random(20261126)
rows = []
for chunks in (8, 64, 1024, 8192, 32768):
    loops = {algorithm: max(1, round(target / run(algorithm, chunks, 3)["cpu"] * 3))
             for algorithm in algorithms}
    samples = {algorithm: [] for algorithm in algorithms}
    order = list(algorithms)
    for _ in range(rounds):
        rng.shuffle(order)
        for algorithm in order:
            samples[algorithm].append(run(algorithm, chunks, loops[algorithm]))
    rates = {algo: [chunks * 1024 * loops[algo] / sample["cpu"] for sample in observations]
             for algo, observations in samples.items()}
    sizes = ", ".join(f"{a}={statistics.median(rates[a]):.3f}" for a in algorithms)
    delta = paired_ratio(rates["avx8"], rates["avx4"])
    print(f"{chunks * 1024} bytes {sizes}; AVX2 8/4 {delta!r}", flush=True)
    rows.append({"chunks": chunks, "loops": loops, "samples": samples})
args.output.write_text(json.dumps(
    {"affinity": [args.cpu], "rounds": rounds, "target_ms": 20, "verified_fixtures": len(fixtures), "rows": rows},
    indent=2) + "\n")
