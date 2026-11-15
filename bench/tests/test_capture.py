"""Static captures keep JIT bytes, addresses and checksum failures visible."""
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import capture


class CaptureTests(unittest.TestCase):
    def test_source_fingerprints_exclude_disposable_project_outputs(self):
        with tempfile.TemporaryDirectory() as temp:
            bench = Path(temp) / "bench"
            root = bench / "src/cs"
            names = ["src/sort.cs", "aot/sort/sort.csproj", "aot/sort/bin/Release/sort.dll",
                     "aot/sort/obj/Release/sort.AssemblyInfo.cs", "jit/sort/.output/api.swg"]
            for name in names:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(name)
            with mock.patch.object(capture.tc, "BENCH", str(bench)):
                actual = {path.relative_to(root).as_posix() for path in capture.sources("sort", "csharp-aot")}
            self.assertEqual(actual, {"src/sort.cs", "aot/sort/sort.csproj"})

    def test_resume_rejects_changed_sources_compilers_and_listings(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source, compiler = root / "task.cpp", root / "compiler.exe"
            source.write_bytes(b"source\n")
            compiler.write_bytes(b"compiler")
            metadata = {"checksum": "599499929", "expected_checksum": "599499929",
                        "command": [str(compiler)], "compiler_executable_sha256": capture.installs.sha256(compiler)}
            capture.codegen.export_entry(root / "out", "compiler", "sort", metadata, "ret",
                                         capture.codegen.source_fingerprints(root, [source]))
            manifest = root / "out/compiler/sort/manifest.json"
            with mock.patch.object(capture.tc, "worktree", return_value=str(root)):
                capture.verify_partial_entry(manifest)
                source.write_bytes(b"different source\n")
                with self.assertRaisesRegex(ValueError, "changed sources"):
                    capture.verify_partial_entry(manifest)
                source.write_bytes(b"source\n")
                compiler.write_bytes(b"different compiler")
                with self.assertRaisesRegex(ValueError, "different compiler"):
                    capture.verify_partial_entry(manifest)
                compiler.write_bytes(b"compiler")
                manifest.with_name("assembly.txt.gz").write_bytes(capture.gzip.compress(b"different code"))
                with self.assertRaisesRegex(ValueError, "artifact changed"):
                    capture.verify_partial_entry(manifest)

    def test_hotspot_bytes_keep_addresses_and_split_discontinuous_regions(self):
        output = """Compiled method (c2) Bench::main
  # {method} 'main' in 'Bench'
  0x0000000100001000: 4883 ec28 | 90c3 ; comment
  0x0000000100001006: 9090
  0x0000000100002000: c3
"""
        blocks = capture.hotspot_blocks(output)
        self.assertEqual([(address, raw) for address, raw, _ in blocks],
                         [(0x100001000, bytes.fromhex("4883ec2890c39090")), (0x100002000, b"\xc3")])
        self.assertIn("main", blocks[0][2])

    def test_checksum_needs_the_expected_value_and_a_marker(self):
        self.assertEqual(capture.check("CHECK=599499929 MS=1", "sort"), "599499929")
        for output in ("MS=1", "CHECK=0 MS=1", "CHECK=599499929 CHECK=0"):
            with self.subTest(output=output), self.assertRaisesRegex(ValueError, "checksum"):
                capture.check(output, "sort")

    def test_swag_symbol_addresses_use_the_linked_image_base(self):
        table = struct.pack("<IIIIIIIII", 0x42445753, 1, 1, 36, 0x1000, 7, 36, 41, 12)
        table += b"main\0task.swg\0"
        pe = bytearray(0x200)
        struct.pack_into("<I", pe, 0x3c, 0x80)
        pe[0x80:0x84] = b"PE\0\0"
        struct.pack_into("<H", pe, 0x80 + 6, 1)
        struct.pack_into("<H", pe, 0x80 + 20, 0xf0)
        struct.pack_into("<Q", pe, 0x80 + 48, 0x140000000)
        struct.pack_into("<8sIIII", pe, 0x80 + 24 + 0xf0, b".swagdbg", len(table), 0x2000, len(table), 0x200)
        with tempfile.TemporaryDirectory() as temp:
            binary = Path(temp) / "program.exe"
            binary.write_bytes(pe + table)
            self.assertIn("0000000140001000        7 main task.swg:12", capture.swag_symbols(binary))


if __name__ == "__main__":
    unittest.main()
