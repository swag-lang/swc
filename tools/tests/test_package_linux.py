"""Check that Linux application archives keep their output and application files intact."""

from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[2]
PACKAGER = REPOSITORY / 'tools' / 'package-linux.py'


@unittest.skipUnless(sys.platform == 'linux', 'requires Linux executable modes and symlinks')
class LinuxPackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='swag-linux-package ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.build = self.root / 'build'
        self.build.mkdir()
        executable = self.build / 'swagscope'
        executable.write_bytes(b'\x7fELFfixture')
        executable.chmod(0o755)

    def package(self, output):
        return subprocess.run([sys.executable, str(PACKAGER), 'swagscope', '--build-dir', str(self.build),
                               '--output', str(output)], text=True, capture_output=True)

    def test_packages_the_application_and_desktop_assets(self):
        (self.build / 'libfixture.so.1').write_bytes(b'shared library')
        (self.build / 'libfixture.so').symlink_to('libfixture.so.1')
        output = self.root / 'application.tar.gz'

        result = self.package(output)

        self.assertEqual(result.returncode, 0, result.stderr)
        with tarfile.open(output, 'r:gz') as archive:
            program = archive.getmember('usr/local/libexec/swag/swagscope/swagscope')
            self.assertTrue(program.isfile())
            self.assertTrue(program.mode & 0o111)
            self.assertTrue(any(name.endswith('/swagscope.desktop') for name in archive.getnames()))
            self.assertTrue(any(name.endswith('/swagscope.png') for name in archive.getnames()))
            self.assertFalse(any('.so' in Path(name).name for name in archive.getnames()))

    def test_refuses_dangling_output_symlink_without_creating_its_target(self):
        target = self.root / 'target.tar.gz'
        output = self.root / 'dangling.tar.gz'
        output.symlink_to(target)

        result = self.package(output)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Refusing to replace existing archive', result.stderr)
        self.assertFalse(target.exists())

if __name__ == '__main__':
    unittest.main()
