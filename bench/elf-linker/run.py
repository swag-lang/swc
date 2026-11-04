"""Compare GNU cc linking with SWC's integrated ELF linker and full rebuilds.

All fixtures, compiler installations and build products stay outside the checkout.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import statistics
import subprocess
import tempfile
import time


def summary(samples, key):
    result = []
    for case in dict.fromkeys(sample[key] for sample in samples):
        medians = {implementation: statistics.median(sample['milliseconds'] for sample in samples
                   if sample[key] == case and sample['implementation'] == implementation)
                   for implementation in ('gnu', 'internal')}
        result.append({key: case, **medians, 'saved_ms': medians['gnu'] - medians['internal'],
                       'reduction_percent': 100 * (1 - medians['internal'] / medians['gnu']),
                       'speedup': medians['gnu'] / medians['internal']})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=Path, required=True, help='configuration directory with the integrated compiler objects')
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--baseline-compiler', type=Path, required=True, help='preserved compiler from before the ELF linker change')
    parser.add_argument('--rounds', type=int, default=7)
    parser.add_argument('--counts', nargs='+', type=int, default=[1, 100, 1000])
    parser.add_argument('--output', type=Path, required=True, help='JSON output outside the checkout')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.rounds < 1 or any(count < 1 for count in args.counts) or args.output.resolve().is_relative_to(root):
        parser.error('use positive counts/rounds and an output outside the checkout')
    build = args.build_dir.resolve()
    build_command = shlex.split((build / 'build-command.txt').read_text())
    objects = sorted(path for path in (build / 'src').rglob('*.o') if path != build / 'src/main.o')
    admission = ['python3', str(root / '.agents/skills/modify-swag-codebase/scripts/check-machine-load.py')]
    subprocess.run(admission, check=True)
    with tempfile.TemporaryDirectory(prefix='swc-elf-link-') as temporary:
        scratch = Path(temporary)
        binary = scratch / 'measure'
        subprocess.run([*build_command, str(Path(__file__).with_name('measure.cpp')), *map(str, objects),
                        '-pthread', '-rdynamic', '-ldl', '-o', str(binary)], check=True)
        subprocess.run(admission, check=True)
        link_samples = []
        for mode in ('executable', 'shared'):
            for count in args.counts:
                case = f'{mode}/{count}'
                result = subprocess.run([str(binary), str(scratch / 'link' / mode / str(count)), str(count), str(args.rounds), mode],
                                        text=True, capture_output=True, check=True)
                for line in result.stdout.splitlines():
                    kind, members, round_, implementation, milliseconds, size = line.split(',')
                    link_samples.append(dict(case=case, output=kind, members=int(members), round=int(round_),
                                             implementation=implementation, milliseconds=float(milliseconds), bytes=int(size)))
                print(f'Measured isolated link: {case}', flush=True)
        installations = {}
        for implementation, compiler in [('gnu', args.baseline_compiler), ('internal', args.compiler)]:
            installation = scratch / ('baseline' if implementation == 'gnu' else 'internal')
            installation.mkdir()
            shutil.copy2(compiler.resolve(), installation / 'swc.dm')
            for directory in ('runtime', 'std'):
                shutil.copytree(root / 'bin' / directory, installation / directory,
                                ignore=shutil.ignore_patterns('.output', '.tmp', '__pycache__'))
            standalone = installation / 'standalone'
            standalone.mkdir()
            shutil.copy2(Path(__file__).with_name('standalone.swg'), standalone / 'main.swg')
            modules = root / 'bin/unittests/workspace/modules'
            for case, names in [('static', ('artifact_name_provider', 'artifact_name_consumer')),
                                ('shared', ('artifact_transitive_leaf', 'artifact_transitive_middle', 'artifact_transitive_consumer'))]:
                for name in names:
                    shutil.copytree(modules / name, installation / case / 'modules' / name,
                                    ignore=shutil.ignore_patterns('.output', '.tmp'))
            installations[implementation] = installation
        compile_samples = []
        subprocess.run(admission, check=True)
        for case in ('standalone', 'static', 'shared'):
            print(f'Measuring complete rebuild: {case}', flush=True)
            options_by_implementation = {}
            for round_ in range(args.rounds + 1):
                order = ('gnu', 'internal') if round_ % 2 == 0 else ('internal', 'gnu')
                for implementation in order:
                    installation = installations[implementation]
                    fixture = installation / case
                    environment = os.environ.copy()
                    environment.update(TMPDIR=str(installation), XDG_CACHE_HOME=str(installation / 'cache'),
                                       SWAG_PATH=str(installation), SWAG_RUNTIME_THREADS='3')
                    options = ['--num-cores', '3', '--build-cfg', 'devmode', '--no-log-color']
                    if case == 'standalone':
                        options += ['--file', str(fixture / 'main.swg'), '--artifact-name', 'standalone',
                                    '--artifact-kind', 'executable', '--out-dir', str(fixture / 'output'), '--work-dir', str(fixture / 'work')]
                    else:
                        module = 'artifact_name_consumer' if case == 'static' else 'artifact_transitive_consumer'
                        options += ['--workspace', str(fixture), '--workspace-module', module]
                    options_by_implementation[implementation] = (options, environment)
                    start = time.perf_counter()
                    result = subprocess.run([str(installation / 'swc.dm'), 'build', *options, '--rebuild'],
                                            cwd=fixture, env=environment, capture_output=True, text=True, timeout=180)
                    elapsed = (time.perf_counter() - start) * 1000
                    if result.returncode:
                        raise RuntimeError(f'{case} {implementation}: {result.stdout}\n{result.stderr}')
                    if round_:
                        compile_samples.append(dict(case=case, round=round_, implementation=implementation, milliseconds=elapsed))
            for implementation in ('gnu', 'internal'):
                installation = installations[implementation]
                options, environment = options_by_implementation[implementation]
                result = subprocess.run([str(installation / 'swc.dm'), 'run', *options], cwd=installation / case,
                                        env=environment, capture_output=True, text=True, timeout=180, check=True)
                marker = {'standalone': 'internal-link-benchmark-ok', 'static': 'artifact provider dropped',
                          'shared': 'transitive shared artifact passed'}[case]
                if marker not in result.stdout:
                    raise RuntimeError(f'{case} {implementation}: expected program output is missing\n{result.stdout}')
        result = dict(recorded_at_utc=datetime.now(timezone.utc).isoformat(), compiler_configuration='devmode' if '-DSWC_DEV_MODE=1' in build_command else 'release', program_configuration='devmode', rounds=args.rounds,
                      platform=platform.platform(), cpu=next(line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')),
                      cpu_quota=Path('/sys/fs/cgroup/cpu.max').read_text().strip(), compiler_flags=build_command,
                      toolchain=subprocess.check_output(['cc', '--version'], text=True).splitlines()[0],
                      baseline_sha256=hashlib.file_digest(args.baseline_compiler.open('rb'), 'sha256').hexdigest(),
                      internal_sha256=hashlib.file_digest(args.compiler.open('rb'), 'sha256').hexdigest(),
                      gnu_linker=subprocess.check_output(['ld', '--version'], text=True).splitlines()[0],
                      link_scope='in-memory objects through atomic image publication, including old materialization, response file, process, image read and cleanup; object generation excluded',
                      compile_scope='complete forced rebuild from sources, including parsing, code generation, dependency archives and image publication; execution validated outside timing',
                      link_summary=summary(link_samples, 'case'), compile_summary=summary(compile_samples, 'case'),
                      link_samples=link_samples, compile_samples=compile_samples)
        args.output.resolve().parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps({'link': result['link_summary'], 'compile': result['compile_summary']}, indent=2))


if __name__ == '__main__':
    main()
