"""Shared Windows/Linux commands behind the repository's workspace and test launchers.

Usage: tool.py <tests|unittests|std|apps|examples|reference|goldens> [dm] [action|suite] [module] [swc options]
Use `tool.py goldens accept` to promote reviewed pending snapshots without a compiler.
Set SWC_COMPILER or SWC_DEVMODE_COMPILER to select an externally built compiler.
Use --keep-going to continue independent test stages after a failure.
"""

from dataclasses import dataclass, field
import os
from pathlib import Path
import shutil
import subprocess
import sys


SOURCE_SUITES = ('lexer', 'parser', 'sema', 'jit', 'safety', 'sanity', 'native')
WORKSPACES = ('std', 'examples', 'apps', 'reference')
COMPILER_SUITES = ('cpp', *SOURCE_SUITES, 'workspace')


@dataclass
class Stage:
    name: str
    command: list[str]
    requires: list[str] = field(default_factory=list)
    expected_output: str = ''
    forbidden_output: str = ''
    expected_returncode: int = 0


def option_value(options, names, default):
    value = default
    for index, option in enumerate(options):
        if option in names:
            if index + 1 == len(options):
                raise ValueError(f'option {option!r} needs a value')
            value = options[index + 1]
        for name in names:
            if option.startswith(name + '='):
                value = option[len(name) + 1:]
    return value


def without_options(options, names):
    result = []
    index = 0
    while index < len(options):
        option = options[index]
        if option in names:
            if index + 1 == len(options):
                raise ValueError(f'option {option!r} needs a value')
            index += 2
        elif any(option.startswith(name + '=') for name in names):
            index += 1
        else:
            result.append(option)
            index += 1
    return result


def runtime_workers(options):
    value = option_value(options, ('-j', '--num-cores'), '3')
    return str(min(int(value), 3)) if value.isdecimal() and int(value) > 0 else '3'


def module_names(workspace):
    return sorted(path.name for path in (workspace / 'modules').iterdir() if path.is_dir())


def cpp_stage(compiler, options, full=True):
    options = without_options(options, ('-bc', '--build-cfg'))
    return Stage('cpp', [str(compiler), 'unittest', *(['--dev-full'] if full else []), '--num-cores', '3', *options])


def source_stages(compiler, bin_root, suite, options, output_root=None):
    flags = {'lexer': ['--lex-only'], 'parser': ['--syntax-only'], 'sema': ['--sema-only'],
             'jit': ['--no-output'], 'safety': ['--no-output', '--tag', 'Swag.AllocatorSafety'],
             'sanity': ['--no-output'], 'native': []}[suite]
    if suite == 'native':
        directories = [suite]
        if '--no-test-native' not in options and '--no-output' not in options:
            directories += ['errors/native/owning', 'errors/native/pointer']
    else:
        directories = [suite, 'errors/' + suite] if suite in ('lexer', 'parser', 'sema') else [suite]
    stages = []
    for directory in directories:
        # The expected-error semantic corpus depends on deterministic cross-file analysis.
        workers = '1' if directory == 'errors/sema' else '3'
        command = [str(compiler), 'test', '--directory', str(bin_root / 'unittests' / directory),
                   '--module-namespace', suite.capitalize(), '--artifact-kind', 'executable',
                   '--num-cores', workers, *flags, *options]
        if output_root:
            command += ['--out-dir', str(output_root / 'out' / directory),
                        '--work-dir', str(output_root / 'work' / directory)]
        stages.append(Stage(directory.replace('/', '-'), command))
    return stages


