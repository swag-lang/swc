"""Run focused compiler suites on Linux with isolated resources, outputs and caches."""

import argparse
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('suite', choices=('cpp', 'lexer', 'parser', 'native'))
    parser.add_argument('--compiler', required=True, type=Path, help='built Linux compiler executable')
    parser.add_argument('--dev-full', action='store_true', help='include filesystem tests and extra IR/native validation in the C++ suite')
    parser.add_argument('--execution', choices=('both', 'jit', 'native'), help='native suite execution mode (default: both)')
    parser.add_argument('--file-filter', help='select standalone source files whose path contains this text')
    parser.add_argument('--timeout', type=int, default=180, help='maximum seconds per compiler invocation')
    args = parser.parse_args()
    if sys.platform != 'linux' or platform.machine() != 'x86_64':
        parser.error('the test host must be Linux x86-64')
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    if args.dev_full and args.suite != 'cpp':
        parser.error('--dev-full only applies to the C++ suite')
    if args.execution and args.suite != 'native':
        parser.error('--execution only applies to the native suite')
    if args.file_filter is not None and (args.suite == 'cpp' or not args.file_filter):
        parser.error('--file-filter requires a nonempty source-suite filter')
    import resource
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    compiler = args.compiler.resolve()
    if not compiler.is_file() or not os.access(compiler, os.X_OK):
        parser.error('--compiler must name an executable file')

    root = Path(__file__).resolve().parent.parent
    admission = [sys.executable, str(root / '.agents/skills/modify-swag-codebase/scripts/check-machine-load.py')]
    # Stage the executable together with this checkout's runtime. Neither its
    # original installation nor another checkout supplies resources or caches.
    with tempfile.TemporaryDirectory(prefix='swc-linux-tests-') as directory:
        scratch = Path(directory).resolve()
        staged_compiler = scratch / compiler.name
        shutil.copy2(compiler, staged_compiler)
        shutil.copytree(root / 'bin/runtime', scratch / 'runtime')
        if args.suite == 'cpp' and args.dev_full:
            # Native fixture subprocesses resolve installed test inputs beside the executable.
            shutil.copytree(root / 'bin/unittests', scratch / 'unittests')
        temporary = scratch / 'temp'
        temporary.mkdir()
        environment = os.environ.copy()
        environment['TMPDIR'] = str(temporary)
        environment['SWAG_PATH'] = str(scratch)
        environment.setdefault('SWAG_RUNTIME_THREADS', '3')

        if args.suite == 'cpp':
            commands = [['unittest', '--num-cores', '3', '--verbose-unittest']]
            if args.dev_full:
                commands[0].append('--dev-full')
        else:
            stages = {'lexer': ['--lex-only'], 'parser': ['--syntax-only'], 'native': []}
            directories = [args.suite] if args.suite == 'native' else [args.suite, 'errors/' + args.suite]
            commands = []
            for directory in directories:
                commands.append([
                    'test', '--directory', str(root / 'bin/unittests' / directory),
                    '--module-namespace', args.suite.capitalize(), '--artifact-kind', 'executable',
                    '--num-cores', '3', '--rebuild', *stages[args.suite], '--out-dir', str(scratch / 'out' / directory),
                    '--work-dir', str(scratch / 'work' / directory),
                ])

            for command in commands:
                if args.file_filter:
                    command += ['--file-filter', args.file_filter]
                if args.execution == 'jit':
                    command.append('--no-test-native')
                elif args.execution == 'native':
                    command.append('--no-test-jit')

        for command in commands:
            subprocess.run(admission, check=True)
            subprocess.run([str(staged_compiler), *command], cwd=scratch, env=environment, check=True, timeout=args.timeout)
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode if error.returncode >= 0 else 128 - error.returncode)
    except (OSError, subprocess.TimeoutExpired) as error:
        print(f'cannot complete Linux compiler tests: {error}', file=sys.stderr)
        raise SystemExit(1)
