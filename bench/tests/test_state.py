"""Warm toolchain states and installation digests."""
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import installs
import toolchains as tc


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def tree(root):
    out = {}
    for folder, _, files in os.walk(root):
        for name in files:
            path = os.path.join(folder, name)
            with open(path, encoding="utf-8") as f:
                out[os.path.relpath(path, root)] = f.read()
    return out


class WarmStateTests(unittest.TestCase):
    def setUp(self):
        self.base = tempfile.mkdtemp(prefix="bench state ")
        self.addCleanup(shutil.rmtree, self.base, True)

    def test_restore_undoes_what_a_sample_changed(self):
        state = tc.WarmState(self.base)
        state.reset()
        write(os.path.join(state.live, "a", "kept.bin"), "kept")
        write(os.path.join(state.live, "rewritten.bin"), "original")
        state.capture()
        warm = tree(state.live)
        write(os.path.join(state.live, "a", "added.bin"), "new entry")
        write(os.path.join(state.live, "b", "c", "deep.bin"), "new folder")
        write(os.path.join(state.live, "rewritten.bin"), "changed by the sample")
        os.unlink(os.path.join(state.live, "a", "kept.bin"))
        state.restore()
        self.assertEqual(tree(state.live), warm)
        self.assertFalse(os.path.exists(os.path.join(state.live, "b")))

    def test_restore_without_a_snapshot_leaves_an_empty_folder(self):
        state = tc.WarmState(self.base)
        write(os.path.join(state.live, "x.bin"), "x")
        state.restore()
        self.assertEqual(os.listdir(state.live), [])


class InstallDigestTests(unittest.TestCase):
    def test_the_digest_ignores_what_campaigns_produce(self):
        root = tempfile.mkdtemp(prefix="bench install ")
        self.addCleanup(shutil.rmtree, root, True)
        write(os.path.join(root, "swc.exe"), "compiler")
        write(os.path.join(root, "std", "modules", "core", "a.swg"), "source")
        before = installs.tree_hash(root)
        write(os.path.join(root, "deps", "release", "kernel32.swg"), "published")
        write(os.path.join(root, "std", ".output", "win32", "x.obj"), "output")
        write(os.path.join(root, "reference.json"), "{}")
        self.assertEqual(installs.tree_hash(root), before)
        write(os.path.join(root, "std", "modules", "core", "a.swg"), "edited")
        self.assertNotEqual(installs.tree_hash(root), before)


if __name__ == "__main__":
    unittest.main()
