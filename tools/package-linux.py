#!/usr/bin/env python3
"""Package a built Linux GUI application for a chosen install prefix."""

import argparse
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import shutil
import tarfile
import tempfile


APPLICATIONS = {
    'swagcapture': ('Swag Capture', 'Screen capture and annotation workspace'),
    'swagscope': ('Swag Scope', 'Fast universal file viewer'),
}


def prefix_path(value: str) -> PurePosixPath:
    if not re.fullmatch(r'/[A-Za-z0-9/_+.-]+', value) or '..' in PurePosixPath(value).parts:
        raise argparse.ArgumentTypeError('prefix must be an absolute path without spaces or traversal')
    return PurePosixPath(value)


def package(app: str, build_dir: Path, output: Path, prefix: PurePosixPath, checkout: Path) -> None:
    build_root = build_dir.resolve()
    binary = build_dir / app
    if not binary.is_file() or not binary.stat().st_mode & 0o111:
        raise SystemExit(f'Expected an executable Linux ELF at {binary}')
    with binary.open('rb') as stream:
        header = stream.read(4)
    if header != b'\x7fELF':
        raise SystemExit(f'Expected an executable Linux ELF at {binary}')
    icon = checkout / 'bin' / 'apps' / 'modules' / app / 'datas' / 'appicon.png'
    if not icon.is_file():
        raise SystemExit(f'Missing application icon: {icon}')
    if output.exists() or output.is_symlink():
        raise SystemExit(f'Refusing to replace existing archive: {output}')

    root = PurePosixPath(*prefix.parts[1:])
    program_dir = root / 'libexec' / 'swag' / app
    program = prefix / 'libexec' / 'swag' / app / app
    desktop_path = root / 'share' / 'applications' / f'{app}.desktop'
    icon_path = root / 'share' / 'icons' / 'hicolor' / '512x512' / 'apps' / f'{app}.png'
    name, description = APPLICATIONS[app]
    desktop = (f'[Desktop Entry]\nType=Application\nName={name}\nComment={description}\n'
               f'Exec={program} %f\nTryExec={program}\nIcon={app}\nTerminal=false\n'
               'Categories=Graphics;Utility;\n')

    with tempfile.TemporaryDirectory(prefix='swag-linux-package-') as temporary:
        stage = Path(temporary)
        destination = stage / str(program_dir)
        destination.mkdir(parents=True)
        shutil.copy2(binary, destination / app)
        for dependency in sorted(build_dir.iterdir()):
            if dependency.name.startswith('.') or '.so' not in dependency.name:
                continue
            if dependency.is_symlink():
                link_target = dependency.readlink()
                try:
                    target = dependency.resolve(strict=True)
                except (OSError, RuntimeError):
                    raise SystemExit(f'Dependency symlink has no usable target: {dependency}') from None
                if (link_target.is_absolute() or len(link_target.parts) != 1 or
                        link_target.name.startswith('.') or '.so' not in link_target.name or not target.is_file() or
                        target.parent != build_root or '.so' not in target.name):
                    raise SystemExit(f'Dependency symlink target is not a packaged sibling library: {dependency}')
                (destination / dependency.name).symlink_to(link_target)
            elif dependency.is_file():
                shutil.copy2(dependency, destination / dependency.name)

        desktop_file = stage / str(desktop_path)
        desktop_file.parent.mkdir(parents=True)
        desktop_file.write_text(desktop)
        package_icon = stage / str(icon_path)
        package_icon.parent.mkdir(parents=True)
        shutil.copy2(icon, package_icon)
        output.parent.mkdir(parents=True, exist_ok=True)
        temporary_archive = None
        try:
            for _ in range(100):
                candidate = output.parent / f'.{output.name}.{secrets.token_hex(8)}.tmp'
                try:
                    descriptor = os.open(candidate, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o666)
                except FileExistsError:
                    continue
                temporary_archive = candidate
                os.close(descriptor)
                break
            else:
                raise FileExistsError(f'Could not create a temporary archive beside {output}')
            with tarfile.open(temporary_archive, 'w:gz') as archive:
                for item in sorted(stage.rglob('*')):
                    archive.add(item, arcname=item.relative_to(stage), recursive=False)
            # Link into place atomically without replacing an archive created concurrently.
            os.link(temporary_archive, output)
        finally:
            if temporary_archive is not None:
                temporary_archive.unlink(missing_ok=True)

    print(f'Packaged {app}: {output}')
    print(f'Install prefix: {prefix}; launcher: {desktop_path}')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', choices=APPLICATIONS)
    parser.add_argument('--configuration', choices=('release', 'devmode'), default='release')
    parser.add_argument('--build-dir', type=Path, help='directory containing the built executable and published dependencies')
    parser.add_argument('--output', type=Path, required=True, help='new .tar.gz archive to write')
    parser.add_argument('--prefix', type=prefix_path, default=PurePosixPath('/usr/local'))
    args = parser.parse_args()
    checkout = Path(__file__).resolve().parent.parent
    build_dir = args.build_dir or (checkout / 'bin' / 'apps' / '.output' / args.app / 'executable' /
                                   args.configuration / 'x86_64')
    package(args.app, build_dir.resolve(), args.output.absolute(), args.prefix, checkout)


if __name__ == '__main__':
    main()
