#!/usr/bin/env python3
"""Generate a tiny WebP with an ICC mluc tag containing French and English names."""

from pathlib import Path
import struct

from PIL import Image, ImageDraw


out = Path(__file__).resolve().parents[1] / "viewer.icc-profile-mluc.webp"
locales = [(b"fr", b"FR", "Profil ICC français"),
           (b"en", b"US", "Swag generated sRGB mluc")]
strings = [text.encode("utf-16-be") for _, _, text in locales]
record_size = 12
record_count = len(locales)
mluc_offset = 144
text_offset = 16 + record_size * record_count
records = bytearray()
text_data = bytearray()
offset = text_offset
for (language, country, _), encoded in zip(locales, strings):
    records += language + country + struct.pack(">II", len(encoded), offset)
    text_data += encoded
    offset += len(encoded)
mluc = b"mluc" + b"\0" * 4 + struct.pack(">II", record_count, record_size) + records + text_data
profile = bytearray(mluc_offset + len(mluc))

struct.pack_into(">I", profile, 0, len(profile))
profile[12:16] = b"mntr"
profile[16:20] = b"RGB "
profile[20:24] = b"XYZ "
profile[36:40] = b"acsp"
struct.pack_into(">I", profile, 128, 1)
profile[132:136] = b"desc"
struct.pack_into(">II", profile, 136, mluc_offset, len(mluc))
profile[mluc_offset:] = mluc

image = Image.new("RGB", (48, 32), (236, 230, 214))
draw = ImageDraw.Draw(image)
draw.rectangle((0, 0, 15, 31), fill=(190, 215, 165))
draw.rectangle((16, 0, 31, 31), fill=(105, 170, 190))
draw.rectangle((32, 0, 47, 31), fill=(238, 166, 74))
image.save(out, format="WEBP", quality=90, method=6, icc_profile=bytes(profile))
print(f"{out.name}: {out.stat().st_size} bytes")
