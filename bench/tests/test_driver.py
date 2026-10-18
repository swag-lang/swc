import contextlib
import copy
import ctypes
import io
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import campaign
import driver
import history
import mkpage
import toolchains
import winproc


class CampaignTests(unittest.TestCase):
    def test_campaign_forwards_the_compiler_worker_cap(self):
        with (
            mock.patch.object(sys, "argv", ["campaign.py", "--quick", "--no-build", "--swc-cores", "6"]),
            mock.patch.dict(os.environ, {"BENCH_SWC": "unrelated-compiler.exe"}),
            mock.patch.object(campaign.os.path, "isfile", return_value=True),
            mock.patch.object(campaign, "run") as run,
        ):
            self.assertEqual(campaign.main(), 0)

        run.assert_called_once_with("driver.py", ["--swc", os.path.join(campaign.ROOT, "bin", "swc.exe"),
                                                "--swc-cores", "6", "--quick"])
    def test_quick_campaign_runs_normal_build_and_uses_published_compiler(self):
        with (
            mock.patch.object(sys, "argv", ["campaign.py", "--quick"]),
            mock.patch.object(campaign, "build", return_value=os.path.join(campaign.ROOT, "bin", "swc.exe")) as build,
            mock.patch.object(campaign, "run") as run,
            mock.patch.object(campaign, "warn_if_dirty") as warn_if_dirty,
        ):
            self.assertEqual(campaign.main(), 0)

        self.assertEqual(run.call_args_list, [mock.call("driver.py", ["--swc", os.path.join(campaign.ROOT, "bin", "swc.exe"), "--quick"])])
        build.assert_called_once_with()
        warn_if_dirty.assert_not_called()

    def test_build_phase_uses_the_published_compiler_and_rebuilds_the_report(self):
        with (
            mock.patch.object(sys, "argv", ["campaign.py", "--build"]),
            mock.patch.object(campaign, "build", return_value=os.path.join(campaign.ROOT, "bin", "swc.exe")) as build,
            mock.patch.object(campaign, "run") as run,
            mock.patch.object(campaign, "warn_if_dirty"),
        ):
            self.assertEqual(campaign.main(), 0)

        self.assertEqual(run.call_args_list,
                         [mock.call("driver.py", ["--swc", os.path.join(campaign.ROOT, "bin", "swc.exe"), "--build"]),
                          mock.call("mkpage.py", [])])
        build.assert_called_once_with()

    def test_driver_phase_flags_are_exclusive_and_select_their_family(self):
        build = driver.parse_args(["--build"])
        run = driver.parse_args(["--run"])
        self.assertEqual(driver.selected_phases(build), (True, False))
        self.assertEqual(driver.selected_phases(run), (False, True))
        with self.assertRaises(SystemExit):
            driver.parse_args(["--build", "--run"])


class CampaignMetadataTests(unittest.TestCase):
    def test_worker_cap_survives_raw_json_and_rebuilt_history(self):
        for arguments, expected in (([], 0), (["--swc-cores", "6"], 6)):
            with self.subTest(cores=expected), tempfile.TemporaryDirectory(prefix="swc bench metadata ") as folder:
                root = Path(folder)
                compiler = root / "swc.exe"
                compiler.write_bytes(b"compiler identity fixture")
                raw = root / "results" / "campaign.json"
                raw.parent.mkdir()
                args = driver.parse_args(arguments)
                with (
                    mock.patch.object(history.tc, "worktree", return_value=str(root)),
                    mock.patch.object(history, "RESULTS", str(raw.parent / "*.json")),
                    mock.patch.object(history, "HISTORY", str(root / "history.json")),
                ):
                    # Exercise the real CLI settings, metadata, JSON archive and history
                    # rebuild. Only repository/output locations are replaced; no compiler
                    # or measured process is needed to preserve the measurement contract.
                    result = {
                        "meta": history.describe(str(compiler), args.label, driver.campaign_settings(args)),
                        "calibration": {"start": 1.0, "drift_pct": 0.0},
                        "tasks": {"fixture": {
                            "swag-release": {"run": {"ms": 1.0}, "build": {"wall_ms": 1.0}},
                            "cpp-clang-cl": {"run": {"ms": 2.0}, "build": {"wall_ms": 2.0}},
                        }},
                    }
                    raw.write_text(json.dumps(result), encoding="utf-8")
                    archived = history.load_results()[0]
                    self.assertEqual(archived["meta"]["settings"]["swc_cores"], expected)
                    rebuilt = history.rebuild()
                    persisted = history.load()
                    for entry in (rebuilt[0], persisted[0]):
                        self.assertEqual(entry["meta"]["settings"]["swc_cores"], expected)
                        self.assertEqual(entry["meta"]["settings"], archived["meta"]["settings"])


