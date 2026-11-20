#!/usr/bin/env python3
"""Generate a tiny deterministic ustar archive for the SwagScope Archive viewer."""
from pathlib import Path
import io
import tarfile

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "viewer.field-kit.tar"
FILES = {
    "data/observations.csv": b"site,date,depth_cm\nnorth-marsh,2026-05-18,42\n",
    "notes/README.txt": b"Generated field kit archive.\n",
    "src/sensor.cpp": b"int sample() { return 42; }\n",
}

with tarfile.open(OUT, "w", format=tarfile.USTAR_FORMAT) as archive:
    for name, payload in FILES.items():
        info = tarfile.TarInfo(name)
        info.size = len(payload)
        info.mode = 0o644
        info.uid = info.gid = 0
        info.uname = info.gname = ""
        info.mtime = 0
        archive.addfile(info, io.BytesIO(payload))
