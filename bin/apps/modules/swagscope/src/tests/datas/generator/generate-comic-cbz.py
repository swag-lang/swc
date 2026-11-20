#!/usr/bin/env python3
"""Generate two fictional comic pages and package them in stable natural-sort order."""

from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo
from PIL import Image, ImageDraw, ImageFont

out_dir = Path(__file__).resolve().parents[1]


def make_page(number: int, title: str, sky: tuple[int, int, int], character_x: int) -> Image.Image:
    page = Image.new("RGB", (480, 680), (249, 246, 233))
    d = ImageDraw.Draw(page)
    font = ImageFont.load_default(size=20)
    d.rectangle((18, 18, 462, 662), outline=(39, 56, 55), width=4)
    d.text((38, 32), "THE RIVER DETECTIVES", fill=(39, 56, 55), font=font)
    d.text((398, 32), f"{number:02d}", fill=(39, 56, 55), font=font)
    d.rectangle((38, 74, 442, 314), fill=(255, 255, 250), outline=(39, 56, 55), width=3)
    d.rectangle((54, 90, 426, 248), fill=sky)
    d.polygon([(54, 226), (144, 172), (218, 230), (310, 168), (426, 225), (426, 248), (54, 248)], fill=(99, 147, 118))
    d.polygon([(54, 230), (150, 214), (235, 238), (326, 212), (426, 236), (426, 248), (54, 248)], fill=(80, 158, 176))
    d.ellipse((character_x - 17, 157, character_x + 17, 191), fill=(238, 167, 81), outline=(39, 56, 55), width=3)
    d.line((character_x, 191, character_x - 5, 222), fill=(39, 56, 55), width=5)
    d.ellipse((330, 96, 408, 138), fill=(255, 255, 248), outline=(39, 56, 55), width=2)
    d.text((343, 110), "Look!", fill=(39, 56, 55), font=font)
    d.rectangle((38, 336, 442, 612), fill=(255, 255, 250), outline=(39, 56, 55), width=3)
    d.rectangle((54, 352, 426, 548), fill=(205, 217, 191))
    d.polygon([(54, 505), (154, 423), (234, 498), (317, 410), (426, 492), (426, 548), (54, 548)], fill=(111, 157, 116))
    d.line((62, 519, 152, 507, 238, 520, 318, 505, 416, 519), fill=(79, 145, 166), width=14)
    d.text((72, 570), title, fill=(39, 56, 55), font=font)
    return page


pages = {
    "2.png": make_page(2, "Mira follows the waterway.", (180, 215, 226), 126),
    "10.png": make_page(10, "The marker points upstream!", (227, 205, 160), 286),
}
for filename, page in pages.items():
    page.save(out_dir / f"{filename}.generated.png", format="PNG", optimize=False, compress_level=9)

entries = [
    ("2.png", (out_dir / "2.png.generated.png").read_bytes()),
    ("10.png", (out_dir / "10.png.generated.png").read_bytes()),
    ("notes.txt", b"Original generated Swag Scope comic fixture. All people, places and events are fictional.\n"),
]
for archive_name in ("viewer.cbz", "viewer.comic.cbz"):
    target = out_dir / archive_name
    with ZipFile(target, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in entries:
            info = ZipInfo(name, date_time=(2020, 1, 2, 3, 4, 6))
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data, compress_type=ZIP_DEFLATED, compresslevel=9)
for filename in ("2.png.generated.png", "10.png.generated.png"):
    (out_dir / filename).unlink()
