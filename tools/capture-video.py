"""Exercise the editor with a synthetic two-hour SCC/MP4, without recording the desktop.

Keeps exported clips, native editor screenshots, timing measurements and a test log outside
the checkout. Requires Windows and an interactive desktop. No browser or audio device is needed.
"""

import argparse
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='new evidence directory outside the checkout')
    parser.add_argument('--regenerate', action='store_true', help='replace the maintained test fixture first')
    args = parser.parse_args()
    if sys.platform != 'win32':
        parser.error('the native editor journey currently requires Windows')
    repo = Path(__file__).resolve().parent.parent
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='capture-video-'))
    if output == repo or repo in output.parents:
        parser.error('--output must be outside the checkout')
    if args.output and output.exists():
        parser.error('--output must name a new directory')
    output.mkdir(parents=True, exist_ok=True)
    sandbox = output / 'sandbox'
    sandbox.mkdir()
    check = repo / '.agents/skills/modify-swag-codebase/scripts/check-machine-load.ps1'

    def run(stage, arguments):
        admitted = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                                   '-File', str(check)], cwd=repo)
        if admitted.returncode:
            return admitted.returncode
        command = [sys.executable, str(repo / 'tools/tool.py'), 'apps', 'test', 'swagcapture',
                   '-bc', 'release', *arguments]
        log_path = output / f'{stage}.log'
        with log_path.open('w', encoding='utf-8') as log:
            result = subprocess.run(command, cwd=repo, stdout=log, stderr=subprocess.STDOUT)
        print(log_path.read_text(encoding='utf-8'), flush=True)
        return result.returncode

    print(f'Evidence: {output}', flush=True)
    if args.regenerate:
        result = run('fixture', ['--test-file', 'longvideo.fixture.swg', '--test-tag',
                                'integration.capture.fixture', '--run-arg',
                                'capture.fixture.generate=true', '--run-timeout', '60'])
        if result:
            return result
    result = run('tools', ['--test-file', 'longvideo.workspace.swg', '--test-tag', 'stress',
                           '--run-arg', f'swag.sandbox={sandbox}', '--run-timeout', '90'])
    if not result and not (sandbox / 'twohours-tools.txt').is_file():
        raise RuntimeError('the native scenario did not produce its timing checkpoint')
    return result


if __name__ == '__main__':
    raise SystemExit(main())
