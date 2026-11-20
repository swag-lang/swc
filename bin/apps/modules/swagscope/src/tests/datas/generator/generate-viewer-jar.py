#!/usr/bin/env python3
"""Build the self-contained, fictional Swag Scope Archive JAR fixture."""

from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

out = Path(__file__).resolve().parents[1] / "viewer.jar"
class_bytes = bytes.fromhex(
    "cafebabe00000034000c"
    "01000a46697874757265417070070001"
    "0100106a6176612f6c616e672f4f626a656374070003"
    "0100063c696e69743e0100032829560c00050006"
    "0a00040007"
    "010004436f64650100046d61696e"
    "010016285b4c6a6176612f6c616e672f537472696e673b2956"
    "0021000200040000000000020001000500060001000900000011"
    "00010001000000052ab70008b1000000000009000a000b00010009"
    "0000000d0000000100000001b1000000000000"
)
entries = [
    ("META-INF/MANIFEST.MF", b"Manifest-Version: 1.0\r\nMain-Class: FixtureApp\r\n\r\n"),
    ("FixtureApp.class", class_bytes),
    ("README.txt", b"Generated executable JAR fixture for archive navigation.\n"),
    ("data/sites.csv", b"site_id,status\nnorth-marsh,active\nold-quarry,active\n"),
]
with ZipFile(out, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
    for name, data in entries:
        info = ZipInfo(name, date_time=(2020, 1, 2, 3, 4, 6))
        info.compress_type = ZIP_DEFLATED
        info.create_system = 3
        info.external_attr = 0o100644 << 16
        archive.writestr(info, data, compress_type=ZIP_DEFLATED, compresslevel=9)
