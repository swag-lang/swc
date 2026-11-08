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

    def invoke(self, arguments, windows=False, environment=None, result=0):
        def execute(stages, env, *, keep_going=False):
            self.stages = stages
            self.environment = env
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
        with redirect_stdout(io.StringIO()):
            self.assertEqual(self.invoke(['goldens', 'accept']), 0)
        self.assertEqual((folder / 'image.png').read_bytes(), b'reviewed image')
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

    def test_full_campaign_uses_same_suites_on_both_hosts(self):
        for windows in (False, True):
            self.assertEqual(self.invoke(['tests', 'dm'], windows=windows), 0)
            names = [stage.name for stage in self.stages]
            self.assertEqual(names[:13], ['cpp', 'lexer', 'errors-lexer', 'parser', 'errors-parser',
                                         'sema', 'errors-sema', 'jit', 'safety', 'sanity', 'native',
                                         'errors-native-owning', 'errors-native-pointer'])
            self.assertEqual(names[-4:], list(tool.WORKSPACES))
            self.assertTrue(self.stages[0].command[0].endswith('swc.dm.exe' if windows else 'swc.dm'))
        self.invoke(['tests'])
        self.assertNotIn('cpp', [stage.name for stage in self.stages])

    def test_cpp_does_not_receive_program_configuration(self):
        for cfg in (['-bc', 'release'], ['--build-cfg', 'devmode'], ['--build-cfg=release']):
            self.invoke(['unittests', 'dm', 'cpp', *cfg, '--num-cores', '1'])
            command = self.stages[0].command
            self.assertEqual(command[1:3], ['unittest', '--dev-full'])
            self.assertFalse(any(arg.startswith('--build-cfg') or arg == '-bc' for arg in command))
            self.assertEqual(command[-2:], ['--num-cores', '1'])

    def test_native_diagnostic_fixtures_require_native_execution(self):
        self.invoke(['unittests', 'native', '--no-test-native'])
        self.assertEqual([stage.name for stage in self.stages], ['native'])

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
            imported = next(stage for stage in self.stages if stage.name == 'workspace-import-script')
            self.assertEqual(imported.expected_output, 'SWAG_IMPORTED_CORE_WITHOUT_USING_RAN')
            png = next(stage for stage in self.stages if stage.name == 'workspace-import-png-script')
            self.assertEqual(png.expected_output, 'SWAG_IMPORTED_PNG_RAN')
            self.assertTrue(png.command[-1].endswith('import_png.swgs'))
            failed_drop = next(stage for stage in self.stages if stage.name == 'workspace-failed-drop-script')
            self.assertEqual(failed_drop.expected_returncode, 5)
            self.assertEqual(failed_drop.expected_output, 'SWAG_SECOND_DROP_RAN')
            failed_main = next(stage for stage in self.stages if stage.name == 'workspace-failed-main-script')
            self.assertEqual(failed_main.expected_returncode, 5)
            self.assertEqual(failed_main.expected_output, 'SWAG_DROP_AFTER_MAIN_RAN')

    def test_workers_and_explicit_runtime_override(self):
        for workers, expected in (('1', '1'), ('2', '2'), ('0', '3'), ('8', '3')):
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

    def test_expected_failure_still_needs_its_output_marker(self):
        command = [sys.executable, '-c', 'print("second drop ran"); raise SystemExit(5)']
        stage = tool.Stage('failed drop', command, expected_output='second drop ran', expected_returncode=5)
        with redirect_stdout(io.StringIO()):
            self.assertEqual(tool.execute([stage], os.environ.copy()), 0)
        stage.expected_output = 'missing marker'
        with redirect_stdout(io.StringIO()):
            self.assertNotEqual(tool.execute([stage], os.environ.copy()), 0)

    def test_script_needs_output_marker(self):
        with redirect_stdout(io.StringIO()):
            self.assertEqual(tool.execute([tool.Stage('script', [sys.executable, '-c', 'print("marker")'],
                                                     expected_output='marker')], os.environ.copy()), 0)

    def test_captured_compiler_output_works_with_narrow_console_encoding(self):
        bytes_out = io.BytesIO()
        narrow_console = io.TextIOWrapper(bytes_out, encoding='cp1252')
        command = [sys.executable, '-c', "import sys; sys.stdout.buffer.write('◆ marker'.encode('utf-8'))"]
        with redirect_stdout(narrow_console):
            self.assertEqual(tool.execute([tool.Stage('script', command, expected_output='marker')],
                                          os.environ.copy()), 0)
        self.assertEqual(bytes_out.getvalue(), '◆ marker'.encode('utf-8'))


if __name__ == '__main__':
    unittest.main()