def workspace_stages(compiler, bin_root, options, *, windows=False, modules=None, script=True, execution=None):
    workspace = bin_root / 'unittests/workspace'
    cfg = option_value(options, ('-bc', '--build-cfg'), 'devmode')
    workers = option_value(options, ('-j', '--num-cores'), '3')
    extension = '.dll' if windows else '.so'
    library = workspace / '.output/runtime_context_dynamic_dll/shared-library' / cfg / 'x86_64' / ('runtime_context_dynamic_dll' + extension)
    dynamic_dependency = workspace / '.output/runtime_context_dynamic_dep/shared-library' / cfg / 'x86_64' / ('runtime_context_dynamic_dep' + extension)
    build_name = 'workspace-build-dynamic-library'
    package_name = 'workspace-package-dynamic-library-dependency'
    build_options = ['--build-cfg', cfg, '--num-cores', workers]
    if '--rebuild' in options:
        build_options.append('--rebuild')
    selected = module_names(workspace) if modules is None else modules
    stages = []
    if 'runtime_context_dynamic_consumer' in selected:
        stages.append(Stage(build_name, [str(compiler), 'build', '--workspace', str(workspace),
                                         '--workspace-module', 'runtime_context_dynamic_dll', *build_options]))
        # A NativeLibrary path identifies one deployable directory. Package its workspace
        # dependency beside it so the platform loader can resolve the library's SONAME.
        stages.append(Stage(package_name, [sys.executable, '-c',
                                           'import shutil, sys; shutil.copy2(sys.argv[1], sys.argv[2])',
                                           str(dynamic_dependency), str(library.parent)], [build_name]))
    script_dependency_build_name = 'workspace-build-lifecycle-script-dependency'
    if script:
        stages.append(Stage(script_dependency_build_name, [str(compiler), 'build', '--workspace', str(workspace),
                                                          '--workspace-module', 'lifecycle_script_dep', *build_options]))
    for module in selected:
        command = [str(compiler), 'test', '--workspace', str(workspace), '--workspace-module', module]
        requires = []
        expected_output = ''
        if module == 'sandbox_consumer':
            command += ['--rebuild', '--no-test-native']
        elif module == 'runtime_context_dynamic_consumer' and execution == 'jit':
            command += ['--test-jit', '--no-test-native']
        elif module == 'runtime_context_dynamic_consumer' and execution == 'both':
            command.append('--test-jit')
        else:
            command.append('--no-test-jit')
        if module == 'runtime_context_dynamic_consumer':
            command.append('--run-arg=--dynamic-runtime-library=' + str(library))
            requires = [package_name]
            expected_output = ('SWAG_DYNAMIC_DEP_INIT\nSWAG_DYNAMIC_LIB_INIT\n'
                               'SWAG_DYNAMIC_DEP_PREMAIN\nSWAG_DYNAMIC_LIB_PREMAIN\n'
                               'SWAG_DYNAMIC_LIB_DROP\nSWAG_DYNAMIC_DEP_DROP')
        if module == 'lifecycle_native_consumer':
            expected_output = ('SWAG_DEP_INIT\nSWAG_NATIVE_INIT\nSWAG_DEP_PREMAIN\n'
                               'SWAG_NATIVE_PREMAIN\nSWAG_NATIVE_TEST\nSWAG_NATIVE_DROP\nSWAG_DEP_DROP')
        stages.append(Stage('workspace-' + module, [*command, '--num-cores', '3', *options], requires,
                            expected_output=expected_output))
    if script:
        failed_drop = workspace / 'native_failed_drop'
        stages.append(Stage('workspace-native-failed-drop', [str(compiler), 'test',
                            '--directory', str(failed_drop / 'src'), '--module-file', str(failed_drop / 'module.swg'),
                            '--module-namespace', 'NativeFailedDrop', '--artifact-kind', 'executable',
                            '--no-test-jit', '--run-timeout', '5', '--build-cfg', cfg,
                            '--num-cores', runtime_workers(options)],
                            expected_output='SWAG_NATIVE_DROP_PANIC', forbidden_output='SWAG_NATIVE_SECOND_DROP',
                            expected_returncode=5))
        failed_test = workspace / 'native_failed_test'
        stages.append(Stage('workspace-native-abandoned-test', [str(compiler), 'test',
                            '--directory', str(failed_test / 'src'), '--module-file', str(failed_test / 'module.swg'),
                            '--module-namespace', 'NativeAbandonedTest', '--artifact-kind', 'executable',
                            '--no-test-jit', '--run-timeout', '5', '--build-cfg', cfg, '--num-cores', runtime_workers(options)],
                            expected_output='SWAG_TEST_PANIC_STARTED', forbidden_output='SWAG_TEST_AFTER_PANIC',
                            expected_returncode=5))
        stages.append(Stage('workspace-jit-abandoned-test', [str(compiler), 'test',
                            '--directory', str(failed_test / 'src'), '--module-file', str(failed_test / 'module.swg'),
                            '--module-namespace', 'JitAbandonedTest', '--artifact-kind', 'export',
                            '--no-test-native', '--build-cfg', cfg, '--num-cores', runtime_workers(options)],
                            expected_output='SWAG_TEST_PANIC_STARTED', forbidden_output='SWAG_TEST_AFTER_PANIC',
                            expected_returncode=5))
        for name, namespace, marker, forbidden in (
                ('jit_failed_init', 'JitFailedInit', 'SWAG_JIT_INIT_PANIC', 'SWAG_JIT_DROP_AFTER_INIT'),
                ('jit_failed_premain', 'JitFailedPreMain', 'SWAG_JIT_PREMAIN_PANIC', 'SWAG_JIT_DROP_AFTER_PREMAIN'),
                ('jit_failed_drop', 'JitFailedDrop', 'SWAG_JIT_DROP_PANIC', 'SWAG_JIT_SECOND_DROP')):
            fixture = workspace / name
            stages.append(Stage('workspace-' + name.replace('_', '-'), [str(compiler), 'test',
                                '--directory', str(fixture / 'src'), '--module-file', str(fixture / 'module.swg'),
                                '--module-namespace', namespace, '--artifact-kind', 'export', '--no-test-native',
                                '--build-cfg', cfg, '--num-cores', runtime_workers(options)],
                                expected_output=marker, forbidden_output=forbidden, expected_returncode=5))
        stages.append(Stage('workspace-import-png-script', [str(compiler), '--build-cfg', cfg, '--num-cores', workers,
                            str(workspace / 'import_png.swgs')],
                            expected_output='SWAG_IMPORTED_PNG_RAN'))
        stages.append(Stage('workspace-import-script', [str(compiler), '--build-cfg', cfg, '--num-cores', workers,
                            str(workspace / 'import_core_without_using.swgs')],
                            expected_output='SWAG_IMPORTED_CORE_WITHOUT_USING_RAN'))
        stages.append(Stage('workspace-lifecycle-script', [str(compiler), '--build-cfg', cfg, '--num-cores', workers,
                            str(workspace / 'lifecycle_order.swgs')],
                            expected_output='SWAG_LIFECYCLE_ORDER_RAN'))
        stages.append(Stage('workspace-failed-drop-script', [str(compiler), '--build-cfg', cfg, '--num-cores', workers,
                            str(workspace / 'lifecycle_failed_drop.swgs')],
                            expected_output='SWAG_SECOND_DROP_RAN', expected_returncode=5))
        stages.append(Stage('workspace-failed-main-script', [str(compiler), '--build-cfg', cfg, '--num-cores', workers,
                            str(workspace / 'lifecycle_failed_main.swgs')],
                            expected_output='SWAG_DROP_AFTER_MAIN_RAN', expected_returncode=5))
        stages.append(Stage('workspace-failed-init-script', [str(compiler), '--build-cfg', cfg, '--num-cores', workers,
                            str(workspace / 'lifecycle_failed_init.swgs')],
                            requires=[script_dependency_build_name], expected_output='SWAG_SCRIPT_DROP\nSWAG_DEP_DROP', expected_returncode=5))
        stages.append(Stage('workspace-failed-check-script', [str(compiler), '--build-cfg', cfg, '--num-cores', workers,
                            str(workspace / 'lifecycle_failed_check.swgs')],
                            requires=[script_dependency_build_name], expected_output='SWAG_ORDINARY_DROP_RELEASED\nSWAG_DEP_DROP', expected_returncode=5))
        stages.append(Stage('workspace-failed-premain-script', [str(compiler), '--build-cfg', cfg, '--num-cores', workers,
                            str(workspace / 'lifecycle_failed_premain.swgs')],
                            requires=[script_dependency_build_name], expected_output='SWAG_SCRIPT_DROP\nSWAG_DEP_DROP', expected_returncode=5))
    return stages


