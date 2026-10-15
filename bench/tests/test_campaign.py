"""Exercise campaign process lifetimes without compiling the compiler or measuring tasks."""
import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import campaign


@unittest.skipUnless(sys.platform == "win32", "running executable locks are a Windows contract")
class CampaignProcessTests(unittest.TestCase):
    def test_campaign_uses_the_live_launcher_without_building_a_temporary_binary(self):
        with tempfile.TemporaryDirectory(prefix="swc campaign process ") as directory:
            scratch = Path(directory)
            root = scratch / "checkout"
            binary = root / "bin" / "swc.exe"
            runtime = binary.parent / "runtime"
            runtime.mkdir(parents=True)
            (runtime / "api.swg").write_text("runtime from this checkout", encoding="utf-8")
            shutil.copy2(sys.executable, binary)
            original = binary.read_bytes()

            bench = root / "bench"
            bench.mkdir()
            (bench / "driver.py").write_text(textwrap.dedent("""
                import json, os, subprocess, sys
                from pathlib import Path
                swc = Path(sys.argv[sys.argv.index("--swc") + 1])
                child = subprocess.run([str(swc), "-S", "-c", "print('fresh compiler')"],
                                       capture_output=True, text=True, check=True)
                Path("driver.json").write_text(json.dumps({
                    "swc": str(swc), "resource_root": os.environ["SWAG_PATH"],
                    "runtime": (swc.parent / "runtime" / "api.swg").read_text(),
                    "output": child.stdout.strip(), "args": sys.argv[1:]}))
                if os.environ.get("CAMPAIGN_TEST_FAILURE") == "driver":
                    sys.exit(9)
                """), encoding="utf-8")

            env = {"PYTHONHOME": sys.base_prefix,
                   "PATH": os.path.dirname(sys.executable) + os.pathsep + os.environ.get("PATH", "")}
            with (
                mock.patch.dict(os.environ, env),
                mock.patch.object(campaign, "ROOT", str(root)),
                mock.patch.object(campaign.tc, "BENCH", str(bench)),
                mock.patch.object(campaign, "build", return_value=str(binary)) as build,
                mock.patch.object(sys, "argv", ["campaign.py", "--quick", "--swc-cores", "6"]),
            ):
                launcher = subprocess.Popen(
                    [str(binary), "-S", "-c", "import sys; print('ready', flush=True); sys.stdin.readline()"],
                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                try:
                    self.assertEqual(launcher.stdout.readline().strip(), "ready")
                    with self.assertRaises(PermissionError):
                        with binary.open("ab"):
                            pass
                    for failure in ("", "driver"):
                        with self.subTest(failure=failure or "success"):
                            os.environ["CAMPAIGN_TEST_FAILURE"] = failure
                            (bench / "driver.json").unlink(missing_ok=True)
                            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                                if failure:
                                    with self.assertRaisesRegex(SystemExit, "driver.py failed"):
                                        campaign.main()
                                else:
                                    self.assertEqual(campaign.main(), 0)
                            self.assertIsNone(launcher.poll())
                            self.assertEqual(binary.read_bytes(), original)
                            measured_path = bench / "driver.json"
                            if failure == "driver":
                                self.assertTrue(measured_path.exists())
                                continue
                            measured = json.loads(measured_path.read_text())
                            self.assertEqual(Path(measured["swc"]), binary)
                            self.assertEqual(measured["runtime"], "runtime from this checkout")
                            self.assertEqual(Path(measured["resource_root"]), root / "bin")
                            self.assertEqual(measured["output"], "fresh compiler")
                            self.assertIn("--swc-cores", measured["args"])
                    self.assertEqual(build.call_count, 2)
                finally:
                    launcher.stdin.close()
                    try:
                        launcher.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        launcher.kill()
                        launcher.wait()
                    launcher.stdout.close()


if __name__ == "__main__":
    unittest.main()
