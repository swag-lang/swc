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
    def test_swag_benchmarks_import_official_native_bindings(self):
        dependencies = ["kernel32.swg"]
        with (patch.object(tc, "resolve", return_value="cl.exe"),
              patch.object(tc, "swag_dependency_api_files", return_value=dependencies)):
            recipes = tc.make_recipes({"clang_cl": "clang-cl.exe"}, {}, "swc.exe")
            runtimes = tc.make_runtimes({}, "swc.exe")
            commands = [recipes[name]("sha256", "probe")["cmd"]
                        for name in ("swag-release", "swag-fast-debug")]
            commands += [runtimes[name]("sha256")
                         for name in ("swc-jit-release", "swc-jit-fast-debug")]
        for command in commands:
            self.assertNotIn("--module-file", command)
            self.assertEqual([command[index + 1] for index, arg in enumerate(command)
                              if arg == "--import-api-file"], dependencies)

    def test_swag_dependencies_are_prepared_before_timed_samples(self):
        completed = {"exit": 0, "stdout": "", "stderr": "", "wall_ms": 12.5}
        with (patch.object(driver.tc, "worktree", return_value="checkout"),
              patch.object(driver.tc, "swag_dependency_api_files",
                           side_effect=[["release-kernel32.swg"], ["devmode-kernel32.swg"]]),
              patch.object(driver.winproc, "run", return_value=completed) as run,
              contextlib.redirect_stdout(io.StringIO())):
            error = driver.prepare_swag_dependencies("swc.exe", {"BENCH": "1"})

        self.assertIsNone(error)
        self.assertEqual(run.call_count, 2)
        for call, cfg in zip(run.call_args_list, ("release", "devmode")):
            self.assertEqual(call.args[0], [
                "swc.exe", "build", "--workspace", os.path.join("checkout", "bin", "std"),
                "--workspace-module", "win32", "--build-cfg", cfg])
            self.assertEqual(call.kwargs, {"cwd": "checkout", "env": {"BENCH": "1"}})

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
                for language in ("zig", "d-ldc", "odin", "go", "java-hotspot"):
                    self.assertIn(language, driver.AOT_ORDER)
                    self.assertIn(language, mkpage.META)
                    for task in ["hello"] + tc.TASKS:
                        rec = hello[language]() if task == "hello" else recipes[language](task, task + language)
                        command = launchers[language](rec["exe"])
                        if language == "java-hotspot":
                            self.assertEqual(command, [tools["java"], "-cp", rec["cwd"], "Bench"])
                        else:
                            self.assertEqual(command, [rec["exe"]])
                        source = [arg for arg in rec["cmd"] if arg.endswith((".zig", ".d", ".odin", ".go", ".java"))]
                        self.assertTrue(source)
                        self.assertTrue(all(Path(arg).is_file() for arg in source))
                        driver.prepare(rec)
                        stale = Path(rec["cwd"], "stale-cache")
                        stale.touch()
                        driver.prepare(rec)
                        self.assertFalse(stale.exists())

    def test_managed_and_script_discovery_needs_the_complete_runtime(self):
        with tempfile.TemporaryDirectory(prefix="bench runtimes ") as folder:
            installed = {"go": "Go/bin/go.exe", "javac": "Java/bin/javac.exe",
                         "java": "Java/bin/java.exe", "php": "PHP/php.exe",
                         "php_opcache": "PHP/ext/php_opcache.dll", "ruby": "Ruby/bin/ruby.exe"}
            overrides = ["BENCH_GO", "BENCH_JAVAC", "BENCH_JAVA", "BENCH_PHP",
                         "BENCH_PHP_OPCACHE", "BENCH_RUBY"]
            for relative in installed.values():
                path = Path(folder, "Programs", relative)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            with (patch.dict(os.environ, {"LOCALAPPDATA": folder, "JAVA_HOME": ""} | dict.fromkeys(overrides, "")),
                  patch.object(tc.shutil, "which", return_value=None)):
                tools = tc.discover()
            for key, relative in installed.items():
                self.assertEqual(Path(tools[key]), Path(folder, "Programs", relative))
            self.assertTrue({"go", "java-hotspot", "php", "php-jit", "ruby"}.isdisjoint(tc.missing(tools)))
            Path(tools["java"]).unlink()
            Path(tools["php_opcache"]).unlink()
            self.assertIn("java-hotspot", tc.missing(tools))
            self.assertIn("php-jit", tc.missing(tools))
            self.assertNotIn("php", tc.missing(tools))

    def test_script_ports_and_hello_use_the_same_launch_options(self):
        tools = tc.discover()
        runtimes = tc.make_runtimes(tools, "swc.exe")
        hello = tc.make_hello_runs(tools, "swc.exe")
        for language, suffix in (("php", ".php"), ("php-jit", ".php"), ("ruby", ".rb")):
            self.assertIn(language, driver.JIT_ORDER)
            self.assertIn(language, mkpage.META)
            for task in tc.TASKS:
                command = runtimes[language](task)
                source = next(arg for arg in command if arg.endswith(suffix) and not arg.startswith("auto_prepend_file="))
                self.assertTrue(Path(source).is_file())
                self.assertEqual(command[:command.index(source)], hello[language][:hello[language].index(
                    next(arg for arg in hello[language] if arg.endswith(suffix) and not arg.startswith("auto_prepend_file=")))])
                if language == "php-jit":
                    self.assertEqual(command[-1], "--require-jit")

    def test_java_artifact_size_includes_nested_classes(self):
        with tempfile.TemporaryDirectory() as folder:
            main = Path(folder, "Bench.class")
            main.write_bytes(b"main")
            Path(folder, "Bench$Node.class").write_bytes(b"node")
            Path(folder, "unrelated.log").write_bytes(b"not bytecode")
            result = {"wall_ms": 10, "peak_job_bytes": 20, "peak_working_set_bytes": 15}
            acc = {}
            driver.keep_build(acc, result, {"exe": str(main), "artifact_glob": os.path.join(folder, "*.class")})
            self.assertEqual(acc["exe_bytes"], 8)

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

    def test_missing_hello_output_blocks_publication(self):
        results = {"tasks": {}, "hello_run": {"ruby": {"error": "process did not print its hello output"}}}
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
                        for language in ("zig", "d-ldc", "odin", "go", "java-hotspot", "php", "php-jit", "ruby"):
                            entries[language] = copy.deepcopy(entries["rust"])
                    for language in ("zig", "d-ldc", "odin", "go", "java-hotspot"):
                        result["hello_build"][language] = copy.deepcopy(result["hello_build"]["rust"])
                    result["allocator"] = {workload: {name: {"ns": ns, "samples": [ns], "peak_bytes": 8 << 20,
                                                             "peak_working_set_bytes": 6 << 20}
                                                      for name, ns in (("swag", 30.0), ("mimalloc", 10.0),
                                                                       ("crt", 60.0))}
                                           for workload in ("pair", "churn:4")}
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
                rendered = page.read_text(encoding="utf-8")
                self.assertLess(rendered.index('aria-label="Language legend"'), rendered.index('<section id="execution">'))
                self.assertIn('scope="col"', rendered)
                self.assertIn('title="C++ / clang-cl (native)"', rendered)
                self.assertIn("build speedup vs fastest rival", rendered)
                self.assertIn("fastest non-Swag build time / swc build time", readme.read_text(encoding="utf-8"))
                self.assertNotIn("build MSVC / swc", rendered)
                self.assertIn('<section id="allocateur">', rendered)
                if extended:
                    self.assertIn("swag / mimalloc", rendered)
                    self.assertIn("temps / mimalloc", rendered)
                elif not original.get("allocator"):
                    self.assertIn("Aucune mesure de l&rsquo;allocateur", rendered)
                if extended:
                    # The page names D alone; the README table keeps its compiler.
                    for shown, tabled in (("Zig", "Zig"), ('class="rl">D <span', "D (LDC)"),
                                          ("Odin", "Odin"), ("Go", "Go"), ("Java HotSpot", "Java HotSpot"),
                                          ("PHP", "PHP"), ("Ruby", "Ruby")):
                        self.assertIn(shown, page.read_text(encoding="utf-8"))
                        self.assertIn(tabled, readme.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
