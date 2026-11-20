#!/usr/bin/env python3
"""Generate original DDS and KTX2 two-layer, two-mip texture fixtures."""
from pathlib import Path
import struct
import subprocess
import tempfile
import numpy as np
import OpenEXR

ROOT = Path(__file__).resolve().parent.parent


def rgba(layer: int, level: int, width: int, height: int) -> bytes:
    # Each layer/mip has a distinct solid color, making subresource selection visible.
    colors = ((36, 130, 196, 255), (222, 112, 45, 255))
    color = colors[layer]
    if level:
        color = tuple((channel + 28) // 2 for channel in color[:3]) + (255,)
    return bytes(color) * width * height


def dds() -> bytes:
    # DDS_HEADER and DDS_HEADER_DXT10: RGBA8 2D array, two layers, two mips.
    flags = 0x0002100F  # CAPS | HEIGHT | WIDTH | PITCH | PIXELFORMAT | MIPMAPCOUNT
    header = struct.pack(
        '<7I11I',
        124, flags, 2, 2, 8, 0, 2,
        *([0] * 11),
    )
    pixel_format = struct.pack('<II4sIIIII', 32, 4, b'DX10', 0, 0, 0, 0, 0)
    caps = struct.pack('<5I', 0x00401008, 0, 0, 0, 0)
    dx10 = struct.pack('<5I', 28, 3, 0, 2, 0)  # DXGI_FORMAT_R8G8B8A8_UNORM
    payload = b''.join(
        rgba(layer, level, max(2 >> level, 1), max(2 >> level, 1))
        for layer in range(2) for level in range(2)
    )
    return b'DDS ' + header + pixel_format + caps + dx10 + payload


def ktx2() -> bytes:
    # KTX2 RGBA8_UNORM, two layers, two mip levels, no supercompression.
    ident = b'\xabKTX 20\xbb\r\n\x1a\n'
    dfd = bytes.fromhex('1c000000000000000000000000000000000000000000000000000000')
    dfd_offset = 128
    level1_offset = dfd_offset + len(dfd)
    level1 = b''.join(rgba(layer, 1, 1, 1) for layer in range(2))
    level0_offset = level1_offset + len(level1)
    level0 = b''.join(rgba(layer, 0, 2, 2) for layer in range(2))
    header = struct.pack(
        '<13I2Q',
        37, 1, 2, 2, 0, 2, 1, 2, 0,
        dfd_offset, len(dfd), 0, 0, 0, 0,
    )
    level_index = struct.pack(
        '<QQQ', level0_offset, len(level0), len(level0)
    ) + struct.pack('<QQQ', level1_offset, len(level1), len(level1))
    return ident + header + level_index + dfd + level1 + level0


def psd() -> bytes:
    """Ask ImageMagick to write three original synthetic image layers to PSD."""
    frames = ((4, 4, (36, 130, 196)), (2, 2, (222, 112, 45)), (2, 2, (66, 168, 94)))
    with tempfile.TemporaryDirectory(prefix='swagscope-texture-') as temp:
        directory = Path(temp)
        paths = []
        for index, (width, height, color) in enumerate(frames):
            path = directory / f'layer-{index}.ppm'
            pixels = bytes(color) * width * height
            path.write_bytes(f'P6\n{width} {height}\n255\n'.encode('ascii') + pixels)
            paths.append(path)
        output = directory / 'layers.psd'
        subprocess.run(
            ['magick', *(str(path) for path in paths), '-depth', '8', str(output)],
            check=True,
        )
        return output.read_bytes()


def exr() -> bytes:
    """Create two original 2x2 scanline parts with distinct floating-point colors."""
    parts = []
    for name, color in (('watershed', (0.14, 0.51, 0.77)), ('sample-grid', (0.82, 0.33, 0.12))):
        header = {'type': OpenEXR.scanlineimage, 'compression': OpenEXR.NO_COMPRESSION}
        channels = {
            channel: np.full((2, 2), value, dtype=np.float32)
            for channel, value in zip(('R', 'G', 'B'), color)
        }
        parts.append(OpenEXR.Part(header, channels, name))
    with tempfile.TemporaryDirectory(prefix='swagscope-texture-') as temp:
        output = Path(temp) / 'parts.exr'
        OpenEXR.File(parts).write(str(output))
        return output.read_bytes()


for name, data in (
    ('imageset-array.dds', dds()),
    ('imageset-array.ktx2', ktx2()),
    ('imageset-layers-0.psd', psd()),
    ('imageset-parts.exr', exr()),
):
    (ROOT / name).write_bytes(data)
    canonical = {
        'imageset-array.dds': 'viewer.dds',
        'imageset-array.ktx2': 'viewer.ktx2',
        'imageset-layers-0.psd': 'viewer.psd',
        'imageset-parts.exr': 'viewer.exr',
    }[name]
    (ROOT / canonical).write_bytes(data)