# A module's native test executable runs all of its tests in one process. The compiler's default
# limit of five minutes guards a single hung program, but the largest application suites take
# about that long on an idle machine and longer on a loaded one, so a sound run was reported as a
# hang. Module tests get twenty minutes unless the caller sets its own limit; each test still has
# to finish within its own deadline.
WORKSPACE_TEST_TIMEOUT_SECONDS = 1200


def module_stage(compiler, bin_root, workspace, action, module, options, *, child_compiler=False):
    command = [str(compiler), action, '--workspace', str(bin_root / workspace)]
    if module:
        command += ['--workspace-module', module]
    if action == 'test':
        if workspace in ('apps', 'std'):
            command.append('--no-test-jit')
            if option_value(options, ('--run-timeout',), None) is None:
                command += ['--run-timeout', str(WORKSPACE_TEST_TIMEOUT_SECONDS)]
        if workspace == 'std':
            command += ['--artifact-kind', 'executable']
    if workspace == 'apps' and action != 'build' and (not module or child_compiler):
        command += ['--run-arg=--compiler=' + str(compiler), '--run-arg=--compiler-workers=' + runtime_workers(options)]
    return Stage(workspace + ('-' + module if module else ''), [*command, '--num-cores', '3', *options])


def compiler_stages(compiler, bin_root, suite, options, *, devmode=False, windows=False):
    stages = []
    for name in COMPILER_SUITES if suite is None else (suite,):
        if name == 'cpp':
            if devmode:
                stages.append(cpp_stage(compiler, options))
        elif name == 'workspace':
            stages += workspace_stages(compiler, bin_root, options, windows=windows)
        elif name in SOURCE_SUITES:
            stages += source_stages(compiler, bin_root, name, options)
        else:
            raise ValueError(f'unknown compiler suite {name!r}; choose from {", ".join(COMPILER_SUITES)}')
    return stages


