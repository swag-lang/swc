"""Generate inputs for the video decode comparison."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


REPO = Path(__file__).resolve().parents[3]
AVC = ["-c:v", "libx264", "-preset", "fast", "-crf", "20"]
HEVC = ["-c:v", "libx265", "-preset", "fast", "-crf", "22"]
MPEG4 = ["-c:v", "mpeg4", "-q:v", "4"]
AVC_OPTIONS = "slices=1:keyint=60:scenecut=0"
HEVC_OPTIONS = "frame-threads=1:scenecut=0:log-level=error"
TEXTURE = "noise=alls=12:allf=t+u:all_seed=27"


def fixtures():
    return (
        ("avc-high-fades.mp4", "960x540", 120, "fade=t=in:s=0:n=36,fade=t=out:s=84:n=36",
         [*AVC, "-profile:v", "high", "-x264-params", f"{AVC_OPTIONS}:weightp=2"]),
        ("avc-baseline-texture.mp4", "960x540", 120, TEXTURE,
         [*AVC, "-profile:v", "baseline", "-x264-params", AVC_OPTIONS]),
        ("avc-high444.mp4", "640x360", 90, None,
         [*AVC, "-profile:v", "high444", "-pix_fmt", "yuv444p", "-x264-params", AVC_OPTIONS]),
        ("avc-high-six-slices-4k.mp4", "3840x2160", 105, None,
         ["-c:v", "libx264", "-preset", "fast", "-profile:v", "high", "-crf", "23",
          "-x264-params", "slices=6:keyint=36:scenecut=0"]),
        ("hevc-main-wpp.mp4", "1280x720", 90, None,
         [*HEVC, "-profile:v", "main", "-x265-params", f"{HEVC_OPTIONS}:pools=2:wpp=1:keyint=60"]),
        ("hevc-main10-intra.mp4", "960x540", 90, None,
         [*HEVC, "-pix_fmt", "yuv420p10le", "-x265-params", f"{HEVC_OPTIONS}:pools=none:wpp=0:keyint=1"]),
        ("hevc-main10-texture.mp4", "960x540", 120, TEXTURE,
         [*HEVC, "-pix_fmt", "yuv420p10le", "-x265-params", f"{HEVC_OPTIONS}:pools=none:wpp=0:keyint=60"]),
        ("mpeg4-simple-720p.avi", "1280x720", 120, None,
         [*MPEG4, "-bf", "0", "-g", "60"]),
        ("mpeg4-weighted-720p.avi", "1280x720", 120, None,
         [*MPEG4, "-bf", "0", "-g", "60", "-mpeg_quant", "1"]),
        ("mpeg4-intra-texture.avi", "640x360", 90, TEXTURE,
         [*MPEG4, "-bf", "0", "-g", "1"]),
        ("mpeg4-bvop-matrix.mkv", "960x540", 90, None,
         [*MPEG4, "-bf", "2", "-g", "30", "-mpeg_quant", "1", "-flags", "+mv4"]),
    )


def rgb_fixtures():
    return (
        ("y4m-420-limited-1080p.y4m", "1920x1080", 36, None, ["-pix_fmt", "yuv420p"]),
        ("y4m-420-full-odd.y4m", "650x370", 36, "scale=651:371:out_range=full:flags=neighbor",
         ["-pix_fmt", "yuv420p", "-color_range", "pc"]),
        ("y4m-411.y4m", "652x370", 36, None, ["-pix_fmt", "yuv411p", "-strict", "-1"]),
        ("y4m-422.y4m", "1280x720", 36, None, ["-pix_fmt", "yuv422p", "-strict", "-1"]),
        ("y4m-444.y4m", "1280x720", 36, None, ["-pix_fmt", "yuv444p", "-strict", "-1"]),
        ("y4m-mono.y4m", "650x370", 36, None, ["-pix_fmt", "gray"]),
        ("mjpeg-420-1080p.avi", "1920x1080", 72, None, ["-c:v", "mjpeg", "-q:v", "4", "-pix_fmt", "yuvj420p"]),
        ("mjpeg-422-720p.avi", "1280x720", 72, TEXTURE, ["-c:v", "mjpeg", "-q:v", "4", "-pix_fmt", "yuvj422p"]),
        ("mjpeg-444-720p.avi", "1280x720", 72, None, ["-c:v", "mjpeg", "-q:v", "4", "-pix_fmt", "yuvj444p"]),
    )


def avc_slice_fixtures():
    return tuple(
        (f"avc-high-{slices}-slices.mp4", "1920x1080", 96, None,
         ["-c:v", "libx264", "-preset", "fast", "-profile:v", "high", "-crf", "23",
          "-x264-params", f"slices={slices}:scenecut=0:keyint=32"])
        for slices in (1, 8, 32)
    )


def raw_avi_fixtures():
    return (
        ("raw-bgr24.avi", "1280x720", 32, None, ["-c:v", "rawvideo", "-pix_fmt", "bgr24"]),
        ("raw-bgra-odd.avi", "652x370", 32, "scale=653:371:flags=neighbor",
         ["-c:v", "rawvideo", "-pix_fmt", "bgra"]),
        ("raw-rgb555.avi", "960x540", 32, None, ["-c:v", "rawvideo", "-pix_fmt", "rgb555le"]),
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    profile = parser.add_mutually_exclusive_group()
    profile.add_argument("--rgb", action="store_true", help="generate Y4M and Motion JPEG fixtures")
    profile.add_argument("--avc-slices", action="store_true", help="generate 1080p H.264 with one, eight and 32 slices")
    profile.add_argument("--raw-avi", action="store_true", help="generate uncompressed AVI in three RGB layouts")
    args = parser.parse_args()
    output = args.output.resolve()
    if output == REPO or REPO in output.parents:
        parser.error("--output must be outside the checkout")
    output.mkdir(parents=True)
    records = []
    if args.rgb:
        selected = rgb_fixtures()
    elif args.avc_slices:
        selected = avc_slice_fixtures()
    elif args.raw_avi:
        selected = raw_avi_fixtures()
    else:
        selected = fixtures()
    for name, size, count, filters, encoder in selected:
        path = output / name
        command = ["ffmpeg", "-nostdin", "-v", "error", "-filter_threads", "1",
                   "-f", "lavfi", "-i", "testsrc2=size=" + size + ":rate=30"]
        if filters:
            command.extend(("-vf", filters))
        command.extend(("-frames:v", str(count), "-an", "-threads", "1", *encoder, path.name))
        subprocess.run(command, cwd=output, check=True)
        with path.open("rb") as movie:
            digest = hashlib.file_digest(movie, "sha256").hexdigest()
        records.append({"file": path.name, "sha256": digest, "command": command})
    version = subprocess.check_output(["ffmpeg", "-version"], text=True).splitlines()[0]
    (output / "manifest.json").write_text(json.dumps({"ffmpeg": version, "fixtures": records}, indent=2) + "\n")


if __name__ == "__main__":
    main()
