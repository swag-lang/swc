#!/usr/bin/env python3
"""Generate the Swag Scope animated watershed review image without external assets."""

from pathlib import Path
from PIL import Image, ImageDraw

out = Path(__file__).resolve().parents[1] / "viewer.synthetic-review.webp"
size = 512
background = Image.new("RGB", (size, size), (224, 229, 212))
draw = ImageDraw.Draw(background)
# Fictional fields, hills, paths, and a broad river built entirely from shapes.
draw.polygon([(0, 0), (512, 0), (512, 150), (380, 180), (250, 132), (0, 190)], fill=(189, 210, 165))
draw.polygon([(0, 190), (250, 132), (380, 180), (512, 150), (512, 512), (0, 512)], fill=(205, 216, 175))
draw.polygon([(0, 288), (92, 244), (173, 267), (228, 320), (312, 331), (370, 302), (512, 339), (512, 385), (373, 348), (302, 379), (211, 364), (151, 313), (83, 302), (0, 341)], fill=(105, 170, 190))
for y in (40, 72, 104, 420, 450, 480):
    draw.arc((-90, y, 580, y + 125), 180, 350, fill=(157, 184, 138), width=2)
for x in range(30, 512, 86):
    draw.line((x, 20, x - 32, 230), fill=(224, 221, 186), width=2)
    draw.line((x - 32, 390, x + 12, 500), fill=(224, 221, 186), width=2)
draw.rounded_rectangle((18, 18, 230, 56), radius=8, fill=(248, 247, 237))
draw.text((30, 29), "WATERSHED / SYNTHETIC REVIEW", fill=(43, 62, 62))

frames = []
for index in range(33):
    frame = background.copy()
    marker = ImageDraw.Draw(frame)
    x = 72 + index * 10
    y = 225 + ((index % 8) - 4) * 3
    marker.ellipse((x - 15, y - 15, x + 15, y + 15), fill=(246, 164, 65), outline=(90, 57, 31), width=3)
    marker.ellipse((x - 4, y - 4, x + 4, y + 4), fill=(255, 250, 232))
    marker.line((x, y + 14, x, y + 43), fill=(90, 57, 31), width=3)
    marker.rectangle((430, 82, 474, 116), fill=(248, 247, 237), outline=(74, 90, 72), width=2)
    marker.text((438, 94), f"{index:02d}", fill=(43, 62, 62))
    frames.append(frame)

metadata = Image.Exif()
metadata[270] = "Generated fictional watershed review image; no photographed content."
metadata[305] = "Swag Scope generate-review-webp.py"
metadata[274] = 1
metadata[306] = "2026:11:20 00:00:00"
frames[0].save(out, format="WEBP", save_all=True, append_images=frames[1:], duration=62,
               loop=0, quality=88, method=6, exif=metadata.tobytes()[6:])