def portability_check(root):
    scripts = sorted((root / 'tools').rglob('*.swgs'))
    if scripts:
        raise ValueError(f'Swag script launchers remain under tools: {scripts[0]}')


def package_vault(bin_root, module, options):
    if module and module != 'swagvault':
        return
    cfg = option_value(options, ('-bc', '--build-cfg'), 'devmode')
    if '--debug' in options:
        cfg += '-debug'
    output = bin_root / 'apps/.output/swagvault/executable' / cfg / 'x86_64'
    if not (output / 'swagvault.exe').is_file():
        return
    app = bin_root / 'apps/modules/swagvault'
    for source in (app / 'vendor/winfsp/runtime/winfsp-x64.dll', app / 'vendor/winfsp/runtime/winfsp-x64.sys',
                   app / 'LICENCE.md', app / 'THIRDPARTY.md'):
        shutil.copy2(source, output / source.name)


def execute(stages, environment, *, keep_going=False):
    passed = set()
    first_failure = 0
    for stage in stages:
        if any(name not in passed for name in stage.requires):
            print(f'blocked {stage.name}: prerequisite did not pass', file=sys.stderr)
            first_failure = first_failure or 1
            if not keep_going:
                return first_failure
            continue
        result = subprocess.run(stage.command, env=environment, check=False,
                                stdout=subprocess.PIPE if stage.expected_output or stage.forbidden_output else None)
        stage_failure = 0
        if stage.expected_output or stage.forbidden_output:
            output = result.stdout.decode('utf-8', errors='replace')
            if hasattr(sys.stdout, 'buffer'):
                sys.stdout.buffer.write(result.stdout)
                sys.stdout.buffer.flush()
            else:
                print(output, end='', flush=True)
            if result.returncode == stage.expected_returncode and stage.expected_output not in output:
                print(f'expected output is missing: {stage.expected_output}', file=sys.stderr)
                stage_failure = 1
            if stage.forbidden_output and stage.forbidden_output in output:
                print(f'forbidden output was present: {stage.forbidden_output}', file=sys.stderr)
                stage_failure = 1
        if result.returncode != stage.expected_returncode:
            stage_failure = result.returncode if result.returncode > 0 else 128 - result.returncode
        if stage_failure:
            first_failure = first_failure or stage_failure
            if not keep_going:
                return first_failure
        else:
            passed.add(stage.name)
    return first_failure


