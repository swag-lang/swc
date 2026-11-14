"""Host boundary regressions: discovery reuse, executable names and process accounting."""
import os
import hashlib
import json
import tarfile
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import compiler_setup
import toolchains


class DiscoveryTests(unittest.TestCase):
    def test_missing_php_does_not_block_hello_planning(self):
        tools = dict.fromkeys(['node', 'luajit', 'lua', 'py', 'php', 'php_opcache', 'ruby'])
        self.assertNotIn('php-jit', toolchains.make_hello_runs(tools, {}, 3))

    def test_process_facade_forwards_private_accounting_helpers(self):
        import process
        with mock.patch.object(process, '_backend', mock.Mock()) as backend:
            backend._system_times.return_value = (10, 20)
            self.assertEqual(process._system_times(), (10, 20))

    @unittest.skipUnless(sys.platform == 'linux', 'Linux installer')
    def test_install_verifies_hash_and_persists_a_working_tool(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            payload = root / 'go'
            payload.write_text('#!/bin/sh\necho go version go1.test\n')
            archive = root / 'tool.tar.gz'
            with tarfile.open(archive, 'w:gz') as t:
                t.add(payload, arcname='bin/go')
            (root / 'compilers').mkdir()
            manifest = {'go': {'version': 'test', 'executable': 'bin/go', 'archives': [
                {'url': archive.as_uri(), 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}]}}
            (root / 'compilers/linux-x64.json').write_text(json.dumps(manifest))
            with mock.patch.object(compiler_setup, 'BENCH', root), \
                 mock.patch.dict(os.environ, {'BENCH_COMPILER_ROOT': str(root / 'cache')}):
                compiler_setup.install('go')
                installed = compiler_setup.configured()['go']
                self.assertEqual(compiler_setup.probe('go', installed), 'go version go1.test')
                with self.assertRaisesRegex(ValueError, 'already exists'):
                    compiler_setup.install('go')
                manifest['go']['version'] = 'corrupt'
                manifest['go']['archives'][0]['sha256'] = 'bad'
                (root / 'compilers/linux-x64.json').write_text(json.dumps(manifest))
                with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                    compiler_setup.install('go')
                self.assertFalse((root / 'cache/go-corrupt').exists())

    def test_preserves_driver_symlink_name(self):
        with mock.patch.object(compiler_setup, 'configured', return_value={'clang': '/tools/clang++'}), \
             mock.patch.object(compiler_setup, 'probe', side_effect=lambda k, p: 'version' if p == '/tools/clang++' else None), \
             mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(compiler_setup.discover_linux()['clang'], '/tools/clang++')

    def test_existing_install_does_not_download(self):
        with mock.patch.object(toolchains, 'discover', return_value=dict.fromkeys(compiler_setup.COMMANDS, '/tools/go')), \
             mock.patch.object(toolchains, 'missing', return_value=[]), \
             mock.patch.object(compiler_setup, 'probe', return_value='go version go1.test'), \
             mock.patch.object(compiler_setup, 'install') as install, \
             mock.patch.object(sys, 'argv', ['setup', 'install', 'go']), mock.patch('builtins.print'):
            compiler_setup.main()
            install.assert_not_called()

    def test_source_adapter_rejects_overlapping_trees(self):
        from linux_sources import prepare
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(ValueError, "separate"):
                prepare(temp, temp)

    def test_go_board_game_is_rejected(self):
        with mock.patch('subprocess.run', return_value=mock.Mock(returncode=0, stdout='Go game', stderr='')):
            self.assertIsNone(compiler_setup.probe('go', sys.executable))


@unittest.skipUnless(sys.platform == 'linux', 'Linux process backend')
class LinuxProcessTests(unittest.TestCase):
    def test_output_marker_exit_and_memory_contract(self):
        import linuxproc
        import process
        self.assertEqual(process.PIN_MASK, linuxproc.PIN_MASK)
        self.assertEqual(linuxproc.PIN_MASK.bit_count(), 1)
        r = linuxproc.run([sys.executable, '-c', 'print("READY", flush=True)'], first_stdout_match='READY', pin=True)
        self.assertEqual(r['exit'], 0)
        self.assertIn('READY', r['stdout'])
        self.assertIsNotNone(r['first_stdout_ms'])
        self.assertGreater(r['peak_working_set_bytes'], 0)
        self.assertIsNone(r['peak_job_bytes'])

    def test_timeout_kills_child(self):
        import linuxproc
        r = linuxproc.run([sys.executable, '-c', 'import time;time.sleep(30)'], timeout=.1)
        self.assertTrue(r['timed_out'])
        self.assertNotEqual(r['exit'], 0)
