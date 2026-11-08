"""Run Linux compiler suites or the complete repository test campaign."""

import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import subprocess
import sys
import tempfile
import time


from tool import (SOURCE_SUITES, WORKSPACES, COMPILER_SUITES, Stage, cpp_stage,
                  module_names, module_stage, portability_check, source_stages, workspace_stages)


SUITES = ('all', 'compiler', *COMPILER_SUITES, *WORKSPACES, 'dynamic-library')


def plan(args, scratch, compiler, dev_compiler):
    """Use the same command builders as the Windows launchers, in an isolated tree."""
    stages = []
    suites = COMPILER_SUITES if args.suite in ('all', 'compiler') else (args.suite,)
    if args.suite == 'all':
        suites += WORKSPACES
    common = ['--build-cfg', args.build_cfg]
    # Every campaign starts from a new immutable snapshot. Reuse its dependencies
    # between stages instead of rebuilding the GUI for every example and application.
    campaign = args.suite in ('all', 'compiler') or (args.suite in WORKSPACES and not args.module)
    if not campaign:
        common.append('--rebuild')
    filters = [arg for value in args.test_file for arg in ('--test-file', value)]
    filters += [arg for value in args.test_tag for arg in ('--test-tag', value)]
    for suite in suites:
        if suite == 'cpp':
            stages.append(cpp_stage(dev_compiler or compiler, ['--verbose-unittest'],
                                    full=args.dev_full or args.suite in ('all', 'compiler')))
        elif suite in SOURCE_SUITES:
            options = common.copy()
            if args.file_filter:
                options += ['--file-filter', args.file_filter]
            if args.execution == 'jit':
                options.append('--no-test-native')
            elif args.execution == 'native':
                options.append('--no-test-jit')
            stages += source_stages(compiler, scratch, suite, options, output_root=scratch)
        elif suite in ('workspace', 'dynamic-library'):
            modules = [args.module] if args.module else None
            if suite == 'dynamic-library':
                modules = ['runtime_context_dynamic_consumer']
            stages += workspace_stages(compiler, scratch, [*common, *filters], modules=modules,
                                       script=suite == 'workspace' and not args.module,
                                       execution=args.execution if suite == 'dynamic-library' else None)
        else:
            modules = [args.module] if args.module else module_names(scratch / suite)
            for module in modules:
                options = [*common, *filters]
                mode = args.execution or ('both' if args.module and suite == 'std' else 'native' if suite in ('std', 'apps') else 'both')
                if mode == 'jit':
                    options += ['--test-jit', '--no-test-native']
                elif mode == 'native':
                    options += ['--no-test-jit']
                elif suite in ('std', 'apps'):
                    options += ['--test-jit']
                stages.append(module_stage(compiler, scratch, suite, 'test', module, options, child_compiler=True))
    return stages


def stop_process_tree(pid):
    """Freeze parents before finding children, then kill even detached descendants."""
    handles = []

    def freeze(current, parent=None):
        try:
            handle = os.pidfd_open(current)
        except ProcessLookupError:
            return
        if parent is not None:
            try:
                actual_parent = int(Path(f'/proc/{current}/stat').read_text().rpartition(')')[2].split()[1])
            except FileNotFoundError:
                actual_parent = None
            if actual_parent != parent:
                os.close(handle)
                return
        handles.append(handle)
        try:
            signal.pidfd_send_signal(handle, signal.SIGSTOP)
            # Wait until no thread can fork another child or reap and recycle a child PID.
            while True:
                status = Path(f'/proc/{current}/status').read_text()
                state = next(line.split()[1] for line in status.splitlines() if line.startswith('State:'))
                if state in ('T', 't', 'Z', 'X'):
                    break
                time.sleep(0.01)
            # task/*/children is optional in Linux kernels; stat always exposes the parent.
            for entry in Path('/proc').iterdir():
                if not entry.name.isdecimal():
                    continue
                try:
                    parent_pid = int((entry / 'stat').read_text().rpartition(')')[2].split()[1])
                except FileNotFoundError:
                    continue
                if parent_pid == current:
                    freeze(int(entry.name), current)
        except (ProcessLookupError, FileNotFoundError):
            pass

    try:
        freeze(pid)
    finally:
        # Never leave a frozen process behind, including when discovery fails.
        for handle in reversed(handles):
            try:
                signal.pidfd_send_signal(handle, signal.SIGKILL)
            except ProcessLookupError:
                pass
            finally:
                os.close(handle)


