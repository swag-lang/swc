import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import campaign
import driver
import toolchains
import winproc


class CampaignTests(unittest.TestCase):
    def test_quick_campaign_does_not_rebuild_the_published_report(self):
        with (
            mock.patch.object(sys, "argv", ["campaign.py", "--quick"]),
            mock.patch.object(campaign, "build"),
            mock.patch.object(campaign, "run") as run,
            mock.patch.object(campaign, "warn_if_dirty") as warn_if_dirty,
        ):
            self.assertEqual(campaign.main(), 0)

        self.assertEqual(run.call_args_list, [mock.call("driver.py", ["--quick"])])
        warn_if_dirty.assert_not_called()

    def test_build_campaign_forwards_the_phase_and_rebuilds_the_report(self):
        with (
            mock.patch.object(sys, "argv", ["campaign.py", "--build"]),
            mock.patch.object(campaign, "build"),
            mock.patch.object(campaign, "run") as run,
            mock.patch.object(campaign, "warn_if_dirty"),
        ):
            self.assertEqual(campaign.main(), 0)

        self.assertEqual(run.call_args_list,
                         [mock.call("driver.py", ["--build"]),
                          mock.call("mkpage.py", [])])

    def test_driver_phase_flags_are_exclusive_and_select_their_family(self):
        build = driver.parse_args(["--build"])
        run = driver.parse_args(["--run"])
        self.assertEqual(driver.selected_phases(build), (True, False))
        self.assertEqual(driver.selected_phases(run), (False, True))
        with self.assertRaises(SystemExit):
            driver.parse_args(["--build", "--run"])


class SampleBudgetTests(unittest.TestCase):
    def test_a_fast_runtime_gets_the_ceiling_and_a_slow_one_the_floor(self):
        self.assertEqual(driver.plan_reps(1), driver.RUN_MAX_REPS)
        self.assertEqual(driver.plan_reps(driver.RUN_SLOW_MS - 1), driver.RUN_MIN_REPS)

    def test_a_very_slow_runtime_is_sampled_twice_and_no_more(self):
        self.assertEqual(driver.plan_reps(driver.RUN_SLOW_MS), 2)
        self.assertEqual(driver.plan_reps(driver.RUN_SLOW_MS * 4), 2)

    def test_the_count_never_rises_with_the_duration(self):
        counts = [driver.plan_reps(d) for d in (1, 10, 100, 1000, 5000, 19000)]
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


class EditLoopTests(unittest.TestCase):
    def test_format_mirror_preserves_configuration_and_maintenance_inputs(self):
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
        with mock.patch.object(toolchains.subprocess, "run"):
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
