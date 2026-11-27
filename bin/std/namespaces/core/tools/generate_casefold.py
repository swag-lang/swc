#!/usr/bin/env python3
"""Generate Core's full Unicode case-fold table from the Unicode 17 UCD input."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
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


@dataclass(frozen=True)
class FoldRange:
    first: int
    last: int
    data: int
    turkic: int
    stride_mask: int
    expands: bool


def pack_mappings(
    mappings: dict[int, list[int]], turkic: dict[int, list[int]]
) -> tuple[list[FoldRange], list[list[int]]]:
    sources = sorted(mappings)
    ranges: list[FoldRange] = []
    expansions: list[list[int]] = []
    expansion_indices: dict[tuple[int, ...], int] = {}

    def index_expansion(mapping: list[int]) -> int:
        key = tuple(mapping)
        index = expansion_indices.get(key)
        if index is None:
            index = len(expansions)
            expansions.append(mapping)
            expansion_indices[key] = index
        return index

    index = 0
    while index < len(sources):
        first = sources[index]
        index += 1
        mapping = mappings[first]
        expands = len(mapping) != 1
        data = index_expansion(mapping) if expands else mapping[0] - first
        alternate = index_expansion(turkic[first]) + 1 if first in turkic else 0

        last = first
        step = 1
        if not expands and not alternate and index < len(sources):
            gap = sources[index] - first
            # A gap of two covers alternating uppercase and lowercase code points.
            if gap in (1, 2):
                while index < len(sources):
                    current = sources[index]
                    if current != last + gap or current in turkic or mappings[current] != [current + data]:
                        break
                    last = current
                    step = gap
                    index += 1
        ranges.append(FoldRange(first, last, data, alternate, step - 1, expands))

    if len(expansions) > 0xFFFF:
        raise ValueError("case-fold expansions exceed the runtime index width")
    return ranges, expansions


def render(mappings: dict[int, list[int]], turkic: dict[int, list[int]]) -> str:
    ranges, expansions = pack_mappings(mappings, turkic)
    lines = [
        "// @LICENCE: Unicode-3.0",
        "// @ORIGIN: Unicode 17.0.0 CaseFolding.txt",
        "// @MODIFIED: Generated from the UCD input for Swag.",
        "// @NOTICE: /bin/std/namespaces/core/tools/data/NOTICE.md",
        "",
        "// Generated from tools/data/CaseFolding.txt by tools/generate_casefold.py.",
        "// Keep the ranges sorted by their first source code point.",
        "#global namespace Unicode",
        "#global internal",
        "",
        "const TableCaseFold: [?] CaseFoldRange = [",
    ]
    for entry in ranges:
        lines.append(
            f"    CaseFoldRange{{0x{entry.first:04X}, 0x{entry.last:04X}, {entry.data}, "
            f"{entry.turkic}, {entry.stride_mask}, {str(entry.expands).lower()}}},"
        )

    lines.extend(["]", "", "const TableCaseFoldExpansions: [?] CaseFoldExpansion = ["])
    for mapping in expansions:
        lines.append(f"    CaseFoldExpansion{{{format_mapping(mapping)}, {len(mapping)}}},")
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
