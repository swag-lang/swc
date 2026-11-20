#!/usr/bin/env python3
"""Generate Swag Scope's synthetic raster fixtures and their embedded document copies.

Requires Pillow (validated with 12.3.0). The images use only deterministic vector-like geometry
drawn here; no external images, fonts, profiles, or random data are read.
"""
from __future__ import annotations

from io import BytesIO
from pathlib import Path
import re
from zipfile import ZIP_DEFLATED, ZipFile

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]


def landscape(width: int, height: int, variant: int = 0) -> Image.Image:
    """A simple fictional watershed map, built from fixed polygons and linework."""
    img = Image.new("RGB", (width, height))
    px = img.load()
    for y in range(height):
        for x in range(width):
            # Gentle, deterministic elevation bands without external texture.
            band = ((x * 7 // max(1, width) + y * 5 // max(1, height) + variant) % 5)
            px[x, y] = ((218, 228, 204), (207, 222, 194), (230, 226, 190),
                        (220, 231, 210), (202, 220, 194))[band]
    draw = ImageDraw.Draw(img)
    sx, sy = width / 1024, height / 768
    def pts(values):
        return [(round(x * sx), round(y * sy)) for x, y in values]
    # A blue river and two tributaries cross an abstract green valley.
    draw.polygon(pts([(0, 430), (120, 380), (240, 425), (360, 365), (490, 405),
                      (625, 330), (760, 365), (895, 280), (1024, 305), (1024, 470),
                      (890, 435), (770, 510), (635, 455), (500, 535), (355, 490),
                      (225, 545), (105, 495), (0, 535)]), fill=(145, 190, 151))
    draw.line(pts([(-30, 85), (110, 175), (220, 210), (310, 290), (440, 320),
                   (550, 390), (660, 395), (770, 470), (900, 495), (1050, 650)]),
              fill=(53, 134, 177), width=max(2, round(25 * sx)), joint="curve")
    draw.line(pts([(450, 0), (470, 120), (430, 220), (440, 310), (550, 390)]),
              fill=(69, 151, 187), width=max(1, round(13 * sx)), joint="curve")
    draw.line(pts([(1024, 150), (900, 230), (830, 350), (770, 470)]),
              fill=(69, 151, 187), width=max(1, round(12 * sx)), joint="curve")
    # Fixed contour paths and roads give decoders non-flat, detailed pixels.
    for inset in range(0, min(width, height) // 10, max(1, round(16 * sx))):
        margin = inset
        box = (margin, margin, width - margin - 1, height - margin - 1)
        if box[2] > box[0] and box[3] > box[1]:
            draw.arc(box, start=190 + (inset // max(1, round(16 * sx))) * 7,
                     end=340 + (inset // max(1, round(16 * sx))) * 9,
                     fill=(176, 194, 158), width=max(1, round(1 * sx)))
    draw.line(pts([(20, 650), (170, 585), (300, 600), (430, 550), (575, 575),
                   (710, 540), (850, 570), (1010, 515)]),
              fill=(159, 119, 83), width=max(1, round(4 * sx)), joint="curve")
    # Landmark circles and marker blocks are geometric and contain no lettering.
    for x, y in [(155, 270), (335, 595), (690, 235), (890, 610)]:
        xx, yy = round(x * sx), round(y * sy)
        radius = max(2, round(9 * sx))
        draw.ellipse((xx-radius, yy-radius, xx+radius, yy+radius),
                     fill=(239, 244, 219), outline=(73, 105, 76), width=max(1, round(2*sx)))
    return img


def write_zip_member(path: Path, target: str, data: bytes) -> None:
    temp = path.with_suffix(path.suffix + ".tmp")
    with ZipFile(path, "r") as source, ZipFile(temp, "w") as out:
        for info in source.infolist():
            payload = data if info.filename == target else source.read(info.filename)
            out.writestr(info, payload, compress_type=info.compress_type or ZIP_DEFLATED)
    temp.replace(path)


def replace_rtf_picture(path: Path, control: str, payload: bytes) -> None:
    text = path.read_text(encoding="ascii")
    marker = "\\" + control
    cursor = 0
    for _ in range(text.count(marker)):
        start = text.index(marker, cursor)
        payload_start = text.index("\n", start) + 1
        payload_end = text.index("}", payload_start)
        encoded = payload.hex()
        # Keep RTF lines short and the file stable for readable review.
        wrapped = "\n".join(encoded[i:i + 80] for i in range(0, len(encoded), 80)) + "\n"
        text = text[:payload_start] + wrapped + text[payload_end:]
        cursor = payload_start + len(wrapped)
    path.write_text(text, encoding="ascii", newline="")


def main() -> None:
    base = landscape(1024, 768)
    square = landscape(512, 512, variant=2)
    base.save(ROOT / "viewer.jpg", "JPEG", quality=88, subsampling=0, optimize=False,
              progressive=False, exif=b"")
    (ROOT / "viewer.jpeg").write_bytes((ROOT / "viewer.jpg").read_bytes())
    base.resize((660, 441), Image.Resampling.LANCZOS).save(
        ROOT / "viewer.progressive.jpg", "JPEG", quality=86, subsampling=0,
        optimize=False, progressive=True, exif=b"")
    cmyk_rgb = Image.new("RGB", (48, 32))
    cmyk_draw = ImageDraw.Draw(cmyk_rgb)
    cmyk_draw.rectangle((0, 0, 15, 31), fill=(255, 0, 0))
    cmyk_draw.rectangle((16, 0, 31, 31), fill=(0, 255, 0))
    cmyk_draw.rectangle((32, 0, 47, 31), fill=(0, 0, 255))
    cmyk_rgb.convert("CMYK").save(ROOT / "viewer.cmyk.jpg", "JPEG", quality=100,
                                   subsampling=0, optimize=False, exif=b"")
    square.save(ROOT / "viewer.png", "PNG", optimize=False, compress_level=9)
    base.resize((4, 4), Image.Resampling.LANCZOS).save(ROOT / "viewer.bmp", "BMP")
    base.resize((660, 441), Image.Resampling.LANCZOS).save(ROOT / "viewer.tga", "TGA",
                                                             compression="tga_rle")

    # Update only the embedded copies that reused these corpus images.
    jpg = (ROOT / "viewer.jpg").read_bytes()
    png = (ROOT / "viewer.png").read_bytes()
    write_zip_member(ROOT / "viewer.image.docx", "word/media/photo.jpg", jpg)
    with ZipFile(ROOT / "viewer.image.odt") as archive:
        picture = next(name for name in archive.namelist()
                       if name.startswith("Pictures/") and name.lower().endswith(".jpg"))
    write_zip_member(ROOT / "viewer.image.odt", picture, jpg)
    write_zip_member(ROOT / "viewer.odp", picture, jpg)
    replace_rtf_picture(ROOT / "viewer.pictures.rtf", "jpegblip", jpg)
    replace_rtf_picture(ROOT / "viewer.alternate-picture.rtf", "pngblip", png)


if __name__ == "__main__":
    main()
