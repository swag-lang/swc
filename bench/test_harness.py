"""Focused harness checks; run with python -B -m unittest discover -s bench."""
import contextlib
import copy
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import driver
import history
import mkpage
import toolchains as tc


class HarnessTests(unittest.TestCase):
    def test_installed_toolchains_are_found_without_path_or_overrides(self):
        with tempfile.TemporaryDirectory(prefix="bench programs ") as folder:
            installed = {"zig": "Zig/zig.exe", "ldc2": "LDC/bin/ldc2.exe", "odin": "Odin/odin.exe"}
            for relative in installed.values():
                exe = Path(folder, "Programs", relative)
                exe.parent.mkdir(parents=True, exist_ok=True)
                exe.touch()
            with (patch.dict(os.environ, {"LOCALAPPDATA": folder, "BENCH_ZIG": "", "BENCH_LDC2": "", "BENCH_ODIN": ""}),
                  patch.object(tc.shutil, "which", return_value=None)):
                tools = tc.discover()
            for key, relative in installed.items():
                self.assertEqual(tools[key], str(Path(folder, "Programs", relative)))
            self.assertTrue({"zig", "d-ldc", "odin"}.isdisjoint(tc.missing(tools)))

            path_exe = Path(folder, "path compiler.exe")
            path_exe.touch()
            override_exe = Path(folder, "override compiler.exe")
            override_exe.touch()
            with (patch.dict(os.environ, {"LOCALAPPDATA": folder, "BENCH_ZIG": "", "BENCH_LDC2": "", "BENCH_ODIN": ""}),
                  patch.object(tc.shutil, "which", return_value=str(path_exe))):
                tools = tc.discover()
                for key in installed:
                    self.assertEqual(tools[key], str(path_exe))
                with patch.dict(os.environ, dict.fromkeys(("BENCH_ZIG", "BENCH_LDC2", "BENCH_ODIN"), str(override_exe))):
                    tools = tc.discover()
                for key in installed:
                    self.assertEqual(tools[key], str(override_exe))

    def test_compiler_overrides_and_missing_toolchains(self):
        with tempfile.TemporaryDirectory(prefix="bench tools ") as folder:
            exe = Path(folder, "compiler.exe")
            exe.touch()
            overrides = dict.fromkeys(("BENCH_ZIG", "BENCH_LDC2", "BENCH_ODIN"), str(exe))
            with patch.dict(os.environ, overrides), patch.object(tc.shutil, "which", return_value=None):
                tools = tc.discover()
            for language, key in (("zig", "zig"), ("d-ldc", "ldc2"), ("odin", "odin")):
                self.assertEqual(tools[key], str(exe))
                self.assertNotIn(language, tc.missing(tools))
                tools[key] = None
                self.assertIn(language, tc.missing(tools))

    def test_new_ports_have_fresh_builds_and_launchers(self):
        with tempfile.TemporaryDirectory(prefix="bench output ") as folder:
            tools = tc.discover() | {"zig": "zig.exe", "ldc2": "ldc2.exe", "odin": "odin.exe"}
            with patch.object(tc, "OUT", folder), patch.object(tc, "resolve", return_value="cl.exe"):
                recipes = tc.make_recipes(tools, {}, "swc.exe")
                hello = tc.make_hello_builds(tools, {}, "swc.exe")
                launchers = tc.make_launchers(tools, "dotnet.exe")
                for language in ("zig", "d-ldc", "odin"):
                    self.assertIn(language, driver.AOT_ORDER)
                    self.assertIn(language, mkpage.META)
                    for task in ["hello"] + tc.TASKS:
                        rec = hello[language]() if task == "hello" else recipes[language](task, task + language)
                        self.assertEqual(launchers[language](rec["exe"]), [rec["exe"]])
                        source = [arg for arg in rec["cmd"] if arg.endswith((".zig", ".d", ".odin"))]
                        self.assertTrue(source)
                        self.assertTrue(all(Path(arg).is_file() for arg in source))
                        driver.prepare(rec)
                        stale = Path(rec["cwd"], "stale-cache")
                        stale.touch()
                        driver.prepare(rec)
                        self.assertFalse(stale.exists())

    def test_failed_process_cannot_supply_a_valid_checksum(self):
        result = {"exit": 1, "stdout": "CHECK=42 MS=1.0\n", "stderr": ""}
        with patch.object(driver.winproc, "run", return_value=result):
            got, _, _ = driver.run_once(["broken.exe"], {})
        self.assertIsNone(got)

    def test_port_errors_and_checksum_disagreements_block_publication(self):
        results = {"tasks": {"chacha": {
            "swag-release": {"run": {"check": 42}},
            "zig": {"run": {"check": 42}},
        }}}
        self.assertFalse(driver.campaign_errors(results))
        for failure in ({"build": {"error": "compiler exited"}},
                        {"run": {"check": 42, "error": "unstable checksum"}},
                        {"run": {"check": 43}}):
            results["tasks"]["chacha"]["zig"] = failure
            self.assertTrue(driver.campaign_errors(results))

    def test_new_controls_do_not_change_an_older_baseline(self):
        base = {"tasks": {"chacha": {
            name: {"run": {"ms": 10}, "build": {"wall_ms": 100}}
            for name in ("swag-release", "cpp-clang-cl", "cpp-msvc", "rust")
        }}}
        current = copy.deepcopy(base)
        for entry in current["tasks"]["chacha"].values():
            entry["run"]["ms"] *= 2
            entry["build"]["wall_ms"] *= 2
        current["tasks"]["chacha"]["zig"] = {"run": {"ms": 9999}, "build": {"wall_ms": 9999}}
        refs = {family: {"chacha": base} for family, _ in history.FAMILIES}
        panel = {family: {"chacha"} for family, _ in history.FAMILIES}
        context = history._context(current, refs, panel)
        for family in panel:
            self.assertAlmostEqual(context[family]["factor"], 2)
            self.assertEqual(context[family]["controls"], 3)

    def test_report_supports_old_and_extended_campaigns(self):
        original = mkpage.latest_campaign()
        with tempfile.TemporaryDirectory(prefix="bench report ") as folder:
            for extended in (False, True):
                result = copy.deepcopy(original)
                if extended:
                    # Synthetic measurements exercise the renderer, never the real history.
                    for entries in result["tasks"].values():
                        for language in ("zig", "d-ldc", "odin"):
                            entries[language] = copy.deepcopy(entries["rust"])
                    for language in ("zig", "d-ldc", "odin"):
                        result["hello_build"][language] = copy.deepcopy(result["hello_build"]["rust"])
                page = Path(folder, "bench.html")
                readme = Path(folder, "README.md")
                readme.write_text(mkpage.README_BEGIN + "\n" + mkpage.README_END)
                entries = history.build_entries([result])
                with (patch.object(mkpage, "latest_campaign", return_value=result),
                      patch.object(history, "rebuild", return_value=entries),
                      patch.object(mkpage, "OUTFILE", str(page)),
                      patch.object(mkpage, "REPO_README", str(readme)),
                      contextlib.redirect_stdout(io.StringIO())):
                    mkpage.main()
                self.assertNotIn("{{", page.read_text(encoding="utf-8"))
                if extended:
                    for label in ("Zig", "D (LDC)", "Odin"):
                        self.assertIn(label, page.read_text(encoding="utf-8"))
                        self.assertIn(label, readme.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
