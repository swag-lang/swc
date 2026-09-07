"""Run the existing benchmark driver with shared-machine admission for every Swag invocation."""
import os
import json
import importlib
from pathlib import Path
import subprocess
import sys
import time

ROOT = next(p for p in Path(__file__).resolve().parents if (p / 'swc.sln').is_file())
sys.path.insert(0, str(ROOT / 'bench'))
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
import driver
import winproc

compile_mode = len(sys.argv) > 1 and sys.argv[1] == '--compile'
if compile_mode:
    sys.argv.pop(1)
trace_path = ROOT / '.tmp/speed/legacy-ab.json'
trace = []
# The existing workload preparation deletes only these private output trees.
if not Path(driver.tc.OUT).resolve().is_relative_to(ROOT):
    raise RuntimeError('Benchmark outputs are outside this worktree')

if compile_mode:
    original_workloads = driver.tc.make_compiler_workloads
    hello_toolchains = driver.tc.discover()
    hello_env = driver.tc.build_env(hello_toolchains)
    def workloads_with_hello(swc, cores=0):
        workloads = original_workloads(swc, cores)
        recipe = driver.tc.make_hello_builds(hello_toolchains, hello_env, swc)['swag-release']()
        def prepare_hello(env):
            for path in recipe['clean']:
                if not Path(path).resolve().is_relative_to(ROOT):
                    raise RuntimeError('Hello output is outside this worktree')
            driver.prepare(recipe)
        workloads['hello_build'] = dict(cmd=recipe['cmd'], cwd=recipe['cwd'], prepare=prepare_hello, what='hello, source to linked executable')
        return workloads
    driver.tc.make_compiler_workloads = workloads_with_hello
    driver.tc.COMPILER_WORKLOADS = [*driver.tc.COMPILER_WORKLOADS, 'hello_build']

original_subprocess_run = subprocess.run
original_winproc_run = winproc.run

def admitted_command(command):
    if not isinstance(command, (list, tuple)) or not command:
        return command
    name = Path(command[0]).name.lower()
    if not name.startswith('swc') or not name.endswith('.exe'):
        return command
    command = list(command)
    if '--num-cores' not in command:
        command.extend(['--num-cores', '6'])
    while True:
        result = original_subprocess_run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(ROOT / '.agents/skills/modify-swag-codebase/scripts/check-machine-load.ps1')], capture_output=True, text=True)
        if result.returncode == 0:
            break
        if result.returncode != 2:
            raise RuntimeError(result.stdout + result.stderr)
        print('Waiting for compiler headroom', flush=True)
        time.sleep(15)
    return command

def guarded_subprocess_run(command, *args, **kwargs):
    # Warm each A/B compiler's actual core artifacts, even when switching to an
    # older frozen executable whose timestamp predates the other compiler's output.
    if compile_mode and isinstance(command, (list, tuple)) and command and Path(command[0]).name.lower().startswith('swc') and 'build' in command and '--rebuild' not in command:
        command = [*command, '--rebuild']
    return original_subprocess_run(admitted_command(command), *args, **kwargs)

def guarded_winproc_run(command, *args, **kwargs):
    command = admitted_command(command)
    result = original_winproc_run(command, *args, **kwargs)
    if compile_mode:
        trace.append(dict(command=command, **result))
        trace_path.write_text(json.dumps(trace, indent=2), encoding='utf-8')
    return result

subprocess.run = guarded_subprocess_run
winproc.run = guarded_winproc_run
os.chdir(ROOT / 'bench')
raise SystemExit(importlib.import_module('compile').main() if compile_mode else driver.main())
