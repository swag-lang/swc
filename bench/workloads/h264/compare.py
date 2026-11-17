"""Compare Swag H.264 and x264 on identical NV12 input; retain all evidence outside the checkout."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--library-bin', type=Path, help='bin tree of an external source snapshot (default: this checkout)')
    parser.add_argument('--input', type=Path, nargs='+', required=True, help='one or more bottom-up packed RGB8 clips with the same dimensions and picture count')
    parser.add_argument('--width', type=int, required=True)
    parser.add_argument('--height', type=int, required=True)
    parser.add_argument('--frames', type=int, default=30)
    parser.add_argument('--qp', type=int, nargs='+', default=[18, 26, 28])
    parser.add_argument('--slices', type=int, default=4)
    parser.add_argument('--output', type=Path, required=True, help='new evidence directory outside the checkout')
    parser.add_argument('--skip-x264', action='store_true', help='measure only a new Swag candidate')
    parser.add_argument('--timeout', type=int, default=1200, help='seconds per command, including initial dependency builds')
    parser.add_argument('--quality-only', action='store_true', help='omit timing results; collect deterministic size and quality under other machine load')
    args = parser.parse_args()
    workload = Path(__file__).resolve().parent
    repo = workload.parents[2]
    output = args.output.resolve()
    if output == repo or repo in output.parents or output.exists():
        parser.error('--output needs a new directory outside the checkout')
    if args.width <= 0 or args.height <= 0 or args.width % 2 or args.height % 2 or args.frames <= 0:
        parser.error('dimensions need positive even values; frame count needs a positive value')
    if any(path.stat().st_size != args.width * args.height * 3 * args.frames for path in args.input):
        parser.error('input size differs from the dimensions and frame count')
    if any(qp < 1 or qp > 51 for qp in args.qp) or args.slices <= 0:
        parser.error('QP accepts values 1 through 51; slice count needs a positive value')
    if args.timeout <= 0:
        parser.error('--timeout needs a positive value')
    if len(set(args.qp)) != len(args.qp):
        parser.error('a QP value is already specified')
    output.mkdir(parents=True)
    environment = os.environ.copy()
    library = args.library_bin.resolve() if args.library_bin else repo / 'bin'
    environment['SWAG_PATH'] = str(library)
    environment['SWAG_RUNTIME_THREADS'] = '3'
    commands = []

    def run(command, name):
        commands.append(command)
        started = time.perf_counter()
        log_path = output / (name + '.log')
        with log_path.open('w') as log:
            result = subprocess.run(command, cwd=output, env=environment, stdout=log,
                                    stderr=subprocess.STDOUT, text=True, timeout=args.timeout)
        elapsed = time.perf_counter() - started
        if result.returncode:
            raise RuntimeError(f'{name} failed: see {log_path}')
        return log_path.read_text(), elapsed

    def raw_options(pixel_format):
        return ['-f', 'rawvideo', '-pixel_format', pixel_format, '-video_size',
                f'{args.width}x{args.height}', '-framerate', '30']

    def quality(video, source, name):
        # Compare raw samples on both sides. A format filter on an untagged NV12 reference
        # can negotiate the tagged video's colour space and silently convert its values.
        planar = Path(str(source) + '.yuv420p')
        if not planar.exists():
            packed = source.read_bytes()
            luma_size = args.width * args.height
            frame_size = luma_size * 3 // 2
            if len(packed) % frame_size:
                raise RuntimeError('NV12 reference ends inside a picture')
            with planar.open('wb') as stream:
                for start in range(0, len(packed), frame_size):
                    frame = packed[start:start + frame_size]
                    chroma = frame[luma_size:]
                    stream.write(frame[:luma_size])
                    stream.write(chroma[::2])
                    stream.write(chroma[1::2])
        decoded = output / (name + '-ffmpeg.yuv')
        if not decoded.exists():
            run(['ffmpeg', '-v', 'error', '-xerror', '-nostdin', '-threads', '3', '-i', str(video),
                 '-pix_fmt', 'yuv420p', '-fps_mode', 'passthrough', '-f', 'rawvideo', str(decoded)], name + '-decode')
        if decoded.stat().st_size != planar.stat().st_size:
            raise RuntimeError('reference and decoded picture counts differ')
        values = {}
        for metric in ('psnr', 'ssim'):
            log, _ = run(['ffmpeg', '-hide_banner', '-nostdin', '-threads', '3',
                          *raw_options('yuv420p'), '-i', str(planar),
                          *raw_options('yuv420p'), '-i', str(decoded),
                          '-filter_complex_threads', '1', '-lavfi', f'[1:v][0:v]{metric}',
                          '-f', 'null', '-'], name + '-' + metric)
            line = next(line for line in reversed(log.splitlines()) if 'Parsed_' + metric in line)
            for key, value in re.findall(r'(y|u|v|average|Y|U|V|All):([0-9.]+|inf)', line):
                values[metric + '_' + key.lower()] = value if value == 'inf' else float(value)
        return values

    # A lossless, explicitly BT.709-tagged stream with a shifted start time must score exactly
    # like its raw input. This catches colour negotiation and timestamp alignment regressions.
    check_source = output / 'metric-check.nv12'
    luma_size = args.width * args.height
    check_source.write_bytes(bytes(16 + (index * 17 + index // args.width * 11) % 220
                                  for index in range(luma_size)) +
                             bytes(16 + (index * 23) % 224 for index in range(luma_size // 2)))
    check_video = output / 'metric-check.mkv'
    run(['ffmpeg', '-v', 'error', '-nostdin', *raw_options('nv12'), '-colorspace', 'bt709',
         '-color_range', 'tv', '-i', str(check_source), '-vf', 'setpts=PTS+5/TB', '-c:v', 'ffv1',
         '-pix_fmt', 'yuv420p', '-colorspace', 'bt709', '-color_range', 'tv',
         '-fps_mode', 'passthrough', '-threads', '3', str(check_video)], 'metric-check-encode')
    checked = quality(check_video, check_source, 'metric-check')
    if checked.get('psnr_average') != 'inf' or checked.get('ssim_all') != 1.0:
        raise RuntimeError('lossless metric reference differs after decoding')

    command = [str(args.compiler.resolve()), 'run', '-f', str(workload / 'src/h264.swg'),
               '--module-file', str(workload / 'module.swg'), '-bc', 'release',
               '--num-cores', '3', '--out-dir', str(output / 'bin'), '--work-dir', str(output / 'work')]
    cases = []
    for index, input_path in enumerate(args.input):
        prefix = f'clip{index}-' if len(args.input) > 1 else ''
        for qp in args.qp:
            name = prefix + f'swag-qp{qp}'
            video = output / (name + '.mp4')
            cases.append((input_path, prefix, qp, name, video))
            for value in (str(input_path.resolve()), args.width, args.height, args.frames, qp, args.slices, video):
                command += ['--run-arg', str(value)]
    log, _ = run(command, 'swag-batch')
    matches = re.findall(r'H264 frames=(\d+) qp=(\d+) slices=(\d+) us=(\d+) bytes=(\d+)', log)
    if len(matches) != len(cases):
        raise RuntimeError('missing encoder measurements')

    rows = []
    for (input_path, prefix, qp, name, video), match in zip(cases, matches):
        if tuple(map(int, match[:3])) != (args.frames, qp, args.slices):
            raise RuntimeError('missing encoder measurements')
        source = Path(str(video) + '.nv12')
        decoded = output / (name + '-ffmpeg.yuv')
        run(['ffmpeg', '-v', 'error', '-xerror', '-nostdin', '-threads', '3', '-i', str(video),
             '-pix_fmt', 'yuv420p', '-fps_mode', 'passthrough', '-f', 'rawvideo', str(decoded)], name + '-decode')
        if decoded.read_bytes() != Path(str(video) + '.yuv').read_bytes():
            raise RuntimeError('Swag Reader and FFmpeg decode different samples')
        row = dict(input=input_path.name, encoder='swag', qp=qp, slices=args.slices, frames=args.frames,
                   encode_us=None if args.quality_only else int(match[3]),
                   packet_bytes=int(match[4]), file_bytes=video.stat().st_size,
                   source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                   decoded_sha256=hashlib.sha256(decoded.read_bytes()).hexdigest(),
                   **quality(video, source, name))
        rows.append(row)
        print(json.dumps(row), flush=True)

        if args.skip_x264:
            continue
        # Baseline isolates coding decisions. The High and ultrafast profiles represent the
        # software encoder settings documented by OBS and shipped as ShareX defaults.
        for preset, profile, mode in [('veryfast', 'baseline', 'qp'), ('veryfast', 'high', 'crf'),
                                      ('ultrafast', 'baseline', 'crf')]:
            name = prefix + f'x264-{preset}-{profile}-{mode}{qp}'
            video = output / (name + '.mp4')
            options = ['-qp', str(qp)] if mode == 'qp' else ['-crf', str(qp)]
            log, elapsed = run(['ffmpeg', '-hide_banner', '-nostdin', *raw_options('nv12'), '-i', str(source),
                                '-c:v', 'libx264', '-threads', '3', '-preset', preset, '-profile:v', profile,
                                '-pix_fmt', 'yuv420p', '-g', '120', *options,
                                '-x264-params', f'scenecut=0:slices={args.slices}', str(video)], name)
            packets, _ = run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                              'packet=size', '-of', 'csv=p=0', str(video)], name + '-packets')
            row = dict(input=input_path.name, encoder='x264', preset=preset, profile=profile, mode=mode, quality=qp,
                       slices=args.slices, frames=args.frames,
                       process_seconds=None if args.quality_only else elapsed,
                       packet_bytes=sum(int(size) for size in packets.splitlines()),
                       file_bytes=video.stat().st_size, **quality(video, source, name))
            rows.append(row)
            print(json.dumps(row), flush=True)

    version, _ = run(['ffmpeg', '-version'], 'ffmpeg-version')
    commit, _ = run(['git', '-C', str(repo), 'rev-parse', 'HEAD'], 'commit')
    diff, _ = run(['git', '-C', str(repo), 'diff'], 'diff')
    (output / 'report.json').write_text(json.dumps(dict(commit=commit.strip(), dirty=bool(diff.strip()),
        library_bin=str(library),
        encoder_sha256=hashlib.sha256((library / 'std/modules/video/src/encode/h264/lossy.swg').read_bytes()).hexdigest(),
        driver_sha256=hashlib.sha256((workload / 'src/h264.swg').read_bytes()).hexdigest(),
        compiler_sha256=hashlib.sha256(args.compiler.read_bytes()).hexdigest(),
        ffmpeg=version.splitlines()[0], quality_only=args.quality_only,
        metric_alignment='raw planar samples, frame order', metric_self_check=checked,
        inputs=[dict(path=str(path.resolve()), sha256=hashlib.sha256(path.read_bytes()).hexdigest()) for path in args.input],
        rows=rows, commands=commands), indent=2) + '\n')


if __name__ == '__main__':
    main()