class SampleSpreadTests(unittest.TestCase):
    def test_zero_duration_has_no_relative_spread(self):
        for samples in ([0.0], [0.0, 0.0], [1.0, 0.0, 2.0]):
            with self.subTest(samples=samples):
                self.assertIsNone(driver.spread_pct(samples))

    def test_positive_samples_keep_their_relative_spread(self):
        self.assertEqual(driver.spread_pct([2.0, 3.0, 4.0]), 100.0)
        self.assertEqual(driver.spread_pct([2.0]), 0.0)
        self.assertEqual(driver.spread_pct([]), 0.0)
        self.assertEqual(driver.spread_pct(None), 0.0)

    def test_small_positive_samples_are_not_rounded_to_zero(self):
        acc = {}
        for ms in (0.00001, 0.00002):
            driver.keep_run(acc, (42, ms), {"wall_ms": 1.0, "peak_job_bytes": 10})
        self.assertEqual(acc["samples"], [0.00001, 0.00002])
        self.assertEqual(acc["ms"], 0.00001)
        self.assertEqual(driver.spread_pct(acc["samples"]), 100.0)


class SampleBudgetTests(unittest.TestCase):
    def test_a_fast_runtime_gets_the_ceiling_and_a_slow_one_the_floor(self):
        self.assertEqual(driver.plan_reps(1), driver.RUN_MAX_REPS)
        self.assertEqual(driver.plan_reps(driver.RUN_SLOW_MS - 1), driver.RUN_MIN_REPS)

    def test_a_very_slow_runtime_keeps_its_pilot_sample_only(self):
        for tracked in (True, False):
            self.assertEqual(driver.plan_reps(driver.RUN_SLOW_MS, tracked), 1)
            self.assertEqual(driver.plan_reps(driver.RUN_SLOW_MS * 4, tracked), 1)
        self.assertEqual(driver.plan_builds(driver.BUILD_SLOW_MS, False), driver.BUILD_MIN_REPS)

    def test_even_a_delayed_build_pilot_gets_a_repeat(self):
        for tracked in (False, True):
            for duration in (400, 800, 2400, 2500, 30000):
                with self.subTest(duration=duration, tracked=tracked):
                    self.assertGreaterEqual(driver.plan_builds(duration, tracked), 2)

    def test_controls_get_fewer_samples_than_the_compiler_under_test(self):
        for duration in (1, 10, 100):
            self.assertLess(driver.plan_reps(duration, False), driver.plan_reps(duration, True))
            self.assertLess(driver.plan_builds(duration, False), driver.plan_builds(duration, True))
        self.assertEqual(driver.plan_reps(1, False), driver.CONTROL_RUN_MAX_REPS)

    def test_the_count_never_rises_with_the_duration(self):
        for tracked in (True, False):
            counts = [driver.plan_reps(d, tracked) for d in (1, 10, 100, 1000, 5000, 19000)]
            self.assertEqual(counts, sorted(counts, reverse=True))

    def test_a_missing_pilot_falls_back_to_the_floor(self):
        self.assertEqual(driver.plan_reps(None), driver.RUN_MIN_REPS)
        self.assertEqual(driver.plan_builds(None), driver.BUILD_MIN_REPS)


class ScheduleTests(unittest.TestCase):
    def test_every_planned_sample_gets_exactly_one_cycle(self):
        for reps in range(driver.RUN_MAX_REPS + 1):
            self.assertEqual(len(driver.schedule(reps)), reps, reps)

    def test_samples_are_spread_over_the_window_not_bunched(self):
        """Three samples must not all land in the first quarter of the sweep: the
        point of the budget is that every runtime covers the same minutes."""
        for reps in (2, 3, 6, 12):
            cycles = sorted(driver.schedule(reps))
            gaps = [b - a for a, b in zip(cycles, cycles[1:])]
            self.assertLessEqual(max(gaps) - min(gaps), 1, cycles)
            self.assertGreaterEqual(cycles[-1], driver.RUN_MAX_REPS - reps)


