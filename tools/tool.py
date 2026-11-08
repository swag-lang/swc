"""Shared Windows/Linux commands behind the repository's workspace and test launchers.

Usage: tool.py <tests|unittests|std|apps|examples|reference|goldens> [dm] [action|suite] [module] [swc options]
Use `tool.py goldens accept` to promote reviewed pending snapshots without a compiler.
Set SWC_COMPILER or SWC_DEVMODE_COMPILER to select an externally built compiler.
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
    build_name = 'workspace-build-dynamic-library'
    build_options = ['--build-cfg', cfg, '--num-cores', workers]
    if '--rebuild' in options:
        build_options.append('--rebuild')
    selected = module_names(workspace) if modules is None else modules
    stages = []
    if 'runtime_context_dynamic_consumer' in selected:
        stages.append(Stage(build_name, [str(compiler), 'build', '--workspace', str(workspace),
                                         '--workspace-module', 'runtime_context_dynamic_dll', *build_options]))
    for module in selected:
        command = [str(compiler), 'test', '--workspace', str(workspace), '--workspace-module', module]
        requires = []
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
            requires = [build_name]
        stages.append(Stage('workspace-' + module, [*command, '--num-cores', '3', *options], requires))
    if script:
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


def execute(stages, environment):
    for stage in stages:
        result = subprocess.run(stage.command, env=environment, check=False,
                                stdout=subprocess.PIPE if stage.expected_output else None)
        if stage.expected_output:
            output = result.stdout.decode('utf-8', errors='replace')
            if hasattr(sys.stdout, 'buffer'):
                sys.stdout.buffer.write(result.stdout)
                sys.stdout.buffer.flush()
            else:
                print(output, end='', flush=True)
            if result.returncode == stage.expected_returncode and stage.expected_output not in output:
                print(f'expected output is missing: {stage.expected_output}', file=sys.stderr)
                return 1
        if result.returncode != stage.expected_returncode:
            return result.returncode if result.returncode > 0 else 128 - result.returncode
    return 0


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
    result = execute(stages, environment)
    if result == 0 and windows and tool == 'apps' and action == 'build':
        package_vault(bin_root, module, arguments)
    return result


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f'error: {error}', file=sys.stderr)
        raise SystemExit(1)
