"""Check that Linux application archives keep their output and shared-library links safe."""

from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[2]
PACKAGER = REPOSITORY / 'tools' / 'package-linux.py'


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

    def test_publishes_valid_sibling_library_symlinks(self):
        (self.build / 'libfixture.so.1').write_bytes(b'shared library')
        (self.build / 'libfixture.so.2').symlink_to('libfixture.so.1')
        (self.build / 'libfixture.so').symlink_to('libfixture.so.2')
        output = self.root / 'valid.tar.gz'

        result = self.package(output)

        self.assertEqual(result.returncode, 0, result.stderr)
        with tarfile.open(output, 'r:gz') as archive:
            link = archive.getmember('usr/local/libexec/swag/swagscope/libfixture.so')
            self.assertTrue(link.issym())
            self.assertEqual(link.linkname, 'libfixture.so.2')
            chained_link = archive.getmember('usr/local/libexec/swag/swagscope/libfixture.so.2')
            self.assertTrue(chained_link.issym())
            self.assertEqual(chained_link.linkname, 'libfixture.so.1')
            self.assertIn('usr/local/libexec/swag/swagscope/libfixture.so.1', archive.getnames())

    def test_rejects_dangling_nested_and_traversing_library_symlinks(self):
        (self.build / 'libfixture.so.1').write_bytes(b'shared library')
        (self.build / 'nested').mkdir()
        (self.build / 'nested' / 'libnested.so.1').write_bytes(b'nested library')

        for name, target in (('libtraversing.so', 'nested/../libfixture.so.1'),
                             ('libnested.so', 'nested/libnested.so.1'),
                             ('libmissing.so', 'libmissing.so.1')):
            with self.subTest(name=name):
                (self.build / name).symlink_to(target)
                output = self.root / f'{name}.tar.gz'
                result = self.package(output)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(output.exists())
                (self.build / name).unlink()

    def test_refuses_dangling_output_symlink_without_creating_its_target(self):
        target = self.root / 'target.tar.gz'
        output = self.root / 'dangling.tar.gz'
        output.symlink_to(target)

        result = self.package(output)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Refusing to replace existing archive', result.stderr)
        self.assertFalse(target.exists())

    def test_rejects_links_through_unpublished_siblings(self):
        (self.build / 'libfixture.so.1').write_bytes(b'shared library')
        for target in ('.hidden.so', 'intermediary'):
            with self.subTest(target=target):
                intermediary = self.build / target
                intermediary.symlink_to('libfixture.so.1')
                link = self.build / 'libfixture.so'
                link.symlink_to(target)
                output = self.root / f'{target}.tar.gz'

                try:
                    result = self.package(output)

                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(output.exists())
                finally:
                    link.unlink()
                    intermediary.unlink()


if __name__ == '__main__':
    unittest.main()