def accept_goldens(bin_root):
    """Promote reviewed pending text and image snapshots using the same rule on both hosts."""
    accepted = 0
    for actual in sorted(bin_root.rglob('*')):
        if not actual.is_file() or not actual.name.endswith(('.actual.txt', '.actual.png')):
            continue
        golden = actual.with_name(actual.name.removesuffix(actual.suffix).removesuffix('.actual') + actual.suffix)
        actual.replace(golden)
        accepted += 1
        print(f'accepted {actual.name}')
    if not accepted:
        print('no pending snapshot to accept')
    return 0


def main(arguments=None):
    arguments = list(sys.argv[1:] if arguments is None else arguments)
    if not arguments or arguments[0] in ('-h', '--help'):
        print(__doc__)
        return 0
    tool = arguments.pop(0).lower()
    if tool not in ('tests', 'unittests', 'goldens', *WORKSPACES):
        raise ValueError(f'unknown tool {tool!r}')
    devmode = bool(arguments and arguments[0].lower() == 'dm')
    if devmode:
        arguments.pop(0)
    if arguments and arguments[0] in ('-h', '--help'):
        print(__doc__)
        print('Compiler suites: ' + ', '.join(COMPILER_SUITES))
        return 0
    keep_going = '--keep-going' in arguments
    arguments = [argument for argument in arguments if argument != '--keep-going']
    root = Path(__file__).resolve().parent.parent
    bin_root = root / 'bin'
    if tool == 'goldens':
        if arguments != ['accept']:
            raise ValueError('use goldens accept to promote reviewed snapshots')
        return accept_goldens(bin_root)
    windows = sys.platform == 'win32'
    default = bin_root / (('swc.dm' if devmode else 'swc') + ('.exe' if windows else ''))
    compiler = Path(os.environ.get('SWC_DEVMODE_COMPILER' if devmode else 'SWC_COMPILER', str(default))).absolute()
    if not compiler.is_file():
        raise ValueError(f'compiler not found: {compiler}')
    environment = os.environ.copy()
    action, module = 'test', None
    if tool in ('tests', 'unittests'):
        suite = arguments.pop(0) if tool == 'unittests' and arguments and not arguments[0].startswith('-') else None
        if tool == 'tests':
            portability_check(root)
        stages = compiler_stages(compiler, bin_root, suite, arguments, devmode=devmode, windows=windows)
        if tool == 'tests':
            stages += [module_stage(compiler, bin_root, workspace, 'test', None, arguments) for workspace in WORKSPACES]
    else:
        action = 'test' if tool == 'reference' else 'build'
        if arguments and arguments[0] in ('build', 'test', 'run', 'smoke'):
            action = arguments.pop(0)
        if arguments and not arguments[0].startswith('-'):
            module = arguments.pop(0).strip('"')
        if tool == 'apps' and action == 'run' and not module:
            raise ValueError('running an application needs its name')
        stages = [module_stage(compiler, bin_root, tool, action, module, arguments)]
    if action == 'test':
        environment.setdefault('SWAG_RUNTIME_THREADS', runtime_workers(arguments))
    result = execute(stages, environment, keep_going=keep_going)
    if result == 0 and windows and tool == 'apps' and action == 'build':
        package_vault(bin_root, module, arguments)
    return result


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f'error: {error}', file=sys.stderr)
        raise SystemExit(1)
