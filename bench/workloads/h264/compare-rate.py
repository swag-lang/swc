"""Measure H.264 average bitrate and luma fidelity across scene changes."""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess

import numpy as np


WORKLOAD = Path(__file__).resolve().parent
REPO = WORKLOAD.parents[2]
WIDTH, HEIGHT, FPS = 640, 360, 30
LUMA = WIDTH * HEIGHT
NV12_BYTES = LUMA * 3 // 2
SCENES = ('desktop', 'gradient', 'street', 'desktop')
SCENE_FRAMES = FPS * 2
COUNT = len(SCENES) * SCENE_FRAMES


def run(command, log, env):
    with log.open('w') as capture:
        subprocess.run(command, env=env, stdout=capture, stderr=subprocess.STDOUT, check=True)
    return log.read_text()


def digest(path):
    with path.open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()


def psnr(squared_error, frames):
    return 10 * math.log10(255**2 * LUMA * frames / squared_error) if squared_error else 'inf'


def analyze(video, source):
    command = ['ffmpeg', '-nostdin', '-v', 'error', '-xerror', '-threads', '1', '-i', video,
               '-map', '0:v:0', '-an', '-sn', '-dn', '-fps_mode', 'passthrough',
               '-c:v', 'rawvideo', '-threads', '1', '-pix_fmt', 'yuv420p', '-f', 'rawvideo', 'pipe:1']
    squares = []
    with subprocess.Popen(command, stdout=subprocess.PIPE) as decoder, source.open('rb') as original:
        for index in range(COUNT):
            decoded = decoder.stdout.read(NV12_BYTES)
            packed = original.read(NV12_BYTES)
            if len(decoded) != NV12_BYTES or len(packed) != NV12_BYTES:
                raise ValueError(f'{video.name} has an incomplete picture at rank {index}')
            delta = (np.frombuffer(decoded, dtype=np.uint8, count=LUMA).astype(np.int32)
                     - np.frombuffer(packed, dtype=np.uint8, count=LUMA))
            squares.append(int(np.sum(delta * delta, dtype=np.int64)))
        if decoder.stdout.read(1) or original.read(1) or decoder.wait():
            raise ValueError(f'{video.name} differs from the expected decoded picture count')

    packet_json = subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', 'v:0',
                                           '-show_packets', '-show_entries', 'packet=size,pts_time',
                                           '-of', 'json', video])
    packets = json.loads(packet_json)['packets']
    if len(packets) != COUNT or any(abs(float(packet['pts_time']) - index / FPS) > 0.000002
                                    for index, packet in enumerate(packets)):
        raise ValueError(f'{video.name} differs from the input timeline')
    sizes = [int(packet['size']) for packet in packets]
    return dict(achieved_bps=sum(sizes) * 8 * FPS / COUNT, frame_packet_bytes=sizes,
                second_bits=[8 * sum(sizes[index:index + FPS]) for index in range(0, COUNT, FPS)],
                luma_psnr_db=psnr(sum(squares), COUNT),
                scene_luma_psnr_db=[psnr(sum(squares[index:index + SCENE_FRAMES]), SCENE_FRAMES)
                                   for index in range(0, COUNT, SCENE_FRAMES)])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--library-bin', type=Path, default=REPO / 'bin')
    parser.add_argument('--input-dir', type=Path, required=True, help='RGB inputs from generate.py')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--target-kbps', type=int, nargs='+', default=[800, 1500, 2500])
    args = parser.parse_args()
    output = args.output.resolve()
    library = args.library_bin.resolve()
    if output.exists() or any(root == output or root in output.parents for root in (REPO, library)):
        parser.error('--output must be a new directory outside the source trees')
    if any(rate <= 0 for rate in args.target_kbps) or len(set(args.target_kbps)) != len(args.target_kbps):
        parser.error('target bitrates must be positive and distinct')

    paths = [args.input_dir / (scene + '.rgb') for scene in SCENES]
    if any(path.stat().st_size != LUMA * 3 * FPS for path in paths):
        parser.error('each raw input needs thirty 640x360 RGB8 pictures')
    output.mkdir(parents=True)
    input_rgb = output / 'transitions.rgb'
    with input_rgb.open('wb') as stream:
        for path in paths:
            for _ in range(SCENE_FRAMES // FPS):
                with path.open('rb') as source:
                    shutil.copyfileobj(source, stream)

    environment = {**os.environ, 'SWAG_PATH': str(library), 'SWAG_RUNTIME_THREADS': '2'}
    nv12 = output / 'transitions.nv12'
    rows = []
    for rate in args.target_kbps:
        target = rate * 1000
        before = output / f'swag-{rate}.mp4'
        command = [args.compiler.resolve(), 'run', '-f', WORKLOAD / 'rate/rate.swg',
                   '--module-file', WORKLOAD / 'module.swg', '-bc', 'release', '--num-cores', '2',
                   '--out-dir', output / 'bin', '--work-dir', output / 'work']
        for value in (target, 4, input_rgb, before):
            command.extend(['--run-arg', str(value)])
        if not nv12.exists():
            command.extend(['--run-arg', str(nv12)])
        trace = run(command, output / f'swag-{rate}.log', environment)
        qp = [int(value) for value in re.findall(r'^rate frame=\d+ qp=(\d+) ', trace, re.M)]
        if len(qp) != COUNT:
            raise ValueError(f'{before.name} needs {COUNT} quantizer observations')
        rows.append(dict(encoder='swag', target_bps=target, qp=qp, **analyze(before, nv12)))

        reference = output / f'x264-{rate}.mp4'
        command = ['ffmpeg', '-nostdin', '-v', 'error', '-f', 'rawvideo', '-pix_fmt', 'nv12',
                   '-s:v', f'{WIDTH}x{HEIGHT}', '-framerate', str(FPS), '-i', nv12,
                   '-frames:v', str(COUNT), '-an', '-c:v', 'libx264', '-profile:v', 'baseline',
                   '-preset', 'veryfast', '-threads', '2', '-b:v', str(target), '-maxrate', str(target),
                   '-bufsize', str(target // 2), '-x264-params', 'keyint=120:scenecut=0:slices=4', reference]
        run(command, output / f'x264-{rate}.log', environment)
        rows.append(dict(encoder='x264', target_bps=target, **analyze(reference, nv12)))

    version = subprocess.check_output(['ffmpeg', '-version'], text=True).splitlines()[0]
    report = dict(ffmpeg=version, scenes=SCENES, frames=COUNT, frames_per_scene=SCENE_FRAMES,
                  source_nv12_sha256=digest(nv12), source_rgb_sha256=digest(input_rgb), results=rows)
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
