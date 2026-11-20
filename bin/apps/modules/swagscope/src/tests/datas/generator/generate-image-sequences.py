#!/usr/bin/env python3
"""Generate deterministic animation, icon, and multipage TIFF fixtures with Pillow."""
from __future__ import annotations

from pathlib import Path
import shutil

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
DURATIONS = [40, 120, 80]


def field_frame(width: int, height: int, phase: int) -> Image.Image:
    """Draw a transparent watershed survey marker at one of three positions."""
    image = Image.new("RGBA", (width, height), (243, 247, 231, 255))
    draw = ImageDraw.Draw(image)
    sx, sy = width / 320, height / 240
    pts = lambda values: [(round(x * sx), round(y * sy)) for x, y in values]

    # Elevation fields, marsh, and a winding stream make each frame useful beyond a color test.
    draw.rectangle((0, 0, width, round(height * .42)), fill=(222, 231, 203, 255))
    draw.polygon(pts([(0, 150), (52, 117), (109, 147), (165, 101), (221, 133),
                      (270, 91), (320, 114), (320, 240), (0, 240)]),
                 fill=(164, 198, 153, 255))
    draw.polygon(pts([(0, 182), (45, 160), (87, 184), (129, 157), (173, 185),
                      (219, 151), (271, 174), (320, 148), (320, 240), (0, 240)]),
                 fill=(197, 215, 171, 255))
    draw.line(pts([(-15, 52), (50, 72), (86, 103), (143, 112), (177, 146),
                   (229, 154), (270, 193), (335, 207)]),
              fill=(42, 133, 179, 255), width=max(2, round(12 * sx)), joint="curve")
    draw.line(pts([(15, 225), (79, 199), (151, 207), (221, 183), (306, 190)]),
              fill=(141, 103, 71, 255), width=max(1, round(2 * sx)), joint="curve")
    # Three fixed contour arcs provide fine detail at each encoded scale.
    for inset in (10, 21, 33, 46):
        box = tuple(round(v * (sx if i % 2 == 0 else sy))
                    for i, v in enumerate((inset, inset, 320 - inset, 240 - inset)))
        draw.arc(box, 205 + phase * 4, 326 + phase * 4, fill=(137, 166, 124, 210), width=max(1, round(sx)))
    x = 70 + phase * 90
    y = 82 + (phase % 2) * 29
    cx, cy = round(x * sx), round(y * sy)
    radius = max(4, round(11 * sx))
    draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius),
                 fill=(245, 183, 69, 255), outline=(65, 78, 56, 255), width=max(1, round(2 * sx)))
    draw.ellipse((cx - round(radius * .35), cy - round(radius * .35),
                  cx + round(radius * .35), cy + round(radius * .35)),
                 fill=(61, 75, 55, 255))
    return image


def sequence_frames() -> list[Image.Image]:
    return [field_frame(320, 240, phase) for phase in range(3)]


def write_aliases(source: Path, names: tuple[str, ...]) -> None:
    for name in names:
        target = ROOT / name
        if target != source:
            shutil.copyfile(source, target)


def write_animations() -> None:
    frames = sequence_frames()

    apng = ROOT / "imageset-animation.apng"
    frames[0].save(apng, format="PNG", save_all=True, append_images=frames[1:],
                   duration=DURATIONS, loop=1, blend=0, disposal=0, optimize=False,
                   compress_level=9)
    write_aliases(apng, ("viewer.animation.apng", "viewer.apng"))

    gif = ROOT / "imageset-animation.gif"
    palette_frames = [frame.convert("P", palette=Image.Palette.ADAPTIVE, colors=255)
                      for frame in frames]
    palette_frames[0].save(gif, format="GIF", save_all=True, append_images=palette_frames[1:],
                           duration=DURATIONS, loop=1, disposal=2, optimize=False)
    write_aliases(gif, ("viewer.animation.gif", "viewer.gif"))

    webp = ROOT / "imageset-animation.webp"
    frames[0].save(webp, format="WEBP", save_all=True, append_images=frames[1:],
                   duration=DURATIONS, loop=1, lossless=True, quality=100, method=6, exact=True)
    write_aliases(webp, ("viewer.animation.webp", "viewer.webp"))


def write_icon() -> None:
    icon = field_frame(64, 64, 2)
    path = ROOT / "imageset-icons.ico"
    icon.save(path, format="ICO", sizes=[(16, 16), (32, 32), (48, 48)])
    write_aliases(path, ("viewer.ico",))


def write_tiff() -> None:
    sizes = [(320, 220), (240, 360), (400, 260)]
    pages = [field_frame(width, height, index).convert("RGB")
             for index, (width, height) in enumerate(sizes)]
    path = ROOT / "imageset-pages-raw.tiff"
    pages[0].save(path, format="TIFF", save_all=True, append_images=pages[1:],
                   compression="raw", dpi=(96, 96))
    write_aliases(path, ("viewer.tif", "viewer.tiff"))


if __name__ == "__main__":
    write_animations()
    write_icon()
    write_tiff()
