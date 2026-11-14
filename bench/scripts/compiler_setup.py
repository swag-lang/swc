"""Discover first, then optionally install hash-pinned Linux toolchains into a user cache."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

BENCH = Path(__file__).resolve().parents[1]
COMMANDS = {'gcc': ('g++', ['--version']), 'clang': ('clang++', ['--version']),
            'rustc': ('rustc', ['--version']), 'zig': ('zig', ['version']),
            'ldc2': ('ldc2', ['--version']), 'odin': ('odin', ['version']),
            'go': ('go', ['version']), 'swiftc': ('swiftc', ['--version']),
            'dotnet': ('dotnet', ['--version']), 'java': ('java', ['-version']),
            'javac': ('javac', ['-version']), 'node': ('node', ['--version']),
            'lua': ('lua', ['-v']), 'luajit': ('luajit', ['-v']),
            'php': ('php', ['-n', '-v']), 'ruby': ('ruby', ['-v']), 'py': ('python3', ['--version'])}


def cache_root():
    return Path(os.environ.get('BENCH_COMPILER_ROOT', Path.home() / '.cache' / 'swc-bench' / 'compilers'))


def configured():
    path = cache_root() / 'local.json'
    return json.loads(path.read_text()) if path.exists() else {}


def probe(key, path):
    if not path or not Path(path).is_file():
        return None
    try:
        r = subprocess.run([str(path), *COMMANDS[key][1]], capture_output=True, text=True,
                           errors='replace', timeout=20)
        text = (r.stdout + r.stderr).strip()
        if r.returncode or not text:
            return None
        # Some distributions ship a board game named go.
        if key == 'go' and not text.startswith('go version go'):
            return None
        return text.splitlines()[0]
    except (OSError, subprocess.TimeoutExpired):
        return None


def discover_linux():
    local = configured()
    found = {}
    for key, (name, _) in COMMANDS.items():
        override = os.environ.get('BENCH_' + key.upper())
        choices = [override] if override else [local.get(key), shutil.which(name)]
        found[key] = next((os.path.abspath(p) for p in choices if probe(key, p)), None)
    if not found['javac'] and found['java']:
        r = subprocess.run([found['java'], '-m', 'jdk.compiler/com.sun.tools.javac.Main', '-version'], capture_output=True)
        if r.returncode == 0:
            found['javac'] = found['java']
    found.update(vcvars=None, clang_cl=None, swift_rt=None, swift_sdk=None, vs=None)
    found['php_opcache'] = os.environ.get('BENCH_PHP_OPCACHE')
    return found


def install(key):
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        raise ValueError('automatic archives currently support Linux x86-64; configure installed tools on other hosts')
    manifest = json.loads((BENCH / 'compilers' / 'linux-x64.json').read_text())
    if key not in manifest:
        raise ValueError('no portable archive for %s; install the host package and rerun doctor' % key)
    entry = manifest[key]
    root = cache_root()
    root.mkdir(parents=True, exist_ok=True)
    dest = root / (key + '-' + entry['version'])
    # Never overwrite a partial installation or an existing user's toolchain.
    if dest.exists():
        raise ValueError('installation directory already exists: ' + str(dest))
    with tempfile.TemporaryDirectory(dir=root) as tmp:
        stage = Path(tmp)
        for i, artifact in enumerate(entry['archives']):
            archive = stage / ('download-' + str(i))
            with urllib.request.urlopen(artifact['url'], timeout=180) as response, archive.open('wb') as output:
                shutil.copyfileobj(response, output)
            algorithm = 'sha256' if 'sha256' in artifact else 'sha512'
            with archive.open('rb') as downloaded:
                actual_hash = hashlib.file_digest(downloaded, algorithm).hexdigest()
            if actual_hash != artifact[algorithm]:
                raise ValueError('download hash mismatch: ' + artifact['url'])
            unpacked = stage / ('unpacked-' + str(i))
            unpacked.mkdir()
            if zipfile.is_zipfile(archive):
                with zipfile.ZipFile(archive) as z:
                    for name in z.namelist():
                        if not (unpacked / name).resolve().is_relative_to(unpacked):
                            raise ValueError('unsafe archive member')
                    z.extractall(unpacked)
            else:
                with tarfile.open(archive) as t:
                    t.extractall(unpacked, filter='data')
            payload = unpacked / artifact.get('payload', '.')
            shutil.copytree(payload, stage / 'installation', dirs_exist_ok=True, symlinks=True)
        executable = stage / 'installation' / entry['executable']
        executable.chmod(executable.stat().st_mode | 0o111)
        if not probe(key, executable):
            raise ValueError('installed compiler version probe failed')
        (stage / 'installation').rename(dest)
    local = configured()
    local[key] = str(dest / entry['executable'])
    (root / 'local.json').write_text(json.dumps(local, indent=2) + '\n')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('action', choices=['doctor', 'install', 'register'])
    ap.add_argument('tools', nargs='*', help='tool ids; register uses KEY=ABSOLUTE_PATH')
    args = ap.parse_args()
    if args.action == 'register':
        local = configured()
        for item in args.tools:
            key, value = item.split('=', 1)
            if key not in COMMANDS or not probe(key, value):
                ap.error('invalid tool: ' + item)
            local[key] = os.path.abspath(value)
        cache_root().mkdir(parents=True, exist_ok=True)
        (cache_root() / 'local.json').write_text(json.dumps(local, indent=2) + '\n')
    if args.action == 'install':
        if not args.tools:
            ap.error('name at least one tool to install')
        import toolchains
        tools = toolchains.discover()
        for key in args.tools:
            if tools.get(key) and probe(key, tools[key]):
                print(key + ': existing installation reused: ' + tools[key])
            else:
                install(key)
    import toolchains
    tools = toolchains.discover()
    for key in COMMANDS:
        version = probe(key, tools.get(key))
        print('%-8s %s' % (key, (tools[key] + ' | ' + version) if version else 'MISSING'))
    print('Unavailable benchmark variants:', ', '.join(toolchains.missing(tools)) or 'none')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
