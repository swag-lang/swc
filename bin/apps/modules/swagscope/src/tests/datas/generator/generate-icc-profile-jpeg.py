#!/usr/bin/env python3
"""Generate a tiny JPEG carrying a deterministic synthetic ICC identity profile."""

from pathlib import Path
import struct

from PIL import Image, ImageDraw


out = Path(__file__).resolve().parents[1] / "viewer.icc-profile.jpg"
description = b"Swag generated sRGB\0"
desc_offset = 144
desc_size = 12 + len(description)
profile = bytearray(desc_offset + desc_size)

struct.pack_into(">I", profile, 0, len(profile))
profile[12:16] = b"mntr"
profile[16:20] = b"RGB "
profile[20:24] = b"XYZ "
profile[36:40] = b"acsp"
struct.pack_into(">I", profile, 128, 1)
profile[132:136] = b"desc"
struct.pack_into(">I", profile, 136, desc_offset)
struct.pack_into(">I", profile, 140, desc_size)
profile[desc_offset:desc_offset + 4] = b"desc"
struct.pack_into(">I", profile, desc_offset + 8, len(description))
profile[desc_offset + 12:desc_offset + 12 + len(description)] = description

image = Image.new("RGB", (48, 32), (236, 230, 214))
draw = ImageDraw.Draw(image)
draw.rectangle((0, 0, 15, 31), fill=(190, 215, 165))
draw.rectangle((16, 0, 31, 31), fill=(105, 170, 190))
draw.rectangle((32, 0, 47, 31), fill=(238, 166, 74))
image.save(out, format="JPEG", quality=90, icc_profile=bytes(profile), optimize=False)
print(f"{out.name}: {out.stat().st_size} bytes")
