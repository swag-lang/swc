"""Generate a multi-page workload with shared or individually stored JPEGs."""

import argparse
from pathlib import Path
import re


def generate(source, distinct=0):
    # The pinned PDF.js large-JPEG fixture has one direct, RGB DCT stream.
    image = re.search(rb"(<<[^>]+/Filter /DCTDecode /Length (\d+)>>)\r?\nstream\r?\n", source)
    if not image or b"/ColorSpace /DeviceRGB" not in image.group(1):
        raise ValueError("use the public perf_images_jpeg_large.pdf raster fixture")
    jpeg = source[image.end():image.end() + int(image.group(2))]
    if not jpeg.startswith(b"\xff\xd8") or not jpeg.endswith(b"\xff\xd9"):
        raise ValueError("expected a complete JPEG stream")

    if distinct:
        return serialize_pdf(distinct_image_objects(image.group(1), jpeg, distinct), b"%PDF-1.7\n")

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
    return serialize_pdf(objects, b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")


def distinct_image_objects(header, jpeg, pages):
    children = b" ".join(f"{3 + index * 2} 0 R".encode() for index in range(pages))
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        f"<< /Type /Pages /Count {pages} /Kids [".encode() + children + b"] >>",
    ]
    contents = 3 + pages * 2
    dictionary = header.rsplit(b"/Length ", 1)[0] + b"/Length "
    for index in range(pages):
        obj = 4 + index * 2
        objects.append(
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 96 80] "
            + f"/Resources << /XObject << /Im {obj} 0 R >> >> /Contents {contents} 0 R >>".encode()
        )
        # A unique JPEG comment changes the retained stream without changing the image.
        serial = 65 + index
        comment = serial.to_bytes(max(1, (serial.bit_length() + 7) // 8), "big")
        marker = b"\xff\xfe" + (len(comment) + 2).to_bytes(2, "big") + comment
        stream = jpeg[:2] + marker + jpeg[2:]
        objects.append(dictionary + f"{len(stream)}>>\nstream\n".encode() + stream + b"\nendstream")
    commands = b"45 0 0 58 24 12 cm /Im Do\n"
    objects.append(f"<< /Length {len(commands)} >>\nstream\n".encode() + commands + b"endstream")
    return objects


def serialize_pdf(objects, header):
    output = bytearray(header)
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
    parser.add_argument("--distinct", type=int, default=0, metavar="PAGES",
                        help="write this many pages with one distinct JPEG stream per page")
    args = parser.parse_args()
    if args.distinct < 0:
        parser.error("--distinct must be nonnegative")
    args.output.write_bytes(generate(args.source.read_bytes(), args.distinct))


if __name__ == "__main__":
    main()