class BuildRepeatabilityTests(unittest.TestCase):
    def measure(self, samples, quick=False):
        calls = []
        pending = {name: iter(values) for name, values in samples.items()}
        with tempfile.TemporaryDirectory() as directory:
            exe = Path(directory, "artifact.exe")
            exe.write_bytes(b"artifact")
            jobs = {name: {"exe": str(exe), "name": name} for name in samples}

            def sample(job, env):
                name = job["name"]
                calls.append(name)
                wall = next(pending[name])
                if isinstance(wall, str):
                    return None, wall
                return {"wall_ms": wall, "peak_job_bytes": 10, "peak_working_set_bytes": 5}, None

            with (
                mock.patch.object(driver, "build_once", side_effect=sample),
                mock.patch.object(driver, "CONTROL_BUILD_BUDGET_MS", 0),
                mock.patch.object(driver, "BUILD_BUDGET_MS", 0),
                mock.patch.object(driver, "BUILD_MIN_REPS", 1 if quick else 2),
                mock.patch.object(driver, "BUILD_MAX_REPS", 1 if quick else 6),
            ):
                measured = driver.measure_builds(jobs, {})
        return measured, calls

    def test_only_a_noisy_measurement_is_retried_and_a_cold_pilot_is_preserved(self):
        measured, calls = self.measure({"stable": [100, 102], "cold": [800, 400, 405]})
        self.assertEqual(calls, ["stable", "cold", "cold", "stable", "cold"])
        self.assertEqual(measured["stable"]["samples"], [100, 102])
        self.assertEqual(measured["cold"]["samples"], [800, 400, 405])
        self.assertEqual(measured["cold"]["wall_ms"], 400)

    def test_a_single_low_outlier_needs_confirmation_instead_of_becoming_the_result(self):
        measured, _ = self.measure({"compiler": [100, 400, 405, 410, 415, 420]})
        result = {"tasks": {"task": {"compiler": {"build": measured["compiler"],
                                                    "run": {"ms": 12, "check": 42}}}}}
        driver.settle_build_measurements(result)
        acc = result["tasks"]["task"]["compiler"]["build"]
        self.assertEqual(acc["wall_ms"], 400)
        self.assertEqual(acc["raw_min_wall_ms"], 100)
        self.assertEqual(acc["unconfirmed_samples"], [100])
        self.assertEqual(acc["repeatability"]["status"], "verified")
        self.assertEqual(len(acc["samples"]), 3)
        self.assertEqual(result["tasks"]["task"]["compiler"]["run"]["ms"], 12)
        self.assertFalse(driver.campaign_errors(result))
        self.assertEqual(history.ratios_to_best(result["tasks"], ["task"], "build", "wall_ms"), {"compiler": 1})

    def test_slow_controls_get_two_samples_and_at_most_one_targeted_retry(self):
        for samples, expected in (([5000, 5100], "verified"),
                                  ([10000, 5000, 5100], "verified"),
                                  ([5000, 7000, 9000], "unresolved")):
            with self.subTest(samples=samples):
                measured, _ = self.measure({"slow": samples})
                driver.settle_build_measurements({"tasks": {}, "hello_build": measured})
                self.assertEqual(measured["slow"]["repeatability"]["status"], expected)
                self.assertEqual(measured["slow"]["samples"], samples)

    def test_quick_keeps_one_sample_and_a_compiler_error_is_not_retried(self):
        measured, calls = self.measure({"compiler": [500]}, quick=True)
        self.assertEqual(calls, ["compiler"])
        self.assertEqual(measured["compiler"]["wall_ms"], 500)
        measured, calls = self.measure({"broken": ["exit=3"]})
        self.assertEqual(calls, ["broken"])
        self.assertEqual(measured["broken"]["error"], "exit=3")

    def test_budget_is_recomputed_after_a_delayed_pilot(self):
        acc = {"wall_ms": 5000, "samples": [5000]}
        self.assertTrue(driver.needs_build_sample(acc, tracked=True))
        acc.update(wall_ms=100, samples=[5000, 100, 101])
        self.assertTrue(driver.needs_build_sample(acc, tracked=True))


