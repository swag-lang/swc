"""Open the configured Linux checkout in WSL, or build and test it from Windows."""

import argparse
import os
from pathlib import Path
import subprocess
import sys


# Values cross the shell boundary as positional arguments, never as shell source.
SESSION = r'''
set -e
source=${1:-$HOME/swag/swc}
build=${2:-$(dirname "$source")/build}
windows_source=$3
action=$4
configuration=$5
shift 5
cd "$source"
export SWAG_SOURCE="$source"
export SWAG_PATH="$source/bin"
export SWC_BUILD_DIR="$build"
export SWC_COMPILER="$build/release/swc"
export SWC_DEVMODE_COMPILER="$build/devmode/swc.dm"
export SWAG_RUNTIME_THREADS=3
export TMPDIR="$(dirname "$source")/tmp"
export PATH="$build/release:$build/devmode:$PATH"
mkdir -p "$TMPDIR"
compiler=$SWC_DEVMODE_COMPILER
if [ "$configuration" = release ]; then compiler=$SWC_COMPILER; fi
case "$action" in
    shell)
        printf 'Swag Linux: %s\nCompiler: %s\n' "$source" "$compiler"
        printf 'Use the same launchers and arguments as Windows: apps.bat build swagscope\n'
        printf 'Also: apps.bat test swagscope --test-file commandpresentation.swg\n'
        printf '      apps.bat run swagscope\n'
        source <(python3 -c "import sys; sys.stdout.write(sys.stdin.read().replace(chr(13), ''))" < tools/linux-shell.sh)
        exec bash -i
        ;;
    sync)
        windows_source=$(wslpath -u "$windows_source")
        git fetch "$windows_source" master
        exec git merge --ff-only FETCH_HEAD
        ;;
    build)
        python3 tools/linux-build.py --build-dir "$build" --configuration "$configuration" --cxx "${SWC_LINUX_CXX:-g++-14}" --jobs 3 "$@"
        mkdir -p "$build/$configuration/runtime"
        cp -a bin/runtime/. "$build/$configuration/runtime/"
        ;;
    test)
        suite=${1:-compiler}
        if [ "$#" -gt 0 ]; then shift; fi
        exec python3 tools/linux-tests.py "$suite" --compiler "$compiler" --dev-compiler "$SWC_DEVMODE_COMPILER" "$@"
        ;;
    exec) exec "$@" ;;
esac
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__, epilog='Defaults: Ubuntu-24.04, ~/swag/swc, ~/swag/build. Override with SWC_WSL_DISTRO, SWC_WSL_SOURCE and SWC_WSL_BUILD.')
    parser.add_argument('--release', action='store_true', help='select the Release compiler for build/test')
    parser.add_argument('action', nargs='?', default='shell', choices=('shell', 'sync', 'build', 'test', 'exec'))
    parser.add_argument('arguments', nargs=argparse.REMAINDER, help='suite and options for test, or command and arguments for exec')
    args = parser.parse_args()
    if sys.platform != 'win32':
        parser.error('this entry point opens WSL from Windows; use tools/tool.py inside Linux')
    if args.action == 'exec' and not args.arguments:
        parser.error('exec needs a command')
    if args.action in ('shell', 'sync') and args.arguments:
        parser.error(f'{args.action} does not accept extra arguments')
    root = Path(__file__).resolve().parent.parent
    if args.action in ('build', 'test'):
        check = root / '.agents/skills/modify-swag-codebase/scripts/check-machine-load.ps1'
        result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(check)])
        if result.returncode:
            return result.returncode
    command = ['wsl.exe', '--distribution', os.environ.get('SWC_WSL_DISTRO', 'Ubuntu-24.04'),
               '--exec', 'bash', '-c', SESSION, 'swag-linux',
               os.environ.get('SWC_WSL_SOURCE', ''), os.environ.get('SWC_WSL_BUILD', ''), str(root),
               args.action, 'release' if args.release else 'devmode', *args.arguments]
    return subprocess.call(command)


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except OSError as error:
        print(f'cannot open Swag Linux: {error}', file=sys.stderr)
        raise SystemExit(1)
