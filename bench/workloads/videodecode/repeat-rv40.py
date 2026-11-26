"""Repeat the checked-in RealVideo I/P/B stream without re-encoding its packets."""

import argparse
from pathlib import Path
import struct


REPO = Path(__file__).resolve().parents[3]
FIXTURE = REPO / "bin/std/modules/video/src/tests/datas/rv40-ipb.mkv"
FIXTURE_DURATION = 360  # Nine pictures at 25 fps and a Matroska time scale of one millisecond.
EBML, SEGMENT = 0x1A45DFA3, 0x18538067
INFO, TRACKS, CLUSTER = 0x1549A966, 0x1654AE6B, 0x1F43B675
DURATION, CLUSTER_TIME = 0x4489, 0xE7
CLUSTER_INDEX_FIELDS = (0xBF, 0xAB, 0xA7)  # CRC-32, previous size and position.


def elements(data):
    at = 0
    while at < len(data):
        first = data[at]
        if not first:
            raise ValueError("invalid Matroska element ID")
        width = 9 - first.bit_length()
        identifier = int.from_bytes(data[at:at + width], "big")
        at += width
        if at >= len(data) or not data[at]:
            raise ValueError("missing Matroska element size")
        width = 9 - data[at].bit_length()
        limit = (1 << (7 * width)) - 1
        size = int.from_bytes(data[at:at + width], "big") & limit
        at += width
        end = len(data) if size == limit else at + size
        if at > end or end > len(data):
            raise ValueError(f"incomplete Matroska element {identifier:#x}")
        yield identifier, data[at:end]
        at = end


def integer(value):
    return value.to_bytes(max(1, (value.bit_length() + 7) // 8), "big")


def element(identifier, payload):
    size = len(payload)
    width = next(width for width in range(1, 9) if size < (1 << (7 * width)) - 1)
    return integer(identifier) + ((1 << (7 * width)) | size).to_bytes(width, "big") + payload


def repeat(copies):
    headers = dict(elements(FIXTURE.read_bytes()))
    segment = list(elements(headers[SEGMENT]))
    parts = []
    clusters = []
    for identifier, payload in segment:
        if identifier == INFO:
            duration = struct.pack(">d", copies * FIXTURE_DURATION)
            info = b"".join(element(key, duration if key == DURATION else value)
                            for key, value in elements(payload))
            parts.append(element(INFO, info))
        elif identifier == TRACKS:
            parts.append(element(TRACKS, payload))
        elif identifier == CLUSTER:
            clusters.append(list(elements(payload)))

    for copy in range(copies):
        for cluster in clusters:
            fields = []
            for identifier, payload in cluster:
                if identifier == CLUSTER_TIME:
                    time = int.from_bytes(payload, "big") + copy * FIXTURE_DURATION
                    payload = integer(time)
                if identifier not in CLUSTER_INDEX_FIELDS:
                    fields.append(element(identifier, payload))
            parts.append(element(CLUSTER, b"".join(fields)))
    return element(EBML, headers[EBML]) + element(SEGMENT, b"".join(parts))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--copies", default=80, type=int)
    args = parser.parse_args()
    output = args.output.resolve()
    if output == REPO or REPO in output.parents:
        parser.error("--output must be outside the checkout")
    if args.copies < 1:
        parser.error("--copies must be positive")
    with output.open("xb") as movie:
        movie.write(repeat(args.copies))


if __name__ == "__main__":
    main()