class CampaignPublicationTests(unittest.TestCase):
    def test_report_renders_unresolved_compilations_without_losing_execution(self):
        result = copy.deepcopy(mkpage.latest_campaign("build"))
        task = next(iter(result["tasks"]))
        build = result["tasks"][task]["swag-release"]["build"]
        build["unverified_wall_ms"] = build.pop("wall_ms")
        build["repeatability"] = {"status": "unresolved"}
        hello = result["hello_build"]["swag-release"]
        hello["unverified_wall_ms"] = hello.pop("wall_ms")
        with tempfile.TemporaryDirectory() as directory:
            page = Path(directory, "bench.html")
            readme = Path(directory, "README.md")
            readme.write_text(mkpage.README_BEGIN + "\n" + mkpage.README_END)
            with (
                mock.patch.object(mkpage, "latest_campaign", return_value=result),
                mock.patch.object(history, "load_results", return_value=[result]),
                mock.patch.object(history, "rebuild", return_value=history.build_entries([result])),
                mock.patch.object(mkpage, "OUTFILE", str(page)),
                mock.patch.object(mkpage, "REPO_README", str(readme)),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                mkpage.main()
            rendered = page.read_text(encoding="utf-8")
            self.assertNotIn("{{", rendered)
            self.assertIn('title="No measurement: swag release (native)"', rendered)
            self.assertIn("Swag release", readme.read_text(encoding="utf-8"))

    def test_historical_split_does_not_discard_a_quiet_campaign(self):
        for end_probe, rejected in ((100, False), (200, True)):
            with self.subTest(end_probe=end_probe), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                exe = root / "compiler.exe"
                exe.write_bytes(b"fixture")
                args = driver.parse_args(["--build", "--warmup", "0", "--swc-cores", "6"])
                samples = iter([100] * 18 + [end_probe] * 12)
                metadata = {"stamp": "fixture", "date": "2026-10-18T17:18:40+00:00"}
                build = {"wall_ms": 500, "peak_bytes": 10, "samples": [500, 505]}
                controls = {"reference": "yesterday", "controls": {"cpp": 1.5}, "spread_pct": 62.8}
                appended = [{"meta": metadata, "context": {"build_factor": 1, "build_controls": 11}}]
                with contextlib.ExitStack() as stack:
                    patches = [
                        mock.patch.object(driver, "parse_args", return_value=args),
                        mock.patch.object(driver.tc, "TASKS", ["fixture"]),
                        mock.patch.object(driver.tc, "BENCH", str(root)),
                        mock.patch.object(driver.tc, "OUT", str(root / "out")),
                        mock.patch.object(driver.tc, "discover", return_value={}),
                        mock.patch.object(driver.tc, "missing", return_value=[]),
                        mock.patch.object(driver.tc, "swc_path", return_value=str(exe)),
                        mock.patch.object(driver.tc, "build_env", return_value={}),
                        mock.patch.object(driver.tc, "make_recipes", return_value={
                            "cpp-clang-cl": lambda *args: {"exe": str(exe)}}),
                        mock.patch.object(driver.tc, "make_hello_builds", return_value={}),
                        mock.patch.object(driver.tc, "make_compiler_workloads", return_value={}),
                        mock.patch.object(driver, "AOT_ORDER", ["cpp-clang-cl"]),
                        mock.patch.object(driver, "JIT_ORDER", []),
                        mock.patch.object(driver, "prepare_swag_dependencies", return_value=None),
                        mock.patch.object(driver, "wait_for_quiet", return_value=2),
                        mock.patch.object(driver, "build_once", return_value=({}, None)),
                        mock.patch.object(driver, "measure_builds", side_effect=[{}, {}, {"cpp-clang-cl": build}]),
                        mock.patch.object(driver, "run_once", side_effect=lambda *args: ((42, next(samples)), None, {})),
                        mock.patch.object(driver.history, "describe", return_value=metadata),
                        mock.patch.object(driver.history, "load_results", return_value=[]),
                        mock.patch.object(driver.history, "build_control_spread", return_value=controls),
                    ]
                    for patch in patches:
                        stack.enter_context(patch)
                    append = stack.enter_context(mock.patch.object(driver.history, "append", return_value=appended))
                    stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
                    self.assertEqual(driver.main(), 0)
                archive = root / "results" / ("rejected" if rejected else "") / "fixture.json"
                self.assertTrue(archive.exists())
                raw = json.loads(archive.read_text())
                self.assertEqual(raw["calibration"]["build_controls"]["spread_pct"], 62.8)
                self.assertEqual(raw["tasks"]["fixture"]["cpp-clang-cl"]["build"]["repeatability"]["status"], "verified")
                self.assertEqual(append.call_count, 0 if rejected else 1)


class TimerFaultTests(unittest.TestCase):
    @staticmethod
    def keep(samples):
        acc = {}
        for ms in samples:
            driver.keep_run(acc, (7, ms), {"wall_ms": 30.0, "peak_job_bytes": 10})
        return acc

    def test_a_clock_that_reads_short_does_not_become_the_result(self):
        """Go's raytrace of 2026-10-17: one 0.51 ms reading among 10.5-13.2 ms runs."""
        acc = self.keep([13.24, 10.53, 11.59, 11.73, 10.66, 0.51])
        self.assertEqual(acc["ms"], 10.53)
        self.assertEqual(acc["timer_faults"], [0.51])
        self.assertEqual(len(acc["samples"]), 6)

    def test_a_warm_jit_run_against_cold_ones_is_honest(self):
        acc = self.keep([75.58, 70.13, 40.0])
        self.assertEqual(acc["ms"], 40.0)
        self.assertNotIn("timer_faults", acc)

    def test_two_samples_are_never_judged(self):
        acc = self.keep([20.0, 1.0])
        self.assertEqual(acc["ms"], 1.0)
        self.assertNotIn("timer_faults", acc)

    def test_an_archived_campaign_is_settled_when_read(self):
        archived = {"tasks": {"leven": {"go": {"run": {
            "ms": 8.08, "samples": [23.56, 30.95, 20.92, 8.08, 16.31, 16.77]}}}}}
        run = history.settle_campaign(archived)["tasks"]["leven"]["go"]["run"]
        self.assertEqual(run["ms"], 16.31)
        self.assertEqual(run["timer_faults"], [8.08])


class EditLoopTests(unittest.TestCase):
    def test_build_records_every_sample_and_keeps_its_minimum(self):
        with tempfile.TemporaryDirectory() as directory:
            exe = Path(directory) / "bench.exe"
            exe.write_bytes(b"exe")
            acc = {}
            for wall in (160.0, 140.0, 155.0):
                driver.keep_build(acc, {"wall_ms": wall, "peak_job_bytes": 10,
                                        "peak_working_set_bytes": 5}, {"exe": str(exe)})
        self.assertEqual(acc["wall_ms"], 140.0)
        self.assertEqual(acc["samples"], [160.0, 140.0, 155.0])

    def test_worker_cap_reaches_every_swag_recipe(self):
        tools = {"clang_cl": "clang-cl", "node": "node", "luajit": "luajit",
                 "lua": "lua", "py": "py", "rustc": "rustc", "swiftc": "swiftc",
                 "dotnet": "dotnet", "php": "php", "php_opcache": "opcache.dll", "ruby": "ruby"}
        with (
            mock.patch.object(toolchains, "resolve", return_value="cl"),
            mock.patch.object(toolchains, "swag_dependency_api_files", return_value=["kernel32.swg"]),
        ):
            commands = [
                toolchains.make_recipes(tools, {}, "swc.exe", 6)["swag-release"]("csvagg", "test")["cmd"],
                toolchains.make_runtimes(tools, "swc.exe", 6)["swc-jit-release"]("csvagg"),
                toolchains.make_hello_builds(tools, {}, "swc.exe", 6)["swag-release"]()["cmd"],
                toolchains.make_hello_runs(tools, "swc.exe", 6)["swc-jit-release"],
            ]
        for command in commands:
            self.assertEqual(command[:4], ["swc.exe", command[1], "--num-cores", "6"])

    def test_format_mirror_preserves_configuration_and_baseline_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "repo"
            output = Path(directory) / "out"
            expected = {
                ".swc-format": b"end-of-line-style = crlf\r\n",
                "bin/unittests/.swc-format": b"indent-style = preserve\n",
                "bin/unittests/lexer/.swc-format": b"spacing-style = preserve\n",
                "bin/unittests/lexer/input.swg": b"let x=1\n",
                "tools/format.swgs": b"#run {}\n",
                "bench/src/hello/hello.swg": b"func main() {}\n",
                "bin/help/tools/brand.swgs": b"#run {}\n",
            }
            excluded = {
                "bin/unittests/.output/generated.swg": b"generated",
                "bin/unittests/.cache/generated.swg": b"generated",
                "bin/unittests/fixture.txt": b"fixture",
                "bench/current/module.swg": b"#run {}\n",
                "bench/current/src/input.swg": b"func main() {}\n",
                "bench/results/archived.swg": b"historical",
            }
            for name, content in (expected | excluded).items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
            with (
                mock.patch.object(toolchains, "worktree", return_value=str(root)),
                mock.patch.object(toolchains, "OUT", str(output)),
            ):
                toolchains.make_compiler_workloads("swc.exe")["format_tree"]["prepare"](None)
            mirrored = output / "format"
            actual = {path.relative_to(mirrored).as_posix(): path.read_bytes()
                      for path in mirrored.rglob("*") if path.is_file()}
            self.assertEqual(actual, expected)

    def test_every_workload_is_defined_and_uses_the_compiler_default(self):
        workloads = toolchains.make_compiler_workloads("swc.exe")
        self.assertEqual(list(workloads), toolchains.COMPILER_WORKLOADS)
        for workload in workloads.values():
            self.assertEqual(workload["cmd"][0], "swc.exe")
            self.assertNotIn("--num-cores", workload["cmd"])
            self.assertTrue(os.path.isabs(workload["cwd"]))

    def test_compiler_workloads_accept_an_explicit_worker_cap(self):
        workloads = toolchains.make_compiler_workloads("swc.exe", 6)
        for workload in workloads.values():
            index = workload["cmd"].index("--num-cores")
            self.assertEqual(workload["cmd"][index + 1], "6")

    def test_workload_preparation_obeys_machine_admission(self):
        admit = mock.Mock()
        workloads = toolchains.make_compiler_workloads("swc.exe", 6, admit)
        with mock.patch.object(toolchains.subprocess, "run", return_value=mock.Mock(returncode=0)):
            workloads["core_noop"]["prepare"]({})
        admit.assert_called_once_with()

    def test_only_the_cold_rebuild_needs_no_preparation(self):
        workloads = toolchains.make_compiler_workloads("swc.exe")
        self.assertIsNone(workloads["core_rebuild"]["prepare"])
        for name in toolchains.COMPILER_WORKLOADS[1:]:
            self.assertIsNotNone(workloads[name]["prepare"], name)

    def test_a_failing_workload_reports_and_keeps_nothing(self):
        failed = {"exit": 3, "wall_ms": 1.0, "cpu_ms": 1.0, "peak_job_bytes": 1,
                  "stdout": "", "stderr": "boom"}
        with mock.patch.object(winproc, "run", return_value=failed):
            r, err = driver.workload_once({"cmd": ["x"], "cwd": ".", "prepare": None}, {})
        self.assertIsNone(r)
        self.assertIn("exit=3", err)
        self.assertIn("boom", err)

    def test_compiler_diagnostic_survives_trailing_progress(self):
        diagnostic = "error: cannot write through a const buffer\nsource.swg:93:17\n"
        failed = {"exit": 5, "stdout": "building modules\n",
                  "stderr": diagnostic + "module complete\n" * 200}
        recipe = {"cmd": ["compiler"], "cwd": ".", "prepare": None, "clean": []}
        with mock.patch.object(winproc, "run", return_value=failed):
            for execute in (driver.build_once, driver.workload_once):
                with self.subTest(command=execute.__name__):
                    result, error = execute(recipe, {})
                    self.assertIsNone(result)
                    self.assertIn(diagnostic, error)
            result, error, _ = driver.run_once(["compiler", "sema"], {})
            self.assertIsNone(result)
            self.assertIn(diagnostic, error)

    def test_a_workload_keeps_its_minimum_and_every_sample(self):
        acc = {}
        for wall in (30.0, 20.0, 25.0):
            driver.keep_workload(acc, {"wall_ms": wall, "cpu_ms": wall * 2,
                                       "peak_job_bytes": int(wall), "peak_working_set_bytes": int(wall * 3)})
        self.assertEqual(acc["wall_ms"], 20.0)
        self.assertEqual(acc["cpu_ms"], 40.0)
        self.assertEqual(acc["peak_bytes"], 30)
        self.assertEqual(acc["peak_working_set_bytes"], 90)
        self.assertEqual(acc["samples"], [30.0, 20.0, 25.0])


class MemoryTests(unittest.TestCase):
    def test_a_terminated_process_keeps_its_resident_peak(self):
        result = winproc.run([sys.executable, "-c", "data = bytearray(64 * 1024 * 1024)"])
        self.assertEqual(result["exit"], 0)
        self.assertGreaterEqual(result["peak_working_set_bytes"], 64 * 1024 * 1024)
        self.assertGreater(result["peak_job_bytes"], 0)

    def test_first_stdout_is_timestamped_before_process_exit(self):
        result = winproc.run([sys.executable, "-c",
                              "import sys, time; print('ready', flush=True); time.sleep(0.2)"],
                             first_stdout_match="ready")
        self.assertEqual(result["exit"], 0)
        self.assertEqual(result["stdout"].splitlines(), ["ready"])
        self.assertIsNotNone(result["first_stdout_ms"])
        self.assertLess(result["first_stdout_ms"], result["wall_ms"] - 100)


class ProcessLifetimeTests(unittest.TestCase):
    def test_driver_death_during_process_creation_reaps_the_suspended_child(self):
        # Stop the driver immediately after CreateProcessW succeeds, before it can
        # execute a separate AssignProcessToJobObject or resume the child.
        script = """
import ctypes
import pathlib
import sys
import time
import winproc

create_process = winproc.k32.CreateProcessW
def pause_after_creation(*args):
    ok = create_process(*args)
    if ok:
        info = ctypes.cast(args[-1], ctypes.POINTER(winproc.PROCESS_INFORMATION)).contents
        marker = pathlib.Path(sys.argv[1])
        pending = marker.with_suffix('.pending')
        pending.write_text(str(info.dwProcessId), encoding='ascii')
        pending.replace(marker)
        time.sleep(30)
    return ok

winproc.k32.CreateProcessW = pause_after_creation
winproc.run([sys.executable, '-c', 'pass'])
"""
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        k32.OpenProcess.argtypes = [ctypes.wintypes.DWORD, ctypes.wintypes.BOOL, ctypes.wintypes.DWORD]
        k32.OpenProcess.restype = ctypes.wintypes.HANDLE
        k32.WaitForSingleObject.argtypes = [ctypes.wintypes.HANDLE, ctypes.wintypes.DWORD]
        k32.TerminateProcess.argtypes = [ctypes.wintypes.HANDLE, ctypes.wintypes.UINT]
        k32.CloseHandle.argtypes = [ctypes.wintypes.HANDLE]
        with tempfile.TemporaryDirectory(prefix="swc bench process lifetime ") as folder:
            marker = Path(folder, "child.pid")
            child = None
            driver_process = subprocess.Popen([sys.executable, "-B", "-c", script, str(marker)],
                                              cwd=Path(winproc.__file__).parent,
                                              stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 10
                while not marker.exists() and driver_process.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(marker.exists(), "the driver did not create its suspended child")
                child = k32.OpenProcess(0x00100001, False, int(marker.read_text(encoding="ascii")))
                self.assertTrue(child, ctypes.WinError(ctypes.get_last_error()))
                driver_process.kill()
                driver_process.wait(timeout=5)
                self.assertEqual(k32.WaitForSingleObject(child, 2000), 0,
                                 "the driver left its suspended child alive")
            finally:
                if driver_process.poll() is None:
                    driver_process.kill()
                if child:
                    k32.TerminateProcess(child, 1)
                    k32.CloseHandle(child)
                driver_process.communicate(timeout=5)


class PinTests(unittest.TestCase):
    def test_the_mask_is_one_logical_processor_per_performance_core(self):
        cpus = winproc.topology()
        if not cpus:
            self.skipTest("no CPU set information on this machine")
        best = max(efficiency for _, _, efficiency in cpus)
        cores = {core for _, core, efficiency in cpus if efficiency == best}
        self.assertEqual(bin(winproc.PIN_MASK).count("1"), len(cores))
        for logical, _, efficiency in cpus:
            if winproc.PIN_MASK & (1 << logical):
                self.assertEqual(efficiency, best)


if __name__ == "__main__":
    unittest.main()
