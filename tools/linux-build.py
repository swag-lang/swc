"""Build the Linux compiler from the shared Visual Studio source manifest with GNU Make."""

import argparse
import os
from pathlib import Path
import platform
import shlex
import subprocess
import sys
import xml.etree.ElementTree as ET


def make_path(path):
    return str(path).replace('\\', '\\\\').replace('$', '$$').replace('#', '\\#').replace(' ', '\\ ')


def recipe(arguments):
    return shlex.join(arguments).replace('$', '$$')


def write_changed(path, text):
    if not path.exists() or path.read_text() != text:
        path.write_text(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=Path, required=True, help='external build directory; retains incremental objects')
    parser.add_argument('--configuration', choices=('devmode', 'release'), default='devmode')
    parser.add_argument('--cxx', default='c++', help='GCC 14 or later with C++23 library support')
    parser.add_argument('--jobs', type=int, choices=range(1, 4), default=3)
    parser.add_argument('--keep-going', action='store_true', help='compile independent sources after an error; the build still fails')
    parser.add_argument('--skip-machine-load-admission', action='store_true',
                        help='skip local-machine admission in a managed cloud workspace')
    args = parser.parse_args()
    if sys.platform != 'linux' or platform.machine() != 'x86_64':
        parser.error('the compiler host must be Linux x86-64')
    root = Path(__file__).resolve().parent.parent
    build = args.build_dir.resolve() / args.configuration
    if build.is_relative_to(root):
        parser.error('--build-dir must be outside the checkout')
    build.mkdir(parents=True, exist_ok=True)

    # Keep the compiler's shared source inventory in one place. Only OS adapters differ;
    # Windows object/debug-format emitters remain available for cross-target compilation.
    manifest = ET.parse(root / 'swc.vcxproj')
    sources = set()
    for item in manifest.iter('{http://schemas.microsoft.com/developer/msbuild/2003}ClCompile'):
        path = item.get('Include')
        if not path:
            continue
        path = Path(path.replace('\\', '/'))
        if path.name == 'pch.cpp' or (path.parent == Path('src/Support/Os') and path.name.endswith('.Windows.cpp')):
            continue
        sources.add(root / path)
    sources.update((root / 'src/Support/Os').glob('*.Linux.cpp'))
    sources = sorted(sources)

    # Aggregate members omitted in C++ initializers are intentionally value-initialized.
    # GCC's -Wmissing-field-initializers is noisy for that convention in this codebase.
    flags = ['-std=c++23', '-O2', '-g1', '-DNDEBUG', '-pthread', '-march=x86-64-v3',
             '-Wall', '-Wextra', '-Wno-missing-field-initializers', '-fmax-errors=5', '-I', str(root / 'src'),
             '-I', str(root / 'src/Support/Memory/mimalloc/include')]
    if args.configuration == 'devmode':
        flags.append('-DSWC_DEV_MODE=1')
    command = [args.cxx, *flags]
    stamp = build / 'build-command.txt'
    write_changed(stamp, shlex.join(command) + '\n')
    pch = build / 'pch.h'
    write_changed(pch, f'#include "{root / "src/pch.h"}"\n')
    binary = build / ('swc.dm' if args.configuration == 'devmode' else 'swc')
    objects = [build / source.relative_to(root).with_suffix('.o') for source in sources]
    for obj in objects:
        obj.parent.mkdir(parents=True, exist_ok=True)
    rules = ['.DELETE_ON_ERROR:', '.PHONY: all', f'all: {make_path(binary)}', '']
    rules += [f'{make_path(pch)}.gch: {make_path(pch)} {make_path(root / "src/pch.h")} {make_path(stamp)}',
              '\t' + recipe([*command, '-x', 'c++-header', str(pch), '-o', str(pch) + '.gch']), '']
    for source, obj in zip(sources, objects):
        uses_pch = source.name not in ('HostCpuGuard.cpp', 'Mimalloc.cpp')
        dependencies = [source, stamp, *([str(pch) + '.gch'] if uses_pch else [])]
        # Mimalloc's own diagnostics are scoped to its amalgamated translation unit.
        vendor_flags = ['-Wno-cpp', '-Wno-stringop-overflow'] if source.name == 'Mimalloc.cpp' else []
        compile_command = [*command, *vendor_flags, *(['-include', str(pch)] if uses_pch else []),
                           '-MMD', '-MP', '-c', str(source), '-o', str(obj)]
        rules += [f'{make_path(obj)}: ' + ' '.join(map(make_path, dependencies)),
                  '\t@' + recipe(['echo', f'CXX {source.relative_to(root)}']),
                  '\t@' + recipe(compile_command), '']
    rules += [f'{make_path(binary)}: ' + ' '.join(map(make_path, objects)),
              '\t' + recipe([args.cxx, *map(str, objects), '-pthread', '-rdynamic', '-ldl', '-o', str(binary)]), '',
              '-include ' + ' '.join(make_path(obj.with_suffix('.d')) for obj in objects)]
    makefile = build / 'Makefile'
    write_changed(makefile, '\n'.join(rules) + '\n')
    if not args.skip_machine_load_admission:
        subprocess.run([sys.executable, str(root / '.agents/skills/modify-swag-codebase/scripts/check-machine-load.py')], check=True)
    # Ignore inherited make jobserver/options so this command honors its explicit worker cap.
    environment = os.environ.copy()
    environment.pop('MAKEFLAGS', None)
    environment.pop('MFLAGS', None)
    subprocess.run(['make', '-f', str(makefile), f'-j{args.jobs}', *(['-k'] if args.keep_going else []), 'all'], cwd=build, env=environment, check=True)
    print(binary)
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode)
    except (OSError, ET.ParseError) as error:
        print(f'cannot build Linux compiler: {error}', file=sys.stderr)
        raise SystemExit(1)
