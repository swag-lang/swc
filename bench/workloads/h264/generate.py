"""Generate small recording workloads outside the checkout; requires Pillow and FFmpeg."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='new external directory')
    parser.add_argument('--font', type=Path, required=True, help='explicit monospace TrueType font')
    parser.add_argument('--camera', type=Path, help='optional camera clip; take 30 pictures starting at two seconds')
    args = parser.parse_args()
    from PIL import Image, ImageDraw, ImageFont
    output = args.output.resolve()
    repo = Path(__file__).resolve().parents[3]
    if output.exists() or output == repo or repo in output.parents:
        parser.error('--output needs a new directory outside the checkout')
    font = ImageFont.truetype(str(args.font.resolve()), 13)
    output.mkdir(parents=True)
    width, height, count = 640, 360, 30

    with (output / 'desktop.rgb').open('wb') as stream:
        for frame in range(count):
            image = Image.new('RGB', (width, height), (28, 30, 36))
            draw = ImageDraw.Draw(image)
            draw.rectangle((0, 0, width, 28), fill=(46, 50, 60))
            draw.text((12, 6), 'Swag Capture | editor and moving window', font=font, fill=(230, 232, 236))
            for line in range(24):
                y = 32 + line * 16 - (frame // 3) * 8
                if y >= 28:
                    draw.text((10, y), f'{line:02d}  func encodeFrame(source: const *Nv12Frame)',
                              font=font, fill=(105 + line * 4, 175, 205))
            x, y = 260 + frame * 3, 75 + frame
            draw.rectangle((x, y, x + 215, y + 150), fill=(232, 230, 218), outline=(85, 126, 172), width=2)
            draw.rectangle((x + 2, y + 2, x + 213, y + 23), fill=(78, 112, 158))
            draw.text((x + 8, y + 4), 'Recording', font=font, fill='white')
            for row in range(6):
                draw.text((x + 10, y + 32 + row * 17), f'progress {frame:02d} / {row * 17:03d}',
                          font=font, fill=(25, 38, 51))
            stream.write(image.transpose(Image.Transpose.FLIP_TOP_BOTTOM).tobytes())

    with (output / 'gradient.rgb').open('wb') as stream:
        for frame in range(count):
            image = Image.new('RGB', (width, height))
            draw = ImageDraw.Draw(image)
            for y in range(0, height, 16):
                for x in range(0, width, 16):
                    bx, by = x // 16, y // 16
                    color = ((bx * 7 + by * 3 + frame * 2) % 220 + 16,
                             (bx * 3 + by * 9 + frame) % 220 + 16,
                             (bx * 5 + by * 5 + frame * 3) % 220 + 16)
                    draw.rectangle((x, y, x + 15, y + 15), fill=color)
            stream.write(image.transpose(Image.Transpose.FLIP_TOP_BOTTOM).tobytes())

    commands = [['ffmpeg', '-v', 'error', '-nostdin', '-f', 'lavfi', '-i',
                 'testsrc2=size=640x360:rate=30', '-frames:v', str(count), '-vf', 'vflip',
                 '-pix_fmt', 'rgb24', '-threads', '3', '-f', 'rawvideo', str(output / 'testsrc.rgb')]]
    if args.camera:
        commands.append(['ffmpeg', '-v', 'error', '-nostdin', '-ss', '2', '-i', str(args.camera.resolve()),
                         '-frames:v', str(count), '-vf', 'scale=640:360,vflip', '-pix_fmt', 'rgb24',
                         '-threads', '3', '-f', 'rawvideo', str(output / 'street.rgb')])
    for command in commands:
        subprocess.run(command, check=True)
    hashes = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in output.glob('*.rgb')}
    for path in output.glob('*.rgb'):
        if path.stat().st_size != width * height * 3 * count:
            raise RuntimeError(f'{path} does not contain {count} complete pictures')
    manifest = dict(width=width, height=height, frames=count, commands=commands, sha256=hashes,
                    font_sha256=hashlib.sha256(args.font.read_bytes()).hexdigest())
    if args.camera:
        manifest['camera_sha256'] = hashlib.sha256(args.camera.read_bytes()).hexdigest()
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()
