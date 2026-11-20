#!/usr/bin/env python3
"""Generate small, deterministic ZIP edge cases for the Swag Scope Archive viewer.

All member names and payloads are fictional and authored in this repository. The fixtures
exercise ZIP64 directory records, streaming data descriptors, UTF-8 and duplicate names,
directory corruption, and a declared preview size above the reader's limit.
"""

from __future__ import annotations

import io
import struct
import zlib
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
STAMP = (2020, 1, 2, 3, 4, 6)


def info(name: str, method: int = ZIP_STORED) -> ZipInfo:
    entry = ZipInfo(name, date_time=STAMP)
    entry.compress_type = method
    entry.create_system = 3
    entry.external_attr = 0o100644 << 16
    return entry


def ordinary_zip(name: str, payload: bytes, method: int = ZIP_STORED) -> bytes:
    output = io.BytesIO()
    with ZipFile(output, "w", compression=method, compresslevel=9) as archive:
        archive.writestr(info(name, method), payload)
    return output.getvalue()


def zip64_fixture() -> bytes:
    name = "reports/zip64-summary.txt".encode()
    payload = b"ZIP64 central directory and local extra fields are readable.\n"
    crc = zlib.crc32(payload) & 0xFFFFFFFF
    local_extra = struct.pack("<HHQQ", 1, 16, len(payload), len(payload))
    local = struct.pack(
        "<IHHHHHIIIHH", 0x04034B50, 45, 0, ZIP_STORED, 0, 0,
        crc, 0xFFFFFFFF, 0xFFFFFFFF, len(name), len(local_extra),
    ) + name + local_extra + payload
    directory_offset = len(local)
    directory_extra = struct.pack("<HHQQQ", 1, 24, len(payload), len(payload), 0)
    central = struct.pack(
        "<IHHHHHHIIIHHHHHII", 0x02014B50, 45, 45, 0, ZIP_STORED, 0, 0,
        crc, 0xFFFFFFFF, 0xFFFFFFFF, len(name), len(directory_extra), 0,
        0, 0, 0, 0xFFFFFFFF,
    ) + name + directory_extra
    zip64_end_offset = directory_offset + len(central)
    zip64_end = struct.pack(
        "<IQHHIIQQQQ", 0x06064B50, 44, 45, 45, 0, 0, 1, 1,
        len(central), directory_offset,
    )
    locator = struct.pack("<IIQI", 0x07064B50, 0, zip64_end_offset, 1)
    end = struct.pack(
        "<IHHHHIIH", 0x06054B50, 0, 0, 0xFFFF, 0xFFFF,
        0xFFFFFFFF, 0xFFFFFFFF, 0,
    )
    return local + central + zip64_end + locator + end


class NonSeekableBytesIO(io.BytesIO):
    def seekable(self) -> bool:
        return False

    def seek(self, *_args, **_kwargs):
        raise io.UnsupportedOperation("stream is not seekable")


def descriptor_fixture() -> bytes:
    output = NonSeekableBytesIO()
    with ZipFile(output, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        archive.writestr(
            info("logs/streamed-observations.txt", ZIP_DEFLATED),
            b"A forward-only writer records this payload before its CRC and sizes.\n",
        )
    return output.getvalue()


def unicode_duplicates_fixture() -> bytes:
    output = io.BytesIO()
    with ZipFile(output, "w") as archive:
        archive.writestr(info("field notes/café-日本語.txt", ZIP_DEFLATED), "UTF-8 path fixture.\n".encode())
        archive.writestr(info("reports/repeated.txt"), b"first copy\n")
        archive.writestr(info("reports/repeated.txt"), b"second copy\n")
    return output.getvalue()


def zipcrypto_fixture() -> bytes:
    name = b"private/field-report.txt"
    password = b"watershed"
    payload = b"Generated encrypted ZIP comparison fixture.\n"
    crc = zlib.crc32(payload) & 0xFFFFFFFF
    keys = [0x12345678, 0x23456789, 0x34567890]

    def crc32_byte(value: int, byte: int) -> int:
        value ^= byte
        for _ in range(8):
            value = (value >> 1) ^ (0xEDB88320 if value & 1 else 0)
        return value & 0xFFFFFFFF

    def update(byte: int) -> None:
        keys[0] = crc32_byte(keys[0], byte)
        keys[1] = ((keys[1] + (keys[0] & 0xFF)) * 134775813 + 1) & 0xFFFFFFFF
        keys[2] = crc32_byte(keys[2], keys[1] >> 24)

    for byte in password:
        update(byte)
    encrypted = bytearray()
    for byte in b"ScopeFixtur" + bytes([crc >> 24]) + payload:
        temp = keys[2] | 2
        encrypted.append(byte ^ ((temp * (temp ^ 1) >> 8) & 0xFF))
        update(byte)

    flags = 1
    packed_size = len(encrypted)
    local = struct.pack(
        "<IHHHHHIIIHH", 0x04034B50, 20, flags, ZIP_STORED, 0, 0,
        crc, packed_size, len(payload), len(name), 0,
    ) + name + encrypted
    central_offset = len(local)
    central = struct.pack(
        "<IHHHHHHIIIHHHHHII", 0x02014B50, 20, 20, flags, ZIP_STORED, 0, 0,
        crc, packed_size, len(payload), len(name), 0, 0, 0, 0, 0, 0,
    ) + name
    end = struct.pack(
        "<IHHHHIIH", 0x06054B50, 0, 0, 1, 1, len(central), central_offset, 0,
    )
    return local + central + end


def main() -> None:
    (ROOT / "viewer.zip64.zip").write_bytes(zip64_fixture())
    (ROOT / "viewer.zip-descriptor.zip").write_bytes(descriptor_fixture())
    (ROOT / "viewer.zip-unicode-duplicates.zip").write_bytes(unicode_duplicates_fixture())
    (ROOT / "viewer.zipcrypto-encrypted.zip").write_bytes(zipcrypto_fixture())

    damaged = bytearray(ordinary_zip("data/readme.txt", b"A valid payload behind a damaged directory.\n"))
    eocd = damaged.rfind(b"PK\x05\x06")
    directory_at = struct.unpack_from("<I", damaged, eocd + 16)[0]
    damaged[directory_at] ^= 0x01
    (ROOT / "viewer.zip-damaged-directory.zip").write_bytes(damaged)

    limited = bytearray(ordinary_zip("data/preview-limit.txt", b"small stored payload"))
    central_at = limited.find(b"PK\x01\x02")
    struct.pack_into("<I", limited, central_at + 24, 256 * 1024 * 1024 + 1)
    (ROOT / "viewer.zip-preview-limit.zip").write_bytes(limited)


if __name__ == "__main__":
    main()
