"""Generate lossless streams whose frames always use verbatim subframes."""

import hashlib
from random import Random

SAMPLE_RATE = 48_000
FRAME_SAMPLES = 4096
FRAMES = 144


def crc_table(width, polynomial):
    mask = (1 << width) - 1
    high = 1 << (width - 1)
    table = []
    for byte in range(256):
        value = byte << (width - 8)
        for _ in range(8):
            value = ((value << 1) ^ (polynomial if value & high else 0)) & mask
        table.append(value)
    return table


def write_fixture(path, bits, depth_code, crc8, crc16):
    source = Random(bits + 2026)
    channel_bytes = FRAME_SAMPLES * (bits // 8)
    with path.open("wb") as stream:
        # A single STREAMINFO block describes a stereo stream with fixed-size frames.
        stream.write(b"fLaC\x80\x00\x00\x22")
        stream.write(FRAME_SAMPLES.to_bytes(2, "big") * 2 + bytes(6))
        properties = (SAMPLE_RATE << 44) | (1 << 41) | ((bits - 1) << 36) | (FRAMES * FRAME_SAMPLES)
        stream.write(properties.to_bytes(8, "big") + bytes(16))
        for frame_index in range(FRAMES):
            # Fixed blocking, 4,096 samples, 48 kHz, and two independent channels.
            header = bytes((0xFF, 0xF8, 0xCA, 0x10 | depth_code << 1))
            header += chr(frame_index).encode("utf-8")
            header_crc = 0
            for byte in header:
                header_crc = crc8[header_crc ^ byte]
            frame = header + bytes((header_crc,))
            for _ in range(2):
                frame += b"\x02" + source.randbytes(channel_bytes)
            frame_crc = 0
            for byte in frame:
                frame_crc = (frame_crc & 255) << 8 ^ crc16[(frame_crc >> 8) ^ byte]
            stream.write(frame + frame_crc.to_bytes(2, "big"))


def write_verbatim_fixtures(folder):
    crc8 = crc_table(8, 7)
    crc16 = crc_table(16, 0x8005)
    for bits, depth_code in ((16, 4), (24, 6), (32, 7)):
        name = f"flac-verbatim-48k-stereo-{bits}.flac"
        path = folder / name
        write_fixture(path, bits, depth_code, crc8, crc16)
        with path.open("rb") as fixture:
            digest = hashlib.file_digest(fixture, "sha256").hexdigest()
        yield {
            "fixture": name,
            "source_rate": SAMPLE_RATE,
            "source_layout": "stereo",
            "source_frames": FRAMES * FRAME_SAMPLES,
            "verbatim_bits": bits,
            "size_bytes": path.stat().st_size,
            "sha256": digest,
        }
