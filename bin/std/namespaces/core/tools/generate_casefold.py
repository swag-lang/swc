#!/usr/bin/env python3
"""Generate Core's full Unicode case-fold table from the Unicode 17 UCD input."""

from __future__ import annotations

import argparse
from pathlib import Path


MODULE_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = MODULE_ROOT / "tools/data/CaseFolding.txt"
DEFAULT_OUTPUT = MODULE_ROOT / "src/text/casefoldtables.swg"
EXPECTED_VERSION = "CaseFolding-17.0.0.txt"
MAX_MAPPING_LENGTH = 3


def parse_codepoints(value: str) -> list[int]:
    return [int(item, 16) for item in value.split()]


def read_mappings(source: Path) -> tuple[dict[int, list[int]], dict[int, list[int]]]:
    text = source.read_text(encoding="utf-8")
    if f"# {EXPECTED_VERSION}" not in text:
        raise ValueError(f"expected {EXPECTED_VERSION} in {source}")

    common: dict[int, list[int]] = {}
    full: dict[int, list[int]] = {}
    turkic: dict[int, list[int]] = {}
    for line in text.splitlines():
        record = line.split("#", 1)[0].strip()
        if not record:
            continue

        source_value, status, mapping, *_ = (part.strip() for part in record.split(";"))
        codepoint = int(source_value, 16)
        mapped = parse_codepoints(mapping)
        if len(mapped) > MAX_MAPPING_LENGTH:
            raise ValueError(f"mapping for U+{codepoint:04X} exceeds three code points")

        if status == "C":
            common[codepoint] = mapped
        elif status == "F":
            full[codepoint] = mapped
        elif status == "T":
            turkic[codepoint] = mapped

    mappings = common | full
    if not mappings or not turkic:
        raise ValueError(f"{source} contains no full or Turkic case-fold mappings")
    if not set(turkic).issubset(mappings):
        raise ValueError("every Turkic mapping must override a default full mapping")
    return mappings, turkic


def format_mapping(mapping: list[int]) -> str:
    padded = mapping + [0] * (MAX_MAPPING_LENGTH - len(mapping))
    values = ", ".join(f"0x{value:04X}" for value in padded)
    return f"[{values}]"


def render(mappings: dict[int, list[int]], turkic: dict[int, list[int]]) -> str:
    lines = [
        "// @LICENCE: Unicode-3.0",
        "// @ORIGIN: Unicode 17.0.0 CaseFolding.txt",
        "// @MODIFIED: Generated from the UCD input for Swag.",
        "// @NOTICE: /bin/std/modules/core/tools/data/NOTICE.md",
        "",
        "// Generated from tools/data/CaseFolding.txt by tools/generate_casefold.py.",
        "// Keep the mappings sorted by source code point.",
        "#global namespace Unicode",
        "#global internal",
        "",
        "const TableCaseFold: [?] CaseFoldMapping = [",
    ]
    for codepoint, mapping in sorted(mappings.items()):
        special = turkic.get(codepoint, mapping)
        lines.append(
            f"    CaseFoldMapping{{0x{codepoint:04X}, {format_mapping(mapping)}, "
            f"{len(mapping)}, {format_mapping(special)}, {len(special)}}},"
        )
    lines.extend(["]", ""])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    mappings, turkic = read_mappings(args.source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="\n") as output:
        output.write(render(mappings, turkic))
    print(f"generated {len(mappings)} full and {len(turkic)} Turkic mappings: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
