"""Encode one photo into raster fixtures with varied dimensions, layouts, and compression."""

import argparse
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--photo", type=Path, required=True, help="any photo readable by ImageMagick")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--magick", default="magick", help="ImageMagick 7 executable")
    args = parser.parse_args()
    photo = args.photo.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    def write(name, *settings):
        subprocess.run([args.magick, photo, "-strip", *settings, output / name], check=True)

    write("small-jpeg.jpg", "-resize", "317x211!", "-sampling-factor", "4:2:0", "-quality", "84")
    write("large-jpeg.jpg", "-resize", "1921x1281!", "-sampling-factor", "4:4:4", "-quality", "91")
    write("progressive.jpg", "-resize", "1279x853!", "-interlace", "Plane", "-quality", "85")
    write("grayscale.jpg", "-resize", "641x427!", "-colorspace", "gray")
    write("palette.png", "-resize", "639x425!", "-colors", "48", "-define", "png:color-type=3")
    write("adam7.png", "-resize", "641x427!", "-depth", "16", "-interlace", "PNG",
          "-define", "png:color-type=2", "-define", "png:bit-depth=16")
    write("packbits.tiff", "-resize", "1025x683!", "-depth", "8", "-compress", "RLE")
    write("lzw-predictor.tiff", "-resize", "1025x683!", "-depth", "8", "-compress", "LZW",
          "-define", "tiff:predictor=2", "-define", "tiff:rows-per-strip=31")
    write("vp8.webp", "-resize", "1601x1067!", "-quality", "82")
    write("vp8l.webp", "-resize", "1009x673!", "-define", "webp:lossless=true")
    write("transparent.gif", "-resize", "641x427!", "-alpha", "set", "-channel", "A",
          "-region", "128x128+0+0", "-evaluate", "set", "0", "+region", "+channel", "-colors", "128")
    subprocess.run([args.magick, "-delay", "8", output / "transparent.gif",
                    "(", output / "transparent.gif", "-flop", ")", "-loop", "0",
                    "-layers", "Optimize", output / "animated.gif"], check=True)


if __name__ == "__main__":
    main()
