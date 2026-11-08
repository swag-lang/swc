#!/usr/bin/env bash
# Install or remove this checkout's compiler environment in one interactive shell profile.
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: tools/setup.sh [--status | --install | --remove] [--compiler ABSOLUTE_PATH] [--profile ABSOLUTE_PATH]

The default is --status. --install configures Bash (~/.bashrc) or Zsh (~/.zshrc).
Bare .swgs execution is unsupported by these shells; use the printed compiler command.
USAGE
}

action=status
compiler=
profile=
while (($#)); do
    case "$1" in
        --status|--install|--remove) action=${1#--}; shift ;;
        --compiler|--profile)
            (($# >= 2)) || { usage >&2; exit 2; }
            if [[ $1 == --compiler ]]; then compiler=$2; else profile=$2; fi
            shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

checkout=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
library=$checkout/bin
shell_name=${SHELL:-}
shell_name=${shell_name##*/}
if [[ -z $profile ]]; then
    case "$shell_name" in
        bash) profile=$HOME/.bashrc ;;
        zsh) profile=$HOME/.zshrc ;;
        *) printf 'Unsupported shell: %s. Use SWAG_PATH=%q /absolute/path/to/swc file.swgs\n' "$shell_name" "$library" >&2; exit 2 ;;
    esac
fi

if [[ $action == install ]]; then
    if [[ -z $compiler ]]; then
        for candidate in "$checkout/bin/swc" "$checkout/bin/swc.dm" \
                         "${SWC_BUILD_DIR:-$checkout/../build}/release/swc" \
                         "${SWC_BUILD_DIR:-$checkout/../build}/devmode/swc.dm"; do
            if [[ -x $candidate ]]; then compiler=$candidate; break; fi
        done
    fi
    if [[ $compiler != /* || ! -x $compiler ]]; then
        printf 'Compiler missing. Build it first or pass --compiler /absolute/path/to/swc[.dm].\n' >&2
        exit 2
    fi
    compiler=$(realpath -- "$compiler")
fi

python3 - "$profile" "$library" "$compiler" "$action" <<'PY'
import os
from pathlib import Path
import shlex
import stat
import sys
import tempfile

profile, library, compiler, action = sys.argv[1:]
path = Path(profile)
if not path.is_absolute():
    raise SystemExit('Profile path must be absolute')
if path.is_symlink():
    raise SystemExit(f'Refusing to replace symlinked profile {path}')
start = '# >>> swag compiler setup >>>'
end = '# <<< swag compiler setup <<<'
old = path.read_text() if path.exists() else ''
begin = old.find(start)
finish = old.find(end)
if (begin < 0) != (finish < 0) or old.count(start) > 1 or old.count(end) > 1 or (begin >= 0 and finish < begin):
    raise SystemExit(f'Refusing to edit malformed setup block in {path}')
installed = begin >= 0
if action == 'status':
    print(f'{path}: {"configured" if installed else "not configured"}')
elif action == 'remove' and not installed:
    print(f'{path}: no setup block to remove')
else:
    if installed:
        after = finish + len(end)
        if old[after:after + 1] == '\n':
            after += 1
        old = old[:begin] + old[after:]
    if action == 'install':
        variable = 'SWC_DEVMODE_COMPILER' if Path(compiler).name == 'swc.dm' else 'SWC_COMPILER'
        block = '\n'.join((start,
                           f'export SWAG_PATH={shlex.quote(library)}',
                           f'export {variable}={shlex.quote(compiler)}',
                           f'export PATH={shlex.quote(str(Path(compiler).parent))}:"$PATH"',
                           end, ''))
        if old and not old.endswith('\n'):
            old += '\n'
        old += block
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    descriptor, temporary = tempfile.mkstemp(prefix='.swag-setup-', dir=path.parent)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, 'w') as stream:
            stream.write(old)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(f'{path}: {"configured" if action == "install" else "setup block removed"}')
PY

if [[ $action == install ]]; then
    printf 'Open a new %s shell, then run: %s file.swgs\n' "$shell_name" "$(basename -- "$compiler")"
elif [[ $action == status ]]; then
    printf 'Bare .swgs execution is unsupported. Run: swc file.swgs (or swc.dm file.swgs).\n'
fi
