"""Protect complete Linux campaign coverage, fixture ordering and error reporting."""

from argparse import Namespace
from contextlib import redirect_stdout
import io
import json
import os
import signal
from pathlib import Path
import runpy
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
RUNNER = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'linux-tests.py'))


class LinuxCampaignTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'logs').mkdir()
        for workspace, modules in {'unittests/workspace': ('sandbox_consumer', 'runtime_context_dynamic_consumer', 'runtime_context_dynamic_dll'),
                                   'std': ('core',), 'apps': ('swagcapture',), 'examples': ('gui1',), 'reference': ('language',)}.items():
            for module in modules:
                path = self.root / workspace / 'modules' / module
                path.mkdir(parents=True)
                (path / 'module.swg').touch()

    def plan(self, suite='all', **options):
        args = Namespace(suite=suite, build_cfg='devmode', dev_full=False, execution=None,
                         file_filter=None, module=None, test_file=[], test_tag=[])
        vars(args).update(options)
        return RUNNER['plan'](args, self.root, Path('/release/swc'), Path('/dev/swc.dm'))

    def test_complete_campaign_contains_every_family(self):
        stages = self.plan()
        names = {stage.name for stage in stages}
        self.assertEqual(names, {'cpp', 'lexer', 'errors-lexer', 'parser', 'errors-parser',
                                'sema', 'errors-sema', 'jit', 'safety', 'sanity', 'native',
                                'errors-native-owning', 'errors-native-pointer',
                                'workspace-build-dynamic-library', 'workspace-sandbox_consumer',
                                'workspace-package-dynamic-library-dependency',
                                'workspace-runtime_context_dynamic_consumer', 'workspace-runtime_context_dynamic_dll',
                                'workspace-build-lifecycle-script-dependency', 'workspace-lifecycle-script',
                                'workspace-failed-init-script', 'workspace-failed-premain-script',
                                'workspace-failed-main-script', 'workspace-failed-drop-script',
                                'workspace-native-failed-drop', 'workspace-native-abandoned-test',
                                'workspace-jit-abandoned-test', 'workspace-jit-failed-init',
                                'workspace-jit-failed-premain', 'workspace-jit-failed-drop',
                                'workspace-import-script', 'workspace-import-png-script', 'std-core', 'apps-swagcapture',
                                'examples-gui1', 'reference-language'})
        cpp = stages[0].command
        self.assertEqual(cpp[0], '/dev/swc.dm')
        self.assertIn('--dev-full', cpp)
        self.assertNotIn('--build-cfg', cpp)
        app = next(stage.command for stage in stages if stage.name == 'apps-swagcapture')
        self.assertEqual(app[0], '/release/swc')
        self.assertIn('--run-arg=--compiler=/release/swc', app)
        self.assertIn('--no-test-jit', app)

    def test_dynamic_fixture_configuration_and_dependency(self):
        stages = self.plan('dynamic-library', build_cfg='release')
        self.assertEqual(len(stages), 3)
        self.assertEqual(stages[1].requires, [stages[0].name])
        self.assertEqual(stages[2].requires, [stages[1].name])
        self.assertTrue(any('/shared-library/release/x86_64/runtime_context_dynamic_dll.so' in arg for arg in stages[2].command))
        workspace = self.plan('workspace')
        sandbox = next(stage.command for stage in workspace if stage.name == 'workspace-sandbox_consumer')
        self.assertIn('--rebuild', sandbox)
        self.assertIn('--no-test-native', sandbox)
        self.assertTrue(workspace[-1].expected_output)

    def test_expected_sema_diagnostics_use_one_worker(self):
        normal, errors = self.plan('sema')
        self.assertEqual(normal.command[normal.command.index('--num-cores') + 1], '3')
        self.assertEqual(errors.command[errors.command.index('--num-cores') + 1], '1')
        self.assertIn('--sema-only', errors.command)

    def test_module_filters_keep_implementation(self):
        stage, = self.plan('std', module='core', test_file=['first.swg', 'second.swg'], test_tag=['integration.example'])
        self.assertEqual(stage.command.count('--test-file'), 2)
        self.assertIn('--test-tag', stage.command)
        self.assertNotIn('--file-filter', stage.command)
        self.assertGreater(stage.command.index('--test-jit'), stage.command.index('--no-test-jit'))
        self.assertNotIn('--no-test-native', stage.command)

    def run_stage(self, code, timeout=5, admission=None, **options):
        stage = RUNNER['Stage']('probe', [sys.executable, '-c', code], **options)
        with redirect_stdout(io.StringIO()):
            return RUNNER['run_stage'](stage, self.root, {}, timeout, admission or [sys.executable, '-c', 'pass'])

    @unittest.skipUnless(sys.platform == "linux", "Linux process-tree cleanup")
    def test_timeout_stops_detached_native_child(self):
        pid_file = self.root / 'child.pid'
        child = 'import time; time.sleep(60)'
        code = (f'import subprocess, sys, time; from pathlib import Path; '
                f'p = subprocess.Popen([sys.executable, "-c", {child!r}], start_new_session=True); '
                f'Path({str(pid_file)!r}).write_text(str(p.pid)); time.sleep(60)')
        try:
            result = self.run_stage(code, timeout=1)
            self.assertEqual(result['status'], 'timeout')
            self.assertEqual(result['returncode'], 124)
            pid = int(pid_file.read_text())
            status = Path(f'/proc/{pid}/status')
            deadline = time.monotonic() + 2
            while status.exists():
                state = next(line.split()[1] for line in status.read_text().splitlines() if line.startswith('State:'))
                if state in ('Z', 'X'):
                    break
                self.assertLess(time.monotonic(), deadline, 'detached child survived the timeout')
                time.sleep(0.01)
        finally:
            if pid_file.exists():
                try:
                    os.kill(int(pid_file.read_text()), signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def test_campaign_reuses_only_its_isolated_dependencies(self):
        stage, = self.plan('std')
        self.assertNotIn('--rebuild', stage.command)
        focused, = self.plan('std', module='core')
        self.assertIn('--rebuild', focused.command)

    @unittest.skipUnless(sys.platform == "linux", "Linux artifact-cache release")
    def test_waiting_admission_keeps_staged_files(self):
        fixture = self.root / 'fixture.bin'
        fixture.write_bytes(b'fixture contents')
        counter = self.root / 'admission-count'
        admission = (f'from pathlib import Path; p = Path({str(counter)!r}); '
                     f'count = int(p.read_text()) if p.exists() else 0; '
                     f'p.write_text(str(count + 1)); raise SystemExit(2 if count == 0 else 0)')
        code = f'from pathlib import Path; assert Path({str(counter)!r}).read_text() == "2"'
        with patch.object(RUNNER['time'], 'sleep'):
            result = self.run_stage(code, admission=[sys.executable, '-c', admission])
        self.assertEqual(result['status'], 'passed')
        self.assertEqual(fixture.read_bytes(), b'fixture contents')

    def test_nonzero_status_preserves_log_and_fails(self):
        result = self.run_stage('print("fixture failure"); raise SystemExit(7)')
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(result['returncode'], 7)
        self.assertIn('fixture failure', Path(result['log']).read_text())
        json.dumps(result)

    def test_script_success_needs_its_output_marker(self):
        self.assertEqual(self.run_stage('pass', expected_output='marker')['status'], 'missing-output')
        self.assertEqual(self.run_stage('print("marker")', expected_output='marker')['status'], 'passed')


if __name__ == '__main__':
    unittest.main()
