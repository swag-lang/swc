#!/usr/bin/env python3
"""Create original, deterministic cursor, QOI, archive-icon, CBZ, and ZIP fixtures.

The generated art is geometric and contains no external images or fonts. Pillow 12.3.0 is used
only to write PNG/JPEG pixels; QOI and archive containers are written with Python's standard
library.
"""
from __future__ import annotations

from io import BytesIO
from pathlib import Path
import shutil
import struct
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile, ZipInfo

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[1]


def png_bytes(image: Image.Image) -> bytes:
    result = BytesIO()
    image.save(result, format="PNG", optimize=False, compress_level=9)
    return result.getvalue()


def qoi_bytes() -> bytes:
    # Four deliberately distinct pixels, encoded with QOI_OP_RGBA for a compact,
    # straightforward single-image decoder fixture.
    pixels = [
        (30, 92, 150, 255), (232, 174, 57, 255),
        (58, 145, 96, 255), (176, 76, 85, 192),
    ]
    data = bytearray(b"qoif")
    data += struct.pack(">IIBB", 2, 2, 4, 0)
    for pixel in pixels:
        data.append(0xFF)
        data.extend(pixel)
    data += b"\0\0\0\0\0\0\0\1"
    return bytes(data)


def icon_atlas() -> Image.Image:
    image = Image.new("RGBA", (48, 16), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    # Folder glyph: a gold tab and body with a one-pixel outline.
    draw.rectangle((2, 5, 13, 13), fill=(244, 184, 54, 255), outline=(112, 76, 24, 255))
    draw.rectangle((3, 3, 8, 5), fill=(244, 184, 54, 255), outline=(112, 76, 24, 255))
    draw.line((3, 7, 12, 7), fill=(255, 221, 116, 255))

    # JSON glyph: paper, folded corner, braces, and two data rows.
    x = 16
    draw.rectangle((x + 2, 1, x + 13, 14), fill=(248, 250, 247, 255), outline=(43, 78, 94, 255))
    draw.polygon(((x + 10, 1), (x + 13, 4), (x + 10, 4)), fill=(145, 192, 197, 255))
    draw.line((x + 4, 6, x + 5, 5, x + 4, 8, x + 5, 9), fill=(44, 121, 157, 255), width=1)
    draw.line((x + 10, 6, x + 9, 5, x + 10, 8, x + 9, 9), fill=(44, 121, 157, 255), width=1)
    draw.line((x + 6, 6, x + 8, 6), fill=(87, 151, 82, 255))
    draw.line((x + 6, 9, x + 8, 9), fill=(87, 151, 82, 255))
    draw.line((x + 4, 11, x + 11, 11), fill=(177, 189, 184, 255))

    # Plain-text glyph: a paper sheet with a green folded corner and ruled lines.
    x = 32
    draw.rectangle((x + 2, 1, x + 13, 14), fill=(250, 251, 248, 255), outline=(49, 95, 65, 255))
    draw.polygon(((x + 10, 1), (x + 13, 4), (x + 10, 4)), fill=(118, 177, 109, 255))
    for y, end in ((6, 11), (8, 12), (10, 9), (12, 11)):
        draw.line((x + 4, y, x + end, y), fill=(74, 139, 85, 255))
    return image


def cursor_bytes() -> bytes:
    entries = []
    images = []
    for width, height, color, hotspot in (
        (4, 4, (35, 125, 205, 255), (1, 1)),
        (2, 2, (235, 156, 45, 255), (0, 0)),
    ):
        image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        draw.rectangle((0, 0, width - 1, height - 1), fill=color)
        if width > 2:
            draw.point((1, 1), fill=(245, 248, 250, 255))
        images.append(png_bytes(image))
        entries.append((width, height, hotspot[0], hotspot[1]))

    offset = 6 + 16 * len(images)
    result = bytearray(struct.pack("<HHH", 0, 2, len(images)))
    for (width, height, hot_x, hot_y), encoded in zip(entries, images):
        result += struct.pack("<BBBBHHII", width, height, 0, 0, hot_x, hot_y, len(encoded), offset)
        offset += len(encoded)
    for encoded in images:
        result += encoded
    return bytes(result)


def comic_page(number: int, sky: tuple[int, int, int], marker_x: int) -> Image.Image:
    image = Image.new("RGB", (96, 128), (245, 242, 226))
    draw = ImageDraw.Draw(image)
    ink = (43, 60, 58)
    draw.rectangle((3, 3, 92, 124), outline=ink, width=2)
    draw.rectangle((9, 10, 86, 70), fill=(253, 252, 244), outline=ink, width=1)
    draw.rectangle((13, 14, 82, 66), fill=sky)
    draw.polygon(((13, 54), (30, 39), (44, 52), (60, 35), (82, 51), (82, 66), (13, 66)),
                 fill=(101, 151, 112))
    draw.polygon(((13, 58), (31, 54), (48, 62), (66, 53), (82, 59), (82, 66), (13, 66)),
                 fill=(58, 143, 169))
    draw.ellipse((marker_x - 4, 28, marker_x + 4, 36), fill=(241, 174, 68), outline=ink)
    draw.line((marker_x, 36, marker_x - 1, 45), fill=ink, width=2)
    draw.rectangle((9, 76, 86, 117), fill=(252, 251, 243), outline=ink, width=1)
    draw.rectangle((13, 80, 82, 108), fill=(207, 222, 195))
    draw.line((14, 101, 28, 91, 41, 102, 57, 88, 81, 101), fill=(88, 145, 103), width=3)
    draw.line((15, 105, 35, 101, 54, 106, 81, 101), fill=(65, 150, 175), width=2)
    # A small page marker keeps the two synthetic pages visibly distinct without using text.
    draw.rectangle((78, 6, 88, 9), fill=(226, 177, 72) if number == 2 else (95, 148, 175))
    return image


def write_zip(path: Path, entries: list[tuple[str, bytes]], date: tuple[int, int, int, int, int, int]) -> None:
    with ZipFile(path, "w", allowZip64=True) as archive:
        for index, (name, payload) in enumerate(entries):
            info = ZipInfo(name, date_time=date)
            info.compress_type = ZIP_STORED if index == 0 else ZIP_DEFLATED
            info.create_system = 0
            info.external_attr = 0
            archive.writestr(info, payload, compress_type=info.compress_type, compresslevel=9)


def main() -> None:
    (OUT / "viewer.qoi").write_bytes(qoi_bytes())
    (OUT / "viewer.archive.icons.png").write_bytes(png_bytes(icon_atlas()))
    (OUT / "viewer.cur").write_bytes(cursor_bytes())

    png = BytesIO()
    comic_page(2, (173, 213, 224), 32).save(png, format="PNG", optimize=False, compress_level=9)
    jpeg = BytesIO()
    comic_page(10, (225, 202, 159), 58).save(jpeg, format="JPEG", quality=88,
                                                subsampling=0, optimize=False, progressive=False)
    nested_entries = [
        ("chapter/2.png", png.getvalue()),
        ("chapter/10.jpg", jpeg.getvalue()),
        ("chapter/notes.txt", b"Only images are comic pages.\n"),
    ]
    write_zip(OUT / "viewer.nested.cbz", nested_entries, (2024, 1, 1, 12, 0, 0))

    archive_entries = [
        ("docs/readme.txt", b"Archive preview through the text viewer.\n"),
        ("data/sample.json", b'{"answer": 42}\n'),
    ]
    archive_path = OUT / "viewer.archive.zip"
    write_zip(archive_path, archive_entries, (2024, 1, 1, 12, 0, 0))
    shutil.copyfile(archive_path, OUT / "viewer.zip")


if __name__ == "__main__":
    main()
