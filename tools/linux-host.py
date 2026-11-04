"""Build and test the implemented Linux compiler host primitives, not the full compiler."""

import argparse
from pathlib import Path
import platform
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cxx', default='c++', help='C++23 compiler (GCC 14 or later)')
    parser.add_argument('--configuration', choices=('devmode', 'release'), default='devmode')
    args = parser.parse_args()
    if sys.platform != 'linux' or platform.machine() != 'x86_64':
        parser.error('the host tests only support Linux x86-64')

    root = Path(__file__).resolve().parent.parent
    admission = [sys.executable, str(root / '.agents/skills/modify-swag-codebase/scripts/check-machine-load.py')]
    sources = [root / path for path in (
        'src/Backend/Encoder/X64DwarfFrame.cpp',
        'src/Backend/JIT/JITMemory.cpp',
        'src/Backend/JIT/JITMemoryManager.cpp',
        'src/Main/HostCpuGuard.cpp',
        'src/Main/FileSystem.IO.cpp',
        'src/Support/Core/ByteArray.cpp',
        'src/Support/Core/Utf8.cpp',
        'src/Support/Os/DirectoryLock.Linux.cpp',
        'src/Support/Os/Os.Linux.cpp',
        'src/Support/Os/Os.File.Linux.cpp',
        'src/Support/Os/Os.Exception.Linux.cpp',
        'src/Support/Os/Os.ExceptionReport.Linux.cpp',
        'src/Support/Report/HardwareException.Fields.cpp',
        'src/Support/Os/Os.Console.Linux.cpp',
        'src/Support/Os/Os.Module.Linux.cpp',
        'src/Support/Os/Os.Process.Linux.cpp',
        'src/Support/Os/Os.Thread.Linux.cpp',
        'src/Support/Os/Os.Stack.Linux.cpp',
        'src/Support/Os/Os.Unwind.Linux.cpp',
        'src/Support/Os/ProcessOutput.cpp',
        'src/Support/Os/Os.Memory.Linux.cpp',
        'src/Support/Os/ReadOnlyFileMapping.Linux.cpp',
        'src/Unittest/Support/LinuxHostMain.cpp',
        'src/Unittest/Support/LinuxHost.Files.cpp',
        'src/Unittest/Support/LinuxHost.Services.cpp',
        'src/Unittest/Support/LinuxHost.Process.cpp',
        'src/Unittest/Support/LinuxHost.Stack.cpp',
        'src/Unittest/Support/LinuxHost.Unwind.cpp',
        'src/Unittest/Support/LinuxHost.Exceptions.cpp',
    )]
    # No artifacts or generated test inputs belong in the checkout.
    with tempfile.TemporaryDirectory(prefix='swc-linux-host-') as scratch:
        scratch = Path(scratch).resolve()
        binary = scratch / 'linux-host-tests'
        module_directory = scratch / 'module path'
        module_directory.mkdir()
        flags = ['-O0', '-g', '-DSWC_DEV_MODE=1'] if args.configuration == 'devmode' else ['-O2', '-DNDEBUG']
        cpu_reject = scratch / 'cpu-reject'
        subprocess.run(admission, check=True)
        subprocess.run([args.cxx, '-O2', '-march=x86-64-v3', '-I', str(root / 'src'),
                        str(root / 'src/Main/HostCpuGuard.cpp'),
                        str(root / 'src/Unittest/Support/LinuxHost.CpuReject.cpp'),
                        '-Wl,--wrap=__cpu_indicator_init', '-o', str(cpu_reject)], cwd=scratch, check=True)
        subprocess.run(admission, check=True)
        rejected = subprocess.run([str(cpu_reject)], cwd=scratch, capture_output=True, timeout=10)
        if rejected.returncode != 4 or b'swc needs a CPU with AVX2' not in rejected.stderr:
            raise RuntimeError(f'CPU rejection failed before initialization: {rejected.returncode}, {rejected.stderr!r}')
        print('PASS unsupported CPU rejected before C++ initialization', flush=True)
        subprocess.run(admission, check=True)
        subprocess.run([args.cxx, '-shared', '-fPIC', str(root / 'src/Unittest/Support/LinuxHost.Module.cpp'),
                        '-o', str(module_directory / 'libswc_host_test.so')], cwd=scratch, check=True)
        subprocess.run(admission, check=True)
        print(f'building Linux host tests ({args.configuration})', flush=True)
        subprocess.run([args.cxx, '-std=c++23', '-pthread', '-Wall', '-Wextra', '-Werror',
                        *flags, '-I', str(root / 'src'), *map(str, sources), '-rdynamic', '-ldl', '-o', str(binary)],
                       cwd=scratch, check=True)
        subprocess.run(admission, check=True)
        subprocess.run([str(binary)], cwd=scratch, check=True, timeout=40)
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode)
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f'cannot complete Linux host tests: {error}', file=sys.stderr)
        raise SystemExit(1)
