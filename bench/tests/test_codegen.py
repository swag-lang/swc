import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("codegen", Path(__file__).resolve().parents[1] / "scripts" / "codegen.py")
codegen = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(codegen)


class CodegenArchiveTests(unittest.TestCase):
    def test_reuse_rejects_changed_sources_and_corrupted_artifacts(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "task.cpp"
            source.write_text("int main() { return 0; }\n")
            out = root / "archive"
            fingerprints = codegen.source_fingerprints(root, [source])
            codegen.export_entry(out, "gcc", "task", {"checksum": "42", "expected_checksum": "42"},
                                 "0000 <main>:\n  0: c3 ret\n", fingerprints)
            index = "gcc/task/manifest.json"
            (out / "snapshot.json").write_text(json.dumps({"schema": 1, "entries": [index]}))
            self.assertEqual(codegen.verify(out, root)[1], [])
            source.write_text("int main() { return 1; }\n")
            self.assertIn("source no longer matches", codegen.verify(out, root)[1][0])
            self.assertEqual(codegen.verify(out)[1], [])
            artifact = out / "gcc/task/assembly.txt.gz"
            artifact.write_bytes(artifact.read_bytes() + b"changed")
            self.assertIn("artifact changed", codegen.verify(out)[1][0])

    def test_failed_checksum_cannot_be_exported(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(ValueError, "checksum"):
                codegen.export_entry(temp, "gcc", "task", {"checksum": "1", "expected_checksum": "2"},
                                     "ret", {"task.cpp": "hash"})
            self.assertEqual(list(Path(temp).iterdir()), [])

    def test_reference_is_immutable_and_inventory_is_checked(self):
        with tempfile.TemporaryDirectory() as temp:
            metadata = {"checksum": "42", "expected_checksum": "42"}
            codegen.export_entry(temp, "gcc", "task", metadata, "ret", {"task.cpp": "hash"})
            with self.assertRaises(FileExistsError):
                codegen.export_entry(temp, "gcc", "task", metadata, "changed", {"task.cpp": "hash"})
            (Path(temp) / "snapshot.json").write_text(json.dumps({"schema": 1, "entries": []}))
            self.assertTrue(codegen.verify(temp)[1])

    def test_sealed_provenance_and_platform_patch_are_checked(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            metadata = {"checksum": "42", "expected_checksum": "42", "options": ["-O2"]}
            codegen.export_entry(root, "gcc", "task", metadata, "ret", {"task.cpp": "hash"})
            patch = root / "clock.patch"
            patch.write_text("clock only\n")
            codegen.finish_snapshot(root, {"purpose": "test"}, ["clock.patch"])
            self.assertEqual(codegen.verify(root)[1], [])
            with self.assertRaises(FileExistsError):
                codegen.finish_snapshot(root, {})
            with self.assertRaisesRegex(FileExistsError, "sealed"):
                codegen.export_entry(root, "clang", "task", metadata, "ret", {"task.cpp": "hash"})
            patch.write_text("changed\n")
            self.assertIn("supporting file changed", codegen.verify(root)[1][0])
            manifest = root / "gcc/task/manifest.json"
            record = json.loads(manifest.read_text())
            record["metadata"]["options"] = ["-O3"]
            manifest.write_text(json.dumps(record))
            self.assertTrue(any("manifest changed" in error for error in codegen.verify(root)[1]))


if __name__ == "__main__":
    unittest.main()
