#!/usr/bin/env python3
"""Make a three-member Arabic TTC whose broken middle cmap leaves both neighbors readable."""

from __future__ import annotations

import argparse
import struct
import tempfile
from pathlib import Path

from fontTools.ttLib import TTCollection, TTFont


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--regular", type=Path, required=True)
    parser.add_argument("--collection", type=Path, required=True,
                        help="the generated Arabic TTC whose face 2 supplies Bold")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="swagscope-partial-ttc-") as temporary:
        bold_path = Path(temporary) / "bold.ttf"
        bold = TTFont(args.collection, fontNumber=1, recalcTimestamp=False)
        bold.save(bold_path)
        bold.close()

        collection = TTCollection()
        collection.fonts = [
            TTFont(args.regular, recalcTimestamp=False),
            TTFont(args.regular, recalcTimestamp=False),
            TTFont(bold_path, recalcTimestamp=False),
        ]
        collection.save(args.output)
        for font in collection.fonts:
            font.close()

    data = bytearray(args.output.read_bytes())
    if data[:4] != b"ttcf":
        raise RuntimeError("fontTools did not produce a TTC")
    count = struct.unpack_from(">I", data, 8)[0]
    if count != 3:
        raise RuntimeError(f"expected 3 faces, got {count}")
    middle = struct.unpack_from(">I", data, 12 + 4)[0]
    # Invalidate only the middle member's scaler signature. The collection directory remains
    # enumerable and Face.loadAt rejects the member before it allocates or reads any tables.
    data[middle : middle + 4] = b"BAD!"
    args.output.write_bytes(data)


if __name__ == "__main__":
    main()
