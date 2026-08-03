#!/usr/bin/env python3
"""Flatten a generated Swag app icon and emit the canonical PNG/ICO pair."""

from __future__ import annotations

import argparse
from pathlib import Path

try:
    from PIL import Image
except ImportError as error:
    raise SystemExit("Pillow is required: py -3 -m pip install pillow") from error


INK = (0x0B, 0x0B, 0x0D)
VOLTAGE = (0xF7, 0xF9, 0x00)
PNG_SIZE = (512, 512)
ICO_SIZES = [(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48),
             (64, 64), (128, 128), (256, 256)]


def color_distance(left: tuple[int, int, int], right: tuple[int, int, int]) -> int:
    return sum((a - b) * (a - b) for a, b in zip(left, right))


def centered_square(image: Image.Image) -> Image.Image:
    edge = min(image.width, image.height)
    left = (image.width - edge) // 2
    top = (image.height - edge) // 2
    return image.crop((left, top, left + edge, top + edge))


def flatten_mask(image: Image.Image) -> Image.Image:
    source = centered_square(image.convert("RGB"))
    source_pixels = source.load()
    pixels = [255 if color_distance(source_pixels[x, y], VOLTAGE) <
              color_distance(source_pixels[x, y], INK) else 0
              for y in range(source.height) for x in range(source.width)]
    result = Image.new("L", source.size)
    result.putdata(pixels)
    return result


def render(mask: Image.Image, size: tuple[int, int]) -> Image.Image:
    resized_mask = mask.resize(size, Image.Resampling.LANCZOS)
    ink = Image.new("RGB", size, INK)
    voltage = Image.new("RGB", size, VOLTAGE)
    return Image.composite(voltage, ink, resized_mask)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert an image-generated master to the standard Swag app icon palette.")
    parser.add_argument("master", type=Path, help="Generated square raster master")
    parser.add_argument("--png", required=True, type=Path, help="Destination 512 px PNG")
    parser.add_argument("--ico", required=True, type=Path, help="Destination multi-size ICO")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not args.master.is_file():
        raise SystemExit(f"Icon master does not exist: {args.master}")

    with Image.open(args.master) as opened:
        mask = flatten_mask(opened)

    args.png.parent.mkdir(parents=True, exist_ok=True)
    args.ico.parent.mkdir(parents=True, exist_ok=True)

    png = render(mask, PNG_SIZE)
    png.save(args.png, format="PNG", optimize=True)

    ico_frames = [render(mask, size) for size in ICO_SIZES]
    ico_frames[-1].save(args.ico, format="ICO", sizes=ICO_SIZES,
                        append_images=ico_frames[:-1])

    print(f"wrote {args.png} ({PNG_SIZE[0]}x{PNG_SIZE[1]})")
    print(f"wrote {args.ico} ({len(ICO_SIZES)} sizes)")


if __name__ == "__main__":
    main()
