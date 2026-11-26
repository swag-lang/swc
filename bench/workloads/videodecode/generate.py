"""Generate deterministic AVC and HEVC inputs for the video decode comparison."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


REPO = Path(__file__).resolve().parents[3]
AVC = ["-c:v", "libx264", "-preset", "fast", "-crf", "20"]
HEVC = ["-c:v", "libx265", "-preset", "fast", "-crf", "22"]
AVC_OPTIONS = "slices=1:keyint=60:scenecut=0"
HEVC_OPTIONS = "frame-threads=1:scenecut=0:log-level=error"
TEXTURE = "noise=alls=12:allf=t+u:all_seed=27"


def fixtures():
    return (
        ("avc-high-fades", "960x540", 120, "fade=t=in:s=0:n=36,fade=t=out:s=84:n=36",
         [*AVC, "-profile:v", "high", "-x264-params", f"{AVC_OPTIONS}:weightp=2"]),
        ("avc-baseline-texture", "960x540", 120, TEXTURE,
         [*AVC, "-profile:v", "baseline", "-x264-params", AVC_OPTIONS]),
        ("avc-high444", "640x360", 90, None,
         [*AVC, "-profile:v", "high444", "-pix_fmt", "yuv444p", "-x264-params", AVC_OPTIONS]),
        ("hevc-main-wpp", "1280x720", 90, None,
         [*HEVC, "-profile:v", "main", "-x265-params", f"{HEVC_OPTIONS}:pools=2:wpp=1:keyint=60"]),
        ("hevc-main10-intra", "960x540", 90, None,
         [*HEVC, "-pix_fmt", "yuv420p10le", "-x265-params", f"{HEVC_OPTIONS}:pools=none:wpp=0:keyint=1"]),
        ("hevc-main10-texture", "960x540", 120, TEXTURE,
         [*HEVC, "-pix_fmt", "yuv420p10le", "-x265-params", f"{HEVC_OPTIONS}:pools=none:wpp=0:keyint=60"]),
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if output == REPO or REPO in output.parents:
        parser.error("--output must be outside the checkout")
    output.mkdir(parents=True)
    records = []
    for name, size, count, filters, encoder in fixtures():
        path = output / (name + ".mp4")
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
