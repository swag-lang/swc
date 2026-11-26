"""Check the shared launcher contract on both host plans without a compiler build."""

from contextlib import redirect_stdout
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import tool


class ToolTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='swag tools ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'tools').mkdir()
        (self.root / 'bin').mkdir()
        for name in ('swc', 'swc.dm', 'swc.exe', 'swc.dm.exe'):
            (self.root / 'bin' / name).touch()
        for module in ('sandbox_consumer', 'runtime_context_dynamic_consumer', 'runtime_context_dynamic_dll'):
            (self.root / 'bin/unittests/workspace/modules' / module).mkdir(parents=True)
        self.stages = []
        self.environment = {}
        self.keep_going = False

    def invoke(self, arguments, windows=False, environment=None, result=0):
        def execute(stages, env, *, keep_going=False):
            self.stages = stages
            self.environment = env
            self.keep_going = keep_going
            return result
        with patch.object(tool, '__file__', str(self.root / 'tools/tool.py')), \
             patch.object(tool.sys, 'platform', 'win32' if windows else 'linux'), \
             patch.dict(os.environ, environment or {}, clear=True), patch.object(tool, 'execute', execute):
            return tool.main(arguments)

    def test_golden_accept_needs_no_compiler_and_preserves_unrelated_files(self):
        folder = self.root / 'bin/std/modules/fixture/src/tests/goldens'
        folder.mkdir(parents=True)
        for path in (self.root / 'bin').glob('swc*'):
            path.unlink()
        (folder / 'image.png').write_bytes(b'old image')
        (folder / 'image.actual.png').write_bytes(b'reviewed image')
        (folder / 'text.actual.txt').write_text('reviewed text')
        (folder / 'keep.actual.bin').write_bytes(b'unrelated')
        # What the parity campaign leaves is a diagnostic of a divergence, never a reference.
        (folder / 'scene.parity.gpu.png').write_bytes(b'gpu image')
        with redirect_stdout(io.StringIO()):
            self.assertEqual(self.invoke(['goldens', 'accept']), 0)
        self.assertEqual((folder / 'image.png').read_bytes(), b'reviewed image')
        self.assertEqual((folder / 'scene.parity.gpu.png').read_bytes(), b'gpu image')
        self.assertEqual((folder / 'text.txt').read_text(), 'reviewed text')
        self.assertEqual((folder / 'keep.actual.bin').read_bytes(), b'unrelated')
        self.assertFalse(list(folder.glob('*.actual.png')))
        self.assertFalse(list(folder.glob('*.actual.txt')))

    def test_empty_golden_accept_and_invalid_action(self):
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(self.invoke(['goldens', 'accept'], windows=True), 0)
        self.assertIn('no pending snapshot', output.getvalue())
        with self.assertRaises(ValueError):
            self.invoke(['goldens', 'unexpected'])

    def test_functional_pass_uses_same_suites_on_both_hosts(self):
        for workspace, tag in (('std', 'stress'), ('apps', 'golden')):
            path = self.root / f'bin/{workspace}/modules/fixture/src/tests/cases/special.swg'
            path.parent.mkdir(parents=True)
            path.write_text(f'#[Swag.TestTag("{tag}")]\n#test {{}}\n', encoding='utf-8')
        for windows in (False, True):
            self.assertEqual(self.invoke(['tests', 'dm', 'functional', '-bc', 'release'], windows=windows), 0)
            names = [stage.name for stage in self.stages]
            self.assertEqual(names[:13], ['cpp', 'lexer', 'errors-lexer', 'parser', 'errors-parser',
                                         'sema', 'errors-sema', 'jit', 'safety', 'sanity', 'native',
                                         'errors-native-owning', 'errors-native-pointer'])
            self.assertEqual(names[-4:], list(tool.WORKSPACES))
            self.assertTrue(self.stages[0].command[0].endswith('swc.dm.exe' if windows else 'swc.dm'))
            for stage in self.stages[:-4]:
                self.assertNotIn('--test-tag', stage.command)
            for stage in self.stages[-4:]:
                tags = ['!golden', '!stress'] if stage.name in ('std', 'apps') else []
                self.assertEqual(list(tool.option_values(stage.command, ('--test-tag',))), tags)
        self.invoke(['tests'])
        self.assertNotIn('cpp', [stage.name for stage in self.stages])
        self.assertIn('!stress', self.stages[-2].command)

    def test_tagged_passes_use_case_owners_and_keep_independent_stages(self):
        for workspace, case, tag in (('std', 'scene.swg', 'golden'), ('examples', 'example.swg', 'golden'),
                                     ('apps', 'large.swg', 'stress'), ('reference', 'stress.swg', 'stress')):
            path = self.root / f'bin/{workspace}/modules/fixture/src/tests/cases/nested' / case
            path.parent.mkdir(parents=True)
            path.write_text(f'#[Swag.TestTag("{tag}")]\n#test {{}}\n', encoding='utf-8')
        prose = self.root / 'bin/reference/modules/fixture/src/guide.swg'
        prose.write_text('#[Swag.TestTag("golden")]\n', encoding='utf-8')

        self.assertEqual(self.invoke(['tests', 'goldens', '--num-cores', '2'], windows=True), 0)
        self.assertEqual([stage.name for stage in self.stages], ['std-fixture', 'examples-fixture'])
        for stage in self.stages:
            self.assertEqual(tool.option_value(stage.command, ('-bc',), ''), 'release')
            self.assertEqual(list(tool.option_values(stage.command, ('--test-tag',))), ['golden'])
        self.assertTrue(self.keep_going)
        self.assertEqual(self.invoke(['goldens', 'dm', 'test'], windows=True, result=7), 1)
        self.assertEqual([stage.name for stage in self.stages], ['std-fixture', 'examples-fixture'])
        self.assertTrue(self.stages[0].command[0].endswith('swc.dm.exe'))
        self.assertTrue(self.keep_going)

        self.invoke(['tests', 'stress', '-bc', 'release'])
        self.assertEqual([stage.name for stage in self.stages], ['apps-fixture', 'reference-fixture'])
        self.assertTrue(self.keep_going)
        self.invoke(['tests', 'stress', '--test-file', 'large.swg'])
        self.assertEqual([stage.name for stage in self.stages], ['apps-fixture'])
        with self.assertRaisesRegex(ValueError, 'match the selected files'):
            self.invoke(['tests', 'stress', '--test-file', 'absent.swg'])
        with self.assertRaisesRegex(ValueError, 'needs -bc release'):
            self.invoke(['tests', 'goldens', '-bc', 'devmode'])

    def test_integrations_default_and_explicit_tags_are_host_specific(self):
        fixtures = (
            ('std', 'pixel', 'parity.swg', 'integration.renderer.opengl'),
            ('std', 'pixel', 'reset.swg', 'integration.renderer.reset'),
            ('std', 'gui', 'host.win32.swg', 'integration.host.windows'),
            ('std', 'gui', 'host.linux.swg', 'integration.host.linux'),
            ('apps', 'scope', 'journey.swg', 'integration.application.journey'),
            ('apps', 'scope', 'input.swg', 'integration.desktop.input'),
            ('apps', 'vault', 'resident.win32.swg', 'integration.application.journey'),
        )
        for workspace, module, case, tag in fixtures:
            path = self.root / f'bin/{workspace}/modules/{module}/src/tests/cases' / case
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f'#[Swag.TestTag("{tag}")]\n#test {{}}\n', encoding='utf-8')
        guarded_case = self.root / 'bin/apps/modules/vault/src/tests/cases/mount.swg'
        guarded_case.write_text('#global if #os == Swag.TargetOs.Linux and #command == Swag.CompilerCommand.Test\n'
                                '#[Swag.TestTag("integration.filesystem.fuse")]\n#test {}\n', encoding='utf-8')

        for windows in (False, True):
            self.invoke(['tests', 'integrations'], windows=windows)
            tags = {stage.name: list(tool.option_values(stage.command, ('--test-tag',))) for stage in self.stages}
            self.assertEqual(tags['std-gui'], ['integration.host.windows' if windows else 'integration.host.linux'])
            self.assertEqual(tags['std-pixel'], ['integration.renderer.opengl'])
            self.assertEqual(tags['apps-scope'], ['integration.application.journey', 'integration.desktop.input'])
            self.assertEqual('apps-vault' in tags, windows)
            self.assertTrue(self.keep_going)

        self.invoke(['tests', 'integrations', '--test-tag=integration.renderer.reset', '--run-timeout', '30'])
        self.assertEqual([stage.name for stage in self.stages], ['std-pixel'])
        self.assertEqual(list(tool.option_values(self.stages[0].command, ('--test-tag',))), ['integration.renderer.reset'])
        self.assertEqual(tool.option_value(self.stages[0].command, ('--run-timeout',), ''), '30')
        with self.assertRaisesRegex(ValueError, 'no integration tests declare'):
            self.invoke(['tests', 'integrations', '--test-tag', 'integration.host.windows'])
        with self.assertRaisesRegex(ValueError, 'no integration tests declare'):
            self.invoke(['tests', 'integrations', '--test-tag', 'integration.filesystem.fuse'], windows=True)
        with self.assertRaisesRegex(ValueError, 'accepts test tags'):
            self.invoke(['tests', 'integrations', '--test-tag', 'stress'])

        output = io.StringIO()
        for compiler in (self.root / 'bin').glob('swc*'):
            compiler.unlink()
        with redirect_stdout(output):
            self.assertEqual(self.invoke(['tests', 'integrations', '--list']), 0)
        self.assertIn('integration.renderer.reset [explicit]: std/pixel', output.getvalue())
        self.assertIn('integration.desktop.input [default]: apps/scope', output.getvalue())
        self.assertNotIn('integration.host.windows', output.getvalue())

    def test_smoke_pass_routes_windows_scripts_and_both_native_workspaces(self):
        scripts = self.root / 'bin/examples/scripts'
        scripts.mkdir(parents=True)
        (scripts / 'example.swgs').touch()
        for windows in (False, True):
            self.invoke(['tests', 'smoke', '-bc', 'release'], windows=windows)
            names = [stage.name for stage in self.stages]
            self.assertEqual(names, ['smoke-example', 'examples', 'apps'] if windows else ['examples', 'apps'])
            for stage in self.stages:
                self.assertEqual(stage.command[1], 'smoke')
                self.assertNotIn('--test-tag', stage.command)
            self.assertNotIn('SWAG_RUNTIME_THREADS', self.environment)

    def test_cpp_does_not_receive_program_configuration(self):
        for cfg in (['-bc', 'release'], ['--build-cfg', 'devmode'], ['--build-cfg=release']):
            self.invoke(['unittests', 'dm', 'cpp', *cfg, '--num-cores', '1'])
            command = self.stages[0].command
            self.assertEqual(command[1:3], ['unittest', '--dev-full'])
            self.assertFalse(any(arg.startswith('--build-cfg') or arg == '-bc' for arg in command))
            self.assertEqual(command[-2:], ['--num-cores', '1'])

    def test_cpp_rebuild_options_apply_only_to_swag_stages(self):
        for windows in (False, True):
            for flag in ('--rebuild', '--rebuild-module', '--rebuild=true', '--rebuild-module=false'):
                self.invoke(['tests', 'dm', '-bc', 'release', flag, '--num-cores', '1'], windows=windows)
                cpp = self.stages[0].command
                source = next(stage.command for stage in self.stages if stage.name == 'lexer')
                self.assertNotIn(flag, cpp)
                self.assertIn(flag, source)
                self.assertEqual(cpp[-2:], ['--num-cores', '1'])
                self.invoke(['unittests', 'dm', 'cpp', flag], windows=windows)
                self.assertNotIn(flag, self.stages[0].command)

    def test_native_diagnostic_fixtures_require_native_execution(self):
        self.invoke(['unittests', 'native', '--no-test-native'])
        self.assertEqual([stage.name for stage in self.stages], ['native'])

    def test_source_suites_keep_generated_files_under_common_output_root(self):
        source_root = self.root / 'bin/unittests'
        output_root = source_root / '.output'
        for windows in (False, True):
            for suite in tool.SOURCE_SUITES:
                self.invoke(['unittests', suite], windows=windows)
                for stage in self.stages:
                    directory = Path(tool.option_value(stage.command, ('--directory',), '')).relative_to(source_root)
                    self.assertEqual(Path(tool.option_value(stage.command, ('--out-dir',), '')),
                                     output_root / 'out' / directory)
                    self.assertEqual(Path(tool.option_value(stage.command, ('--work-dir',), '')),
                                     output_root / 'work' / directory)

    def test_source_output_defaults_preserve_explicit_paths_and_isolation_root(self):
        self.invoke(['unittests', 'native', '--out-dir', 'custom output', '--work-dir', 'custom work'])
        for stage in self.stages:
            self.assertEqual(tool.option_value(stage.command, ('--out-dir',), ''), 'custom output')
            self.assertEqual(tool.option_value(stage.command, ('--work-dir',), ''), 'custom work')
        isolated = self.root / 'isolated'
        stages = tool.source_stages(self.root / 'bin/swc', self.root / 'bin', 'native', [], output_root=isolated)
        for stage in stages:
            for option, folder in (('--out-dir', 'out'), ('--work-dir', 'work')):
                path = Path(tool.option_value(stage.command, (option,), ''))
                self.assertTrue(path.is_relative_to(isolated / folder))

    def test_expected_error_sema_corpus_keeps_one_worker(self):
        for worker_option in (['--num-cores', '3'], ['-j', '2'], ['--num-cores=3']):
            self.invoke(['unittests', 'dm', 'sema', '-bc', 'devmode', *worker_option])
            command = next(stage.command for stage in self.stages if stage.name == 'errors-sema')
            self.assertEqual(command.count('--num-cores'), 1)
            self.assertEqual(command[command.index('--num-cores') + 1], '1')
            self.assertNotIn('-j', command)
            self.assertIn('devmode', command)

    def test_workspace_dynamic_library_tracks_host_and_configuration(self):
        for windows in (False, True):
            self.invoke(['unittests', 'dm', 'workspace', '-bc', 'release', '--num-cores', '1'], windows=windows)
            build, package = self.stages[:2]
            consumer = next(stage for stage in self.stages if stage.name == 'workspace-runtime_context_dynamic_consumer')
            self.assertEqual(build.command[1], 'build')
            self.assertIn('release', build.command)
            self.assertEqual(build.command[-2:], ['--num-cores', '1'])
            self.assertEqual(package.requires, [build.name])
            self.assertEqual(consumer.requires, [package.name])
            self.assertTrue(any(arg.endswith('runtime_context_dynamic_dll.dll' if windows else 'runtime_context_dynamic_dll.so') for arg in consumer.command))
            sandbox = next(stage for stage in self.stages if stage.name.endswith('sandbox_consumer'))
            self.assertIn('--rebuild', sandbox.command)
            self.assertIn('--no-test-native', sandbox.command)
            scripts = [Path(stage.command[-1]).name for stage in self.stages if stage.name.endswith('-script')]
            self.assertEqual(scripts, ['import_png.swgs', 'import_core_without_using.swgs', 'lifecycle_order.swgs'])

    def test_workers_and_explicit_runtime_override(self):
        for workers, expected in (('1', '1'), ('2', '2'), ('0', str(os.cpu_count() or 1)), ('8', '8')):
            self.invoke(['apps', 'dm', 'test', '--num-cores', workers])
            self.assertEqual(self.environment['SWAG_RUNTIME_THREADS'], expected)
            self.assertIn('--run-arg=--compiler-workers=' + expected, self.stages[0].command)
        self.invoke(['apps', 'dm', 'test', '--num-cores=1'], environment={'SWAG_RUNTIME_THREADS': '2'})
        self.assertEqual(self.environment['SWAG_RUNTIME_THREADS'], '2')
        self.assertIn('--run-arg=--compiler-workers=1', self.stages[0].command)

    def test_named_application_does_not_receive_unrequested_runtime_arguments(self):
        self.invoke(['apps', 'dm', 'test', 'swagscope', '--num-cores', '1'])
        command = self.stages[0].command
        self.assertIn('--no-test-jit', command)
        self.assertFalse(any(arg.startswith('--run-arg=--compiler') for arg in command))

    def test_module_tests_get_a_suite_sized_run_limit_unless_one_is_given(self):
        self.invoke(['apps', 'test', 'swagscope'])
        command = self.stages[0].command
        self.assertEqual(command[command.index('--run-timeout') + 1], str(tool.WORKSPACE_TEST_TIMEOUT_SECONDS))
        self.invoke(['std', 'dm', 'test', 'gui', '--run-timeout', '60'])
        command = self.stages[0].command
        self.assertEqual(command.count('--run-timeout'), 1)
        self.assertEqual(command[command.index('--run-timeout') + 1], '60')
        self.invoke(['apps', 'build', 'swagscope'])
        self.assertNotIn('--run-timeout', self.stages[0].command)

    def test_standard_native_default_can_be_overridden(self):
        self.invoke(['std', 'dm', 'test', 'pixel', '--test-jit', '--no-test-native', '--test-file', 'two words.swg'])
        command = self.stages[0].command
        self.assertGreater(command.index('--test-jit'), command.index('--no-test-jit'))
        self.assertEqual(command[-1], 'two words.swg')
        self.assertIn('--artifact-kind', command)
        self.invoke(['std', 'dm', 'build', 'pixel'])
        self.assertNotIn('--artifact-kind', self.stages[0].command)
        self.assertNotIn('--no-test-jit', self.stages[0].command)
        self.assertNotIn('SWAG_RUNTIME_THREADS', self.environment)

    def test_external_compiler_and_exit_status_are_preserved(self):
        self.assertEqual(self.invoke(['reference'], environment={'SWC_COMPILER': str(self.root / 'bin/swc.dm')}, result=7), 7)
        self.assertTrue(self.stages[0].command[0].endswith('swc.dm'))

    def test_application_run_needs_a_name(self):
        with self.assertRaisesRegex(ValueError, 'needs its name'):
            self.invoke(['apps', 'run'])

    def test_execution_stops_on_failure(self):
        marker = self.root / 'should-not-exist'
        stages = [tool.Stage('failure', [sys.executable, '-c', 'raise SystemExit(7)']),
                  tool.Stage('later', [sys.executable, '-c', f'open({str(marker)!r}, "w").close()'])]
        self.assertEqual(tool.execute(stages, os.environ.copy()), 7)
        self.assertFalse(marker.exists())


if __name__ == '__main__':
    unittest.main()
