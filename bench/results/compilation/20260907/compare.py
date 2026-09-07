"""Order-alternated, module-only edit-build measurements on an isolated source mirror."""
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
import winproc
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

parser = argparse.ArgumentParser()
parser.add_argument('--a', required=True)
parser.add_argument('--b', required=True)
parser.add_argument('--label', required=True)
parser.add_argument('--modules', default='gui,pixel,ogl,core')
parser.add_argument('--cfg', default='devmode')
parser.add_argument('--reps', type=int, default=5)
parser.add_argument('--max-cpu', type=int, default=15)
parser.add_argument('--warm-module', default='gui')
parser.add_argument('--rebuild-warm', action='store_true')
parser.add_argument('--pin', action='store_true', help='diagnostic control: use the benchmark performance-core mask')
parser.add_argument('--fixed-dependencies', action='store_true', help='GUI-only control: warm once with A and preserve all dependency artifacts')
args = parser.parse_args()
if args.fixed_dependencies and (args.modules != 'gui' or args.warm_module != 'gui'):
    parser.error('--fixed-dependencies requires --modules gui --warm-module gui')
workspace = ROOT / '.tmp/speed/profile/std'
result_path = ROOT / '.tmp/speed' / (args.label + '.json')
records = []
admissions = []
binaries = [('A', str(Path(args.a).resolve())), ('B', str(Path(args.b).resolve()))]
metadata = dict(vars(args), affinity_mask=hex(winproc.PIN_MASK) if args.pin else None, binaries={tag: dict(path=path, sha256=hashlib.sha256(Path(path).read_bytes()).hexdigest()) for tag, path in binaries})

def save():
    result_path.write_text(json.dumps(dict(metadata=metadata, samples=records, admissions=admissions), indent=2), encoding='utf-8')

def admit():
    while True:
        check = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(ROOT / '.agents/skills/modify-swag-codebase/scripts/check-machine-load.ps1'), '-MaxCpuPercent', str(args.max_cpu)], capture_output=True, text=True)
        admissions.append(dict(time=time.strftime('%Y-%m-%d %H:%M:%S'), status=check.returncode, output=check.stdout))
        save()
        if check.returncode == 0:
            return
        if 'wait' not in check.stdout:
            raise RuntimeError(check.stdout + check.stderr)
        print('Waiting for measurement headroom', flush=True)
        time.sleep(15)

def measure(tag, binary, module, round_number, warm=False):
    command = [binary, 'build', '--workspace', str(workspace), '--workspace-module', module, '-bc', args.cfg, '--num-cores', '6']
    if warm and args.rebuild_warm:
        command.append('--rebuild')
    admit()
    source = workspace / 'modules' / module / 'module.swg'
    stamp = source.stat()
    if not warm:
        os.utime(source, None)
    try:
        system_start = winproc._system_times()
        sample = winproc.run(command, cwd=str(ROOT), env=os.environ.copy(), pin=args.pin)
        system_end = winproc._system_times()
    finally:
        if not warm:
            os.utime(source, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
    sample.update(tag=tag, module=module, round=round_number, warm=warm, command=command)
    if system_start and system_end:
        total_cpu = system_end[1] - system_start[1]
        busy_cpu = total_cpu - (system_end[0] - system_start[0])
        if total_cpu > 0:
            sample['system_busy_pct_during'] = 100 * busy_cpu / total_cpu
            # Swag's native module writer runs in-process. For commands with child
            # helpers, this subtraction would also count their CPU as background.
            sample['background_cpu_pct_estimate'] = max(0, 100 * (busy_cpu - sample['cpu_ms']) / total_cpu)
    if warm:
        sample['api_foreign_lines'] = {
            name: sorted(line.strip() for path in (workspace / '.output' / name / 'shared-library' / args.cfg / 'x86_64').rglob('*.swg') for line in path.read_text(encoding='utf-8-sig').splitlines() if '#[Foreign(' in line)
            for name in ('core', 'ogl', 'pixel', 'gui')
        }
    records.append(sample)
    save()
    print('%s r%d %-5s %s wall=%.1f ms cpu=%.1f ms ws=%.1f MiB' % ('warm' if warm else 'test', round_number, module, tag, sample['wall_ms'], sample['cpu_ms'], sample['peak_working_set_bytes'] / 1048576), flush=True)
    if sample['exit']:
        print(sample['stdout'] + sample['stderr'], flush=True)
        raise SystemExit(sample['exit'])
    if not warm:
        rebuilt = [line.split('module      ', 1)[1].split('â€¢', 1)[0].strip() for line in sample['stdout'].splitlines() if 'module      ' in line and 'up-to-date' not in line]
        if rebuilt != [module]:
            raise RuntimeError('Expected only %s to rebuild, got %s' % (module, rebuilt))

def dependency_hashes():
    roots = [workspace / '.dep']
    roots.extend(p for p in (workspace / '.output').iterdir() if p.is_dir() and p.name != 'gui')
    result = {str(p.relative_to(workspace)): hashlib.sha256(p.read_bytes()).hexdigest()
              for root in roots for p in root.rglob('*') if p.is_file()}
    if not result:
        raise RuntimeError('No dependency artifacts found')
    return result

if args.fixed_dependencies:
    measure('A', binaries[0][1], 'gui', 0, warm=True)
    metadata['fixed_dependency_sha256'] = dependency_hashes()

for rnd in range(1, args.reps + 1):
    for tag, binary in binaries if rnd % 2 else binaries[::-1]:
        # Build the complete dependency graph with this binary outside the measured sample.
        if not args.fixed_dependencies:
            measure(tag, binary, args.warm_module, rnd, warm=True)
        # Consumers precede dependencies, so each touched module finds unchanged dependencies.
        for module in args.modules.split(','):
            measure(tag, binary, module, rnd)
            if args.fixed_dependencies and dependency_hashes() != metadata['fixed_dependency_sha256']:
                raise RuntimeError('Fixed dependency artifacts changed during the GUI comparison')

for module in args.modules.split(','):
    samples = {tag: [s for s in records if not s['warm'] and s['module'] == module and s['tag'] == tag] for tag, _ in binaries}
    ratios = {key: statistics.median(b[key] / a[key] for a, b in zip(samples['A'], samples['B'])) for key in ('wall_ms', 'cpu_ms', 'peak_working_set_bytes', 'peak_job_bytes')}
    print(module, 'B/A', json.dumps(ratios), flush=True)
