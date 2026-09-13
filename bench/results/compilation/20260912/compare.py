"""Compile the benchmark sources only; never execute a generated program."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time

ROOT = next(p for p in Path(__file__).resolve().parents if (p / 'swc.sln').is_file())
sys.path.insert(0, str(ROOT / 'bench'))
import toolchains as tc
import winproc

ap = argparse.ArgumentParser()
ap.add_argument('--binaries', nargs='+', default=['baseline', 'candidate'])
ap.add_argument('--tasks', nargs='+', default=tc.TASKS + ['core'])
ap.add_argument('--reps', type=int, default=3)
ap.add_argument('--label', required=True)
ap.add_argument('--cfg', default='release')
ap.add_argument('--cores', type=int, default=0, help='0 uses the compiler default; unrestricted measurements were explicitly requested')
ap.add_argument('--max-cpu', type=int, default=20)
args = ap.parse_args()
result_file = ROOT / '.tmp/compile-perf' / (args.label + '.json')
data = {'arguments': vars(args), 'logical_processors': os.cpu_count(), 'samples': [], 'admissions': [], 'binaries': {}}
for tag in args.binaries:
    binary = ROOT / 'bin' / ('swc.' + tag + '.exe')
    data['binaries'][tag] = {'path': str(binary), 'sha256': hashlib.sha256(binary.read_bytes()).hexdigest()}

def save():
    result_file.write_text(json.dumps(data, indent=2), encoding='utf-8')

def admit():
    while True:
        r = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(ROOT / '.agents/skills/modify-swag-codebase/scripts/check-machine-load.ps1'), '-MaxCpuPercent', str(args.max_cpu)], capture_output=True, text=True)
        data['admissions'].append({'time': time.strftime('%Y-%m-%d %H:%M:%S'), 'exit': r.returncode, 'output': r.stdout})
        save()
        if r.returncode == 0:
            return
        if r.returncode != 2:
            raise RuntimeError(r.stdout + r.stderr)
        print('Waiting for machine headroom', flush=True)
        time.sleep(10)

for rnd in range(args.reps):
    for task in args.tasks:
        for tag in args.binaries if rnd % 2 == 0 else args.binaries[::-1]:
            binary = data['binaries'][tag]['path']
            folder = ROOT / '.tmp/compile-perf/output' / tag / task
            folder.mkdir(parents=True, exist_ok=True)
            cmd = [binary, 'build', '--build-cfg', args.cfg, '--rebuild']
            if args.cores:
                cmd += ['--num-cores', str(args.cores)]
            if task == 'core':
                cmd += ['--workspace', str(ROOT / 'bin/std'), '--workspace-module', 'core']
            else:
                cmd += ['-n', task, '-od', str(folder), '-wd', str(folder)]
                for src in tc.swag_files(task, 'swagnat'):
                    cmd += ['-f', src]
            admit()
            start = winproc._system_times()
            result = winproc.run(cmd, cwd=str(ROOT), env=dict(os.environ))
            end = winproc._system_times()
            if start and end and end[1] > start[1]:
                total = end[1] - start[1]
                result['background_cpu_pct'] = max(0, 100 * (total - (end[0] - start[0]) - result['cpu_ms']) / total)
            result.update(tag=tag, task=task, round=rnd, command=cmd)
            data['samples'].append(result)
            save()
            print(f"{rnd + 1} {tag:10} {task:10} wall={result['wall_ms']:.1f} cpu={result['cpu_ms']:.1f} ws={result['peak_working_set_bytes']/1048576:.1f} MiB", flush=True)
            if result['exit']:
                raise RuntimeError(result['stdout'] + result['stderr'])

for task in args.tasks:
    for tag in args.binaries:
        samples = [s for s in data['samples'] if s['task'] == task and s['tag'] == tag]
        print(task, tag, {k: round(statistics.median(s[k] for s in samples), 2) for k in ['wall_ms', 'cpu_ms', 'peak_working_set_bytes']}, flush=True)
