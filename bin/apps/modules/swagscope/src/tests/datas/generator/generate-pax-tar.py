#!/usr/bin/env python3
"""Generate a deterministic PAX TAR with a long UTF-8 member path."""
from pathlib import Path
import io
import tarfile

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "viewer.pax-field-kit.tar"
name = "field-reports/observations/2026/seasonal/north-marsh/" + "watershed-measurements-" + "early-summer-" * 5 + "summary.txt"
payload = b"PAX extended paths remain browseable.\n"
info = tarfile.TarInfo(name)
info.size = len(payload)
info.mode = 0o644
info.uid = info.gid = 0
info.uname = info.gname = ""
info.mtime = 0
info.pax_headers = {"comment": "generated long-path compatibility fixture", "size": str(len(payload))}

with tarfile.open(OUT, "w", format=tarfile.PAX_FORMAT) as archive:
    archive.addfile(info, io.BytesIO(payload))