def release_artifact_cache(scratch):
    """Release inactive files owned by this campaign without deleting reusable artifacts."""
    for path in scratch.rglob('*'):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open('rb') as stream:
            os.fsync(stream.fileno())
            os.posix_fadvise(stream.fileno(), 0, 0, os.POSIX_FADV_DONTNEED)


def run_stage(stage, scratch, environment, timeout, admission):
    log = scratch / 'logs' / (stage.name + '.log')
    print(f'RUN {stage.name} (log: {log})', flush=True)
    released_cache = False
    while True:
        status = subprocess.run(admission, check=False).returncode
        if status == 0:
            break
        if status != 2:
            raise RuntimeError('cannot measure build and test admission')
        if not released_cache:
            # Staging large fixtures and prior stages can fill a memory-limited cgroup with
            # reclaimable file pages. No stage is running here; release only our own cache.
            release_artifact_cache(scratch)
            released_cache = True
        print('Waiting for build and test admission.', flush=True)
        time.sleep(5)
    start = time.monotonic()
    state = 'passed'
    with log.open('wb') as output:
        process = subprocess.Popen(stage.command, cwd=scratch, env=environment,
                                   stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            # Native tests create their own sessions, so killing one process group is insufficient.
            stop_process_tree(process.pid)
            process.wait()
            if sys.exc_info()[0] is KeyboardInterrupt:
                raise
            code, state = 124, 'timeout'
    content = log.read_text(errors='replace')
    if code != stage.expected_returncode:
        state = 'failed' if state == 'passed' else state
    elif stage.expected_output and stage.expected_output not in content:
        code, state = 1, 'missing-output'
    result = dict(name=stage.name, status=state, returncode=code,
                  seconds=round(time.monotonic() - start, 2), log=str(log), command=stage.command)
    print(f'{state.upper()} {stage.name} ({result["seconds"]}s)', flush=True)
    if state != 'passed':
        print('\n'.join(content.splitlines()[-35:]), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('suite', choices=SUITES)
    parser.add_argument('--compiler', required=True, type=Path, help='Linux compiler executable; use Release for applications')
    parser.add_argument('--dev-compiler', type=Path, help='DevMode compiler for the C++ stage; required by all and compiler')
    parser.add_argument('--dev-full', action='store_true', help='include filesystem C++ tests (automatic in all and compiler)')
    parser.add_argument('--execution', choices=('both', 'jit', 'native'))
    parser.add_argument('--build-cfg', choices=('devmode', 'release', 'release-safe'), default='devmode')
    parser.add_argument('--file-filter', help='select standalone compiler source inputs')
    parser.add_argument('--module', help='select one workspace module')
    parser.add_argument('--test-file', action='append', default=[])
    parser.add_argument('--test-tag', action='append', default=[])
    parser.add_argument('--timeout', type=int, default=900, help='seconds per compiler invocation (default: 900)')
    parser.add_argument('--output-dir', type=Path, help='new external directory for sources, caches, logs and report; retained after the run')
    parser.add_argument('--keep-going', action='store_true', help='continue independent stages after an error')
    parser.add_argument('--dry-run', action='store_true', help='stage inputs and write the command plan without executing tests')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if sys.platform != 'linux' or platform.machine() != 'x86_64':
        parser.error('the test host must be Linux x86-64')
    if args.timeout <= 0:
        parser.error('--timeout needs a positive number of seconds')
    if args.suite in ('all', 'compiler') and not args.dev_compiler:
        parser.error('--dev-compiler is required to include the C++ tests')
    if args.dev_full and args.suite != 'cpp':
        parser.error('--dev-full only applies to cpp; all and compiler already include it')
    if args.execution and args.suite not in ('native', *WORKSPACES, 'dynamic-library'):
        parser.error('--execution only applies to native or a bin workspace')
    if (args.module or args.test_file or args.test_tag) and args.suite not in (*WORKSPACES, 'workspace'):
        parser.error('--module, --test-file and --test-tag need a workspace suite')
    if args.file_filter is not None and (args.suite not in SOURCE_SUITES or not args.file_filter):
        parser.error('--file-filter needs a nonempty standalone source-suite filter')
    if args.module:
        directory = root / 'bin' / ('unittests/workspace' if args.suite == 'workspace' else args.suite)
        if Path(args.module).name != args.module or args.module in ('.', '..') or not (directory / 'modules' / args.module / 'module.swg').is_file():
            parser.error('--module needs an existing module in the selected workspace')
    for executable in (args.compiler, args.dev_compiler):
        if executable and (not executable.is_file() or not os.access(executable, os.X_OK)):
            parser.error(f'compiler is not executable: {executable}')
    if args.output_dir:
        scratch = args.output_dir.resolve()
        if scratch == root or root in scratch.parents:
            parser.error('--output-dir needs a directory outside the checkout')
        if scratch.exists():
            parser.error('--output-dir already exists; select a new directory')
        scratch.mkdir(parents=True)
    else:
        scratch = Path(tempfile.mkdtemp(prefix='swc-linux-tests-')).resolve()
    print(f'Test artifacts: {scratch}', flush=True)
    import resource
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    compiler = scratch / 'swc'
    shutil.copy2(args.compiler.resolve(), compiler)
    dev_compiler = None
    if args.dev_compiler:
        dev_compiler = scratch / 'swc.dm'
        shutil.copy2(args.dev_compiler.resolve(), dev_compiler)
    # Keep the installed bin layout, including data and golden fixtures. Exclude only
    # generated workspace output and caches; never select a subset of source files.
    for name in ('runtime', 'unittests', 'std', *(WORKSPACES[1:] if args.suite == 'all' else (args.suite,) if args.suite in WORKSPACES[1:] else ())):
        shutil.copytree(root / 'bin' / name, scratch / name, ignore=shutil.ignore_patterns('.output', '.tmp'))
    (scratch / 'temp').mkdir()
    (scratch / 'logs').mkdir()
    environment = os.environ.copy()
    environment.update(TMPDIR=str(scratch / 'temp'), SWAG_PATH=str(scratch), SWAG_RUNTIME_THREADS='3')
    if environment.get('SWAG_GOLDEN_CONTINUE') == '1':
        parser.error('SWAG_GOLDEN_CONTINUE=1 hides golden failures; unset it before running tests')
    if args.suite == 'all':
        portability_check(root)
    stages = plan(args, scratch, compiler, dev_compiler)
    (scratch / 'plan.json').write_text(json.dumps([vars(stage) for stage in stages], indent=2) + '\n')
    if args.dry_run:
        print(f'Planned {len(stages)} stages; no tests executed.', flush=True)
        return 0
    admission = [sys.executable, str(root / '.agents/skills/modify-swag-codebase/scripts/check-machine-load.py')]
    results = []
    passed = set()
    for stage in stages:
        if any(name not in passed for name in stage.requires):
            result = dict(name=stage.name, status='blocked', requires=stage.requires)
            print(f'BLOCKED {stage.name}: prerequisite did not pass', flush=True)
        else:
            result = run_stage(stage, scratch, environment, args.timeout, admission)
        results.append(result)
        if result['status'] == 'passed':
            passed.add(stage.name)
        report = dict(suite=args.suite, planned=len(stages), passed=len(passed), results=results,
                      complete=len(results) == len(stages))
        (scratch / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        if result['status'] != 'passed' and not args.keep_going:
            break
    print(f'{len(passed)}/{len(stages)} stages passed; report: {scratch / "report.json"}', flush=True)
    return 0 if len(passed) == len(stages) else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError) as error:
        print(f'cannot complete Linux tests: {error}', file=sys.stderr)
        raise SystemExit(1)
