"""Generate a multi-page workload that shares one large JPEG XObject."""

import argparse
from pathlib import Path
import re


def generate(source):
    # The pinned PDF.js large-JPEG fixture has one direct, RGB DCT stream.
    image = re.search(rb"(<<[^>]+/Filter /DCTDecode /Length (\d+)>>)\r?\nstream\r?\n", source)
    if not image or b"/ColorSpace /DeviceRGB" not in image.group(1):
        raise ValueError("use the public perf_images_jpeg_large.pdf raster fixture")
    jpeg = source[image.end():image.end() + int(image.group(2))]
    if not jpeg.startswith(b"\xff\xd8") or not jpeg.endswith(b"\xff\xd9"):
        raise ValueError("expected a complete JPEG stream")

    pages = 64
    children = b" ".join(f"{number} 0 R".encode() for number in range(5, 5 + pages))
    commands = b"q 45 0 0 58 24 12 cm /Im Do Q\n" * 8
    page = (b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 96 80] "
            b"/Resources << /XObject << /Im 3 0 R >> >> /Contents 4 0 R >>")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Count 64 /Kids [" + children + b"] >>",
        image.group(1) + b"\nstream\n" + jpeg + b"\nendstream",
        f"<< /Length {len(commands)} >>\nstream\n".encode() + commands + b"endstream",
    ]
    objects.extend([page] * pages)

    output = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for number, body in enumerate(objects, 1):
        offsets.append(len(output))
        output.extend(f"{number} 0 obj\n".encode() + body + b"\nendobj\n")

    xref = len(output)
    size = len(offsets) + 1
    output.extend(f"xref\n0 {size}\n0000000000 65535 f \n".encode())
    for offset in offsets:
        output.extend(f"{offset:010d} 00000 n \n".encode())
    output.extend(f"trailer\n<< /Root 1 0 R /Size {size} >>\nstartxref\n{xref}\n%%EOF\n".encode())
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="pinned perf_images_jpeg_large.pdf fixture")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.write_bytes(generate(args.source.read_bytes()))


if __name__ == "__main__":
    main()
