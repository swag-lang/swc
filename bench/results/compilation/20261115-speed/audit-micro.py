"""Compare complete Micro bodies in a saved microdiff.py capture directory.

Usage: python3 audit-micro.py /absolute/path/to/capture
Only the metadata described in this report is normalized. Any remaining body
change, including a changed instruction with equal counts, fails the audit.
"""

import argparse
import collections
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts"))
import microdiff


GENERATED_NAMES = (
    re.compile(r"Swag\.runWork\.__lambda_[0-9a-f]{16}"),
    re.compile(r"__run_expr_[0-9a-f]{16}"),
)


def collect(path):
    listing = path.read_text(encoding="utf-8")
    functions = microdiff.parse(listing)
    families = collections.defaultdict(collections.Counter)
    metadata = []
    locations = {}
    for block in listing.split("[micro]"):
        name = re.search(r"^  function : (.*)$", block, re.M)
        location = re.search(r"^  location : (.*)$", block, re.M)
        if name and location:
            locations[name.group(1)] = location.group(1)

    generated_names = {}
    for name, location in locations.items():
        if any(pattern.fullmatch(name) for pattern in GENERATED_NAMES):
            relative_location = re.search(r"/runtime/[^:]+:\d+$", location)
            if not relative_location:
                raise ValueError(f"Unexpected generated-function source: {name}: {location}")
            stem = re.sub(r"_[0-9a-f]{16}$", "", name)
            generated_names[name] = stem + "_AT_" + relative_location.group(0).lstrip("/")

    def normalize_names(text):
        for name, family in generated_names.items():
            text = text.replace(name, family)
        return text

    for name, body in functions.items():
        plain = re.sub(r"#\d+$", "", name)
        family = normalize_names(plain)
        lines = [normalize_names(line) for line in microdiff.normalized(body)]
        if plain.startswith("__run_expr_") and locations.get(plain, "").endswith("/runtime/core.swg:669"):
            for index, line in enumerate(lines):
                if not re.fullmatch(r"load_reg_imm rsi, b64, 0x[0-9A-Fa-f]+", line):
                    continue
                if not index or not lines[index - 1].startswith("load_reg_ptr_imm rdi, b64, "):
                    continue
                # persistCompilerRunValue's second SysV argument is rawTypeRef.
                # Verify every other argument, including the R9 allocation size.
                call = next((offset for offset in range(index + 1, min(index + 9, len(lines)))
                             if lines[offset] == "call_indirect r10, sysv64"), None)
                setup = lines[index + 1:call] if call is not None else []
                required = {
                    "load_reg_reg rcx, rax, b64",
                    "load_addr_reg_mem r8, [rsp + 0x8], b64",
                    "load_reg_imm r9, b64, 0x20",
                    "clear_reg rax, b32",
                }
                return_buffers = {"load_reg_reg rdx, r12, b64", "load_reg_reg rdx, rbx, b64"}
                if call is None or not required.issubset(setup) or not return_buffers.intersection(setup):
                    raise ValueError(f"Unexpected persistCompilerRunValue argument setup in {path}: {name}")
                metadata.append({"name": name, "type_ref": line, "location": locations[plain]})
                # All setup instructions remain in the complete sequence comparison.
                lines[index] = "load_reg_imm rsi, b64, TYPE_REF"
        families[family][tuple(lines)] += 1
    return families, metadata, len(functions)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path, help="microdiff.py output containing base/ and new/")
    root = parser.parse_args().capture
    tasks = sorted(path.name for path in (root / "base").iterdir() if path.is_dir())
    new_tasks = sorted(path.name for path in (root / "new").iterdir() if path.is_dir())
    if not tasks or tasks != new_tasks:
        raise ValueError("Both roles must contain the same nonempty task set")
    report = []
    failed = False
    for task in tasks:
        base, base_metadata, base_count = collect(root / "base" / task / "micro.txt")
        new, new_metadata, new_count = collect(root / "new" / task / "micro.txt")
        differences = []
        for family in sorted(base.keys() | new.keys()):
            if base[family] == new[family]:
                continue
            differences.append(family)
            print(task, family)
            for label, bodies in (("BASE", base[family] - new[family]), ("NEW", new[family] - base[family])):
                for body, count in bodies.items():
                    print(label, count, "\n".join(body), sep="\n")
        report.append({"task": task, "base_functions": base_count, "new_functions": new_count,
                       "differing_families": differences, "base_metadata": base_metadata,
                       "new_metadata": new_metadata})
        failed |= bool(differences)
        print(task, "FAIL" if differences else "PASS", base_count, new_count, flush=True)
    (root / "instruction-audit.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
