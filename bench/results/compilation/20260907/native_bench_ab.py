"""Compare the existing seven native benchmark programs, without changing their work."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import time

ROOT = next(p for p in Path(__file__).resolve().parents if (p / 'swc.sln').is_file())
sys.path.insert(0, str(ROOT / 'bench'))
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
import toolchains as tc
import winproc

parser = argparse.ArgumentParser()
parser.add_argument('--a', required=True)
parser.add_argument('--b', required=True)
parser.add_argument('--label', required=True)
parser.add_argument('--reps', type=int, default=7)
parser.add_argument('--max-cpu', type=int, default=15)
args = parser.parse_args()
env = os.environ.copy()
result_path = ROOT / '.tmp/speed' / (args.label + '.json')
out = ROOT / '.tmp/speed/native-bench' / args.label
out.mkdir(parents=True, exist_ok=True)
records = []
admissions = []
binaries = [('A', str(Path(args.a).resolve())), ('B', str(Path(args.b).resolve()))]
metadata = dict(vars(args), binaries={tag: dict(path=p, sha256=hashlib.sha256(Path(p).read_bytes()).hexdigest()) for tag, p in binaries})

def save():
    result_path.write_text(json.dumps(dict(metadata=metadata, samples=records, admissions=admissions), indent=2), encoding='utf-8')

def admit():
    while True:
        result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(ROOT / '.agents/skills/modify-swag-codebase/scripts/check-machine-load.ps1'), '-MaxCpuPercent', str(args.max_cpu)], capture_output=True, text=True)
        admissions.append(dict(time=time.strftime('%Y-%m-%d %H:%M:%S'), status=result.returncode, output=result.stdout))
        save()
        if result.returncode == 0:
            return
        if result.returncode != 2:
            raise RuntimeError(result.stdout + result.stderr)
        print('Waiting for benchmark headroom', flush=True)
        time.sleep(15)

def execute(command, pin=False):
    start = winproc._system_times()
    result = winproc.run(command, cwd=str(ROOT), env=env, pin=pin)
    end = winproc._system_times()
    if start and end and end[1] > start[1]:
        total = end[1] - start[1]
        busy = total - (end[0] - start[0])
        result['background_cpu_pct_estimate'] = max(0, 100 * (busy - result['cpu_ms']) / total)
    return result

for task in tc.TASKS:
    executables = {}
    checksums = {}
    for tag, binary in binaries:
        folder = out / (task + '_' + tag)
        folder.mkdir(exist_ok=True)
        command = [binary, 'build', '--build-cfg', 'release', '--num-cores', '6', '-n', task, '-od', str(folder), '-wd', str(folder)]
        for source in tc.swag_files(task, 'swagnat'):
            command.extend(['-f', source])
        admit()
        result = execute(command)
        result.update(tag=tag, task=task, build=True, command=command)
        records.append(result)
        save()
        if result['exit']:
            print(result['stdout'] + result['stderr'])
            raise SystemExit(result['exit'])
        executables[tag] = str(folder / (task + '.exe'))
    for rnd in range(args.reps + 1):
        admit()
        for tag, _ in binaries if rnd % 2 else binaries[::-1]:
            result = execute([executables[tag]], pin=True)
            result.update(tag=tag, task=task, build=False, round=rnd, warm=rnd == 0)
            records.append(result)
            match = re.search(r'CHECK=(-?\d+)\s+MS=([\d.]+)', result['stdout'] + result['stderr'])
            checksum = int(match[1]) if match else None
            result['kernel_ms'] = float(match[2]) if match else None
            if result['exit'] or not match or (checksums and checksum not in checksums.values()):
                print(task, tag, 'checksum mismatch', checksums, result)
                save()
                raise SystemExit(1)
            checksums[tag] = checksum
            save()
    pair = {tag: [r for r in records if r['task'] == task and not r['build'] and not r['warm'] and r['tag'] == tag] for tag, _ in binaries}
    ratio = statistics.median(b['kernel_ms'] / a['kernel_ms'] for a, b in zip(pair['A'], pair['B']))
    print(task, 'B/A kernel', round(ratio, 4), 'checksum', checksums['A'], flush=True)
