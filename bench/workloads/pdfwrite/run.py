import argparse
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import tempfile

import pypdfium2 as pdfium

parser = argparse.ArgumentParser()
parser.add_argument("--baseline", type=Path, required=True)
parser.add_argument("--candidate", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--cpu", type=int, required=True)
parser.add_argument("--batches", type=int, default=7)
parser.add_argument("--case", action="append", required=True)
parser.add_argument("--mode", action="append", choices=("encode", "save"))
args = parser.parse_args()
if args.batches < 1:
    parser.error("--batches must be positive")

executables = {"baseline": args.baseline, "candidate": args.candidate}

def raster_digests(path):
    digests = []
    with pdfium.PdfDocument(path) as doc:
        for i in range(len(doc)):
            page = doc[i]
            bitmap = page.render(scale=1.0)
            try:
                image = bitmap.to_pil()
                digests.append(hashlib.sha256(image.tobytes()).hexdigest())
            finally:
                bitmap.close()
                page.close()
    return digests


cases = []
with tempfile.TemporaryDirectory(prefix="pdfwrite-") as tmp:
    for case in args.case:
        print(f"Measuring {Path(case).name}", flush=True)
        for mode in args.mode or ("encode", "save"):
            timings = {key: [] for key in executables}
            output_files = {key: Path(tmp) / f"{key}.pdf" for key in executables}
            for batch in range(args.batches):
                order = list(executables) if batch % 2 == 0 else reversed(executables)
                for key in order:
                    cmd = ["taskset", "-c", str(args.cpu), str(executables[key]), case,
                           mode, "1", str(output_files[key])]
                    line = subprocess.check_output(cmd, text=True).strip().splitlines()[-1]
                    hz, ticks, size, crc32 = map(int, line.split())
                    timings[key].append({"ns": round(ticks * 10**9 / hz), "size": size, "crc32": crc32})
            rasters = {key: raster_digests(path) for key, path in output_files.items()} if mode == "save" else None
            same_raster = rasters["baseline"] == rasters["candidate"] if rasters else None
            if not all(len({(v["size"], v["crc32"]) for v in vals}) == 1 for vals in timings.values()):
                raise RuntimeError(f"{case} {mode} produces inconsistent output within one build")
            medians = {key: statistics.median(v["ns"] for v in vals) / 10**6
                       for key, vals in timings.items()}
            print(mode, medians, same_raster, flush=True)
            cases.append({"case": Path(case).name, "mode": mode, "median_ms": medians,
                          "samples": timings, "same_pdfium_raster": same_raster})

report = {"cpu": args.cpu, "pdfium": pdfium.PDFIUM_INFO.version,
          "batches": args.batches, "cases": cases}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, indent=2) + "\n")
