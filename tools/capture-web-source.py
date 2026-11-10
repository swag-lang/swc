"""Prepare a native 1080p movie excerpt with reference sound for capture-web.py.

Requires PyAV and NumPy. The supplied movie remains unchanged; generated media must
stay outside the checkout. This is a test-source utility, not a Capture dependency.
"""

import argparse
from fractions import Fraction
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--start', type=float, default=30)
    args = parser.parse_args()
    source = args.input.resolve(strict=True)
    target = args.output.resolve()
    repo = Path(__file__).resolve().parent.parent
    if target == repo or repo in target.parents or target == source:
        parser.error('--output must be outside the checkout and differ from --input')
    if target.exists():
        parser.error('--output already exists')
    if args.start < 0:
        parser.error('--start must be nonnegative')
    check = repo / '.agents/skills/modify-swag-codebase/scripts/check-machine-load.ps1'
    result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(check)], cwd=repo)
    if result.returncode:
        return result.returncode
    import av
    import numpy as np

    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        with av.open(str(source)) as movie:
            stream = movie.streams.video[0]
            if (stream.width, stream.height) != (1920, 1080):
                raise ValueError('the source must contain native 1920 by 1080 pictures')
            rate = stream.average_rate
            wanted = round(8 * rate)
            movie.seek(int(args.start / stream.time_base), stream=stream)
            with av.open(str(target), 'w', format='mp4') as output:
                video = output.add_stream('libx264', rate=rate,
                                          options={'preset': 'veryfast', 'crf': '20', 'threads': '3'})
                video.width, video.height, video.pix_fmt = 1920, 1080, 'yuv420p'
                audio = output.add_stream('aac', rate=48000)
                audio.layout, audio.bit_rate = 'stereo', 192000
                count = 0
                for frame in movie.decode(stream):
                    if frame.time < args.start:
                        continue
                    frame = frame.reformat(format='yuv420p')
                    frame.pts, frame.time_base = count, Fraction(1, rate)
                    for packet in video.encode(frame):
                        output.mux(packet)
                    count += 1
                    if count == wanted:
                        break
                if count != wanted:
                    raise ValueError('the source must have eight seconds after --start')
                for packet in video.encode():
                    output.mux(packet)
                for start in range(0, 8 * 48000, 1024):
                    samples = min(1024, 8 * 48000 - start)
                    tone = (.28 * np.sin(2 * np.pi * 440 * (start + np.arange(samples)) / 48000)).astype('float32')
                    frame = av.AudioFrame.from_ndarray(np.stack((tone, tone)), format='fltp', layout='stereo')
                    frame.sample_rate, frame.pts, frame.time_base = 48000, start, Fraction(1, 48000)
                    for packet in audio.encode(frame):
                        output.mux(packet)
                for packet in audio.encode():
                    output.mux(packet)
    except BaseException:
        target.unlink(missing_ok=True)
        raise
    print(target)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
