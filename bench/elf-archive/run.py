"""Compare the former GNU ar MRI path with SWC's in-memory ELF archive writer.

Requires a completed tools/linux-build.py build. All working files stay outside the checkout.
"""
import argparse
import json
import platform
import shlex
from pathlib import Path
import statistics
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=Path, required=True, help='configuration directory containing compiler objects')
    parser.add_argument('--counts', type=int, nargs='+', default=[1, 100, 1000, 10000])
    parser.add_argument('--rounds', type=int, default=7)
    parser.add_argument('--output', type=Path, required=True, help='JSON results outside the checkout')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    if output.is_relative_to(root) or args.rounds < 1 or any(count < 1 for count in args.counts):
        parser.error('use positive counts/rounds and an output outside the checkout')
    build = args.build_dir.resolve()
    build_command = shlex.split((build / 'build-command.txt').read_text())
    flags = build_command[1:]
    objects = sorted((build / 'src').rglob('*.o'))
    objects = [obj for obj in objects if obj != build / 'src/main.o']
    if not objects:
        parser.error('no compiler objects found')
    subprocess.run(['python3', str(root / '.agents/skills/modify-swag-codebase/scripts/check-machine-load.py')], check=True)
    with tempfile.TemporaryDirectory(prefix='swc-elf-archive-') as scratch:
        scratch = Path(scratch)
        binary = scratch / 'measure'
        command = [build_command[0], *flags, str(Path(__file__).with_name('measure.cpp')), *map(str, objects),
                   '-pthread', '-rdynamic', '-ldl', '-o', str(binary)]
        subprocess.run(command, check=True)
        subprocess.run(['python3', str(root / '.agents/skills/modify-swag-codebase/scripts/check-machine-load.py')], check=True)
        rows = []
        samples = []
        for count in args.counts:
            result = subprocess.run([str(binary), str(scratch / str(count)), str(count), str(args.rounds)], check=True, text=True, capture_output=True)
            for line in result.stdout.splitlines():
                members, round_, implementation, milliseconds, size = line.split(',')
                samples.append(dict(members=int(members), round=int(round_), implementation=implementation, milliseconds=float(milliseconds), bytes=int(size)))
            # Both archives must expose the same symbols and link an actual consumer.
            directory = scratch / str(count)
            indexes = [subprocess.check_output(['nm', '--defined-only', '--format=just-symbols', str(directory / name)], text=True)
                       for name in ('gnu.a', 'internal.a')]
            symbols = [sorted(line for line in index.splitlines() if line.startswith('function_')) for index in indexes]
            if symbols[0] != symbols[1] or len(symbols[0]) != count:
                raise RuntimeError('archive symbol indexes differ')
            source = directory / 'consumer.c'
            source.write_text(f'extern int function_0(void); extern int function_{count - 1}(void);\nint main(void) {{ return function_0() + function_{count - 1}() != 84; }}\n')
            for name in ('gnu.a', 'internal.a'):
                consumer = directory / 'consumer'
                subprocess.run(['cc', '-no-pie', str(source), str(directory / name), '-o', str(consumer)], check=True)
                subprocess.run([str(consumer)], check=True)
            medians = {implementation: statistics.median(s['milliseconds'] for s in samples if s['members'] == count and s['implementation'] == implementation)
                       for implementation in ('ar', 'internal')}
            rows.append(dict(members=count, **medians, saved_ms=medians['ar'] - medians['internal'],
                             reduction_percent=100 * (1 - medians['internal'] / medians['ar']),
                             speedup=medians['ar'] / medians['internal']))
        data = dict(scope='warm end-to-end archive publication from in-memory ELF objects, including temporary cleanup; excludes object generation',
                    toolchain=subprocess.check_output(['ar', '--version'], text=True).splitlines()[0],
                    platform=platform.platform(),
                    cpu=next(line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')),
                    cpu_quota=Path('/sys/fs/cgroup/cpu.max').read_text().strip(),
                    compiler=subprocess.check_output([build_command[0], '--version'], text=True).splitlines()[0],
                    compiler_flags=flags,
                    rounds=args.rounds, summary=rows, samples=samples)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(data, indent=2) + '\n')
        print(json.dumps(rows, indent=2))


if __name__ == '__main__':
    main()
