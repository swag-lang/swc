"""Restore the pinned FileSamples fixtures or verify an existing local copy."""

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from hashlib import sha256
import json
from pathlib import Path, PurePosixPath
import subprocess
from threading import Lock
import time
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parent
REQUEST_LOCK = Lock()
next_request = 0.0


def local_path(sample):
    relative = sample['path']
    path = PurePosixPath(relative)
    url = urlsplit(sample['url'])
    if (len(path.parts) != 4 or path.parts[0] != 'samples' or '..' in path.parts
            or path.as_posix() != relative or '\\' in relative or ':' in relative
            or url.netloc != 'filesamples.com' or url.scheme != 'https'
            or unquote(url.path) != '/' + relative):
        raise ValueError(f'Invalid catalogue entry {relative!r}')
    return ROOT.joinpath(*path.parts)


def matches(path, sample):
    if not path.is_file() or path.stat().st_size != sample['bytes']:
        return False

    digest = sha256()
    with path.open('rb') as data:
        for block in iter(lambda: data.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest() == sample['sha256']


def fetch(url, destination):
    global next_request
    for attempt in range(4):
        with REQUEST_LOCK:
            time.sleep(max(0, next_request - time.monotonic()))
            next_request = time.monotonic() + 0.75
        response = subprocess.run(
            ['curl', '--fail', '--silent', '--show-error', '--location', '--proto', '=https',
             '--connect-timeout', '15', '--max-time', '240', '--output', str(destination), url],
            capture_output=True,
        )
        if response.returncode == 0:
            return
        if attempt < 3:
            time.sleep(2 ** attempt)
    raise RuntimeError(response.stderr.decode(errors='replace').strip())


def restore(sample, verify_only):
    destination = local_path(sample)
    if matches(destination, sample):
        return
    if verify_only:
        raise ValueError('Missing file or digest mismatch')

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + '.part')
    try:
        fetch(sample['url'], temporary)
        if not matches(temporary, sample):
            raise ValueError('Download differs from the pinned size or digest')
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', action='store_true', help='Check local files without downloading')
    args = parser.parse_args()
    catalogue = json.loads((ROOT / 'catalogue.json').read_text(encoding='utf-8'))
    samples = catalogue['samples']

    failures = 0
    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = {pool.submit(restore, sample, args.verify): sample['path'] for sample in samples}
        for completed in as_completed(futures):
            try:
                completed.result()
            except (OSError, RuntimeError, ValueError) as error:
                print(f'{futures[completed]}: {error}', flush=True)
                failures += 1

    print(f'{len(samples) - failures}/{len(samples)} fixtures match the catalogue.')
    return bool(failures)


if __name__ == '__main__':
    raise SystemExit(main())
