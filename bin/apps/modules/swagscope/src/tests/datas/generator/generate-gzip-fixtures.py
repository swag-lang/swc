#!/usr/bin/env python3
"""Generate deterministic GZIP and TAR.GZ examples for the SwagScope Archive viewer."""
from io import BytesIO
from pathlib import Path
import gzip
import struct
import tarfile
import zlib

ROOT = Path(__file__).resolve().parent.parent


def gzip_member(name: str, payload: bytes) -> bytes:
    output = BytesIO()
    with gzip.GzipFile(filename=name, mode="wb", fileobj=output, mtime=0, compresslevel=6) as stream:
        stream.write(payload)
    member = output.getvalue()
    deflate_at = 10 + len(name.encode("latin-1")) + 1
    header = bytearray(member[:10])
    header[3] = 0x1E  # FEXTRA, FNAME, FCOMMENT and FHCRC.
    header.extend(struct.pack("<H", 3))
    header.extend(b"kit")
    header.extend(name.encode("latin-1") + b"\0")
    header.extend(b"Repository-generated fixture\0")
    header.extend(struct.pack("<H", zlib.crc32(header) & 0xFFFF))
    return bytes(header) + member[deflate_at:-8] + member[-8:]


(ROOT / "viewer.field-notes.txt.gz").write_bytes(
    gzip_member("field-notes.txt", b"Generated watershed field notes.\nRainfall: 12 mm\n")
)

tar_bytes = BytesIO()
with tarfile.open(fileobj=tar_bytes, mode="w", format=tarfile.USTAR_FORMAT) as archive:
    files = {
        "data/observations.csv": b"site,date,depth_cm\nnorth-marsh,2026-05-18,42\n",
        "notes/README.txt": b"Generated field kit archive.\n",
        "src/sensor.cpp": b"int sample() { return 42; }\n",
    }
    for name, payload in files.items():
        info = tarfile.TarInfo(name)
        info.size = len(payload)
        info.mode = 0o644
        info.uid = info.gid = 0
        info.uname = info.gname = ""
        info.mtime = 0
        archive.addfile(info, BytesIO(payload))

(ROOT / "viewer.field-kit.tar.gz").write_bytes(gzip_member("field-kit.tar", tar_bytes.getvalue()))
